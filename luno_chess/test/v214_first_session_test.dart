import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/services/first_session_telemetry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'journey bookkeeping persists without altering economy or match stats',
    () async {
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.load();
      final before = store.data.toJson();
      expect(store.firstSessionMatchesStarted, 0);
      expect(
        store.recordFirstSessionMatchStart(store.accountBindingRevision),
        1,
      );
      expect(
        store.recordFirstSessionMatchStart(store.accountBindingRevision),
        1,
      );
      expect(store.needsFirstSessionMatch, isTrue);
      expect(
        store.recordFirstSessionMatchCompletion(store.accountBindingRevision),
        isTrue,
      );
      expect(
        store.recordFirstSessionMatchStart(store.accountBindingRevision),
        2,
      );
      expect(
        store.recordFirstSessionMatchStart(store.accountBindingRevision),
        0,
      );
      expect(store.data.toJson(), before);
      await store.save();
      final restored = GameStore.createForTesting();
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.firstSessionMatchesStarted, 2);
    },
  );
  test(
    'existing players are not mislabeled as awaiting their first match',
    () async {
      SharedPreferences.setMockInitialValues({
        'luno_player_v1': jsonEncode({
          ...PlayerData.initial().toJson(),
          'accountUid': 'old',
          'tutorialCompleted': true,
          'usernameChosen': true,
        }),
      });
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.load();
      expect(store.firstSessionMatchesStarted, 2);
    },
  );
  test(
    'introduction completion does not consume the real first match',
    () async {
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.load();
      await store.completeIntroduction(store.accountBindingRevision);
      await store.save();
      final restored = GameStore.createForTesting();
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.firstSessionMatchesStarted, 0);
    },
  );
  test(
    'account archives isolate journey progress and reject old owners',
    () async {
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.load();
      await store.bindAccount('first');
      final oldRevision = store.accountBindingRevision;
      expect(store.recordFirstSessionMatchStart(oldRevision), 1);
      await store.bindAccount('other');
      expect(store.firstSessionMatchesStarted, 0);
      expect(store.recordFirstSessionMatchStart(oldRevision), 0);
      await store.bindAccount('first');
      expect(store.firstSessionMatchesStarted, 1);
    },
  );
  test(
    'typed local funnel is deduplicated and never sends by default',
    () async {
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.load();
      final telemetry = FirstSessionTelemetry(store),
          sent = <FirstSessionSample>[];
      telemetry.configure(sink: sent.add);
      const repeatable = {
        FirstSessionEvent.cardDrawn,
        FirstSessionEvent.cardPlayed,
        FirstSessionEvent.cardDiscarded,
        FirstSessionEvent.cardCancelled,
        FirstSessionEvent.reconnect,
        FirstSessionEvent.rankedStarted,
        FirstSessionEvent.rankedCompleted,
        FirstSessionEvent.deckOpened,
        FirstSessionEvent.deckSaved,
        FirstSessionEvent.cardUnlocked,
        FirstSessionEvent.cardAddedToDeck,
        FirstSessionEvent.matchmakingWaitBucket,
      };
      for (final event in FirstSessionEvent.values) {
        expect(telemetry.record(event, store.accountBindingRevision), isTrue);
        expect(
          telemetry.record(event, store.accountBindingRevision),
          repeatable.contains(event),
          reason: '$event follows its funnel/aggregate semantics',
        );
      }
      expect(sent, isEmpty);
      expect(
        telemetry.samples.length,
        FirstSessionEvent.values.length + repeatable.length,
      );
      for (final event in FirstSessionEvent.values) {
        expect(
          telemetry.samples.where((sample) => sample.event == event).length,
          repeatable.contains(event) ? 2 : 1,
        );
      }
      expect(
        telemetry.record(
          FirstSessionEvent.introStepCompleted,
          store.accountBindingRevision,
          step: 14,
        ),
        isFalse,
      );
      for (final sample in telemetry.samples) {
        expect(sample.toJson().keys.toSet(), {'event', 'elapsedMs'});
      }
    },
  );
  test(
    'explicit provider consent sends only allowlisted typed properties',
    () async {
      final store = GameStore.createForTesting();
      addTearDown(store.dispose);
      await store.load();
      final telemetry = FirstSessionTelemetry(store),
          sent = <FirstSessionSample>[];
      telemetry.configure(sink: sent.add, transmissionAllowed: true);
      telemetry.record(
        FirstSessionEvent.firstMatchFinished,
        store.accountBindingRevision,
        mode: SessionMatchMode.ai,
        result: SessionMatchResult.win,
      );
      await Future<void>.delayed(Duration.zero);
      expect(sent.single.toJson()['event'], 'first_match_completed');
      expect(sent.single.toJson().keys.toSet(), {
        'event',
        'elapsedMs',
        'mode',
        'result',
      });
      telemetry.configure(
        sink: (_) => throw StateError('provider failure'),
        transmissionAllowed: true,
      );
      expect(
        () => telemetry.record(
          FirstSessionEvent.resultSeen,
          store.accountBindingRevision,
        ),
        returnsNormally,
      );
      await Future<void>.delayed(Duration.zero);
    },
  );
  test('departed account cannot emit old local samples', () async {
    final store = GameStore.createForTesting();
    addTearDown(store.dispose);
    await store.load();
    await store.bindAccount('one');
    final telemetry = FirstSessionTelemetry(store),
        revision = store.accountBindingRevision;
    telemetry.record(FirstSessionEvent.introStarted, revision);
    await store.bindAccount('two');
    expect(
      telemetry.record(FirstSessionEvent.introFinished, revision),
      isFalse,
    );
    telemetry.record(
      FirstSessionEvent.homeFirstSeen,
      store.accountBindingRevision,
    );
    expect(telemetry.samples.map((s) => s.event), [
      FirstSessionEvent.homeFirstSeen,
    ]);
  });
  test('first_open is installation scoped rather than every launch', () async {
    final store = GameStore.createForTesting();
    addTearDown(store.dispose);
    await store.load();
    final first = FirstSessionTelemetry(store);
    await first.recordFirstOpen(store.accountBindingRevision);
    expect(first.samples.single.event, FirstSessionEvent.firstOpen);
    final next = FirstSessionTelemetry(store);
    await next.recordFirstOpen(store.accountBindingRevision);
    expect(next.samples, isEmpty);
  });
}
