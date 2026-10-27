import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/services/first_session_telemetry.dart';
import 'package:luno_chess/services/luno_online_service.dart';

import 'battle_deck_account_test.dart' show response;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'helpers/battle_v1_response.dart';
import 'online_request_session_test.dart' show TestAuth, TestUser;
import 'v214_first_match_ui_test.dart' show resign, settleRoute;

Map<String, dynamic> activeResponse(String uid, {int version = 0}) {
  final result = v1Response(version: version);
  final public = (result['view'] as Map)['public'] as Map;
  public['participants'] = {uid: true, 'other': true};
  ((public['players'] as Map)['w'] as Map)['uid'] = uid;
  return result;
}

Map<String, dynamic> finishedResponse(String uid) {
  final result = activeResponse(uid, version: 1);
  final public = (result['view'] as Map)['public'] as Map;
  final rules =
      RuleDraft(
          RuleState.fromJson(jsonDecode(public['rulesJson'] as String) as Map),
        )
        ..phase = BattlePhase.terminal
        ..terminal = const TerminalState('resign', winner: PieceColor.black);
  public['rulesJson'] = jsonEncode(rules.freeze().toJson());
  public['result'] = {'reason': 'resign', 'winner': 'b'};
  public['settlementStatus'] = 'pending';
  result['status'] = 'finished';
  return result;
}

