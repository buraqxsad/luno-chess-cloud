import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/navigation/luno_account_scope.dart';
import 'package:luno_chess/screens/collection_screens.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/screens/pass_screen.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'online_request_session_test.dart' show TestAuth;

void main() {
  setupPracticeTestAssets();
  for (final page in const <Widget>[
    SeasonScreen(),
    MissionsScreen(),
    EditProfileScreen(),
    SettingsScreen(),
    PassScreen(),
    ShopScreen(),
    LunoPremiumScreen(),
    PieceCostumeScreen(),
    EmojiCollectionScreen(),
  ]) {
    test('${page.runtimeType} resets private state with its account route', () {
      expect(page, isA<LunoAccountScopedPage>());
    });
  }
  for (final mission in [false, true]) {
    testWidgets(
      '${mission ? 'mission' : 'season'} bootstrap has a recovery deadline',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final store =
            GameStore.createForTesting()
              ..loaded = true
              ..accountUid = 'first';
        final pending = Completer<void>();
        final online = LunoOnlineService.forTesting(
          bootstrap: () => pending.future,
          auth: TestAuth(),
        );
        addTearDown(() {
          online.dispose();
          store.dispose();
        });
        await tester.pumpWidget(
          shell(
            mission
                ? MissionsScreen(online: online, playerStore: store)
                : SeasonScreen(online: online, playerStore: store),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 13));
        expect(
          find.text(
            mission
                ? 'Görevler sunucudan yüklenemedi.'
                : 'Sezon bilgileri sunucudan yüklenemedi.',
          ),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
        pending.complete();
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
