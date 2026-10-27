import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/difficulty_screen.dart';
import 'package:luno_chess/screens/guide_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final screen in [const DifficultyScreen(), const GuideScreen()]) {
    testWidgets('${screen.runtimeType} fits narrow enlarged text', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(320, 700);
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
          home: screen,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView), const Offset(0, -1000));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'trainer selection rejects repeated taps and resets after cancel',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      for (final channel in [
        'xyz.luan/audioplayers.global/events',
        'xyz.luan/audioplayers.global',
        'xyz.luan/audioplayers',
        for (final id in [
          'luno_music',
          'luno_sfx_0',
          'luno_sfx_1',
          'luno_sfx_2',
        ])
          'xyz.luan/audioplayers/events/$id',
      ]) {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          MethodChannel(channel),
          (_) async => null,
        );
      }
      await tester.pumpWidget(
        MaterialApp(theme: LunoTheme.dark, home: const DifficultyScreen()),
      );
      final tile =
          find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(InkWell),
              )
              .first;
      final callback = tester.widget<InkWell>(tile).onTap!;
      callback();
      await tester.pump();
      callback();
      await tester.pump();
      expect(tester.widget<InkWell>(tile).onTap, isNull);
      Navigator.of(tester.element(find.byType(DifficultyScreen))).pop();
      await tester.pumpAndSettle();
      expect(tester.widget<InkWell>(tile).onTap, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
      callback();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
