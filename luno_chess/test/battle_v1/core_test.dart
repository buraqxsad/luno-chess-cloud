import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/piece.dart';

const w = PieceColor.white, b = PieceColor.black;
AuthoritativeBattleState ready(List<CardId> cards, {String? fen}) {
  final deck =
      [
        ...cards,
        ...CardId.values.where((c) => !cards.contains(c)),
      ].take(10).toList();
  final s = DeckManager.newBattle(
    white: deck,
    board: fen == null ? null : Board.fromFen(fen),
  );
  final d = RuleDraft(s.rules)..phase = BattlePhase.card;
  d.ownTurns = {w: 2, b: 2};
  d.mana = {w: 6, b: 6};
  d.repetitions = {};
  return AuthoritativeBattleState(d.freeze(), s.hidden);
}

AuthoritativeBattleState edit(
  AuthoritativeBattleState s,
  void Function(RuleDraft) change,
) {
  final d = RuleDraft(s.rules);
  change(d);
  return AuthoritativeBattleState(d.freeze(), s.hidden);
}

bool has(AuthoritativeBattleState s, BattleAction action) =>
    BattleRulesCore.legalActions(
      s.view(s.rules.board.turn),
    ).any((a) => a.key == action.key);
AuthoritativeBattleState move(AuthoritativeBattleState s, String uci) =>
    DeckManager.apply(s, ChessMoveAction(uci));
AuthoritativeBattleState pass(AuthoritativeBattleState s) =>
    DeckManager.apply(s, const PassAction());
ActivePieceEffect pieceEffect(
  RuleState s,
  PieceEffectType type,
  int square, {
  String id = 'test',
  PieceColor owner = b,
  EffectDuration duration = EffectDuration.move,
}) => ActivePieceEffect(
  id: id,
  type: type,
  owner: owner,
  pieceId: s.pieceIds[square]!,
  responseSide: owner.opposite,
  duration: duration,
);
BoardEffectInstance boardEffect(
  BoardEffectType type,
  List<int> squares, {
  String id = 'test',
  PieceColor owner = b,
  EffectDuration duration = EffectDuration.move,
}) => BoardEffectInstance(
  id: id,
  type: type,
  owner: owner,
  squares: squares,
  responseSide: owner.opposite,
  duration: duration,
);

