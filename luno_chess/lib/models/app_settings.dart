import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SettingsSaveFailure { storageUnavailable, writeRejected, writeFailed }

/// App-wide preferences used by native screens and future platform adapters.
///
/// The old build wrote individual keys directly from SettingsScreen. This
/// store keeps those keys readable, but serializes writes so a quick sequence
/// of taps cannot let an older async write overwrite the newest value.
class LunoSettings extends ChangeNotifier {
  LunoSettings({Locale? deviceLocale})
    : _deviceLanguage =
          (deviceLocale ?? PlatformDispatcher.instance.locale).languageCode ==
                  'tr'
              ? languageTurkish
              : languageEnglish {
    language = _deviceLanguage;
  }

  static final instance = LunoSettings();

  static const storageKey = 'luno_settings_v1';
  static const storageVersionKey = 'luno_settings_schema_v2';
  static const storageVersion = 3;
  static const languageTurkish = 'Türkçe';
  static const languageEnglish = 'English';
  static const supportedLanguages = <String>[languageTurkish, languageEnglish];

  int effectsLevel = 3;
  int musicLevel = 3;
  bool vibrationEnabled = true;
  late String language;
  final String _deviceLanguage;

  Future<void>? _loadFuture;
  Future<void> _saveQueue = Future<void>.value();
  final Set<String> _modifiedFields = {};
  bool _loaded = false;
  bool _needsRead = true;
  bool _hasSavedLanguage = false;
  bool _dirty = false;
  bool _saving = false;
  int _editRevision = 0;
  SettingsSaveFailure? _saveFailure;

  bool get loaded => _loaded;
  bool get dirty => _dirty;
  bool get saving => _saving;
  SettingsSaveFailure? get saveFailure => _saveFailure;
  String get languageCode => language == languageEnglish ? 'en' : 'tr';
  bool get soundEnabled => effectsVolume > 0;
  bool get musicEnabled => musicVolume > 0;
  double get effectsVolume => _volumeFor(effectsLevel);
  double get musicVolume => _volumeFor(musicLevel);

  Future<void> load() {
    return _loadFuture ??= _loadInternal();
  }

  Future<void> _loadInternal() async {
    final migration = await _readStoredValues();
    if (migration == true) {
      _dirty = true;
      await _write(_snapshot, _editRevision);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<bool?> _readStoredValues() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final values = _readValues(prefs);
      // Preserve early user choices without discarding untouched disk fields.
      if (!_modifiedFields.contains('effectsLevel')) {
        effectsLevel = values.effectsLevel;
      }
      if (!_modifiedFields.contains('musicLevel')) {
        musicLevel = values.musicLevel;
      }
      if (!_modifiedFields.contains('vibrationEnabled')) {
        vibrationEnabled = values.vibrationEnabled;
      }
      if (!_modifiedFields.contains('language')) language = values.language;
      _needsRead = false;
      // Old builds wrote individual legacy keys. Persist the normalized
      // structured snapshot once so future upgrades have one source of truth.
      return _hasStoredValues(prefs) &&
          _readInt(prefs, storageVersionKey) != storageVersion;
    } catch (_) {
      // Defaults keep SettingsScreen usable if the platform store is blocked.
      // A retry must read untouched preferences before writing any defaults.
      _needsRead = true;
      _dirty = true;
      _saveFailure = SettingsSaveFailure.storageUnavailable;
      return null;
    }
  }

  Future<void> setEffectsLevel(int value) {
    final next = _clampLevel(value);
    if (effectsLevel == next && _loaded && !_dirty) {
      return Future<void>.value();
    }
    effectsLevel = next;
    _markEdited('effectsLevel');
    return _enqueueSave();
  }

  Future<void> setMusicLevel(int value) {
    final next = _clampLevel(value);
    if (musicLevel == next && _loaded && !_dirty) {
      return Future<void>.value();
    }
    musicLevel = next;
    _markEdited('musicLevel');
    return _enqueueSave();
  }

  Future<void> setVibrationEnabled(bool value) {
    if (vibrationEnabled == value && _loaded && !_dirty) {
      return Future<void>.value();
    }
    vibrationEnabled = value;
    _markEdited('vibrationEnabled');
    return _enqueueSave();
  }

  Future<void> setLanguage(String value) {
    final next = supportedLanguages.contains(value) ? value : languageTurkish;
    if (language == next && _loaded && !_dirty && _hasSavedLanguage) {
      return Future<void>.value();
    }
    language = next;
    _markEdited('language');
    return _enqueueSave();
  }

  void _markEdited(String field) {
    _modifiedFields.add(field);
    _editRevision++;
    _dirty = true;
    notifyListeners();
  }

  _SettingsValues get _snapshot => _SettingsValues(
    effectsLevel: effectsLevel,
    musicLevel: musicLevel,
    vibrationEnabled: vibrationEnabled,
    language: language,
  );

  Future<void> _enqueueSave() {
    _saveQueue = _saveQueue
        .catchError((Object _) {})
        .then<void>((_) async {
          // Migration finishes before queued writes, so an old snapshot cannot win.
          await load();
          if (_needsRead && (await _readStoredValues()) == null) return;
          if (!_dirty) return;
          await _write(_snapshot, _editRevision);
        })
        .catchError((Object _) {
          _dirty = true;
          _saveFailure = SettingsSaveFailure.writeFailed;
          notifyListeners();
        });
    return _saveQueue;
  }

