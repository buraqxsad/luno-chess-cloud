import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:luno_chess/theme/luno_visual_assets.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'rc_screen_capture_test.dart' show capture;

void main() {
  setupPracticeTestAssets();
  for (final language in ['tr', 'en']) {
    for (final kind in ['shop', 'chest']) {
      for (final size in [
        const Size(320, 568),
        const Size(390, 844),
        const Size(568, 320),
        const Size(768, 1024),
      ]) {
        for (final scale in [1.0, 1.5, 2.0]) {
          final name =
              '$kind-$language-${size.width.toInt()}x${size.height.toInt()}-$scale';
          testWidgets('reward frame $name', (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final en = language == 'en';
            final title =
                kind == 'shop'
                    ? (en ? 'DAILY REWARD' : 'GÜNLÜK ÖDÜL')
                    : (en ? 'CHEST OPENED' : 'SANDIK AÇILDI');
            final message = en ? 'Your reward is ready.' : 'Ödülün hazır.';
            await tester.pumpWidget(
              shell(
                Scaffold(
                  body:
                      kind == 'shop'
                          ? ShopRewardDialog(
                            title: title,
                            art: LunoAssets.shopDaily,
                            message: message,
                          )
                          : const ChestRevealDialog(
                            chestId: 'rare',
                            rewards: [
                              {'type': 'gold', 'amount': 1500},
                              {'type': 'gems', 'amount': 30},
                            ],
                          ),
                ),
                language: language,
                scale: scale,
                reduced: true,
              ),
            );
            await tester.pump();
            final frame = find.byWidgetPredicate((widget) {
              if (widget is! Container || widget.decoration is! BoxDecoration) {
                return false;
              }
              final image = (widget.decoration! as BoxDecoration).image?.image;
              return image is AssetImage &&
                  image.assetName == LunoVisualAssets.premium;
            });
            expect(frame, findsOneWidget);
            final decoration =
                tester.widget<Container>(frame).decoration! as BoxDecoration;
            expect(
              decoration.image!.centerSlice!.top,
              greaterThanOrEqualTo(40),
            );
            expect(
              tester.getRect(find.text(title)).top - tester.getRect(frame).top,
              greaterThanOrEqualTo(44),
              reason: 'The painted crown must not overlap the reward title.',
            );
            final action = find.byKey(
              ValueKey(
                kind == 'shop' ? 'shop-reward-action' : 'chest-reveal-continue',
              ),
            );
            expect(action.hitTestable(), findsOneWidget);
            expect(tester.getRect(action).top, greaterThanOrEqualTo(0));
            expect(
              tester.getRect(action).bottom,
              lessThanOrEqualTo(size.height),
            );
            await capture(
              tester,
              name,
              outputDirectory: 'qa/v216/after/reward-frame',
            );
            final detail =
                kind == 'shop'
                    ? find.text(message)
                    : find.textContaining(en ? 'Gems' : 'Elmas');
            await tester.ensureVisible(detail);
            await tester.pump();
            expect(detail.hitTestable(), findsOneWidget);
            expect(
              tester.getRect(detail).bottom,
              lessThanOrEqualTo(tester.getRect(action).top),
            );
            if (scale == 2 && size.width <= 568) {
              await capture(
                tester,
                '$name-tail',
                outputDirectory: 'qa/v216/after/reward-frame',
              );
            }
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          });
        }
      }
    }
  }
}
