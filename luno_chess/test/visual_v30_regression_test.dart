import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GameStore.instance.data = PlayerData.initial();
    GameStore.instance.loaded = true;
  });

  testWidgets('level rewards do not truncate player level to 50', (
    tester,
  ) async {
    GameStore.instance.data.lvl = 62;
    await tester.pumpWidget(
      MaterialApp(theme: LunoTheme.dark, home: const LevelRewardsScreen()),
    );
    expect(find.textContaining('62'), findsOneWidget);
    expect(find.text('Seviye 63'), findsOneWidget);
    expect(find.text('+1360 altın'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'membership never presents a gem Pass price or treats Pass as membership',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(theme: LunoTheme.dark, home: const LunoPremiumScreen()),
      );
      expect(find.textContaining('450'), findsNothing);
      expect(find.byKey(const ValueKey('membership-status')), findsOneWidget);
      GameStore.instance.data.premium = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(theme: LunoTheme.dark, home: const LunoPremiumScreen()),
      );
      final button = tester.widget<LunoButton>(find.byType(LunoButton));
      expect(button.onPressed, isNull);
      expect(GameStore.instance.data.isMembershipActive, false);
      expect(button.label, 'ABONELİK SEÇENEKLERİ');
      expect(tester.takeException(), isNull);
    },
  );
}
