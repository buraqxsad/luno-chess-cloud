import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/app.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell, noOverflow, boundaryKey;
import 'rc_screen_capture_test.dart' show capture;
import 'online_request_session_test.dart' show TestAuth;

void main() {
  setupPracticeTestAssets();
  for (final language in ['tr', 'en']) {
    for (final page in ['username', 'settings']) {
      testWidgets(
        'restore confirmation clear and cancelable $language $page text200',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          tester.view
            ..physicalSize = const Size(320, 568)
            ..devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final store = GameStore.createForTesting();
          await store.load();
          var selections = 0;
          final online = LunoOnlineService.forTesting(
            auth: TestAuth(),
            bootstrap: () async {},
            googleCredential: () async {
              selections++;
              throw FirebaseAuthException(code: 'web-context-canceled');
            },
          );
          final settings = LunoSettings(deviceLocale: Locale(language));
          await settings.load();
          addTearDown(() {
            online.dispose();
            store.dispose();
          });
          await tester.pumpWidget(
            shell(
              page == 'username'
                  ? UsernameSetupScreen(store: store, online: online)
                  : SettingsScreen(online: online, settings: settings),
              language: language,
              scale: 2,
              reduced: true,
            ),
          );
          await tester.runAsync(() async {
            final context = tester.element(find.byKey(boundaryKey));
            for (final image
                in tester.widgetList<Image>(find.byType(Image)).toList()) {
              await precacheImage(image.image, context);
            }
          });
          await tester.pumpAndSettle();
          final button = find.byKey(const ValueKey('google-account-restore'));
          if (button.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              button,
              300,
              scrollable: find.byType(Scrollable).first,
            );
          }
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          await capture(
            tester,
            '$page-$language',
            repaintKey: boundaryKey,
            outputDirectory: 'qa/v236/account',
          );
          final action = tester.widget<TextButton>(button).onPressed!;
          action();
          action();
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(
            find.text(
              language == 'en' ? 'Stay on this account' : 'Bu hesapta kal',
            ),
            findsOneWidget,
          );
          final confirm = find.byKey(
            const ValueKey('google-account-restore-confirm'),
          );
          await tester.ensureVisible(confirm);
          await tester.pumpAndSettle();
          expect(confirm.hitTestable(), findsOneWidget);
          await capture(
            tester,
            '$page-confirm-$language',
            repaintKey: boundaryKey,
            outputDirectory: 'qa/v236/account',
          );
          noOverflow(tester);
          final cancel = find.text(
            language == 'en' ? 'Stay on this account' : 'Bu hesapta kal',
          );
          await tester.ensureVisible(cancel);
          await tester.pumpAndSettle();
          expect(cancel.hitTestable(), findsOneWidget);
          await tester.tap(cancel);
          await tester.pumpAndSettle();
          expect(selections, 0);
          expect(online.user!.uid, 'first');
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
