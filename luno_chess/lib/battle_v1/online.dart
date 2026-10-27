import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'core.dart';
import 'model.dart';

const battleV1Protocol = 'LUNO_BATTLE_V1';
typedef BattleV1Request =
    Future<Map<String, dynamic>> Function(String, Map<String, dynamic>);
typedef PendingIntentWriter = Future<void> Function(String?);

bool _pendingKeys(
  Map value,
  Set<String> requiredKeys, [
  Set<String> optionalKeys = const {},
]) =>
    requiredKeys.every(value.containsKey) &&
    value.keys.every(
      (key) => requiredKeys.contains(key) || optionalKeys.contains(key),
    );

bool _pendingInteger(Object? value, int maximum) =>
    value is num &&
    value.isFinite &&
    value == value.toInt() &&
    value.toInt() >= 0 &&
    value.toInt() <= maximum;

// Mirror rules-v1 parseIntent's wire shape, not current-position legality.
bool _pendingIntent(Object? value) {
  if (value is! Map) return false;
  bool card() =>
      value['card'] is String && (value['card'] as String).length <= 32;
  switch (value['type']) {
    case 'move':
      return _pendingKeys(value, {'type', 'uci'}) &&
          value['uci'] is String &&
          RegExp(
            r'^[a-h][1-8][a-h][1-8][qrbn]?$',
          ).hasMatch(value['uci'] as String);
    case 'discard':
      return _pendingKeys(value, {'type', 'card'}) && card();
    case 'play':
      final target = value['target'];
      return _pendingKeys(value, {'type', 'card'}, {'target', 'sacrifice'}) &&
          card() &&
          (!value.containsKey('target') ||
              _pendingInteger(target, 63) ||
              target is String && target.length <= 80) &&
          (!value.containsKey('sacrifice') || value['sacrifice'] is String);
    case 'resolve':
      final order = value['order'];
      return _pendingKeys(value, {'type', 'order'}, {'selected'}) &&
          order is List &&
          order.length <= 3 &&
          order.every((card) => card is String) &&
          order.toSet().length == order.length &&
          (!value.containsKey('selected') || value['selected'] is String);
    case 'pass':
    case 'resign':
      // Resign is a local marker removed before calling the strict endpoint.
      return _pendingKeys(value, {'type'});
    default:
      return false;
  }
}

bool _pendingEnvelope(Object? value, String matchId) {
  if (value is! Map ||
      !_pendingKeys(value, {
        'matchId',
        'protocolVersion',
        'expectedStateVersion',
        'actionId',
        'intent',
      }) ||
      value['matchId'] != matchId ||
      !RegExp(r'^bv1_[a-f0-9]{32}$').hasMatch(matchId) ||
      value['protocolVersion'] != battleV1Protocol ||
      !_pendingInteger(value['expectedStateVersion'], 9007199254740991)) {
    return false;
  }
  final id = value['actionId'];
  final version = (value['expectedStateVersion'] as num).toInt();
  return id is String &&
      RegExp(r'^[A-Za-z0-9_-]{12,80}$').hasMatch(id) &&
      id.startsWith('a${version}_') &&
      _pendingIntent(value['intent']);
}

class BattleV1Rejection implements Exception {
  final String code;
  const BattleV1Rejection(this.code);
  @override
  String toString() => code;
}