  Future<void> retrySave() => _dirty ? _enqueueSave() : _saveQueue;

  /// Lets the app lifecycle coordinator wait for the last preference write
  /// before Android suspends or tears down the Flutter process.
  Future<void> flush() async {
    await _saveQueue;
    if (_dirty) await _enqueueSave();
  }

  Future<void> _write(_SettingsValues values, int revision) async {
    var storageReady = false;
    _saving = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      storageReady = true;
      if (!await _writeValues(prefs, values)) {
        _saveFailure = SettingsSaveFailure.writeRejected;
        return;
      }
      if (revision == _editRevision) _dirty = false;
      _hasSavedLanguage = true;
      _saveFailure = null;
    } catch (_) {
      _saveFailure =
          storageReady
              ? SettingsSaveFailure.writeFailed
              : SettingsSaveFailure.storageUnavailable;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  Future<bool> _writeValues(
    SharedPreferences prefs,
    _SettingsValues values,
  ) async {
    // A rejected primary snapshot must not advance compatibility metadata.
    if (!await prefs.setString(storageKey, jsonEncode(values.toJson()))) {
      return false;
    }
    // Keep legacy keys for users upgrading from the HTML/native bridge.
    return await prefs.setInt(storageVersionKey, storageVersion) &&
        await prefs.setInt(
          'sound_level',
          (values.effectsLevel - 1).clamp(0, 2),
        ) &&
        await prefs.setInt(
          'music_level',
          (values.musicLevel - 1).clamp(0, 2),
        ) &&
        await prefs.setBool('sound_effects', values.effectsLevel > 0) &&
        await prefs.setBool('background_music', values.musicLevel > 0) &&
        await prefs.setBool('vibration', values.vibrationEnabled) &&
        await prefs.setString('language', values.language);
  }

  _SettingsValues _readValues(SharedPreferences prefs) {
    Map<String, dynamic>? stored;
    final raw = _readString(prefs, storageKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          stored = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        stored = null;
      }
    }

    final schema =
        stored?['schemaVersion'] ?? _readInt(prefs, storageVersionKey) ?? 0;
    final current = schema is int && schema >= storageVersion;
    int audioLevel(String field, String oldLevel, String oldEnabled) {
      final rawLevel = stored?[field];
      if (current && rawLevel is int) return _clampLevel(rawLevel);
      // Older booleans explicitly represent mute, even when an older build
      // also left a low-level integer behind. Never restore that as audible.
      if (_readBool(prefs, oldEnabled) == false) return 0;
      final legacy = rawLevel is int ? rawLevel : _readInt(prefs, oldLevel);
      return legacy == null ? 3 : legacy.clamp(0, 2) + 1;
    }

    final effects = audioLevel('effectsLevel', 'sound_level', 'sound_effects');
    final music = audioLevel('musicLevel', 'music_level', 'background_music');
    final vibration =
        stored?['vibrationEnabled'] ?? _readBool(prefs, 'vibration') ?? true;
    final storedLanguage = stored?['language'];
    final rawLanguage =
        supportedLanguages.contains(storedLanguage)
            ? storedLanguage
            : _readString(prefs, 'language');
    _hasSavedLanguage = supportedLanguages.contains(rawLanguage);

    return _SettingsValues(
      effectsLevel: effects,
      musicLevel: music,
      vibrationEnabled: vibration is bool ? vibration : true,
      language:
          supportedLanguages.contains(rawLanguage)
              ? rawLanguage as String
              : _deviceLanguage,
    );
  }

  static bool _hasStoredValues(SharedPreferences prefs) =>
      prefs.containsKey(storageKey) ||
      prefs.containsKey('sound_level') ||
      prefs.containsKey('music_level') ||
      prefs.containsKey('sound_effects') ||
      prefs.containsKey('background_music') ||
      prefs.containsKey('vibration') ||
      prefs.containsKey('language');

  static int _clampLevel(int value) => value.clamp(0, 3).toInt();

  static double _volumeFor(int value) =>
      const [0.0, 0.28, 0.55, 0.82][_clampLevel(value)];

  static int? _readInt(SharedPreferences prefs, String key) {
    try {
      return prefs.getInt(key);
    } catch (_) {
      return null;
    }
  }

  static bool? _readBool(SharedPreferences prefs, String key) {
    try {
      return prefs.getBool(key);
    } catch (_) {
      return null;
    }
  }

  static String? _readString(SharedPreferences prefs, String key) {
    try {
      return prefs.getString(key);
    } catch (_) {
      return null;
    }
  }
}

class _SettingsValues {
  final int effectsLevel;
  final int musicLevel;
  final bool vibrationEnabled;
  final String language;

  const _SettingsValues({
    required this.effectsLevel,
    required this.musicLevel,
    required this.vibrationEnabled,
    required this.language,
  });

  Map<String, Object> toJson() => {
    'schemaVersion': LunoSettings.storageVersion,
    'effectsLevel': effectsLevel,
    'musicLevel': musicLevel,
    'vibrationEnabled': vibrationEnabled,
    'language': language,
  };
}
