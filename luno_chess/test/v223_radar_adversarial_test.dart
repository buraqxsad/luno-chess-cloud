import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/feedback.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_ui/private.dart';
import 'package:luno_chess/battle_ui/sheets.dart';
import 'package:luno_chess/battle_ui/spell_vfx.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/local_session.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/engine/move_gen.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';

import 'helpers/battle_v1_response.dart';
import 'helpers/v223_radar_cases.dart';

void _observation(
  AuthoritativeBattleState state,
  PieceColor observer, {
  required CardId query,
  required bool positive,
  required bool stale,
  int drawsAt = 3,
}) {
  final result = radarResult(state, observer);
  expect(result.queriedCardId, query);
  expect(result.inHand, positive);
  expect(result.stale, stale);
  expect(result.observedTurn, 0);
  expect(result.opponentCumulativeDrawCountAtObservation, drawsAt);
  expect(state.view(observer.opposite).knowledge.radarObservations, isEmpty);
}

AuthoritativeBattleState _kingMove(AuthoritativeBattleState state) =>
    DeckManager.apply(
      state,
      ChessMoveAction(state.rules.board.turn.isWhite ? 'e1d1' : 'e8d8'),
    );

Map<String, dynamic> _response(
  AuthoritativeBattleState state,
  PieceColor side,
  int version,
) => v1Response(state: state, side: side, version: version);

Widget _app(Widget child, {String language = 'en', double? textScale}) =>
    MaterialApp(
      locale: Locale(language),
      supportedLocales: LunoLocalizations.supportedLocales,
      localizationsDelegates: const [
        LunoLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder:
          textScale == null
              ? null
              : (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
      home: child,
    );

Future<void> _tap(WidgetTester tester, String key) async {
  final control = find.byKey(ValueKey(key));
  expect(control, findsOneWidget);
  await tester.ensureVisible(control);
  expect(control.hitTestable(), findsOneWidget);
  await tester.tap(control);
  await tester.pumpAndSettle();
}

String _radarText(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('battle-radar-result')),
        matching: find.byType(Text),
      ),
    )
    .map((text) => text.data ?? '')
    .join('\n');

