import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Existing transitive test transport; do not add or upgrade dependencies.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'battle_deck_account_test.dart' show app;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'online_request_session_test.dart' show TestAuth;
import 'v217_player_journey_support.dart' show journeyAwait, journeyPump;

Map<String, Object> _values(String language) => {
  'schemaVersion': LunoSettings.storageVersion,
  'effectsLevel': 1,
  'musicLevel': 0,
  'vibrationEnabled': false,
  'language': language,
};

class _PreferenceStore extends InMemorySharedPreferencesStore {
  _PreferenceStore(Map<String, Object> values)
    : super.withData({
        for (final entry in values.entries) 'flutter.${entry.key}': entry.value,
      });

  String? rejectedKey;
  bool throwOnRejectedKey = false;
  bool failReads = false;
  Completer<void>? writeEntered;
  Completer<void>? writeGate;
  final List<String> writes = [];

  @override
  Future<Map<String, Object>> getAll() async {
    if (failReads) throw StateError('Test read failure');
    return super.getAll();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writes.add(key);
    if (key == 'flutter.${LunoSettings.storageKey}' && writeGate != null) {
      final gate = writeGate!;
      writeGate = null;
      writeEntered?.complete();
      await gate.future;
    }
    if (key == rejectedKey) {
      if (throwOnRejectedKey) throw StateError('Test write failure');
      return false;
    }
    return super.setValue(valueType, key, value);
  }

  Future<String> persistedLanguage() async {
    final values = await getAll();
    return (jsonDecode(values['flutter.${LunoSettings.storageKey}']! as String)
            as Map)['language']
        as String;
  }
}