class BattleV1Snapshot {
  final String matchId;
  final int stateVersion;
  final PlayerView player;
  final Map<String, dynamic> public;
  final Map<String, dynamic>? result;
  final int serverNow;
  final BattleV1Settlement? settlement;
  BattleV1Snapshot._(
    this.matchId,
    this.stateVersion,
    this.player,
    this.public,
    this.result,
    this.serverNow,
    this.settlement,
  );
  factory BattleV1Snapshot.fromResponse(
    Map<String, dynamic> response,
    String uid,
  ) {
    final view = response['view'];
    if (response['ok'] != true ||
        view is! Map ||
        view['public'] is! Map ||
        view['private'] is! Map) {
      throw const FormatException('Invalid V1 snapshot');
    }
    final p = Map<String, dynamic>.from(view['public'] as Map);
    final own = Map<String, dynamic>.from(view['private'] as Map);
    const publicKeys = {
      'matchId',
      'protocolVersion',
      'rulesetVersion',
      'stateVersion',
      'participants',
      'players',
      'rulesJson',
      'clock',
      'result',
      'settlementStatus',
      'rated',
      'createdAt',
      'lastEvent',
    };
    const privateKeys = {
      'stateVersion',
      'viewer',
      'handJson',
      'knowledgeJson',
      'analysisJson',
      'settlementJson',
    };
    if (p.keys.any((k) => !publicKeys.contains(k)) ||
        own.keys.any((k) => !privateKeys.contains(k))) {
      throw const FormatException('Unknown V1 fields');
    }
    final id = p['matchId'];
    final version = p['stateVersion'];
    final result = p['result'];
    if (result != null &&
        (result is! Map ||
            result['reason'] is! String ||
            (result['reason'] as String).isEmpty ||
            !result.containsKey('winner') ||
            !const {null, 'w', 'b'}.contains(result['winner']))) {
      throw const FormatException('Invalid match result');
    }
    if (response['status'] != (p['result'] == null ? 'active' : 'finished')) {
      throw const FormatException('Invalid match status');
    }
    if (id is! String ||
        !RegExp(r'^bv1_[a-f0-9]{32}$').hasMatch(id) ||
        response['matchId'] != id ||
        p['protocolVersion'] != battleV1Protocol ||
        p['rulesetVersion'] != 1 ||
        version is! int ||
        version < 0 ||
        own['stateVersion'] != version ||
        p['participants'] is! Map ||
        (p['participants'] as Map)[uid] != true) {
      throw const FormatException('Incompatible V1 snapshot');
    }
    final players = p['players'];
    if (!const {'w', 'b'}.contains(own['viewer']) ||
        players is! Map ||
        players['w'] is! Map ||
        players['b'] is! Map) {
      throw const FormatException('Invalid players');
    }
    final side = parseSide(own['viewer'] as String);
    final ownPlayer = players[sideWire(side)] as Map;
    if (ownPlayer['uid'] != uid || ownPlayer['bot'] != false) {
      throw const FormatException('Wrong account');
    }
    final ruleJson = jsonDecode(p['rulesJson'] as String) as Map;
    const ruleKeys = {
      'fen',
      'pieceIds',
      'movedPawns',
      'phase',
      'mana',
      'ownTurns',
      'handCounts',
      'deckCounts',
      'drawCounts',
      'arsenals',
      'used',
      'discarded',
      'pieceEffects',
      'boardEffects',
      'modifiers',
      'vows',
      'special',
      'pending',
      'terminal',
      'effectSequence',
      'ply',
      'repetitions',
    };
    if (ruleJson.keys.any((k) => !ruleKeys.contains(k))) {
      throw const FormatException('Secret rule fields');
    }
    final rules = RuleState.fromJson(ruleJson);
    if (rules.pieceIds.length != 64 ||
        rules.ply < 0 ||
        rules.effectSequence < 0 ||
        rules.handCounts.values.any((count) => count < 0 || count > 4) ||
        rules.deckCounts.values.any((count) => count < 0 || count > 10)) {
      throw const FormatException('Invalid public rule state');
    }
    final hand = parseCards(jsonDecode(own['handJson'] as String));
    final knowledgeJson = jsonDecode(own['knowledgeJson'] as String) as Map;
    if (knowledgeJson.keys.any(
      (k) =>
          !const {
            'knownUpcomingCards',
            'radarObservations',
            'pendingCards',
          }.contains(k),
    )) {
      throw const FormatException('Secret private fields');
    }
    final knowledge = PlayerKnowledgeState.fromJson(knowledgeJson);
    if (hand.length > 4 ||
        hand.toSet().length != hand.length ||
        hand.length != rules.handCounts[side] ||
        knowledge.knownUpcomingCards.length > 3 ||
        knowledge.pendingCards.length > 3 ||
        knowledge.radarObservations.length > 24) {
      throw const FormatException('Invalid private information');
    }
    final clock = p['clock'];
    if (clock is! Map ||
        !const {'w', 'b'}.contains(clock['activeSide']) ||
        clock['startedAt'] is! int ||
        (clock['startedAt'] as int) < 0 ||
        clock['incrementMs'] != 2000 ||
        ['w', 'b'].any((s) => clock[s] is! int || (clock[s] as int) < 0) ||
        (response.containsKey('serverNow') &&
            (response['serverNow'] is! int ||
                (response['serverNow'] as int) < 0))) {
      throw const FormatException('Invalid clock');
    }
    p['clock'] = Map<String, dynamic>.unmodifiable(clock);
    if (result is Map) p['result'] = Map<String, dynamic>.unmodifiable(result);
    return BattleV1Snapshot._(
      id,
      version,
      PlayerView(rules, side, hand, knowledge),
      Map.unmodifiable(p),
      p['result'] as Map<String, dynamic>?,
      response['serverNow'] is int
          ? response['serverNow'] as int
          : clock['startedAt'] as int,
      own['settlementJson'] == null
          ? null
          : BattleV1Settlement.fromJson(
            jsonDecode(own['settlementJson'] as String) as Map,
            matchId: id,
            complete:
                p['result'] != null && p['settlementStatus'] == 'complete',
            rated: p['rated'] == true,
          ),
    );
  }
}

