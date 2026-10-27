import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/screens/pass_screen.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'online_request_session_test.dart' show TestAuth;

void main() {
  setupPracticeTestAssets();
  for (final kind in ['pass', 'premium', 'shop', 'profile']) {
    for (final disposed in [false, true]) {
      testWidgets('$kind bootstrap releases UI, disposed=$disposed', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        final store =
            GameStore.createForTesting()
              ..loaded = true
              ..accountUid = 'first';
        store.data.gems = 9999;
        final pending = Completer<void>();
        final online = LunoOnlineService.forTesting(
          bootstrap: () => pending.future,
          auth: TestAuth(),
        );
        addTearDown(() {
          online.dispose();
          store.dispose();
        });
        final Widget page = switch (kind) {
          'pass' => PassScreen(online: online, playerStore: store),
          'premium' => LunoPremiumScreen(online: online, playerStore: store),
          'shop' => ShopScreen(online: online, playerStore: store),
          _ => EditProfileScreen(online: online, playerStore: store),
        };
        await tester.pumpWidget(shell(page, reduced: true));
        await tester.pump();
        final shopButton = find.widgetWithText(FilledButton, 'AL');
        final shopElement =
            kind == 'shop' ? shopButton.evaluate().single : null;
        if (kind == 'premium') {
          await tester.scrollUntilVisible(
            find.widgetWithText(TextButton, 'DURUMU YENİLE'),
            200,
            scrollable: find.byType(Scrollable).first,
          );
        }
        VoidCallback? action() => switch (kind) {
          'pass' =>
            tester
                .widget<LunoButton>(
                  find
                      .byWidgetPredicate(
                        (w) =>
                            w is LunoButton && w.label.contains('PREMIUM AL'),
                      )
                      .first,
                )
                .onPressed,
          'premium' =>
            tester
                .widget<TextButton>(
                  find.widgetWithText(TextButton, 'DURUMU YENİLE'),
                )
                .onPressed,
          'shop' => (shopElement!.widget as FilledButton).onPressed,
          _ =>
            tester
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (w) => w is IconButton && w.tooltip == 'Kaydet',
                  ),
                )
                .onPressed,
        };
        final callback = action();
        if (kind == 'premium') {
          expect(
            callback,
            isNull,
            reason: 'The automatic status bootstrap owns the busy gate.',
          );
        } else {
          callback!();
          callback();
        }
        await tester.pump();
        if (disposed) {
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        } else {
          await tester.pump(const Duration(seconds: 13));
          if (kind == 'shop') await tester.pump(const Duration(seconds: 13));
          expect(
            action(),
            isNotNull,
            reason: 'A stalled bootstrap must release the busy action',
          );
          expect(store.data.premium, false);
          if (kind == 'premium') {
            expect(
              find.byKey(const ValueKey('membership-status')),
              findsOneWidget,
            );
            expect(find.byType(SnackBar), findsNothing);
          } else {
            expect(find.byType(SnackBar), findsOneWidget);
          }
          await tester.pumpWidget(const SizedBox());
        }
        pending.complete();
        await tester.pump(const Duration(milliseconds: 10));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
