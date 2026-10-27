import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/pass_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:luno_chess/widgets/resource_amount.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GameStore.instance.data = PlayerData.initial();
    GameStore.instance.loaded = true;
  });

  Future<void> pumpPass(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: LunoTheme.dark, home: const PassScreen()),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  }

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(800, 1280),
  ]) {
    testWidgets('all premium tiers remain reachable at ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = GameStore.instance.data;
      data.passXp = 7500;
      data.premium = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: LunoTheme.dark,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!,
              ),
          home: const PassScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.scrollUntilVisible(
        find.text('Neon Krallık Seti'),
        350,
        maxScrolls: 60,
      );
      expect(find.text('Neon Krallık Seti'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('future rewards stay visible without enabling claims', (
    tester,
  ) async {
    await pumpPass(tester);
    final amounts = tester.widgetList<ResourceAmount>(
      find.byType(ResourceAmount),
    );
    expect(amounts.any((amount) => amount.value == 120), isTrue);
    expect(amounts.any((amount) => amount.value == 18), isTrue);
    expect(find.widgetWithText(LunoButton, 'AL'), findsNothing);
    expect(find.text('Ödül hazır değil'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('claimed free reward stays visible and cannot be claimed again', (
    tester,
  ) async {
    final data = GameStore.instance.data;
    data.passXp = 250;
    data.passFreeClaimed.add(1);
    await pumpPass(tester);
    expect(find.text('Alındı'), findsOneWidget);
    expect(find.widgetWithText(LunoButton, 'AL'), findsNothing);
    expect(
      tester
          .widgetList<ResourceAmount>(find.byType(ResourceAmount))
          .any((a) => a.value == 120),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'unlocked free tier exposes only one claim while premium remains locked',
    (tester) async {
      GameStore.instance.data.passXp = 250;
      await pumpPass(tester);
      expect(find.widgetWithText(LunoButton, 'AL'), findsOneWidget);
      expect(
        tester.getSize(find.widgetWithText(LunoButton, 'AL')).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is LunoArt &&
              widget.path == 'assets/native_art/v205-lock-premium.png',
        ),
        findsWidgets,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