/// Read-only receipt from the already account-redacted server projection.
class BattleV1Settlement {
  final int trophyDelta, newTrophies;
  final bool rated;
  const BattleV1Settlement(this.trophyDelta, this.newTrophies, this.rated);
  factory BattleV1Settlement.fromJson(
    Map value, {
    required String matchId,
    required bool complete,
    required bool rated,
  }) {
    if (!complete ||
        value['matchId'] != matchId ||
        value['protocolVersion'] != battleV1Protocol ||
        value['rated'] != rated ||
        value['trophyDelta'] is! int ||
        value['newTrophies'] is! int ||
        (value['newTrophies'] as int) < 0 ||
        !rated && value['trophyDelta'] != 0) {
      throw const FormatException('Invalid V1 settlement receipt');
    }
    return BattleV1Settlement(
      value['trophyDelta'] as int,
      value['newTrophies'] as int,
      rated,
    );
  }
}

class BattleV1Controller extends ChangeNotifier {
  final String uid;
  final String matchId;
  final BattleV1Request request;
  final PendingIntentWriter persistPending;
  final bool Function()? isSessionCurrent;
  BattleV1Snapshot? snapshot;
  Map<String, dynamic>? _pending;
  bool busy = false;
  int synchronizationEpoch = 0;
  Object? error;
  bool _closed = false;
  bool _sessionInvalidated = false;
  bool _pendingPersisted = false;
  bool _pendingResolved = false;
  bool _invalidPending = false;
  Future<void>? _refreshFuture;
  bool _synchronizationRequested = false;
  int _generation = 0;
  int _clockNowAtSnapshot = 0;
  final Stopwatch _sinceSnapshot = Stopwatch()..start();
  BattleV1Controller({
    required this.uid,
    required this.matchId,
    required this.request,
    required this.persistPending,
    this.isSessionCurrent,
    String? pendingJson,
    bool pendingPersisted = true,
    Map<String, dynamic>? initialResponse,
  }) {
    if (initialResponse != null) {
      _accept(initialResponse);
    }
    if (pendingJson != null) {
      try {
        final raw = jsonDecode(pendingJson);
        if (raw is Map && _pendingEnvelope(raw, matchId)) {
          _pending = Map<String, dynamic>.from(raw);
          _pendingPersisted = pendingPersisted;
        } else {
          throw const FormatException('Invalid saved intent');
        }
      } on FormatException {
        _invalidPending = true;
        error = const FormatException('Invalid saved intent');
      }
    }
  }
  PlayerView? get view => snapshot?.player;
  List<BattleAction> get legalActions =>
      snapshot?.result != null || view == null
          ? const []
          : BattleRulesCore.legalActions(view!);
  bool get hasPendingIntent => _pending != null || _invalidPending;
  bool get refreshing => _refreshFuture != null;
  bool get _current => _ownsGeneration(_generation);

