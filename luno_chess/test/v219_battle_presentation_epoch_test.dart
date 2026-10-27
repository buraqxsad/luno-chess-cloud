import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/audio_feedback.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_ui/feedback.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/services/luno_audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'v219_battle_presentation_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  final settings = LunoSettings.instance;
  late LunoAudioService audio;
  Completer<void>? entered, blocked;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  List<MethodCall> resumes() =>
      calls.where((call) {
        final id = (call.arguments as Map?)?['playerId'] as String? ?? '';
        return call.method == 'resume' && id.startsWith('luno_sfx_');
      }).toList();

  Future<void> pumpNativeUntil(
    WidgetTester tester,
    bool Function() complete,
    String reason,
  ) async {
    final deadline = Stopwatch()..start();
    while (!complete() && deadline.elapsed < const Duration(seconds: 3)) {
      await tester.pump();
      if (!complete()) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }
    expect(
      complete(),
      isTrue,
      reason:
          '$reason; native calls: ${calls.map((call) => '${call.method}:${(call.arguments as Map?)?['playerId']}').join(', ')}',
    );
  }

  Future<void> drain(WidgetTester tester) async {
    var complete = false;
    Object? failure;
    unawaited(
      audio
          .setScene(LunoMusicScene.menu)
          .then<void>(
            (_) => complete = true,
            onError: (Object error, StackTrace stack) {
              failure = error;
              complete = true;
            },
          ),
    );
    await pumpNativeUntil(
      tester,
      () => complete,
      'The native mixer queue must drain',
    );
    expect(failure, isNull);
  }

  Future<void> cleanup(WidgetTester tester) async {
    if (blocked != null && !blocked!.isCompleted) blocked!.complete();
    entered = blocked = null;
    await tester.pumpWidget(const SizedBox());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    audio.cancelEffects();
    await drain(tester);
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await loadV219PresentationFonts();
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
        if (call.method == 'setVolume' &&
            args?['playerId'] != 'luno_music' &&
            entered != null &&
            !entered!.isCompleted) {
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
    entered = blocked = null;
    audio.effectMillisForTesting = () => 10000;
    audio.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await settings.setEffectsLevel(3);
    await settings.setMusicLevel(0);
    audio.cancelEffects();
    await audio
        .setScene(LunoMusicScene.menu)
        .timeout(const Duration(seconds: 3));
    calls.clear();
  });

  tearDown(() {
    if (blocked != null && !blocked!.isCompleted) blocked!.complete();
    entered = blocked = null;
    // Each widget case drains in finally; do not enqueue into its departing zone.
    audio.effectMillisForTesting = null;
  });

  Widget stage(
    PlayerView view, {
    int epoch = 0,
    bool reduced = false,
    bool visible = true,
    TerminalState? terminal,
  }) => v219PresentationShell(
    BattleAudioFeedback(
      view: view,
      synchronizationEpoch: epoch,
      terminal: terminal,
      child: const SizedBox(),
    ),
    reduced: reduced,
    visible: visible,
  );

  for (final boundary in [
    'epoch',
    'viewer',
    'dispose',
    'terminal',
    'hidden',
    'reduced',
    'background',
  ]) {
    testWidgets('V219 native queued cast is invalidated by $boundary', (
      tester,
    ) async {
      // Native players and the singleton queue must outlive a test's fake zone.
      await tester.runAsync(() async {
        final pair = v219Cast(CardId.freeze);
        final before = pair.before.view(PieceColor.white);
        final after = pair.after.view(PieceColor.white);
        try {
          expect(
            battleSoundCues(before, after),
            contains((sound: LunoSound.cardCast, delayMs: 0)),
          );
          expect(settings.soundEnabled, isTrue);
          await tester.pumpWidget(stage(before));
          entered = Completer<void>();
          blocked = Completer<void>();
          await tester.pumpWidget(stage(after));
          await pumpNativeUntil(
            tester,
            () => entered!.isCompleted,
            'The native preparation gate must be reached before invalidation',
          );
          expect(resumes(), isEmpty);

          switch (boundary) {
            case 'epoch':
              await tester.pumpWidget(stage(after, epoch: 1));
            case 'viewer':
              await tester.pumpWidget(stage(pair.after.view(PieceColor.black)));
            case 'dispose':
              await tester.pumpWidget(const SizedBox());
            case 'terminal':
              await tester.pumpWidget(
                stage(
                  after,
                  terminal: const TerminalState(
                    'resign',
                    winner: PieceColor.white,
                  ),
                ),
              );
            case 'hidden':
              await tester.pumpWidget(stage(after, visible: false));
            case 'reduced':
              await tester.pumpWidget(stage(after, reduced: true));
            case 'background':
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.paused,
              );
              await tester.pump();
          }
          blocked!.complete();
          await drain(tester);
          expect(
            resumes(),
            isEmpty,
            reason: 'Native preparation must retain its widget owner',
          );

          if (boundary == 'terminal') {
            await Future<void>.delayed(const Duration(milliseconds: 400));
            await tester.pump(const Duration(milliseconds: 400));
            await drain(tester);
            expect(
              resumes(),
              hasLength(1),
              reason: 'The new terminal fanfare is still valid',
            );
          }
        } finally {
          await cleanup(tester);
        }
      });
    });
  }

  testWidgets('V219 epoch stops playing SFX without releasing battle music', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final lease = audio.holdScene(LunoMusicScene.battle);
      final pair = v219Cast(CardId.freeze);
      final after = pair.after.view(PieceColor.white);
      try {
        await tester.pumpWidget(stage(pair.before.view(PieceColor.white)));
        await tester.pumpWidget(stage(after));
        await drain(tester);
        expect(resumes(), hasLength(1));
        final id = (resumes().single.arguments as Map)['playerId'];
        calls.clear();
        await tester.pumpWidget(stage(after, epoch: 1));
        await drain(tester);
        expect(
          calls.any(
            (call) =>
                call.method == 'stop' &&
                (call.arguments as Map?)?['playerId'] == id,
          ),
          isTrue,
        );
        expect(audio.effectiveScene, LunoMusicScene.battle);
      } finally {
        audio.releaseScene(lease);
        await cleanup(tester);
      }
    });
  });

  testWidgets('V219 duplicate accepted snapshot cannot replay mixer feedback', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final pair = v219Cast(CardId.freeze);
      final after = pair.after.view(PieceColor.white);
      try {
        await tester.pumpWidget(stage(pair.before.view(PieceColor.white)));
        await tester.pumpWidget(stage(after));
        await Future<void>.delayed(
          Duration(milliseconds: battleImpactDelay(CardId.freeze)),
        );
        await tester.pump(
          Duration(milliseconds: battleImpactDelay(CardId.freeze)),
        );
        await drain(tester);
        expect(resumes(), hasLength(2));
        await tester.pumpWidget(stage(after));
        await tester.pump(const Duration(seconds: 1));
        await drain(tester);
        expect(resumes(), hasLength(2));
      } finally {
        await cleanup(tester);
      }
    });
  });

  testWidgets('V219 epoch cancellation permits fresh accepted feedback', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final pair = v219Cast(CardId.freeze);
      final before = pair.before.view(PieceColor.white);
      final after = pair.after.view(PieceColor.white);
      try {
        await tester.pumpWidget(stage(before));
        await tester.pumpWidget(stage(after));
        await drain(tester);
        await tester.pumpWidget(stage(before, epoch: 1));
        await drain(tester);
        calls.clear();
        await tester.pumpWidget(stage(after, epoch: 1));
        await Future<void>.delayed(
          Duration(milliseconds: battleImpactDelay(CardId.freeze)),
        );
        await tester.pump(
          Duration(milliseconds: battleImpactDelay(CardId.freeze)),
        );
        await drain(tester);
        expect(resumes(), hasLength(2));
      } finally {
        await cleanup(tester);
      }
    });
  });

  Widget notice(PlayerView view, {int epoch = 0}) => v219PresentationShell(
    BattleCastNotice(
      view: view,
      synchronizationEpoch: epoch,
      child: const Text('Current instruction'),
    ),
  );

  test('V219 cast notice epoch defaults to zero for existing callers', () {
    final view = v219Cast(CardId.freeze).before.view(PieceColor.white);
    expect(
      BattleCastNotice(
        view: view,
        child: const SizedBox(),
      ).synchronizationEpoch,
      0,
    );
  });

  testWidgets('V219 synchronized history is not a live cast notice', (
    tester,
  ) async {
    final pair = v219Cast(CardId.freeze);
    final before = pair.before.view(PieceColor.white);
    final after = pair.after.view(PieceColor.white);
    await tester.pumpWidget(notice(before));
    await tester.pumpWidget(notice(after, epoch: 1));
    expect(find.byKey(const ValueKey('cast-notice-freeze')), findsNothing);
    await tester.pumpWidget(notice(before, epoch: 2));
    await tester.pumpWidget(notice(after, epoch: 2));
    expect(find.byKey(const ValueKey('cast-notice-freeze')), findsOneWidget);
    await tester.pumpWidget(notice(after, epoch: 3));
    expect(find.byKey(const ValueKey('cast-notice-freeze')), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(const ValueKey('cast-notice-freeze')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
