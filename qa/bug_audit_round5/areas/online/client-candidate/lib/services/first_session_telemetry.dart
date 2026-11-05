import 'dart:async';
import 'dart:collection';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/game_store.dart';

enum FirstSessionEvent {
  firstOpen,
  introStarted,
  introStepCompleted,
  introSkipped,
  introFinished,
  homeFirstSeen,
  firstMatchCtaPressed,
  firstMatchStarted,
  firstMatchAbandoned,
  firstMatchFinished,
  resultSeen,
  secondMatchPressed,
  secondMatchStarted,
  academyOpened,
  deckOpened,
  deckSaved,
  cardUnlocked,
  cardAddedToDeck,
  rankedStarted,
  rankedCompleted,
  reconnect,
  matchmakingWaitBucket,
  cardDrawn,
  cardPlayed,
  cardDiscarded,
  cardCancelled,
}

extension FirstSessionEventWire on FirstSessionEvent {
  String get wireName =>
      const {
        FirstSessionEvent.firstOpen: 'first_open',
        FirstSessionEvent.introStarted: 'intro_started',
        FirstSessionEvent.introStepCompleted: 'intro_step',
        FirstSessionEvent.introSkipped: 'intro_skipped',
        FirstSessionEvent.introFinished: 'intro_completed',
        FirstSessionEvent.homeFirstSeen: 'first_home',
        FirstSessionEvent.firstMatchCtaPressed: 'first_match_cta_pressed',
        FirstSessionEvent.firstMatchStarted: 'first_match_started',
        FirstSessionEvent.firstMatchAbandoned: 'first_match_abandoned',
        FirstSessionEvent.firstMatchFinished: 'first_match_completed',
        FirstSessionEvent.resultSeen: 'first_result',
        FirstSessionEvent.secondMatchPressed: 'second_match_pressed',
        FirstSessionEvent.secondMatchStarted: 'second_match_started',
        FirstSessionEvent.academyOpened: 'academy_opened',
        FirstSessionEvent.deckOpened: 'deck_opened',
        FirstSessionEvent.deckSaved: 'deck_saved',
        FirstSessionEvent.cardUnlocked: 'card_unlocked',
        FirstSessionEvent.cardAddedToDeck: 'card_added_to_deck',
        FirstSessionEvent.rankedStarted: 'ranked_started',
        FirstSessionEvent.rankedCompleted: 'ranked_completed',
        FirstSessionEvent.reconnect: 'reconnect',
        FirstSessionEvent.matchmakingWaitBucket: 'matchmaking_wait_bucket',
        FirstSessionEvent.cardDrawn: 'card_drawn',
        FirstSessionEvent.cardPlayed: 'card_played',
        FirstSessionEvent.cardDiscarded: 'card_discarded',
        FirstSessionEvent.cardCancelled: 'card_cancelled',
      }[this]!;
}

enum SessionMatchMode { ai, local, online }

enum SessionMatchResult { win, loss, draw }

enum SessionWaitBucket {
  under5s,
  from5to15s,
  from15to30s,
  from30to60s,
  over60s,
}

class FirstSessionSample {
  final FirstSessionEvent event;
  final int elapsedMs;
  final int? step;
  final SessionMatchMode? mode;
  final SessionMatchResult? result;
  final SessionWaitBucket? waitBucket;
  const FirstSessionSample(
    this.event,
    this.elapsedMs, {
    this.step,
    this.mode,
    this.result,
    this.waitBucket,
  });

  Map<String, Object> toJson() => {
    'event': event.wireName,
    'elapsedMs': elapsedMs,
    if (step != null) 'step': step!,
    if (mode != null) 'mode': mode!.name,
    if (result != null) 'result': result!.name,
    if (waitBucket != null) 'waitBucket': waitBucket!.name,
  };
}

typedef FirstSessionSink = FutureOr<void> Function(FirstSessionSample sample);

/// A bounded local funnel, not an analytics SDK. No provider means no network.
/// Only typed product events leave this boundary: never UIDs, usernames, chat,
/// biographies, tokens, email, FEN, hands, deck order, or device identifiers.
class FirstSessionTelemetry {
  static final _instances = Expando<FirstSessionTelemetry>();
  static FirstSessionTelemetry forStore(GameStore store) =>
      _instances[store] ??= FirstSessionTelemetry(store);
  final GameStore store;
  late int _revision = store.accountBindingRevision;
  final _clock = Stopwatch()..start();
  final _samples = Queue<FirstSessionSample>();
  final _once = <(FirstSessionEvent, int?)>{};
  FirstSessionSink? _sink;
  bool _transmissionAllowed = false;
  FirstSessionTelemetry(this.store);
  void _synchronizeOwner() {
    if (_revision == store.accountBindingRevision) return;
    _revision = store.accountBindingRevision;
    _samples.clear();
    _once.clear();
    _clock.reset();
    _transmissionAllowed = false;
  }

  List<FirstSessionSample> get samples {
    _synchronizeOwner();
    return List.unmodifiable(_samples);
  }

  Future<void> recordFirstOpen(int ownerRevision) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (ownerRevision != store.accountBindingRevision ||
          prefs.getBool('luno_first_open_observed_v1') == true) {
        return;
      }
      if (!await prefs.setBool('luno_first_open_observed_v1', true)) return;
      record(FirstSessionEvent.firstOpen, ownerRevision);
    } catch (_) {
      // Optional measurement must never affect startup or account creation.
    }
  }

  void configure({FirstSessionSink? sink, bool transmissionAllowed = false}) {
    _synchronizeOwner();
    _sink = sink;
    _transmissionAllowed = transmissionAllowed;
  }

  bool record(
    FirstSessionEvent event,
    int ownerRevision, {
    int? step,
    SessionMatchMode? mode,
    SessionMatchResult? result,
    SessionWaitBucket? waitBucket,
  }) {
    if (ownerRevision != store.accountBindingRevision) return false;
    _synchronizeOwner();
    if (step != null &&
        (event != FirstSessionEvent.introStepCompleted ||
            step < 0 ||
            step >= GameStore.introductionStepCount)) {
      return false;
    }
    if (waitBucket != null &&
        event != FirstSessionEvent.matchmakingWaitBucket) {
      return false;
    }
    final repeated = const {
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
    }.contains(event);
    if (!repeated && !_once.add((event, step))) return false;
    final sample = FirstSessionSample(
      event,
      _clock.elapsedMilliseconds.clamp(0, 86400000),
      step: step,
      mode: mode,
      result: result,
      waitBucket: waitBucket,
    );
    if (_samples.length == 64) _samples.removeFirst();
    _samples.add(sample);
    final sink = _sink;
    if (_transmissionAllowed && sink != null) {
      // Sink failures cannot interrupt input, navigation or gameplay.
      unawaited(
        Future<void>.sync(() {
          if (ownerRevision == store.accountBindingRevision &&
              _transmissionAllowed &&
              identical(sink, _sink)) {
            return sink(sample);
          }
        }).catchError((_) {}),
      );
    }
    return true;
  }
}