  bool _ownsGeneration(int generation) {
    if (_closed || _sessionInvalidated || generation != _generation) {
      return false;
    }
    if (isSessionCurrent?.call() == false) {
      invalidateSession();
      return false;
    }
    return true;
  }

  void invalidateSession() {
    if (_closed || _sessionInvalidated) return;
    _sessionInvalidated = true;
    _generation++;
    snapshot = null;
    busy = false;
    error = const BattleV1Rejection('session-changed');
    notifyListeners();
  }

  bool _accept(Map<String, dynamic> response) {
    final next = BattleV1Snapshot.fromResponse(response, uid);
    if (next.matchId != matchId) throw const FormatException('Wrong match');
    if (snapshot != null &&
        next.stateVersion == snapshot!.stateVersion &&
        next.serverNow < snapshot!.serverNow) {
      return false;
    }
    if (snapshot == null || next.stateVersion >= snapshot!.stateVersion) {
      final changed =
          snapshot == null ||
          next.stateVersion != snapshot!.stateVersion ||
          next.public['settlementStatus'] !=
              snapshot!.public['settlementStatus'] ||
          !mapEquals(next.result, snapshot!.result);
      final estimatedNow =
          snapshot == null
              ? next.serverNow
              : _clockNowAtSnapshot + _sinceSnapshot.elapsedMilliseconds;
      snapshot = next;
      // A cached response must not refund time already spent on this version.
      _clockNowAtSnapshot = max(next.serverNow, estimatedNow);
      _sinceSnapshot.reset();
      return changed;
    }
    return false;
  }

  int remainingMillis(String side) {
    final s = snapshot;
    if (s == null) return 0;
    final clock = s.public['clock'] as Map;
    final elapsed =
        s.result == null && clock['activeSide'] == side
            ? _clockNowAtSnapshot -
                (clock['startedAt'] as int) +
                _sinceSnapshot.elapsedMilliseconds
            : 0;
    return ((clock[side] as int) - elapsed.clamp(0, 0x7fffffff)).clamp(
      0,
      0x7fffffff,
    );
  }

  Future<void> reconnect({bool synchronization = true}) {
    if (!_current) return Future<void>.value();
    if (_refreshFuture case final running?) {
      _synchronizationRequested |= synchronization;
      return running;
    }
    if (busy) return Future<void>.value();
    _synchronizationRequested = synchronization;
    final completion = Completer<void>();
    final running = completion.future;
    _refreshFuture = running;
    unawaited(
      _reconnect(synchronization, running).then<void>(
        (_) => completion.complete(),
        onError: (Object cause, StackTrace stack) {
          completion.completeError(cause, stack);
        },
      ),
    );
    return running;
  }

  Future<void> _reconnect(bool synchronization, Future<void> running) async {
    final generation = _generation;
    final blocking = synchronization || snapshot == null;
    final previousError = error;
    var changed = false;
    if (blocking) {
      busy = true;
      if (!hasPendingIntent) error = null;
      notifyListeners();
    }
    try {
      if (!_ownsGeneration(generation)) return;
      final response = await request('/getBattleV1', {
        'matchId': matchId,
        'protocolVersion': battleV1Protocol,
      });
      if (!_ownsGeneration(generation)) return;
      changed = _accept(response);
      if (_synchronizationRequested) {
        synchronizationEpoch++;
        changed = true;
      }
      if (_invalidPending) {
        await _removePending(generation);
        if (!_ownsGeneration(generation)) return;
      }
      if (!hasPendingIntent) error = null;
    } catch (cause) {
      if (_ownsGeneration(generation)) error = cause;
    } finally {
      if (identical(_refreshFuture, running)) {
        _refreshFuture = null;
        _synchronizationRequested = false;
      }
      if (_ownsGeneration(generation)) {
        if (blocking) busy = false;
        if (blocking || changed || error != previousError) notifyListeners();
      }
    }
  }

