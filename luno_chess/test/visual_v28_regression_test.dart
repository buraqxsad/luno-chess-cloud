import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/game_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GameStore.instance.data = PlayerData.initial();
    GameStore.instance.loaded = true;
  });

  testWidgets('move phase clears armed card and cannot be skipped twice', (
    tester,
  ) async {
    for (final channel in [
      'xyz.luan/audioplayers.global/events',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers',
      for (final id in ['luno_music', 'luno_sfx_0', 'luno_sfx_1', 'luno_sfx_2'])
        'xyz.luan/audioplayers/events/$id',
    ]) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (_) async => null,
      );
    }
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: LunoTheme.dark,
        home: GameScreen(level: aiLevels.first, local: true),
      ),
    );
    final dynamic state = tester.state(find.byType(GameScreen));
    final turn = state.m.turn;
    state.setState(() {
      state.armedKey = state.m.handOf(turn).first;
      state.cardTargets = <int>{16};
      state.gluePendingFirst = 8;
      state.selected = 8;
      state.moveTargets = <int>{16};
    });
    await tester.pump();
    final button = find.byWidgetPredicate(
      (w) => w is LunoButton && w.label == 'HAMLEYE GEÇ',
    );
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    await tester.tap(button);
    await tester.pump();
    expect(state.m.cardUsed, isTrue);
    expect(state.m.turn, turn);
    expect(state.armedKey, isNull);
    expect(state.gluePendingFirst, isNull);
    expect(state.cardTargets, isEmpty);
    expect(state.moveTargets, isEmpty);
    expect(state.selected, isNull);
    final disabled = tester.widget<LunoButton>(find.byType(LunoButton));
    expect(disabled.onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('new phase labels have English translations', () {
    const en = LunoLocalizations(Locale('en'));
    for (final label in [
      'HAMLEYE GEÇ',
      'TAŞINI SEÇ',
      'KART AŞAMASI',
      'HAMLE AŞAMASI',
      'RAKİP OYNUYOR',
      'KARTLARIN',
    ]) {
      expect(en.translate(label), isNot(label));
    }
  });
}
