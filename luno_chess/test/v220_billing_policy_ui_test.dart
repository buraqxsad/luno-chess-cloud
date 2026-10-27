import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/services/legal_link_service.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_deck_account_test.dart' as deck_fixture;
import 'online_request_session_test.dart' show TestAuth;
import 'v220_billing_odds_fixture.dart';

Widget harness(String language, Widget child) => MaterialApp(
  locale: Locale(language),
  supportedLocales: LunoLocalizations.supportedLocales,
  localizationsDelegates: const [
    LunoLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: LunoTheme.dark,
  home: child,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.luno.chess/legal');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  Future<GameStore> storeFor() async {
    final store = GameStore.createForTesting();
    await store.bindAccount('first');
    addTearDown(store.dispose);
    return store;
  }

  LunoOnlineService serviceFor(
    GameStore store,
    Future<http.Response> Function(http.Request) respond,
  ) {
    final online = LunoOnlineService.forTesting(
      bootstrap: () async {},
      auth: TestAuth(),
      playerStore: store,
      appCheck: () async => 'test-only',
      client: MockClient(respond),
    );
    addTearDown(online.dispose);
    return online;
  }

  test(
    'static Play method has no caller URL and legal allowlist remains narrow',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      expect(await LegalLinkService.openPlaySubscriptions(), true);
      expect(calls.single.method, 'openPlaySubscriptions');
      expect(calls.single.arguments, isNull);
      expect(
        await LegalLinkService.instance.open(
          'https://play.google.com/store/account/subscriptions',
        ),
        false,
      );
      expect(calls.length, 1);
    },
  );
  test('missing or failed native subscription launcher fails safely', () async {
    expect(await LegalLinkService.openPlaySubscriptions(), false);
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'no-browser'),
    );
    expect(await LegalLinkService.openPlaySubscriptions(), false);
  });
  for (final language in ['tr', 'en']) {
    testWidgets('premium exposes management even without products: $language', (
      tester,
    ) async {
      var launches = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'openPlaySubscriptions');
        launches++;
        return true;
      });
      final store = await storeFor();
      final online = serviceFor(
        store,
        (_) async => http.Response(
          jsonEncode({'ok': true, 'state': v220ChestState('first')}),
          200,
        ),
      );
      await online.start();
      await tester.pumpWidget(
        harness(
          language,
          LunoPremiumScreen(online: online, playerStore: store),
        ),
      );
      await tester.pumpAndSettle();
      final manage = find.byKey(
        const ValueKey('membership-manage-subscription'),
      );
      await tester.scrollUntilVisible(
        manage,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(manage);
      await tester.pumpAndSettle();
      expect(launches, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
    testWidgets(
      'delete warning management never deletes or cancels: $language',
      (tester) async {
        var launches = 0, requests = 0;
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'openPlaySubscriptions');
          launches++;
          return true;
        });
        final store = await storeFor();
        final online = serviceFor(store, (_) async {
          requests++;
          return http.Response('{}', 200);
        });
        await online.start();
        final settings = LunoSettings(deviceLocale: Locale(language));
        addTearDown(settings.dispose);
        await tester.runAsync(settings.load);
        await tester.pumpWidget(
          harness(language, SettingsScreen(online: online, settings: settings)),
        );
        await tester.pumpAndSettle();
        final delete = find.text(
          language == 'en' ? 'Delete account' : 'Hesabımı sil',
        );
        await tester.ensureVisible(delete);
        await tester.pumpAndSettle();
        await tester.tap(delete);
        // The account screen stays busy while its confirmation is open.
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          find.textContaining(
            language == 'en'
                ? 'does not cancel your Google Play subscription'
                : 'Google Play aboneliğini iptal etmez',
          ),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('delete-account-manage-subscription')),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(launches, 1);
        expect(requests, 0);
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text(language == 'en' ? 'Cancel' : 'Vazgeç'));
        await tester.pumpAndSettle();
        expect(requests, 0);
        expect(online.user?.uid, 'first');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  for (final scenario in ['cancel', 'confirm', 'account-switch', 'malformed']) {
    testWidgets(
      'no chest debit until valid, account-current consent: $scenario',
      (tester) async {
        final store = await storeFor();
        var openings = 0;
        final online = serviceFor(store, (request) async {
          if (request.url.path.endsWith('/getBattleV1Deck')) {
            return http.Response(jsonEncode(deck_fixture.response()), 200);
          }
          if (request.url.path.endsWith('/getPlayerState')) {
            final state = v220ChestState('first');
            if (scenario == 'malformed')
              (state['shopChests'] as Map)['common']['price'] = 1;
            return http.Response(jsonEncode({'ok': true, 'state': state}), 200);
          }
          expect(request.url.path.endsWith('/openChest'), true);
          openings++;
          return http.Response(
            '{"ok":false,"error":"insufficient-balance"}',
            409,
          );
        });
        await online.start();
        await tester.pumpWidget(
          harness('en', ShopScreen(online: online, playerStore: store)),
        );
        await tester.pumpAndSettle();
        final buy = find.widgetWithText(FilledButton, '500');
        await tester.ensureVisible(buy);
        await tester.pumpAndSettle();
        final callback = tester.widget<FilledButton>(buy).onPressed!;
        callback();
        callback();
        await tester.pumpAndSettle();
        expect(openings, 0);
        final confirm = find.byKey(const ValueKey('chest-odds-confirm'));
        if (scenario == 'malformed') {
          expect(confirm, findsNothing);
          expect(find.textContaining('No purchase was sent'), findsOneWidget);
        } else if (scenario == 'account-switch') {
          final old = tester.widget<FilledButton>(confirm).onPressed!;
          store.accountUid = 'second';
          store.notifyListeners();
          await tester.pumpAndSettle();
          old();
          await tester.pumpAndSettle();
          expect(openings, 0);
          expect(find.byKey(const ValueKey('chest-odds-dialog')), findsNothing);
        } else {
          await tester.tap(
            find.byKey(
              ValueKey(
                scenario == 'confirm'
                    ? 'chest-odds-confirm'
                    : 'chest-odds-cancel',
              ),
            ),
          );
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pumpAndSettle();
          expect(openings, scenario == 'confirm' ? 1 : 0);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
