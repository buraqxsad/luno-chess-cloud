import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

Widget app(LunoOnlineService online, String language) => MaterialApp(
  theme: LunoTheme.dark,
  locale: Locale(language),
  supportedLocales: const [Locale('tr'), Locale('en')],
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
  home: InboxScreen(online: online),
);

void main() {
  for (final language in ['tr', 'en']) {
    for (final size in [
      const Size(320, 568),
      const Size(568, 320),
      const Size(800, 1280),
    ]) {
      testWidgets('inbox timeout and retry layout $language $size', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final pending = Completer<void>();
        var attempts = 0;
        final online = LunoOnlineService.forTesting(
          auth: TestAuth(),
          bootstrap: () {
            attempts++;
            return attempts == 1
                ? pending.future
                : Future.error(StateError('Unavailable'));
          },
        );
        addTearDown(online.dispose);
        await tester.pumpWidget(app(online, language));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(
          InboxScreen.connectionTimeout + const Duration(milliseconds: 50),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(
          find.text(
            language == 'en'
                ? 'The inbox could not be opened.'
                : 'Mesaj kutusu şu an açılamıyor.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        // Finishing the old bootstrap must not silently reopen the timed-out UI.
        pending.completeError(StateError('Late bootstrap failure'));
        await tester.pumpAndSettle();
        expect(attempts, 1);
        final retry = find.text(language == 'en' ? 'TRY AGAIN' : 'TEKRAR DENE');
        await tester.ensureVisible(retry);
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(attempts, 2);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(retry, findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  for (final departure in ['account', 'disposed', 'covered']) {
    testWidgets('inbox timeout ignores departed session $departure', (
      tester,
    ) async {
      final auth = TestAuth();
      final pending = Completer<void>();
      final online = LunoOnlineService.forTesting(
        auth: auth,
        bootstrap: () => pending.future,
      );
      addTearDown(online.dispose);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: LunoTheme.dark,
          home: InboxScreen(online: online),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      final dynamic state = tester.state(find.byType(InboxScreen));
      if (departure == 'account') {
        auth.currentUser = TestUser('second');
      } else if (departure == 'disposed') {
        await tester.pumpWidget(const MaterialApp(home: Text('Replacement')));
      } else {
        unawaited(
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Covered')),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.pump(
        InboxScreen.connectionTimeout + const Duration(milliseconds: 50),
      );
      pending.completeError(StateError('Late bootstrap failure'));
      // The unscoped account-change fixture intentionally keeps its old spinner.
      // Production account-scope replacement is verified in the scope suite.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SnackBar), findsNothing);
      if (departure == 'account') {
        expect(state.error, isNull);
      } else if (departure == 'disposed') {
        expect(find.text('Replacement'), findsOneWidget);
      } else {
        expect(find.text('Covered'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
