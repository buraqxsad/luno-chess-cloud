import 'dart:async';
import 'package:flutter/foundation.dart';
import '../engine/piece.dart';
import '../models/player_data.dart';
import 'model.dart';
import 'online.dart';

class BattleEmoteEvent {
  final int sequence;
  final String emojiId;
  final PieceColor side;
  const BattleEmoteEvent(this.sequence, this.emojiId, this.side);
  factory BattleEmoteEvent.parse(Object? value) {
    if (value is! Map ||
        value['sequence'] is! int ||
        (value['sequence'] as int) < 1 ||
        !kEmojiIds.contains(value['emojiId']) ||
        !['w', 'b'].contains(value['side'])) {
      throw const FormatException('Invalid emote');
    }
    return BattleEmoteEvent(
      value['sequence'] as int,
      value['emojiId'] as String,
      parseSide(value['side'] as String),
    );
  }
}

class BattleEmoteChannel extends ChangeNotifier {
  final BattleV1Request? request;
  final String? matchId;
  final int Function()? monotonicMillis;
  final Stopwatch _time = Stopwatch()..start();
  bool _closed = false,
      _fetching = false,
      _sending = false,
      _initialized = false;
  bool muted = false, failed = false;
  int _cursor = 0, _lastSent = -3000;
  int _visibilityGeneration = 0;
  Timer? _expiry, _cooldown;
  final Map<PieceColor, BattleEmoteEvent> visible = {};
  final Set<int> _shown = {};
  BattleEmoteChannel({this.request, this.matchId, this.monotonicMillis});
  int get _now => monotonicMillis?.call() ?? _time.elapsedMilliseconds;
  bool get canSend => !_closed && !_sending && _now - _lastSent >= 3000;
  Map<String, dynamic> _body() => {
    'matchId': matchId,
    'protocolVersion': battleV1Protocol,
  };
  void setMuted(bool value) {
    if (_closed) return;
    muted = value;
    if (muted) {
      clear();
    } else {
      notifyListeners();
    }
  }

  void clear() {
    _visibilityGeneration++;
    _expiry?.cancel();
    visible.clear();
    if (!_closed) notifyListeners();
  }

  void _show(BattleEmoteEvent event, {bool display = true}) {
    if (_closed || !_shown.add(event.sequence)) return;
    if (_shown.length > 32) _shown.remove(_shown.first);
    if (muted || !display) return;
    visible[event.side] = event;
    _expiry?.cancel();
    _expiry = Timer(const Duration(milliseconds: 3600), () {
      if (!_closed) {
        visible.clear();
        notifyListeners();
      }
    });
    notifyListeners();
  }

  Future<void> fetch() async {
    if (_closed || _fetching || request == null) return;
    final visibilityGeneration = _visibilityGeneration;
    _fetching = true;
    try {
      final r = await request!('/getBattleV1Emotes', {
        ..._body(),
        'after': _cursor,
      });
      if (_closed) return;
      if (r['ok'] != true ||
          r['sequence'] is! int ||
          r['events'] is! List ||
          (r['events'] as List).length > 16) {
        throw const FormatException('Invalid emote feed');
      }
      final events = (r['events'] as List).map(BattleEmoteEvent.parse).toList();
      final sequence = r['sequence'] as int;
      if (sequence < _cursor || events.any((e) => e.sequence > sequence)) {
        return;
      }
      for (final event in events) {
        if (_initialized && event.sequence > _cursor) {
          _show(event, display: visibilityGeneration == _visibilityGeneration);
        }
      }
      _cursor = sequence;
      _initialized = true;
    } catch (_) {
      /* Optional emotes never stop a match or its reconnect path. */
    } finally {
      _fetching = false;
    }
  }

  Future<bool> send(String id, PieceColor side, Set<String> owned) async {
    if (!canSend || !owned.contains(id) || !kEmojiIds.contains(id)) {
      return false;
    }
    _sending = true;
    final visibilityGeneration = _visibilityGeneration;
    failed = false;
    notifyListeners();
    try {
      final event =
          request == null
              ? BattleEmoteEvent(++_cursor, id, side)
              : BattleEmoteEvent.parse(
                (await request!('/sendBattleV1Emote', {
                  ..._body(),
                  'emojiId': id,
                }))['event'],
              );
      if (_closed || event.side != side || event.emojiId != id) return false;
      _lastSent = _now;
      _cooldown?.cancel();
      _cooldown = Timer(const Duration(milliseconds: 3000), () {
        if (!_closed) notifyListeners();
      });
      // A first send is also a feed baseline; earlier server emotes are history.
      if (!_initialized) _cursor = event.sequence;
      _initialized = true;
      final display = visibilityGeneration == _visibilityGeneration;
      _show(event, display: display);
      return display;
    } catch (_) {
      if (!_closed) {
        failed = true;
        notifyListeners();
      }
      return false;
    } finally {
      _sending = false;
      if (!_closed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _closed = true;
    _cooldown?.cancel();
    clear();
    _time.stop();
    super.dispose();
  }
}
