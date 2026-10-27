import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object> _snapshot(String language) => {
  'schemaVersion': LunoSettings.storageVersion,
  'effectsLevel': 1,
  'musicLevel': 0,
  'vibrationEnabled': false,
  'language': language,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final structured in [false, true]) {
    for (final language in LunoSettings.supportedLanguages) {
      test('explicit $language survives ${structured ? "current" : "legacy"} '
          'settings load, unrelated edits and reload', () async {
        SharedPreferences.setMockInitialValues(
          structured
              ? {
                LunoSettings.storageKey: jsonEncode(_snapshot(language)),
                LunoSettings.storageVersionKey: LunoSettings.storageVersion,
              }
              : {
                'sound_level': 0,
                'music_level': 2,
                'background_music': false,
                'vibration': false,
                'language': language,
              },
        );
        final settings = LunoSettings();
        final reloaded = LunoSettings();
        addTearDown(settings.dispose);
        addTearDown(reloaded.dispose);

        await settings.load();
        expect(settings.language, language);
        expect(settings.effectsLevel, 1);
        expect(settings.musicLevel, 0);
        expect(settings.vibrationEnabled, isFalse);

        await settings.setEffectsLevel(2);
        await settings.flush();
        await reloaded.load();
        expect(reloaded.language, language);
        expect(reloaded.effectsLevel, 2);
        expect(reloaded.musicLevel, 0);
        expect(reloaded.vibrationEnabled, isFalse);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('language'), language);
        expect(jsonDecode(prefs.getString(LunoSettings.storageKey)!), {
          ..._snapshot(language),
          'effectsLevel': 2,
        });
      });
    }
  }

  for (final language in LunoSettings.supportedLanguages) {
    test('early explicit $language wins without changing stored mute settings',
        () async {
      final previous = language == LunoSettings.languageTurkish
          ? LunoSettings.languageEnglish
          : LunoSettings.languageTurkish;
      SharedPreferences.setMockInitialValues({
        LunoSettings.storageKey: jsonEncode(_snapshot(previous)),
        LunoSettings.storageVersionKey: LunoSettings.storageVersion,
      });
      final settings = LunoSettings();
      final reloaded = LunoSettings();
      addTearDown(settings.dispose);
      addTearDown(reloaded.dispose);

      await Future.wait([settings.load(), settings.setLanguage(language)]);
      await settings.flush();
      await reloaded.load();
      for (final value in [settings, reloaded]) {
        expect(value.language, language);
        expect(value.effectsLevel, 1);
        expect(value.musicLevel, 0);
        expect(value.vibrationEnabled, isFalse);
      }
    });
  }

  test('rapid explicit language changes persist the final Turkish choice',
      () async {
    SharedPreferences.setMockInitialValues({
      LunoSettings.storageKey:
          jsonEncode(_snapshot(LunoSettings.languageEnglish)),
      LunoSettings.storageVersionKey: LunoSettings.storageVersion,
    });
    final settings = LunoSettings();
    final reloaded = LunoSettings();
    addTearDown(settings.dispose);
    addTearDown(reloaded.dispose);

    await settings.load();
    await Future.wait([
      settings.setLanguage(LunoSettings.languageTurkish),
      settings.setLanguage(LunoSettings.languageEnglish),
      settings.setLanguage(LunoSettings.languageTurkish),
    ]);
    await settings.flush();
    await reloaded.load();
    expect(settings.language, LunoSettings.languageTurkish);
    expect(reloaded.language, LunoSettings.languageTurkish);
    expect(reloaded.musicLevel, 0);
  });
}
