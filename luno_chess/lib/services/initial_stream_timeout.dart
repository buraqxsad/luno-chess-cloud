import 'dart:async';

/// Bounds the first event only, while allowing late data to recover the stream.
Stream<T> withInitialStreamTimeout<T>(Stream<T> source, Duration timeout) {
  if (timeout <= Duration.zero) {
    throw ArgumentError.value(timeout, 'timeout', 'Must be positive');
  }
  return Stream<T>.multi((controller) {
    Timer? timer;
    var waiting = true;
    void finishWaiting() {
      waiting = false;
      timer?.cancel();
      timer = null;
    }

    void arm() {
      if (!waiting) return;
      timer = Timer(timeout, () {
        finishWaiting();
        controller.addErrorSync(
          TimeoutException('Initial stream event timed out', timeout),
        );
      });
    }

    arm();
    final subscription = source.listen(
      (value) {
        finishWaiting();
        controller.addSync(value);
      },
      onError: (Object error, StackTrace stack) {
        finishWaiting();
        controller.addErrorSync(error, stack);
      },
      onDone: () {
        finishWaiting();
        controller.closeSync();
      },
    );
    controller.onCancel = () {
      finishWaiting();
      return subscription.cancel();
    };
    controller.onPause = () {
      timer?.cancel();
      timer = null;
      subscription.pause();
    };
    controller.onResume = () {
      arm();
      subscription.resume();
    };
  }, isBroadcast: source.isBroadcast);
}
