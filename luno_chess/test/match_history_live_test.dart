import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/navigation/luno_account_scope.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/screens/profile_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_request_session_test.dart' show TestAuth;

void main() {
  test('profile and history opt into account-scoped navigation', () {
    expect(const ProfileScreen(), isA<LunoAccountScopedPage>());
    expect(const MatchHistoryScreen(), isA<LunoAccountScopedPage>());
  });
  for (final english in [false, true]) {
    for (final size in [
      const Size(320, 568),
      const Size(568, 320),
      const Size(800, 1280),
    ]) {
      testWidgets('history stays live and consistent: en=$english at $size', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        final store = GameStore.createForTesting()..loaded = true;
        addTearDown(store.dispose);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(english ? 'en' : 'tr'),
            supportedLocales: LunoLocalizations.supportedLocales,
            localizationsDelegates: const [
              LunoLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: LunoTheme.dark,
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.8)),
                  child: child!,
                ),
            home: MatchHistoryScreen(playerStore: store),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            english ? 'No completed matches yet' : 'Henüz tamamlanmış maç yok',
          ),
          findsOneWidget,
        );
        store.data.wins = 4;
        store.data.draws = 2;
        store.data.losses = -3;
        store.data.gamesPlayed = 1;
        store.data.bestStreak = -2;
        store.notifyListeners();
        await tester.pumpAndSettle();
        expect(
          find.text(
            english ? '6 matches in your career' : '6 maçlık kariyer özeti',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            english
                ? '4 wins · 2 draws · 0 losses · best streak 0'
                : '4 galibiyet · 2 beraberlik · 0 mağlubiyet · en iyi seri 0',
          ),
          findsOneWidget,
        );
        store.data.gamesPlayed = 9;
        store.notifyListeners();
        await tester.pumpAndSettle();
        expect(
          find.text(
            english
                ? '3 matches have no recorded result.'
                : '3 maçın kayıtlı sonucu yok.',
          ),
          findsOneWidget,
        );
        store.data = PlayerData.initial();
        store.notifyListeners();
        await tester.pumpAndSettle();
        expect(
          find.text(
            english ? 'No completed matches yet' : 'Henüz tamamlanmış maç yok',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('best streak 0'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final covered in [false, true]) {
    testWidgets(
      'history hides previous session after signout, covered=$covered',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final store = GameStore.createForTesting()..loaded = true;
        store.data.gamesPlayed = 7;
        final auth = TestAuth();
        final events = StreamController<User?>.broadcast(sync: true);
        final online = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: auth,
          authChanges: events.stream,
        );
        addTearDown(() async {
          online.dispose();
          store.dispose();
          await events.close();
        });
        await online.start();
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            theme: LunoTheme.dark,
            home: LunoAccountScope(
              service: online,
              page: MatchHistoryScreen(playerStore: store),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('7 maçlık kariyer özeti'), findsOneWidget);
        if (covered) {
          unawaited(
            navigator.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Other page')),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }
        auth.currentUser = null;
        events.add(null);
        await tester.pumpAndSettle();
        expect(
          find.text('7 maçlık kariyer özeti', skipOffstage: false),
          findsNothing,
        );
        if (covered) {
          expect(find.text('Other page'), findsOneWidget);
          navigator.currentState!.pop();
          await tester.pumpAndSettle();
        }
        expect(
          find.text(
            'Oturumun kapandı. Giriş yaptıktan sonra bu ekranı yeniden aç.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
