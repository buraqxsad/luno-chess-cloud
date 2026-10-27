import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/pass_screen.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/services/cosmetic_catalog.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'rc_screen_capture_test.dart' show visualOnline, capture;

void main() {
  setupPracticeTestAssets();
  final phase = Platform.environment['LUNO_V216_1_PHASE'] ?? 'after';
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LunoSettings.instance.load();
    await GameStore.instance.bindAccount('first');
  });
  for (final language in ['tr', 'en']) {
    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(768, 1024),
    ]) {
      for (final scale in [1.0, 2.0]) {
        for (final screen in ['shop', 'chests', 'cosmetics', 'pass']) {
          testWidgets(
            'V216.1 $screen $language ${size.width.toInt()} scale$scale',
            (tester) async {
              final store = GameStore.instance;
              store
                ..data =
                    (PlayerData.initial()
                      ..username = 'luno_player'
                      ..gold = 16000
                      ..gems = 1500
                      ..passXp = 250
                      ..ownedEmojis = {'smile', 'heart'})
                ..loaded = true;
              final online = await visualOnline();
              addTearDown(online.dispose);
              tester.view.physicalSize = size;
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              LunoSettings.instance.language = language;
              await tester.pumpWidget(
                shell(
                  screen == 'pass'
                      ? PassScreen(online: online)
                      : ShopScreen(online: online),
                  language: language,
                  scale: scale,
                  reduced: true,
                ),
              );
              await tester.pump(const Duration(milliseconds: 600));
              if (screen == 'chests' || screen == 'cosmetics') {
                final label =
                    screen == 'chests'
                        ? (language == 'en' ? 'Chests' : 'Sandıklar')
                        : (language == 'en' ? 'Cosmetics' : 'Kozmetik');
                await tester.ensureVisible(find.text(label));
                await tester.tap(find.text(label));
                await tester.pump(const Duration(milliseconds: 300));
              }
              final name =
                  '$screen-$language-${size.width.toInt()}x${size.height.toInt()}-$scale';
              await capture(
                tester,
                name,
                outputDirectory: 'qa/v216_1/$phase/shop-pass',
              );
              if (screen == 'pass' || screen == 'cosmetics') {
                final scroll = find.byType(Scrollable).first;
                await tester.drag(scroll, const Offset(0, -650));
                await tester.pump(const Duration(milliseconds: 300));
                await capture(
                  tester,
                  '$name-tail',
                  outputDirectory: 'qa/v216_1/$phase/shop-pass',
                );
              }
              if (screen == 'pass' && phase == 'after') {
                tester
                    .state<ScrollableState>(find.byType(Scrollable).first)
                    .position
                    .jumpTo(0);
                await tester.pump();
                final premiumState = find.byKey(
                  const ValueKey('pass-state-premium-1'),
                );
                await tester.scrollUntilVisible(
                  premiumState,
                  160,
                  scrollable: find.byType(Scrollable).first,
                );
                await tester.ensureVisible(premiumState);
                await tester.pump();
                _expectWholeWords(tester, premiumState, singleLine: true);
                final firstTier = find.byKey(const ValueKey('pass-tier-1'));
                final labels = find.descendant(
                  of: firstTier,
                  matching: find.byType(Text),
                );
                for (final text in labels.evaluate()) {
                  _expectWholeWords(tester, find.byWidget(text.widget));
                }
                expect(premiumState.hitTestable(), findsOneWidget);
              await Scrollable.ensureVisible(tester.element(firstTier));
                await tester.pump();
                await capture(
                  tester,
                  '$name-reward-fit',
                  outputDirectory: 'qa/v216_1/$phase/shop-pass',
                );
              }
              if (screen == 'cosmetics') {
                for (final emote in cosmeticEmotes) {
                  final button = find.byKey(ValueKey('shop-emote-${emote.id}'));
                  await tester.scrollUntilVisible(
                    button,
                    200,
                    scrollable: find.byType(Scrollable).first,
                  );
                  await tester.ensureVisible(button);
                  await tester.pump();
                  final title = find.byKey(
                    ValueKey('shop-emote-title-${emote.id}'),
                  );
                  _expectWholeWords(tester, title);
                  final label = find.descendant(
                    of: button,
                    matching: find.byType(Text),
                  );
                  expect(label, findsOneWidget);
                  _expectWholeWords(tester, label, singleLine: true);
                  expect(
                    tester.getSize(button).height,
                    greaterThanOrEqualTo(48),
                  );
                  expect(tester.widget<LunoButton>(button).label, isNotEmpty);
                  expect(tester.takeException(), isNull);
                }
                await capture(
                  tester,
                  '$name-last-emote',
                  outputDirectory: 'qa/v216_1/$phase/shop-pass',
                );
                final positions = {
                  for (final emote in cosmeticEmotes)
                    emote.id: tester.getTopLeft(
                      find.byKey(ValueKey('shop-emote-title-${emote.id}')),
                    ),
                };
                store.applyServerState({
                  'inventory': {
                    'ownedEmojis':
                        cosmeticEmotes.map((emote) => emote.id).toList(),
                  },
                });
                await tester.pump();
                for (final emote in cosmeticEmotes) {
                  final title = find.byKey(
                    ValueKey('shop-emote-title-${emote.id}'),
                  );
                  expect(
                    tester.getTopLeft(title),
                    positions[emote.id],
                    reason: 'Ownership must not rearrange the emote grid',
                  );
                }
              }
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox());
            },
          );
        }
      }
    }
  }
}

void _expectWholeWords(
  WidgetTester tester,
  Finder text, {
  bool singleLine = false,
}) {
  final rich = find.descendant(of: text, matching: find.byType(RichText));
  expect(rich, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(rich);
  final value = paragraph.text.toPlainText();
  final tops = <double>{};
  for (final word in RegExp(r'\S+').allMatches(value)) {
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: word.start, extentOffset: word.end),
    );
    expect(boxes, isNotEmpty, reason: 'Invisible word: ${word.group(0)}');
    expect(
      boxes.map((box) => box.top).toSet().length,
      1,
      reason: 'Split word: ${word.group(0)}',
    );
    for (final box in boxes) {
      tops.add(box.top);
      expect(box.left, greaterThanOrEqualTo(-0.5));
      expect(box.right, lessThanOrEqualTo(paragraph.size.width + 0.5));
    }
  }
  expect(paragraph.didExceedMaxLines, isFalse);
  if (singleLine) expect(tops.length, 1, reason: 'CTA wrapped: $value');
}
