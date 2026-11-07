// l10n:ignore-file — PocketForge's independent product/runtime boundary.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fa/sandbox/memory_shell.dart';
import 'package:flutter_agent_harness/flutter_agent_harness.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'pocketforge_store_stub.dart'
    if (dart.library.io) 'pocketforge_store_io.dart'
    as native;

/// The project and its shell have their own root. Session/checkpoint metadata
/// stays in the separate [storage] namespace, outside the shell's preopen.
final class PocketForgeStore {
  PocketForgeStore._(
    this.storage,
    this.backend,
    this.projectStoragePath,
    this.statePath,
    this.runtimeLabel,
    this._mirror,
  );

  static const maxFileBytes = 512 * 1024;
  static const maxProjectBytes = 20 * 1024 * 1024;
  static const maxFiles = 500;
  final ExecutionEnv storage;
  final ExecutionEnv backend;
  final String projectStoragePath;
  final String statePath;
  final String runtimeLabel;
  final bool _mirror;
  String Function(String) redactText = (text) => text;
  bool get isWasi => !_mirror;
  late final PocketForgeProjectEnv env = PocketForgeProjectEnv(this);
  Future<void> _tail = Future.value();
  int _sequence = 0;
  void Function()? _closeShell;

  void dispose() {
    _closeShell?.call();
    _closeShell = null;
  }

  static Future<PocketForgeStore> create(
    ExecutionEnv storage, {
    bool useNativeRuntime = true,
  }) async {
    final projectPath = (await storage.absolutePath(
      'pocketforge-project',
    )).getOrThrow();
    final statePath = (await storage.absolutePath(
      'pocketforge-state',
    )).getOrThrow();
    (await storage.createDir(projectPath)).getOrThrow();
    (await storage.createDir(statePath)).getOrThrow();
    final nativeBackend = useNativeRuntime
        ? await native.createProjectBackend(projectPath)
        : null;
    if (nativeBackend != null) {
      final result = PocketForgeStore._(
        storage,
        nativeBackend,
        projectPath,
        statePath,
        'On-device WASI sandbox · local project',
        false,
      );
      result._closeShell = () => native.disposeProjectBackend(nativeBackend);
      return result;
    }
    final client = http.Client();
    final shell = MemoryShell(httpClient: client);
    final memory = MemoryExecutionEnv(cwd: '/', shell: shell);
    shell.attach(memory);
    final result = PocketForgeStore._(
      storage,
      memory,
      projectPath,
      statePath,
      'Portable sandbox · local project',
      true,
    );
    result._closeShell = client.close;
    for (final path in await result._scan(storage, projectPath)) {
      final data = (await storage.readBinaryFile(
        p.posix.join(projectPath, path),
      )).getOrThrow();
      (await memory.writeBinaryFile('/$path', data)).getOrThrow();
    }
    return result;
  }

  String get sessionsPath => p.posix.join(statePath, 'sessions');

