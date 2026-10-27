import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:luno_chess/screens/public_player_profile_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/social_safety_actions.dart';

import 'online_request_session_test.dart' show TestAuth;

Widget app(LunoOnlineService online, {String target = 'target'}) => MaterialApp(
  theme: LunoTheme.dark,
  locale: const Locale('en'),
  supportedLocales: LunoLocalizations.supportedLocales,
  localizationsDelegates: const [
    LunoLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: PublicPlayerProfileScreen(targetUid: target, online: online),
);

void main() {
  testWidgets(
    'confirmed block removes cached profile and retry uses a fresh read',
    (tester) async {
      final language = LunoSettings.instance.language;
      LunoSettings.instance.language = LunoSettings.languageEnglish;
      addTearDown(() => LunoSettings.instance.language = language);
      var reads = 0;
      var blocks = 0;
      var unavailable = false;
      final online = LunoOnlineService.forTesting(
        auth: TestAuth(),
        bootstrap: () async {},
        appCheck: () async => 'check',
        databaseRead: (_) async {
          reads++;
          if (unavailable) return null;
          return {'username': 'target_player', 'bio': 'Cached biography'};
        },
        client: MockClient((request) async {
          expect(request.url.path, endsWith('/blockUser'));
          blocks++;
          unavailable = true;
          return http.Response(
            '{"ok":true,"blocked":true,"targetUid":"target"}',
            200,
          );
        }),
      );
      addTearDown(online.dispose);
      await online.start();
      await tester.pumpWidget(app(online));
      await tester.pumpAndSettle();
      expect(find.text('Cached biography'), findsOneWidget);
      await tester.tap(find.byTooltip('Player safety'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block player'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      expect(blocks, 1);
      expect(find.byType(PlayerDetailsScreen), findsNothing);
      expect(find.text('Cached biography'), findsNothing);
      await tester.tap(find.text('TRY AGAIN'));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.byType(PlayerDetailsScreen), findsNothing);
      unavailable = false;
      await tester.tap(find.text('TRY AGAIN'));
      await tester.pumpAndSettle();
      expect(reads, 3);
      expect(find.byType(PlayerDetailsScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('delayed profile refresh cannot restore a blocked profile', (
    tester,
  ) async {
    final delayed = Completer<Object?>();
    var reads = 0;
    final online = LunoOnlineService.forTesting(
      auth: TestAuth(),
      bootstrap: () async {},
      databaseRead: (_) {
        reads++;
        return reads == 1
            ? Future.value({
              'username': 'target_player',
              'bio': 'Old biography',
            })
            : delayed.future;
      },
    );
    addTearDown(online.dispose);
    await online.start();
    await tester.pumpWidget(app(online));
    await tester.pumpAndSettle();
    final safety = tester.widget<SocialSafetyActions>(
      find.byType(SocialSafetyActions),
    );
    expect(safety.onBlocked, isNotNull);
    final blocked = safety.onBlocked!;
    tester
        .widget<PlayerDetailsScreen>(find.byType(PlayerDetailsScreen))
        .onRefresh!();
    await tester.pump();
    expect(reads, 2);
    blocked('target');
    delayed.complete({'username': 'target_player', 'bio': 'Late biography'});
    await tester.pumpAndSettle();
    expect(find.byType(PlayerDetailsScreen), findsNothing);
    expect(find.text('Late biography'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('old block callback cannot remove a replacement target profile', (
    tester,
  ) async {
    final online = LunoOnlineService.forTesting(
      auth: TestAuth(),
      bootstrap: () async {},
      databaseRead:
          (path) async => {
            'username':
                path.endsWith('/target') ? 'target_player' : 'next_player',
          },
    );
    addTearDown(online.dispose);
    await online.start();
    await tester.pumpWidget(app(online));
    await tester.pumpAndSettle();
    final safety = tester.widget<SocialSafetyActions>(
      find.byType(SocialSafetyActions),
    );
    expect(safety.onBlocked, isNotNull);
    final blocked = safety.onBlocked!;
    await tester.pumpWidget(app(online, target: 'next'));
    await tester.pumpAndSettle();
    blocked('target');
    await tester.pump();
    expect(
      tester.widget<PlayerDetailsScreen>(find.byType(PlayerDetailsScreen)).name,
      'next_player',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    blocked('target');
    expect(tester.takeException(), isNull);
  });
}
