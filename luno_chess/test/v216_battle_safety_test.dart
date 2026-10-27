import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/audio_feedback.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/feedback.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_ui/sheets.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/battle_ui/spell_vfx.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'battle_ui/fixtures.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_ui/visual_test.dart' show renderBattle, visualTap;
import 'battle_tutorial_v207_test.dart' show shell;
import 'v214_vfx_review_test.dart' as review;
import 'v216_battle_payoff_test.dart' show payoff;

PlayerView changed(PlayerView view, void Function(RuleDraft) edit,
    {PieceColor? viewer}) {
  final draft = RuleDraft(view.rules);
  edit(draft);
  return PlayerView(draft.freeze(), viewer ?? view.viewer, view.ownHand, view.knowledge);
}

void main() {
  setupPracticeTestAssets();
  setUpAll(() async {
    await LunoSettings.instance.load();
    await GameStore.instance.load();
    review.fixtures = ((jsonDecode(File('../battle_contract/v1/rules.json')
      .readAsStringSync()) as Map)['fixtures'] as List).cast<Map>();
  });
  test('V216 malformed spell squares are unique valid and bounded', () {
    final cue = BattleSpellCue(CardId.fog, PieceColor.white,
      [-1, 64, 0, 0, 63, 4, 5, 6, 7]);
    expect(cue.squares, [0, 63, 4, 5]);
    expect(() => cue.squares.add(20), throwsUnsupportedError);
  });
  test('V216 nonfinite spell progress is fully transparent', () async {
    final cue = BattleSpellCue(CardId.freeze, PieceColor.white, [52]);
    for (final progress in [double.nan, double.infinity, double.negativeInfinity, -1.0, 1.0]) {
      expect(review.alphaPixels(await review.pixels(cue, progress)), 0);
    }
  });
  test('V216 stale replaced viewer and terminal casts are silent', () {
    final pair = review.cast(CardId.freeze);
    final before = pair.before.view(PieceColor.white), after = pair.after.view(PieceColor.white);
    for (final invalid in [
      changed(after, (d) => d.ply = before.rules.ply - 1),
      changed(after, (d) => d.effectSequence = before.rules.effectSequence - 1),
      changed(after, (d) {}, viewer: PieceColor.black),
    ]) {
      expect(acceptedBattleCasts(before, invalid), isEmpty);
    }
    final oldUsed = changed(before, (d) => d.used[PieceColor.white]!.add(CardId.radar));
    expect(acceptedBattleCasts(oldUsed, after), isEmpty,
      reason: 'A replaced history is not a new accepted cast');
    final terminal = changed(before, (d) => d.terminal = const TerminalState('resign'));
    expect(acceptedBattleCasts(terminal, after), isEmpty);
  });
  for (final card in [CardId.huntVow, CardId.watchVow]) {
    test('V216 duplicate ${card.wire} payoff identities are deduplicated', () {
      final pair = payoff(card);
      final duplicate = changed(pair.before, (d) => d.vows.add(d.vows.single));
      expect(acceptedBattleVowPayoffs(duplicate, pair.after),
        acceptedBattleVowPayoffs(pair.before, pair.after));
    });
  }
  test('V216 malformed and expired Watch Vow never invents a payoff', () {
    final pair = payoff(CardId.watchVow), vow = pair.before.rules.vows.single;
    for (final square in [-1, 64, 999999]) {
      final invalid = changed(pair.before, (d) => d.vows = [VowState(
        id: vow.id, type: vow.type, owner: vow.owner, pieceId: null,
        square: square, remainingMoves: 1)]);
      expect(acceptedBattleVowPayoffs(invalid, pair.after), isEmpty);
    }
    final expired = changed(pair.before, (d) => d.vows = [VowState(
      id: vow.id, type: vow.type, owner: vow.owner, pieceId: null,
      square: vow.square, remainingMoves: 0)]);
    expect(acceptedBattleVowPayoffs(expired, pair.after), isEmpty);
  });
  testWidgets('V216 public enemy Mine has a square visual and semantics', (tester) async {
    final pair = review.cast(CardId.mine);
    final before = pair.before.view(PieceColor.black), after = pair.after.view(PieceColor.black);
    expect(BattleSpellCue.fromViews(CardId.mine, PieceColor.white, before, after).squares, [21]);
    await tester.pumpWidget(shell(Center(child: SizedBox.square(dimension: 332,
      child: BattleBoard(view: before, onTap: (_) {})))));
    await tester.pumpWidget(shell(Center(child: SizedBox.square(dimension: 332,
      child: BattleBoard(view: after, onTap: (_) {})))));
    await tester.pump();
    await tester.pump(Duration(
      microseconds: battleEffectDuration(CardId.mine).inMicroseconds ~/ 2,
    ));
    final mine = after.rules.boardEffects.single;
    expect(find.byKey(ValueKey('effect-${mine.id}-21')), findsOneWidget);
    expect(find.byKey(const ValueKey('accepted-pulse-21')), findsOneWidget);
    expect(find.byKey(const ValueKey('impact-ring-21')), findsOneWidget);
    final squareSemantics = tester.widgetList<Semantics>(find.ancestor(
      of: find.byKey(const ValueKey('square-21')), matching: find.byType(Semantics)));
    expect(squareSemantics.any((s) => s.properties.label?.contains('Mayın') == true), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('V216 account switch closes private sheet and blocks resume', (tester) async {
    final store = GameStore.instance;
    await tester.runAsync(() async {
      await store.flush();
      await store.bindAccount('v216-safety-a');
    });
    await renderBattle(tester);
    await visualTap(tester, 'open-own-deck');
    expect(find.byType(OpponentArsenalSheet), findsOneWidget);
    expect(find.byType(BattleBoard), findsOneWidget);
    await tester.runAsync(() => store.bindAccount('v216-safety-b'));
    await tester.pumpAndSettle();
    expect(find.byType(BattleBoard), findsNothing);
    expect(find.byType(BattleAudioFeedback), findsNothing);
    expect(find.byType(OpponentArsenalSheet), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(BattleBoard), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('V216 late pending action cannot restore another account battle', (tester) async {
    final store = GameStore.instance;
    await tester.runAsync(() async {
      await store.flush();
      await store.bindAccount('v216-pending-a');
    });
    final hold = Completer<void>();
    final controller = await renderBattle(tester, hold: hold);
    final pass = find.byKey(const ValueKey('pass-card'));
    await tester.ensureVisible(pass);
    await tester.tap(pass);
    await tester.pump();
    await tester.pump();
    expect(controller.hasPendingIntent, isTrue);
    expect(controller.busy, isTrue);
    await tester.runAsync(() => store.bindAccount('v216-pending-b'));
    await tester.pumpAndSettle();
    expect(find.byType(BattleBoard), findsNothing);
    hold.complete();
    await tester.pumpAndSettle();
    expect(controller.busy, isFalse);
    expect(find.byType(BattleBoard), findsNothing);
    expect(find.byType(BattleAudioFeedback), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('V216 account switch closes narrow action instruction', (tester) async {
    final store = GameStore.instance;
    await tester.runAsync(() async {
      await store.flush();
      await store.bindAccount('v216-instruction-a');
    });
    await renderBattle(tester, size: const Size(320, 844), textScale: 1.5,
      theme: LunoTheme.darkFor('tr'));
    await visualTap(tester, 'battle-narrow-instruction');
    expect(find.byKey(const ValueKey('battle-next-action')), findsOneWidget);
    await tester.runAsync(() => store.bindAccount('v216-instruction-b'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('battle-next-action')), findsNothing);
    expect(find.byType(BattleBoard), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final language in ['tr', 'en']) {
    for (final width in [320.0, 390.0, 430.0, 768.0]) {
      testWidgets('V216 full hand and commands remain uncropped $language $width', (tester) async {
        await renderBattle(tester, size: Size(width, width == 768 ? 1024 : 844),
          language: language, textScale: 1.5, theme: LunoTheme.darkFor(language),
          state: battleFixture(hand: [CardId.shelter, CardId.chain, CardId.slow, CardId.freeze]));
        expect(find.byType(BattleCardTile), findsNWidgets(4));
        final command = find.byKey(const ValueKey('pass-card'));
        final commandTop = tester.getTopLeft(command).dy;
        for (final card in find.byType(BattleCardTile).evaluate()) {
          final rect = tester.getRect(find.byWidget(card.widget));
          expect(rect.bottom, lessThanOrEqualTo(commandTop),
            reason: 'The entire art and name must precede the fixed commands');
          expect(rect.top, greaterThanOrEqualTo(24));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
        }
        expect(tester.getSize(find.byType(BattleBoard)).width, greaterThanOrEqualTo(192));
        await visualTap(tester, 'hand-shelter');
        final mana = tester.widgetList<BattleMana>(find.byType(BattleMana))
          .singleWhere((m) => m.previewCost != null);
        expect(mana.previewCost, cardDefinitions[CardId.shelter]!.cost);
        expect(mana.value, 6, reason: 'Selection cannot spend mana');
        final play = find.byKey(const ValueKey('play-card'));
        expect(tester.getBottomRight(find.byType(BattleHand)).dy,
          lessThanOrEqualTo(tester.getTopLeft(play).dy));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
