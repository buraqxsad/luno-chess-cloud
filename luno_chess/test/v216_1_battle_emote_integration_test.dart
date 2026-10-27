import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/services/luno_audio_service.dart';
import 'package:luno_chess/widgets/cosmetic_emote_art.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'battle_ui/interaction_test.dart' show Harness;
import 'helpers/battle_v1_response.dart';

void main() {
  setupPracticeTestAssets();
  final calls = <MethodCall>[];
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late LunoAudioService audio;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    for (final sound in LunoSound.values) {
      final asset = LunoAudioService.assetForSound(sound);
      AudioCache.instance.loadedFiles[asset] = File('assets/$asset').absolute.uri;
    }
    messenger.setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers'), (call) async {
      calls.add(call);
      if (call.method == 'setSourceUrl') {
        final args = call.arguments as Map;
        scheduleMicrotask(() {
          // ignore: deprecated_member_use
          messenger.handlePlatformMessage('xyz.luan/audioplayers/events/${args['playerId']}',
            const StandardMethodCodec().encodeSuccessEnvelope({'event': 'audio.onPrepared', 'value': true}), (_) {});
        });
      }
      return call.method == 'getCurrentPosition' ? 0 : null;
    });
    audio = LunoAudioService.instance;
    audio.effectMillisForTesting = () => 10000;
    await audio.initialize();
    await GameStore.instance.bindAccount('emote-battle');
  });
  setUp(() async {
    GameStore.instance.accountUid = 'emote-battle';
    GameStore.instance.data = PlayerData.initial();
    await LunoSettings.instance.setEffectsLevel(3);
    await LunoSettings.instance.setMusicLevel(0);
    audio.didChangeAppLifecycleState(AppLifecycleState.resumed);
    audio.cancelEffects();
    calls.clear();
  });
  tearDown(() async => LunoSettings.instance.setEffectsLevel(0));
  tearDownAll(() => audio.effectMillisForTesting = null);
  Future<void> flush(WidgetTester tester) async {
    await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 30)));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 2)));
    }
  }
  for (final boundary in ['visible', 'muted', 'covered', 'background', 'account']) {
    testWidgets('actual battle accepted emote respects $boundary presentation boundary', (tester) async {
      await tester.pumpWidget(shell(const BattleV1Screen(local: true), reduced: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hotseat-ready')));
      await tester.pumpAndSettle();
      await flush(tester);
      final dynamic state = tester.state(find.byType(BattleV1Screen));
      final channel = state.emotes;
      if (boundary == 'muted') channel.setMuted(true);
      if (boundary == 'covered') {
        unawaited(Navigator.of(tester.element(find.byType(BattleV1Screen))).push(
          MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Other route')))));
        await tester.pumpAndSettle();
      }
      if (boundary == 'background') tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      if (boundary == 'account') {
        var bound = false;
        unawaited(GameStore.instance.bindAccount('other').then((_) => bound = true));
        for (var i = 0; i < 40 && !bound; i++) {
          await tester.pump(const Duration(milliseconds: 600));
          await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 2)));
        }
        expect(bound, isTrue);
      }
      calls.clear();
      await channel.send('heart', PieceColor.white, {'heart'});
      await flush(tester);
      final heart = calls.where((c) => c.method == 'setSourceUrl' &&
          (c.arguments as Map)['url'].toString().endsWith('audio/emote_heart.wav'));
      expect(heart.length, boundary == 'visible' ? 1 : 0,
        reason: 'Enabled ${LunoSettings.instance.soundEnabled}; visible ${channel.visible}; calls ${calls.map((c) => '${c.method}:${c.arguments}').join(', ')}');
      if (boundary == 'visible') {
        expect(find.byType(CosmeticEmoteArt), findsOneWidget);
        await channel.send('heart', PieceColor.white, {'heart'});
        await flush(tester);
        expect(heart.length, 1);
        channel.setMuted(true);
        await flush(tester);
        expect(find.byType(CosmeticEmoteArt), findsNothing);
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('pending emote accepted under covered route stays silent on return', (tester) async {
    final harness = Harness();
    final held = Completer<Map<String, dynamic>>();
    final controller = BattleV1Controller(uid: 'self', matchId: v1MatchId,
      initialResponse: v1Response(state: harness.state), persistPending: (_) async {},
      request: (path, body) async => path == '/sendBattleV1Emote' ? held.future
          : {'ok': true, 'sequence': 0, 'events': []});
    await tester.pumpWidget(shell(BattleV1Screen(controllerOverride: controller,
      clockOverride: (_) => 300000), reduced: true));
    await tester.pumpAndSettle(); await flush(tester);
    final dynamic state = tester.state(find.byType(BattleV1Screen));
    final channel = state.emotes;
    final sending = channel.send('heart', PieceColor.white, {'heart'});
    final navigator = Navigator.of(tester.element(find.byType(BattleV1Screen)));
    unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Cover')))));
    await tester.pumpAndSettle();
    calls.clear();
    held.complete({'ok': true, 'event': {'sequence': 1, 'emojiId': 'heart', 'side': 'w'}});
    expect(await sending, isFalse);
    navigator.pop(); await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 3100)); await flush(tester);
    expect(channel.visible, isEmpty);
    expect(calls.where((c) => c.method == 'setSourceUrl' &&
        (c.arguments as Map)['url'].toString().contains('audio/emote_')), isEmpty);
    expect(find.byType(CosmeticEmoteArt), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose(); harness.controller.dispose();
    expect(tester.takeException(), isNull);
  });
}
