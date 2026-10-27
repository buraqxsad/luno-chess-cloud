import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'helpers/battle_v1_response.dart';

AuthoritativeBattleState restricted(PieceEffectType type, PieceColor side) {
  final base = Board.fromFen('4k3/8/8/8/p7/8/R7/4K3 w - - 0 10');
  final board =
      side.isWhite
          ? base
          : Board(
            squares:
                base.squares.reversed
                    .map((p) => p?.copyWith(color: p.color.opposite))
                    .toList(),
            turn: side,
            castling: 0,
            enPassant: null,
            halfmoveClock: 0,
            fullmoveNumber: 10,
          );
  final initial = DeckManager.newBattle(
    board: board,
    white: starterDeck,
    black: starterDeck,
  );
  final draft =
      RuleDraft(initial.rules)
        ..phase = BattlePhase.chess
        ..ownTurns[side] = 3
        ..pieceEffects.add(
          ActivePieceEffect(
            id: 'e1',
            type: type,
            owner: side.opposite,
            pieceId: initial.rules.pieceIds[side.isWhite ? 8 : 55]!,
            responseSide: side,
            duration:
                type == PieceEffectType.mineDebuff
                    ? EffectDuration.pieceMove
                    : EffectDuration.move,
          ),
        )
        ..effectSequence = 1;
  return AuthoritativeBattleState(draft.freeze(), initial.hidden);
}

void main() {
  for (final side in PieceColor.values) {
    int orient(int square) => side.isWhite ? square : 63 - square;
    for (final type in [
      PieceEffectType.chain,
      PieceEffectType.mineDebuff,
      PieceEffectType.slow,
      PieceEffectType.freeze,
    ]) {
      test(
        '${type.name}/${side.name}: blocked tap retains inspectable piece without granting a move',
        () {
          final state = restricted(type, side), view = state.view(side);
          final actions = BattleRulesCore.legalActions(view);
          final selection = BattleInteraction()..synchronize(view, 0);
          expect(selection.tap(orient(8), view, actions), isEmpty);
          expect(selection.piece, orient(8));
          final invalid = orient(
            type == PieceEffectType.slow
                ? 32
                : type == PieceEffectType.freeze
                ? 16
                : 24,
          );
          expect(selection.tap(invalid, view, actions), isEmpty);
          expect(selection.piece, orient(8));
          expect(selection.invalidTarget, isTrue);
          expect(selection.targets(view, actions), isNot(contains(invalid)));
          expect(selection.play, isNull);
          expect(state.rules.ply, 0);
          if (type != PieceEffectType.freeze) {
            final moves = selection.tap(orient(16), view, actions);
            expect(moves.whereType<ChessMoveAction>(), hasLength(1));
            expect(selection.invalidTarget, isFalse);
            final moved = DeckManager.apply(state, moves.single);
            expect(moved.rules.ply, 1);
          }
          selection.cancel();
          expect(selection.piece, isNull);
          expect(selection.invalidTarget, isFalse);
        },
      );

      for (final language in ['tr', 'en']) {
        testWidgets(
          '${type.name}/${side.name}/$language: actual battle explains the active restriction',
          (tester) async {
            tester.view.physicalSize = const Size(390, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final state = restricted(type, side);
            final requests = <String>[];
            final controller = BattleV1Controller(
              uid: side.isWhite ? 'self' : 'other',
              matchId: v1MatchId,
              initialResponse: v1Response(state: state, side: side),
              persistPending: (_) async {},
              request: (path, body) async {
                requests.add(path);
                return v1Response(state: state, side: side);
              },
            );
            addTearDown(controller.dispose);
            await tester.pumpWidget(
              MaterialApp(
                locale: Locale(language),
                supportedLocales: LunoLocalizations.supportedLocales,
                localizationsDelegates: const [
                  LunoLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: BattleV1Screen(controllerOverride: controller),
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(ValueKey('square-${orient(8)}')));
            await tester.pumpAndSettle();
            final term = switch (type) {
              PieceEffectType.freeze =>
                language == 'tr' ? 'Dondurma:' : 'Freeze:',
              PieceEffectType.chain => language == 'tr' ? 'Zincir:' : 'Chain:',
              PieceEffectType.slow =>
                language == 'tr' ? 'Yavaşlatma:' : 'Slow:',
              _ => language == 'tr' ? 'Mayın:' : 'Mine:',
            };
            expect(find.textContaining(term), findsWidgets);
            expect(
              requests.where((path) => path == '/submitBattleV1Action'),
              isEmpty,
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
}
