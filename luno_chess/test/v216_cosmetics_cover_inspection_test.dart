import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/data/card_pool.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:luno_chess/theme/luno_theme.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'v216_cosmetics_visual_test.dart' show captureCosmetic;

void main() {
  setupPracticeTestAssets();
  for (final set in kPieceSetIds) {
    testWidgets('production atlas $set decodes and renders without fallback', (tester) async {
      tester.view.physicalSize = const Size(430, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final path = LunoAssets.setPreview(set);
      expect(path, 'assets/native_art/piece-set-$set-v216.webp');
      await tester.runAsync(() async {
        final bytes = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
        final image = (await codec.getNextFrame()).image;
        expect(image.width, 960);
        expect(image.height, 400);
        image.dispose();
        codec.dispose();
      });
      await tester.pumpWidget(shell(Scaffold(body: Center(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(set, style: LunoType.screenTitle),
          const SizedBox(height: 12),
          AspectRatio(aspectRatio: 2.4, child: LunoArt(path)),
        ]),
      ))), language: 'en', scale: 1.5, reduced: true));
      await captureCosmetic(tester, 'catalog-$set-v216');
      final decoded = tester.widgetList<RawImage>(find.byType(RawImage))
          .map((widget) => widget.image).whereType<ui.Image>().toList();
      expect(decoded, hasLength(1));
      expect(decoded.single.width, 398);
      expect(decoded.single.height, (398 / 2.4).floor());
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
