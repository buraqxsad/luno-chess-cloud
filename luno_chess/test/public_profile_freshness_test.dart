import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:luno_chess/screens/public_player_profile_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  for (final scenario in [
    'success',
    'missing',
    'malformed',
    'error',
    'account',
    'disposed',
    'target',
  ]) {
    testWidgets('fresh public profile handles $scenario', (tester) async {
      final auth = TestAuth();
      final responses = <Completer<Object?>>[];
      final paths = <String>[];
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        databaseRead: (path) {
          paths.add(path);
          final response = Completer<Object?>();
          responses.add(response);
          return response.future;
        },
      );
      addTearDown(online.dispose);
      await online.start();
      Future<void> render(String uid) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: LunoTheme.dark,
            home: PublicPlayerProfileScreen(targetUid: uid, online: online),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }

      await render('target');
      expect(paths, ['publicProfiles/target']);
      expect(find.byType(PlayerDetailsScreen), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      if (scenario == 'account') auth.currentUser = TestUser('second');
      if (scenario == 'disposed') {
        await tester.pumpWidget(const SizedBox.shrink());
      }
      if (scenario == 'target') {
        await render('new_target');
        expect(paths, ['publicProfiles/target', 'publicProfiles/new_target']);
        responses[1].complete({
          'username': 'new_player',
          'bio': 'Newest biography',
          'isPremium': true,
        });
        await tester.pump(const Duration(milliseconds: 50));
      }
      if (scenario == 'error') {
        responses.first.completeError(StateError('offline'));
      } else {
        responses.first.complete(
          scenario == 'missing'
              ? null
              : scenario == 'malformed'
              ? {'username': 42}
              : {
                'username': 'current_player',
                'bio': 'Fresh biography',
                'isPremium': true,
              },
        );
      }
      await tester.pump(const Duration(milliseconds: 100));
      if (scenario == 'success') {
        expect(find.text('Fresh biography'), findsOneWidget);
        expect(find.textContaining('LUNO PREMIUM'), findsOneWidget);
      } else if (scenario == 'target') {
        expect(find.text('Newest biography'), findsOneWidget);
        expect(find.text('Fresh biography'), findsNothing);
      } else {
        expect(find.byType(PlayerDetailsScreen), findsNothing);
        if (scenario == 'missing') {
          expect(
            find.text('Bu oyuncunun profili artık mevcut değil.'),
            findsOneWidget,
          );
        }
        if (scenario == 'error' || scenario == 'malformed') {
          expect(find.text('Oyuncu profili yüklenemedi.'), findsOneWidget);
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
    'refresh discards stale data and duplicate callbacks share a read',
    (tester) async {
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
      responses.first.complete({
        'username': 'current_player',
        'bio': 'Old biography',
      });
      await tester.pumpAndSettle();
      final callback =
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is IconButton && widget.tooltip == 'Yenile',
                ),
              )
              .onPressed!;
      callback();
      callback();
      await tester.pump(const Duration(milliseconds: 50));
      expect(responses, hasLength(2));
      expect(find.text('Old biography'), findsNothing);
      responses[1].complete(null);
      await tester.pumpAndSettle();
      expect(
        find.text('Bu oyuncunun profili artık mevcut değil.'),
        findsOneWidget,
      );
      await tester.tap(find.text('TEKRAR DENE'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(responses, hasLength(3));
      responses[2].complete({
        'username': 'current_player',
        'bio': 'New biography',
      });
      await tester.pumpAndSettle();
      expect(find.text('New biography'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('invalid public target never dispatches a read', () async {
    var reads = 0;
    final online = LunoOnlineService.forTesting(
      bootstrap: () async {},
      auth: TestAuth(),
      databaseRead: (_) async {
        reads++;
        return null;
      },
    );
    addTearDown(online.dispose);
    await online.start();
    expect(() => online.publicPlayerProfile('bad/path'), throwsFormatException);
    expect(reads, 0);
  });
}
