import 'dart:io';

import 'package:fa/sandbox/env_factory_io.dart' as platform;
import 'package:fa/sandbox/wasm_shell.dart';
import 'package:flutter_agent_harness/flutter_agent_harness.dart';
import 'package:flutter_agent_harness/io.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

final _cleanup = Expando<void Function()>();

/// Storage is independent of the optional interpreter. Native app projects
/// must survive a process restart even when WASI cannot initialize.
Future<ExecutionEnv?> createNativeStorage({String? directoryPath}) async {
  if (directoryPath == null && !Platform.isIOS && !Platform.isAndroid) {
    return null;
  }
  final root =
      directoryPath ??
      '${(await getApplicationDocumentsDirectory()).path}/fah_sandbox';
  await Directory(root).create(recursive: true);
  return _NativeProjectFiles(cwd: root, shell: const _MetadataOnlyShell());
}

/// Fa's generic local filesystem follows links while statting files. The
/// product's containment checks need the link itself, including broken links.
/// Normalize entry names too: native Windows paths contain backslashes.
final class _NativeProjectFiles extends ForwardingFs {
  _NativeProjectFiles({required String cwd, required Shell shell})
    : super(LocalExecutionEnv(cwd: cwd, shell: shell));

  @override
  Future<Result<FileInfo, FileError>> fileInfo(String path) async {
    try {
      final absolute = (await delegate.absolutePath(path)).getOrThrow();
      final name = absolute.replaceAll('\\', '/').split('/').last;
      final kind = await FileSystemEntity.type(absolute, followLinks: false);
      if (kind == FileSystemEntityType.link) {
        return Ok(
          FileInfo(
            name: name,
            path: absolute,
            kind: FileKind.symlink,
            size: 0,
            mtimeMs: 0,
          ),
        );
      }
      final info = await delegate.fileInfo(path);
      return switch (info) {
        Ok(:final value) => Ok(
          FileInfo(
            name: name,
            path: value.path,
            kind: value.kind,
            size: value.size,
            mtimeMs: value.mtimeMs,
          ),
        ),
        Err(:final error) => Err(error),
      };
    } on FileError catch (error) {
      return Err(error);
    } on Object catch (error) {
      return Err(FileError(FileErrorCode.unknown, '$error', path: path));
    }
  }

  @override
  Future<Result<List<FileInfo>, FileError>> listDir(String path) async {
    try {
      final absolute = (await delegate.absolutePath(path)).getOrThrow();
      final entries = <FileInfo>[];
      await for (final entity in Directory(absolute).list(followLinks: false)) {
        entries.add((await fileInfo(entity.path)).getOrThrow());
      }
      entries.sort((first, second) => first.name.compareTo(second.name));
      return Ok(entries);
    } on FileError catch (error) {
      return Err(error);
    } on Object catch (error) {
      return Err(FileError(FileErrorCode.unknown, '$error', path: path));
    }
  }
}

/// Raw storage is never an agent tool surface or an OS process launcher.
final class _MetadataOnlyShell implements Shell {
  const _MetadataOnlyShell();
  @override
  Future<Result<ShellExecResult, ExecutionError>> exec(
    String command, {
    ShellExecOptions? options,
  }) async => const Err(
    ExecutionError(
      ExecutionErrorCode.shellUnavailable,
      'Metadata storage does not expose a process shell.',
    ),
  );
}

void disposeProjectBackend(ExecutionEnv env) {
  _cleanup[env]?.call();
  _cleanup[env] = null;
}

Future<ExecutionEnv?> createProjectBackend(String projectPath) async {
  // Only a real app sandbox path can be preopened. Tests and browser-origin
  // filesystems use the isolated portable environment instead.
  if (!Directory(projectPath).existsSync()) return null;
  final client = http.Client();
  try {
    final shell = await WasiSandboxShell.load(
      workingDirectory: '/',
      sandboxHostPath: projectPath,
      httpClient: client,
    );
    final env = platform.SandboxedExecutionEnv(
      _NativeProjectFiles(cwd: projectPath, shell: shell),
      projectPath,
    );
    _cleanup[env] = client.close;
    return env;
  } on Object {
    client.close();
    return null;
  }
}
