import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    for (final channel in [
      'xyz.luan/audioplayers.global/events',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers',
      for (final id in ['luno_music', 'luno_sfx_0', 'luno_sfx_1', 'luno_sfx_2'])
        'xyz.luan/audioplayers/events/$id',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
    }
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('disabled controls never invoke actions or haptics', (
    tester,
  ) async {
    var haptics = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') haptics++;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: LunoTheme.dark,
        home: const Scaffold(
          body: LunoButton(label: 'Disabled', onPressed: null),
        ),
      ),
    );
    await tester.tap(find.byType(LunoButton));
    await tester.pump();
    expect(haptics, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('feedback never blocks actions and vibration off is respected', (
    tester,
  ) async {
    await LunoSettings.instance.load();
    await LunoSettings.instance.setVibrationEnabled(false);
    var actions = 0;
    var haptics = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') haptics++;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: LunoTheme.dark,
        home: Scaffold(
          body: LunoButton(label: 'Action', onPressed: () => actions++),
        ),
      ),
    );
    await tester.tap(find.byType(LunoButton));
    await tester.tap(find.byType(LunoButton));
    await tester.pump();
    expect(actions, 2);
    expect(haptics, 0);
    expect(tester.takeException(), isNull);
  });
}
