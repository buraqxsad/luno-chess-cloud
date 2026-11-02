import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/arena_progression_benefits.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final entry
        in {
          'Nunito': 'assets/fonts/nunito/nunito-variable.ttf',
          'Cinzel': 'assets/fonts/cinzel-latin.ttf',
          'CinzelTurkish': 'assets/fonts/cinzel-turkish.ttf',
          'Spectral': 'assets/fonts/spectral/spectral-regular-latin.ttf',
        }.entries) {
      await (FontLoader(entry.key)
        ..addFont(rootBundle.load(entry.value))).load();
    }
  });
  for (final (label, scale, name) in [
    ('PAWN VALLEY', 1.0, 'english-control'),
    ('PİYON VADİSİ', 1.0, 'turkish'),
    ('ŞAH GÖLGESİ', 1.6, 'turkish-large'),
  ]) {
    testWidgets(
      'promotion glyph rendering matches explicit supported font $name',
      (tester) async {
        tester.view.physicalSize = const Size(640, 180);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final actual = GlobalKey(), supported = GlobalKey();
        Widget title(GlobalKey key, {required bool forceSupported}) => SizedBox(
          width: 320,
          height: 180,
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: Colors.black,
              child: DefaultTextStyle(
                style: LunoTheme.darkFor(
                  'Türkçe',
                ).textTheme.bodyMedium!.copyWith(
                  fontFamilyFallback:
                      forceSupported ? ['CinzelTurkish'] : ['Spectral'],
                ),
                child: ArenaPromotionHeading(label: label),
              ),
            ),
          ),
        );
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Row(
                children: [
                  title(actual, forceSupported: false),
                  title(supported, forceSupported: true),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        final images = <ui.Image>[];
        final pixels = <List<int>>[];
        await tester.runAsync(() async {
          for (final (key, suffix) in [
            (actual, 'actual'),
            (supported, 'supported'),
          ]) {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            images.add(image);
            final bytes =
                (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
            pixels.add(bytes.buffer.asUint8List());
            final output = Platform.environment['LUNO_ROUND4_FONT_QA'];
            if (output != null) {
              final png =
                  (await image.toByteData(format: ui.ImageByteFormat.png))!;
              final file = File('$output/$name-$suffix.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(png.buffer.asUint8List());
            }
          }
        });
        try {
          expect(tester.takeException(), isNull);
          expect(
            pixels[0].where((value) => value != 0 && value != 255).length,
            greaterThan(100),
            reason:
                'The real font raster must be present, not two blank surfaces.',
          );
          final differences =
              Iterable<int>.generate(
                pixels[0].length,
              ).where((i) => pixels[0][i] != pixels[1][i]).length;
          expect(
            differences,
            0,
            reason:
                'The title must render Turkish glyphs with the bundled display face, rather than missing-glyph boxes or an unrelated system fallback.',
          );
        } finally {
          for (final image in images) {
            image.dispose();
          }
        }
      },
    );
  }
}
