import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/collection_screens.dart';
import 'package:luno_chess/screens/shop_screen.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell, boundaryKey, warm;

Future<void> captureCosmetic(WidgetTester tester, String name) async {
  await warm(tester);
  final context = tester.element(find.byType(Scaffold).first);
  await tester.runAsync(() async {
    for (final box in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))) {
      if (box.decoration case final BoxDecoration decoration) {
        if (decoration.image != null) {
          await precacheImage(decoration.image!.image, context);
        }
      }
    }
  });
  for (final render in tester.allRenderObjects) {
    render.markNeedsPaint();
  }
  await tester.pump();
  expect(tester.takeException(), isNull, reason: name);
  await tester.runAsync(() async {
    final stage = Platform.environment['V216_STAGE'] ?? 'after';
    final directory = Directory('qa/v216/$stage/cosmetics-emotes')
      ..createSync(recursive: true);
    final boundary = tester.element(find.byKey(boundaryKey)).renderObject!
        as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('${directory.path}/$name.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setupPracticeTestAssets();
  for (final language in ['tr', 'en']) {
    for (final width in [320.0, 390.0, 430.0, 768.0]) {
      for (final page in ['costumes', 'emotes', 'chest']) {
        testWidgets('cosmetic render $page $language $width large text',
            (tester) async {
          tester.view.physicalSize = Size(width, width == 320 ? 568 : 1024);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final store = GameStore.instance;
          final original = store.data;
          addTearDown(() => store.data = original);
          store.data = PlayerData.initial()
            ..ownedPieceSets.add('ottoman')
            ..ownedEmojis.addAll(['smile', 'heart'])
            ..emojiLoadout = ['smile'];
          await tester.pumpWidget(shell(
            switch (page) {
              'costumes' => const PieceCostumeScreen(),
              'emotes' => const EmojiCollectionScreen(),
              _ => const Scaffold(body: ChestRevealDialog(
                chestId: 'rare',
                rewards: [
                  {'type': 'gold', 'amount': 120},
                  {'type': 'emoji', 'id': 'heart', 'amount': 2, 'unlocked': true},
                  {'type': 'skin', 'id': 'obsidian', 'amount': 1},
                ],
              )),
            },
            language: language, scale: 1.5, reduced: true,
          ));
          await captureCosmetic(tester, '$page-$language-${width.toInt()}-150');
          if (page == 'chest') {
            final detail = find.textContaining(language == 'en'
                ? 'Ready in your emote collection' : 'İfade koleksiyonunda hazır');
            await tester.ensureVisible(detail);
            await captureCosmetic(tester, 'chest-detail-$language-${width.toInt()}-150');
            expect(find.byKey(const ValueKey('chest-reveal-continue')).hitTestable(), findsOneWidget);
          }
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
