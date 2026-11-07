import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The only connection between generated game code and the app is this
/// page-operation interface. Provider credentials and filesystem APIs are absent.
abstract class GamePreviewBackend extends ChangeNotifier {
  bool get attached;
  bool get isLoading;
  String get status;
  Future<void> load(String html);
  Future<Object?> invoke(String method, Map<String, Object?> payload);
  Future<Uint8List> screenshot();
  void cancel();
  Widget buildView();
}

/// Cancels pending callers immediately, including unresolved page promises.
/// Native WebKit is recreated on cancellation to stop the old JS context.
class GameOperationGate {
  Completer<void> _canceled = Completer<void>();
  bool _disposed = false;

  Future<T> run<T>(
    Future<T> operation, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    if (_disposed) return Future.error(StateError('Game preview disposed.'));
    final stopped = _canceled.future;
    return Future.any<T>([
      operation,
      stopped.then<T>((_) => throw StateError('Game operation canceled.')),
    ]).timeout(timeout);
  }

  void cancel() {
    if (!_canceled.isCompleted) _canceled.complete();
    _canceled = Completer<void>();
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}
