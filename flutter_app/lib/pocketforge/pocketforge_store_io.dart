import 'dart:io';

import 'package:fa/sandbox/env_factory_io.dart' as platform;
import 'package:fa/sandbox/wasm_shell.dart';
import 'package:flutter_agent_harness/flutter_agent_harness.dart';
import 'package:flutter_agent_harness/io.dart';
import 'package:http/http.dart' as http;

final _cleanup = Expando<void Function()>();

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
      LocalExecutionEnv(cwd: projectPath, shell: shell),
      projectPath,
    );
    _cleanup[env] = client.close;
    return env;
  } on Object {
    client.close();
    return null;
  }
}
