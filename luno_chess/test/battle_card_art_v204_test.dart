import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_v1/model.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('Nunito')
          ..addFont(rootBundle.load('assets/fonts/nunito/nunito-variable.ttf')))
        .load();
  });

  testWidgets('every V1 card has its own bundled artwork', (tester) async {
    final paths = CardId.values.map(battleCardArtAsset).toList();
    expect(paths.toSet(), hasLength(CardId.values.length));
    for (final path in paths) {
      final data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(0), reason: path);
    }

    tester.view.physicalSize = const Size(480, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF211A2B),
          body: Center(
            child: Wrap(
              children: [
                for (final card in CardId.values)
                  SizedBox(
                    width: 112,
                    height: 128,
                    child: Column(
                      children: [
                        SizedBox(
                          width: 104,
                          height: 104,
                          child: BattleCardArt(card: card),
                        ),
                        Text(
                          card.wire,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontFamily: 'Nunito',
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      final context = tester.element(find.byType(Scaffold));
      for (final image in tester.widgetList<Image>(find.byType(Image))) {
        await precacheImage(image.image, context);
      }
    });
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/battle-card-art-v204.png'),
    );
  });
}
