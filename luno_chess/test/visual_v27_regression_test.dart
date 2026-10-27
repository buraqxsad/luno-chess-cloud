import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GameStore.instance.data = PlayerData.initial();
    GameStore.instance.loaded = true;
  });

  Future<dynamic> mount(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(MaterialApp(theme: LunoTheme.dark, home: screen));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    return tester.state(find.byType(screen.runtimeType));
  }

  testWidgets('notification stream waiting is not an empty inbox', (
    tester,
  ) async {
    final dynamic state = await mount(tester, const InboxScreen());
    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();
    state.setState(() {
      state.error = null;
      state.notificationStream = controller.stream;
      state.inboxStream = Stream<List<Map<String, dynamic>>>.value([]);
    });
    await tester.pump();
    expect(find.text('Henüz bildirim yok'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    controller.add([]);
    await tester.pump();
    expect(find.text('Henüz bildirim yok'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.close();
  });

  testWidgets('read notification opens full details and closes safely', (
    tester,
  ) async {
    final dynamic state = await mount(tester, const InboxScreen());
    const message =
        'Uzun bildirim: arkadaşın davetini kabul etti. Maça başlamadan önce desteni kontrol edebilirsin.';
    state.setState(() {
      state.error = null;
      state.notificationStream = Stream<List<Map<String, dynamic>>>.value([
        {
          'notificationId': 'fixture-read',
          'type': 'general',
          'message': message,
          'read': true,
        },
      ]);
      state.inboxStream = Stream<List<Map<String, dynamic>>>.value([]);
    });
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text(message));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(message),
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(LunoButton, 'TAMAM'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('zero-target mission does not expose a claim action', (
    tester,
  ) async {
    final dynamic state = await mount(tester, const MissionsScreen());
    state.setState(() {
      state.loading = false;
      state.error = null;
      state.missions = <String, List<Map<String, dynamic>>>{
        'daily': [
          {
            'id': 'invalid',
            'title': 'Kontrol',
            'target': 0,
            'progress': 0,
            'reward': {'gold': 100},
          },
        ],
        'weekly': [],
        'special': [],
      };
    });
    await tester.pump();
    expect(find.byTooltip('Ödülü al'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mission failure has an actionable retry control', (
    tester,
  ) async {
    final dynamic state = await mount(tester, const MissionsScreen());
    state.setState(() {
      state.loading = false;
      state.error = 'Görevler sunucudan yüklenemedi.';
    });
    await tester.pump();
    expect(find.widgetWithText(LunoButton, 'TEKRAR DENE'), findsOneWidget);
    expect(
      tester.widget<LunoButton>(find.byType(LunoButton)).onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