  Future<T> mutate<T>(Future<T> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<List<String>> files() => _scan(backend, backend.cwd);

  Future<List<String>> _scan(ExecutionEnv fs, String root) async {
    final result = <String>[];
    var bytes = 0;
    Future<void> visit(String directory, String relative, int depth) async {
      if (depth > 24) {
        throw StateError('Project nesting exceeds 24 directories.');
      }
      final entries = (await fs.listDir(directory)).getOrThrow();
      for (final entry in entries) {
        if (entry.name == '.' || entry.name == '..') continue;
        final path = relative.isEmpty ? entry.name : '$relative/${entry.name}';
        if (entry.kind == FileKind.symlink) {
          throw StateError('Project symbolic links are not supported: $path');
        }
        final addressed = p.posix.join(directory, entry.name);
        if (entry.kind == FileKind.directory) {
          await visit(addressed, path, depth + 1);
        } else {
          if (entry.size > maxFileBytes || entry.size < 0) {
            throw StateError('$path exceeds the 512 KiB file limit.');
          }
          bytes += entry.size;
          result.add(path);
          if (result.length > maxFiles || bytes > maxProjectBytes) {
            throw StateError(
              'Project limit: 500 files / 20 MiB. Restore a checkpoint to recover.',
            );
          }
        }
      }
    }

    await visit(root, '', 0);
    return result..sort();
  }

  Future<void> flush() async {
    final paths = await files();
    if (!_mirror) return;
    final current = await _scan(storage, projectStoragePath);
    for (final path in current.where((path) => !paths.contains(path))) {
      (await storage.remove(
        p.posix.join(projectStoragePath, path),
        force: true,
      )).getOrThrow();
    }
    for (final path in paths) {
      final data = (await backend.readBinaryFile(
        p.posix.join(backend.cwd, path),
      )).getOrThrow();
      (await storage.writeBinaryFile(
        p.posix.join(projectStoragePath, path),
        data,
      )).getOrThrow();
    }
  }

  Future<String> checkpoint() async {
    final paths = await files();
    final content = <String, String>{};
    for (final path in paths) {
      content[path] = base64Encode(
        (await backend.readBinaryFile(
          p.posix.join(backend.cwd, path),
        )).getOrThrow(),
      );
    }
    final id = '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
    (await storage.writeFile(
      '$statePath/checkpoints/$id.json',
      jsonEncode({'version': 1, 'files': content}),
    )).getOrThrow();
    final all = await checkpoints();
    for (final old in all.skip(8)) {
      (await storage.remove(
        '$statePath/checkpoints/$old.json',
        force: true,
      )).getOrThrow();
    }
    return id;
  }

  Future<List<String>> checkpoints() async {
    (await storage.createDir('$statePath/checkpoints')).getOrThrow();
    final entries = (await storage.listDir(
      '$statePath/checkpoints',
    )).getOrThrow();
    return entries
        .where(
          (item) => item.kind == FileKind.file && item.name.endsWith('.json'),
        )
        .map((item) => item.name.substring(0, item.name.length - 5))
        .toList()
      ..sort((a, b) => b.compareTo(a));
  }

  Future<void> restore(String id) => mutate(() async {
    if (!(await checkpoints()).contains(id)) {
      throw StateError('Checkpoint not found.');
    }
    // Read the selected version before making a safety copy, which can prune it.
    final selected = (await storage.readTextFile(
      '$statePath/checkpoints/$id.json',
    )).getOrThrow();
    final parsed = jsonDecode(selected) as Map<String, dynamic>;
    final saved = (parsed['files'] as Map<String, dynamic>).map((key, value) {
      PocketForgeProjectEnv.relative(key);
      return MapEntry(key, base64Decode(value as String));
    });
    if (saved.length > maxFiles ||
        saved.values.any((bytes) => bytes.length > maxFileBytes) ||
        saved.values.fold<int>(0, (total, bytes) => total + bytes.length) >
            maxProjectBytes) {
      throw StateError('Checkpoint exceeds workspace limits.');
    }
    final before = await checkpoint();
    try {
      await _replaceContents(saved);
    } on Object {
      final backup =
          jsonDecode(
                (await storage.readTextFile(
                  '$statePath/checkpoints/$before.json',
                )).getOrThrow(),
              )
              as Map<String, dynamic>;
      await _replaceContents(
        (backup['files'] as Map<String, dynamic>).map(
          (key, value) => MapEntry(key, base64Decode(value as String)),
        ),
      );
      rethrow;
    }
  });

  Future<void> _replaceContents(Map<String, Uint8List> saved) async {
    // Clear immediate children, including any invalid oversized output or
    // symlinks a shell invocation created. Never traverse links to recover.
    final children = (await backend.listDir(backend.cwd)).getOrThrow();
    for (final child in children) {
      if (child.name == '.' || child.name == '..') continue;
      if (child.name.contains('/') || child.name.contains('\\')) {
        throw StateError('Invalid project directory entry.');
      }
      (await backend.remove(
        p.posix.join(backend.cwd, child.name),
        recursive: true,
        force: true,
      )).getOrThrow();
    }
    for (final entry in saved.entries) {
      (await backend.writeBinaryFile(
        p.posix.join(backend.cwd, entry.key),
        entry.value,
      )).getOrThrow();
    }
    await flush();
  }

  Future<void> rollback(String id) async {
    final backup =
        jsonDecode(
              (await storage.readTextFile(
                '$statePath/checkpoints/$id.json',
              )).getOrThrow(),
            )
            as Map<String, dynamic>;
    await _replaceContents(
      (backup['files'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, base64Decode(value as String)),
      ),
    );
  }

  Future<Map<String, dynamic>> readSettings() async {
    final result = await storage.readTextFile('$statePath/settings.json');
    if (result.isErr) return {};
    try {
      return jsonDecode(result.getOrThrow()) as Map<String, dynamic>;
    } on Object {
      throw StateError('Saved workspace settings could not be read.');
    }
  }

  Future<void> writeSettings(Map<String, dynamic> settings) async {
    (await storage.writeFile(
      '$statePath/settings.json',
      jsonEncode(settings),
    )).getOrThrow();
  }
}

/// Virtual-root tool filesystem and bounded shell. Only the provider adapter
/// receives the model key; this env has no credential variables.
final class PocketForgeProjectEnv extends ForwardingFs {
  PocketForgeProjectEnv(this.store) : super(store.backend);
  final PocketForgeStore store;
  @override
  String get cwd => '/';

