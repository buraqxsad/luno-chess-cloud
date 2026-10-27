import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/navigation/luno_account_scope.dart';
import 'package:luno_chess/screens/public_player_profile_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'online_request_session_test.dart' show TestAuth;

void main() {
  for (final lateError in [false, true]) {
    testWidgets('timeout permits retry and ignores late error=$lateError', (
      tester,
    ) async {
      final responses = <Completer<Object?>>[];
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth(),
        databaseRead: (_) {
          final response = Completer<Object?>();
          responses.add(response);
          return response.future;
        },
      );
      addTearDown(online.dispose);
      await online.start();
      await tester.pumpWidget(
        MaterialApp(
          theme: LunoTheme.dark,
          home: PublicPlayerProfileScreen(targetUid: 'target', online: online),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(
        LunoOnlineService.publicProfileReadTimeout +
            const Duration(milliseconds: 50),
      );
      expect(find.text('Oyuncu profili yüklenemedi.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.text('TEKRAR DENE'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(responses, hasLength(2));
      responses[1].complete({'username': 'new_player', 'bio': 'New biography'});
      await tester.pumpAndSettle();
      if (lateError) {
        responses.first.completeError(StateError('late failure'));
      } else {
        responses.first.complete({
          'username': 'old_player',
          'bio': 'Old biography',
        });
      }
      await tester.pumpAndSettle();
      expect(find.text('New biography'), findsOneWidget);
      expect(find.text('Old biography'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final covered in [false, true]) {
    testWidgets('loaded fresh profile is cleared on signout covered=$covered', (
      tester,
    ) async {
      final auth = TestAuth();
      final events = StreamController<User?>.broadcast(sync: true);
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        authChanges: events.stream,
        databaseRead:
            (_) async => {
              'username': 'target_player',
              'bio': 'Private session biography',
            },
      );
      addTearDown(() async {
        online.dispose();
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
            page: PublicPlayerProfileScreen(
              targetUid: 'target',
              online: online,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Private session biography'), findsOneWidget);
      if (covered) {
        unawaited(
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('cover')),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }
      auth.currentUser = null;
      events.add(null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text('Private session biography', skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byType(PublicPlayerProfileScreen, skipOffstage: false),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final english in [false, true]) {
    for (final size in [
      const Size(320, 568),
      const Size(568, 320),
      const Size(800, 1280),
    ]) {
      for (final missing in [false, true]) {
        testWidgets(
          'profile status fits en=$english size=$size missing=$missing',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final online = LunoOnlineService.forTesting(
              bootstrap: () async {},
              auth: TestAuth(),
              databaseRead: (_) async {
                if (missing) return null;
                throw StateError('offline');
              },
            );
            addTearDown(online.dispose);
            await online.start();
            await tester.pumpWidget(
              MaterialApp(
                theme: LunoTheme.dark,
                locale: Locale(english ? 'en' : 'tr'),
                supportedLocales: LunoLocalizations.supportedLocales,
                localizationsDelegates: const [
                  LunoLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                builder:
                    (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: const TextScaler.linear(1.8)),
                      child: child!,
                    ),
                home: PublicPlayerProfileScreen(
                  targetUid: 'target',
                  online: online,
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              find.text(english ? 'TRY AGAIN' : 'TEKRAR DENE'),
              findsOneWidget,
            );
            expect(find.byType(CircularProgressIndicator), findsNothing);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
}
