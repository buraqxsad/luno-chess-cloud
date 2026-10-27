import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final channel in ['sound', 'music']) {
    final field = channel == 'sound' ? 'effectsLevel' : 'musicLevel';
    final enabledKey =
        channel == 'sound' ? 'sound_effects' : 'background_music';
    int level(LunoSettings settings) =>
        channel == 'sound' ? settings.effectsLevel : settings.musicLevel;
    double volume(LunoSettings settings) =>
        channel == 'sound' ? settings.effectsVolume : settings.musicVolume;

    for (final old in [0, 1, 2]) {
      for (final explicitEnabled in [null, false, true]) {
        test(
          '$channel schema 2 level $old / legacy $explicitEnabled',
          () async {
            SharedPreferences.setMockInitialValues({
              LunoSettings.storageKey: jsonEncode({field: old}),
              LunoSettings.storageVersionKey: 2,
              if (explicitEnabled != null) enabledKey: explicitEnabled,
            });
            final settings = LunoSettings();
            await settings.load();
            final expected = explicitEnabled == false ? 0 : old + 1;
            expect(level(settings), expected);
            expect(volume(settings), [0.0, .28, .55, .82][expected]);
            await settings.flush();
            final reloaded = LunoSettings();
            await reloaded.load();
            expect(level(reloaded), expected);
            expect(volume(reloaded), volume(settings));
            settings.dispose();
            reloaded.dispose();
          },
        );
      }
    }

    for (final enabled in [false, true]) {
      test('$channel boolean-only $enabled preserves intent', () async {
        SharedPreferences.setMockInitialValues({enabledKey: enabled});
        final settings = LunoSettings();
        await settings.load();
        expect(level(settings), enabled ? 3 : 0);
        expect(volume(settings), enabled ? .82 : 0);
        settings.dispose();
      });
    }

    for (var selected = 0; selected <= 3; selected++) {
      test(
        '$channel schema 3 level $selected survives a stale legacy mirror',
        () async {
          SharedPreferences.setMockInitialValues({
            LunoSettings.storageKey: jsonEncode({
              'schemaVersion': 3,
              field: selected,
            }),
            LunoSettings.storageVersionKey: 2,
            enabledKey: selected == 0,
            '${channel}_level': 2,
          });
          final settings = LunoSettings();
          await settings.load();
          expect(level(settings), selected);
          expect(volume(settings), [0.0, .28, .55, .82][selected]);
          final nextSession = LunoSettings();
          await nextSession.load();
          expect(level(nextSession), selected);
          settings.dispose();
          nextSession.dispose();
        },
      );
    }

    test(
      '$channel corrupt structured value does not override legacy mute',
      () async {
        SharedPreferences.setMockInitialValues({
          LunoSettings.storageKey: jsonEncode({
            'schemaVersion': 3,
            field: 'bad',
          }),
          enabledKey: false,
          '${channel}_level': 0,
        });
        final settings = LunoSettings();
        await settings.load();
        expect(level(settings), 0);
        expect(volume(settings), 0);
        settings.dispose();
      },
    );
  }

  test(
    'early OFF wins migration and untouched preferences survive restart',
    () async {
      SharedPreferences.setMockInitialValues({
        LunoSettings.storageVersionKey: 2,
        LunoSettings.storageKey: jsonEncode({
          'effectsLevel': 2,
          'musicLevel': 1,
          'language': LunoSettings.languageEnglish,
          'vibrationEnabled': false,
        }),
      });
      final settings = LunoSettings();
      final loading = settings.load();
      final muted = settings.setEffectsLevel(0);
      await Future.wait([loading, muted]);
      await settings.flush();
      expect(settings.effectsVolume, 0);
      expect(settings.musicVolume, .55);
      final nextAccountOnDevice = LunoSettings();
      await nextAccountOnDevice.load();
      expect(nextAccountOnDevice.effectsVolume, 0);
      expect(nextAccountOnDevice.musicVolume, .55);
      expect(nextAccountOnDevice.language, LunoSettings.languageEnglish);
      expect(nextAccountOnDevice.vibrationEnabled, false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(LunoSettings.storageVersionKey), 3);
      expect(
        jsonDecode(prefs.getString(LunoSettings.storageKey)!)['schemaVersion'],
        3,
      );
      settings.dispose();
      nextAccountOnDevice.dispose();
    },
  );
}
