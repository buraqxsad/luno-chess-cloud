import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/layout.dart';
import 'package:luno_chess/battle_v1/model.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'battle_ui/visual_test.dart' show renderBattle;

Rect paintedBounds(RenderBox box) =>
    MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);

void main() {
  setupPracticeTestAssets();
  final metrics = <Map<String, Object>>[];
  tearDownAll(() {
    final phase = Platform.environment['V219_RENDER_PHASE'] ?? 'after';
    final directory = Directory('qa/v219/$phase')..createSync(recursive: true);
    File(
      '${directory.path}/card-decode-metrics.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(metrics));
  });

  for (final sample in [
    (size: 24.0, dpr: 1.0, pixels: 64),
    (size: 34.0, dpr: 2.0, pixels: 128),
    (size: 48.0, dpr: 3.0, pixels: 192),
    (size: 96.0, dpr: 2.0, pixels: 192),
    (size: 144.0, dpr: 3.0, pixels: 448),
    (size: 220.0, dpr: 3.0, pixels: 640),
    (size: 320.0, dpr: 4.0, pixels: 640),
  ]) {
    testWidgets('V219 card decode ${sample.size} at ${sample.dpr} DPR', (
      tester,
    ) async {
      tester.view.devicePixelRatio = sample.dpr;
      tester.view.physicalSize = Size(800 * sample.dpr, 900 * sample.dpr);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: Center(
              child: SizedBox.square(
                dimension: sample.size,
                child: const BattleCardArt(card: CardId.radar),
              ),
            ),
          ),
        ),
      );
      final image = tester.widget<Image>(
        find.descendant(
          of: find.byType(BattleCardArt),
          matching: find.byType(Image),
        ),
      );
      final provider = image.image as ResizeImage;
      metrics.add({
        'logicalSize': sample.size,
        'devicePixelRatio': sample.dpr,
        'decodeWidth': provider.width!,
        'rgbaBytesAtSquareDecode': provider.width! * provider.width! * 4,
      });
      expect(provider.width, sample.pixels);
      expect(image.fit, BoxFit.contain);
      expect(image.filterQuality, FilterQuality.medium);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('V219 unbounded card art keeps a bounded safe decode', (
    tester,
  ) async {
    await tester.pumpWidget(
      shell(
        const Scaffold(
          body: UnconstrainedBox(child: BattleCardArt(card: CardId.mine)),
        ),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as ResizeImage).width, 384);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('V219 decode policy preserves all 24 original illustrations', () {
    final paths = CardId.values.map(battleCardArtAsset).toSet();
    expect(paths, hasLength(24));
    for (final path in paths) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });

  for (final language in ['tr', 'en']) {
    for (final scale in [1.0, 1.8]) {
      testWidgets('V219 compact deck label stays inside its touch target '
          '$language scale$scale', (tester) async {
        var taps = 0;
        await tester.pumpWidget(
          shell(
            Scaffold(
              body: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BattleDeckAccess(
                      key: const ValueKey('deck-access'),
                      compact: true,
                      cardCount: 10,
                      onPressed: () => taps++,
                    ),
                    BattleClock(
                      label: 'clock',
                      active: false,
                      remaining: () => 300000,
                    ),
                  ],
                ),
              ),
            ),
            language: language,
            scale: scale,
          ),
        );
        final access = find.byKey(const ValueKey('deck-access'));
        final label = find.descendant(of: access, matching: find.byType(Text));
        expect(label, findsOneWidget);
        final target = paintedBounds(tester.renderObject<RenderBox>(access));
        final painted = paintedBounds(tester.renderObject<RenderBox>(label));
        expect(painted.left, greaterThanOrEqualTo(target.left - .1));
        expect(painted.right, lessThanOrEqualTo(target.right + .1));
        expect(painted.top, greaterThanOrEqualTo(target.top - .1));
        expect(painted.bottom, lessThanOrEqualTo(target.bottom + .1));
        expect(target.width, greaterThanOrEqualTo(48));
        expect(target.height, greaterThanOrEqualTo(48));
        await tester.tap(access);
        expect(taps, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
    for (final size in [const Size(320, 640), const Size(390, 844)]) {
      testWidgets('V219 real opponent label does not paint into clock '
          '$language $size', (tester) async {
        await renderBattle(tester, size: size, language: language);
        final access = find.byKey(const ValueKey('open-arsenal'));
        final label = find.descendant(of: access, matching: find.byType(Text));
        final target = paintedBounds(tester.renderObject<RenderBox>(access));
        final painted = paintedBounds(tester.renderObject<RenderBox>(label));
        expect(painted.left, greaterThanOrEqualTo(target.left - .1));
        expect(painted.right, lessThanOrEqualTo(target.right + .1));
        final clock = paintedBounds(
          tester.renderObject<RenderBox>(find.byType(BattleClock).first),
        );
        expect(painted.overlaps(clock), isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
