import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/luno_audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'audio initialized while paused does not start background music',
    () async {
      SharedPreferences.setMockInitialValues({});
      final calls = <MethodCall>[];
      final binding = TestWidgetsFlutterBinding.instance;
      final messenger = binding.defaultBinaryMessenger;
      AudioCache.instance.loadedFiles['audio/menu_loop.wav'] =
          File('assets/audio/menu_loop.wav').absolute.uri;
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
          if (call.method == 'getCurrentPosition') return 0;
          return null;
        },
      );
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      try {
        await LunoAudioService.instance.setScene(LunoMusicScene.menu);
        expect(
          calls.where((call) {
            final args = call.arguments as Map?;
            return args?['playerId'] == 'luno_music' &&
                (call.method == 'setSourceUrl' || call.method == 'resume');
          }),
          isEmpty,
        );
      } finally {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await LunoAudioService.instance.setScene(LunoMusicScene.menu);
      }
      expect(
        calls.any(
          (call) =>
              call.method == 'resume' &&
              (call.arguments as Map?)?['playerId'] == 'luno_music',
        ),
        isTrue,
        reason: 'The platform mock must support playback after resume.',
      );
    },
  );
}
