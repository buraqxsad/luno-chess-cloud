import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/navigation/luno_account_modal.dart';
import 'package:luno_chess/services/luno_online_service.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  late TestAuth auth;
  late StreamController<User?> events;
  late LunoOnlineService service;
  late GlobalKey<NavigatorState> navigator;
  late BuildContext pageContext;

  setUp(() async {
    auth = TestAuth();
    events = StreamController<User?>.broadcast(sync: true);
    service = LunoOnlineService.forTesting(
      bootstrap: () async {},
      auth: auth,
      authChanges: events.stream,
    );
    navigator = GlobalKey<NavigatorState>();
    await service.start();
  });

  tearDown(() async {
    service.dispose();
    await events.close();
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold(body: Text('base page'));
          },
        ),
      ),
    );
  }

  Future<bool?> open(bool sheet) {
    Widget content(BuildContext context) => AlertDialog(
      title: const Text('private old account text'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('confirm'),
        ),
      ],
    );
    return sheet
        ? showLunoAccountBottomSheet<bool>(
          context: pageContext,
          builder: content,
          service: service,
        )
        : showLunoAccountDialog<bool>(
          context: pageContext,
          builder: content,
          service: service,
        );
  }

  void change(String mode) {
    auth.currentUser = mode == 'account' ? TestUser('second') : null;
    events.add(auth.currentUser);
    if (mode == 'same-uid') {
      auth.currentUser = TestUser('first');
      events.add(auth.currentUser);
    }
  }

  for (final sheet in [false, true]) {
    final kind = sheet ? 'sheet' : 'dialog';
    for (final mode in ['account', 'signout', 'same-uid']) {
      testWidgets(
        '$kind $mode hides private content and returns no confirmation',
        (tester) async {
          await mount(tester);
          final result = open(sheet);
          await tester.pumpAndSettle();
          expect(find.text('private old account text'), findsOneWidget);
          change(mode);
          await tester.pump();
          await tester.pumpAndSettle();
          expect(await result, isNull);
          expect(
            find.text('private old account text', skipOffstage: false),
            findsNothing,
          );
          expect(find.text('base page'), findsOneWidget);
          expect(navigator.currentState!.canPop(), isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('$kind discards a stale confirmation before the next frame', (
      tester,
    ) async {
      await mount(tester);
      final result = open(sheet);
      await tester.pumpAndSettle();
      final confirm =
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'confirm'))
              .onPressed!;
      change('account');
      confirm();
      await tester.pumpAndSettle();
      expect(await result, isNull);
      expect(navigator.currentState!.canPop(), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '$kind preserves valid confirmation across same-account retry',
      (tester) async {
        await mount(tester);
        final result = open(sheet);
        await tester.pumpAndSettle();
        await service.retry();
        await tester.pump();
        expect(find.text('private old account text'), findsOneWidget);
        await tester.tap(find.text('confirm'));
        await tester.pumpAndSettle();
        expect(await result, isTrue);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$kind invalidated before first render never builds old content',
      (tester) async {
        await mount(tester);
        final result = open(sheet);
        change('account');
        await tester.pumpAndSettle();
        expect(await result, isNull);
        expect(
          find.text('private old account text', skipOffstage: false),
          findsNothing,
        );
        expect(navigator.currentState!.canPop(), isFalse);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('$kind closes only its own route below another screen', (
      tester,
    ) async {
      await mount(tester);
      final result = open(sheet);
      await tester.pumpAndSettle();
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('unrelated screen')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      change('account');
      await tester.pumpAndSettle();
      expect(await result, isNull);
      expect(find.text('unrelated screen'), findsOneWidget);
      expect(
        find.text('private old account text', skipOffstage: false),
        findsNothing,
      );
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('base page'), findsOneWidget);
      expect(navigator.currentState!.canPop(), isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
