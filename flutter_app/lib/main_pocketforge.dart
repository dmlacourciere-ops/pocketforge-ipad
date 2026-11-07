// l10n:ignore-file — Independent, English-only PocketForge product entrypoint.
import 'package:fa_ui/fa_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pocketforge/browser/game_preview.dart';
import 'pocketforge/pocketforge_session.dart';
import 'pocketforge/ui/pocketforge_theme.dart';
import 'pocketforge/ui/pocketforge_workbench.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final notice in const [
      ('Flutter Agent Harness', 'assets/pocketforge/LICENSE.fa.txt'),
      ('Inter', 'assets/fonts/Inter-LICENSE.txt'),
      ('JetBrains Mono', 'assets/fonts/JetBrainsMono-LICENSE.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        notice.$1,
      ], await rootBundle.loadString(notice.$2));
    }
  });
  runApp(const PocketForgeApp());
}

/// Paints before runtime startup. A failed runtime produces a retryable screen.
class PocketForgeApp extends StatefulWidget {
  const PocketForgeApp({super.key});
  @override
  State<PocketForgeApp> createState() => _PocketForgeAppState();
}

class _PocketForgeAppState extends State<PocketForgeApp> {
  late Future<PocketForgeSession> _startup = _openSession();
  PocketForgeSession? _session;

  Future<PocketForgeSession> _openSession() async {
    final session = await PocketForgeSession.create();
    if (!mounted) {
      session.dispose();
      throw StateError('The workspace was closed during startup.');
    }
    _session = session;
    return session;
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FaUiThemeProvider(
    data: pocketForgeUiTheme,
    child: MaterialApp(
      title: 'PocketForge',
      debugShowCheckedModeBanner: false,
      theme: buildFahTheme(uiTheme: pocketForgeUiTheme),
      home: FutureBuilder<PocketForgeSession>(
        future: _startup,
        builder: (context, state) {
          final session = state.data;
          if (session != null) {
            return PocketForgeWorkbench(
              session: session,
              previewBuilder: (_) => PocketForgeGameStage(game: session.game),
            );
          }
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.code_rounded, size: 36),
                      const SizedBox(height: 24),
                      const Text(
                        'POCKETFORGE',
                        style: TextStyle(letterSpacing: 4, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        state.hasError
                            ? 'The workspace could not open.'
                            : 'Your next great game starts here.',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (state.hasError) ...[
                        SelectableText(state.error.toString()),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: () => setState(() {
                            _startup = _openSession();
                          }),
                          child: const Text('Try again'),
                        ),
                      ] else ...[
                        const LinearProgressIndicator(minHeight: 2),
                        const SizedBox(height: 12),
                        const Text(
                          'Opening your local workspace…',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class PocketForgeGameStage extends StatelessWidget {
  const PocketForgeGameStage({super.key, required this.game});
  final GamePreviewController game;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(child: PocketGamePreview(controller: game)),
      AnimatedBuilder(
        animation: game,
        builder: (context, _) {
          final result = game.lastTest;
          final colors = FahColors.of(context);
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Icon(
                  result == null
                      ? Icons.radio_button_unchecked
                      : result.passed
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  size: 14,
                  color: result == null
                      ? colors.dim
                      : result.passed
                      ? const Color(0xff8cdac3)
                      : colors.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result == null
                        ? game.status
                        : 'LAST RUN · ${result.passed ? 'PASS' : 'FAIL'} · ${result.checks.length} checks',
                    style: forgeMono(context, size: 9),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (result != null)
                  TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Game test results'),
                        content: SizedBox(
                          width: 480,
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final check in result.checks)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 5,
                                    ),
                                    child: Text(
                                      '${check.passed ? 'PASS' : 'FAIL'}  ${check.message}',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Done'),
                          ),
                        ],
                      ),
                    ),
                    child: const Text(
                      'Details',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                if (game.lastScreenshot != null)
                  IconButton(
                    tooltip: 'Captured screenshot',
                    icon: const Icon(Icons.image_outlined, size: 16),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => Dialog(
                        child: InteractiveViewer(
                          child: Image.memory(game.lastScreenshot!),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ],
  );
}
