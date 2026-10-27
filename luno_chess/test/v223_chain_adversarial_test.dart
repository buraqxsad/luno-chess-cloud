import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/accepted_frames.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_ui/feedback.dart';
import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_ui/spell_vfx.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';

import 'helpers/battle_v1_response.dart';
import 'helpers/v223_chain_cases.dart';

Widget _app(Widget child, {String language = 'en', bool reduced = false}) =>
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
          (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
      home: child,
    );

Map<String, dynamic> _response(
  AuthoritativeBattleState state,
  PieceColor viewer,
  int version,
) {
  final response = v1Response(state: state, side: viewer, version: version);
  final public = response['view']['public'] as Map;
  public['players'] = {
    sideWire(viewer): {'uid': 'self', 'name': 'Self', 'bot': false},
    sideWire(viewer.opposite): {'uid': 'other', 'name': 'Other', 'bot': false},
  };
  (public['clock'] as Map)['activeSide'] = sideWire(state.rules.board.turn);
  return response;
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

List<BattleSpellPainter> _chainPainters(WidgetTester tester) =>
    tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.painter)
        .whereType<BattleSpellPainter>()
        .where((painter) => painter.cue.card == CardId.chain)
        .toList();

void main() {
  // Admission/discard payload typing is owned by v223_card_admission_test.dart.
  for (final auditCase in chainCoreCases()) {
    test('CHAIN core: ${auditCase.name}', auditCase.run);
  }

  for (final reflected in [false, true]) {
    final side = reflected ? chainBlack : chainWhite;
    final enemy = side.opposite;
    final prefix = side.name;
    int square(String text) => chainSquare(text) ^ (reflected ? 56 : 0);
    String move(String text) => reflected ? chainReflectMove(text) : text;
    AuthoritativeBattleState position(
      String fen, {
      BattlePhase phase = BattlePhase.card,
      List<CardId> hand = const [CardId.chain, CardId.purify, CardId.angryN],
    }) => chainPosition(
      fen,
      reflect: reflected,
      phase: phase,
      whiteHand: hand,
      blackHand: hand,
    );

    test('$prefix Chain targeting clears a protected or invalid retarget', () {
      var state = position('7k/8/8/8/1r1r4/8/8/R3K3 w - - 0 10');
      state = chainEdit(state, (draft) {
        draft.pieceEffects.add(
          ActivePieceEffect(
            id: 'v223-shelter',
            type: PieceEffectType.shelter,
            owner: enemy,
            pieceId: draft.pieceIds[square('b4')]!,
            responseSide: side,
            duration: EffectDuration.card,
          ),
        );
      });
      final view = state.view(side),
          actions = BattleRulesCore.legalActions(state.view(side));
      final selection = BattleInteraction()..select(CardId.chain, actions);
      expect(selection.targets(view, actions), {square('d4')});
      for (final invalid in ['b4', 'a1', 'h8', 'a3']) {
        selection.tap(square('d4'), view, actions);
        expect(selection.play?.target, square('d4'));
        expect(selection.preview(), {square('d4')});
        expect(selection.tap(square(invalid), view, actions), isEmpty);
        expect(selection.play, isNull, reason: '$invalid must not reuse d4');
        expect(selection.preview(), isEmpty);
        expect(selection.invalidTarget, isTrue);
      }
      expect(state.rules.pieceEffects.single.id, 'v223-shelter');
      expect(state.rules.used[side], isEmpty);
    });

    test(
      '$prefix capture-only restricted knight is inspectable but grants no move',
      () {
        final state = chainAddEffect(
          position(
            '7k/8/2r1r3/1r3r2/3N4/1r3r2/2r1r3/K7 w - - 0 10',
            phase: BattlePhase.chess,
          ),
          square('d4'),
        );
        final view = state.view(side),
            actions = BattleRulesCore.legalActions(state.view(side));
        final selection = BattleInteraction();
        expect(selection.tap(square('d4'), view, actions), isEmpty);
        expect(selection.piece, square('d4'));
        expect(selection.targets(view, actions), isEmpty);
        expect(selection.tap(square('f5'), view, actions), isEmpty);
        expect(selection.piece, square('d4'));
        expect(selection.invalidTarget, isTrue);
        expect(
          selection
              .moves(view, actions)
              .any(
                (action) => action.uci.startsWith(move('d4d4').substring(0, 2)),
              ),
          isFalse,
        );
        expect(selection.play, isNull);
      },
    );

    test(
      '$prefix card-window chess preview preserves Chain and blocks capture',
      () {
        final state = chainAddEffect(
          position('7k/8/8/8/Rp6/8/8/4K3 w - - 0 10'),
          square('a4'),
        );
        final before = jsonEncode(state.toJson());
        final view = state.view(side),
            actions = BattleRulesCore.legalActions(state.view(side));
        final selection = BattleInteraction();
        selection.tap(square('a4'), view, actions);
        expect(selection.piece, square('a4'));
        expect(selection.targets(view, actions), contains(square('a5')));
        expect(selection.targets(view, actions), isNot(contains(square('b4'))));
        expect(selection.tap(square('b4'), view, actions), isEmpty);
        expect(selection.invalidTarget, isTrue);
        expect(selection.piece, square('a4'));
        expect(
          selection
              .tap(square('a5'), view, actions)
              .map((action) => action.key),
          ['move:${move('a4a5')}'],
        );
        expect(
          jsonEncode(state.toJson()),
          before,
          reason: 'preview is read-only',
        );
      },
    );

    test(
      '$prefix Angry Knight invalid capture clears only the destination',
      () {
        final state = chainAddEffect(
          position('7k/8/8/3P4/2bNp3/8/8/4K3 w - - 0 10'),
          square('d4'),
        );
        final view = state.view(side),
            actions = BattleRulesCore.legalActions(state.view(side));
        final selection = BattleInteraction()..select(CardId.angryN, actions);
        selection.tap(square('d4'), view, actions);
        expect(selection.targets(view, actions), {square('d3')});
        selection.tap(square('d3'), view, actions);
        expect(selection.specialDestination?.uci, move('d4d3'));
        selection.tap(square('e4'), view, actions);
        expect(selection.specialDestination, isNull);
        expect(selection.piece, square('d4'));
        expect(selection.play?.card, CardId.angryN);
        expect(selection.invalidTarget, isTrue);
        expect(selection.preview(), {square('d4')});
      },
    );

    test(
      '$prefix Chain cue follows target identity after an opposing quiet move',
      () {
        final initial = position('7k/8/8/8/3r4/8/8/R3K3 w - - 0 10');
        final cast = DeckManager.apply(
          initial,
          PlayCardAction(CardId.chain, target: square('d4')),
        );
        final cue = BattleSpellCue.fromViews(
          CardId.chain,
          side,
          initial.view(side),
          cast.view(side),
        );
        final ownMove = DeckManager.apply(cast, ChessMoveAction(move('a1a2')));
        final response = DeckManager.apply(ownMove, const PassAction());
        final enemyMove = DeckManager.apply(
          response,
          ChessMoveAction(move('d4d5')),
        );
        expect(enemyMove.rules.pieceEffects, isEmpty);
        expect(cue.following(enemyMove.rules).squares, [square('d5')]);
        expect(cue.boundPieceIds, [initial.rules.pieceIds[square('d4')]]);
      },
    );

    test(
      'V223-CHAIN-01 $prefix captured target must not keep its occupied old square',
      () {
        final initial = position('1r5k/8/8/8/Rr6/8/8/4K3 w - - 0 10');
        final cast = DeckManager.apply(
          initial,
          PlayCardAction(CardId.chain, target: square('b4')),
        );
        final cue = BattleSpellCue.fromViews(
          CardId.chain,
          side,
          initial.view(side),
          cast.view(side),
        );
        final captured = DeckManager.apply(cast, ChessMoveAction(move('a4b4')));
        expect(captured.rules.pieceEffects, isEmpty);
        expect(
          captured.rules.pieceIds,
          isNot(contains(cue.boundPieceIds.single)),
        );
        expect(captured.rules.board.pieceAt(square('b4'))?.color, side);
        expect(
          cue.following(captured.rules).squares,
          isEmpty,
          reason:
              'A dead opposing identity must not visually chain the capturing own rook.',
        );
      },
    );

    test(
      '$prefix delayed Chain acceptance consumes effect and resources exactly once',
      () async {
        final initial = position('7k/8/8/8/3r4/8/8/R3K3 w - - 0 10');
        final play = PlayCardAction(CardId.chain, target: square('d4'));
        final accepted = DeckManager.apply(initial, play);
        final gate = Completer<Map<String, dynamic>>();
        final sent = <Map<String, dynamic>>[];
        final persisted = <String?>[];
        final controller = BattleV1Controller(
          uid: 'self',
          matchId: v1MatchId,
          initialResponse: _response(initial, side, 0),
          persistPending: (value) async => persisted.add(value),
          request: (path, body) async {
            expect(path, '/submitBattleV1Action');
            sent.add(Map<String, dynamic>.from(body));
            return gate.future;
          },
        );
        addTearDown(controller.dispose);
        final first = controller.submit(play);
        await Future<void>.delayed(Duration.zero);
        expect(controller.busy, isTrue);
        expect(controller.hasPendingIntent, isTrue);
        expect(controller.view!.rules.pieceEffects, isEmpty);
        expect(await controller.submit(play), isFalse);
        expect(sent, hasLength(1));
        gate.complete(_response(accepted, side, 1));
        expect(await first, isTrue);
        expect(controller.view!.rules.pieceEffects, hasLength(1));
        expect(controller.view!.rules.mana[side], 4);
        expect(controller.view!.rules.used[side], [CardId.chain]);
        expect(controller.view!.ownHand, hasLength(2));
        expect(controller.view!.rules.pieceEffects.single.responseSide, enemy);
        expect(
          controller.view!.rules.pieceEffects.single.duration,
          EffectDuration.move,
        );
        expect(persisted.whereType<String>(), hasLength(1));
        expect(persisted.last, isNull);
        await controller.retryPending();
        expect(sent, hasLength(1));
      },
    );

    test(
      '$prefix accepted Chain survives pending-journal cleanup retry without recast',
      () async {
        final initial = position('7k/8/8/8/3r4/8/8/R3K3 w - - 0 10');
        final play = PlayCardAction(CardId.chain, target: square('d4'));
        final accepted = DeckManager.apply(initial, play);
        var requests = 0, clearAttempts = 0;
        final controller = BattleV1Controller(
          uid: 'self',
          matchId: v1MatchId,
          initialResponse: _response(initial, side, 0),
          persistPending: (value) async {
            if (value == null && clearAttempts++ == 0) {
              throw StateError('test-storage');
            }
          },
          request: (path, body) async {
            requests++;
            return _response(accepted, side, 1);
          },
        );
        addTearDown(controller.dispose);
        expect(await controller.submit(play), isFalse);
        expect(controller.view!.rules.pieceEffects, hasLength(1));
        expect(controller.hasPendingIntent, isTrue);
        expect(controller.error, isNotNull);
        await controller.retryPending();
        expect(requests, 1, reason: 'accepted Chain must not be sent again');
        expect(controller.hasPendingIntent, isFalse);
        expect(controller.error, isNull);
        expect(controller.view!.rules.effectSequence, 1);
        expect(controller.view!.rules.mana[side], 4);
        expect(controller.view!.rules.used[side], [CardId.chain]);
      },
    );

    test(
      '$prefix rejected Chain never creates accepted feedback or debits mana',
      () async {
        final initial = position('7k/8/8/8/3r4/8/8/R3K3 w - - 0 10');
        final controller = BattleV1Controller(
          uid: 'self',
          matchId: v1MatchId,
          initialResponse: _response(initial, side, 0),
          persistPending: (_) async {},
          request:
              (path, body) async =>
                  throw const BattleV1Rejection('INVALID_ACTION'),
        );
        addTearDown(controller.dispose);
        final before = controller.view!;
        expect(
          await controller.submit(
            PlayCardAction(CardId.chain, target: square('d4')),
          ),
          isFalse,
        );
        expect(controller.hasPendingIntent, isFalse);
        expect(controller.view!.rules.pieceEffects, isEmpty);
        expect(controller.view!.rules.mana[side], 6);
        expect(controller.view!.ownHand, hasLength(3));
        expect(acceptedBattleCasts(before, controller.view!), isEmpty);
      },
    );

    for (final language in ['tr', 'en']) {
      testWidgets(
        '$prefix/$language screen protected retarget cannot submit stale Chain',
        (tester) async {
          _phone(tester);
          var state = position('7k/8/8/8/1r1r4/8/8/R3K3 w - - 0 10');
          state = chainEdit(
            state,
            (draft) => draft.pieceEffects.add(
              ActivePieceEffect(
                id: 'v223-shelter',
                type: PieceEffectType.shelter,
                owner: enemy,
                pieceId: draft.pieceIds[square('b4')]!,
                responseSide: side,
                duration: EffectDuration.card,
              ),
            ),
          );
          final sent = <BattleAction>[];
          var version = 0;
          final controller = BattleV1Controller(
            uid: 'self',
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
            _app(
              BattleV1Screen(controllerOverride: controller),
              language: language,
            ),
          );
          await tester.pumpAndSettle();
          await _tap(tester, 'hand-chain');
          await _tap(tester, 'square-${square('d4')}');
          expect(
            find.byKey(ValueKey('card-preview-${square('d4')}')),
            findsOneWidget,
          );
          await _tap(tester, 'square-${square('b4')}');
          expect(
            find.byKey(ValueKey('card-preview-${square('d4')}')),
            findsNothing,
          );
          expect(
            find.textContaining(
              language == 'en' ? 'That target is not valid.' : 'Bu hedef uygun',
            ),
            findsOneWidget,
          );
          await _tap(tester, 'play-card');
          expect(sent, isEmpty);
          expect(state.rules.mana[side], 6);
          await _tap(tester, 'square-${square('d4')}');
          await _tap(tester, 'play-card');
          expect(sent.whereType<PlayCardAction>().map((action) => action.key), [
            'play:chain:${square('d4')}:',
          ]);
          expect(
            state.rules.pieceEffects.single.type,
            PieceEffectType.chain,
            reason: 'response-window Shelter closes, new Chain remains',
          );
          expect(
            state.rules.pieceEffects.single.pieceId,
            state.rules.pieceIds[square('d4')],
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );

      testWidgets(
        '$prefix/$language screen explains Chain and other-piece move expires it',
        (tester) async {
          _phone(tester);
          var state = chainAddEffect(
            position('7k/8/8/8/Rp6/8/8/4K3 w - - 0 10'),
            square('a4'),
          );
          var version = 0;
          final sent = <BattleAction>[];
          final controller = BattleV1Controller(
            uid: 'self',
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
            _app(
              BattleV1Screen(controllerOverride: controller),
              language: language,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('piece-effect-v223-chain')),
            findsOneWidget,
          );
          await _tap(tester, 'square-${square('a4')}');
          expect(
            find.textContaining(
              language == 'en'
                  ? 'Chain: this piece cannot capture.'
                  : 'Zincir:',
            ),
            findsOneWidget,
          );
          await _tap(tester, 'square-${square('b4')}');
          expect(sent, isEmpty);
          expect(
            find.textContaining(
              language == 'en' ? 'That destination is not legal.' : 'Bu hedefe',
            ),
            findsOneWidget,
          );
          await _tap(tester, 'square-${square('e1')}');
          await _tap(tester, 'square-${square('f1')}');
          expect(sent.map((action) => action.key), [
            'pass',
            'move:${move('e1f1')}',
          ]);
          expect(state.rules.pieceEffects, isEmpty);
          expect(state.rules.board.turn, enemy);
          expect(
            find.byKey(const ValueKey('piece-effect-v223-chain')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }

    testWidgets(
      'V223-CHAIN-01 $prefix combined cast/capture must not paint Chain on captor',
      (tester) async {
        final initial = position('1r5k/8/8/8/Rr6/8/8/4K3 w - - 0 10');
        final cast = DeckManager.apply(
          initial,
          PlayCardAction(CardId.chain, target: square('b4')),
        );
        final captured = DeckManager.apply(cast, ChessMoveAction(move('a4b4')));
        final tracker =
            BattlePresentationTracker()..observe(initial.view(side), 0);
        Widget feedback(AuthoritativeBattleState state) => _app(
          Scaffold(
            body: Center(
              child: SizedBox.square(
                dimension: 320,
                child: BattleAcceptedFeedback(
                  view: state.view(side),
                  acceptedFrames: tracker.frames,
                  showProjectiles: false,
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(feedback(initial));
        tracker.observe(cast.view(side), 1);
        tracker.observe(captured.view(side), 2);
        await tester.pumpWidget(feedback(captured));
        await tester.pump(const Duration(milliseconds: 700));
        expect(
          _chainPainters(
            tester,
          ).any((painter) => painter.cue.squares.contains(square('b4'))),
          isFalse,
          reason:
              'The live b4 piece is the caster\'s rook, not the chained victim.',
        );
        await tester.pump(battleEffectDuration(CardId.chain));
        await tester.pumpWidget(const SizedBox());
      },
    );

    for (final reduced in [false, true]) {
      testWidgets(
        '$prefix board and notice preserve Chain with reduced=$reduced',
        (tester) async {
          final initial = position('7k/8/8/8/3r4/8/8/R3K3 w - - 0 10');
          final cast = DeckManager.apply(
            initial,
            PlayCardAction(CardId.chain, target: square('d4')),
          );
          Widget board(AuthoritativeBattleState state, {int epoch = 0}) => _app(
            Scaffold(
              body: Column(
                children: [
                  BattleCastNotice(
                    view: state.view(side),
                    synchronizationEpoch: epoch,
                    child: const Text('baseline'),
                  ),
                  SizedBox.square(
                    dimension: 320,
                    child: BattleBoard(
                      view: state.view(side),
                      synchronizationEpoch: epoch,
                      onTap: (_) {},
                    ),
                  ),
                ],
              ),
            ),
            reduced: reduced,
          );
          await tester.pumpWidget(board(initial));
          await tester.pumpWidget(board(cast));
          await tester.pump(const Duration(milliseconds: 100));
          expect(
            find.byKey(
              ValueKey('piece-effect-${cast.rules.pieceEffects.single.id}'),
            ),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('cast-notice-chain')),
            findsOneWidget,
          );
          expect(find.textContaining('2 mana'), findsOneWidget);
          await tester.pumpWidget(board(cast, epoch: 1));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('cast-notice-chain')), findsNothing);
          expect(
            find.byKey(
              ValueKey('piece-effect-${cast.rules.pieceEffects.single.id}'),
            ),
            findsOneWidget,
            reason: 'reconnect clears playback, not public rules',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
