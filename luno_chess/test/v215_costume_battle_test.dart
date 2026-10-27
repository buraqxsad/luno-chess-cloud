import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/art.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/sheets.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell, warm, noOverflow;
import 'battle_ui/interaction_test.dart' show Harness;

Set<String> providers(WidgetTester tester) =>
    tester.widgetList<Image>(find.byType(Image)).map((image) {
      final provider =
          image.image is ResizeImage
              ? (image.image as ResizeImage).imageProvider
              : image.image;
      return provider is AssetImage ? provider.assetName : '';
    }).toSet();

void main() {
  setupPracticeTestAssets();
  test('unsupported/base set preserves current battle assets', () {
    expect(
      BattleArt.piecePath(PieceColor.white, PieceType.king),
      'assets/native_art/battle-v202b-piece-w-king.webp',
    );
    expect(
      BattleArt.piecePath(PieceColor.black, PieceType.queen, set: 'forged'),
      'assets/native_art/battle-v202b-piece-b-queen.webp',
    );
  });
  for (final set in [
    'ottoman',
    'roma',
    'brit',
    'viking',
    'tasdevri',
    'samuray',
    'ice',
    'dragon',
    'neon',
  ]) {
    testWidgets(
      'owned $set draws static, moving and promotion pieces consistently',
      (tester) async {
        final h = Harness();
        GameStore.instance.data =
            PlayerData.initial()
              ..pieceSet = set
              ..ownedPieceSets.add(set);
        await tester.pumpWidget(
          shell(
            BattleV1Screen(
              controllerOverride: h.controller,
              clockOverride: (_) => 300000,
            ),
          ),
        );
        await warm(tester);
        expect(
          tester.widget<BattleBoard>(find.byType(BattleBoard)).pieceSet,
          set,
        );
        expect(
          providers(tester),
          contains(
            BattleArt.piecePath(PieceColor.white, PieceType.king, set: set),
          ),
        );
        final movingId = h.state.rules.pieceIds[12];
        await h.controller.submit(const PassAction());
        await tester.pump();
        await h.controller.submit(const ChessMoveAction('e2e4'));
        await tester.pump();
        expect(h.sent.map((action) => action.key), ['pass', 'move:e2e4']);
        expect(h.state.rules.pieceIds[28], movingId);
        expect(find.byKey(ValueKey('moving-piece-$movingId')), findsOneWidget);
        expect(
          providers(tester),
          contains(
            BattleArt.piecePath(PieceColor.white, PieceType.pawn, set: set),
          ),
        );
        noOverflow(tester);
        await tester.pumpWidget(
          shell(
            Scaffold(
              body: BattleActionChoices(
                title: 'Promotion',
                pieceSet: set,
                pieceSide: PieceColor.black,
                actions: const [
                  ChessMoveAction('e2e1q'),
                  ChessMoveAction('e2e1r'),
                  ChessMoveAction('e2e1b'),
                  ChessMoveAction('e2e1n'),
                ],
                label: (a) => a.key,
              ),
            ),
          ),
        );
        await warm(tester);
        for (final type in [
          PieceType.queen,
          PieceType.rook,
          PieceType.bishop,
          PieceType.knight,
        ]) {
          expect(
            providers(tester),
            contains(BattleArt.piecePath(PieceColor.black, type, set: set)),
          );
        }
        noOverflow(tester);
        await tester.pumpWidget(const SizedBox());
        h.controller.dispose();
      },
    );
  }
  testWidgets('unowned selection cannot choose a costume in battle', (
    tester,
  ) async {
    GameStore.instance.data = PlayerData.initial()..pieceSet = 'neon';
    final h = Harness();
    await tester.pumpWidget(
      shell(
        BattleV1Screen(
          controllerOverride: h.controller,
          clockOverride: (_) => 300000,
        ),
      ),
    );
    await warm(tester);
    expect(
      tester.widget<BattleBoard>(find.byType(BattleBoard)).pieceSet,
      'luno',
    );
    await tester.pumpWidget(const SizedBox());
    h.controller.dispose();
  });
}
