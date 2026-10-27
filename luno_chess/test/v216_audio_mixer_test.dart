import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/services/luno_audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  final settings = LunoSettings.instance;
  late LunoAudioService audio;
  Completer<void>? entered, blocked;
  String? holdMethod;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  List<MethodCall> resumes() =>
      calls
          .where(
            (call) =>
                call.method == 'resume' &&
                ((call.arguments as Map?)?['playerId'] as String? ?? '')
                    .startsWith('luno_sfx_'),
          )
          .toList();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    for (final sound in LunoSound.values) {
      final asset = LunoAudioService.assetForSound(sound);
      AudioCache.instance.loadedFiles[asset] =
          File('assets/$asset').absolute.uri;
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
        if (call.method == holdMethod && args?['playerId'] != 'luno_music') {
          holdMethod = null;
          entered!.complete();
          await blocked!.future;
        }
        if (call.method == 'setSourceUrl') {
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
        return call.method == 'getCurrentPosition' ? 0 : null;
      },
    );
    audio = LunoAudioService.instance;
    await audio.initialize();
  });
  setUp(() async {
    holdMethod = null;
    await settings.setEffectsLevel(3);
    await settings.setMusicLevel(0);
    audio.didChangeAppLifecycleState(AppLifecycleState.paused);
    audio.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await audio.setScene(LunoMusicScene.menu);
    calls.clear();
  });
  tearDown(() async {
    await settings.setEffectsLevel(0);
    await audio.setScene(LunoMusicScene.menu);
  });

  test(
    'all semantic cue budgets match actual PCM length and packaged assets',
    () {
      expect(LunoSound.move.index, 1);
      expect(LunoSound.cardRadar.index, 16);
      expect(LunoSound.cardBoardSeal.index, 39);
      for (final sound in LunoSound.values) {
        final bytes =
            File(
              'assets/${LunoAudioService.assetForSound(sound)}',
            ).readAsBytesSync();
        final data = ByteData.sublistView(bytes);
        final duration =
            (bytes.length - 44) / data.getUint32(28, Endian.little) * 1000;
        final policy = LunoAudioService.policyForSound(sound);
        expect(policy.durationMs, closeTo(duration, 1), reason: sound.name);
        expect(policy.debounceMs, greaterThan(0));
        expect(policy.maxAgeMs, inInclusiveRange(200, 800));
      }
    },
  );

  test('three active important layers reject low priority taps', () async {
    for (final sound in [
      LunoSound.cardFreeze,
      LunoSound.cardRadar,
      LunoSound.check,
    ]) {
      await audio.playEffect(sound);
    }
    expect(resumes().length, 3);
    calls.clear();
    await audio.playEffect(LunoSound.uiClick);
    await audio.playEffect(LunoSound.move);
    expect(resumes(), isEmpty);
    expect(calls.where((c) => c.method == 'stop'), isEmpty);
  });

  test(
    'result preempts the lowest priority layer without adding players',
    () async {
      for (final sound in [
        LunoSound.cardCast,
        LunoSound.cardRadar,
        LunoSound.check,
      ]) {
        await audio.playEffect(sound);
      }
      final existing =
          resumes().map((c) => (c.arguments as Map)['playerId']).toSet();
      calls.clear();
      await audio.playEffect(LunoSound.victory);
      expect(resumes().length, 1);
      expect(
        existing,
        contains((resumes().single.arguments as Map)['playerId']),
      );
      expect(calls.where((c) => c.method == 'create'), isEmpty);
    },
  );

  test('same cue and selection aliases are debounced', () async {
    await audio.playEffect(LunoSound.pieceSelect);
    await audio.playEffect(LunoSound.cardSelect);
    await audio.playEffect(LunoSound.uiClick);
    expect(resumes().length, 1);
    await audio.playEffect(LunoSound.cardFreeze);
    await audio.playEffect(LunoSound.cardFreeze);
    expect(resumes().length, 2);
  });

  test('OFF request cannot become audible after immediate ON', () async {
    await settings.setEffectsLevel(0);
    final effect = audio.playEffect(LunoSound.cardFreeze);
    await settings.setEffectsLevel(3);
    await effect;
    await audio.setScene(LunoMusicScene.menu);
    expect(resumes(), isEmpty);
  });

  test('rapid OFF then ON still stops already playing effects', () async {
    await audio.playEffect(LunoSound.cardFreeze);
    calls.clear();
    final muted = settings.setEffectsLevel(0);
    final unmuted = settings.setEffectsLevel(3);
    await muted;
    await unmuted;
    await audio.setScene(LunoMusicScene.menu);
    expect(
      calls
          .where(
            (c) =>
                c.method == 'stop' &&
                ((c.arguments as Map?)?['playerId'] as String? ?? '')
                    .startsWith('luno_sfx_'),
          )
          .length,
      greaterThanOrEqualTo(3),
    );
  });

  test(
    'a slow native preparation drops expired effects instead of replaying late',
    () async {
      entered = Completer<void>();
      blocked = Completer<void>();
      holdMethod = 'setVolume';
      final effect = audio.playEffect(LunoSound.cardFreeze);
      await entered!.future;
      await Future<void>.delayed(const Duration(milliseconds: 290));
      blocked!.complete();
      await effect;
      expect(resumes(), isEmpty);
    },
  );

  test(
    'mute while native resume is in flight stops that just-started player',
    () async {
      entered = Completer<void>();
      blocked = Completer<void>();
      holdMethod = 'resume';
      final effect = audio.playEffect(LunoSound.cardFreeze);
      await entered!.future;
      await settings.setEffectsLevel(0);
      final resume = calls.lastIndexWhere((call) => call.method == 'resume');
      final id = (calls[resume].arguments as Map)['playerId'];
      blocked!.complete();
      await effect;
      await audio.setScene(LunoMusicScene.menu);
      expect(
        calls
            .skip(resume + 1)
            .any(
              (call) =>
                  call.method == 'stop' &&
                  (call.arguments as Map?)?['playerId'] == id,
            ),
        isTrue,
      );
    },
  );

  test(
    'hidden feedback cancellation invalidates prepared SFX, not music lease',
    () async {
      final owner = audio.holdScene(LunoMusicScene.battle);
      await audio.setScene(LunoMusicScene.menu);
      entered = Completer<void>();
      blocked = Completer<void>();
      holdMethod = 'setVolume';
      final effect = audio.playEffect(LunoSound.cardFreeze);
      await entered!.future;
      audio.cancelEffects();
      blocked!.complete();
      await effect;
      await audio.setScene(LunoMusicScene.menu);
      expect(resumes(), isEmpty);
      expect(audio.effectiveScene, LunoMusicScene.battle);
      audio.releaseScene(owner);
      await audio.setScene(LunoMusicScene.menu);
    },
  );
}
