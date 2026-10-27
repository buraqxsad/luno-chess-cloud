import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/cards/card_catalog.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/card_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  for (final action in ['Desteye ekle', 'Desteden çıkar']) {
    for (final change in ['none', 'auth', 'store', 'signout', 'roundtrip']) {
      testWidgets('$action cannot cross $change account boundary', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        final store =
            GameStore.createForTesting()
              ..loaded = true
              ..accountUid = 'first';
        final auth = TestAuth();
        final changes = StreamController<User?>.broadcast(sync: true);
        final online = LunoOnlineService.forTesting(
          bootstrap: () async {},
          auth: auth,
          authChanges: changes.stream,
        );
        addTearDown(() async {
          online.dispose();
          store.dispose();
          await changes.close();
        });
        await online.start();
        var calls = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: LunoTheme.dark,
            home: Builder(
              builder:
                  (context) => Scaffold(
                    body: TextButton(
                      onPressed:
                          () => showCardActionMenu(
                            context,
                            kCards.keys.first,
                            owned: true,
                            onAddToDeck: () => calls++,
                            onRemoveFromDeck: () => calls++,
                            playerStore: store,
                            online: online,
                          ),
                      child: const Text('Open'),
                    ),
                  ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        if (change == 'auth') auth.currentUser = TestUser('second');
        if (change == 'store') store.accountUid = 'second';
        if (change == 'signout') auth.currentUser = null;
        if (change == 'roundtrip') {
          auth.currentUser = TestUser('second');
          changes.add(auth.currentUser);
          await tester.pumpAndSettle();
          auth.currentUser = TestUser('first');
          changes.add(auth.currentUser);
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
        expect(calls, change == 'none' ? 1 : 0);
        expect(find.text(action), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