void main() {
  setupPracticeTestAssets();
  late SharedPreferencesStorePlatform previousStore;

  setUp(() {
    previousStore = SharedPreferencesStorePlatform.instance;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previousStore;
  });

  for (final (locale, expected) in [
    (const Locale('tr'), 'tr'),
    (const Locale('tr', 'TR'), 'tr'),
    (const Locale('en', 'US'), 'en'),
    (const Locale('de', 'DE'), 'en'),
    (const Locale('ar'), 'en'),
    (const Locale('und'), 'en'),
  ]) {
    test('fresh settings use the explicit device language $locale', () async {
      final settings = LunoSettings(deviceLocale: locale);
      addTearDown(settings.dispose);
      expect(settings.languageCode, expected);
      await settings.load();
      expect(settings.languageCode, expected);
      expect(settings.effectsLevel, 3);
      expect(settings.musicLevel, 3);
      expect(settings.vibrationEnabled, isTrue);
      expect(settings.dirty, isFalse);
      expect(settings.saveFailure, isNull);
    });
  }

  for (final (locale, language) in [
    (const Locale('tr'), LunoSettings.languageTurkish),
    (const Locale('en'), LunoSettings.languageEnglish),
  ]) {
    test(
      'explicit choice matching the fresh device default is saved: $language',
      () async {
        final settings = LunoSettings(deviceLocale: locale);
        addTearDown(settings.dispose);
        await settings.load();
        await settings.setLanguage(language);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('language'), language);
        final opposite =
            locale.languageCode == 'tr'
                ? const Locale('en')
                : const Locale('tr');
        final restored = LunoSettings(deviceLocale: opposite);
        addTearDown(restored.dispose);
        await restored.load();
        expect(restored.language, language);
        expect(settings.dirty, isFalse);
      },
    );
  }

  for (final structured in [false, true]) {
    for (final language in LunoSettings.supportedLanguages) {
      test('saved $language beats the opposite injected device locale: '
          '$structured', () async {
        SharedPreferences.setMockInitialValues(
          structured
              ? {
                LunoSettings.storageKey: jsonEncode(_values(language)),
                LunoSettings.storageVersionKey: LunoSettings.storageVersion,
              }
              : {'language': language},
        );
        final locale =
            language == LunoSettings.languageTurkish
                ? const Locale('en')
                : const Locale('tr');
        final settings = LunoSettings(deviceLocale: locale);
        addTearDown(settings.dispose);
        await settings.load();
        expect(settings.language, language);
        expect(settings.dirty, isFalse);
      });
    }
  }

  test(
    'missing or invalid stored language uses the device, not a TR fixture',
    () async {
      for (final stored in [
        <String, Object>{},
        <String, Object>{'music_level': 1},
        <String, Object>{'language': 'Deutsch'},
        <String, Object>{LunoSettings.storageKey: '{invalid JSON'},
      ]) {
        SharedPreferences.setMockInitialValues(stored);
        final settings = LunoSettings(deviceLocale: const Locale('de'));
        await settings.load();
        expect(settings.language, LunoSettings.languageEnglish);
        settings.dispose();
      }
    },
  );

  test('early explicit TR selection beats saved EN and injected EN', () async {
    SharedPreferences.setMockInitialValues({
      LunoSettings.storageKey: jsonEncode(
        _values(LunoSettings.languageEnglish),
      ),
      LunoSettings.storageVersionKey: LunoSettings.storageVersion,
    });
    final settings = LunoSettings(deviceLocale: const Locale('en'));
    addTearDown(settings.dispose);
    await Future.wait([
      settings.load(),
      settings.setLanguage(LunoSettings.languageTurkish),
    ]);
    await settings.flush();
    expect(settings.language, LunoSettings.languageTurkish);
    expect(settings.musicLevel, 0);
    expect(settings.vibrationEnabled, isFalse);
    expect(settings.dirty, isFalse);
  });

  test(
    'invalid structured language preserves a valid legacy manual choice',
    () async {
      SharedPreferences.setMockInitialValues({
        LunoSettings.storageKey: jsonEncode({
          ..._values(LunoSettings.languageTurkish),
          'language': 'invalid',
        }),
        LunoSettings.storageVersionKey: LunoSettings.storageVersion,
        'language': LunoSettings.languageTurkish,
      });
      final settings = LunoSettings(deviceLocale: const Locale('en'));
      addTearDown(settings.dispose);
      await settings.load();
      expect(settings.language, LunoSettings.languageTurkish);
    },
  );

  for (final throwFailure in [false, true]) {
    for (final retry in ['same-value', 'explicit', 'flush']) {
      test(
        'write failure $throwFailure is observable and $retry retry recovers',
        () async {
          final backend =
              _PreferenceStore({
                  LunoSettings.storageKey: jsonEncode(
                    _values(LunoSettings.languageTurkish),
                  ),
                  LunoSettings.storageVersionKey: LunoSettings.storageVersion,
                })
                ..rejectedKey = 'flutter.${LunoSettings.storageKey}'
                ..throwOnRejectedKey = throwFailure;
          SharedPreferences.resetStatic();
          SharedPreferencesStorePlatform.instance = backend;
          final settings = LunoSettings(deviceLocale: const Locale('tr'));
          addTearDown(settings.dispose);
          await settings.load();

          // Real callers intentionally do not await these setters.
          unawaited(settings.setLanguage(LunoSettings.languageEnglish));
          await settings.flush();
          expect(settings.language, LunoSettings.languageEnglish);
          expect(settings.dirty, isTrue);
          expect(
            settings.saveFailure,
            throwFailure
                ? SettingsSaveFailure.writeFailed
                : SettingsSaveFailure.writeRejected,
          );
          expect(
            await backend.persistedLanguage(),
            LunoSettings.languageTurkish,
          );
          expect(backend.writes.toSet(), {
            'flutter.${LunoSettings.storageKey}',
          });
          final attempts = backend.writes.length;

          backend.rejectedKey = null;
          switch (retry) {
            case 'same-value':
              await settings.setLanguage(LunoSettings.languageEnglish);
            case 'explicit':
              await settings.retrySave();
            case 'flush':
              await settings.flush();
          }
          expect(backend.writes.length, greaterThan(attempts));
          expect(settings.dirty, isFalse);
          expect(settings.saveFailure, isNull);
          expect(
            await backend.persistedLanguage(),
            LunoSettings.languageEnglish,
          );

          await settings.setLanguage(LunoSettings.languageTurkish);
          expect(
            await backend.persistedLanguage(),
            LunoSettings.languageTurkish,
          );
          expect(settings.dirty, isFalse);
        },
      );
    }
  }

  for (final key in [
    LunoSettings.storageVersionKey,
    'sound_level',
    'music_level',
    'sound_effects',
    'background_music',
    'vibration',
    'language',
  ]) {
    test(
      'rejected compatibility write $key remains dirty until retry',
      () async {
        final backend = _PreferenceStore({
          LunoSettings.storageKey: jsonEncode(
            _values(LunoSettings.languageTurkish),
          ),
          LunoSettings.storageVersionKey: LunoSettings.storageVersion,
        })..rejectedKey = 'flutter.$key';
        SharedPreferences.resetStatic();
        SharedPreferencesStorePlatform.instance = backend;
        final settings = LunoSettings(deviceLocale: const Locale('tr'));
        addTearDown(settings.dispose);
        await settings.load();
        await settings.setLanguage(LunoSettings.languageEnglish);
        expect(settings.dirty, isTrue);
        expect(settings.saveFailure, SettingsSaveFailure.writeRejected);
        backend.rejectedKey = null;
        await settings.retrySave();
        expect(settings.dirty, isFalse);
        expect(settings.saveFailure, isNull);
      },
    );
  }

  test(
    'failed migration stays observable and retry preserves the old choice',
    () async {
      final backend = _PreferenceStore({
        'language': LunoSettings.languageTurkish,
        'sound_effects': false,
      })..rejectedKey = 'flutter.${LunoSettings.storageKey}';
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = backend;
      final settings = LunoSettings(deviceLocale: const Locale('en'));
      addTearDown(settings.dispose);
      await settings.load();
      expect(settings.language, LunoSettings.languageTurkish);
      expect(settings.effectsLevel, 0);
      expect(settings.dirty, isTrue);
      expect(settings.saveFailure, SettingsSaveFailure.writeRejected);
      backend.rejectedKey = null;
      await settings.retrySave();
      expect(settings.dirty, isFalse);
      expect(await backend.persistedLanguage(), LunoSettings.languageTurkish);
    },
  );

  test('storage-read retry merges untouched choices before writing', () async {
    final backend = _PreferenceStore({
      LunoSettings.storageKey: jsonEncode(
        _values(LunoSettings.languageEnglish),
      ),
      LunoSettings.storageVersionKey: LunoSettings.storageVersion,
    })..failReads = true;
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = backend;
    final settings = LunoSettings(deviceLocale: const Locale('tr'));
    addTearDown(settings.dispose);
    await settings.load();
    expect(settings.loaded, isTrue);
    expect(settings.saveFailure, SettingsSaveFailure.storageUnavailable);
    await settings.setEffectsLevel(2);
    expect(backend.writes, isEmpty);
    backend.failReads = false;
    await settings.retrySave();
    expect(settings.language, LunoSettings.languageEnglish);
    expect(settings.effectsLevel, 2);
    expect(settings.musicLevel, 0);
    expect(settings.vibrationEnabled, isFalse);
    expect(settings.dirty, isFalse);
    expect(settings.saveFailure, isNull);
  });

  test('an older successful write cannot clear a newer dirty edit', () async {
    final gate = Completer<void>();
    final entered = Completer<void>();
    final backend =
        _PreferenceStore({
            LunoSettings.storageKey: jsonEncode(
              _values(LunoSettings.languageTurkish),
            ),
            LunoSettings.storageVersionKey: LunoSettings.storageVersion,
          })
          ..writeGate = gate
          ..writeEntered = entered;
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = backend;
    final settings = LunoSettings(deviceLocale: const Locale('tr'));
    addTearDown(settings.dispose);
    await settings.load();
    final dirtyAtCompletion = <bool>[];
    settings.addListener(() {
      if (!settings.saving) dirtyAtCompletion.add(settings.dirty);
    });
    final first = settings.setLanguage(LunoSettings.languageEnglish);
    await entered.future;
    final second = settings.setLanguage(LunoSettings.languageTurkish);
    gate.complete();
    await Future.wait([first, second]);
    expect(dirtyAtCompletion, [true, true, false]);
    expect(settings.dirty, isFalse);
    expect(await backend.persistedLanguage(), LunoSettings.languageTurkish);
  });

  test(
    'unawaited setters and flush keep failure recovery non-throwing',
    () async {
      final backend =
          _PreferenceStore({
              LunoSettings.storageKey: jsonEncode(
                _values(LunoSettings.languageTurkish),
              ),
              LunoSettings.storageVersionKey: LunoSettings.storageVersion,
            })
            ..rejectedKey = 'flutter.${LunoSettings.storageKey}'
            ..throwOnRejectedKey = true;
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = backend;
      final settings = LunoSettings(deviceLocale: const Locale('tr'));
      addTearDown(settings.dispose);
      await settings.load();
      final uncaught = <Object>[];
      final finished = Completer<void>();
      runZonedGuarded(() async {
        unawaited(settings.setEffectsLevel(0));
        unawaited(settings.setMusicLevel(1));
        unawaited(settings.setVibrationEnabled(true));
        unawaited(settings.setLanguage(LunoSettings.languageEnglish));
        unawaited(settings.flush());
        await settings.flush();
        finished.complete();
      }, (error, _) => uncaught.add(error));
      await finished.future;
      expect(uncaught, isEmpty);
      expect(settings.saveFailure, SettingsSaveFailure.writeFailed);
      backend.rejectedKey = null;
      await settings.setLanguage(LunoSettings.languageEnglish);
      expect(settings.dirty, isFalse);
      expect(settings.effectsLevel, 0);
      expect(settings.musicLevel, 1);
      expect(settings.vibrationEnabled, isTrue);
    },
  );

  for (final language in LunoSettings.supportedLanguages) {
    testWidgets('SettingsScreen shows and retries a failed save: $language', (
      tester,
    ) async {
      final backend = _PreferenceStore({
        LunoSettings.storageKey: jsonEncode(_values(language)),
        LunoSettings.storageVersionKey: LunoSettings.storageVersion,
      })..rejectedKey = 'flutter.${LunoSettings.storageKey}';
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = backend;
      final settings = LunoSettings(deviceLocale: const Locale('tr'));
      addTearDown(settings.dispose);
      await journeyAwait(tester, () async {
        await settings.load();
        await settings.setEffectsLevel(2);
      });
      final online = LunoOnlineService.forTesting(
        auth: TestAuth()..currentUser = null,
        bootstrap: () async {},
      );
      addTearDown(online.dispose);
      await tester.pumpWidget(
        app(
          SettingsScreen(settings: settings, online: online),
          settings.languageCode,
        ),
      );
      await journeyPump(tester);
      final failure = find.byKey(const ValueKey('settings-save-failure'));
      final retry = find.byKey(const ValueKey('settings-save-retry'));
      await tester.ensureVisible(retry);
      expect(failure, findsOneWidget);
      expect(
        find.text(
          language == LunoSettings.languageEnglish
              ? 'Settings are not saved on this device.'
              : 'Ayarlar bu cihazda kaydedilemedi.',
        ),
        findsOneWidget,
      );
      backend.rejectedKey = null;
      await tester.tap(retry);
      await journeyPump(tester);
      expect(failure, findsNothing);
      expect(settings.dirty, isFalse);
      expect(settings.language, language);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
