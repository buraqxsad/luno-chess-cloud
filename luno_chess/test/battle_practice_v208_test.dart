import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/emotes.dart';
import 'package:luno_chess/battle_v1/local_session.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/practice.dart';
import 'package:luno_chess/battle_ui/practice_coach.dart';
import 'package:luno_chess/battle_ui/interaction.dart';
import 'package:luno_chess/battle_ui/spell_vfx.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'battle_tutorial_v207_test.dart' show shell, warm, shot, noOverflow;
import 'battle_ui/visual_test.dart' show renderBattle, closeCapture;

void setupPracticeTestAssets() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final channel in [
      'xyz.luan/audioplayers.global/events',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers',
      for (final id in ['luno_music', 'luno_sfx_0', 'luno_sfx_1', 'luno_sfx_2'])
        'xyz.luan/audioplayers/events/$id',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
    }
    for (final e
        in {
          'Nunito': 'assets/fonts/nunito/nunito-variable.ttf',
          'Cinzel': 'assets/fonts/cinzel-latin.ttf',
          'CinzelTurkish': 'assets/fonts/cinzel-turkish.ttf',
          'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
        }.entries) {
      await (FontLoader(e.key)..addFont(rootBundle.load(e.value))).load();
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
}

void main() {
  setupPracticeTestAssets();
  test(
    'explicit Academy enrollment persists four stages and advances only once',
    () async {
      final s = GameStore.createForTesting();
      await s.load();
      await s.completeTutorial(beginPractice: true);
      await s.save();
      expect(s.practiceStage, 0);
      final restored = GameStore.createForTesting();
      await restored.load();
      expect(restored.practiceStage, 0);
      for (var stage = 0; stage < 4; stage++) {
        await restored.completePracticeStage(
          stage,
          restored.accountBindingRevision,
        );
        await restored.completePracticeStage(
          stage,
          restored.accountBindingRevision,
        );
        expect(restored.practiceStage, stage + 1);
      }
      expect(restored.needsPractice, isFalse);
      expect(restored.hasChosenUsername, isFalse);
    },
  );
  test(
    'legacy completed tutorials are not forced back into onboarding',
    () async {
      SharedPreferences.setMockInitialValues({
        'luno_player_v1': jsonEncode({
          ...PlayerData.initial().toJson(),
          'tutorialCompleted': true,
          'usernameChosen': true,
        }),
      });
      final s = GameStore.createForTesting();
      await s.load();
      expect(s.hasCompletedTutorial, isTrue);
      expect(s.needsPractice, isFalse);
    },
  );
  test(
    'practice progress is account-scoped and stale completion cannot cross sessions',
    () async {
      final s = GameStore.createForTesting();
      await s.load();
      await s.bindAccount('a');
      await s.completeTutorial(beginPractice: true);
      await s.save();
      final oldRevision = s.accountBindingRevision;
      await s.completePracticeStage(0, oldRevision);
      await s.bindAccount('b');
      await s.completePracticeStage(1, oldRevision);
      expect(s.practiceStage, isNull);
      await s.bindAccount('a');
      expect(s.practiceStage, 1);
    },
  );
  for (var stage = 0; stage < 4; stage++) {
    test(
      'practice $stage completes via actual legal card, discard and chess transitions',
      () {
        final p = BattlePracticeProgress(stage);
        validateDeck(p.deck);
        expect(p.deck.first, p.card);
        var state = DeckManager.newBattle(white: p.deck);
        for (var i = 0; i < 100 && !p.complete; i++) {
          expect(state.rules.terminal, isNull);
          final side = state.rules.board.turn, before = state.view(side);
          final actions = BattleRulesCore.legalActions(before);
          BattleAction? action;
          if (side == PieceColor.white && !p.cast) {
            action =
                actions
                    .whereType<PlayCardAction>()
                    .where((a) => a.card == p.card)
                    .firstOrNull;
          }
          if (side == PieceColor.white && p.cast && !p.discarded) {
            action ??= actions.whereType<DiscardAction>().firstOrNull;
          }
          action ??= actions.whereType<ResolveAction>().firstOrNull;
          action ??= actions.whereType<PassAction>().firstOrNull;
          action ??= actions.whereType<ChessMoveAction>().firstOrNull;
          expect(action, isNotNull);
          state = DeckManager.apply(state, action!);
          p.accepted(action, before, state.view(side));
          final count = p.moves;
          p.accepted(action, before, state.view(side));
          expect(
            p.moves,
            count,
            reason: 'duplicate completion must not count twice',
          );
        }
        expect(p.complete, isTrue);
        expect(p.cast && p.discarded, isTrue);
        if (p.card == CardId.prophecy) expect(p.resolved, isTrue);
      },
    );
  }
  test(
    'selected difficulty reaches local AI and practice has no timeout rewards',
    () {
      final s = BattleV1LocalSession(level: aiLevels[3], practice: true);
      expect(s.level.id, 'bilge');
      expect(s.practice, isTrue);
      s.checkTimeout();
      expect(s.terminal, isNull);
      s.dispose();
    },
  );
  testWidgets(
    'background suspends bot actions and resumes without duplicate turn',
    (tester) async {
      final s = BattleV1LocalSession(practice: true);
      await s.submit(const ChessMoveAction('e2e4'));
      s.observe(false);
      await tester.pump(const Duration(seconds: 4));
      expect(s.view.rules.ply, 1);
      expect(s.busy, isFalse);
      s.observe(true);
      await tester.pump(const Duration(milliseconds: 950));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      expect(s.view.rules.ply, 2);
      s.dispose();
    },
  );
  test('VFX has a readable hold and a finite endpoint', () {
    expect(battleSpellEnvelope(.25), 1);
    expect(battleSpellEnvelope(.7), 1);
    expect(battleSpellEnvelope(.9), greaterThan(0));
    expect(battleSpellEnvelope(1), 0);
  });
  test(
    'coach follows legal pieces after e2 is emptied and actual card targets',
    () {
      var state = DeckManager.newBattle(white: BattlePracticeProgress(1).deck);
      state = DeckManager.apply(state, const ChessMoveAction('e2e4'));
      state = DeckManager.apply(state, const ChessMoveAction('e7e5'));
      final selection = BattleInteraction();
      var view = state.view(PieceColor.white);
      var actions = BattleRulesCore.legalActions(view);
      final square = battlePracticeBoardSquare(view, selection, actions);
      expect(square, isNotNull);
      expect(square, isNot(12));
      expect(view.rules.board.pieceAt(square!)?.color, PieceColor.white);
      expect(
        selection
            .moves(view, actions)
            .any(
              (m) =>
                  m.uci.codeUnitAt(0) - 97 + (int.parse(m.uci[1]) - 1) * 8 ==
                  square,
            ),
        isTrue,
      );
      final draft = RuleDraft(view.rules)..mana[PieceColor.white] = 6;
      view = PlayerView(
        draft.freeze(),
        view.viewer,
        view.ownHand,
        view.knowledge,
      );
      actions = BattleRulesCore.legalActions(view);
      selection.select(CardId.freeze, actions);
      expect(
        selection.targets(view, actions),
        contains(battlePracticeBoardSquare(view, selection, actions)),
      );
    },
  );
  testWidgets(
    'emotes enforce ownership, appear, expire and remain independent of gameplay',
    (tester) async {
      final c = BattleEmoteChannel();
      expect(await c.send('crown', PieceColor.white, {'smile'}), isFalse);
      expect(await c.send('smile', PieceColor.white, {'smile'}), isTrue);
      expect(c.visible[PieceColor.white]!.emojiId, 'smile');
      expect(await c.send('smile', PieceColor.white, {'smile'}), isFalse);
      await tester.pump(const Duration(milliseconds: 3700));
      expect(c.visible, isEmpty);
      c.dispose();
    },
  );
  test(
    'initial emote feed does not replay historical messages, failed transport is isolated',
    () async {
      var calls = 0;
      final c = BattleEmoteChannel(
        matchId: 'm',
        request: (_, _) async {
          if (++calls == 3) throw StateError('offline');
          return {
            'ok': true,
            'sequence': calls,
            'events': [
              {'sequence': calls, 'emojiId': 'heart', 'side': 'b', 'at': 1000},
            ],
          };
        },
      );
      await c.fetch();
      expect(c.visible, isEmpty);
      await c.fetch();
      expect(c.visible[PieceColor.black]!.sequence, 2);
      await c.fetch();
      expect(c.visible[PieceColor.black]!.sequence, 2);
      c.setMuted(true);
      expect(c.visible, isEmpty);
      c.dispose();
    },
  );
  testWidgets('emote cooldown notifies and expires on monotonic time', (
    tester,
  ) async {
    var now = 0, notifications = 0;
    final c = BattleEmoteChannel(monotonicMillis: () => now);
    c.addListener(() => notifications++);
    expect(await c.send('smile', PieceColor.white, {'smile'}), isTrue);
    final before = notifications;
    now = 2999;
    expect(c.canSend, isFalse);
    now = 3000;
    await tester.pump(const Duration(milliseconds: 3000));
    expect(notifications, greaterThan(before));
    expect(c.canSend, isTrue);
    expect(await c.send('smile', PieceColor.white, {'smile'}), isTrue);
    c.dispose();
  });
  test('late network response cannot animate into a departed screen', () async {
    final pending = Completer<Map<String, dynamic>>();
    final c = BattleEmoteChannel(
      matchId: 'm',
      request: (_, _) => pending.future,
    );
    final send = c.send('smile', PieceColor.white, {'smile'});
    c.dispose();
    pending.complete({
      'event': {'sequence': 1, 'side': 'w', 'emojiId': 'smile'},
    });
    expect(await send, isFalse);
  });
  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(600, 960),
    const Size(844, 390),
  ]) {
    for (final language in ['tr', 'en']) {
      testWidgets('practice coach readable at $size $language', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          shell(
            const BattleV1Screen(practiceStage: 0, clockOverride: _clock),
            language: language,
          ),
        );
        await warm(tester);
        noOverflow(tester);
        expect(find.byType(BattlePracticeCoach), findsOneWidget);
        expect(find.byKey(const ValueKey('open-emotes')), findsOneWidget);
        await shot(
          tester,
          'practice-${size.width.toInt()}-${size.height.toInt()}-$language',
        );
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  for (final scale in [1.3, 1.8]) {
    for (final language in ['tr', 'en']) {
      testWidgets('practice large text remains readable $scale $language', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          shell(
            const BattleV1Screen(practiceStage: 0, clockOverride: _clock),
            language: language,
            scale: scale,
          ),
        );
        await warm(tester);
        noOverflow(tester);
        final emote = find.byKey(const ValueKey('open-emotes'));
        await tester.ensureVisible(emote);
        await tester.tap(emote);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('send-emote-smile')), findsOneWidget);
        noOverflow(tester);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets('battle emote picker opens actual owned expressions', (
    tester,
  ) async {
    GameStore.instance.data = PlayerData.initial();
    await renderBattle(tester);
    final button = find.byKey(const ValueKey('open-emotes'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send-emote-smile')), findsOneWidget);
    await closeCapture(tester);
  });
}

int _clock(PieceColor _) => 300000;