void main() {
  test('invalid initial boards are rejected at the authority boundary', () {
    for (final fen in [
      '7k/8/8/8/8/8/8/8 w - - 0 1',
      '7k/8/8/8/8/8/8/P3K3 w - - 0 1',
    ]) {
      expect(
        () => DeckManager.newBattle(board: Board.fromFen(fen)),
        throwsArgumentError,
      );
    }
  });
  test(
    'repetition API rejects card-committed and unresolved intermediate phases',
    () {
      final s = ready([CardId.prophecy]);
      expect(BattleRulesCore.publicFingerprint(s.rules), isNotEmpty);
      expect(
        () => BattleRulesCore.publicFingerprint(pass(s).rules),
        throwsStateError,
      );
      expect(
        () => BattleRulesCore.publicFingerprint(
          DeckManager.apply(s, const PlayCardAction(CardId.prophecy)).rules,
        ),
        throwsStateError,
      );
    },
  );
  test('malformed private reveals rejected before permutation generation', () {
    final s = DeckManager.apply(
      ready([CardId.prophecy]),
      const PlayCardAction(CardId.prophecy),
    );
    for (final pending in [s.hidden.decks[w]!, <CardId>[]]) {
      final view = PlayerView(
        s.rules,
        w,
        s.hidden.hands[w]!,
        s.hidden.knowledge[w]!.copyWith(pendingCards: pending),
      );
      expect(() => BattleRulesCore.legalActions(view), throwsStateError);
    }
  });
  test('terminal initial FENs have no actions', () {
    for (final (fen, reason) in [
      ('7k/6Q1/5K2/8/8/8/8/8 b - - 0 1', 'checkmate'),
      ('7k/5K2/6Q1/8/8/8/8/8 b - - 0 1', 'stalemate'),
      ('7k/8/8/8/8/8/8/R3K3 w - - 150 1', 'seventy_five_moves'),
    ]) {
      final s = DeckManager.newBattle(board: Board.fromFen(fen));
      expect(s.rules.terminal?.reason, reason);
      expect(BattleRulesCore.legalActions(s.view(s.rules.board.turn)), isEmpty);
    }
  });
  test(
    'finite deck never recycles; stabilized fivefold ends without drawing',
    () {
      var s = DeckManager.newBattle(
            board: Board.fromFen('6nk/8/8/8/8/8/8/KN6 w - - 0 1'),
          ),
          ply = 0;
      while (s.rules.phase != BattlePhase.terminal && ply < 60) {
        final side = s.rules.board.turn;
        if (s.rules.phase == BattlePhase.card) {
          s = DeckManager.apply(
            s,
            s.hidden.hands[side]!.isEmpty
                ? const PassAction()
                : DiscardAction(s.hidden.hands[side]!.first),
          );
        }
        s = move(s, ['b1c3', 'g8f6', 'c3b1', 'f6g8'][ply++ % 4]);
      }
      expect(s.rules.terminal?.reason, 'fivefold');
      expect(s.rules.drawCounts, {w: 10, b: 10});
      expect(s.rules.deckCounts, {w: 0, b: 0});
      expect(s.hidden.decks, {w: <CardId>[], b: <CardId>[]});
    },
  );
  test(
    'manifest costs/rarity/targets and starter match versioned contract',
    () {
      final contract =
          jsonDecode(
                File('../battle_contract/v1/cards.json').readAsStringSync(),
              )
              as Map;
      expect(
        cardDefinitions.values.map((c) => c.toJson()).toList(),
        contract['cards'],
      );
      expect(starterDeck.map((c) => c.wire).toList(), contract['starter']);
      expect(cardDefinitions.length, 24);
      expect(
        () => DeckManager.newBattle(white: starterDeck.skip(1).toList()),
        throwsArgumentError,
      );
      expect(
        () => DeckManager.newBattle(
          white: [...starterDeck.skip(1), CardId.prophecy],
        ),
        throwsArgumentError,
      );
      expect(() => CardId.parse('unknown'), throwsFormatException);
    },
  );
  test(
    'first own turns: chess only, 1 mana both, single draw, second turn increment',
    () {
      var s = DeckManager.newBattle();
      expect(s.rules.mana, {w: 1, b: 1});
      expect(s.hidden.hands[w]!.length, 3);
      expect(
        BattleRulesCore.legalActions(
          s.view(w),
        ).every((a) => a is ChessMoveAction),
        true,
      );
      for (final action in [
        const PassAction(),
        const DiscardAction(CardId.radar),
        const PlayCardAction(CardId.radar, target: 'radar'),
      ]) {
        expect(() => DeckManager.apply(s, action), throwsStateError);
      }
      s = move(s, 'e2e4');
      expect(s.rules.handCounts, {w: 4, b: 3});
      expect(s.rules.mana, {w: 1, b: 1});
      s = move(s, 'e7e5');
      expect(s.rules.phase, BattlePhase.card);
      expect(s.rules.mana, {w: 2, b: 1});
      expect(s.rules.deckCounts[w], 6);
    },
  );
  test(
    'discard free/permanent, one action, invalid action leaves exact input unchanged',
    () {
      final s = ready([CardId.radar]);
      final before = jsonEncode(s.toJson());
      final discarded = DeckManager.apply(s, const DiscardAction(CardId.radar));
      expect(discarded.rules.mana[w], 6);
      expect(discarded.rules.discarded[w], [CardId.radar]);
      expect(discarded.rules.fen, s.rules.fen);
      expect(
        () => DeckManager.apply(discarded, const PassAction()),
        throwsStateError,
      );
      expect(jsonEncode(s.toJson()), before);
      expect(
        move(discarded, 'e2e4').hidden.decks[w]!.contains(CardId.radar),
        false,
      );
    },
  );
  test('insufficient mana and king target are atomic', () {
    final s = edit(ready([CardId.freeze]), (d) => d.mana[w] = 3),
        before = jsonEncode(
          edit(ready([CardId.freeze]), (d) => d.mana[w] = 3).toJson(),
        );
    expect(
      () =>
          DeckManager.apply(s, const PlayCardAction(CardId.freeze, target: 48)),
      throwsStateError,
    );
    expect(
      () =>
          DeckManager.apply(s, const PlayCardAction(CardId.freeze, target: 60)),
      throwsStateError,
    );
    expect(s.rules.used[w], isEmpty);
    expect(s.rules.mana[w], 3);
    expect(jsonEncode(s.toJson()), before);
  });
  for (final (card, fen, from, uci) in [
    (CardId.pawnDeviation, '7k/8/8/8/8/4P3/8/4K3 w - - 0 1', 20, 'e3d4'),
    (CardId.pawnAdvance, '7k/8/8/8/8/4P3/8/4K3 w - - 0 1', 20, 'e3e5'),
    (CardId.rookBend, '7k/8/8/8/8/8/8/R3K3 w Q - 0 1', 0, 'a1b2'),
    (CardId.angryN, '7k/8/8/8/8/8/8/1N2K3 w - - 0 1', 1, 'b1b2'),
    (CardId.shadowPass, '7k/8/8/8/8/P7/8/R3K3 w Q - 0 1', 0, 'a1a4'),
  ]) {
    test('${card.wire} binds mandatory move and disallows alternate piece', () {
      final s = ready([card], fen: fen),
          a = DeckManager.apply(s, PlayCardAction(card, target: from));
      expect(a.rules.special?.from, from);
      expect(has(a, ChessMoveAction(uci)), true);
      expect(() => move(a, 'e1d1'), throwsStateError);
      expect(() => move(a, 'e1f1'), throwsStateError);
      final after = move(a, uci);
      expect(after.rules.special, isNull);
      expect(after.rules.board.enPassant, isNull);
      if (card == CardId.rookBend || card == CardId.shadowPass) {
        expect(after.rules.board.castling, 0);
      }
    });
  }
  test('Piyon Atilimi distinguishes standard and card-granted doubles', () {
    var s = ready([CardId.pawnAdvance]);
    s = DeckManager.apply(
      s,
      const PlayCardAction(CardId.pawnAdvance, target: 12),
    );
    s = move(s, 'e2e4');
    expect(s.rules.board.enPassant, 20);
    var t = ready([CardId.pawnAdvance], fen: '7k/8/8/8/8/4P3/8/4K3 w - - 99 1');
    t = DeckManager.apply(
      t,
      const PlayCardAction(CardId.pawnAdvance, target: 20),
    );
    t = move(t, 'e3e5');
    expect(t.rules.board.enPassant, isNull);
    expect(t.rules.board.halfmoveClock, 0);
  });
  test(
    'special moves enforce pin, check resolution and no special promotion',
    () {
      final s = ready([
        CardId.pawnDeviation,
      ], fen: 'k3r3/8/8/8/8/8/4P3/4K3 w - - 0 1');
      expect(
        BattleRulesCore.specialMoves(s.rules, CardId.pawnDeviation, 12, w),
        isEmpty,
      );
      final t = ready([
        CardId.pawnAdvance,
      ], fen: '7k/4P3/8/8/8/8/8/4K3 w - - 0 1');
      expect(
        BattleRulesCore.specialMoves(t.rules, CardId.pawnAdvance, 52, w),
        isEmpty,
      );
      final check = ready([
        CardId.radar,
      ], fen: 'k3r3/8/8/8/8/8/3P4/4K3 w - - 0 1');
      final after = DeckManager.apply(
        check,
        const PlayCardAction(CardId.radar, target: 'radar'),
      );
      expect(() => move(after, 'd2d3'), throwsStateError);
      expect(has(after, const ChessMoveAction('e1d1')), true);
    },
  );
  for (final type in [
    BoardEffectType.lockedSquare,
    BoardEffectType.boardSeal,
  ]) {
    test(
      '${type.name} empty destination only, captures/promotions allowed, EP blocked and king immune',
      () {
        final s = edit(
          ready([CardId.radar], fen: '7k/8/8/8/8/8/p7/R3K3 w - - 0 1'),
          (d) {
            d.phase = BattlePhase.chess;
            d.boardEffects.add(boardEffect(type, [8, 1, 5]));
          },
        );
        expect(has(s, const ChessMoveAction('a1a2')), true);
        expect(has(s, const ChessMoveAction('a1b1')), false);
        expect(has(s, const ChessMoveAction('e1f1')), true);
        final ep = edit(
          ready([CardId.radar], fen: '7k/8/8/3pP3/8/8/8/4K3 w - d6 0 1'),
          (d) {
            d.phase = BattlePhase.chess;
            d.boardEffects.add(boardEffect(type, [43]));
          },
        );
        expect(has(ep, const ChessMoveAction('e5d6')), false);
        final promotion = edit(
          ready([CardId.radar], fen: 'k6r/6P1/8/8/8/8/8/4K3 w - - 0 1'),
          (d) {
            d.phase = BattlePhase.chess;
            d.boardEffects.add(boardEffect(type, [62, 63]));
          },
        );
        expect(has(promotion, const ChessMoveAction('g7g8q')), false);
        expect(has(promotion, const ChessMoveAction('g7h8n')), true);
      },
    );
  }
  test('castling rook restrictions and king immunity', () {
    final original = ready([
      CardId.radar,
    ], fen: '4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1');
    final slowed = edit(original, (d) {
      d.phase = BattlePhase.chess;
      d.pieceEffects.add(
        pieceEffect(original.rules, PieceEffectType.slow, 0, id: 'a'),
      );
      d.pieceEffects.add(
        pieceEffect(original.rules, PieceEffectType.slow, 7, id: 'h'),
      );
    });
    expect(has(slowed, const ChessMoveAction('e1g1')), true);
    expect(has(slowed, const ChessMoveAction('e1c1')), false);
    final frozen = edit(
      slowed,
      (d) => d.pieceEffects.add(
        pieceEffect(original.rules, PieceEffectType.freeze, 7),
      ),
    );
    expect(has(frozen, const ChessMoveAction('e1g1')), false);
    final kingZone = edit(original, (d) {
      d.phase = BattlePhase.chess;
      d.boardEffects.add(boardEffect(BoardEffectType.lockedSquare, [6]));
    });
    expect(has(kingZone, const ChessMoveAction('e1g1')), true);
    final rookZone = edit(
      kingZone,
      (d) => d.boardEffects.add(
        boardEffect(BoardEffectType.boardSeal, [5], id: 'rook'),
      ),
    );
    expect(has(rookZone, const ChessMoveAction('e1g1')), false);
  });
  test(
    'Mine and watch simultaneous on castling rook; new debuff survives; king immune',
    () {
      final s = edit(
        ready([CardId.radar], fen: '4k3/8/8/8/8/8/8/4K2R w K - 0 1'),
        (d) {
          d.phase = BattlePhase.chess;
          d.mana[b] = 1;
          d.boardEffects.add(
            boardEffect(BoardEffectType.mine, [
              5,
            ], duration: EffectDuration.persistent),
          );
          d.vows.add(
            const VowState(
              id: 'v',
              type: VowType.watch,
              owner: b,
              pieceId: null,
              square: 5,
              remainingMoves: 1,
            ),
          );
        },
      );
      final after = move(s, 'e1g1');
      expect(after.rules.boardEffects, isEmpty);
      expect(after.rules.vows, isEmpty);
      expect(after.rules.pieceEffects.single.type, PieceEffectType.mineDebuff);
      expect(after.rules.mana[b], 4);
      final k = edit(
        ready([CardId.radar], fen: '7k/8/8/8/8/8/8/4K3 w - - 0 1'),
        (d) {
          d.phase = BattlePhase.chess;
          d.boardEffects.add(
            boardEffect(BoardEffectType.mine, [
              5,
            ], duration: EffectDuration.persistent),
          );
        },
      );
      final kt = move(k, 'e1f1');
      expect(kt.rules.boardEffects.length, 1);
      expect(kt.rules.pieceEffects, isEmpty);
    },
  );
  test(
    'Mine debuff persists across other-piece moves and expires only on affected-piece noncapture',
    () {
      final original = ready([
        CardId.radar,
      ], fen: '7k/8/8/8/8/8/p7/R3K3 w - - 0 1');
      var s = edit(original, (d) {
        d.phase = BattlePhase.chess;
        d.pieceEffects.add(
          pieceEffect(
            original.rules,
            PieceEffectType.mineDebuff,
            0,
            duration: EffectDuration.pieceMove,
          ),
        );
      });
      expect(has(s, const ChessMoveAction('a1a2')), false);
      s = move(s, 'e1f1');
      expect(s.rules.pieceEffects.length, 1);
      s = move(pass(s), 'h8g8');
      s = move(pass(s), 'a1b1');
      expect(s.rules.pieceEffects, isEmpty);
    },
  );
  test('response-window freeze/chain/slow expire after other-piece move', () {
    final original = ready([CardId.radar]);
    final s = edit(original, (d) {
      d.phase = BattlePhase.chess;
      for (final (type, square) in [
        (PieceEffectType.freeze, 0),
        (PieceEffectType.chain, 1),
        (PieceEffectType.slow, 3),
      ]) {
        d.pieceEffects.add(
          pieceEffect(original.rules, type, square, id: type.name),
        );
      }
    });
    expect(move(s, 'e2e4').rules.pieceEffects, isEmpty);
  });
  test(
    'Muhur Bozma only one opposing board instance, overlap and own Mine preserved',
    () {
      final s = edit(ready([CardId.breakSeal, CardId.mine]), (d) {
        d.boardEffects.add(
          boardEffect(
            BoardEffectType.mine,
            [20],
            id: 'mine',
            owner: w,
            duration: EffectDuration.persistent,
          ),
        );
        d.boardEffects.add(
          boardEffect(BoardEffectType.lockedSquare, [20], id: 'lock'),
        );
        d.boardEffects.add(
          boardEffect(BoardEffectType.boardSeal, [20, 21, 28, 29], id: 'seal'),
        );
      });
      expect(
        BattleRulesCore.cardTargets(
          s.view(w),
          CardId.breakSeal,
        ).contains('mine'),
        false,
      );
      expect(BattleRulesCore.cardTargets(s.view(w), CardId.mine), isEmpty);
      final after = DeckManager.apply(
        s,
        const PlayCardAction(CardId.breakSeal, target: 'lock'),
      );
      expect(after.rules.boardEffects.map((e) => e.id).toList(), [
        'mine',
        'seal',
      ]);
    },
  );
  test(
    'Siper and Sis block direct cards not chess capture; Arinma removes only selected effect',
    () {
      final original = ready([
        CardId.freeze,
      ], fen: '7k/8/8/8/8/8/p7/R3K3 w - - 0 1');
      final s = edit(
        original,
        (d) => d.pieceEffects.add(
          pieceEffect(
            original.rules,
            PieceEffectType.shelter,
            8,
            owner: b,
            duration: EffectDuration.card,
          ),
        ),
      );
      expect(
        BattleRulesCore.cardTargets(s.view(w), CardId.freeze).contains(8),
        false,
      );
      expect(
        has(
          edit(s, (d) => d.phase = BattlePhase.chess),
          const ChessMoveAction('a1a2'),
        ),
        true,
      );
      final own = ready([CardId.purify]);
      final dirty = edit(own, (d) {
        d.pieceEffects.add(
          pieceEffect(own.rules, PieceEffectType.chain, 0, id: 'chain'),
        );
        d.pieceEffects.add(
          pieceEffect(own.rules, PieceEffectType.slow, 0, id: 'slow'),
        );
      });
      expect(
        DeckManager.apply(
          dirty,
          const PlayCardAction(CardId.purify, target: 'chain'),
        ).rules.pieceEffects.single.id,
        'slow',
      );
      final fog = edit(
        ready([CardId.freeze]),
        (d) => d.boardEffects.add(
          boardEffect(BoardEffectType.fog, [
            48,
            49,
            56,
            57,
          ], duration: EffectDuration.card),
        ),
      );
      expect(
        BattleRulesCore.cardTargets(fog.view(w), CardId.freeze).contains(48),
        false,
      );
    },
  );
  test('Radar private positive/negative, negative stales on opponent draw', () {
    final s = ready([CardId.radar]);
    final positive = DeckManager.apply(
      s,
      const PlayCardAction(CardId.radar, target: 'radar'),
    );
    expect(positive.hidden.knowledge[w]!.radarObservations.single.inHand, true);
    expect(positive.view(b).knowledge.radarObservations, isEmpty);
    var negative = DeckManager.apply(
      s,
      const PlayCardAction(CardId.radar, target: 'purify'),
    );
    expect(
      negative.hidden.knowledge[w]!.radarObservations.single.inHand,
      false,
    );
    negative = move(negative, 'e2e4');
    negative = move(pass(negative), 'e7e5');
    expect(negative.hidden.knowledge[w]!.radarObservations.single.stale, true);
  });
  test(
    'Kehanet pending blocks other actions, no immediate draw, reveal2/order/shift',
    () {
      var s = DeckManager.apply(
        ready([CardId.prophecy]),
        const PlayCardAction(CardId.prophecy),
      );
      expect(s.rules.phase, BattlePhase.pending);
      expect(s.hidden.knowledge[w]!.pendingCards.length, 2);
      expect(() => move(s, 'e2e4'), throwsStateError);
      expect(() => pass(s), throwsStateError);
      final ordered = s.hidden.knowledge[w]!.pendingCards.reversed.toList();
      s = DeckManager.apply(s, ResolveAction(ordered));
      expect(s.rules.handCounts[w], 2);
      expect(s.hidden.knowledge[w]!.knownUpcomingCards, ordered);
      s = move(s, 'e2e4');
      expect(s.hidden.hands[w]!.last, ordered.first);
      expect(
        s.hidden.knowledge[w]!.knownUpcomingCards,
        ordered.skip(1).toList(),
      );
    },
  );
  test(
    'Kader Takasi sacrifice, inspect3 max, selected1, known remaining order, end draw',
    () {
      var s = DeckManager.apply(
        ready([CardId.fateExchange, CardId.radar]),
        const PlayCardAction(CardId.fateExchange, sacrifice: CardId.radar),
      );
      final inspected = s.hidden.knowledge[w]!.pendingCards;
      expect(inspected.length, 3);
      final selected = inspected[1], order = [inspected[2], inspected[0]];
      s = DeckManager.apply(s, ResolveAction(order, selected: selected));
      expect(s.hidden.hands[w]!.contains(selected), true);
      expect(s.rules.discarded[w], [CardId.radar]);
      expect(s.hidden.decks[w]!.take(2).toList(), order);
      final count = s.rules.drawCounts[w]!;
      s = move(s, 'e2e4');
      expect(s.rules.drawCounts[w], count + 1);
    },
  );
  test(
    'cost discount min1/sabotage; card lock permits discard; echo exact PLAY only',
    () {
      final s = edit(ready([CardId.freeze, CardId.radar]), (d) {
        d.mana[b] = 1;
        d.modifiers.addAll([
          const PendingModifier(
            id: 'd',
            type: ModifierType.discount,
            owner: w,
            responseSide: w,
            targetCard: null,
            ownTurn: 2,
          ),
          const PendingModifier(
            id: 's',
            type: ModifierType.manaSabotage,
            owner: b,
            responseSide: w,
            targetCard: CardId.freeze,
            ownTurn: 2,
          ),
          const PendingModifier(
            id: 'e',
            type: ModifierType.echo,
            owner: b,
            responseSide: w,
            targetCard: CardId.radar,
            ownTurn: 2,
          ),
        ]);
      });
      expect(BattleRulesCore.effectiveCost(s.rules, w, CardId.freeze), 3);
      expect(BattleRulesCore.effectiveCost(s.rules, w, CardId.radar), 1);
      final discarded = DeckManager.apply(s, const DiscardAction(CardId.radar));
      expect(discarded.rules.mana[b], 1);
      expect(discarded.rules.modifiers, isEmpty);
      expect(
        DeckManager.apply(
          s,
          const PlayCardAction(CardId.radar, target: 'radar'),
        ).rules.mana[b],
        3,
      );
      final locked = edit(
        s,
        (d) => d.modifiers.add(
          const PendingModifier(
            id: 'l',
            type: ModifierType.cardBlock,
            owner: b,
            responseSide: w,
            targetCard: CardId.radar,
            ownTurn: 2,
          ),
        ),
      );
      expect(
        has(locked, const PlayCardAction(CardId.radar, target: 'radar')),
        false,
      );
      expect(has(locked, const DiscardAction(CardId.radar)), true);
      final c = DeckManager.apply(
        ready([CardId.shadowContract, CardId.radar]),
        const PlayCardAction(CardId.shadowContract, sacrifice: CardId.radar),
      );
      expect(c.rules.modifiers.single.ownTurn, 3);
      expect(c.rules.mana[w], 5);
    },
  );
  test('Hunt normal capture reward, special capture no reward', () {
    var s = DeckManager.apply(
      ready([CardId.huntVow], fen: '7k/8/8/8/8/8/p7/R3K3 w - - 0 1'),
      const PlayCardAction(CardId.huntVow, target: 8),
    );
    s = move(s, 'a1a2');
    expect(s.rules.mana[w], 6);
    expect(s.rules.vows, isEmpty);
    final original = ready([
      CardId.angryN,
    ], fen: '7k/8/8/8/8/8/1p6/1N2K3 w - - 0 1');
    var t = edit(
      original,
      (d) => d.vows.add(
        VowState(
          id: 'v',
          type: VowType.hunt,
          owner: w,
          pieceId: original.rules.pieceIds[9],
          square: null,
          remainingMoves: 2,
        ),
      ),
    );
    t = DeckManager.apply(t, const PlayCardAction(CardId.angryN, target: 1));
    t = move(t, 'b1b2');
    expect(t.rules.mana[w], 3);
    expect(t.rules.vows, isEmpty);
  });
  test('terminal only after chess move; mate/stalemate draw suppressed', () {
    var s = DeckManager.apply(
      ready([CardId.radar], fen: '7k/8/5KQ1/8/8/8/8/8 w - - 0 1'),
      const PlayCardAction(CardId.radar, target: 'radar'),
    );
    expect(s.rules.terminal, isNull);
    final count = s.rules.drawCounts[w];
    s = move(s, 'g6g7');
    expect(s.rules.terminal?.reason, 'checkmate');
    expect(s.rules.drawCounts[w], count);
    final t = move(
      pass(ready([CardId.radar], fen: '7k/5K2/8/6Q1/8/8/8/8 w - - 0 1')),
      'g5g6',
    );
    expect(t.rules.terminal?.reason, 'stalemate');
    expect(t.rules.drawCounts[w], 3);
  });
  test(
    'redacted bot input, immutable states, exact serialization roundtrip',
    () {
      var s = DeckManager.newBattle();
      expect(
        () => s.hidden.decks[w]!.add(CardId.radar),
        throwsUnsupportedError,
      );
      expect(() => s.rules.mana[w] = 6, throwsUnsupportedError);
      expect(
        AuthoritativeBattleState.fromJson(
          jsonDecode(jsonEncode(s.toJson())) as Map,
        ).toJson(),
        s.toJson(),
      );
      for (var i = 0; i < 40 && s.rules.phase != BattlePhase.terminal; i++) {
        final view = s.view(s.rules.board.turn),
            action = BattleRulesCore.chooseBotAction(view);
        expect(action, isNotNull);
        expect(has(s, action!), true);
        expect(view.toJson().containsKey('decks'), false);
        expect(view.toJson().containsKey('opponentHand'), false);
        s = DeckManager.apply(s, action);
      }
    },
  );
  for (final card in CardId.values) {
    test('${card.wire} successful rule resolution', () {
      var s = ready([
        card,
      ], fen: '4k3/1p2r3/8/8/3p4/2P1B3/PP1N4/R3K2R w KQ - 0 1');
      if (card == CardId.purify) {
        final original = s;
        s = edit(
          s,
          (d) => d.pieceEffects.add(
            pieceEffect(original.rules, PieceEffectType.chain, 0),
          ),
        );
      }
      if (card == CardId.breakSeal) {
        s = edit(
          s,
          (d) => d.boardEffects.add(
            boardEffect(BoardEffectType.mine, [
              20,
            ], duration: EffectDuration.persistent),
          ),
        );
      }
      final candidates =
          BattleRulesCore.legalActions(
            s.view(w),
          ).whereType<PlayCardAction>().where((a) => a.card == card).toList();
      expect(candidates, isNotEmpty, reason: card.wire);
      s = DeckManager.apply(s, candidates.first);
      expect(s.rules.used[w]!.contains(card), true);
      if (s.rules.phase == BattlePhase.pending) {
        s = DeckManager.apply(s, BattleRulesCore.legalActions(s.view(w)).first);
      }
      expect(s.rules.phase, BattlePhase.chess);
      expect(s.rules.pending, isNull);
    });
  }
  test(
    'zero/one/two deck cards: secret-card preconditions and bounded inspection',
    () {
      for (final count in [0, 1, 2]) {
        for (final card in [CardId.prophecy, CardId.fateExchange]) {
          final original = ready([card, CardId.radar]);
          final decks = {
            w: original.hidden.decks[w]!.take(count).toList(),
            b: original.hidden.decks[b]!,
          };
          var s = edit(original, (d) {
            d.deckCounts[w] = count;
            d.discarded[w]!.addAll(original.hidden.decks[w]!.skip(count));
            d.discarded[w]!.sort((a, b) => a.wire.compareTo(b.wire));
          });
          s = AuthoritativeBattleState(
            s.rules,
            AuthoritativeHiddenState(
              hands: s.hidden.hands,
              decks: decks,
              knowledge: s.hidden.knowledge,
            ),
          );
          final plays =
              BattleRulesCore.legalActions(s.view(w))
                  .whereType<PlayCardAction>()
                  .where((a) => a.card == card)
                  .toList();
          expect(plays.isNotEmpty, count > 0);
          if (count > 0) {
            s = DeckManager.apply(s, plays.first);
            expect(s.hidden.knowledge[w]!.pendingCards.length, count);
            s = DeckManager.apply(
              s,
              BattleRulesCore.legalActions(s.view(w)).first,
            );
            expect(s.rules.phase, BattlePhase.chess);
          }
        }
      }
    },
  );
  test(
    'positive Radar persists through draws and stales on public discard',
    () {
      var s = DeckManager.apply(
        ready([CardId.radar]),
        const PlayCardAction(CardId.radar, target: 'radar'),
      );
      s = move(s, 'e2e4');
      s = move(pass(s), 'e7e5');
      expect(s.hidden.knowledge[w]!.radarObservations.single.stale, false);
      s = move(pass(s), 'g1f3');
      s = DeckManager.apply(s, const DiscardAction(CardId.radar));
      expect(s.hidden.knowledge[w]!.radarObservations.single.stale, true);
    },
  );
  test(
    'assisted mate/stalemate flags need a real restriction-eliminated defense',
    () {
      final a = ready([CardId.freeze], fen: '7k/r7/5KQ1/8/8/8/8/8 w - - 0 1');
      final mate = move(
        DeckManager.apply(a, const PlayCardAction(CardId.freeze, target: 48)),
        'g6g7',
      );
      expect(mate.rules.terminal?.mateByRestriction, true);
      expect(mate.rules.terminal?.mateBySpecialMove, false);
      expect(move(pass(a), 'g6g7').rules.terminal, isNull);
      final c = ready([CardId.freeze], fen: 'r6k/5K2/8/6Q1/8/8/8/8 w - - 0 1');
      final stale = move(
        DeckManager.apply(c, const PlayCardAction(CardId.freeze, target: 56)),
        'g5g6',
      );
      expect(stale.rules.terminal?.stalemateByRestriction, true);
      expect(stale.rules.terminal?.reason, 'stalemate');
    },
  );
  test(
    'Shadow Pass cannot cross own king or enemy; knight cannot capture king',
    () {
      for (final fen in [
        '7k/8/8/8/8/K7/8/R7 w - - 0 1',
        '7k/8/8/8/8/p7/8/R3K3 w - - 0 1',
      ]) {
        final s = ready([CardId.shadowPass], fen: fen);
        expect(
          BattleRulesCore.specialMoves(s.rules, CardId.shadowPass, 0, w),
          isEmpty,
        );
      }
      final n = ready([CardId.angryN], fen: '8/8/8/8/8/8/1k6/1N2K3 w - - 0 1');
      expect(
        BattleRulesCore.specialMoves(
          n.rules,
          CardId.angryN,
          1,
          w,
        ).any((m) => m.uci == 'b1b2'),
        false,
      );
    },
  );
}
