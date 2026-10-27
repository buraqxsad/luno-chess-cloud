import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/collection_screens.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/services/luno_audio_service.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_tutorial_v207_test.dart' show shell;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late LunoAudioService audio;
  final store = GameStore.instance;
  Completer<void>? hold, entered;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await store.bindAccount('cosmetic-audio');
    for (final sound in LunoSound.values) {
      final asset = LunoAudioService.assetForSound(sound);
      AudioCache.instance.loadedFiles[asset] = File('assets/$asset').absolute.uri;
    }
    for (final channel in ['xyz.luan/audioplayers.global', 'xyz.luan/audioplayers.global/events',
      for (final id in ['luno_music', 'luno_sfx_0', 'luno_sfx_1', 'luno_sfx_2'])
        'xyz.luan/audioplayers/events/$id']) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
    }
    messenger.setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers'), (call) async {
      calls.add(call);
      final args = call.arguments as Map?;
      if (call.method == 'setSourceUrl') {
        if (hold != null) {
          entered!.complete();
          await hold!.future;
        }
        scheduleMicrotask(() {
          // ignore: deprecated_member_use
          messenger.handlePlatformMessage('xyz.luan/audioplayers/events/${args?['playerId']}',
            const StandardMethodCodec().encodeSuccessEnvelope({'event': 'audio.onPrepared', 'value': true}), (_) {});
        });
      }
      return call.method == 'getCurrentPosition' ? 0 : null;
    });
    audio = LunoAudioService.instance;
    await audio.initialize();
    await LunoSettings.instance.setEffectsLevel(3);
    await LunoSettings.instance.setMusicLevel(0);
    audio.didChangeAppLifecycleState(AppLifecycleState.paused);
    audio.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await audio.setScene(LunoMusicScene.menu);
    calls.clear();
  });
  tearDownAll(() async {
    await LunoSettings.instance.setEffectsLevel(0);
  });
  List<MethodCall> resumes() => calls.where((c) => c.method == 'resume').toList();
  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 48; i++) {
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 2)));
    }
  }

  testWidgets('five semantic reveals and six cancellation boundaries use prepared native audio', (tester) async {
    await tester.pumpWidget(shell(const Scaffold(body: SizedBox())));
    final preloadContext = tester.element(find.byType(Scaffold));
    await tester.runAsync(() => precacheImage(
      const AssetImage('assets/native_art/polish-v203-button-secondary.webp'), preloadContext));
    for (final kind in ['card', 'set', 'reward', 'emote', 'fragments']) {
      calls.clear();
      Widget page() => Scaffold(body: kind == 'emote' || kind == 'fragments'
        ? ChestRevealDialog(chestId: 'rare', rewards: [
            {'type': 'emoji', 'id': 'heart', 'amount': 2, 'unlocked': kind == 'emote'}])
        : ShopRewardDialog(title: 'Confirmed', art: 'assets/native_art/luno-coin.png', message: 'Confirmed',
            pieceSet: kind == 'set' ? 'ottoman' : null,
            cardUnlock: kind == 'card' ? CardId.prophecy : null));
      await tester.pumpWidget(shell(page(), reduced: true));
      await flush(tester);
      expect(resumes().length, 1, reason: calls.map((c) => c.method).join(', '));
      final asset = LunoAudioService.assetForSound(switch (kind) {
        'card' => LunoSound.cardUnlock, 'set' => LunoSound.costumeUnlock,
        'emote' => LunoSound.emoteUnlock, _ => LunoSound.reward});
      expect(calls.where((c) => c.method == 'setSourceUrl').single.arguments,
        containsPair('url', endsWith(asset)));
      await tester.pumpWidget(shell(page(), reduced: true));
      await flush(tester);
      expect(resumes().length, 1);
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
    }

  for (final cancellation in ['epoch', 'account', 'hidden', 'paused', 'disposed', 'close']) {
      calls.clear();
      hold = Completer<void>();
      entered = Completer<void>();
      final key = GlobalKey<CosmeticPresentationFeedbackState>();
      Widget page({bool enabled = true}) => TickerMode(enabled: enabled,
        child: CosmeticPresentationFeedback(key: key, playerStore: store,
          sound: LunoSound.emoteUnlock, child: const Scaffold(body: Text('Confirmed emote'))));
      await tester.pumpWidget(shell(page()));
      await flush(tester);
      await tester.runAsync(() async => entered!.future.timeout(const Duration(seconds: 2)));
      if (cancellation == 'epoch') {
        store.invalidateServerStates();
        await tester.pumpWidget(shell(page()));
      }
      if (cancellation == 'account') {
        await tester.runAsync(() => store.bindAccount('other-audio-owner'));
      }
      if (cancellation == 'hidden') await tester.pumpWidget(shell(page(enabled: false)));
      if (cancellation == 'paused') tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      if (cancellation == 'disposed') await tester.pumpWidget(const SizedBox());
      if (cancellation == 'close') key.currentState!.cancel();
      hold!.complete();
      hold = null;
      await flush(tester);
      expect(resumes(), isEmpty, reason: cancellation);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => store.bindAccount('cosmetic-audio'));
      await flush(tester);
  }
    expect(tester.takeException(), isNull);
  });
}