void main() {
  for (final side in PieceColor.values) {
    test(
      'RADAR ${side.name}: all 24 query identities preserve historical answers',
      () {
        for (final query in CardId.values) {
          for (final index in [0, 3, 9]) {
            final before = radarFixture(
              side: side,
              opponentDeck: radarQueryDeck(query, index),
            );
            final cast = radarCast(before, query);
            _observation(
              cast,
              side,
              query: query,
              positive: index == 0,
              stale: false,
            );
            final reply = _kingMove(cast);
            _observation(
              reply,
              side,
              query: query,
              positive: index == 0,
              stale: false,
            );
            final cardPhase = DeckManager.apply(
              reply,
              index == 0 ? DiscardAction(query) : const PassAction(),
            );
            _observation(
              cardPhase,
              side,
              query: query,
              positive: index == 0,
              stale: index == 0,
            );
            final moved = _kingMove(cardPhase);
            _observation(
              moved,
              side,
              query: query,
              positive: index == 0,
              stale: true,
            );
            expect(
              moved.hidden.hands[side.opposite]!.contains(query),
              index == 3,
            );
            expect(radarResult(cast, side).stale, false);
          }
        }
      },
    );

    test(
      'RADAR ${side.name}: Shadow Contract sacrifice is public spend, not acquisition',
      () {
        final deck = [
          CardId.shadowContract,
          CardId.freeze,
          CardId.chain,
          ...radarOpponentDeck.where(
            (c) =>
                ![
                  CardId.shadowContract,
                  CardId.freeze,
                  CardId.chain,
                ].contains(c),
          ),
        ];
        for (final query in [
          CardId.shadowContract,
          CardId.freeze,
          CardId.chain,
          CardId.shelter,
        ]) {
          final cast = radarCast(
            radarFixture(side: side, opponentDeck: deck),
            query,
          );
          final played = DeckManager.apply(
            _kingMove(cast),
            const PlayCardAction(
              CardId.shadowContract,
              sacrifice: CardId.freeze,
            ),
          );
          expect(played.rules.pending, isNull);
          expect(played.rules.phase, BattlePhase.chess);
          expect(played.rules.drawCounts[side.opposite], 3);
          _observation(
            played,
            side,
            query: query,
            positive: query != CardId.shelter,
            stale: query == CardId.shadowContract || query == CardId.freeze,
          );
          _observation(
            _kingMove(played),
            side,
            query: query,
            positive: query != CardId.shelter,
            stale: query != CardId.chain,
          );
        }
      },
    );

    for (final position in radarEdgePositions(side)) {
      test(
        'RADAR ${side.name}/${position.id}: board rights and safety survive',
        () {
          for (final query in radarOpponentDeck) {
            final before = radarFixture(side: side, fen: position.fen);
            final original = jsonEncode(before.toJson());
            final after = radarCast(before, query);
            expect(after.rules.fen, position.fen);
            expect(after.rules.pieceIds, before.rules.pieceIds);
            expect(after.rules.movedPawns, before.rules.movedPawns);
            expect(after.rules.phase, BattlePhase.chess);
            expect(after.rules.special, isNull);
            expect(after.rules.pending, isNull);
            expect(after.rules.drawCounts, before.rules.drawCounts);
            expect(after.rules.effectSequence, before.rules.effectSequence);
            expect(
              after.hidden.hands[side.opposite],
              before.hidden.hands[side.opposite],
            );
            expect(
              after.hidden.decks[side.opposite],
              before.hidden.decks[side.opposite],
            );
            _observation(
              after,
              side,
              query: query,
              positive: radarOpponentDeck.take(3).contains(query),
              stale: false,
            );
            final legal =
                BattleRulesCore.legalActions(
                  after.view(side),
                ).whereType<ChessMoveAction>().toList();
            final keys = legal.map((a) => a.uci).toSet();
            expect(keys, containsAll(position.requiredMoves));
            for (final forbidden in position.forbiddenMoves) {
              expect(keys, isNot(contains(forbidden)));
              expect(
                () => DeckManager.apply(after, ChessMoveAction(forbidden)),
                throwsStateError,
              );
            }
            if (position.kingOnly) {
              expect(
                legal.every(
                  (a) => a.uci.startsWith(side.isWhite ? 'e1' : 'e8'),
                ),
                true,
                reason:
                    'Radar cannot release the absolute pin or double check.',
              );
            }
            for (final action in legal) {
              final moved = DeckManager.apply(after, action);
              expect(MoveGen.inCheck(moved.rules.board, side), false);
              expect(
                radarResult(moved, side).toJson(),
                radarResult(after, side).toJson(),
              );
              if (position.id == 'seventy-five-move-boundary' &&
                  action.uci.startsWith(side.isWhite ? 'e1' : 'e8')) {
                expect(moved.rules.terminal?.reason, 'seventy_five_moves');
                expect(moved.rules.drawCounts[side], 3);
              }
            }
            expect(jsonEncode(before.toJson()), original);
          }
        },
      );
    }

    test('RADAR ${side.name}: arsenal choice ignores all 64 board squares', () {
      final state = radarFixture(side: side);
      final view = state.view(side);
      final actions = BattleRulesCore.legalActions(view);
      final selection = BattleInteraction()..select(CardId.radar, actions);
      selection.play = const PlayCardAction(CardId.radar, target: 'chain');
      expect(selection.targets(view, actions), isEmpty);
      for (var square = 0; square < 64; square++) {
        expect(selection.tap(square, view, actions), isEmpty);
        expect(selection.play!.target, 'chain');
        expect(selection.piece, isNull);
        expect(selection.preview(), isEmpty);
        expect(selection.invalidTarget, false);
      }
      selection.select(CardId.radar, actions);
      expect(selection.play, isNull);
      expect(selection.card, isNull);
    });

    test(
      'RADAR ${side.name}: observation records ply rather than own-turn count',
      () {
        final before = radarEdit(
          radarFixture(side: side),
          (draft) => draft.ply = 87,
        );
        final after = radarCast(before, CardId.chain);
        final observation = radarResult(after, side);
        expect(observation.observedTurn, 87);
        expect(observation.opponentCumulativeDrawCountAtObservation, 3);
        expect(observation.inHand, true);
        final moved = _kingMove(
          DeckManager.apply(_kingMove(after), const PassAction()),
        );
        expect(radarResult(moved, side).toJson(), observation.toJson());
      },
    );

    for (final remaining in [1, 2, 3]) {
      test(
        'RADAR ${side.name}: exchange with $remaining deck cards stales only on take',
        () {
          final enemy = side.opposite;
          final tail =
              [
                CardId.shelter,
                CardId.radar,
                CardId.prophecy,
              ].take(remaining).toList();
          const hand = [CardId.fateExchange, CardId.freeze, CardId.chain];
          final used =
              radarOpponentDeck
                  .where((c) => !hand.contains(c) && !tail.contains(c))
                  .toList();
          final before = radarRepartition(
            radarFixture(side: side),
            enemy,
            hand: hand,
            deck: tail,
            used: used,
          );
          final draws = 10 - remaining;
          final cast = radarCast(before, CardId.shelter);
          final pending = DeckManager.apply(
            _kingMove(cast),
            const PlayCardAction(CardId.fateExchange, sacrifice: CardId.freeze),
          );
          _observation(
            pending,
            side,
            query: CardId.shelter,
            positive: false,
            stale: false,
            drawsAt: draws,
          );
          expect(pending.view(enemy).knowledge.pendingCards, tail);
          expect(pending.view(side).knowledge.pendingCards, isEmpty);
          final resolutions =
              BattleRulesCore.legalActions(
                pending.view(enemy),
              ).whereType<ResolveAction>().toList();
          expect(
            resolutions,
            hasLength(
              remaining == 1
                  ? 1
                  : remaining == 2
                  ? 2
                  : 6,
            ),
          );
          for (final action in resolutions) {
            final resolved = DeckManager.apply(pending, action);
            _observation(
              resolved,
              side,
              query: CardId.shelter,
              positive: false,
              stale: true,
              drawsAt: draws,
            );
            expect(resolved.rules.drawCounts[enemy], draws + 1);
            expect(resolved.hidden.decks[enemy], action.order);
            expect(
              resolved.view(enemy).knowledge.knownUpcomingCards,
              action.order,
            );
            final moved = _kingMove(resolved);
            expect(
              moved.rules.drawCounts[enemy],
              draws + (remaining == 1 ? 1 : 2),
            );
            expect(radarResult(moved, side).stale, true);
            expect(radarResult(cast, side).stale, false);
          }
        },
      );
    }

    test(
      'RADAR ${side.name}: unknown result must not become negative knowledge',
      () {
        final cast = radarCast(radarFixture(side: side), CardId.chain);
        for (final value in <Object?>[
          null,
          'UNKNOWN',
          'in_hand',
          '',
          true,
          0,
          [],
          {},
        ]) {
          final observation = <String, Object?>{
            ...radarResult(cast, side).toJson(),
            'result': value,
          };
          expect(
            () => RadarObservation.fromJson(observation),
            throwsFormatException,
            reason: 'An unrecognized result is not an assertion of absence.',
          );
        }
        final missing = radarResult(cast, side).toJson()..remove('result');
        expect(() => RadarObservation.fromJson(missing), throwsFormatException);
      },
    );

    test(
      'RADAR ${side.name}: snapshot rejects corrupted result before displaying it',
      () {
        final cast = radarCast(radarFixture(side: side), CardId.chain);
        final response = _response(cast, side, 80);
        final private = (response['view'] as Map)['private'] as Map;
        final knowledge = jsonDecode(private['knowledgeJson'] as String) as Map;
        (knowledge['radarObservations'] as List).single['result'] =
            'UNAVAILABLE';
        private['knowledgeJson'] = jsonEncode(knowledge);
        expect(
          () => BattleV1Snapshot.fromResponse(
            response,
            side.isWhite ? 'self' : 'other',
          ),
          throwsFormatException,
        );
      },
    );
  }

  test('RADAR timing retains the V222 travel, impact and settle contract', () {
    final timing = battleEffectTiming(CardId.radar);
    expect(timing.total, const Duration(milliseconds: 1600));
    expect(timing.travel, const Duration(milliseconds: 480));
    expect(timing.impact, const Duration(milliseconds: 800));
    expect(timing.settle, const Duration(milliseconds: 320));
    expect(
      battleCardFeedbackPacingDuration(CardId.radar),
      const Duration(milliseconds: 480),
    );
  });

  for (final observer in PieceColor.values) {
    final enemy = observer.opposite;
    group('RADAR ${observer.name} adversarial authority', () {
      test(
        'absence stales at exchange acquisition, not sacrifice or inspect',
        () {
          final cast = radarCast(radarFixture(side: observer), CardId.shelter);
          final frozen = jsonEncode(cast.toJson());
          final reply = _kingMove(cast);
          final pending = DeckManager.apply(
            reply,
            const PlayCardAction(CardId.fateExchange, sacrifice: CardId.freeze),
          );
          _observation(
            pending,
            observer,
            query: CardId.shelter,
            positive: false,
            stale: false,
          );
          expect(pending.rules.drawCounts[enemy], 3);
          expect(pending.view(observer).knowledge.pendingCards, isEmpty);
          final choices =
              BattleRulesCore.legalActions(
                pending.view(enemy),
              ).whereType<ResolveAction>().toList();
          expect(choices, hasLength(6));
          for (final choice in choices) {
            final resolved = DeckManager.apply(pending, choice);
            _observation(
              resolved,
              observer,
              query: CardId.shelter,
              positive: false,
              stale: true,
            );
            expect(resolved.rules.drawCounts[enemy], 4);
            expect(resolved.view(observer).knowledge.pendingCards, isEmpty);
            expect(
              resolved.view(observer).knowledge.knownUpcomingCards,
              isEmpty,
            );
            expect(resolved.hidden.hands[enemy], contains(choice.selected));
            expect(_kingMove(resolved).rules.drawCounts[enemy], 5);
            expect(jsonEncode(cast.toJson()), frozen);
          }
        },
      );

      test(
        'positive sacrifice stales before exchange resolves; sibling stays',
        () {
          for (final query in [
            CardId.freeze,
            CardId.chain,
            CardId.fateExchange,
          ]) {
            final cast = radarCast(radarFixture(side: observer), query);
            final reply = _kingMove(cast);
            final pending = DeckManager.apply(
              reply,
              const PlayCardAction(
                CardId.fateExchange,
                sacrifice: CardId.freeze,
              ),
            );
            final stale = query != CardId.chain;
            _observation(
              pending,
              observer,
              query: query,
              positive: true,
              stale: stale,
            );
            final resolved = DeckManager.apply(
              pending,
              BattleRulesCore.legalActions(
                pending.view(enemy),
              ).whereType<ResolveAction>().last,
            );
            final moved = _kingMove(resolved);
            _observation(
              moved,
              observer,
              query: query,
              positive: true,
              stale: stale,
            );
            expect(
              radarResult(cast, observer).stale,
              false,
              reason: 'An old accepted projection must remain immutable.',
            );
          }
        },
      );

      test(
        'Prophecy reordering is not acquisition and cannot stale absence',
        () {
          final deck = [
            CardId.prophecy,
            CardId.freeze,
            CardId.chain,
            ...radarOpponentDeck.where(
              (c) =>
                  ![CardId.prophecy, CardId.freeze, CardId.chain].contains(c),
            ),
          ];
          final reply = _kingMove(
            radarCast(
              radarFixture(side: observer, opponentDeck: deck),
              CardId.shelter,
            ),
          );
          final pending = DeckManager.apply(
            reply,
            const PlayCardAction(CardId.prophecy),
          );
          _observation(
            pending,
            observer,
            query: CardId.shelter,
            positive: false,
            stale: false,
          );
          for (final order
              in BattleRulesCore.legalActions(
                pending.view(enemy),
              ).whereType<ResolveAction>()) {
            final resolved = DeckManager.apply(pending, order);
            _observation(
              resolved,
              observer,
              query: CardId.shelter,
              positive: false,
              stale: false,
            );
            expect(resolved.rules.drawCounts[enemy], 3);
            _observation(
              _kingMove(resolved),
              observer,
              query: CardId.shelter,
              positive: false,
              stale: true,
            );
          }
        },
      );

      test(
        'full hand suppresses draw and preserves a negative observation',
        () {
          final initial = radarRepartition(
            radarFixture(side: observer),
            enemy,
            hand: radarOpponentDeck.take(4).toList(),
            deck: radarOpponentDeck.skip(4).toList(),
          );
          final reply = _kingMove(radarCast(initial, CardId.radar));
          final moved = _kingMove(DeckManager.apply(reply, const PassAction()));
          expect(moved.rules.drawCounts[enemy], 4);
          expect(moved.rules.deckCounts[enemy], 6);
          _observation(
            moved,
            observer,
            query: CardId.radar,
            positive: false,
            stale: false,
            drawsAt: 4,
          );
        },
      );

      test(
        'empty deck keeps a positive observation and excludes spent cards',
        () {
          final initial = radarRepartition(
            radarFixture(side: observer),
            enemy,
            hand: const [CardId.freeze, CardId.chain],
            deck: const [],
            used:
                radarOpponentDeck
                    .where((c) => c != CardId.freeze && c != CardId.chain)
                    .toList(),
          );
          expect(
            BattleRulesCore.cardTargets(initial.view(observer), CardId.radar),
            unorderedEquals(['freeze', 'chain']),
          );
          final moved = _kingMove(
            DeckManager.apply(
              _kingMove(radarCast(initial, CardId.freeze)),
              const PassAction(),
            ),
          );
          expect(moved.rules.drawCounts[enemy], 10);
          _observation(
            moved,
            observer,
            query: CardId.freeze,
            positive: true,
            stale: false,
            drawsAt: 10,
          );
        },
      );

      test(
        'opponent mating move suppresses acquisition and preserves absence',
        () {
          final fen =
              observer.isWhite
                  ? '8/8/8/8/6q1/8/5k2/7K w - - 0 12'
                  : 'k7/2K5/8/1Q6/8/8/8/8 b - - 0 12';
          final cast = radarCast(
            radarFixture(side: observer, fen: fen),
            CardId.radar,
          );
          final reply = DeckManager.apply(
            cast,
            ChessMoveAction(observer.isWhite ? 'h1h2' : 'a8a7'),
          );
          final mate = DeckManager.apply(
            DeckManager.apply(reply, const PassAction()),
            ChessMoveAction(observer.isWhite ? 'g4g2' : 'b5b7'),
          );
          expect(mate.rules.terminal?.reason, 'checkmate');
          expect(mate.rules.terminal?.winner, enemy);
          expect(mate.rules.drawCounts[enemy], 3);
          _observation(
            mate,
            observer,
            query: CardId.radar,
            positive: false,
            stale: false,
          );
        },
      );

      test('Radar under check never authorizes an unsafe chess escape', () {
        final fen =
            observer.isWhite
                ? '4k3/pp6/8/8/8/8/P3r3/4K3 w - - 0 12'
                : '4k3/p3R3/8/8/8/8/PP6/4K3 b - - 0 12';
        final initial = radarFixture(side: observer, fen: fen);
        expect(MoveGen.inCheck(initial.rules.board, observer), true);
        final cast = radarCast(initial, CardId.freeze);
        expect(cast.rules.fen, initial.rules.fen);
        expect(MoveGen.inCheck(cast.rules.board, observer), true);
        final unsafe = ChessMoveAction(observer.isWhite ? 'a2a3' : 'a7a6');
        expect(() => DeckManager.apply(cast, unsafe), throwsStateError);
        final escapes =
            BattleRulesCore.legalActions(
              cast.view(observer),
            ).whereType<ChessMoveAction>().toList();
        expect(escapes, isNotEmpty);
        for (final escape in escapes) {
          final escaped = DeckManager.apply(cast, escape);
          expect(MoveGen.inCheck(escaped.rules.board, observer), false);
          expect(
            escaped.view(observer).knowledge.radarObservations,
            hasLength(1),
          );
        }
      });

      test(
        'card-window cleanup overlaps do not turn Radar into a board card',
        () {
          final ownPawn = observer.isWhite ? 8 : 48;
          final enemyPawn = observer.isWhite ? 48 : 8;
          final initial = radarEdit(radarFixture(side: observer), (draft) {
            draft.pieceEffects.addAll([
              ActivePieceEffect(
                id: 'radar-shelter',
                type: PieceEffectType.shelter,
                owner: enemy,
                pieceId: draft.pieceIds[enemyPawn]!,
                responseSide: observer,
                duration: EffectDuration.card,
              ),
              ActivePieceEffect(
                id: 'radar-freeze',
                type: PieceEffectType.freeze,
                owner: enemy,
                pieceId: draft.pieceIds[ownPawn]!,
                responseSide: observer,
                duration: EffectDuration.move,
              ),
            ]);
            draft.boardEffects.addAll([
              BoardEffectInstance(
                id: 'radar-fog',
                type: BoardEffectType.fog,
                owner: enemy,
                squares: boardZone(enemyPawn),
                responseSide: observer,
                duration: EffectDuration.card,
              ),
              BoardEffectInstance(
                id: 'radar-mine',
                type: BoardEffectType.mine,
                owner: enemy,
                squares: const [27],
                responseSide: observer,
                duration: EffectDuration.persistent,
              ),
            ]);
          });
          final cast = radarCast(initial, CardId.shelter);
          expect(cast.rules.pieceEffects.map((e) => e.id), ['radar-freeze']);
          expect(cast.rules.boardEffects.map((e) => e.id), ['radar-mine']);
          expect(cast.rules.special, isNull);
          expect(cast.rules.pending, isNull);
          _observation(
            cast,
            observer,
            query: CardId.shelter,
            positive: false,
            stale: false,
          );
          expect(_kingMove(cast).rules.pieceEffects, isEmpty);
        },
      );

      test(
        'discount, sabotage, Echo and future modifiers have separate windows',
        () {
          final initial = radarEdit(radarFixture(side: observer, mana: 1), (
            draft,
          ) {
            draft.mana[enemy] = 3;
            for (final (id, type, card, ownTurn) in [
              ('discount', ModifierType.discount, null, 3),
              ('sabotage', ModifierType.manaSabotage, CardId.radar, 3),
              ('echo', ModifierType.echo, CardId.radar, 3),
              ('echo-other', ModifierType.echo, CardId.freeze, 3),
              ('future-block', ModifierType.cardBlock, CardId.radar, 4),
            ]) {
              draft.modifiers.add(
                PendingModifier(
                  id: id,
                  type: type,
                  owner: enemy,
                  responseSide: observer,
                  targetCard: card,
                  ownTurn: ownTurn,
                ),
              );
            }
          });
          expect(
            BattleRulesCore.effectiveCost(
              initial.rules,
              observer,
              CardId.radar,
            ),
            1,
          );
          final cast = radarCast(initial, CardId.chain);
          expect(cast.rules.mana[observer], 0);
          expect(cast.rules.mana[enemy], 5);
          expect(cast.rules.modifiers.map((m) => m.id), ['future-block']);
          _observation(
            cast,
            observer,
            query: CardId.chain,
            positive: true,
            stale: false,
          );
        },
      );

      test(
        'blocking Radar still permits discard without producing knowledge',
        () {
          final initial = radarEdit(radarFixture(side: observer), (draft) {
            draft.modifiers.add(
              PendingModifier(
                id: 'block',
                type: ModifierType.cardBlock,
                owner: enemy,
                responseSide: observer,
                targetCard: CardId.radar,
                ownTurn: 3,
              ),
            );
          });
          final selection = BattleInteraction();
          final legal = BattleRulesCore.legalActions(initial.view(observer));
          selection.select(CardId.radar, legal);
          expect(selection.card, CardId.radar);
          expect(selection.options(legal), isEmpty);
          expect(selection.play, isNull);
          expect(() => radarCast(initial, CardId.chain), throwsStateError);
          final discarded = DeckManager.apply(
            initial,
            const DiscardAction(CardId.radar),
          );
          expect(discarded.rules.mana[observer], 6);
          expect(discarded.view(observer).knowledge.radarObservations, isEmpty);
          expect(discarded.rules.phase, BattlePhase.chess);
        },
      );

      test(
        'target selected one turn ago rejects after opponent publicly uses it',
        () {
          final initial = radarFixture(side: observer);
          const captured = PlayCardAction(CardId.radar, target: 'chain');
          final selection =
              BattleInteraction()..synchronize(initial.view(observer), 20);
          selection.select(
            CardId.radar,
            BattleRulesCore.legalActions(initial.view(observer)),
          );
          selection.play = captured;
          var advanced = _kingMove(
            DeckManager.apply(initial, const PassAction()),
          );
          advanced = DeckManager.apply(
            advanced,
            PlayCardAction(CardId.chain, target: observer.isWhite ? 8 : 48),
          );
          advanced = _kingMove(advanced);
          final frozen = jsonEncode(advanced.toJson());
          selection.synchronize(advanced.view(observer), 24);
          expect(selection.card, isNull);
          expect(selection.play, isNull);
          expect(() => DeckManager.apply(advanced, captured), throwsStateError);
          expect(jsonEncode(advanced.toJson()), frozen);
          expect(advanced.view(observer).knowledge.radarObservations, isEmpty);
          expect(
            BattleRulesCore.cardTargets(advanced.view(observer), CardId.radar),
            isNot(contains('chain')),
          );
        },
      );

      test(
        'changing only the hidden opponent partition changes only the answer',
        () {
          final first = radarFixture(side: observer);
          final second = radarFixture(
            side: observer,
            opponentDeck: [
              CardId.shelter,
              CardId.freeze,
              CardId.chain,
              CardId.fateExchange,
              ...radarOpponentDeck.where(
                (c) =>
                    ![
                      CardId.shelter,
                      CardId.freeze,
                      CardId.chain,
                      CardId.fateExchange,
                    ].contains(c),
              ),
            ],
          );
          expect(
            jsonEncode(first.rules.toJson()),
            jsonEncode(second.rules.toJson()),
          );
          expect(first.view(observer).toJson(), second.view(observer).toJson());
          final castA = radarCast(first, CardId.shelter);
          final castB = radarCast(second, CardId.shelter);
          expect(radarResult(castA, observer).inHand, false);
          expect(radarResult(castB, observer).inHand, true);
          expect(
            jsonEncode(castA.rules.toJson()),
            jsonEncode(castB.rules.toJson()),
          );
          expect(castA.view(observer).ownHand, castB.view(observer).ownHand);
          expect(
            castA.view(enemy).knowledge.toJson(),
            castB.view(enemy).knowledge.toJson(),
          );
          final cueA = BattleSpellCue.fromViews(
            CardId.radar,
            observer,
            first.view(enemy),
            castA.view(enemy),
          );
          final cueB = BattleSpellCue.fromViews(
            CardId.radar,
            observer,
            second.view(enemy),
            castB.view(enemy),
          );
          expect(cueA.squares, isEmpty);
          expect(cueB.squares, isEmpty);
          expect(cueA.resourceSide, cueB.resourceSide);
          expect(
            acceptedBattleCasts(castA.view(observer), castA.view(observer)),
            isEmpty,
          );
        },
      );
    });
  }

  test('offline hotseat owns the result across both viewer handoffs', () async {
    final session = BattleV1LocalSession(
      hotseat: true,
      practice: true,
      practiceDeck: radarOwnDeck,
      random: Random(223),
    );
    addTearDown(session.dispose);
    expect(await session.submit(const ChessMoveAction('e2e4')), true);
    final knownBlackCard = session.view.ownHand.first;
    expect(await session.submit(const ChessMoveAction('e7e5')), true);
    expect(
      await session.submit(
        PlayCardAction(CardId.radar, target: knownBlackCard.wire),
      ),
      true,
    );
    final old = session.view;
    expect(old.viewer, PieceColor.white);
    expect(old.knowledge.radarObservations.single.inHand, true);
    expect(await session.submit(const ChessMoveAction('g1f3')), true);
    expect(session.view.viewer, PieceColor.black);
    expect(session.view.knowledge.radarObservations, isEmpty);
    expect(await session.submit(const PassAction()), true);
    expect(await session.submit(const ChessMoveAction('g8f6')), true);
    expect(session.view.viewer, PieceColor.white);
    expect(session.view.knowledge.radarObservations.single.stale, false);
    expect(old.knowledge.radarObservations.single.stale, false);
    expect(
      await session.submit(
        PlayCardAction(CardId.radar, target: knownBlackCard.wire),
      ),
      false,
    );
  });

  test(
    'retry after an accepted response was lost keeps one private observation',
    () async {
      var state = radarFixture(side: PieceColor.black);
      var version = 40;
      var attempts = 0;
      String? actionId;
      final controller = BattleV1Controller(
        uid: 'other',
        matchId: v1MatchId,
        initialResponse: _response(state, PieceColor.black, version),
        persistPending: (_) async {},
        request: (path, body) async {
          if (path == '/submitBattleV1Action') {
            attempts++;
            expect(body['expectedStateVersion'], 40);
            if (attempts == 1) {
              actionId = body['actionId'] as String;
              state = DeckManager.apply(
                state,
                BattleAction.fromJson(body['intent'] as Map),
              );
              version++;
              throw StateError('simulated-lost-ack');
            }
            expect(body['actionId'], actionId);
          }
          return _response(state, PieceColor.black, version);
        },
      );
      addTearDown(controller.dispose);
      expect(
        await controller.submit(
          const PlayCardAction(CardId.radar, target: 'shelter'),
        ),
        false,
      );
      expect(controller.hasPendingIntent, true);
      expect(controller.view!.knowledge.radarObservations, isEmpty);
      await controller.retryPending();
      expect(controller.hasPendingIntent, false);
      expect(controller.error, isNull);
      expect(controller.view!.knowledge.radarObservations, hasLength(1));
      final accepted = jsonEncode(controller.view!.knowledge.toJson());
      for (var i = 0; i < 3; i++) {
        await controller.reconnect(synchronization: false);
        expect(jsonEncode(controller.view!.knowledge.toJson()), accepted);
      }
      expect(attempts, 2);
      expect(state.rules.used[PieceColor.black], [CardId.radar]);
    },
  );

  test(
    'older private projection cannot revive an expired Radar answer',
    () async {
      final cast = radarCast(radarFixture(), CardId.shelter);
      final pending = DeckManager.apply(
        _kingMove(cast),
        const PlayCardAction(CardId.fateExchange, sacrifice: CardId.freeze),
      );
      final resolved = DeckManager.apply(
        pending,
        BattleRulesCore.legalActions(
          pending.view(PieceColor.black),
        ).whereType<ResolveAction>().first,
      );
      final controller = BattleV1Controller(
        uid: 'self',
        matchId: v1MatchId,
        initialResponse: _response(resolved, PieceColor.white, 54),
        persistPending: (_) async {},
        request: (_, _) async => _response(cast, PieceColor.white, 51),
      );
      addTearDown(controller.dispose);
      await controller.reconnect(synchronization: false);
      expect(controller.snapshot!.stateVersion, 54);
      expect(controller.view!.knowledge.radarObservations.single.stale, true);
      controller.invalidateSession();
      expect(controller.view, isNull);
      expect(controller.snapshot, isNull);
    },
  );

  for (final side in PieceColor.values) {
    testWidgets(
      'RADAR ${side.name} target cancel, submit and private visible answer',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var state = radarFixture(side: side);
        var version = 60;
        final sent = <BattleAction>[];
        final controller = BattleV1Controller(
          uid: side.isWhite ? 'self' : 'other',
          matchId: v1MatchId,
          initialResponse: _response(state, side, version),
          persistPending: (_) async {},
          request: (path, body) async {
            if (path == '/submitBattleV1Action') {
              final action = BattleAction.fromJson(body['intent'] as Map);
              sent.add(action);
              state = DeckManager.apply(state, action);
              version++;
            }
            return _response(state, side, version);
          },
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _app(BattleV1Screen(controllerOverride: controller)),
        );
        await tester.pumpAndSettle();
        await _tap(tester, 'hand-radar');
        await _tap(tester, 'arsenal-shelter');
        expect(sent, isEmpty);
        expect(find.byKey(const ValueKey('battle-radar-result')), findsNothing);
        // Toggling the selected card must not preserve the previous target.
        await _tap(tester, 'hand-radar');
        await _tap(tester, 'hand-radar');
        await _tap(tester, 'arsenal-chain');
        expect(sent, isEmpty);
        await _tap(tester, 'play-card');
        expect(sent.whereType<PlayCardAction>().single.target, 'chain');
        expect(_radarText(tester), contains('In hand'));
        expect(_radarText(tester), contains('Chain'));
        expect(state.view(side.opposite).knowledge.radarObservations, isEmpty);
        final accepted = controller.view!;
        await controller.reconnect(synchronization: false);
        await tester.pumpAndSettle();
        expect(sent, hasLength(1));
        expect(acceptedBattleCasts(accepted, controller.view!), isEmpty);
        expect(_radarText(tester), contains('In hand'));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'open Radar sheet is dismissed when Fate Exchange expires its answer',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var state = radarCast(radarFixture(), CardId.shelter);
      var version = 70;
      final controller = BattleV1Controller(
        uid: 'self',
        matchId: v1MatchId,
        initialResponse: _response(state, PieceColor.white, version),
        persistPending: (_) async {},
        request: (_, _) async => _response(state, PieceColor.white, version),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(BattleV1Screen(controllerOverride: controller)),
      );
      await tester.pumpAndSettle();
      expect(_radarText(tester), contains('Not in hand'));
      await _tap(tester, 'battle-radar-result');
      expect(find.byType(PrivateKnowledgeSheet), findsOneWidget);
      final pending = DeckManager.apply(
        _kingMove(state),
        const PlayCardAction(CardId.fateExchange, sacrifice: CardId.freeze),
      );
      state = DeckManager.apply(
        pending,
        BattleRulesCore.legalActions(
          pending.view(PieceColor.black),
        ).whereType<ResolveAction>().first,
      );
      version += 3;
      await controller.reconnect(synchronization: false);
      await tester.pumpAndSettle();
      expect(find.byType(PrivateKnowledgeSheet), findsNothing);
      expect(_radarText(tester), contains('Stale'));
      expect(_radarText(tester), isNot(contains('Not in hand')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'arsenal target sheet cannot distinguish hidden hand partitions',
    (tester) async {
      final first = radarFixture();
      final second = radarFixture(
        opponentDeck: [
          CardId.shelter,
          CardId.freeze,
          CardId.chain,
          CardId.fateExchange,
          ...radarOpponentDeck.where(
            (c) =>
                ![
                  CardId.shelter,
                  CardId.freeze,
                  CardId.chain,
                  CardId.fateExchange,
                ].contains(c),
          ),
        ],
      );
      final eligible =
          BattleRulesCore.cardTargets(
            first.view(PieceColor.white),
            CardId.radar,
          ).whereType<String>().map(CardId.parse).toSet();
      Future<List<String>> labels(AuthoritativeBattleState state) async {
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: OpponentArsenalSheet(
                rules: state.rules,
                opponent: PieceColor.black,
                eligible: eligible,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data ?? '')
            .toList();
      }

      expect(await labels(first), await labels(second));
      expect(find.text('In hand'), findsNothing);
      expect(find.text('Not in hand'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final side in PieceColor.values) {
    for (final stale in [false, true]) {
      for (final language in ['en', 'tr']) {
        testWidgets(
          'RADAR ${side.name}/$language: ${stale ? 'stale' : 'fresh'} result survives compact large-text card phase',
          (tester) async {
            tester.view.physicalSize = const Size(320, 568);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final cast = radarCast(
              radarFixture(side: side),
              stale ? CardId.shelter : CardId.chain,
            );
            final state = _kingMove(
              DeckManager.apply(_kingMove(cast), const PassAction()),
            );
            expect(state.rules.board.turn, side);
            expect(state.rules.phase, BattlePhase.card);
            expect(radarResult(state, side).stale, stale);
            final controller = BattleV1Controller(
              uid: side.isWhite ? 'self' : 'other',
              matchId: v1MatchId,
              initialResponse: _response(state, side, 90),
              persistPending: (_) async {},
              request: (_, _) async => _response(state, side, 90),
            );
            addTearDown(controller.dispose);
            await tester.pumpWidget(
              _app(
                BattleV1Screen(controllerOverride: controller),
                language: language,
                textScale: 1.5,
              ),
            );
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('battle-radar-result')),
              findsOneWidget,
              reason: 'Compact skip must not hide private Radar feedback.',
            );
            expect(_radarText(tester), isNotEmpty);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
}
