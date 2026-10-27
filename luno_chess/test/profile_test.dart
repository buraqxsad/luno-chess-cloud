import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/profile_screen.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(568, 320),
    const Size(800, 1280),
  ]) {
    testWidgets('profile metadata stays readable at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      GameStore.instance.data.username = 'LunoPlayerLongName';
      GameStore.instance.data.country = 'GB';
      GameStore.instance.data.trophies = 99999;
      GameStore.instance.data.gold = 999999999;
      GameStore.instance.data.gems = 999999999;
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
          home: const ProfileScreen(),
        ),
      );
      expect(find.text('GB'), findsOneWidget);
      expect(
        find.ancestor(of: find.text('GB'), matching: find.byType(FittedBox)),
        findsNothing,
      );
      for (
        var i = 0;
        i < 12 && find.text('BAŞARIMLAR').hitTestable().evaluate().isEmpty;
        i++
      ) {
        await tester.drag(find.byType(ListView), const Offset(0, -220));
        await tester.pumpAndSettle();
      }
      expect(find.text('BAŞARIMLAR').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GameStore.instance.data = PlayerData.initial();
  });

  testWidgets('public profile preserves wins when total is stale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LunoTheme.dark,
        home: const PlayerDetailsScreen(
          name: 'Deniz',
          trophies: 100,
          wins: 8,
          games: 0,
          country: 'JP',
        ),
      ),
    );
    expect(find.text('8'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('own profile distinguishes unknown results from draws', (
    tester,
  ) async {
    GameStore.instance.data.wins = 3;
    GameStore.instance.data.losses = 1;
    GameStore.instance.data.draws = 2;
    GameStore.instance.data.gamesPlayed = 10;
    await tester.pumpWidget(
      MaterialApp(theme: LunoTheme.dark, home: const ProfileScreen()),
    );
    await tester.scrollUntilVisible(
      find.text('Sonucu bilinmeyen'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final row =
        find
            .ancestor(
              of: find.text('Sonucu bilinmeyen'),
              matching: find.byType(Row),
            )
            .first;
    expect(find.descendant(of: row, matching: find.text('4')), findsOneWidget);
    final draws =
        find
            .ancestor(of: find.text('Berabere'), matching: find.byType(Row))
            .first;
    expect(
      find.descendant(of: draws, matching: find.text('2')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('profil özet ve detaylarda bilgiler tekilleşir', (tester) async {
    final store = GameStore.instance;
    store.data.username = 'luno_player';
    store.data.bio = 'Tahtada sakin, hamlede cesur.';
    store.data.trophies = 640;
    store.data.wins = 3;
    store.data.losses = 1;
    store.data.draws = 2;
    store.data.gamesPlayed = 6;
    store.data.streak = 2;
    store.data.bestStreak = 4;

    await tester.pumpWidget(
      MaterialApp(theme: LunoTheme.dark, home: const ProfileScreen()),
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(tester.takeException(), isNull);
    expect(find.text('HAKKINDA'), findsOneWidget);
    expect(find.text('KUPA'), findsOneWidget);
    expect(find.text('GALİBİYET'), findsOneWidget);
    expect(find.text('ORAN'), findsOneWidget);
    expect(find.text('SERİ'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('Berabere'), findsOneWidget);
    expect(find.text('Galibiyet oranı'), findsNothing);
  });
}
