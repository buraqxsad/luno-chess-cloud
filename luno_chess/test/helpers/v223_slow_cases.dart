import 'dart:convert';

import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_ui/accepted_frames.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/move_gen.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/engine/square.dart';

typedef SlowVerify = void Function(bool condition, String reason);

class SlowAuditCase {
  final String name;
  final void Function(SlowVerify verify) run;
  const SlowAuditCase(this.name, this.run);
}

int slowSquare(String square) =>
    Square.of(square.codeUnitAt(0) - 97, int.parse(square[1]) - 1);

List<CardId> _deck(List<CardId> first) =>
    [
      ...first,
      ...CardId.values.where((card) => !first.contains(card)),
    ].take(10).toList();

AuthoritativeBattleState slowReady(
  String fen, {
  List<CardId> white = const [CardId.slow, CardId.mine, CardId.radar],
  List<CardId> black = const [
    CardId.purify,
    CardId.rookBend,
    CardId.shadowPass,
  ],
  BattlePhase phase = BattlePhase.card,
  int mana = 6,
}) {
  final initial = DeckManager.newBattle(
    board: Board.fromFen(fen),
    white: _deck(white),
    black: _deck(black),
  );
  final draft =
      RuleDraft(initial.rules)
        ..phase = phase
        ..ownTurns = {for (final side in PieceColor.values) side: 3}
        ..mana = {for (final side in PieceColor.values) side: mana}
        ..repetitions = {};
  return AuthoritativeBattleState(draft.freeze(), initial.hidden);
}

AuthoritativeBattleState slowEdit(
  AuthoritativeBattleState state,
  void Function(RuleDraft draft) edit,
) {
  final draft = RuleDraft(state.rules);
  edit(draft);
  return AuthoritativeBattleState(draft.freeze(), state.hidden);
}

ActivePieceEffect slowEffect(
  RuleState rules,
  String square, {
  PieceEffectType type = PieceEffectType.slow,
  String id = 'audit-slow',
}) {
  final index = slowSquare(square);
  final side = rules.board.pieceAt(index)!.color;
  return ActivePieceEffect(
    id: id,
    type: type,
    owner: side.opposite,
    pieceId: rules.pieceIds[index]!,
    responseSide: side,
    duration:
        type == PieceEffectType.mineDebuff
            ? EffectDuration.pieceMove
            : EffectDuration.move,
  );
}

Set<String> slowMoves(AuthoritativeBattleState state, PieceColor side) =>
    BattleRulesCore.legalMoves(
      state.rules,
      side,
      authorization: state.rules.special,
    ).map((move) => move.uci).toSet();

bool slowHas(AuthoritativeBattleState state, BattleAction action) =>
    BattleRulesCore.isLegalAction(state.view(state.rules.board.turn), action);

AuthoritativeBattleState slowMove(AuthoritativeBattleState state, String uci) =>
    DeckManager.apply(state, ChessMoveAction(uci));

({
  AuthoritativeBattleState before,
  AuthoritativeBattleState cast,
  AuthoritativeBattleState moved,
  AuthoritativeBattleState response,
  AuthoritativeBattleState after,
})
slowPairedCasts(PieceColor caster) {
  final before = slowReady(
    caster.isWhite
        ? '4k3/8/8/8/3r4/8/8/K7 w - - 0 10'
        : '4k3/8/8/8/3R4/8/8/K7 b - - 0 10',
    white:
        caster.isWhite
            ? const [CardId.slow, CardId.radar, CardId.mine]
            : const [CardId.purify, CardId.radar, CardId.mine],
    black:
        caster.isWhite
            ? const [CardId.purify, CardId.radar, CardId.mine]
            : const [CardId.slow, CardId.radar, CardId.mine],
  );
  final cast = DeckManager.apply(
    before,
    PlayCardAction(CardId.slow, target: slowSquare('d4')),
  );
  final moved = slowMove(cast, caster.isWhite ? 'a1b1' : 'e8f8');
  final response = DeckManager.apply(
    moved,
    PlayCardAction(CardId.purify, target: cast.rules.pieceEffects.single.id),
  );
  final after = slowMove(response, caster.isWhite ? 'e8f8' : 'a1b1');
  return (
    before: before,
    cast: cast,
    moved: moved,
    response: response,
    after: after,
  );
}

AuthoritativeBattleState slowResponseReady(
  PieceColor caster, {
  List<CardId> defender = const [
    CardId.prophecy,
    CardId.fateExchange,
    CardId.fog,
  ],
}) {
  final initial = slowReady(
    caster.isWhite
        ? '4k3/8/8/8/3r4/8/8/K7 w - - 0 10'
        : '4k3/8/8/8/3R4/8/8/K7 b - - 0 10',
    white:
        caster.isWhite
            ? const [CardId.slow, CardId.mine, CardId.radar]
            : defender,
    black:
        caster.isWhite
            ? defender
            : const [CardId.slow, CardId.mine, CardId.radar],
  );
  final cast = DeckManager.apply(
    initial,
    PlayCardAction(CardId.slow, target: slowSquare('d4')),
  );
  return slowMove(cast, caster.isWhite ? 'a1b1' : 'e8f8');
}

void _rejected(
  SlowVerify verify,
  AuthoritativeBattleState state,
  BattleAction action,
  String reason,
) {
  final before = jsonEncode(state.toJson());
  var rejected = false;
  try {
    DeckManager.apply(state, action);
  } on StateError {
    rejected = true;
  }
  verify(rejected, '$reason: must reject');
  verify(jsonEncode(state.toJson()) == before, '$reason: atomic input');
}

AuthoritativeBattleState slowMineOverlap() {
  var state = slowReady('2B4k/8/5P2/8/2r5/8/8/K7 w - - 0 10');
  state = DeckManager.apply(
    state,
    PlayCardAction(CardId.mine, target: slowSquare('c6')),
  );
  state = slowMove(state, 'a1b1');
  state = DeckManager.apply(state, const PassAction());
  state = slowMove(state, 'c4c6');
  state = DeckManager.apply(
    state,
    PlayCardAction(CardId.slow, target: slowSquare('c6')),
  );
  return slowMove(state, 'b1a1');
}

