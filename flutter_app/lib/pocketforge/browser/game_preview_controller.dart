import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_agent_harness/flutter_agent_harness.dart';

import 'game_document.dart';
import 'game_preview_backend.dart';
import 'game_preview_backend_factory.dart';

class GameCheck {
  const GameCheck({required this.passed, required this.message});
  final bool passed;
  final String message;
  Map<String, Object?> toJson() => {'passed': passed, 'message': message};
}

class GameTestReport {
  const GameTestReport({required this.passed, required this.checks});
  final bool passed;
  final List<GameCheck> checks;
  Map<String, Object?> toJson() => {
    'passed': passed,
    'checks': checks.map((check) => check.toJson()).toList(),
  };
}

class GamePreviewController extends ChangeNotifier {
  GamePreviewController({
    required this.env,
    required this.projectRoot,
    GamePreviewBackend? backend,
  }) : _backend = backend ?? createGamePreviewBackend() {
    _backend.addListener(_changed);
  }
  final ExecutionEnv env;
  final String projectRoot;
  final GamePreviewBackend _backend;
  VoidCallback? onFocusRequest;
  int _generation = 0;
  bool _disposed = false;
  bool _loading = false;
  String _status = 'Open a game preview.';
  String _path = '';
  List<String> _console = [];
  Uint8List? _screenshot;
  GameTestReport? _lastTest;
  bool get attached => _backend.attached;
  bool get isLoading => _loading || _backend.isLoading;
  String get status => _status;
  String get path => _path;
  List<String> get consoleLines => List.unmodifiable(_console);
  Uint8List? get lastScreenshot => _screenshot;
  GameTestReport? get lastTest => _lastTest;
  Widget buildView() => _backend.buildView();

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _active(int generation) {
    if (_disposed || generation != _generation) {
      throw StateError('Game operation canceled.');
    }
  }

  Future<String> preview({String path = 'index.html'}) async {
    onFocusRequest?.call();
    final generation = ++_generation;
    _loading = true;
    _status = 'Preparing $path…';
    _lastTest = null;
    _screenshot = null;
    _console = [];
    _changed();
    try {
      final runtime = await rootBundle.loadString(
        'assets/pocketforge/game_runtime.js',
      );
      final html = await GameDocumentBundler(
        env: env,
        projectRoot: projectRoot,
      ).bundle(path, runtime);
      _active(generation);
      await _backend.load(html);
      _active(generation);
      _path = path;
      _status = _backend.status;
      return await read();
    } catch (error) {
      if (!_disposed && generation == _generation) {
        _status = 'Preview failed: $error';
      }
      rethrow;
    } finally {
      if (!_disposed && generation == _generation) {
        _loading = false;
        _changed();
      }
    }
  }

  Future<Object?> invoke(
    String operation,
    Map<String, Object?> arguments,
  ) async {
    if (_path.isEmpty && !_loading) {
      throw StateError('Run game_preview before testing a game.');
    }
    final generation = _generation;
    final result = await _backend.invoke(operation, arguments);
    _active(generation);
    return result;
  }

  Future<String> read() async {
    final result = await invoke('read', const {});
    if (result is Map && result['console'] is List) {
      _console = (result['console'] as List)
          .map((line) => line.toString())
          .take(80)
          .toList();
      _changed();
    }
    return jsonEncode(result);
  }

  Future<Object?> evaluate(String code) {
    if (code.length > 64000) {
      throw ArgumentError('Game expressions must be below 64 KB.');
    }
    return invoke('eval', {'code': code});
  }

  Future<GameTestReport> test(String script) async {
    if (script.length > 64000) {
      throw ArgumentError('Game tests must be below 64 KB.');
    }
    final result = await invoke('test', {'script': script});
    if (result is! Map || result['checks'] is! List) {
      throw StateError('The game returned an invalid test report.');
    }
    final checks = (result['checks'] as List)
        .whereType<Map>()
        .map(
          (item) => GameCheck(
            passed: item['passed'] == true,
            message: item['message'].toString(),
          ),
        )
        .toList();
    final report = GameTestReport(
      passed: checks.isNotEmpty && checks.every((check) => check.passed),
      checks: checks,
    );
    _lastTest = report;
    _status = '${report.passed ? 'PASS' : 'FAIL'} · ${checks.length} checks';
    await read();
    _changed();
    return report;
  }

  Future<Uint8List> screenshot() async {
    if (_path.isEmpty) {
      throw StateError('Run game_preview before capturing the game.');
    }
    final generation = _generation;
    onFocusRequest?.call();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _active(generation);
    final image = await _backend.screenshot();
    _active(generation);
    _screenshot = image;
    _changed();
    return image;
  }

  void cancel() {
    _generation++;
    _backend.cancel();
    _path = '';
    _loading = false;
    _status = 'Stopped. Reload the preview to run again.';
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _backend.removeListener(_changed);
    _backend.dispose();
    super.dispose();
  }
}