  Future<bool> submit(BattleAction action) async {
    if (!_current || busy) return false;
    if (_refreshFuture case final running?) await running;
    if (!_current ||
        busy ||
        error != null ||
        snapshot == null ||
        hasPendingIntent ||
        snapshot!.result != null ||
        !BattleRulesCore.isLegalAction(snapshot!.player, action)) {
      return false;
    }
    final version = snapshot!.stateVersion;
    final nonce =
        List.generate(
          16,
          (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
    final intent = Map<String, dynamic>.from(action.toJson())
      ..removeWhere((_, value) => value == null);
    _pending = {
      'matchId': matchId,
      'protocolVersion': battleV1Protocol,
      'expectedStateVersion': version,
      'actionId': 'a${version}_$nonce',
      'intent': intent,
    };
    await retryPending();
    return _current &&
        _pending == null &&
        error == null &&
        snapshot!.stateVersion > version;
  }

  Future<void> retryPending() async {
    if (!_current || busy || !hasPendingIntent) return;
    if (_refreshFuture case final running?) await running;
    if (!_current || busy || !hasPendingIntent) return;
    final generation = _generation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (!_ownsGeneration(generation)) return;
      if (_pendingResolved || _invalidPending) {
        await _removePending(generation);
        return;
      }
      final body = Map<String, dynamic>.from(_pending!);
      if (!_pendingPersisted) {
        await persistPending(jsonEncode(body));
        if (!_ownsGeneration(generation)) return;
        _pendingPersisted = true;
      }
      if (!_ownsGeneration(generation)) return;
      final resign = (body['intent'] as Map)['type'] == 'resign';
      final payload = Map<String, dynamic>.from(body);
      if (resign) payload.remove('intent');
      final response = await request(
        resign ? '/resignBattleV1' : '/submitBattleV1Action',
        payload,
      );
      if (!_ownsGeneration(generation)) return;
      _accept(response);
      _pendingResolved = true;
      await _removePending(generation);
    } catch (cause) {
      if (_ownsGeneration(generation)) {
        error = cause;
        if (cause is BattleV1Rejection &&
            const {
              'STALE_STATE',
              'MATCH_TERMINAL',
              'MATCH_TIMEOUT',
              'INVALID_ACTION',
              'ACTION_ID_CONFLICT',
              'NOT_YOUR_TURN',
            }.contains(cause.code)) {
          _pendingResolved = true;
          try {
            await _removePending(generation);
          } catch (storageError) {
            if (_ownsGeneration(generation)) error = storageError;
          }
        }
      }
    } finally {
      if (_ownsGeneration(generation)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _removePending(int generation) async {
    if (!_ownsGeneration(generation)) return;
    await persistPending(null);
    if (!_ownsGeneration(generation)) return;
    _pending = null;
    _pendingPersisted = false;
    _pendingResolved = false;
    _invalidPending = false;
  }

  Future<void> resign() async {
    if (!_current || busy) return;
    if (_refreshFuture case final running?) await running;
    if (!_current ||
        busy ||
        error != null ||
        snapshot == null ||
        snapshot!.result != null ||
        hasPendingIntent) {
      return;
    }
    final version = snapshot!.stateVersion,
        nonce = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    _pending = {
      'matchId': matchId,
      'protocolVersion': battleV1Protocol,
      'expectedStateVersion': version,
      'actionId': 'a${version}_resign_$nonce',
      'intent': {'type': 'resign'},
    };
    await retryPending();
  }

  Future<void> clearRejectedPending() async {
    if (!_current || busy || !_pendingResolved) return;
    await retryPending();
    if (!_current || hasPendingIntent) return;
    await reconnect();
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    snapshot = null;
    _pending = null;
    _invalidPending = false;
    super.dispose();
  }
}
