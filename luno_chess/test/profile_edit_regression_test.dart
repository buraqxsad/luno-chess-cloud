import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(568, 320),
    const Size(800, 1280),
  ]) {
    testWidgets('profile avatar layout at $size with enlarged text', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      GameStore.instance.data = PlayerData.initial();
      GameStore.instance.loaded = true;
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
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
          home: const EditProfileScreen(),
        ),
      );
      for (
        var i = 0;
        i < 20 && find.text('Robot Kral').hitTestable().evaluate().isEmpty;
        i++
      ) {
        await tester.drag(find.byType(ListView), const Offset(0, -180));
        await tester.pumpAndSettle();
      }
      expect(find.text('Robot Kral').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Robot Kral'));
      await tester.pump();
      final dynamic state = tester.state(find.byType(EditProfileScreen));
      expect(state.avatar, 'av_robotcrown');
      expect(find.text('ROBOTCROWN'), findsNothing);
      for (
        var i = 0;
        i < 20 && find.text('KAYDET').hitTestable().evaluate().isEmpty;
        i++
      ) {
        await tester.drag(find.byType(ListView), const Offset(0, -180));
        await tester.pumpAndSettle();
      }
      expect(find.text('KAYDET').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('profile save locks inputs and ignores disposed callbacks', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    GameStore.instance.data = PlayerData.initial();
    GameStore.instance.loaded = true;
    await tester.pumpWidget(
      MaterialApp(theme: LunoTheme.dark, home: const EditProfileScreen()),
    );
    final save = find.byWidgetPredicate(
      (w) => w is IconButton && w.tooltip == 'Kaydet',
    );
    final callback = tester.widget<IconButton>(save).onPressed!;
    final dynamic state = tester.state(find.byType(EditProfileScreen));
    state.setState(() => state.saving = true);
    await tester.pump();
    expect(tester.widget<IconButton>(save).onPressed, isNull);
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .onChanged,
      isNull,
    );
    callback();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    callback();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
