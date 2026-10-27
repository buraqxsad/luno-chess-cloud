import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/screen_request_timeouts.dart';

void main() {
  testWidgets('screen deadline returns completed value and clears its timer', (
    tester,
  ) async {
    final deadlines = ScreenRequestTimeouts();
    expect(
      await deadlines.run(Future.value(42), const Duration(seconds: 12)),
      42,
    );
    deadlines.dispose();
  });

  testWidgets('screen deadline preserves the operation error', (tester) async {
    final deadlines = ScreenRequestTimeouts();
    final failure = StateError('rejected');
    await expectLater(
      deadlines.run(Future<int>.error(failure), const Duration(seconds: 12)),
      throwsA(same(failure)),
    );
    deadlines.dispose();
  });

  testWidgets('screen deadline times out and consumes a late error', (
    tester,
  ) async {
    final deadlines = ScreenRequestTimeouts();
    final pending = Completer<int>();
    final check = expectLater(
      deadlines.run(pending.future, const Duration(seconds: 12)),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump(const Duration(seconds: 12));
    await check;
    pending.completeError(StateError('late rejection'));
    await tester.pump();
    deadlines.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'screen disposal cancels all waits and consumes late completions',
    (tester) async {
      final deadlines = ScreenRequestTimeouts();
      final first = Completer<int>();
      final second = Completer<int>();
      final checks = [
        expectLater(
          deadlines.run(first.future, const Duration(seconds: 12)),
          throwsA(isA<ScreenDisposedException>()),
        ),
        expectLater(
          deadlines.run(second.future, const Duration(seconds: 12)),
          throwsA(isA<ScreenDisposedException>()),
        ),
      ];
      deadlines.dispose();
      deadlines.dispose();
      await tester.pump();
      await Future.wait(checks);
      first.complete(1);
      second.completeError(StateError('late rejection'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelling current waits leaves the screen usable', (
    tester,
  ) async {
    final deadlines = ScreenRequestTimeouts();
    final pending = Completer<int>();
    final check = expectLater(
      deadlines.run(pending.future, const Duration(seconds: 12)),
      throwsA(isA<ScreenDisposedException>()),
    );
    deadlines.cancelPending();
    await tester.pump();
    await check;
    expect(
      await deadlines.run(Future.value(7), const Duration(seconds: 12)),
      7,
    );
    pending.complete(1);
    await tester.pump();
    deadlines.dispose();
  });

  testWidgets('a disposed deadline rejects new waits without adding a timer', (
    tester,
  ) async {
    final deadlines = ScreenRequestTimeouts()..dispose();
    await expectLater(
      deadlines.run(Future.value(1), const Duration(seconds: 12)),
      throwsA(isA<ScreenDisposedException>()),
    );
  });

  testWidgets('a disposed deadline consumes an already-started late error', (
    tester,
  ) async {
    final deadlines = ScreenRequestTimeouts()..dispose();
    final pending = Completer<int>();
    await expectLater(
      deadlines.run(pending.future, const Duration(seconds: 12)),
      throwsA(isA<ScreenDisposedException>()),
    );
    pending.completeError(StateError('late error'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
