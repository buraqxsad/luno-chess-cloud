import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/private.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/battle_ui/sheets.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';

import 'battle_async_v213_test.dart' show mountBattle, cleanup;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'battle_ui/fixtures.dart';
import 'helpers/battle_v1_response.dart';

void main() {
  setupPracticeTestAssets();
  for (final kind in ['close', 'arsenal', 'action', 'private']) {
    testWidgets('$kind modal action cannot dismiss a covering route', (
      tester,
    ) async {
      final state =
          kind == 'private'
              ? DeckManager.apply(
                battleFixture(
                  hand: [CardId.prophecy, CardId.shelter, CardId.mine],
                ),
                const PlayCardAction(CardId.prophecy),
              )
              : battleFixture();
      final view = state.view(PieceColor.white);
      late BuildContext owner;
      await tester.pumpWidget(
        shell(
          Builder(
            builder: (context) {
              owner = context;
              return const Scaffold(body: Text('modal-owner'));
            },
          ),
        ),
      );
      final Widget sheet = switch (kind) {
        'close' => const BattleSheet(title: 'test', child: Text('sheet')),
        'arsenal' => OpponentArsenalSheet(
          rules: view.rules,
          opponent: view.viewer,
          eligible: {CardId.shelter},
        ),
        'action' => BattleActionChoices(
          title: 'test',
          actions: const [PassAction()],
          label: (_) => 'pass',
        ),
        _ => PrivateChoiceSheet(
          view: view,
          actions:
              BattleRulesCore.legalActions(
                view,
              ).whereType<ResolveAction>().toList(),
        ),
      };
      final result = showModalBottomSheet<Object>(
        context: owner,
        isScrollControlled: true,
        builder: (_) => sheet,
      );
      await tester.pumpAndSettle();
      late VoidCallback action;
      if (kind == 'close') {
        action =
            tester
                .widget<BattleIconControl>(find.byType(BattleIconControl).first)
                .onPressed!;
      } else if (kind == 'arsenal') {
        action =
            tester
                .widget<InkWell>(find.byKey(const ValueKey('arsenal-shelter')))
                .onTap!;
      } else {
        action =
            tester
                .widget<BattleCommand>(find.byType(BattleCommand).first)
                .onPressed!;
      }
      final navigator = Navigator.of(owner);
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('modal-cover')),
        ),
      );
      await tester.pumpAndSettle();
      action();
      await tester.pumpAndSettle();
      expect(find.text('modal-cover'), findsOneWidget);
      navigator.pop();
      await tester.pumpAndSettle();
      action();
      action();
      await tester.pumpAndSettle();
      final selected = await result;
      if (kind == 'arsenal') expect(selected, CardId.shelter);
      if (kind == 'action') expect(selected, isA<PassAction>());
      if (kind == 'private') expect(selected, isA<ResolveAction>());
      expect(find.text('modal-owner'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      action();
      expect(tester.takeException(), isNull);
    });
  }

  for (final key in ['open-menu', 'pass-card', 'hand', 'board']) {
    testWidgets('covered battle ignores $key callback and does not dispatch', (
      tester,
    ) async {
      var requests = 0;
      final controller = BattleV1Controller(
        uid: 'self',
        matchId: v1MatchId,
        initialResponse: v1Response(state: battleFixture()),
        persistPending: (_) async {},
        request: (_, _) async {
          requests++;
          return v1Response(state: battleFixture());
        },
      );
      addTearDown(controller.dispose);
      final navigator = await mountBattle(
        tester,
        BattleV1Screen(controllerOverride: controller),
      );
      final select =
          tester.widget<BattleHand>(find.byType(BattleHand)).onSelect;
      final tap = tester.widget<BattleBoard>(find.byType(BattleBoard)).onTap;
      final VoidCallback action = switch (key) {
        'open-menu' =>
          tester
              .widget<BattleIconControl>(find.byKey(ValueKey(key)))
              .onPressed!,
        'hand' => () => select(CardId.shelter),
        'board' => () => tap(12),
        _ => tester.widget<BattleCommand>(find.byKey(ValueKey(key))).onPressed!,
      };
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('battle-cover')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      action();
      await tester.pumpAndSettle();
      expect(find.text('battle-cover'), findsOneWidget);
      expect(find.byType(BattleSheet), findsNothing);
      expect(requests, 0);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(
        tester.widget<BattleHand>(find.byType(BattleHand)).selected,
        isNull,
      );
      expect(
        tester.widget<BattleBoard>(find.byType(BattleBoard)).selected,
        isNull,
      );
      await cleanup(tester);
      action();
      expect(tester.takeException(), isNull);
    });
  }
}
