import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:luno_chess/services/luno_audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('ses servisi platform desteği yokken akışı bozmaz', () async {
    await expectLater(
      LunoAudioService.instance.setScene(LunoMusicScene.menu),
      completes,
    );
    await expectLater(
      LunoAudioService.instance.playEffect(LunoSound.uiClick),
      completes,
    );
  });

  test(
    'background scene changes and resume complete without platform support',
    () async {
      final audio = LunoAudioService.instance;
      await audio.setScene(LunoMusicScene.menu);
      audio.didChangeAppLifecycleState(AppLifecycleState.paused);
      await audio.setScene(LunoMusicScene.battle);
      await expectLater(audio.playEffect(LunoSound.capture), completes);
      audio.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await expectLater(audio.setScene(LunoMusicScene.menu), completes);
    },
  );
}