  static String relative(String path) {
    if (path.contains('\\') ||
        path.contains(':') ||
        path.contains('\u0000') ||
        path.length > 600) {
      throw const FileError(
        FileErrorCode.invalid,
        'Use a relative project path.',
      );
    }
    final parts = path
        .split('/')
        .where((part) => part.isNotEmpty && part != '.')
        .toList();
    if (parts.any(
      (part) => part == '..' || part.codeUnits.any((code) => code < 32),
    )) {
      throw const FileError(
        FileErrorCode.permissionDenied,
        'The path leaves this project.',
      );
    }
    return parts.join('/');
  }

  String _backendPath(String path) =>
      p.posix.join(delegate.cwd, relative(path));

  Future<void> _validate(String path) async {
    if (store.redactText(path) != path) {
      throw const FileError(
        FileErrorCode.permissionDenied,
        'A provider credential cannot be used as a project path.',
      );
    }
    final parts = relative(path).split('/').where((part) => part.isNotEmpty);
    var cursor = delegate.cwd;
    for (final part in parts) {
      cursor = p.posix.join(cursor, part);
      final info = await delegate.fileInfo(cursor);
      if (info.valueOrNull?.kind == FileKind.symlink) {
        throw FileError(
          FileErrorCode.permissionDenied,
          'Symbolic links are not supported.',
          path: path,
        );
      }
    }
  }

  Future<Result<T, FileError>> _guard<T>(
    String path,
    Future<Result<T, FileError>> Function(String) operation,
  ) async {
    try {
      await _validate(path);
      return await operation(_backendPath(path));
    } on FileError catch (error) {
      return Err(error);
    } on Object catch (error) {
      return Err(FileError(FileErrorCode.unknown, '$error'));
    }
  }

  @override
  Future<Result<String, FileError>> absolutePath(String path) async {
    try {
      return Ok('/${relative(path)}');
    } on FileError catch (error) {
      return Err(error);
    }
  }

  @override
  Future<Result<String, FileError>> joinPath(List<String> parts) =>
      absolutePath(parts.join('/'));
  @override
  Future<Result<bool, FileError>> exists(String path) =>
      _guard(path, delegate.exists);
  @override
  Future<Result<String, FileError>> readTextFile(String path) =>
      _guard(path, (address) async {
        final info = await delegate.fileInfo(address);
        if ((info.valueOrNull?.size ?? 0) > PocketForgeStore.maxFileBytes) {
          return const Err(
            FileError(FileErrorCode.invalid, 'File exceeds 512 KiB.'),
          );
        }
        return delegate.readTextFile(address);
      });
  @override
  Future<Result<Uint8List, FileError>> readBinaryFile(String path) =>
      _guard(path, (address) async {
        final info = await delegate.fileInfo(address);
        if ((info.valueOrNull?.size ?? 0) > PocketForgeStore.maxFileBytes) {
          return const Err(
            FileError(FileErrorCode.invalid, 'File exceeds 512 KiB.'),
          );
        }
        return delegate.readBinaryFile(address);
      });
  @override
  Future<Result<List<String>, FileError>> readTextLines(
    String path, {
    int? maxLines,
  }) async {
    final result = await readTextFile(path);
    return switch (result) {
      Ok(:final value) => Ok(
        const LineSplitter().convert(value).take(maxLines ?? 100000).toList(),
      ),
      Err(:final error) => Err(error),
    };
  }

  @override
  Future<Result<FileInfo, FileError>> fileInfo(String path) =>
      _guard(path, (address) async {
        final result = await delegate.fileInfo(address);
        return switch (result) {
          Ok(:final value) => Ok(
            FileInfo(
              name: value.name,
              path: '/${relative(path)}',
              kind: value.kind,
              size: value.size,
              mtimeMs: value.mtimeMs,
            ),
          ),
          Err(:final error) => Err(error),
        };
      });
  @override
  Future<Result<List<FileInfo>, FileError>> listDir(
    String path,
  ) => _guard(path, (address) async {
    final result = await delegate.listDir(address);
    return switch (result) {
      Ok(:final value) => Ok(
        value
            .map(
              (item) => FileInfo(
                name: item.name,
                path:
                    '/${[relative(path), item.name].where((part) => part.isNotEmpty).join('/')}',
                kind: item.kind,
                size: item.size,
                mtimeMs: item.mtimeMs,
              ),
            )
            .toList(),
      ),
      Err(:final error) => Err(error),
    };
  });

