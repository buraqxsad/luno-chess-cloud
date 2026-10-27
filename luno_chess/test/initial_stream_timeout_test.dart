import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/initial_stream_timeout.dart';

void main() {
  const timeout = Duration(milliseconds: 30);
  test('timeout must be positive', () {
    expect(
      () => withInitialStreamTimeout(const Stream<int>.empty(), Duration.zero),
      throwsArgumentError,
    );
  });
  for (final scenario in [
    'late-data',
    'first-data',
    'source-error',
    'done',
    'cancel',
    'pause',
    'listeners',
  ]) {
    test('initial event watchdog $scenario', () async {
      Future<void> cancel(StreamSubscription<int> subscription) async {
        await subscription.cancel();
      }

      var cancellations = 0;
      final source = StreamController<int>.broadcast(
        sync: true,
        onCancel: () => cancellations++,
      );
      final stream = withInitialStreamTimeout(source.stream, timeout);
      final values = <int>[];
      final errors = <Object>[];
      var done = false;
      final subscription = stream.listen(
        values.add,
        onError: errors.add,
        onDone: () => done = true,
      );
      await Future<void>.delayed(Duration.zero);
      if (scenario == 'first-data') {
        source.add(1);
      } else if (scenario == 'source-error') {
        source.addError(StateError('Source failure'));
      } else if (scenario == 'done') {
        await source.close();
      } else if (scenario == 'cancel') {
        await cancel(subscription);
      } else if (scenario == 'pause') {
        subscription.pause();
      }
      if (scenario == 'listeners') {
        final secondErrors = <Object>[];
        final second = stream.listen((_) {}, onError: secondErrors.add);
        await cancel(subscription);
        await Future<void>.delayed(timeout * 2);
        expect(errors, isEmpty);
        expect(secondErrors.single, isA<TimeoutException>());
        await cancel(second);
      } else {
        await Future<void>.delayed(timeout * 2);
        if (scenario == 'late-data') {
          expect(errors.single, isA<TimeoutException>());
          source.add(2);
          await Future<void>.delayed(Duration.zero);
          expect(values, [2]);
        } else if (scenario == 'source-error') {
          expect(errors.single, isA<StateError>());
          source.add(2);
          await Future<void>.delayed(Duration.zero);
          expect(values, [2]);
        } else {
          expect(errors, isEmpty);
        }
        if (scenario == 'pause') {
          subscription.resume();
          await Future<void>.delayed(timeout * 2);
          expect(errors.single, isA<TimeoutException>());
        }
        if (scenario == 'done') expect(done, true);
        await Future<void>.delayed(timeout * 3);
        expect(
          errors.length,
          scenario == 'late-data' ||
                  scenario == 'source-error' ||
                  scenario == 'pause'
              ? 1
              : 0,
        );
        await cancel(subscription);
      }
      if (!source.isClosed) {
        await source.close();
      }
      expect(source.hasListener, false);
      expect(cancellations, 1);
    });
  }
}
