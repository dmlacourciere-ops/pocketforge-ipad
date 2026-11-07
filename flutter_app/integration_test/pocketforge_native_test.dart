// Run in a disposable ARM64 iPad simulator app container:
// flutter test integration_test/pocketforge_native_test.dart -d <simulator-id>
// This is a native boundary test: no fake filesystem, shell, WebView, provider,
// or app UI. It never sends a model prompt or uses an API credential.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fa/main_pocketforge.dart' as app;
import 'package:fa/pocketforge/pocketforge_session.dart';
import 'package:fa/pocketforge/ui/pocketforge_workbench.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _collisionChecks = '''
assert(typeof window.__gameTest === 'object', 'Production game test hooks loaded');
window.__gameTest.reset();
document.querySelector('#start').click();
window.__gameTest.addObstacle(0, .92);
window.__gameTest.advance(1 / 60);
const state = window.__gameTest.snapshot();
assert(state.shield === 2, 'A collision consumes exactly one shield');
assert(state.running === true, 'A single collision leaves the game playable');
assert(document.querySelector('#race').width > 0, 'The real game canvas has a drawable size');
''';

/// Platform views and startup futures need real asynchronous time plus Flutter
/// frames. Keep pumping while waiting, with an independent wall-clock bound.
Future<T> _native<T>(WidgetTester tester, Future<T> Function() action) async {
  final operation = action();
  var complete = false;
  unawaited(
    operation.then<void>(
      (_) => complete = true,
      onError: (Object _, StackTrace _) {
        complete = true;
      },
    ),
  );
  final clock = Stopwatch()..start();
  while (!complete) {
    if (clock.elapsed > const Duration(seconds: 90)) {
      throw TimeoutException(
        'The native operation did not finish within 90 seconds.',
      );
    }
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  return operation;
}

Future<PocketForgeSession> _boot(WidgetTester tester) async {
  app.main();
  final clock = Stopwatch()..start();
  while (find.byType(PocketForgeWorkbench).evaluate().isEmpty) {
    if (clock.elapsed > const Duration(seconds: 120)) {
      throw TimeoutException(
        'The production PocketForge workspace did not open.',
      );
    }
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return tester
          .widget<PocketForgeWorkbench>(find.byType(PocketForgeWorkbench))
          .session
      as PocketForgeSession;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'iPad runs WASI, detects and repairs a real WebKit game failure',
    (tester) async {
      await tester.runAsync(() async {
        final session = await _boot(tester);
        PocketForgeSession? reopened;
        final original = <String, String?>{};
        const proofPath = '.pocketforge-native-smoke.txt';
        try {
          expect(
            session.runtimeLabel,
            contains('WASI'),
            reason:
                'A portable fallback must not pass the native interpreter test.',
          );
          expect(
            session.secureKeyStorage,
            isTrue,
            reason: 'The production iOS Keychain channel must be registered.',
          );
          expect(
            find.byType(InAppWebView),
            findsOneWidget,
            reason:
                'The actual native browser must be mounted by the product UI.',
          );

          for (final asset in const {
            'index.html': 'starter-index.html',
            'style.css': 'starter-style.css',
            'game.js': 'starter-game.js',
          }.entries) {
            original[asset.key] = session.files.contains(asset.key)
                ? await session.readFile(asset.key)
                : null;
            await session.writeFile(
              asset.key,
              await rootBundle.loadString('assets/pocketforge/${asset.value}'),
            );
            expect(session.error, isNull);
          }
          final source = await session.readFile('game.js');
          expect('this.shield -= 1;'.allMatches(source), hasLength(1));

          final shell = (await session.env.exec('rg --version')).getOrThrow();
          expect(shell.exitCode, 0, reason: shell.stderr);
          expect(
            shell.stdout.toLowerCase(),
            contains('ripgrep'),
            reason: 'This must execute the bundled rg.wasm through Wasmi/WASI.',
          );

          await _native(tester, () => session.game.preview());
          expect(session.game.status, contains('WebKit'));
          final baseline = await _native(
            tester,
            () => session.game.test(_collisionChecks),
          );
          expect(baseline.passed, isTrue, reason: baseline.toJson().toString());

          // Introduce a real source regression, reload the browser and require
          // the real page's assertion to detect the broken collision behavior.
          await session.writeFile(
            'game.js',
            source.replaceFirst('this.shield -= 1;', 'this.shield -= 0;'),
          );
          expect(session.error, isNull);
          await _native(tester, () => session.game.preview());
          final broken = await _native(
            tester,
            () => session.game.test(_collisionChecks),
          );
          expect(broken.passed, isFalse);
          expect(
            broken.checks.any(
              (check) =>
                  !check.passed &&
                  check.message == 'A collision consumes exactly one shield',
            ),
            isTrue,
          );

          await session.writeFile('game.js', source);
          expect(session.error, isNull);
          await _native(tester, () => session.game.preview());
          final repaired = await _native(
            tester,
            () => session.game.test(_collisionChecks),
          );
          expect(repaired.passed, isTrue, reason: repaired.toJson().toString());
          expect(repaired.checks.length, greaterThanOrEqualTo(4));

          // A page promise that never resolves must cancel promptly through the
          // real native gate, then the visible WebKit instance must reload.
          final pending = session.game.test(
            'await new Promise(() => {}); assert(true, "unreachable");',
          );
          final canceled = expectLater(
            pending,
            throwsA(
              isA<StateError>().having(
                (error) => '$error',
                'message',
                contains('canceled'),
              ),
            ),
          );
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 100));
          session.stop();
          await _native(tester, () => canceled);
          await _native(tester, () => session.game.preview());
          final afterStop = await _native(
            tester,
            () => session.game.test(_collisionChecks),
          );
          expect(
            afterStop.passed,
            isTrue,
            reason: afterStop.toJson().toString(),
          );

          final png = await _native(tester, session.game.screenshot);
          expect(png.length, greaterThan(1000));
          expect(png.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
          final codec = await ui.instantiateImageCodec(png);
          final image = (await codec.getNextFrame()).image;
          expect(image.width, greaterThan(100));
          expect(image.height, greaterThan(100));
          image.dispose();
          codec.dispose();
          (await session.store.storage.writeBinaryFile(
            '${session.store.statePath}/native-smoke-preview.png',
            png,
          )).getOrThrow();

          await session.writeFile(
            proofPath,
            'Native project survives session recreation.',
          );
          expect(session.error, isNull);
          await session.createCheckpoint();
          final checkpoint = session.checkpoints.first;
          // Unmount the actual app (disposing its session), then open a fresh
          // production session against the device's persistent sandbox.
          await tester.pumpWidget(const SizedBox.shrink());
          reopened = await PocketForgeSession.create();
          expect(reopened.runtimeLabel, contains('WASI'));
          expect(
            await reopened.readFile(proofPath),
            'Native project survives session recreation.',
          );
          expect(reopened.checkpoints, contains(checkpoint));
          expect(
            (await reopened.env.readTextFile(
              '/pocketforge-state/settings.json',
            )).isErr,
            isTrue,
          );

          binding.reportData = {
            'runtime': reopened.runtimeLabel,
            'wasiCommand': shell.stdout.trim(),
            'baselinePassed': baseline.passed,
            'injectedBugDetected': !broken.passed,
            'repairedPassed': repaired.passed,
            'checks': repaired.checks.map((check) => check.toJson()).toList(),
            'webKitPngBytes': png.length,
            'deviceStorageReopened': true,
            'nativeKeychainAvailable': reopened.secureKeyStorage,
            'pendingBrowserCanceledAndReloaded': afterStop.passed,
            'modelRequests': 0,
          };
          (await reopened.store.storage.writeFile(
            '${reopened.store.statePath}/native-smoke-report.json',
            jsonEncode(binding.reportData),
          )).getOrThrow();
        } finally {
          final cleanup = reopened ?? session;
          for (final entry in original.entries) {
            if (entry.value == null) {
              (await cleanup.env.remove(entry.key, force: true)).getOrThrow();
            } else {
              (await cleanup.env.writeFile(
                entry.key,
                entry.value!,
              )).getOrThrow();
            }
          }
          (await cleanup.env.remove(proofPath, force: true)).getOrThrow();
          reopened?.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
        }
      });
    },
    skip: !Platform.isIOS,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