void main() {
  setupPracticeTestAssets();
  final store = GameStore.instance;
  var account = 0;
  setUp(() async {
    await store.load();
    await store.bindAccount('v217-first-match-${account++}');
    store
      ..data = PlayerData.initial()
      ..hasCompletedTutorial = true
      ..firstSessionMatchesStarted = 0;
  });
  tearDown(store.flush);

  Future<void> mount(WidgetTester tester, BattleV1Screen screen) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    await tester.pumpWidget(shell(screen, reduced: true));
    await settleRoute(tester);
  }

  for (final starts in [0, 1]) {
    testWidgets('already finished online resume repairs $starts prior starts', (
      tester,
    ) async {
      store.firstSessionMatchesStarted = starts;
      final before = store.data.toJson();
      final requests = <String>[];
      final terminal = finishedResponse(store.accountUid!);
      final controller = BattleV1Controller(
        uid: store.accountUid!,
        matchId: v1MatchId,
        initialResponse: terminal,
        persistPending: (_) async {},
        request: (path, _) async {
          requests.add(path);
          return terminal;
        },
      );
      addTearDown(controller.dispose);
      await mount(tester, BattleV1Screen(controllerOverride: controller));
      expect(store.firstSessionPhase, 'firstCompleted');
      expect(store.firstSessionMatchesStarted, 1);
      final telemetry = FirstSessionTelemetry.forStore(store);
      expect(
        telemetry.samples.where(
          (s) => s.event == FirstSessionEvent.firstMatchFinished,
        ),
        hasLength(1),
      );
      await controller.reconnect();
      await controller.reconnect();
      expect(store.firstSessionMatchesStarted, 1);
      expect(
        telemetry.samples.where(
          (s) => s.event == FirstSessionEvent.firstMatchFinished,
        ),
        hasLength(1),
      );
      expect(store.data.toJson(), before);
      expect(requests, everyElement('/getBattleV1'));
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(store.flush);
      final restored = GameStore.createForTesting();
      await tester.runAsync(restored.load);
      expect(restored.needsFirstSessionMatch, isFalse);
      restored.dispose();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'late first snapshot and completion are observed in background before result UI',
    (tester) async {
      var next = activeResponse(store.accountUid!);
      final controller = BattleV1Controller(
        uid: store.accountUid!,
        matchId: v1MatchId,
        persistPending: (_) async {},
        request: (_, _) async => next,
      );
      addTearDown(controller.dispose);
      await mount(tester, BattleV1Screen(controllerOverride: controller));
      final telemetry = FirstSessionTelemetry.forStore(store);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await controller.reconnect();
      expect(store.firstSessionPhase, 'firstStarted');
      next = finishedResponse(store.accountUid!);
      await controller.reconnect();
      // Deliberately do not pump: terminal bookkeeping must precede result build.
      expect(store.firstSessionPhase, 'firstCompleted');
      expect(
        telemetry.samples.where(
          (s) => s.event == FirstSessionEvent.firstMatchFinished,
        ),
        hasLength(1),
      );
      expect(
        telemetry.samples.where((s) => s.event == FirstSessionEvent.resultSeen),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.runAsync(store.flush);
      final restored = GameStore.createForTesting();
      await tester.runAsync(restored.load);
      expect(restored.needsFirstSessionMatch, isFalse);
      restored.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late terminal response after account switch cannot complete either owner',
    (tester) async {
      final reply = Completer<Map<String, dynamic>>();
      final controller = BattleV1Controller(
        uid: store.accountUid!,
        matchId: v1MatchId,
        initialResponse: activeResponse(store.accountUid!),
        persistPending: (_) async {},
        request: (_, _) => reply.future,
      );
      addTearDown(controller.dispose);
      await mount(tester, BattleV1Screen(controllerOverride: controller));
      expect(store.firstSessionPhase, 'firstStarted');
      final oldUid = store.accountUid!;
      final pending = controller.reconnect();
      await tester.runAsync(() => store.bindAccount('v217-switched'));
      reply.complete(finishedResponse(oldUid));
      await pending;
      expect(store.firstSessionPhase, 'none');
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => store.bindAccount(oldUid));
      expect(store.firstSessionPhase, 'firstStarted');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('active online first match finishes once without local rewards', (
    tester,
  ) async {
    final before = store.data.toJson();
    var next = activeResponse(store.accountUid!);
    final controller = BattleV1Controller(
      uid: store.accountUid!,
      matchId: v1MatchId,
      initialResponse: next,
      persistPending: (_) async {},
      request: (_, _) async => next,
    );
    addTearDown(controller.dispose);
    await mount(tester, BattleV1Screen(controllerOverride: controller));
    expect(store.firstSessionPhase, 'firstStarted');
    next = finishedResponse(store.accountUid!);
    await controller.reconnect();
    expect(store.firstSessionPhase, 'firstCompleted');
    await controller.reconnect();
    expect(store.firstSessionMatchesStarted, 1);
    expect(store.data.toJson(), before);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tutorial-skipped AI resignation persists completion without rewards',
    (tester) async {
      store.hasCompletedTutorial = false;
      await tester.runAsync(
        () => store.completeIntroduction(store.accountBindingRevision),
      );
      expect(store.needsFirstSessionMatch, isTrue);
      final before = store.data.toJson();
      final paths = <String>[];
      final auth = TestAuth()..currentUser = TestUser(store.accountUid!);
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        appCheck: () async => 'check',
        client: MockClient((request) async {
          paths.add(request.url.path);
          if (!request.url.path.endsWith('/getBattleV1Deck')) {
            throw StateError('Unexpected request ${request.url.path}');
          }
          return http.Response(jsonEncode(response()), 200);
        }),
      );
      addTearDown(online.dispose);
      await tester.runAsync(() async {
        await online.start();
        await online.getBattleV1Deck();
      });
      await mount(tester, BattleV1Screen(deckOnline: online));
      expect(store.firstSessionPhase, 'firstStarted');
      await resign(tester);
      expect(store.firstSessionPhase, 'firstCompleted');
      expect(store.data.toJson(), before);
      expect(paths, isNotEmpty);
      expect(paths.every((path) => path.endsWith('/getBattleV1Deck')), isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(store.flush);
      final restored = GameStore.createForTesting();
      await tester.runAsync(restored.load);
      expect(restored.needsFirstSessionMatch, isFalse);
      restored.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('practice never records a first match', (tester) async {
    await mount(tester, const BattleV1Screen(practiceStage: 0));
    expect(store.firstSessionPhase, 'none');
    expect(
      FirstSessionTelemetry.forStore(store).samples.where(
        (s) =>
            s.event == FirstSessionEvent.firstMatchStarted ||
            s.event == FirstSessionEvent.firstMatchFinished,
      ),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
