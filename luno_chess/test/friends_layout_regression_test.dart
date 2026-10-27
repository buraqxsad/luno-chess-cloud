import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'online_request_session_test.dart' show TestAuth;

Future<LunoOnlineService> readyOnline() async {
  final online = LunoOnlineService.forTesting(
    bootstrap: () async {},
    auth: TestAuth(),
    databaseRead: (_) async => {},
    friendRequestStream: const Stream.empty(),
    matchInviteStream: const Stream.empty(),
  );
  await online.start();
  return online;
}

void main() {
  testWidgets(
    'request actions remain reachable with large text and empty state',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final online = await readyOnline();
      addTearDown(online.dispose);
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: LunoTheme.dark,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
          home: FriendsScreen(online: online),
        ),
      );
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(FriendsScreen));
      state.setState(() {
        state.tab = 1;
        state.socialLoading = false;
        state.requestRows = <Map<String, dynamic>>[
          {'fromUid': 'fixture', 'fromUsername': 'long_player_name'},
        ];
      });
      await tester.pump();
      for (final label in ['Kabul et', 'Reddet']) {
        final button = find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == label,
        );
        expect(button.hitTestable(), findsOneWidget);
        expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      }
      expect(tester.takeException(), isNull);
      state.setState(() => state.requestRows = <Map<String, dynamic>>[]);
      await tester.pump();
      expect(find.text('Bekleyen istek yok'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final size in [
    const Size(320, 568),
    const Size(568, 320),
    const Size(800, 1280),
  ]) {
    testWidgets('friends list remains scrollable at $size', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final online = await readyOnline();
      addTearDown(online.dispose);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: LunoTheme.dark,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
          home: FriendsScreen(online: online),
        ),
      );
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(FriendsScreen));
      state.setState(() {
        state.socialLoading = false;
        state.friendRows = List<Map<String, dynamic>>.generate(
          15,
          (i) => {
            'uid': 'fixture_$i',
            'username': 'Player_$i',
            'trophies': 999999999,
          },
        );
      });
      await tester.pump();
      ScaffoldMessenger.of(
        tester.element(find.byType(FriendsScreen)),
      ).clearSnackBars();
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.text('player_14'),
        find.byType(NestedScrollView),
        const Offset(0, -160),
        maxIteration: 40,
      );
      await tester.pumpAndSettle();
      expect(find.text('player_14').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
