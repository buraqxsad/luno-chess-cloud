import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/hotseat_privacy.dart';
import 'package:luno_chess/engine/piece.dart';

void main() {
  test(
    'each player and each foreground entry needs a fresh acknowledgement',
    () {
      final privacy = BattleHotseatPrivacy();
      addTearDown(privacy.dispose);
      expect(privacy.revealed, isFalse);
      expect(privacy.observe(PieceColor.white), isTrue);
      final firstEpoch = privacy.epoch;
      expect(privacy.acknowledge(PieceColor.black, firstEpoch), isFalse);
      expect(privacy.acknowledge(PieceColor.white, firstEpoch), isTrue);
      expect(privacy.observe(PieceColor.white), isFalse);
      expect(privacy.revealed, isTrue);

      expect(privacy.observe(PieceColor.black), isTrue);
      expect(privacy.revealed, isFalse);
      expect(privacy.acknowledge(PieceColor.white, firstEpoch), isFalse);
      expect(privacy.acknowledge(PieceColor.black, privacy.epoch), isTrue);
      final beforeBackground = privacy.epoch;
      privacy.conceal();
      expect(privacy.revealed, isFalse);
      expect(privacy.acknowledge(PieceColor.black, beforeBackground), isFalse);
      expect(privacy.acknowledge(PieceColor.black, privacy.epoch), isTrue);
    },
  );

  test(
    'double acknowledgement and pre-restart callbacks cannot reveal a hand',
    () {
      final privacy = BattleHotseatPrivacy();
      addTearDown(privacy.dispose);
      privacy.observe(PieceColor.white);
      final oldEpoch = privacy.epoch;
      expect(privacy.acknowledge(PieceColor.white, oldEpoch), isTrue);
      expect(privacy.acknowledge(PieceColor.white, oldEpoch), isFalse);
      privacy.reset();
      privacy.observe(PieceColor.white);
      expect(privacy.acknowledge(PieceColor.white, oldEpoch), isFalse);
      expect(privacy.revealed, isFalse);
      expect(privacy.acknowledge(PieceColor.white, privacy.epoch), isTrue);
    },
  );
}
