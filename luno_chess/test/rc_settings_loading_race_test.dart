import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

const stored = <String, Object>{
  'schemaVersion': 3,
  'effectsLevel': 1,
  'musicLevel': 0,
  'vibrationEnabled': false,
  'language': LunoSettings.languageEnglish,
};

void main() {
  for (final structured in [false, true]) {
    test('early effects change preserves other stored preferences: '
        '${structured ? 'current schema' : 'legacy migration'}', () async {
      SharedPreferences.setMockInitialValues(
        structured
            ? {
              LunoSettings.storageKey: jsonEncode(stored),
              LunoSettings.storageVersionKey: LunoSettings.storageVersion,
            }
            : {
              'sound_level': 1,
              'music_level': 0,
              'vibration': false,
              'language': LunoSettings.languageEnglish,
            },
      );
      final settings = LunoSettings();
      final loading = settings.load();
      final changed = settings.setEffectsLevel(0);
      await Future.wait([loading, changed]);
      await settings.flush();

      final music = structured ? 0 : 1;
      expectValues(settings, effects: 0, music: music);
      final reloaded = LunoSettings();
      await reloaded.load();
      expectValues(reloaded, effects: 0, music: music);
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString(LunoSettings.storageKey)!), {
        ...stored,
        'effectsLevel': 0,
        'musicLevel': music,
      });
      expect(prefs.getInt(LunoSettings.storageVersionKey), 3);
      settings.dispose();
      reloaded.dispose();
    });
  }

  test(
    'setter before explicit load does not replace untouched preferences',
    () async {
      SharedPreferences.setMockInitialValues({
        LunoSettings.storageKey: jsonEncode(stored),
        LunoSettings.storageVersionKey: LunoSettings.storageVersion,
      });
      final settings = LunoSettings();
      await settings.setEffectsLevel(0);
      await settings.flush();
      expect(settings.loaded, isTrue);
      expectValues(settings, effects: 0);
      final reloaded = LunoSettings();
      await reloaded.load();
      expectValues(reloaded, effects: 0);
      settings.dispose();
      reloaded.dispose();
    },
  );

  test(
    'multiple early changes merge before queued writes and reload',
    () async {
      SharedPreferences.setMockInitialValues({
        'sound_level': 1,
        'music_level': 0,
        'vibration': false,
        'language': LunoSettings.languageEnglish,
      });
      final settings = LunoSettings();
      final loading = settings.load();
      final changes = [
        settings.setEffectsLevel(0),
        settings.setMusicLevel(1),
        settings.setEffectsLevel(2),
      ];
      await Future.wait([loading, ...changes]);
      await settings.flush();
      expectValues(settings, effects: 2, music: 1);
      final reloaded = LunoSettings();
      await reloaded.load();
      expectValues(reloaded, effects: 2, music: 1);
      settings.dispose();
      reloaded.dispose();
    },
  );

  test(
    'explicit default-level choice before load is not silently ignored',
    () async {
      SharedPreferences.setMockInitialValues({
        LunoSettings.storageKey: jsonEncode({...stored, 'effectsLevel': 0}),
        LunoSettings.storageVersionKey: LunoSettings.storageVersion,
      });
      final settings = LunoSettings();
      final loading = settings.load();
      final changed = settings.setEffectsLevel(2);
      await Future.wait([loading, changed]);
      await settings.flush();
      expectValues(settings, effects: 2);
      final reloaded = LunoSettings();
      await reloaded.load();
      expectValues(reloaded, effects: 2);
      settings.dispose();
      reloaded.dispose();
    },
  );
}

void expectValues(
  LunoSettings settings, {
  required int effects,
  int music = 0,
}) {
  expect(settings.effectsLevel, effects);
  expect(settings.musicLevel, music);
  expect(settings.vibrationEnabled, isFalse);
  expect(settings.language, LunoSettings.languageEnglish);
}
