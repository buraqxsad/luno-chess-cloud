import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/screens/friendly_online_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'helpers/battle_v1_response.dart' show v1Response;
import 'online_request_session_test.dart' show TestAuth, TestUser;

class _Replacements extends NavigatorObserver {
  final oldRoutes = <Route<dynamic>?>[];
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    oldRoutes.add(oldRoute);
  }
}

void resume(WidgetTester tester) {
  final binding = tester.binding;
  if (binding.lifecycleState == AppLifecycleState.paused) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (binding.lifecycleState == AppLifecycleState.hidden) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  if (binding.lifecycleState != AppLifecycleState.resumed) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

void main() {
  setupPracticeTestAssets();
  for (final boundary in ['current', 'covered', 'paused']) {
    final covered = boundary == 'covered';
    testWidgets(
      'late friendly join replaces only its own current route: $boundary',
      (tester) async {
        final auth = TestAuth()..currentUser = TestUser('self');
        final reply = Completer<http.Response>();
        var joins = 0;
        final paths = <String>[];
        final online = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: auth,
          appCheck: () async => 'round2-local-check',
          client: MockClient((request) {
            paths.add(request.url.path);
            joins++;
            return reply.future;
          }),
        );
        addTearDown(online.dispose);
        await online.start();
        final navigator = GlobalKey<NavigatorState>();
        final observer = _Replacements();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            navigatorObservers: [observer],
            locale: const Locale('tr'),
            supportedLocales: LunoLocalizations.supportedLocales,
            localizationsDelegates: const [
              LunoLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: LunoTheme.dark,
            home: FriendlyOnlineScreen(online: online),
          ),
        );
        await tester.enterText(find.byType(TextField), 'ABC123');
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Katıl',
              ),
            )
            .onPressed!();
        await tester.pump();
        await tester.pump();
        await tester.pump();
        final dynamic diagnostics = tester.state(
          find.byType(FriendlyOnlineScreen),
        );
        expect(diagnostics.codeController.text, 'ABC123');
        expect(
          online.isOnline,
          isTrue,
          reason: 'Online fixture must be ready.',
        );
        expect(
          diagnostics.error,
          isNull,
          reason: 'Request setup: ${diagnostics.status}',
        );
        expect(joins, 1);
        expect(paths.single, endsWith('/joinBattleV1Room'));
        Route<void>? cover;
        if (boundary == 'paused') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          addTearDown(() => resume(tester));
        }
        if (covered) {
          cover = MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'round2-unrelated-page'),
            builder: (_) => const Scaffold(body: Text('Unrelated page')),
          );
          unawaited(navigator.currentState!.push(cover));
          await tester.pumpAndSettle();
          expect(cover.isCurrent, isTrue);
        }
        // Let the real HTTP/service completion and navigation finish without
        // rendering the destination battle: this assertion concerns which route
        // is replaced, not Firebase setup of the next screen.
        await tester.runAsync(() async {
          reply.complete(
            http.Response(jsonEncode(v1Response(uid: 'self')), 200),
          );
          for (var i = 0; i < 8; i++) {
            await Future<void>.delayed(Duration.zero);
          }
        });
        if (covered) {
          expect(
            cover!.isCurrent,
            isTrue,
            reason:
                'A late join must not replace an unrelated route above its page.',
          );
          expect(observer.oldRoutes, isEmpty);
          navigator.currentState!.pop();
          await tester.pump();
          expect(observer.oldRoutes, hasLength(1));
          expect(observer.oldRoutes.single!.settings.name, '/');
        } else if (boundary == 'paused') {
          expect(observer.oldRoutes, isEmpty);
          resume(tester);
          await tester.pump();
          expect(observer.oldRoutes, hasLength(1));
          expect(observer.oldRoutes.single!.settings.name, '/');
        } else {
          expect(observer.oldRoutes, hasLength(1));
          expect(observer.oldRoutes.single!.settings.name, '/');
        }
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final boundary in ['covered', 'disposed']) {
    testWidgets('old create-room callback does not dispatch after $boundary', (
      tester,
    ) async {
      var requests = 0;
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: TestAuth(),
        appCheck: () async => 'round2-local-check',
        client: MockClient((_) async {
          requests++;
          return http.Response('{"ok":true,"roomCode":"ABC123"}', 200);
        }),
      );
      addTearDown(online.dispose);
      await online.start();
      await tester.pumpWidget(shell(FriendlyOnlineScreen(online: online)));
      final button = tester.widget<LunoButton>(
        find.byWidgetPredicate(
          (widget) =>
              widget is LunoButton &&
              widget.label.startsWith('ODA KODU OLUŞTUR'),
        ),
      );
      final callback = button.onPressed!;
      final dynamic screen = tester.state(find.byType(FriendlyOnlineScreen));
      if (boundary == 'covered') {
        unawaited(
          Navigator.of(tester.element(find.byType(FriendlyOnlineScreen))).push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Other page')),
            ),
          ),
        );
        await tester.pumpAndSettle();
      } else {
        await tester.pumpWidget(const SizedBox());
      }
      callback();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(requests, 0);
      if (boundary == 'covered') {
        expect(screen.roomCode, isNull);
        expect(screen.busy, isFalse);
        expect(screen.status, 'Arkadaşınla aynı tahtaya çık.');
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
