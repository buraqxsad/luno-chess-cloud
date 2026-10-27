import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/layout.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/battle_v1_copy.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';

void main() {
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.3, 1.5]) {
      for (final lang in ['tr', 'en']) {
        testWidgets('shell $width / $scale / $lang', (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final view = DeckManager.newBattle(
            white: starterDeck,
            black: starterDeck,
          ).view(PieceColor.white);
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(lang),
              supportedLocales: LunoLocalizations.supportedLocales,
              localizationsDelegates: const [
                LunoLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: Builder(
                builder: (context) {
                  final l = LunoLocalizations.of(context);
                  return MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: BattleV1Scaffold(
                      opponent: BattlePlayerHeader(
                        name: 'Ayışığı Uzun Oyuncu Adı',
                        side: PieceColor.black,
                        view: view,
                        clock: BattleClock(
                          remaining: () => 258000,
                          label: 'Clock',
                          active: false,
                          terminal: true,
                        ),
                      ),
                      arsenal: SizedBox(
                        width: double.infinity,
                        child: BattleCommand(
                          label: '${l.battle(BattleCopy.arsenal)} 10',
                          art: 'arsenal',
                          icon: Icons.style,
                          onPressed: () {},
                        ),
                      ),
                      board: BattleBoard(view: view, onTap: (_) {}),
                      status: BattlePhaseIndicator(phase: view.rules.phase),
                      own: BattlePlayerHeader(
                        name: 'LunoPlayer',
                        side: PieceColor.white,
                        view: view,
                        own: true,
                        clock: BattleClock(
                          remaining: () => 272000,
                          label: 'Clock',
                          active: true,
                          terminal: true,
                        ),
                      ),
                      hand: BattleHand(
                        view: view,
                        enabled: false,
                        cost: (c) => cardDefinitions[c]!.cost,
                        selectable: (_) => true,
                        onSelect: (_) {},
                        onDetail: (_) {},
                      ),
                      controls: const SizedBox(),
                    ),
                  );
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final board = tester.getSize(find.byType(BattleBoard));
          expect(board.width, board.height);
          // Normal-size copy reserves room for the taller battle hand.
          final expectedWidth =
              scale * 14 <= 17
                  ? (844.0 - 478).clamp(152.0, width - 16)
                  : width - 16;
          expect(board.width, expectedWidth);
          expect(
            tester.getTopLeft(find.byType(BattleCommand)).dy,
            greaterThan(tester.getBottomRight(find.byType(BattleBoard)).dy),
          );
          expect(
            tester.getBottomRight(find.byType(BattleCommand)).dy,
            lessThanOrEqualTo(tester.getTopLeft(find.byType(BattleHand)).dy),
          );
          expect(find.byType(BattleCardTile), findsNWidgets(3));
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
