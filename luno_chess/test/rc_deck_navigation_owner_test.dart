import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/navigation/luno_account_scope.dart';
import 'package:luno_chess/screens/battle_deck_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/widgets/luno_surface.dart';

import 'battle_deck_account_test.dart' show response;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'online_request_session_test.dart' show TestAuth, TestUser;

void main() {
  setupPracticeTestAssets();
  test('battle deck opts into account-owned navigation', () {
    expect(const BattleDeckScreen(), isA<LunoAccountScopedPage>());
  });

  for (final scenario in ['normal', 'account', 'covered', 'disposed']) {
    testWidgets('deck actions respect $scenario owner/route state', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = TestAuth()..currentUser = TestUser('first');
      final online = LunoOnlineService.forTesting(
        auth: auth,
        bootstrap: () async {},
      );
      addTearDown(online.dispose);
      var saves = 0;
      await tester.pumpWidget(
        shell(
          BattleDeckScreen(
            online: online,
            loadOverride: () async => response(),
            saveOverride: (deck) async {
              saves++;
              return {'ok': true, 'deck': deck};
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final slot = find.byKey(const ValueKey('deck-slot-purify'));
      final tap = tester.widget<InkWell>(slot).onTap!;
      final dynamic state = tester.state(find.byType(BattleDeckScreen));
      state.setState(() {
        state.selected = [...starterDeck.take(9), CardId.fog];
      });
      await tester.pump();
      final save =
          tester
              .widgetList<LunoButton>(find.byType(LunoButton))
              .singleWhere((button) => button.onPressed != null)
              .onPressed!;
      if (scenario == 'account') auth.currentUser = TestUser('second');
      if (scenario == 'covered') {
        Navigator.of(
          tester.element(find.byType(BattleDeckScreen)),
        ).push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
        await tester.pump();
      }
      if (scenario == 'disposed') {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }
      save();
      await tester.pump();
      tap();
      await tester.pump();
      expect(saves, scenario == 'normal' ? 1 : 0);
      if (scenario != 'normal' && scenario != 'disposed') {
        expect(state.selected, hasLength(10));
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('card detail ignores duplicate and disposed entry callbacks', (
    tester,
  ) async {
    BuildContext? page;
    await tester.pumpWidget(
      shell(
        Builder(
          builder: (context) {
            page = context;
            return const Scaffold();
          },
        ),
      ),
    );
    showBattleCatalogDetail(page!, CardId.radar);
    showBattleCatalogDetail(page!, CardId.radar);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byType(BottomSheet, skipOffstage: false), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await showBattleCatalogDetail(page!, CardId.radar);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card detail close owns current route and rejects stale calls', (
    tester,
  ) async {
    late BuildContext owner;
    await tester.pumpWidget(
      shell(
        Builder(
          builder: (context) {
            owner = context;
            return const Scaffold(body: Text('detail-owner'));
          },
        ),
      ),
    );
    final detail = showBattleCatalogDetail(owner, CardId.radar);
    await tester.pumpAndSettle();
    final close =
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == 'Kapat',
              ),
            )
            .onPressed!;
    final navigator = Navigator.of(owner);
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('detail-cover')),
      ),
    );
    await tester.pumpAndSettle();
    close();
    await tester.pumpAndSettle();
    expect(find.text('detail-cover'), findsOneWidget);
    expect(find.byType(BottomSheet, skipOffstage: false), findsOneWidget);
    navigator.pop();
    await tester.pumpAndSettle();
    close();
    close();
    await tester.pumpAndSettle();
    await detail;
    expect(find.byType(BottomSheet, skipOffstage: false), findsNothing);
    expect(find.text('detail-owner'), findsOneWidget);
    expect(close, returnsNormally);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(close, returnsNormally);
  });
}
