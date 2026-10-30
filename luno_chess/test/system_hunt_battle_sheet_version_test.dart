import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/sheets.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_ui/fixtures.dart' show battleFixture;
import 'battle_ui/visual_test.dart' show renderBattle;
import 'helpers/battle_v1_response.dart' show v1Response;

void main() {
  setupPracticeTestAssets();
  setUp(() {
    GameStore.instance
      ..loaded = true
      ..data = PlayerData.initial()
      ..hasCompletedTutorial = true
      ..hasChosenUsername = true
      ..firstSessionMatchesStarted = 2;
  });

  for (final timing in ['before first builder', 'already visible']) {
    for (final event in ['new version', 'terminal']) {
      testWidgets('old battle sheet disappears on $event $timing', (
        tester,
      ) async {
        var current = battleFixture();
        var version = 0;
        Map<String, dynamic> response() {
          final value = v1Response(state: current, version: version);
          if (current.rules.terminal case final terminal?) {
            value['status'] = 'finished';
            final public = (value['view'] as Map)['public'] as Map;
            public['result'] = {
              'reason': terminal.reason,
              'winner': sideWire(terminal.winner!),
            };
            public['settlementStatus'] = 'pending';
          }
          return value;
        }

        final controller = await renderBattle(
          tester,
          state: current,
          requestOverride: (_, _) async => response(),
        );
        final open =
            tester
                .widget<IconButton>(find.byKey(const ValueKey('open-own-deck')))
                .onPressed!;
        open();
        final dynamic screen = tester.state(find.byType(BattleV1Screen));
        expect(screen.sheetOpen, isTrue);
        if (timing == 'already visible') {
          await tester.pumpAndSettle();
          expect(find.byType(OpponentArsenalSheet), findsOneWidget);
        } else {
          expect(screen.sheetRoute, isNull);
        }

        bool? staleAtFirstPaint;
        tester.binding.addPostFrameCallback((_) {
          staleAtFirstPaint =
              find
                  .byType(OpponentArsenalSheet, skipOffstage: false)
                  .evaluate()
                  .isNotEmpty;
        });
        if (event == 'new version') {
          current = DeckManager.apply(current, const PassAction());
        } else {
          final draft =
              RuleDraft(current.rules)
                ..phase = BattlePhase.terminal
                ..terminal = const TerminalState(
                  'resign',
                  winner: PieceColor.black,
                );
          current = AuthoritativeBattleState(draft.freeze(), current.hidden);
        }
        version++;
        await controller.reconnect(synchronization: false);
        expect(controller.error, isNull);
        expect(controller.snapshot!.stateVersion, version);
        await tester.pump();
        expect(staleAtFirstPaint, isFalse);
        expect(
          find.byType(OpponentArsenalSheet, skipOffstage: false),
          findsNothing,
        );
        await tester.pumpAndSettle();
        expect(screen.sheetOpen, isFalse);
        expect(
          Navigator.of(tester.element(find.byType(BattleV1Screen))).canPop(),
          isFalse,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('current battle sheet remains usable without a state change', (
    tester,
  ) async {
    await renderBattle(tester);
    tester
        .widget<IconButton>(find.byKey(const ValueKey('open-own-deck')))
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.byType(OpponentArsenalSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
