import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'game_preview_backend.dart';

GamePreviewBackend createGamePreviewBackend() => _NativeGamePreviewBackend();

class _NativeGamePreviewBackend extends GamePreviewBackend {
  InAppWebViewController? _web;
  Completer<void>? _loaded;
  final _gate = GameOperationGate();
  int _viewGeneration = 0;
  bool _disposed = false;
  bool _loading = false;
  String _status = 'Open a game preview.';

  @override
  bool get attached => _web != null;
  @override
  bool get isLoading => _loading;
  @override
  String get status => _status;

  Future<InAppWebViewController> _controller() async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (_web == null && !_disposed && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (_web == null) {
      throw StateError('The game preview must be mounted before running it.');
    }
    return _web!;
  }

  @override
  Future<void> load(String html) async {
    final web = await _gate.run(_controller());
    if (_loaded case final pending? when !pending.isCompleted) {
      pending.completeError(StateError('Preview replaced by another load.'));
    }
    final loaded = Completer<void>();
    _loaded = loaded;
    _loading = true;
    _status = 'Loading game…';
    notifyListeners();
    try {
      // Attach the readiness error listener before awaiting the platform
      // request: Stop/onReceivedError may complete it while loadData is pending.
      await _gate.run(
        Future.wait<void>([
          loaded.future,
          web.loadData(data: html, mimeType: 'text/html', encoding: 'utf-8'),
        ], eagerError: true),
        timeout: const Duration(seconds: 30),
      );
      _status = 'Game running in WebKit.';
    } catch (error) {
      _status = 'Preview failed: $error';
      rethrow;
    } finally {
      if (identical(_loaded, loaded)) _loaded = null;
      _loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  Future<Object?> invoke(String method, Map<String, Object?> payload) async {
    final web = await _gate.run(_controller());
    final result = await _gate.run(
      web.callAsyncJavaScript(
        functionBody:
            'if (!window.__pocketGame) throw new Error("Reload the game preview."); return await window.__pocketGame.run(method, payload);',
        arguments: {'method': method, 'payload': payload},
        contentWorld: ContentWorld.PAGE,
      ),
    );
    if (result == null) throw StateError('The browser returned no result.');
    if (result.error != null) throw StateError(result.error.toString());
    return result.value;
  }

  @override
  Future<Uint8List> screenshot() async {
    final web = await _gate.run(_controller());
    final png = await _gate.run(web.takeScreenshot());
    if (png == null || png.isEmpty) {
      throw StateError('WebKit could not capture the visible preview.');
    }
    return png;
  }

  @override
  void cancel() {
    _gate.cancel();
    final pending = _loaded;
    _loaded = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('Game operation canceled.'));
    }
    final old = _web;
    _web = null;
    if (old != null) unawaited(_stopDetachedView(old));
    _viewGeneration++;
    _loading = false;
    _status = 'Stopped. Reload the preview to run again.';
    if (!_disposed) notifyListeners();
  }

  Future<void> _stopDetachedView(InAppWebViewController web) async {
    try {
      await web.stopLoading();
    } on Object {
      // Cancel/dispose has already detached this platform view. Its channel
      // may be gone; cleanup must not produce an unhandled asynchronous error.
    }
  }

  @override
  Widget buildView() {
    final generation = _viewGeneration;
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.macOS)) {
      return const Center(
        child: Text(
          'Use the browser build on Windows, or the native app on iPad.',
        ),
      );
    }
    return InAppWebView(
      key: ValueKey('pocket-game-$generation'),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        javaScriptBridgeEnabled: false,
        incognito: true,
        cacheEnabled: false,
        useShouldOverrideUrlLoading: true,
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: false,
        allowsInlineMediaPlayback: true,
        isInspectable: false,
      ),
      initialUserScripts: UnmodifiableListView<UserScript>([]),
      onWebViewCreated: (web) {
        if (_disposed || generation != _viewGeneration) return;
        _web = web;
        _status = 'Preview ready.';
        notifyListeners();
      },
      shouldOverrideUrlLoading: (controller, action) async {
        final scheme = action.request.url?.scheme;
        return scheme == 'about' || scheme == 'data' || scheme == 'blob'
            ? NavigationActionPolicy.ALLOW
            : NavigationActionPolicy.CANCEL;
      },
      onLoadStop: (controller, url) {
        if (_disposed || generation != _viewGeneration) return;
        final pending = _loaded;
        if (pending != null && !pending.isCompleted) pending.complete();
      },
      onReceivedError: (controller, request, error) {
        if (_disposed ||
            generation != _viewGeneration ||
            request.isForMainFrame != true) {
          return;
        }
        final pending = _loaded;
        if (pending != null && !pending.isCompleted) {
          pending.completeError(StateError(error.description));
        }
      },
      onCreateWindow: (controller, action) async => false,
      onPermissionRequest: (controller, request) async => PermissionResponse(
        resources: request.resources,
        action: PermissionResponseAction.DENY,
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    _gate.dispose();
    super.dispose();
  }
}
