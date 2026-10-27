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
  test(
    'real prepared audio obeys OFF, live volume, queued mute and scene release',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = LunoSettings.instance;
      settings.effectsLevel = 3;
      settings.musicLevel = 3;
      final calls = <MethodCall>[];
      Completer<void>? blocked, entered;
      String? holdPlayer;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final asset in ['menu_loop', 'battle_loop', 'spell_freeze']) {
        AudioCache.instance.loadedFiles['audio/$asset.wav'] =
            File('assets/audio/$asset.wav').absolute.uri;
      }
      for (final channel in [
        'xyz.luan/audioplayers.global/events',
        'xyz.luan/audioplayers.global',
        for (final id in [
          'luno_music',
          'luno_sfx_0',
          'luno_sfx_1',
          'luno_sfx_2',
        ])
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
          if (call.method == 'setVolume' && args?['playerId'] == holdPlayer) {
            holdPlayer = null;
            entered!.complete();
            await blocked!.future;
          }
          if (call.method == 'setSourceUrl') {
            scheduleMicrotask(() {
              // A real prepared signal ensures resume() is exercised; an absent
              // platform could otherwise make a mute test pass without playback.
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
          return call.method == 'getCurrentPosition' ? 0 : null;
        },
      );
      bool isMusic(MethodCall c, String method) =>
          c.method == method &&
          (c.arguments as Map?)?['playerId'] == 'luno_music';
      bool isEffect(MethodCall c, String method) =>
          c.method == method &&
          ((c.arguments as Map?)?['playerId'] as String? ?? '').startsWith(
            'luno_sfx_',
          );
      final audio = LunoAudioService.instance;
      audio.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await audio.setScene(LunoMusicScene.menu);
      await audio.playEffect(LunoSound.cardFreeze);
      expect(calls.where((c) => isMusic(c, 'resume')), isNotEmpty);
      expect(calls.where((c) => isEffect(c, 'resume')), isNotEmpty);

      for (final (level, volume) in [(1, .28), (2, .55), (3, .82)]) {
        calls.clear();
        await settings.setEffectsLevel(level);
        await settings.setMusicLevel(level);
        await audio.setScene(LunoMusicScene.menu);
        expect(calls.where((c) => isEffect(c, 'setVolume')), isNotEmpty);
        expect(
          calls
              .where((c) => isEffect(c, 'setVolume'))
              .map((c) => (c.arguments as Map)['volume']),
          everyElement(volume),
        );
        expect(calls.where((c) => isMusic(c, 'setVolume')), isNotEmpty);
        expect(
          (calls.lastWhere((c) => isMusic(c, 'setVolume')).arguments
              as Map)['volume'],
          volume,
        );
      }

      calls.clear();
      await settings.setEffectsLevel(0);
      await settings.setMusicLevel(0);
      await audio.setScene(LunoMusicScene.menu);
      expect(
        calls.where((c) => isEffect(c, 'stop')).length,
        greaterThanOrEqualTo(3),
      );
      expect(calls.where((c) => isMusic(c, 'stop')), isNotEmpty);
      calls.clear();
      await audio.playEffect(LunoSound.cardFreeze);
      audio.didChangeAppLifecycleState(AppLifecycleState.paused);
      audio.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await audio.setScene(LunoMusicScene.menu);
      expect(calls.where((c) => c.method == 'resume'), isEmpty);
      expect(settings.effectsVolume, 0);
      expect(settings.musicVolume, 0);

      await settings.setEffectsLevel(3);
      await settings.setMusicLevel(3);
      await audio.setScene(LunoMusicScene.menu);
      calls.clear();
      entered = Completer<void>();
      blocked = Completer<void>();
      holdPlayer = 'luno_music';
      final changing = audio.setScene(LunoMusicScene.battle);
      await entered.future;
      final queued = audio.playEffect(LunoSound.cardFreeze);
      await settings.setEffectsLevel(0);
      await settings.setMusicLevel(0);
      blocked.complete();
      await changing;
      await queued;
      await audio.setScene(LunoMusicScene.menu);
      expect(
        calls.where((c) => c.method == 'resume'),
        isEmpty,
        reason:
            'Mute during preparation must invalidate both queued SFX and BGM resume.',
      );

      await settings.setEffectsLevel(3);
      await settings.setMusicLevel(3);
      await audio.setScene(LunoMusicScene.menu);
      final owner = audio.holdScene(LunoMusicScene.battle);
      await audio.setScene(LunoMusicScene.menu);
      calls.clear();
      entered = Completer<void>();
      blocked = Completer<void>();
      holdPlayer = 'luno_music';
      final held = audio.setScene(LunoMusicScene.menu);
      await entered.future;
      final stale = audio.playEffect(LunoSound.cardFreeze);
      audio.releaseScene(owner);
      blocked.complete();
      await held;
      await stale;
      await audio.setScene(LunoMusicScene.menu);
      expect(
        calls.where((c) => isEffect(c, 'resume')),
        isEmpty,
        reason:
            'An effect queued by a departed battle scene cannot replay in the menu.',
      );
      await settings.setEffectsLevel(0);
      await settings.setMusicLevel(0);
      await audio.setScene(LunoMusicScene.menu);
    },
  );
}