  Future<Result<void, FileError>> _write(
    String path,
    Uint8List bytes,
  ) => store.mutate(() async {
    try {
      await _validate(path);
      if (relative(path).isEmpty ||
          bytes.length > PocketForgeStore.maxFileBytes) {
        throw const FileError(
          FileErrorCode.invalid,
          'File exceeds 512 KiB or has no name.',
        );
      }
      final paths = await store.files();
      if (!paths.contains(relative(path)) &&
          paths.length >= PocketForgeStore.maxFiles) {
        throw const FileError(
          FileErrorCode.invalid,
          'Project already contains 500 files.',
        );
      }
      var total = bytes.length;
      for (final existing in paths.where((item) => item != relative(path))) {
        total += (await delegate.fileInfo(
          _backendPath(existing),
        )).getOrThrow().size;
      }
      if (total > PocketForgeStore.maxProjectBytes) {
        throw StateError('Project exceeds 20 MiB.');
      }
      await store.checkpoint();
      final result = await delegate.writeBinaryFile(_backendPath(path), bytes);
      if (result.isOk) await store.flush();
      return result;
    } on FileError catch (error) {
      return Err(error);
    } on Object catch (error) {
      return Err(FileError(FileErrorCode.unknown, '$error'));
    }
  });
  @override
  Future<Result<void, FileError>> writeFile(String path, String content) =>
      _write(path, Uint8List.fromList(utf8.encode(store.redactText(content))));
  @override
  Future<Result<void, FileError>> writeBinaryFile(
    String path,
    Uint8List content,
  ) => _write(path, content);
  @override
  Future<Result<void, FileError>> appendFile(
    String path,
    String content,
  ) async {
    final previous = await readTextFile(path);
    if (previous.isErr &&
        previous.errorOrNull?.code != FileErrorCode.notFound) {
      return Err(previous.errorOrNull!);
    }
    return writeFile(path, '${previous.valueOrNull ?? ''}$content');
  }

  @override
  Future<Result<void, FileError>> createDir(
    String path, {
    bool recursive = true,
  }) => _guard(
    path,
    (address) => delegate.createDir(address, recursive: recursive),
  );
  @override
  Future<Result<void, FileError>> remove(
    String path, {
    bool recursive = false,
    bool force = false,
  }) => store.mutate(() async {
    try {
      if (relative(path).isEmpty) {
        throw const FileError(
          FileErrorCode.permissionDenied,
          'Cannot remove the project root.',
        );
      }
      await _validate(path);
      await store.checkpoint();
      final result = await delegate.remove(
        _backendPath(path),
        recursive: recursive,
        force: force,
      );
      if (result.isOk) await store.flush();
      return result;
    } on FileError catch (error) {
      return Err(error);
    } on Object catch (error) {
      return Err(FileError(FileErrorCode.unknown, '$error'));
    }
  });

  @override
  Future<Result<ShellExecResult, ExecutionError>> exec(
    String command, {
    ShellExecOptions? options,
  }) => store.mutate(() async {
    try {
      options?.cancelToken?.throwIfCancelled();
      if (store.redactText(command) != command) {
        throw StateError(
          'A provider credential cannot be passed to the shell.',
        );
      }
      final normalizedCommand = command.replaceAll("'", '').replaceAll('"', '');
      if (RegExp(
        r'(^|[\s;&|()])(?:python(?:3(?:\.14)?)?|pip3?|node|npm|npx|gcc|clang|swift|xcodebuild)(?=$|[\s;&|()])',
        caseSensitive: false,
      ).hasMatch(normalizedCommand)) {
        return const Err(
          ExecutionError(
            ExecutionErrorCode.shellUnavailable,
            'This game milestone supports project utilities and browser JavaScript. Python/package installation and native compilers are unavailable.',
          ),
        );
      }
      if (command.length > 32000) {
        throw StateError('Shell command exceeds 32 KiB.');
      }
      final before = await store.checkpoint();
      final result = await delegate.exec(
        command,
        options: ShellExecOptions(
          cwd: '/',
          env: options?.env,
          cancelToken: options?.cancelToken,
          timeout: options?.timeout ?? const Duration(minutes: 2),
          onStdout: options?.onStdout,
          onStderr: options?.onStderr,
          stdinData: options?.stdinData,
        ),
      );
      try {
        await store.flush();
      } on Object {
        await store.rollback(before);
        rethrow;
      }
      return result;
    } on Object catch (error) {
      return Err(ExecutionError(ExecutionErrorCode.unknown, '$error'));
    }
  });
}