({
  AuthoritativeBattleState before,
  AuthoritativeBattleState cast,
  AuthoritativeBattleState expired,
})
slowBatchedProjection() {
  final before = slowReady('4k3/8/8/8/3r4/8/8/K7 w - - 0 10');
  final cast = DeckManager.apply(
    before,
    PlayCardAction(CardId.slow, target: slowSquare('d4')),
  );
  var expired = slowMove(cast, 'a1b1');
  expired = DeckManager.apply(expired, const PassAction());
  expired = slowMove(expired, 'e8f8');
  return (before: before, cast: cast, expired: expired);
}

final slowAuditCases = <SlowAuditCase>[
  SlowAuditCase('queen diagonal distance is steps, not Manhattan distance', (
    v,
  ) {
    final initial = slowReady(
      '7k/8/5n2/8/3Q4/8/1n6/K7 w - - 0 10',
      phase: BattlePhase.chess,
    );
    final state = slowEdit(initial, (d) {
      d.pieceEffects.add(slowEffect(initial.rules, 'd4'));
    });
    final moves = slowMoves(state, PieceColor.white);
    v(moves.contains('d4f6'), 'two diagonal steps may capture f6');
    v(moves.contains('d4b2'), 'two diagonal steps may capture b2');
    v(moves.contains('d4f4'), 'two horizontal steps are allowed');
    v(moves.contains('d4d6'), 'two vertical steps are allowed');
    v(!moves.contains('d4g4'), 'three horizontal steps are denied');
    v(!moves.contains('d4d7'), 'three vertical steps are denied');
    final captured = slowMove(state, 'd4f6');
    v(
      captured.rules.board.pieceAt(slowSquare('f6'))?.type == PieceType.queen,
      'capture preserves the queen',
    );
    v(
      captured.rules.pieceIds[slowSquare('f6')] ==
          state.rules.pieceIds[slowSquare('d4')],
      'stable mover ID after capture',
    );
    v(captured.rules.pieceEffects.isEmpty, 'successful capture consumes SLOW');
  }),
  SlowAuditCase('SLOW never adds a jump over friendly or hostile blockers', (
    v,
  ) {
    for (final blocker in ['P', 'p', 'N', 'n']) {
      final initial = slowReady(
        '7k/8/8/8/3Q${blocker}3/8/8/K7 w - - 0 10',
        phase: BattlePhase.chess,
      );
      final state = slowEdit(initial, (d) {
        d.pieceEffects.add(slowEffect(initial.rules, 'd4'));
      });
      final moves = slowMoves(state, PieceColor.white);
      v(!moves.contains('d4f4'), '$blocker blocks two-step destination');
      v(
        moves.contains('d4e4') == (blocker == blocker.toLowerCase()),
        '$blocker: adjacent enemy can be captured, own piece cannot',
      );
      _rejected(v, state, const ChessMoveAction('d4f4'), '$blocker jump');
    }
  }),
  SlowAuditCase('pinned slowed rook: unrelated move consumes the debuff', (v) {
    var state = slowReady('n3k3/4r3/8/8/8/8/8/K3R3 w - - 0 10');
    state = DeckManager.apply(
      state,
      PlayCardAction(CardId.slow, target: slowSquare('e7')),
    );
    state = slowMove(state, 'a1b1');
    final id = state.rules.pieceIds[slowSquare('e7')];
    state = DeckManager.apply(state, const PassAction());
    final moves = slowMoves(state, PieceColor.black);
    v(moves.contains('e7e5'), 'pinned rook can remain on pin line within two');
    v(!moves.contains('e7e4'), 'pin-line defense beyond two is still denied');
    v(!moves.contains('e7f7'), 'near sideways move cannot expose king');
    _rejected(v, state, const ChessMoveAction('e7f7'), 'pinned short move');
    state = slowMove(state, 'a8b6');
    v(
      state.rules.pieceIds[slowSquare('e7')] == id,
      'different mover does not relocate slowed rook',
    );
    v(state.rules.pieceEffects.isEmpty, 'different mover expires SLOW');
    v(
      slowMoves(state, PieceColor.black).contains('e7e4'),
      'later projected rook has its full pin-line range',
    );
  }),
  SlowAuditCase('slowed queen may capture checker or interpose within two', (
    v,
  ) {
    final initial = slowReady(
      '4k3/8/8/8/1b1Q4/8/8/4K3 w - - 0 10',
      phase: BattlePhase.chess,
    );
    final state = slowEdit(initial, (d) {
      d.pieceEffects.add(slowEffect(initial.rules, 'd4'));
    });
    v(
      MoveGen.inCheck(state.rules.board, PieceColor.white),
      'real starting check',
    );
    final moves = slowMoves(state, PieceColor.white);
    v(moves.contains('d4b4'), 'capture the bishop checker in two squares');
    v(moves.contains('d4c3'), 'one-square diagonal interposition');
    v(moves.contains('d4d2'), 'two-square vertical interposition');
    v(!moves.contains('d4f4'), 'near unrelated move cannot ignore check');
    for (final uci in ['d4b4', 'd4c3', 'd4d2']) {
      final after = slowMove(state, uci);
      v(
        !MoveGen.inCheck(after.rules.board, PieceColor.white),
        '$uci really escapes check',
      );
      v(after.rules.pieceEffects.isEmpty, '$uci consumes SLOW');
    }
  }),
  SlowAuditCase('Shadow Pass crosses one adjacent ally but SLOW caps landing', (
    v,
  ) {
    for (final (fen, from, allowed, denied) in [
      ('7k/8/8/8/3P4/2B5/8/K7 w - - 0 10', 'c3', 'c3e5', 'c3f6'),
      ('7k/8/8/8/3RP3/8/8/K7 w - - 0 10', 'd4', 'd4f4', 'd4g4'),
      ('7k/8/3rp3/8/8/8/8/K7 b - - 0 10', 'd6', 'd6f6', 'd6g6'),
    ]) {
      final initial = slowReady(
        fen,
        white: const [CardId.shadowPass, CardId.slow, CardId.radar],
      );
      final state = slowEdit(initial, (d) {
        d.pieceEffects.add(slowEffect(initial.rules, from));
      });
      final side = state.rules.board.turn;
      final special =
          BattleRulesCore.specialMoves(
            state.rules,
            CardId.shadowPass,
            slowSquare(from),
            side,
          ).map((move) => move.uci).toSet();
      v(special.contains(allowed), '$side $from: exact two-step exception');
      v(!special.contains(denied), '$side $from: third step is denied');
      final authorized = DeckManager.apply(
        state,
        PlayCardAction(CardId.shadowPass, target: slowSquare(from)),
      );
      v(
        authorized.rules.special?.moves.contains(allowed) == true,
        'stored authorization includes only current restricted path',
      );
      _rejected(v, authorized, ChessMoveAction(denied), 'long Shadow Pass');
      final after = slowMove(authorized, allowed);
      v(after.rules.special == null, 'special authorization is one use');
      v(after.rules.pieceEffects.isEmpty, 'special move consumes SLOW');
    }
  }),
  SlowAuditCase(
    'Shadow Pass has no target when first ally is two squares away',
    (v) {
      final initial = slowReady(
        '7k/8/8/8/3R1P2/8/8/K7 w - - 0 10',
        white: const [CardId.shadowPass, CardId.slow, CardId.radar],
      );
      final state = slowEdit(initial, (d) {
        d.pieceEffects.add(slowEffect(initial.rules, 'd4'));
      });
      v(
        BattleRulesCore.specialMoves(
          state.rules,
          CardId.shadowPass,
          slowSquare('d4'),
          PieceColor.white,
        ).isEmpty,
        'crossing f4 would require landing at least three squares away',
      );
      _rejected(
        v,
        state,
        PlayCardAction(CardId.shadowPass, target: slowSquare('d4')),
        'dead special target cannot spend mana',
      );
    },
  ),
  SlowAuditCase('Rook Bend respects Slow, pin and empty-only destination', (v) {
    final initial = slowReady(
      '7k/8/8/2n5/3R4/8/8/K7 w - - 0 10',
      white: const [CardId.rookBend, CardId.slow, CardId.radar],
    );
    final state = slowEdit(initial, (d) {
      d.pieceEffects.add(slowEffect(initial.rules, 'd4'));
    });
    final special =
        BattleRulesCore.specialMoves(
          state.rules,
          CardId.rookBend,
          slowSquare('d4'),
          PieceColor.white,
        ).map((move) => move.uci).toSet();
    v(special.contains('d4e5'), 'one diagonal empty square survives SLOW');
    v(
      !special.contains('d4c5'),
      'Rook Bend cannot capture even within Slow range',
    );
    final authorized = DeckManager.apply(
      state,
      PlayCardAction(CardId.rookBend, target: slowSquare('d4')),
    );
    v(
      !slowHas(authorized, const ChessMoveAction('a1b1')),
      'movement card binds rook instead of allowing another piece',
    );
    v(
      slowMove(authorized, 'd4e5').rules.pieceEffects.isEmpty,
      'Rook Bend consumes the opposing move-window SLOW',
    );
    final pinned = slowReady(
      '4r2k/8/8/8/8/8/4R3/4K3 w - - 0 10',
      white: const [CardId.rookBend, CardId.slow, CardId.radar],
    );
    final pinSlow = slowEdit(pinned, (d) {
      d.pieceEffects.add(slowEffect(pinned.rules, 'e2'));
    });
    v(
      BattleRulesCore.specialMoves(
        pinSlow.rules,
        CardId.rookBend,
        slowSquare('e2'),
        PieceColor.white,
      ).isEmpty,
      'short diagonal special move cannot break king pin',
    );
  }),
  SlowAuditCase(
    'black short castle consumes both Slow effects and retains new Mine',
    (v) {
      final initial = slowReady(
        'r3k2r/8/8/8/8/8/8/4K3 b kq - 0 10',
        phase: BattlePhase.chess,
      );
      final state = slowEdit(initial, (d) {
        d.pieceEffects.addAll([
          slowEffect(initial.rules, 'a8', id: 'slow-queen-rook'),
          slowEffect(initial.rules, 'h8', id: 'slow-king-rook'),
        ]);
        d.boardEffects.add(
          BoardEffectInstance(
            id: 'mine-f8',
            type: BoardEffectType.mine,
            owner: PieceColor.white,
            squares: [slowSquare('f8')],
            responseSide: PieceColor.black,
            duration: EffectDuration.persistent,
          ),
        );
      });
      final moves = slowMoves(state, PieceColor.black);
      v(moves.contains('e8g8'), 'short rook displacement h8-f8 is two');
      v(!moves.contains('e8c8'), 'long rook displacement a8-d8 is three');
      _rejected(v, state, const ChessMoveAction('e8c8'), 'black long castle');
      final after = slowMove(state, 'e8g8');
      v(
        after.rules.pieceIds[slowSquare('f8')] ==
            state.rules.pieceIds[slowSquare('h8')],
        'castling relocates stable rook ID',
      );
      v(
        after.rules.pieceEffects.length == 1 &&
            after.rules.pieceEffects.single.type == PieceEffectType.mineDebuff,
        'freshly triggered Mine survives while both old Slow effects expire',
      );
      v(
        after.rules.pieceEffects.single.pieceId ==
            after.rules.pieceIds[slowSquare('f8')],
        'Mine binds castling rook, not king',
      );
      v(
        after.rules.boardEffects.isEmpty,
        'arriving rook consumes the board Mine',
      );
      v(
        after.rules.board.castling == 0,
        'king movement revokes both black rights',
      );
    },
  ),
  SlowAuditCase('real Mine+Slow: Purify one effect does not erase the other', (
    v,
  ) {
    final state = slowMineOverlap();
    v(
      state.rules.phase == BattlePhase.card &&
          state.rules.board.turn == PieceColor.black,
      'real black response card phase',
    );
    v(state.rules.pieceEffects.length == 2, 'reachable Mine+Slow overlap');
    final slow = state.rules.pieceEffects.singleWhere(
      (effect) => effect.type == PieceEffectType.slow,
    );
    final mine = state.rules.pieceEffects.singleWhere(
      (effect) => effect.type == PieceEffectType.mineDebuff,
    );
    final removeSlow = DeckManager.apply(
      state,
      PlayCardAction(CardId.purify, target: slow.id),
    );
    v(
      removeSlow.rules.pieceEffects.single.id == mine.id,
      'Purify Slow keeps Mine',
    );
    v(
      slowMoves(removeSlow, PieceColor.black).contains('c6c3'),
      'cleansed Slow restores long noncapture despite Mine',
    );
    v(
      !slowMoves(removeSlow, PieceColor.black).contains('c6c8'),
      'remaining Mine denies nearby capture',
    );
    final removeMine = DeckManager.apply(
      state,
      PlayCardAction(CardId.purify, target: mine.id),
    );
    v(
      removeMine.rules.pieceEffects.single.id == slow.id,
      'Purify Mine keeps Slow',
    );
    v(
      slowMoves(removeMine, PieceColor.black).contains('c6c8'),
      'remaining Slow permits nearby capture',
    );
    v(
      !slowMoves(removeMine, PieceColor.black).contains('c6c3'),
      'remaining Slow denies long noncapture',
    );
    final pass = DeckManager.apply(state, const PassAction());
    _rejected(v, pass, const ChessMoveAction('c6c8'), 'Mine+Slow capture');
    _rejected(v, pass, const ChessMoveAction('c6c3'), 'Mine+Slow long move');
    final other = slowMove(pass, 'h8g8');
    v(
      other.rules.pieceEffects.single.id == mine.id,
      'unrelated king move expires Slow, not persistent Mine debuff',
    );
  }),
  SlowAuditCase(
    'synthetic overlaps intersect, and an occupied seal landing can capture',
    (v) {
      final initial = slowReady(
        '7k/8/8/8/3R1n2/8/8/K7 w - - 0 10',
        phase: BattlePhase.chess,
      );
      final base = slowEdit(initial, (d) {
        d.pieceEffects.add(slowEffect(initial.rules, 'd4'));
        d.boardEffects.add(
          BoardEffectInstance(
            id: 'seal',
            type: BoardEffectType.boardSeal,
            owner: PieceColor.black,
            squares: [slowSquare('e4'), slowSquare('f4')],
            responseSide: PieceColor.white,
            duration: EffectDuration.move,
          ),
        );
      });
      v(
        !slowMoves(base, PieceColor.white).contains('d4e4'),
        'empty hostile seal landing is denied despite one-step Slow distance',
      );
      v(
        slowMoves(base, PieceColor.white).contains('d4f4'),
        'occupied two-step seal landing still allows a capture',
      );
      for (final type in [
        PieceEffectType.chain,
        PieceEffectType.mineDebuff,
        PieceEffectType.freeze,
      ]) {
        final overlap = slowEdit(base, (d) {
          d.pieceEffects.add(
            slowEffect(
              initial.rules,
              'd4',
              type: type,
              id: 'overlap-${type.name}',
            ),
          );
        });
        final moves = slowMoves(overlap, PieceColor.white);
        v(!moves.contains('d4f4'), '$type overrides Slow capture permission');
        v(
          moves.contains('d4d5') == (type != PieceEffectType.freeze),
          '$type: empty one-step movement intersection',
        );
      }
    },
  ),
  SlowAuditCase(
    'valid Slow selection: protection rejection and version cancellation',
    (v) {
      final initial = slowReady('4k3/8/8/8/2b1r1q1/8/8/K7 w - - 0 10');
      final state = slowEdit(initial, (d) {
        d.pieceEffects.add(
          ActivePieceEffect(
            id: 'shelter',
            type: PieceEffectType.shelter,
            owner: PieceColor.black,
            pieceId: d.pieceIds[slowSquare('e4')]!,
            responseSide: PieceColor.white,
            duration: EffectDuration.card,
          ),
        );
        d.boardEffects.add(
          BoardEffectInstance(
            id: 'fog',
            type: BoardEffectType.fog,
            owner: PieceColor.black,
            squares: boardZone(slowSquare('f4')),
            responseSide: PieceColor.white,
            duration: EffectDuration.card,
          ),
        );
      });
      final view = state.view(PieceColor.white);
      final actions = BattleRulesCore.legalActions(view);
      final interaction =
          BattleInteraction()
            ..synchronize(view, 40)
            ..select(CardId.slow, actions);
      v(
        interaction.targets(view, actions).contains(slowSquare('c4')),
        'unprotected bishop is highlighted',
      );
      v(
        !interaction.targets(view, actions).contains(slowSquare('e4')),
        'Shelter rook is not highlighted',
      );
      v(
        !interaction.targets(view, actions).contains(slowSquare('g4')),
        'Fog queen is not highlighted',
      );
      interaction.tap(slowSquare('c4'), view, actions);
      v(
        interaction.play?.target == slowSquare('c4'),
        'selection stores board square',
      );
      v(
        interaction.preview().contains(slowSquare('c4')),
        'target preview matches intent',
      );
      interaction.tap(slowSquare('e4'), view, actions);
      v(
        interaction.play == null && interaction.invalidTarget,
        'protected retarget cannot retain previous target',
      );
      interaction.tap(slowSquare('c4'), view, actions);
      final after = DeckManager.apply(state, interaction.play!);
      interaction.synchronize(after.view(PieceColor.white), 41);
      v(
        interaction.card == null &&
            interaction.play == null &&
            interaction.preview().isEmpty,
        'accepted version clears stale selection',
      );
      v(
        after.rules.pieceEffects.any(
          (effect) => effect.type == PieceEffectType.slow,
        ),
        'selected target became a stable-ID Slow effect',
      );
      v(
        after.rules.pieceEffects.every(
              (effect) => effect.type != PieceEffectType.shelter,
            ) &&
            after.rules.boardEffects.isEmpty,
        'card-window protections expire separately',
      );
    },
  ),
  SlowAuditCase('Slow cost intersects sabotage and prior self-discount', (v) {
    for (final (sabotage, discount, expected) in [
      (false, false, 2),
      (true, false, 3),
      (false, true, 1),
      (true, true, 1),
    ]) {
      final initial = slowReady(
        '4k3/8/8/8/3r4/8/8/K7 w - - 0 10',
        mana: expected,
      );
      final state = slowEdit(initial, (d) {
        if (sabotage) {
          d.modifiers.add(
            PendingModifier(
              id: 'sabotage',
              type: ModifierType.manaSabotage,
              owner: PieceColor.black,
              responseSide: PieceColor.white,
              targetCard: CardId.slow,
              ownTurn: d.ownTurns[PieceColor.white]!,
            ),
          );
        }
        if (discount) {
          d.modifiers.add(
            PendingModifier(
              id: 'discount',
              type: ModifierType.discount,
              owner: PieceColor.white,
              responseSide: PieceColor.white,
              targetCard: null,
              ownTurn: d.ownTurns[PieceColor.white]!,
            ),
          );
        }
      });
      v(
        BattleRulesCore.effectiveCost(
              state.rules,
              PieceColor.white,
              CardId.slow,
            ) ==
            expected,
        'sabotage=$sabotage discount=$discount cost=$expected',
      );
      final after = DeckManager.apply(
        state,
        PlayCardAction(CardId.slow, target: slowSquare('d4')),
      );
      v(after.rules.mana[PieceColor.white] == 0, 'exact affordability charge');
      v(after.rules.modifiers.isEmpty, 'response cost modifiers close once');
      final poor = slowEdit(
        state,
        (d) => d.mana[PieceColor.white] = expected - 1,
      );
      _rejected(
        v,
        poor,
        PlayCardAction(CardId.slow, target: slowSquare('d4')),
        'cost shortfall $expected',
      );
    }
  }),
  SlowAuditCase(
    'skipped snapshots can show used Slow after effect already expired',
    (v) {
      final states = slowBatchedProjection();
      v(
        !states.before.rules.used[PieceColor.white]!.contains(CardId.slow),
        'old poll predates the cast',
      );
      v(
        states.cast.rules.pieceEffects.single.type == PieceEffectType.slow,
        'intermediate cast had a target effect',
      );
      v(
        states.expired.rules.used[PieceColor.white]!.contains(CardId.slow),
        'new poll proves card consumption',
      );
      v(
        states.expired.rules.pieceEffects.isEmpty,
        'new poll cannot infer the cast square from active effects',
      );
      v(
        states.expired.rules.ply == states.before.rules.ply + 2,
        'two real chess moves can fit between polls',
      );
      final roundTrip = AuthoritativeBattleState.fromJson(
        jsonDecode(jsonEncode(states.expired.toJson())) as Map,
      );
      v(
        jsonEncode(roundTrip.toJson()) == jsonEncode(states.expired.toJson()),
        'expiry survives offline authoritative serialization',
      );
    },
  ),
  SlowAuditCase(
    'both sides: exact target species and malformed admission are atomic',
    (v) {
      for (final caster in PieceColor.values) {
        final state = slowReady(
          caster.isWhite
              ? '4k3/ppnbrq2/8/8/8/8/PPNBRQ2/4K3 w - - 0 10'
              : '4k3/ppnbrq2/8/8/8/8/PPNBRQ2/4K3 b - - 0 10',
          black: const [CardId.slow, CardId.mine, CardId.radar],
        );
        final targetRank = caster.isWhite ? '7' : '2';
        final ownRank = caster.isWhite ? '2' : '7';
        final expected =
            [
              'd$targetRank',
              'e$targetRank',
              'f$targetRank',
            ].map(slowSquare).toSet();
        final actual =
            BattleRulesCore.cardTargets(
              state.view(caster),
              CardId.slow,
            ).whereType<int>().toSet();
        v(
          actual.length == 3 && actual.containsAll(expected),
          '$caster: bishop/rook/queen only, regardless of occupied rays',
        );
        for (final target in [
          null,
          -1,
          64,
          'd$targetRank',
          '${slowSquare('d$targetRank')}',
          slowSquare('d$targetRank').toDouble(),
          true,
          <int>[slowSquare('d$targetRank')],
          {'square': slowSquare('d$targetRank')},
          slowSquare('a$targetRank'),
          slowSquare('c$targetRank'),
          slowSquare('d$ownRank'),
          slowSquare(caster.isWhite ? 'e8' : 'e1'),
        ]) {
          final action = PlayCardAction(CardId.slow, target: target);
          v(
            !slowHas(state, action),
            '$caster rejects typed/illegal target $target',
          );
          _rejected(v, state, action, '$caster malformed target $target');
        }
        for (final target in expected) {
          final before = jsonEncode(state.toJson());
          final after = DeckManager.apply(
            state,
            PlayCardAction(CardId.slow, target: target),
          );
          final effect = after.rules.pieceEffects.single;
          v(
            after.rules.mana[caster] == 4 &&
                after.rules.phase == BattlePhase.chess,
            'cast charges two, not a chess move',
          );
          v(
            effect.owner == caster &&
                effect.responseSide == caster.opposite &&
                effect.duration == EffectDuration.move &&
                effect.pieceId == state.rules.pieceIds[target],
            'stable enemy binding',
          );
          v(
            after.rules.ply == state.rules.ply &&
                after.rules.fen == state.rules.fen,
            'cast leaves the chess position and ply unchanged',
          );
          v(
            !after.hidden.hands[caster]!.contains(CardId.slow) &&
                after.rules.used[caster]!.contains(CardId.slow),
            'one card consumed',
          );
          v(
            after.hidden.decks[caster]!.map((c) => c.wire).join(',') ==
                state.hidden.decks[caster]!.map((c) => c.wire).join(','),
            'casting does not draw',
          );
          _rejected(
            v,
            after,
            PlayCardAction(CardId.slow, target: target),
            'same cast cannot replay in chess phase',
          );
          v(
            jsonEncode(state.toJson()) == before,
            'accepted input remains immutable',
          );
        }
      }
    },
  ),
  SlowAuditCase('both sides: capture by caster removes Slow before response', (
    v,
  ) {
    for (final caster in PieceColor.values) {
      var state = slowReady(
        caster.isWhite
            ? '4k3/8/8/8/3r4/8/8/K2R4 w - - 0 10'
            : '3r3k/8/8/3R4/8/8/8/4K3 b - - 0 10',
        black: const [CardId.slow, CardId.mine, CardId.radar],
      );
      final target = slowSquare(caster.isWhite ? 'd4' : 'd5');
      final oldId = state.rules.pieceIds[target];
      state = DeckManager.apply(
        state,
        PlayCardAction(CardId.slow, target: target),
      );
      v(
        state.rules.pieceEffects.single.pieceId == oldId,
        'bind pre-capture identity',
      );
      final after = slowMove(state, caster.isWhite ? 'd1d4' : 'd8d5');
      v(
        after.rules.pieceEffects.isEmpty,
        'captured target status cannot transfer',
      );
      v(!after.rules.pieceIds.contains(oldId), 'captured stable ID is gone');
      v(
        after.rules.board.pieceAt(target)?.color == caster,
        'caster owns the landing occupant, not the Slow effect',
      );
    }
  }),
  SlowAuditCase(
    'both sides: pending Prophecy and Fate resolve without consuming Slow',
    (v) {
      for (final caster in PieceColor.values) {
        final reply = slowResponseReady(caster);
        final defender = caster.opposite;
        final id = reply.rules.pieceEffects.single.id;
        for (final card in [CardId.prophecy, CardId.fateExchange]) {
          final pending = DeckManager.apply(
            reply,
            PlayCardAction(
              card,
              sacrifice: card == CardId.fateExchange ? CardId.fog : null,
            ),
          );
          v(
            pending.rules.phase == BattlePhase.pending,
            '$card creates pending',
          );
          v(
            pending.rules.pieceEffects.single.id == id,
            '$card inspection is not a move',
          );
          v(
            pending.view(caster).knowledge.pendingCards.isEmpty,
            'opponent does not learn response pending deck identities',
          );
          v(
            pending.view(caster).knowledge.knownUpcomingCards.isEmpty,
            'opponent does not learn response ordering',
          );
          _rejected(
            v,
            pending,
            const PassAction(),
            '$card pending cannot pass',
          );
          _rejected(
            v,
            pending,
            ChessMoveAction(defender.isWhite ? 'a1b1' : 'e8f8'),
            '$card pending cannot move chess',
          );
          final choices =
              BattleRulesCore.legalActions(
                pending.view(defender),
              ).whereType<ResolveAction>().toList();
          v(
            choices.length == (card == CardId.prophecy ? 2 : 6),
            'all independently expected two/three-card orderings',
          );
          for (final choice in choices) {
            final resolved = DeckManager.apply(pending, choice);
            v(
              resolved.rules.phase == BattlePhase.chess &&
                  resolved.rules.pieceEffects.single.id == id,
              'resolve closes card window, not move-window Slow',
            );
            v(
              !slowMoves(resolved, defender).contains('d4d7'),
              'long rook move remains restricted after resolution',
            );
            final moved = slowMove(
              resolved,
              defender.isWhite ? 'a1b1' : 'e8f8',
            );
            v(
              moved.rules.pieceEffects.isEmpty,
              'only completed response move consumes Slow',
            );
            v(
              moved.view(caster).knowledge.pendingCards.isEmpty &&
                  moved.view(caster).knowledge.knownUpcomingCards.isEmpty,
              'private ordering remains redacted after the response',
            );
          }
        }
      }
    },
  ),
  SlowAuditCase(
    'both sides: Fog and Shelter cannot retroactively cleanse Slow',
    (v) {
      for (final caster in PieceColor.values) {
        for (final card in [CardId.fog, CardId.shelter]) {
          final reply = slowResponseReady(
            caster,
            defender: const [CardId.fog, CardId.shelter, CardId.radar],
          );
          final defender = caster.opposite;
          final id = reply.rules.pieceEffects.single.id;
          final response = DeckManager.apply(
            reply,
            PlayCardAction(card, target: slowSquare('d4')),
          );
          v(
            response.rules.pieceEffects.any((e) => e.id == id),
            '$card protects future cards but does not cleanse existing Slow',
          );
          v(
            !slowMoves(response, defender).contains('d4d7'),
            '$card cannot restore a three-square move',
          );
          final moved = slowMove(response, defender.isWhite ? 'a1b1' : 'e8f8');
          v(
            !moved.rules.pieceEffects.any((e) => e.id == id),
            'Slow expires normally',
          );
          v(
            card == CardId.fog
                ? moved.rules.boardEffects.length == 1
                : moved.rules.pieceEffects.length == 1,
            'new protection persists into the caster next card window',
          );
        }
      }
    },
  ),
  SlowAuditCase(
    'both sides: pass and discard consume neither mana nor response Slow',
    (v) {
      for (final caster in PieceColor.values) {
        final reply = slowResponseReady(caster);
        final defender = caster.opposite;
        final id = reply.rules.pieceEffects.single.id;
        for (final action in <BattleAction>[
          const PassAction(),
          const DiscardAction(CardId.prophecy),
        ]) {
          final after = DeckManager.apply(reply, action);
          v(
            after.rules.pieceEffects.single.id == id,
            '$action leaves move debuff',
          );
          v(
            after.rules.mana[defender] == reply.rules.mana[defender],
            'pass/discard cannot spend card mana',
          );
          v(!slowMoves(after, defender).contains('d4d7'), 'range is still two');
          final moved = slowMove(after, defender.isWhite ? 'a1b1' : 'e8f8');
          v(
            moved.rules.pieceEffects.isEmpty,
            'other king movement consumes Slow',
          );
        }
      }
    },
  ),
  SlowAuditCase(
    'both sides: two consecutive Slow casts use separate response windows',
    (v) {
      var state = slowReady(
        '4k3/8/8/8/3r4/8/8/K2R4 w - - 0 10',
        black: const [CardId.slow, CardId.purify, CardId.radar],
      );
      state = DeckManager.apply(
        state,
        PlayCardAction(CardId.slow, target: slowSquare('d4')),
      );
      final first = state.rules.pieceEffects.single.id;
      state = slowMove(state, 'a1b1');
      state = DeckManager.apply(
        state,
        PlayCardAction(CardId.slow, target: slowSquare('d1')),
      );
      v(
        state.rules.pieceEffects.length == 2,
        'different owners have overlapping windows',
      );
      final second =
          state.rules.pieceEffects.singleWhere((e) => e.id != first).id;
      v(
        !slowMoves(state, PieceColor.black).contains('d4d7'),
        'old Slow still binds black',
      );
      state = slowMove(state, 'e8f8');
      v(
        state.rules.pieceEffects.single.id == second,
        'black move only ends first Slow',
      );
      state = DeckManager.apply(state, const PassAction());
      v(
        slowMoves(state, PieceColor.white).contains('d1d3'),
        'white two-square escape',
      );
      v(
        !slowMoves(state, PieceColor.white).contains('d1d4'),
        'white three-square capture denied',
      );
      state = slowMove(state, 'd1d3');
      v(state.rules.pieceEffects.isEmpty, 'white move ends second Slow');
    },
  ),
  SlowAuditCase(
    'both sides: chronological cast histories are real and remain redacted',
    (v) {
      for (final caster in PieceColor.values) {
        final pair = slowPairedCasts(caster);
        v(pair.after.rules.pieceEffects.isEmpty, 'Purify really removed Slow');
        v(
          pair.after.rules.used[caster]!.contains(CardId.slow) &&
              pair.after.rules.used[caster.opposite]!.contains(CardId.purify),
          'public used sets prove two real casts',
        );
        v(
          pair.after.rules.ply == pair.before.rules.ply + 2,
          'two completed moves can fit in one poll delta',
        );
        v(
          pair.response.rules.board.turn == caster.opposite,
          'known latest real cast is responder Purify',
        );
        for (final viewer in PieceColor.values) {
          final json = pair.after.view(viewer).toJson();
          v(
            !json.containsKey('hidden') &&
                !json.containsKey('decks') &&
                (json['ownHand'] as List).length ==
                    pair.after.hidden.hands[viewer]!.length,
            'projection has own hand only and no secret decks',
          );
        }
      }
    },
  ),
  SlowAuditCase(
    'both sides: Slow-assisted mate flags a genuine eliminated long capture',
    (v) {
      for (final caster in PieceColor.values) {
        final initial = slowReady(
          caster.isWhite
              ? '7k/r7/5KQ1/8/8/8/8/8 w - - 0 10'
              : '8/8/8/8/8/1qk5/7R/K7 b - - 0 10',
          black: const [CardId.slow, CardId.purify, CardId.radar],
        );
        final target = slowSquare(caster.isWhite ? 'a7' : 'h2');
        final attack = caster.isWhite ? 'g6g7' : 'b3b2';
        final escape = caster.isWhite ? 'a7g7' : 'h2b2';
        final baseline = slowMove(
          DeckManager.apply(initial, const PassAction()),
          attack,
        );
        v(
          baseline.rules.terminal == null &&
              slowMoves(baseline, caster.opposite).contains(escape),
          'independently specified six-square checker capture avoids normal mate',
        );
        final cast = DeckManager.apply(
          initial,
          PlayCardAction(CardId.slow, target: target),
        );
        final mate = slowMove(cast, attack);
        v(
          mate.rules.phase == BattlePhase.terminal &&
              mate.rules.terminal?.reason == 'checkmate' &&
              mate.rules.terminal?.winner == caster &&
              mate.rules.terminal?.mateByRestriction == true &&
              mate.rules.terminal?.mateBySpecialMove == false,
          'Slow removes the only long defense, not the checker attack geometry',
        );
        v(
          BattleRulesCore.legalActions(mate.view(caster.opposite)).isEmpty,
          'contract terminal adjudication precedes a later Purify card window',
        );
        v(
          mate.rules.pieceEffects.single.type == PieceEffectType.slow,
          'uncompleted defender move cannot consume the mate-causing effect',
        );
        v(
          mate.rules.drawCounts[caster] == initial.rules.drawCounts[caster],
          'terminal attack does not draw a post-mate card',
        );
      }
    },
  ),
  SlowAuditCase('Slow never replaces orthodox attack geometry or king safety', (
    v,
  ) {
    final initial = slowReady('4k3/8/8/8/8/8/8/K3r3 w - - 0 10');
    v(
      MoveGen.inCheck(initial.rules.board, PieceColor.white),
      'rook checks the casting king over four squares',
    );
    final cast = DeckManager.apply(
      initial,
      PlayCardAction(CardId.slow, target: slowSquare('e1')),
    );
    v(
      MoveGen.inCheck(cast.rules.board, PieceColor.white),
      'Slow affects travel, not existing orthodox check geometry',
    );
    v(
      !slowHas(cast, const ChessMoveAction('a1b1')),
      'near king move staying on the attacked rank is illegal',
    );
    _rejected(
      v,
      cast,
      const ChessMoveAction('a1b1'),
      'Slow is not a check eraser',
    );
    final escaped = slowMove(cast, 'a1a2');
    v(
      escaped.rules.pieceEffects.length == 1,
      'caster escape still leaves the opposing response Slow',
    );
  }),
  SlowAuditCase(
    'live Sabotage, Block and Echo apply to Slow at their exact response turn',
    (v) {
      for (final modifierCard in [
        CardId.manaSabotage,
        CardId.cardBlock,
        CardId.echo,
      ]) {
        final initial = slowReady(
          '4k3/8/8/8/3r4/8/8/K7 b - - 0 10',
          black: const [CardId.manaSabotage, CardId.cardBlock, CardId.echo],
        );
        final prepared =
            modifierCard == CardId.manaSabotage
                ? slowEdit(initial, (d) => d.mana[PieceColor.white] = 1)
                : initial;
        final cast = DeckManager.apply(
          prepared,
          PlayCardAction(modifierCard, target: CardId.slow.wire),
        );
        final reply = slowMove(cast, 'e8f8');
        final slow = PlayCardAction(CardId.slow, target: slowSquare('d4'));
        v(
          BattleRulesCore.effectiveCost(
                reply.rules,
                PieceColor.white,
                CardId.slow,
              ) ==
              (modifierCard == CardId.manaSabotage ? 3 : 2),
          '$modifierCard exact Slow cost',
        );
        if (modifierCard == CardId.echo) {
          final accepted = DeckManager.apply(reply, slow);
          v(
            accepted.rules.mana[PieceColor.black] == 6 &&
                accepted.rules.mana[PieceColor.white] == 4,
            'Slow triggers exactly two Echo mana once, capped at six',
          );
          v(
            accepted.rules.modifiers.isEmpty,
            'Echo closes after the response cast',
          );
          _rejected(v, accepted, slow, 'Echo cannot reward a replayed Slow');
        } else {
          v(!slowHas(reply, slow), 'poor or blocked Slow cannot be admitted');
          _rejected(
            v,
            reply,
            slow,
            'live response modifier rejects Slow atomically',
          );
          v(
            slowHas(reply, const DiscardAction(CardId.slow)),
            'blocked/poor Slow remains discardable',
          );
          var next = slowMove(
            DeckManager.apply(reply, const PassAction()),
            'a1b1',
          );
          next = slowMove(DeckManager.apply(next, const PassAction()), 'f8g8');
          v(
            next.rules.modifiers.isEmpty && slowHas(next, slow),
            'next own card turn restores normal Slow admission',
          );
        }
      }
    },
  ),
  SlowAuditCase(
    'live Shadow Contract discount makes Slow cost one on the next own turn',
    (v) {
      var state = slowReady(
        '4k3/8/8/8/3r4/8/8/K7 w - - 0 10',
        white: const [CardId.shadowContract, CardId.mine, CardId.slow],
      );
      state = DeckManager.apply(
        state,
        const PlayCardAction(CardId.shadowContract, sacrifice: CardId.mine),
      );
      v(
        state.rules.used[PieceColor.white]!.contains(CardId.shadowContract) &&
            state.rules.discarded[PieceColor.white]!.contains(CardId.mine),
        'discount preparation consumes Contract and sacrifices Mine, not Slow',
      );
      state = slowMove(state, 'a1b1');
      state = slowMove(DeckManager.apply(state, const PassAction()), 'e8f8');
      v(
        BattleRulesCore.effectiveCost(
              state.rules,
              PieceColor.white,
              CardId.slow,
            ) ==
            1,
        'next own turn Slow cost floors at one',
      );
      final mana = state.rules.mana[PieceColor.white]!;
      state = DeckManager.apply(
        state,
        PlayCardAction(CardId.slow, target: slowSquare('d4')),
      );
      v(
        state.rules.mana[PieceColor.white] == mana - 1 &&
            state.rules.modifiers.isEmpty,
        'one discounted charge closes modifier',
      );
    },
  ),
  SlowAuditCase(
    'opponent secret repartition never changes Slow public targeting or transition',
    (v) {
      final initial = slowReady('4k3/8/8/8/3r4/8/8/K7 w - - 0 10');
      final enemy = PieceColor.black;
      final originalHand = initial.hidden.hands[enemy]!;
      final originalDeck = initial.hidden.decks[enemy]!;
      final alternate = AuthoritativeBattleState(
        initial.rules,
        AuthoritativeHiddenState(
          hands: {
            ...initial.hidden.hands,
            enemy: [originalDeck.first, ...originalHand.skip(1)],
          },
          decks: {
            ...initial.hidden.decks,
            enemy: [
              originalHand.first,
              ...originalDeck.skip(1).toList().reversed,
            ],
          },
          knowledge: initial.hidden.knowledge,
        ),
      );
      v(
        jsonEncode(initial.view(PieceColor.white).toJson()) ==
            jsonEncode(alternate.view(PieceColor.white).toJson()),
        'equal visible rules and own hand remain byte-equal despite enemy secrets',
      );
      final action = PlayCardAction(CardId.slow, target: slowSquare('d4'));
      final a = DeckManager.apply(initial, action);
      final b = DeckManager.apply(alternate, action);
      v(
        jsonEncode(a.rules.toJson()) == jsonEncode(b.rules.toJson()),
        'Slow public transition does not read enemy deck or hand identities',
      );
      v(
        a.hidden.hands[enemy]!.first != b.hidden.hands[enemy]!.first,
        'probe really varied hidden opponent state rather than identical fixtures',
      );
    },
  ),
  SlowAuditCase(
    'parent accepted-frame tracker preserves exact Slow/Purify deltas only',
    (v) {
      for (final caster in PieceColor.values) {
        final pair = slowPairedCasts(caster);
        final tracker = BattlePresentationTracker();
        final states = [
          pair.before,
          pair.cast,
          pair.moved,
          pair.response,
          pair.after,
        ];
        for (var i = 0; i < states.length; i++) {
          tracker.observe(states[i].view(caster), i);
        }
        v(
          tracker.frames.length == 4,
          'every accepted event survived a combined build',
        );
        v(
          tracker.frames.first.after.rules.pieceEffects.single.type ==
              PieceEffectType.slow,
          'original cast target is still available in the bounded frame',
        );
        v(
          tracker.frames[2].before.rules.pieceEffects.single.type ==
                  PieceEffectType.slow &&
              tracker.frames[2].after.rules.pieceEffects.isEmpty,
          'exact Purify frame identifies the removed Slow',
        );
        tracker.observe(pair.after.view(caster), 4);
        v(
          tracker.frames.length == 4,
          'duplicate version cannot invent a second cast',
        );
        tracker.observe(pair.after.view(caster), 9);
        v(tracker.frames.isEmpty, 'version gap clears unverifiable history');
        tracker.observe(pair.after.view(caster), 10, epoch: 1);
        v(
          tracker.frames.isEmpty,
          'new synchronization epoch establishes baseline',
        );
      }
    },
  ),
  SlowAuditCase(
    'restricted Slow piece remains inspectable without granting any forbidden destination',
    (v) {
      for (final side in PieceColor.values) {
        final initial = slowReady(
          side.isWhite
              ? '4k3/8/8/8/3R4/8/8/K7 w - - 0 10'
              : '4k3/8/8/8/3r4/8/8/K7 b - - 0 10',
          phase: BattlePhase.chess,
        );
        for (final frozen in [false, true]) {
          final state = slowEdit(initial, (d) {
            d.pieceEffects.add(slowEffect(initial.rules, 'd4'));
            if (frozen) {
              d.pieceEffects.add(
                slowEffect(
                  initial.rules,
                  'd4',
                  type: PieceEffectType.freeze,
                  id: 'additional-freeze',
                ),
              );
            }
          });
          final view = state.view(side);
          final actions = BattleRulesCore.legalActions(view);
          final interaction = BattleInteraction()..synchronize(view, 1);
          v(
            interaction.tap(slowSquare('d4'), view, actions).isEmpty &&
                interaction.piece == slowSquare('d4'),
            'restricted piece can be inspected',
          );
          final targets = interaction.targets(view, actions);
          v(
            !targets.contains(slowSquare('d7')),
            'long destination never highlighted',
          );
          v(
            targets.contains(slowSquare('d6')) == !frozen,
            'two-step destination exists only without Freeze overlap',
          );
          v(
            interaction.tap(slowSquare('d7'), view, actions).isEmpty &&
                interaction.invalidTarget &&
                interaction.piece == slowSquare('d4'),
            'bad move keeps selected piece for explanation but sends no move',
          );
          final king = slowSquare(side.isWhite ? 'a1' : 'e8');
          interaction.tap(king, view, actions);
          v(
            interaction.piece == king && !interaction.invalidTarget,
            'selecting another own piece clears invalid destination feedback',
          );
        }
      }
    },
  ),
];
