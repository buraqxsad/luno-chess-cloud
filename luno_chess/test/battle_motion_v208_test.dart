import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/emotes.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/battle_practice_campaign.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'battle_ui/interaction_test.dart' show Harness;
import 'battle_tutorial_v207_test.dart'
    show shell, warm, shot, noOverflow, visibleTap;
import 'helpers/battle_v1_response.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'battle_practice_v208_test.dart' as practice_tests;

void main() {
  practice_tests.setupPracticeTestAssets();
  testWidgets('practice replay can return home without changing onboarding', (
    tester,
  ) async {
    final store = GameStore.createForTesting();
    await store.load();
    await tester.pumpWidget(
      shell(
        Builder(
          builder:
              (context) => TextButton(
                onPressed:
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder:
                            (_) => BattlePracticeCampaign(
                              storeOverride: store,
                              replay: true,
                            ),
                      ),
                    ),
                child: const Text('Replay'),
              ),
        ),
        reduced: true,
      ),
    );
    await tester.tap(find.text('Replay'));
    await tester.pumpAndSettle();
    await visibleTap(tester, 'open-menu');
    await tester.pumpAndSettle();
    await visibleTap(tester, 'leave-practice');
    await tester.pumpAndSettle();
    expect(find.text('Replay'), findsOneWidget);
    expect(store.practiceStage, isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'four practice opponents transition without stale board or coach state',
    (tester) async {
      final store = GameStore.createForTesting();
      await store.load();
      await store.completeTutorial(beginPractice: true);
      await tester.pumpWidget(
        shell(BattlePracticeCampaign(storeOverride: store), reduced: true),
      );
      await tester.pumpAndSettle();
      for (var stage = 0; stage < 4; stage++) {
        expect(
          tester
              .widget<BattleV1Screen>(find.byType(BattleV1Screen))
              .practiceStage,
          stage,
        );
        expect(
          tester.widget<BattleBoard>(find.byType(BattleBoard)).view.rules.ply,
          0,
        );
        final portrait = ['bebek', 'comez', 'sovalye', 'bilge'][stage];
        expect(
          tester.widgetList<Image>(find.byType(Image)).any((i) {
            final provider =
                i.image is ResizeImage
                    ? (i.image as ResizeImage).imageProvider
                    : i.image;
            return provider is AssetImage &&
                provider.assetName == LunoAssets.aiPortrait(portrait);
          }),
          isTrue,
        );
        await store.completePracticeStage(stage, store.accountBindingRevision);
        await tester.pumpAndSettle();
      }
      expect(find.byType(BattleV1Screen), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'emoji sends through V1 endpoint and displays without moving the board',
    (tester) async {
      final h = Harness(), feed = <Map<String, dynamic>>[];
      final c = BattleV1Controller(
        uid: 'self',
        matchId: v1MatchId,
        initialResponse: v1Response(state: h.state),
        persistPending: (_) async {},
        request: (path, body) async {
          if (path == '/sendBattleV1Emote') {
            feed.add({
              'sequence': feed.length + 1,
              'side': 'w',
              'emojiId': body['emojiId'],
              'at': 1000,
            });
            return {'ok': true, 'event': feed.last};
          }
          if (path == '/getBattleV1Emotes') {
            return {'ok': true, 'sequence': feed.length, 'events': feed};
          }
          return h.controller.request(path, body);
        },
      );
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      GameStore.instance.data = PlayerData.initial();
      await tester.pumpWidget(
        shell(
          BattleV1Screen(controllerOverride: c, clockOverride: (_) => 300000),
        ),
      );
      await warm(tester);
      final boardRect = tester.getRect(find.byType(BattleBoard));
      await visibleTap(tester, 'open-emotes');
      await warm(tester);
      await visibleTap(tester, 'send-emote-smile');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(feed, hasLength(1));
      expect(find.byType(BattleEmoteBubble), findsOneWidget);
      expect(tester.getRect(find.byType(BattleBoard)), boardRect);
      noOverflow(tester);
      await shot(tester, 'v208-emote-320');
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      h.controller.dispose();
    },
  );
  testWidgets('long native cast motion captures actual accepted card state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = Harness(
      hand: const [CardId.freeze, CardId.shelter, CardId.radar],
    );
    await tester.pumpWidget(
      shell(
        BattleV1Screen(
          controllerOverride: h.controller,
          clockOverride: (_) => 300000,
        ),
      ),
    );
    await warm(tester);
    await visibleTap(tester, 'hand-freeze');
    await visibleTap(tester, 'square-57');
    await tester.pumpAndSettle();
    await visibleTap(tester, 'play-card');
    await tester.runAsync(() => Directory('qa/v208').create(recursive: true));
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 190));
      final name = 'v208-motion-${frame.toString().padLeft(2, '0')}';
      await shot(tester, name);
      noOverflow(tester);
      await tester.runAsync(
        () => File('qa/v207/$name.png').copy('qa/v208/$name.png'),
      );
    }
    expect(
      h.state.rules.used.values.any((cards) => cards.contains(CardId.freeze)),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    h.controller.dispose();
  });
}
