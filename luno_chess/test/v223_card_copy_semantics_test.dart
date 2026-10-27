import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/battle_v1_copy.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';

void main() {
  for (final side in PieceColor.values) {
    test(
      '${side.name}: Watch Vow checks rook occupancy after castling, not the king destination',
      () {
        final deck = [
          CardId.watchVow,
          ...CardId.values.where((card) => card != CardId.watchVow).take(9),
        ];
        final initial = DeckManager.newBattle(
          board: Board.fromFen(
            side.isWhite
                ? '4k2r/8/8/8/8/8/4P3/4K3 w k - 0 10'
                : '4k3/4p3/8/8/8/8/8/4K2R b K - 0 10',
          ),
          white: deck,
          black: deck,
        );
        final draft =
            RuleDraft(initial.rules)
              ..phase = BattlePhase.card
              ..ownTurns = {PieceColor.white: 2, PieceColor.black: 2}
              ..mana = {side: 4, side.opposite: 6};
        var state = AuthoritativeBattleState(draft.freeze(), initial.hidden);
        final watched = side.isWhite ? 61 : 5;
        state = DeckManager.apply(
          state,
          PlayCardAction(CardId.watchVow, target: watched),
        );
        state = DeckManager.apply(
          state,
          ChessMoveAction(side.isWhite ? 'e2e3' : 'e7e6'),
        );
        state = DeckManager.apply(state, const PassAction());
        expect(state.rules.mana[side], 2);
        state = DeckManager.apply(
          state,
          ChessMoveAction(side.isWhite ? 'e8g8' : 'e1g1'),
        );
        expect(state.rules.board.pieceAt(watched)?.type, PieceType.rook);
        expect(state.rules.board.pieceAt(watched)?.color, side.opposite);
        expect(state.rules.board.pieceAt(watched + 1)?.type, PieceType.king);
        expect(
          state.rules.mana[side],
          5,
          reason: '+2 vow, then +1 next-turn mana',
        );
        expect(state.rules.vows, isEmpty);
      },
    );
  }

  for (final language in ['tr', 'en']) {
    test('$language: Watch Vow notice describes occupancy after the move', () {
      final l = LunoLocalizations(Locale(language));
      expect(
        l.battleCardOutcome(CardId.watchVow),
        language == 'tr'
            ? 'Rakibin sonraki taş hamlesi sonunda bu karede rakip taş varsa kartı oynayan +2 mana alır.'
            : 'The caster gains +2 mana if an opposing piece occupies this square after their next chess move.',
      );
    });
  }
}
