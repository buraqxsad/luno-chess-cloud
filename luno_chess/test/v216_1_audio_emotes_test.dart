import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/services/cosmetic_catalog.dart';
import 'package:luno_chess/services/luno_audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  final settings = LunoSettings.instance;
  late LunoAudioService audio;
  Completer<void>? entered, hold;
  String? holdMethod;
  List<MethodCall> resumes() =>
      calls.where((c) => c.method == 'resume').toList();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    for (final sound in LunoSound.values) {
      final asset = LunoAudioService.assetForSound(sound);
      AudioCache.instance.loadedFiles[asset] =
          File('assets/$asset').absolute.uri;
    }
    for (final channel in [
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
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
        if (call.method == holdMethod && !(entered?.isCompleted ?? true)) {
          entered!.complete();
          await hold!.future;
        }
        if (call.method == 'setSourceUrl') {
          final args = call.arguments as Map;
          scheduleMicrotask(() {
            // ignore: deprecated_member_use
            messenger.handlePlatformMessage(
              'xyz.luan/audioplayers/events/${args['playerId']}',
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
    audio = LunoAudioService.instance;
    await audio.initialize();
  });
  setUp(() async {
    holdMethod = null;
    entered = null;
    hold = null;
    await settings.setEffectsLevel(3);
    await settings.setMusicLevel(0);
    audio.didChangeAppLifecycleState(AppLifecycleState.resumed);
    audio.cancelEffects();
    await audio.setScene(LunoMusicScene.menu);
    calls.clear();
  });
  tearDown(() async {
    hold?.complete();
    hold = null;
    holdMethod = null;
    await settings.setEffectsLevel(0);
    await audio.setScene(LunoMusicScene.menu);
  });

  test('append-only enum and fourteen unique, known-only emote assets', () {
    expect(LunoSound.cardBoardSeal.index, 39);
    expect(LunoSound.costumeEquip.index, 47);
    expect(LunoSound.emoteSmile.index, 48);
    final sounds =
        cosmeticEmotes.map((e) => LunoAudioService.soundForEmote(e.id)).toSet();
    expect(sounds.length, 14);
    expect(sounds, isNot(contains(null)));
    expect(LunoAudioService.soundForEmote('private-card-id'), isNull);
    expect(
      sounds.map((s) => LunoAudioService.assetForSound(s!)).toSet().length,
      14,
    );
    for (final sound in LunoSound.values) {
      final bytes =
          File(
            'assets/${LunoAudioService.assetForSound(sound)}',
          ).readAsBytesSync();
      final data = ByteData.sublistView(bytes);
      final duration =
          (bytes.length - 44) / data.getUint32(28, Endian.little) * 1000;
      expect(
        LunoAudioService.policyForSound(sound).durationMs,
        closeTo(duration, 1.1),
        reason: sound.name,
      );
    }
  });

  test('different emotes share a three second family debounce', () async {
    await audio.playEmote('smile');
    await audio.playEmote('rainbow');
    await audio.playEffect(LunoSound.emoteHeart);
    expect(resumes().length, 1);
    expect(
      LunoAudioService.policyForSound(LunoSound.emoteRainbow).debounceMs,
      3000,
    );
    expect(LunoAudioService.policyForSound(LunoSound.emoteRainbow).priority, 1);
  });

  test(
    'unknown, channel muted, stale or throwing owner cannot prepare audio',
    () async {
      await audio.playEmote('unknown');
      await audio.playEmote('smile', muted: true);
      await audio.playEmote('heart', isCurrent: () => false);
      await audio.playEmote(
        'laugh',
        isCurrent: () => throw StateError('old owner'),
      );
      expect(resumes(), isEmpty);
      expect(calls.where((c) => c.method == 'setSourceUrl'), isEmpty);
    },
  );

  for (final cancellation in [
    'owner',
    'emoteMute',
    'globalMute',
    'lifecycle',
    'surface',
  ]) {
    test(
      '$cancellation invalidates an emote during native preparation',
      () async {
        entered = Completer<void>();
        hold = Completer<void>();
        holdMethod = 'setVolume';
        var current = true;
        final future = audio.playEmote('crown', isCurrent: () => current);
        await entered!.future;
        switch (cancellation) {
          case 'owner':
            current = false;
          case 'emoteMute':
            audio.cancelEmotes();
          case 'globalMute':
            await settings.setEffectsLevel(0);
          case 'lifecycle':
            audio.didChangeAppLifecycleState(AppLifecycleState.paused);
          case 'surface':
            audio.cancelEffects();
        }
        hold!.complete();
        hold = null;
        await future;
        await audio.setScene(LunoMusicScene.menu);
        expect(resumes(), isEmpty);
      },
    );
  }

  test(
    'channel mute stops only emote voice, keeps important battle voice and music lease',
    () async {
      final lease = audio.holdScene(LunoMusicScene.battle);
      await audio.setScene(LunoMusicScene.menu);
      await audio.playEffect(LunoSound.cardFreeze);
      final spellPlayer = (resumes().last.arguments as Map)['playerId'];
      await audio.playEmote('star');
      final emotePlayer = (resumes().last.arguments as Map)['playerId'];
      expect(emotePlayer, isNot(spellPlayer));
      calls.clear();
      audio.cancelEmotes();
      await audio.setScene(LunoMusicScene.menu);
      final stops = calls
          .where((c) => c.method == 'stop')
          .map((c) => (c.arguments as Map)['playerId']);
      expect(stops, contains(emotePlayer));
      expect(stops, isNot(contains(spellPlayer)));
      expect(stops, isNot(contains('luno_music')));
      expect(audio.effectiveScene, LunoMusicScene.battle);
      audio.releaseScene(lease);
    },
  );

  test('emotes cannot evict three important gameplay voices', () async {
    for (final sound in [
      LunoSound.cardFreeze,
      LunoSound.cardBoardSeal,
      LunoSound.check,
    ]) {
      await audio.playEffect(sound);
    }
    calls.clear();
    await audio.playEmote('thunder');
    expect(resumes(), isEmpty);
    expect(calls.where((c) => c.method == 'stop'), isEmpty);
  });

  test('OFF then ON and background requests remain silent', () async {
    await settings.setEffectsLevel(0);
    final future = audio.playEmote('smile');
    await settings.setEffectsLevel(3);
    await future;
    audio.didChangeAppLifecycleState(AppLifecycleState.paused);
    await audio.playEmote('heart');
    audio.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await audio.setScene(LunoMusicScene.menu);
    expect(resumes(), isEmpty);
  });
}
