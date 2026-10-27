import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/emotes.dart';
import 'package:luno_chess/engine/piece.dart';

Map<String, dynamic> emote(int sequence, {String side = 'b'}) => {
  'sequence': sequence,
  'emojiId': 'smile',
  'side': side,
};

void main() {
  test(
    'first send establishes a baseline without replaying earlier emotes',
    () async {
      int? requestedAfter;
      final channel = BattleEmoteChannel(
        matchId: 'match',
        request: (route, body) async {
          if (route == '/sendBattleV1Emote') {
            return {'ok': true, 'event': emote(10, side: 'w')};
          }
          requestedAfter = body['after'] as int;
          return {
            'ok': true,
            'sequence': 10,
            'events': [emote(9), emote(10, side: 'w')],
          };
        },
      );
      addTearDown(channel.dispose);
      expect(await channel.send('smile', PieceColor.white, {'smile'}), isTrue);
      await channel.fetch();
      expect(requestedAfter, 10);
      expect(channel.visible.keys, [PieceColor.white]);
    },
  );

  test('mute and unmute invalidate a feed already in flight', () async {
    final pending = Completer<Map<String, dynamic>>();
    var calls = 0;
    final channel = BattleEmoteChannel(
      matchId: 'match',
      request:
          (_, _) async =>
              ++calls == 1
                  ? {'ok': true, 'sequence': 0, 'events': []}
                  : pending.future,
    );
    addTearDown(channel.dispose);
    await channel.fetch();
    final fetch = channel.fetch();
    channel.setMuted(true);
    channel.setMuted(false);
    pending.complete({
      'ok': true,
      'sequence': 1,
      'events': [emote(1)],
    });
    await fetch;
    expect(channel.visible, isEmpty);
  });

  test(
    'mute and unmute suppress late send display but retain cooldown',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      final channel = BattleEmoteChannel(
        matchId: 'match',
        request: (_, _) => pending.future,
      );
      addTearDown(channel.dispose);
      final send = channel.send('smile', PieceColor.white, {'smile'});
      channel.setMuted(true);
      channel.setMuted(false);
      pending.complete({'ok': true, 'event': emote(1, side: 'w')});
      expect(await send, isFalse);
      expect(channel.visible, isEmpty);
      expect(channel.canSend, isFalse);
    },
  );

  test(
    'send on an initialized feed does not discard unseen opponent emotes',
    () async {
      var feedCalls = 0;
      int? requestedAfter;
      final channel = BattleEmoteChannel(
        matchId: 'match',
        request: (route, body) async {
          if (route == '/sendBattleV1Emote') {
            return {'ok': true, 'event': emote(3, side: 'w')};
          }
          requestedAfter = body['after'] as int;
          if (++feedCalls == 1) {
            return {'ok': true, 'sequence': 0, 'events': []};
          }
          return {
            'ok': true,
            'sequence': 3,
            'events': [emote(1), emote(2), emote(3, side: 'w')],
          };
        },
      );
      addTearDown(channel.dispose);
      await channel.fetch();
      expect(await channel.send('smile', PieceColor.white, {'smile'}), isTrue);
      await channel.fetch();
      expect(requestedAfter, 0);
      expect(channel.visible[PieceColor.black]?.sequence, 2);
      expect(channel.visible[PieceColor.white]?.sequence, 3);
    },
  );
}
