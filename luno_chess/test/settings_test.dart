import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('varsayılan ayarlar güvenli ve geçerli değerlerdir', () async {
    final settings = LunoSettings(deviceLocale: const Locale('tr'));
    await settings.load();

    expect(settings.effectsLevel, 3);
    expect(settings.musicLevel, 3);
    expect(settings.vibrationEnabled, isTrue);
    expect(settings.language, LunoSettings.languageTurkish);
    expect(settings.soundEnabled, isTrue);
    expect(settings.musicEnabled, isTrue);
    expect(settings.effectsVolume, closeTo(.82, .001));
    expect(settings.musicVolume, closeTo(.82, .001));
  });

  test('eski anahtarlar okunur ve bozuk değerler normalize edilir', () async {
    SharedPreferences.setMockInitialValues({
      'sound_level': 99,
      'music_level': -4,
      'vibration': 'bozuk',
      'language': 'Deutsch',
    });

    final settings = LunoSettings(deviceLocale: const Locale('tr'));
    await settings.load();

    expect(settings.effectsLevel, 3);
    expect(settings.musicLevel, 1);
    expect(settings.vibrationEnabled, isTrue);
    expect(settings.language, LunoSettings.languageTurkish);
    expect(settings.musicEnabled, isTrue);
    expect(settings.musicVolume, closeTo(.28, .001));
  });

  test('eski ayarlar güncellemede yeni şemaya taşınır', () async {
    SharedPreferences.setMockInitialValues({
      'sound_level': 0,
      'music_level': 1,
      'vibration': false,
      'language': LunoSettings.languageEnglish,
    });

    final settings = LunoSettings();
    await settings.load();
    final prefs = await SharedPreferences.getInstance();

    expect(settings.effectsLevel, 1);
    expect(settings.musicLevel, 2);
    expect(settings.vibrationEnabled, isFalse);
    expect(settings.language, LunoSettings.languageEnglish);
    expect(prefs.getInt(LunoSettings.storageVersionKey), 3);
    expect(prefs.getString(LunoSettings.storageKey), isNotNull);
  });

  test(
    'ayarlar kalıcıdır ve hızlı değişikliklerde son değer kazanır',
    () async {
      final settings = LunoSettings();
      await settings.load();

      await Future.wait([
        settings.setEffectsLevel(0),
        settings.setEffectsLevel(1),
        settings.setEffectsLevel(2),
        settings.setMusicLevel(1),
        settings.setVibrationEnabled(false),
        settings.setLanguage(LunoSettings.languageEnglish),
      ]);

      final reloaded = LunoSettings();
      await reloaded.load();
      expect(reloaded.effectsLevel, 2);
      expect(reloaded.musicLevel, 1);
      expect(reloaded.vibrationEnabled, isFalse);
      expect(reloaded.language, LunoSettings.languageEnglish);
    },
  );

  test(
    'açılış yüklemesi sürerken yapılan kullanıcı değişikliği ezilmez',
    () async {
      final settings = LunoSettings();
      final loading = settings.load();
      final change = settings.setEffectsLevel(0);

      await Future.wait([loading, change]);
      expect(settings.effectsLevel, 0);

      final reloaded = LunoSettings();
      await reloaded.load();
      expect(reloaded.effectsLevel, 0);
    },
  );

  test('dil kodu ve metinler Türkçe/İngilizce arasında tutarlıdır', () async {
    final settings = LunoSettings(deviceLocale: const Locale('tr'));
    await settings.load();

    expect(settings.languageCode, 'tr');
    expect(const LunoLocalizations(Locale('tr')).settingsTitle, 'AYARLAR');
    expect(const LunoLocalizations(Locale('en')).settingsTitle, 'SETTINGS');
    expect(const LunoLocalizations(Locale('en')).low, 'LOW');

    await settings.setLanguage(LunoSettings.languageEnglish);
    expect(settings.languageCode, 'en');
  });

  test('iki dil de okunakli Nunito ve Turkce fallback kullanir', () {
    expect(LunoTheme.darkFor('en').textTheme.bodyMedium?.fontFamily, 'Nunito');
    expect(
      LunoTheme.darkFor(
        LunoSettings.languageTurkish,
      ).textTheme.bodyMedium?.fontFamily,
      'Nunito',
    );
    expect(
      LunoTheme.darkFor('en').textTheme.bodyMedium?.fontFamilyFallback,
      contains('SpectralTurkish'),
    );
  });

  testWidgets('ayar ekranı dili seçimle anında güncellenir', (tester) async {
    final settings = LunoSettings.instance;
    await settings.setLanguage(LunoSettings.languageTurkish);

    await tester.pumpWidget(
      ListenableBuilder(
        listenable: settings,
        builder:
            (context, _) => MaterialApp(
              locale: Locale(settings.languageCode),
              supportedLocales: LunoLocalizations.supportedLocales,
              localizationsDelegates: const [
                LunoLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: LunoTheme.darkFor(settings.language),
              home: const SettingsScreen(),
            ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AYARLAR'), findsOneWidget);
    expect(find.text('SES VE GÖRÜNTÜ'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();

    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.text('SOUND & DISPLAY'), findsOneWidget);
    expect(find.text('MEDIUM'), findsNWidgets(2));

    await settings.setLanguage(LunoSettings.languageTurkish);
  });
}
