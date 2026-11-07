import 'package:fa/pocketforge/pocketforge_model.dart';
import 'package:fa/pocketforge/ui/pocketforge_settings.dart';
import 'package:fa/pocketforge/ui/pocketforge_theme.dart';
import 'package:fa/pocketforge/ui/pocketforge_workbench.dart';
import 'package:fa_ui/fa_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../golden/golden_test_helper.dart';
import 'fake_pocketforge_model.dart';

Future<void> _pump(WidgetTester tester, FakePocketForgeModel session) =>
    pumpGolden(
      tester,
      PocketForgeWorkbench(
        session: session,
        previewBuilder: (_) =>
            const Center(child: Text('Test preview surface')),
      ),
      size: const Size(744, 1133),
      theme: buildFahTheme(uiTheme: pocketForgeUiTheme),
      wrap: (child) =>
          FaUiThemeProvider(data: pocketForgeUiTheme, child: child),
    );

void main() {
  setUpAll(ensureGoldenFonts);

  testWidgets(
    'send passes actual user input to the model and global Stop aborts a run',
    (tester) async {
      final model = FakePocketForgeModel();
      addTearDown(model.dispose);
      await _pump(tester, model);
      await tester.enterText(
        find.byKey(const ValueKey('forge-prompt')),
        'Make the track wider',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('forge-send')));
      await tester.pumpAndSettle();
      expect(model.sent, ['Make the track wider']);
      model.isRunning = true;
      model.status = 'Using read';
      model.changed();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('forge-global-stop')));
      await tester.pump();
      expect(model.stopCount, 1);
      expect(model.isRunning, false);
    },
  );

  testWidgets('dirty editor blocks changing panels until explicit discard', (
    tester,
  ) async {
    final model = FakePocketForgeModel();
    addTearDown(model.dispose);
    await _pump(tester, model);
    await tester.tap(find.text('Files').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('game.js'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('forge-file-editor')),
      'unsaved code',
    );
    await tester.tap(find.text('Agent').last);
    await tester.pumpAndSettle();
    expect(find.text('Discard file edits?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('forge-file-editor')), findsOneWidget);
    expect(model.fileContents['game.js'], isNot('unsaved code'));
    await tester.tap(find.text('Agent').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('forge-prompt')), findsOneWidget);
  });

  testWidgets('a game tool makes the persistent preview visible during a run', (
    tester,
  ) async {
    final model = FakePocketForgeModel();
    addTearDown(model.dispose);
    await _pump(tester, model);
    expect(find.text('Test preview surface'), findsNothing);
    model.isRunning = true;
    model.activity.add(
      const ForgeActivity(label: 'game_preview', detail: 'index.html'),
    );
    model.changed();
    await tester.pump();
    expect(find.text('Test preview surface'), findsOneWidget);
    expect(find.byKey(const ValueKey('forge-global-stop')), findsOneWidget);
  });

  testWidgets(
    'settings never load stored key into the field and memory-only mode is honest',
    (tester) async {
      final model = FakePocketForgeModel()..secureKeyStorage = false;
      addTearDown(model.dispose);
      await pumpGolden(
        tester,
        PocketForgeSettings(session: model),
        size: const Size(744, 1133),
        theme: buildFahTheme(uiTheme: pocketForgeUiTheme),
        wrap: (child) => FaUiThemeProvider(
          data: pocketForgeUiTheme,
          child: Scaffold(body: child),
        ),
      );
      expect(find.textContaining('session memory only'), findsOneWidget);
      final secretField = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.obscureText,
      );
      expect(tester.widget<TextField>(secretField).controller!.text, isEmpty);
      await tester.enterText(secretField, 'new-test-key');
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      expect(model.savedKey, 'new-test-key');
    },
  );

  testWidgets(
    'native preview focus callback selects preview and detaches on disposal',
    (tester) async {
      final model = FakePocketForgeModel();
      addTearDown(model.dispose);
      await _pump(tester, model);
      expect(model.onPreviewRequested, isNotNull);
      model.onPreviewRequested!();
      await tester.pump();
      expect(find.text('Test preview surface'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(model.onPreviewRequested, isNull);
    },
  );

  testWidgets('clean editor reloads agent edits but preserves unsaved typing', (
    tester,
  ) async {
    final model = FakePocketForgeModel();
    addTearDown(model.dispose);
    await _pump(tester, model);
    await tester.tap(find.text('Files').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('game.js'));
    await tester.pumpAndSettle();
    model.fileContents['game.js'] = 'updated by agent';
    model.changed();
    await tester.pumpAndSettle();
    final editor = find.byKey(const ValueKey('forge-file-editor'));
    expect(
      tester.widget<TextField>(editor).controller!.text,
      'updated by agent',
    );
    await tester.enterText(editor, 'unsaved local changes');
    model.fileContents['game.js'] = 'another disk edit';
    model.changed();
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(editor).controller!.text,
      'unsaved local changes',
    );
  });
}
