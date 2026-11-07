// This conditional adapter follows the existing app's iframe platform-view
// implementation. It is excluded from native builds.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

import 'game_preview_backend.dart';

GamePreviewBackend createGamePreviewBackend() => _WebGamePreviewBackend();

int _nextGameFrame = 0;

class _WebGamePreviewBackend extends GamePreviewBackend {
  _WebGamePreviewBackend() {
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) => _frame);
    _messages = html.window.onMessage.listen(_onMessage);
    _loads = _frame.onLoad.listen((_) {
      _attached = true;
      final pending = _loaded;
      if (pending != null && !pending.isCompleted) pending.complete();
      if (!_disposed) notifyListeners();
    });
  }

  final String _viewType = 'pocket-game-${_nextGameFrame++}';
  final html.IFrameElement _frame = html.IFrameElement()
    ..style.border = '0'
    ..style.width = '100%'
    ..style.height = '100%'
    ..setAttribute('sandbox', 'allow-scripts')
    ..setAttribute('title', 'PocketForge game preview');
  final _gate = GameOperationGate();
  final Map<String, Completer<Object?>> _requests = {};
  late final StreamSubscription<html.MessageEvent> _messages;
  late final StreamSubscription<html.Event> _loads;
  Completer<void>? _loaded;
  String _nonce = '';
  int _sequence = 0;
  bool _attached = false;
  bool _loading = false;
  bool _disposed = false;
  String _status = 'Open a game preview.';

  @override
  bool get attached => _attached;
  @override
  bool get isLoading => _loading;
  @override
  String get status => _status;

  void _onMessage(html.MessageEvent event) {
    // dart:html creates a fresh cross-frame Window wrapper for each access.
    // Compare the raw JS WindowProxy identities, retaining the source check.
    final source = js_util.getProperty<Object?>(event, 'source');
    final expected = js_util.getProperty<Object?>(_frame, 'contentWindow');
    if (_disposed || !identical(source, expected)) return;
    // Structured-clone replies are JavaScript objects, not Dart Maps in the
    // compiled web app. Convert before checking the protocol envelope.
    final data = js_util.dartify(js_util.getProperty<Object?>(event, 'data'));
    if (data is! Map ||
        data['channel'] != 'pocketforge-game' ||
        data['nonce'] != _nonce ||
        data['kind'] != 'result') {
      return;
    }
    final pending = _requests.remove(data['id']);
    if (pending == null || pending.isCompleted) return;
    if (data['error'] != null) {
      pending.completeError(StateError(data['error'].toString()));
    } else {
      pending.complete(data['value']);
    }
  }

  @override
  Future<void> load(String document) async {
    _gate.cancel();
    _rejectRequests();
    _nonce = List.generate(
      6,
      (_) => Random.secure().nextInt(0x7fffffff).toRadixString(16),
    ).join();
    final loaded = Completer<void>();
    _loaded = loaded;
    _loading = true;
    _status = 'Loading game…';
    notifyListeners();
    // Only page-operations are bridged. The frame has an opaque origin and
    // cannot reach the Flutter app's IndexedDB, provider keys, or DOM.
    final quotedNonce = '"$_nonce"';
    _frame.srcdoc = document.replaceFirst(
      '/*POCKETFORGE_RPC*/',
      'window.__pocketGame.installRpc($quotedNonce);',
    );
    try {
      await _gate.run(loaded.future, timeout: const Duration(seconds: 30));
      _status = 'Game running in an isolated browser frame.';
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
    if (!_attached || _nonce.isEmpty) {
      throw StateError('Run the game preview first.');
    }
    final id = '${++_sequence}';
    final pending = Completer<Object?>();
    _requests[id] = pending;
    _frame.contentWindow!.postMessage({
      'channel': 'pocketforge-game',
      'nonce': _nonce,
      'kind': 'request',
      'id': id,
      'method': method,
      'payload': payload,
    }, '*');
    try {
      return await _gate.run(pending.future);
    } finally {
      _requests.remove(id);
    }
  }

  @override
  Future<Uint8List> screenshot() => Future.error(
    UnsupportedError(
      'Full-page screenshots are unavailable in this web build. DOM, input and JavaScript tests work here; native iPad WebKit supports screenshots.',
    ),
  );

  void _rejectRequests() {
    for (final pending in _requests.values) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('Game operation canceled.'));
      }
    }
    _requests.clear();
  }

  @override
  void cancel() {
    _gate.cancel();
    _rejectRequests();
    final pending = _loaded;
    _loaded = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('Game operation canceled.'));
    }
    _nonce = '';
    _frame.srcdoc =
        '<!doctype html><html><body>Preview stopped. Run it again to reload.</body></html>';
    _loading = false;
    _status = 'Stopped. Reload the preview to run again.';
    if (!_disposed) notifyListeners();
  }

  @override
  Widget buildView() => HtmlElementView(viewType: _viewType);

  @override
  void dispose() {
    _disposed = true;
    cancel();
    _messages.cancel();
    _loads.cancel();
    _gate.dispose();
    super.dispose();
  }
}
