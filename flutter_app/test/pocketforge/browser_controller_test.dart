import 'dart:async';
import 'dart:typed_data';

import 'package:fa/pocketforge/browser/game_preview_backend.dart';
import 'package:fa/pocketforge/browser/game_preview_controller.dart';
import 'package:fa/pocketforge/browser/game_tools.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_agent_harness/flutter_agent_harness.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeGameBackend extends GamePreviewBackend {
  bool canceled = false;
  Completer<Object?>? pending;
  @override
  bool get attached => true;
  @override
  bool get isLoading => false;
  @override
  String get status => 'Fake preview ready';
  @override
  Future<void> load(String html) async {
    canceled = false;
  }

  @override
  Future<Object?> invoke(String method, Map<String, Object?> payload) async {
    if (pending != null) return pending!.future;
    return switch (method) {
      'read' => {
        'title': 'Test game',
        'console': ['ready'],
      },
      'test' => {
        'passed': false,
        'checks': [
          {'passed': true, 'message': 'score increases'},
          {'passed': false, 'message': 'restart resets'},
        ],
      },
      _ => {'result': method},
    };
  }

  @override
  Future<Uint8List> screenshot() async => Uint8List.fromList([1, 2, 3]);
  @override
  void cancel() {
    canceled = true;
    if (pending != null && !pending!.isCompleted) {
      pending!.completeError(StateError('canceled'));
    }
  }

  @override
  Widget buildView() => const SizedBox.expand();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryExecutionEnv env;
  late FakeGameBackend backend;
  late GamePreviewController controller;
  setUp(() async {
    env = MemoryExecutionEnv(cwd: '/workspace');
    (await env.createDir('/workspace')).getOrThrow();
    (await env.writeFile(
      '/workspace/index.html',
      '<html><head></head><body>Game</body></html>',
    )).getOrThrow();
    backend = FakeGameBackend();
    controller = GamePreviewController(
      env: env,
      projectRoot: '/workspace',
      backend: backend,
    );
  });
  tearDown(() => controller.dispose());

  test(
    'preview reads actual backend, publishes logs and failed test checks',
    () async {
      var focusRequests = 0;
      controller.onFocusRequest = () => focusRequests++;
      final read = await controller.preview();
      expect(read, contains('Test game'));
      expect(controller.path, 'index.html');
      expect(controller.consoleLines, ['ready']);
      final report = await controller.test('assert(true,"score");');
      expect(report.passed, isFalse);
      expect(report.checks.length, 2);
      expect(report.checks.last.message, 'restart resets');
      expect(controller.status, contains('FAIL'));
      expect(await controller.screenshot(), [1, 2, 3]);
      expect(controller.lastScreenshot, [1, 2, 3]);
      expect(focusRequests, 2);
    },
  );

  test(
    'cancel rejects an unresolved game promise and invalidates preview',
    () async {
      await controller.preview();
      backend.pending = Completer<Object?>();
      final result = controller.evaluate('new Promise(()=>{})');
      final rejected = expectLater(result, throwsStateError);
      controller.cancel();
      await rejected;
      expect(backend.canceled, isTrue);
      expect(controller.path, isEmpty);
      await expectLater(controller.evaluate('1'), throwsStateError);
    },
  );

  test(
    'tool call cancellation aborts backend and never returns success',
    () async {
      await controller.preview();
      backend.pending = Completer<Object?>();
      final cancel = CancelTokenSource();
      final tool = pocketGameTools(
        controller,
      ).firstWhere((tool) => tool.name == 'game_eval');
      final result = tool.execute({'code': '1'}, cancel.token, null);
      final rejected = expectLater(result, throwsA(anything));
      cancel.cancel();
      await rejected;
      expect(backend.canceled, isTrue);
    },
  );

  test(
    'a cancellation gate releases pending work and supports a new generation',
    () async {
      final gate = GameOperationGate();
      final pending = gate.run(Completer<int>().future);
      final rejected = expectLater(pending, throwsStateError);
      gate.cancel();
      await rejected;
      expect(await gate.run(Future.value(3)), 3);
      gate.dispose();
      await expectLater(gate.run(Future.value(4)), throwsStateError);
    },
  );
}
