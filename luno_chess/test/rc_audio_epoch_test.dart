import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/services/luno_audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('queued pre-background SFX cannot replay after rapid resume', () async {
    SharedPreferences.setMockInitialValues({});
    LunoSettings.instance.effectsLevel = 2;
    LunoSettings.instance.musicLevel = 2;
    final calls = <MethodCall>[];
    final blocked = Completer<void>();
    final entered = Completer<void>();
    var holdMusic = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final asset in ['menu_loop', 'battle_loop', 'spell_freeze']) {
      AudioCache.instance.loadedFiles['audio/$asset.wav'] =
          File('assets/audio/$asset.wav').absolute.uri;
    }
    for (final channel in [
      'xyz.luan/audioplayers.global/events',
      'xyz.luan/audioplayers.global',
      for (final id in ['luno_music', 'luno_sfx_0', 'luno_sfx_1', 'luno_sfx_2'])
        'xyz.luan/audioplayers/events/$id',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (_) async => null,
      );
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async {
        calls.add(call);
        final args = call.arguments as Map?;
        if (holdMusic &&
            call.method == 'setVolume' &&
            args?['playerId'] == 'luno_music') {
          holdMusic = false;
          entered.complete();
          await blocked.future;
        }
        if (call.method == 'setSourceUrl') {
          // A functioning platform reports prepared; a missing plugin would make
          // this test falsely pass because play() never reaches resume().
          scheduleMicrotask(() {
            // ignore: deprecated_member_use
            messenger.handlePlatformMessage(
              'xyz.luan/audioplayers/events/${args?['playerId']}',
              const StandardMethodCodec().encodeSuccessEnvelope({
                'event': 'audio.onPrepared',
                'value': true,
              }),
              (_) {},
            );
          });
        }
        if (call.method == 'getCurrentPosition') return 0;
        return null;
      },
    );
    final audio = LunoAudioService.instance;
    audio.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await audio.setScene(LunoMusicScene.menu);
    await audio.playEffect(LunoSound.cardFreeze);
    expect(
      calls.any(
        (call) =>
            call.method == 'resume' &&
            (call.arguments as Map)['playerId'].toString().startsWith(
              'luno_sfx_',
            ),
      ),
      true,
      reason: calls
          .map((call) => '${call.method}:${call.arguments}')
          .join('\n'),
    );
    calls.clear();
    holdMusic = true;
    final music = audio.setScene(LunoMusicScene.battle);
    await entered.future;
    final effect = audio.playEffect(LunoSound.cardFreeze);
    await Future<void>.delayed(Duration.zero);
    audio.didChangeAppLifecycleState(AppLifecycleState.paused);
    audio.didChangeAppLifecycleState(AppLifecycleState.resumed);
    blocked.complete();
    await music;
    await effect;
    await audio.setScene(LunoMusicScene.menu);
    expect(
      calls.where((call) {
        final args = call.arguments as Map?;
        return call.method == 'resume' &&
            (args?['playerId'] as String? ?? '').startsWith('luno_sfx_');
      }),
      isEmpty,
    );
  });
}
