import 'dart:async';

class ScreenDisposedException implements Exception {
  const ScreenDisposedException();
}

/// Bounds screen waits without cancelling the authoritative server operation.
class ScreenRequestTimeouts {
  final Map<Timer, void Function()> _cancelers = {};
  bool _disposed = false;

  Future<T> run<T>(Future<T> operation, Duration timeout) {
    if (_disposed) {
      operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
      return Future<T>.error(const ScreenDisposedException());
    }

    final completer = Completer<T>();
    late final Timer timer;
    void clear() {
      timer.cancel();
      _cancelers.remove(timer);
    }

    void cancel() {
      clear();
      if (!completer.isCompleted) {
        completer.completeError(const ScreenDisposedException());
      }
    }

    timer = Timer(timeout, () {
      _cancelers.remove(timer);
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('Screen request timed out', timeout),
        );
      }
    });
    _cancelers[timer] = cancel;
    operation.then(
      (value) {
        clear();
        if (!completer.isCompleted) completer.complete(value);
      },
      onError: (Object error, StackTrace stackTrace) {
        clear();
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      },
    );
    return completer.future;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancelPending();
  }

  void cancelPending() {
    for (final cancel in List<void Function()>.of(_cancelers.values)) {
      cancel();
    }
    _cancelers.clear();
  }
}
