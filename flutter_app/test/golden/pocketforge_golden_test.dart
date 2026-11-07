/// Full-frame coverage for pocketforge_workbench, pocketforge_agent_pane,
/// pocketforge_files_pane, pocketforge_settings, and game_preview.
/// The preview uses an explicit test backend: no native engine/network is booted.
library;

import 'dart:typed_data';

import 'package:fa/main_pocketforge.dart' show PocketForgeGameStage;
import 'package:fa/pocketforge/browser/game_preview.dart';
import 'package:fa/pocketforge/browser/game_preview_backend.dart';
import 'package:fa/pocketforge/ui/pocketforge_settings.dart';
import 'package:fa/pocketforge/ui/pocketforge_theme.dart';
import 'package:fa/pocketforge/ui/pocketforge_workbench.dart';
import 'package:fa_ui/fa_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../pocketforge/fake_pocketforge_model.dart';
import 'golden_test_helper.dart';

class _GoldenGameBackend extends GamePreviewBackend {
  @override
  bool get attached => true;
  @override
  bool get isLoading => false;
  @override
  String get status => 'Local preview';
  @override
  Future<void> load(String html) async {}
  @override
  Future<Object?> invoke(String method, Map<String, Object?> payload) async => {
    'title': 'Neon Drift',
    'text': 'Neon Drift',
    'console': <String>[],
  };
  @override
  Future<Uint8List> screenshot() async => Uint8List(0);
  @override
  void cancel() {}
  @override
  Widget buildView() => const _GameFrame();
}

class _GameFrame extends StatelessWidget {
  const _GameFrame();
  @override
  Widget build(BuildContext context) {
    final colors = FahColors.of(context);
    return ColoredBox(
      color: colors.bg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 500;
          return Padding(
            padding: EdgeInsets.all(compact ? 24 : 44),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NEON DRIFT',
                  style: forgeMono(
                    context,
                    color: colors.teal,
                    size: 10,
                  ).copyWith(letterSpacing: 3),
                ),
                const SizedBox(height: 14),
                Text(
                  'Find your line.',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -1.3,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'One track. Endless possibility.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.dim),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    _stat(context, 'DISTANCE', '1,240'),
                    const SizedBox(width: 36),
                    _stat(context, 'SPEED', '84'),
                    const Spacer(),
                    if (!compact) _stat(context, 'BEST', '2,680'),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _TrackPainter(colors.teal, colors.border),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _control(context, Icons.keyboard_arrow_left_rounded),
                    const SizedBox(width: 10),
                    _control(context, Icons.keyboard_arrow_right_rounded),
                    const Spacer(),
                    Text('Drag to steer', style: forgeMono(context, size: 10)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: forgeMono(context, size: 8).copyWith(letterSpacing: 1.5),
      ),
      const SizedBox(height: 6),
      Text(
        value,
        style: forgeMono(context, color: FahColors.of(context).text, size: 24),
      ),
    ],
  );
  Widget _control(BuildContext context, IconData icon) => Container(
    width: 56,
    height: 42,
    decoration: BoxDecoration(
      border: Border.all(color: FahColors.of(context).border),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, color: FahColors.of(context).dim),
  );
}

class _TrackPainter extends CustomPainter {
  _TrackPainter(this.accent, this.border);
  final Color accent;
  final Color border;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF161D20),
    );
    final grid = Paint()
      ..color = border.withValues(alpha: .5)
      ..strokeWidth = .6;
    for (double x = 0; x < size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final road = Path()
      ..moveTo(size.width * .15, size.height)
      ..cubicTo(
        size.width * .13,
        size.height * .55,
        size.width * .83,
        size.height * .65,
        size.width * .68,
        0,
      );
    canvas.drawPath(
      road,
      Paint()
        ..color = const Color(0xFF293334)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .32,
    );
    canvas.drawPath(
      road,
      Paint()
        ..color = accent.withValues(alpha: .7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final car = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width * .37, size.height * .72),
        width: 19,
        height: 36,
      ),
      const Radius.circular(5),
    );
    canvas.drawRRect(car, Paint()..color = accent);
    canvas.drawRRect(car.deflate(5), Paint()..color = const Color(0xFF16342C));
  }

  @override
  bool shouldRepaint(_TrackPainter oldDelegate) => false;
}

Future<void> _pumpWorkbench(
  WidgetTester tester,
  FakePocketForgeModel model,
  Size size,
) async {
  final controller = GamePreviewController(
    env: model.env,
    projectRoot: '/workspace',
    backend: _GoldenGameBackend(),
  );
  addTearDown(controller.dispose);
  await tester.runAsync(() async {
    await model.env.writeFile(
      '/workspace/index.html',
      '<!doctype html><title>Neon Drift</title>',
    );
    await controller.preview();
  });
  await pumpGolden(
    tester,
    PocketForgeWorkbench(
      session: model,
      previewBuilder: (_) => PocketForgeGameStage(game: controller),
    ),
    size: size,
    theme: buildFahTheme(uiTheme: pocketForgeUiTheme),
    wrap: (child) => FaUiThemeProvider(data: pocketForgeUiTheme, child: child),
  );
}

void main() {
  setUpAll(ensureGoldenFonts);

  testWidgets(
    'desktop workbench with real transcript widgets and game backend fixture',
    (tester) async {
      final model = FakePocketForgeModel()..addConversationFixture();
      addTearDown(model.dispose);
      await _pumpWorkbench(tester, model, goldenSizeDesktop);
      await expectGolden(tester, 'pocketforge_desktop');
    },
  );

  testWidgets('iPad portrait preview full frame', (tester) async {
    final model = FakePocketForgeModel();
    addTearDown(model.dispose);
    await _pumpWorkbench(tester, model, const Size(744, 1133));
    await tester.tap(find.text('Preview').last);
    await tester.pumpAndSettle();
    await expectGolden(tester, 'pocketforge_ipad_preview');
  });

  testWidgets('phone agent full frame', (tester) async {
    final model = FakePocketForgeModel()..hasApiKey = false;
    addTearDown(model.dispose);
    await _pumpWorkbench(tester, model, goldenSizePhone);
    await expectGolden(tester, 'pocketforge_phone');
  });

  testWidgets('file editor full frame', (tester) async {
    final model = FakePocketForgeModel();
    addTearDown(model.dispose);
    await _pumpWorkbench(tester, model, const Size(744, 1133));
    await tester.tap(find.text('Files').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('game.js'));
    await tester.pumpAndSettle();
    await expectGolden(tester, 'pocketforge_files');
  });

  testWidgets('model settings full frame', (tester) async {
    final model = FakePocketForgeModel();
    addTearDown(model.dispose);
    await pumpGolden(
      tester,
      PocketForgeSettings(session: model),
      size: goldenSizePhone,
      theme: buildFahTheme(uiTheme: pocketForgeUiTheme),
      wrap: (child) => FaUiThemeProvider(
        data: pocketForgeUiTheme,
        child: Scaffold(body: SafeArea(child: child)),
      ),
    );
    await expectGolden(tester, 'pocketforge_settings');
  });
}
