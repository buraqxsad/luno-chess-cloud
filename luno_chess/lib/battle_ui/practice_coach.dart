import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../battle_v1/core.dart';
import '../battle_v1/model.dart';
import '../battle_v1/practice.dart';
import '../i18n/battle_learning_copy.dart';
import '../i18n/battle_v1_copy.dart';
import '../i18n/luno_localizations.dart';
import '../engine/square.dart';
import '../engine/piece.dart';
import '../engine/move_gen.dart';
import 'interaction.dart';
import 'tokens.dart';
import '../widgets/tutorial_coach.dart';

enum BattleCoachFocus { board, hand, controls, none }

int? battlePracticeBoardSquare(
  PlayerView view,
  BattleInteraction selection,
  List<BattleAction> actions,
) {
  final targets = selection.targets(view, actions);
  if (targets.isNotEmpty) {
    final suggested = battlePracticeCardTarget(view, selection.card, actions);
    return suggested != null && targets.contains(suggested)
        ? suggested
        : targets.first;
  }
  final moves = selection.moves(view, actions);
  if (moves.isEmpty) return null;
  final preferred = moves.where((m) => m.uci.startsWith('e2')).firstOrNull;
  final uci = (preferred ?? moves.first).uci;
  return Square.of(uci.codeUnitAt(0) - 97, int.parse(uci[1]) - 1);
}

/// Suggestions use public board information and admitted card targets only.
/// They never execute a move or constrain the learner to the suggested square.
int? battlePracticeCardTarget(
  PlayerView view,
  CardId? card,
  List<BattleAction> actions,
) {
  if (card != CardId.shelter && card != CardId.freeze) return null;
  final candidates =
      actions
          .whereType<PlayCardAction>()
          .where((a) => a.card == card)
          .map((a) => a.target)
          .whereType<int>()
          .toSet();
  if (candidates.isEmpty) return null;
  final enemyMoves =
      card == CardId.freeze
          ? BattleRulesCore.legalMoves(view.rules, view.viewer.opposite)
          : null;
  int score(int square) {
    final piece = view.rules.board.pieceAt(square)!;
    if (card == CardId.shelter) {
      final sheltered = view.rules.pieceEffects.any(
        (e) =>
            e.pieceId == view.rules.pieceIds[square] &&
            e.type == PieceEffectType.shelter,
      );
      final advance =
          view.viewer == PieceColor.white
              ? Square.rankOf(square)
              : 7 - Square.rankOf(square);
      return (sheltered ? -1000 : 0) + advance * 10 + piece.type.index;
    }
    final moves = enemyMoves!.where((m) => m.from == square);
    final captures = moves.where(
      (m) =>
          view.rules.board.pieceAt(m.to)?.color == view.viewer || m.isEnPassant,
    );
    return captures.length * 100 + moves.length * 10 + piece.type.index;
  }

  final ordered =
      candidates.toList()..sort((a, b) {
        final comparison = score(b).compareTo(score(a));
        return comparison != 0 ? comparison : a.compareTo(b);
      });
  return ordered.first;
}

BattleCoachFocus practiceFocus(
  BattlePracticeProgress p,
  PlayerView v,
  CardId? selected,
  bool targetReady,
) {
  if (p.complete) return BattleCoachFocus.none;
  if (v.rules.board.turn != v.viewer) {
    return BattleCoachFocus.none;
  }
  if (v.rules.pending != null) return BattleCoachFocus.controls;
  if (p.guidedMatch) {
    if (v.rules.phase == BattlePhase.chess) return BattleCoachFocus.board;
    if (p.cast && !p.discarded) {
      return selected == null
          ? BattleCoachFocus.hand
          : BattleCoachFocus.controls;
    }
    if (p.cast && p.discarded && !p.passed) return BattleCoachFocus.controls;
    if (selected != null) {
      if (targetReady) return BattleCoachFocus.controls;
      return BattleRulesCore.legalActions(v).whereType<PlayCardAction>().any(
            (a) => a.card == selected && a.target is int,
          )
          ? BattleCoachFocus.board
          : BattleCoachFocus.controls;
    }
    return p.moves > 0 && (!p.cast || !p.discarded)
        ? BattleCoachFocus.hand
        : BattleCoachFocus.board;
  }
  if (p.complete) return BattleCoachFocus.none;
  if (p.freePlay) return BattleCoachFocus.none;
  if (v.rules.phase == BattlePhase.chess) return BattleCoachFocus.board;
  if (!p.cast) {
    final playable = BattleRulesCore.legalActions(
      v,
    ).whereType<PlayCardAction>().any((a) => a.card == p.card);
    if (!playable) {
      return selected == null
          ? BattleCoachFocus.board
          : BattleCoachFocus.controls;
    }
    if (selected != p.card) return BattleCoachFocus.hand;
    return targetReady ? BattleCoachFocus.controls : BattleCoachFocus.board;
  }
  if (!p.discarded) {
    return selected == null ? BattleCoachFocus.hand : BattleCoachFocus.controls;
  }
  return BattleCoachFocus.board;
}

class BattlePracticeCoach extends StatelessWidget {
  final BattlePracticeProgress progress;
  final PlayerView view;
  final CardId? selected;
  final bool targetReady;
  final int? selectedPiece;
  final bool invalidTarget;
  final String? freeInstruction;
  final VoidCallback? onComplete;
  const BattlePracticeCoach({
    super.key,
    required this.progress,
    required this.view,
    this.selected,
    this.targetReady = false,
    this.selectedPiece,
    this.invalidTarget = false,
    this.freeInstruction,
    this.onComplete,
  });
  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context), p = progress;
    final legal = BattleRulesCore.legalActions(view);
    final playable = legal.whereType<PlayCardAction>().any(
      (a) => a.card == p.card,
    );
    final suggestedTarget = battlePracticeCardTarget(view, p.card, legal);
    final playGoalLabel =
        p.guidedMatch
            ? l.learning('Hedefli kart', 'Target a card')
            : l.battleCardName(p.card);
    final blockedPiece =
        selected == null &&
        selectedPiece != null &&
        view.rules.phase == BattlePhase.chess &&
        view.rules.board.pieceAt(selectedPiece!)?.color == view.viewer &&
        !legal.whereType<ChessMoveAction>().any(
          (move) => move.uci.startsWith(Square.algebraic(selectedPiece!)),
        );
    final text =
        p.canFinish(view) &&
                (!p.freePlay ||
                    (selected == null && view.rules.pending == null))
            ? p.guidedMatch
                ? l.learning(
                  p.complete
                      ? 'Temeller tamam! Taş oynattın, hedefli kart kullandın, feda ettin ve kart pasını denedin. Maçı kazanmak gerekmiyor; hazır olduğunda devam edebilirsin.'
                      : 'Bu deneme bitti. Menüden yeniden başlayabilir veya şimdilik geçebilirsin. Rehberde tekrar buluşabiliriz.',
                  p.complete
                      ? 'Basics complete! You moved, targeted a card, discarded and tried a card pass. No win is required; continue when ready.'
                      : 'This attempt ended. Restart from the menu or skip for now. We can meet again in the Guide.',
                )
                : l.learning(
                  p.freePlay && view.rules.terminal != null
                      ? 'Bu deneme bitti. Hazırsan kendi maçına geçelim; öğrendiklerini orada kullanabilirsin.'
                      : p.freePlay
                      ? 'Kontrol sende! İstersen denemeye devam et. Hazırsan kendi maçına geçelim.'
                      : 'Harika! Kartı kullandın, feda ettin ve taş hamlelerini yaptın. Sıradaki denemeye hazırsın.',
                  p.freePlay && view.rules.terminal != null
                      ? 'This practice has ended. When you are ready, start your own match and use what you learned.'
                      : p.freePlay
                      ? 'You are in control! Keep practising if you like, or start your own match when you are ready.'
                      : 'Great! You played a card, discarded and moved your pieces. Ready for the next practice.',
                )
            : view.rules.board.turn != view.viewer
            ? l.learning(
              'Şimdi ${p.level.name} oynuyor. Ben yanındayım; sıra sana gelince devam edeceğiz.',
              '${l.translate(p.level.name)} is playing. I am here; we will continue on your turn.',
            )
            : view.rules.pending != null
            ? l.battlePendingChoiceInstruction(view.rules.pending!.card)
            : view.rules.special != null
            ? l.learning(
              '${Square.algebraic(view.rules.special!.from)} karesindeki işaretli taşla devam et. Başka taş seçemezsin.',
              'Move the marked piece on ${Square.algebraic(view.rules.special!.from)}. Do not switch pieces.',
            )
            : blockedPiece
            ? l.learning(
              'Bu taşın şu anda yasal hamlesi yok. Başka taşını seç; hamle hakkın duruyor.',
              'This piece has no legal move right now. Choose another piece; you still have your move.',
            )
            : invalidTarget
            ? l.learning(
              'Bu kare uygun değil. İşaretli yasal hedeflerden birini seç; hamle hakkın duruyor.',
              'That square is not valid. Choose a marked legal target; you still have your move.',
            )
            : p.guidedMatch
            ? _guidedInstruction(l, p, view, legal)
            : p.freePlay
            ? freeInstruction ??
                l.learning(
                  view.rules.phase == BattlePhase.chess
                      ? view.rules.ownTurns[view.viewer] == 1
                          ? 'Bu kez kontrol sende! İlk tur sadece taş hamlesi yap. Sonraki turlarda kart seçimin de serbest.'
                          : 'Bu kez kararlar sende. Bir taşını seçip işaretli yasal kareye git.'
                      : 'İstediğin yasal kartı oyna, bir kartı feda et veya kart kullanmadan taşını oynat.',
                  view.rules.phase == BattlePhase.chess
                      ? view.rules.ownTurns[view.viewer] == 1
                          ? 'You are in control! Turn one is chess only. On later turns your card choice is free too.'
                          : 'Your decisions now. Choose a piece and a marked legal square.'
                      : 'Play any legal card, discard a card, or move a piece without using a card.',
                )
            : view.rules.ownTurns[view.viewer] == 1
            ? l.learning(
              p.stage == 0
                  ? selectedPiece == null
                      ? 'Ben Luno! İlk tur kart yok. İstediğin beyaz taşı seç.'
                      : 'Işıklı kareler yasal hamlelerin. Birine dokun; sonra destenden yeni kart gelecek.'
                  : 'İlk taş hamleni sen seç. Sonra ${l.battleCardName(p.card)} kartını birlikte deneyeceğiz.',
              p.stage == 0
                  ? selectedPiece == null
                      ? 'I am Luno! No card on turn one. Tap any white piece.'
                      : 'The lit squares are legal moves. Tap one; a new card comes from your deck afterwards.'
                  : 'Choose your opening chess move. Then we will try ${l.battleCardName(p.card)} together.',
            )
            : !p.cast && !playable
            ? _unavailableInstruction(l, p, view, selected != null)
            : !p.cast && selected != p.card
            ? l.learning(
              'Bu eğitim adımında ${l.battleCardName(p.card)} kartını deniyoruz. Kartına dokun; sol üstteki sayı mana bedeli.',
              'For this lesson, we are trying ${l.battleCardName(p.card)}. Tap it; the top-left number is its mana cost.',
            )
            : !p.cast && !targetReady
            ? _targetInstruction(l, p.card, suggestedTarget)
            : !p.cast
            ? l.learning(
              '${l.battleCardName(p.card)} hazır! Kartı Oyna ile onayla. Karttan sonra taş hamlen yine sende.',
              '${l.battleCardName(p.card)} is ready! Confirm with Play Card. You still make a chess move after the card.',
            )
            : view.rules.phase == BattlePhase.chess
            ? _afterCardInstruction(l, p, view)
            : !p.discarded
            ? l.learning(
              'Şimdi bir kart seçip Feda Et. Mana kazanmazsın; elinde yer açılır. Sonra yine taşını oynatabilirsin.',
              'Now choose a card and Discard it. It gives no mana; it makes hand space. You still move a piece afterwards.',
            )
            : l.learning(
              'Artık kart seçimin de serbest. Kart oyna, feda et veya kart kullanmadan taş hamleni yap.',
              'Your card choice is free now too. Play, discard, or make your chess move without a card.',
            );
    return Semantics(
      liveRegion: true,
      child: Padding(
        key: const ValueKey('practice-coach'),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TutorialCoach(
              text: text,
              cue: text,
              heading: l.learning(
                p.onboarding
                    ? p.guidedMatch
                        ? 'LUNO · İLK MAÇIN'
                        : 'LUNO · ${p.freePlay ? 'SERBEST' : 'ANTRENMAN'} ${p.stage + 1}/3'
                    : 'LUNO · BİRLİKTE ÖĞRENELİM',
                p.onboarding
                    ? p.guidedMatch
                        ? 'LUNO · YOUR FIRST MATCH'
                        : 'LUNO · ${p.freePlay ? 'FREE PLAY' : 'PRACTICE'} ${p.stage + 1}/3'
                    : 'LUNO · LET US LEARN',
              ),
              feedback: invalidTarget,
            ),
            if (p.onboarding &&
                (!p.guidedMatch ||
                    (selected == null && view.rules.pending == null)))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  key: const ValueKey('practice-goals'),
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (!p.freePlay)
                      _goal(
                        playGoalLabel,
                        p.cast,
                        key: const ValueKey('practice-goal-play'),
                        semanticsLabel:
                            '$playGoalLabel: ${l.learning(p.cast ? 'tamamlandı' : 'bekliyor', p.cast ? 'complete' : 'pending')}',
                      ),
                    if (!p.freePlay)
                      _goal(
                        l.learning('Feda', 'Discard'),
                        p.discarded,
                        key: const ValueKey('practice-goal-discard'),
                        semanticsLabel: l.learning(
                          p.discarded ? 'Feda: tamamlandı' : 'Feda: bekliyor',
                          p.discarded
                              ? 'Discard: complete'
                              : 'Discard: pending',
                        ),
                      ),
                    if (p.guidedMatch)
                      _goal(
                        l.learning('Kart pası', 'Card pass'),
                        p.passed,
                        key: const ValueKey('practice-goal-pass'),
                      ),
                    _goal(
                      p.freePlay && view.rules.terminal != null
                          ? l.learning('Deneme tamamlandı', 'Practice complete')
                          : '${p.moves.clamp(0, 4)}/4 ${l.learning('hamle', 'moves')}',
                      p.moves >= 4 ||
                          (p.freePlay && view.rules.terminal != null),
                      key: const ValueKey('practice-goal-moves'),
                    ),
                  ],
                ),
              ),
            if (!p.onboarding)
              Padding(
                padding: const EdgeInsets.only(left: 64, top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l.learning(
                        'ANTRENMAN ${p.stage + 1}/${p.onboarding ? 3 : 4} · ${p.level.name}',
                        'PRACTICE ${p.stage + 1}/${p.onboarding ? 3 : 4} · ${l.translate(p.level.name)}',
                      ),
                      style: BattleTokens.caption.copyWith(
                        color: BattleTokens.gold,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (!p.freePlay)
                          _goal(l.learning('Kart', 'Card'), p.cast),
                        if (!p.freePlay)
                          _goal(l.learning('Feda', 'Discard'), p.discarded),
                        Text(
                          '${p.moves.clamp(0, 4)}/4 ${l.learning('hamle', 'moves')}',
                          style: BattleTokens.caption,
                        ),
                      ],
                    ),
                    if (p.complete && !p.onboarding)
                      TextButton.icon(
                        key: const ValueKey('practice-next'),
                        onPressed: onComplete,
                        icon: const Icon(Icons.arrow_forward, size: 20),
                        label: Text(
                          l.learning(
                            p.stage < (p.onboarding ? 2 : 3)
                                ? 'Sonraki antrenman'
                                : 'Hazırım, oyuna geç',
                            p.stage < (p.onboarding ? 2 : 3)
                                ? 'Next practice'
                                : 'Ready, let us play',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _targetInstruction(LunoLocalizations l, CardId card, int? square) {
    final example =
        square == null
            ? ''
            : l.learning(
              ' Örneğin ${Square.algebraic(square)}. Başka işaretli taşı da seçebilirsin.',
              ' For example ${Square.algebraic(square)}. You can choose another marked piece too.',
            );
    return switch (card) {
      CardId.shelter => l.learning(
        'Siper, hedefli kartlardan korur; satrançta taş alınmasını engellemez.$example',
        'Shelter blocks targeted cards, not chess captures.$example',
      ),
      CardId.freeze => l.learning(
        'Dondurma, rakibin bu tur o taşı oynatmasını engeller.$example',
        'Freeze prevents it moving on the opponent turn.$example',
      ),
      _ => l.learning(
        'İşaretli bir hedef seç. Kartın bilgisine dokunarak etkisini de okuyabilirsin.',
        'Choose a marked target. Tap the card information to read its effect.',
      ),
    };
  }

  String _afterCardInstruction(
    LunoLocalizations l,
    BattlePracticeProgress p,
    PlayerView view,
  ) {
    final card = switch (p.lastAction) {
      PlayCardAction(:final card) => card,
      _ => p.card,
    };
    final type =
        card == CardId.shelter
            ? PieceEffectType.shelter
            : card == CardId.freeze
            ? PieceEffectType.freeze
            : null;
    final effect =
        view.rules.pieceEffects
            .where((e) => e.type == type && e.owner == view.viewer)
            .firstOrNull;
    final square =
        effect == null ? -1 : view.rules.pieceIds.indexOf(effect.pieceId);
    final active =
        square < 0
            ? ''
            : l.learning(
              '${Square.algebraic(square)} üzerindeki ${l.battleCardName(card)} etkisini görüyor musun? ',
              'See the ${l.battleCardName(card)} effect on ${Square.algebraic(square)}? ',
            );
    if (p.guidedMatch) {
      if (p.lastAction is DiscardAction) {
        return l.learning(
          'Feda tamam, mana değişmedi. Şimdi taş hamleni yap.',
          'Discard complete, mana unchanged. Now make your chess move.',
        );
      }
      return l.learning(
        square >= 0
            ? '${l.battleCardName(card)} ${Square.algebraic(square)} üzerinde etkin! Şimdi taş hamleni yap.'
            : 'Kart tamam! Şimdi taş hamleni yap.',
        square >= 0
            ? '${l.battleCardName(card)} is active on ${Square.algebraic(square)}! Now make your chess move.'
            : 'Card complete! Now make your chess move.',
      );
    }
    return l.learning(
      '${p.lastAction is DiscardAction ? 'Feda tamam; mana değişmedi. ' : active}Hamle hakkın duruyor. Hangi taşını oynatacağın sana kalmış.',
      '${p.lastAction is DiscardAction ? 'Discard complete; mana did not change. ' : active}You still have your move. The piece you move is your choice.',
    );
  }

  String _guidedInstruction(
    LunoLocalizations l,
    BattlePracticeProgress p,
    PlayerView v,
    List<BattleAction> legal,
  ) {
    if (v.rules.ownTurns[v.viewer] == 1) {
      return l.learning(
        selectedPiece == null
            ? 'Yanındayım! İlk tur kart yok. Beyaz taşını, sonra ışıklı kareyi seç.'
            : 'Işıklı kareler yasal hamlelerin. Birini seç; hamlenden sonra destenden bir kart gelecek.',
        selectedPiece == null
            ? 'I am here! No cards on turn one. Choose a white piece, then a lit square.'
            : 'The lit squares are legal moves. Choose one; a card comes from your deck after your move.',
      );
    }
    if (v.rules.phase == BattlePhase.card && p.cast && !p.discarded) {
      return l.learning(
        selected == null
            ? 'Şimdi elindeki bir karta dokun; Feda Et ile elinde yer açmayı deneyelim. Mana kazanmazsın, taş hamlen sende kalır.'
            : 'Feda Et düğmesine dokun. Bu kart gider, mana değişmez; ardından taşını oynatırsın.',
        selected == null
            ? 'Tap a hand card. Let us try Discard to make space. It grants no mana; you keep your chess move.'
            : 'Tap Discard. This card leaves, mana stays the same; then move a piece.',
      );
    }
    if (v.rules.phase == BattlePhase.card &&
        p.cast &&
        p.discarded &&
        !p.passed) {
      return l.learning(
        selected == null
            ? 'Bu tur kart kullanmayalım. ${l.battle(BattleCopy.pass)} düğmesine dokun, sonra taş hamleni yap. Yalnızca kart seçimini geçersin; sıran bitmez.'
            : 'X ile kart seçimini kapat. Sonra ${l.battle(BattleCopy.pass)} düğmesini dene; taş hamlen yine sende.',
        selected == null
            ? 'Let us use no card this turn. Tap ${l.battle(BattleCopy.pass)}, then move a piece. Only the card choice is skipped; your turn is not over.'
            : 'Close the card with X, then try ${l.battle(BattleCopy.pass)}. You still make your chess move.',
      );
    }
    if (selected case final card?) {
      final choices = legal.whereType<PlayCardAction>().where(
        (a) => a.card == card,
      );
      if (choices.isEmpty) {
        return freeInstruction ?? _unavailableInstruction(l, p, v, true);
      }
      if (targetReady) {
        final cost = BattleRulesCore.effectiveCost(v.rules, v.viewer, card);
        return l.learning(
          '${l.battleCardName(card)}: $cost mana. Kartı Oyna; ardından taş hamleni tamamla.',
          '${l.battleCardName(card)}: $cost mana. Tap Play Card, then make your chess move.',
        );
      }
      if (card == CardId.shelter || card == CardId.freeze) {
        final target = battlePracticeCardTarget(v, card, legal);
        final example =
            target == null
                ? ''
                : l.learning(
                  ' Örneğin ${Square.algebraic(target)}.',
                  ' For example ${Square.algebraic(target)}.',
                );
        return card == CardId.shelter
            ? l.learning(
              'Korumak istediğin işaretli taşını seç.$example',
              'Choose a marked piece to protect.$example',
            )
            : l.learning(
              'Dondurmak istediğin işaretli rakip taşını seç.$example',
              'Choose a marked opponent piece to Freeze.$example',
            );
      }
      return '${l.battleCardShortDescription(card)} ${freeInstruction ?? ''}'
          .trim();
    }
    if (MoveGen.inCheck(v.rules.board, v.viewer)) {
      return l.learning(
        'Şah! Şahını güvende bırakacak yasal bir hamle seç. İşaretli kareler sana yardım edecek.',
        'Check! Choose a legal move that leaves your king safe. The marked squares will help.',
      );
    }
    if (v.rules.phase == BattlePhase.chess) {
      if (p.lastAction is DiscardAction || p.lastAction is PlayCardAction) {
        return _afterCardInstruction(l, p, v);
      }
      return freeInstruction ??
          l.learning(
            'Şimdi taşını oynat. Hangi hamleyi yapacağın sana kalmış.',
            'Now move a piece. The move is your choice.',
          );
    }
    if (!p.cast &&
        legal.whereType<PlayCardAction>().any((a) => a.card == p.card)) {
      return l.learning(
        'Siper hedefli kartları engeller, taş alınmasını engellemez. Kartına dokun.',
        'Shelter blocks targeted cards, not chess captures. Tap it to try.',
      );
    }
    if (p.cast && !p.discarded && legal.any((a) => a is DiscardAction)) {
      return l.learning(
        'Elinde yer açmak ister misin? Bir kart seçip Feda Et. Mana kazanmazsın; ardından taş hamlen yine sende.',
        'Want to make hand space? Choose a card and Discard it. No mana is gained; you still make your chess move.',
      );
    }
    final freezeTarget = battlePracticeCardTarget(v, CardId.freeze, legal);
    if (freezeTarget != null &&
        BattleRulesCore.legalMoves(
          v.rules,
          v.viewer.opposite,
        ).any((move) => move.from == freezeTarget)) {
      return l.learning(
        'Bak, ${Square.algebraic(freezeTarget)} üzerindeki rakip taşı hareket edebiliyor. Dondurma ile sıradaki hareketini durdurmayı deneyebilirsin.',
        'Look, the opponent piece on ${Square.algebraic(freezeTarget)} can move. You could try Freeze to stop its next move.',
      );
    }
    if (v.ownHand.isNotEmpty && !legal.any((a) => a is PlayCardAction)) {
      return l.learning(
        'Şu an oynanabilir kart yok. Bir kartı feda edebilir veya doğrudan taşını oynatabilirsin; mana en fazla 6 birikir.',
        'No card can be played right now. Discard one or move a piece directly; mana builds up to 6.',
      );
    }
    return freeInstruction ??
        l.learning(
          'Kart oyna, feda et veya doğrudan taş hamleni yap. Karar sende; kartın bilgi düğmesinden ayrıntılarını okuyabilirsin.',
          'Play, discard or move a piece directly. Your choice; use a card info button for details.',
        );
  }

  String _unavailableInstruction(
    LunoLocalizations l,
    BattlePracticeProgress p,
    PlayerView view,
    bool selected,
  ) {
    final name = l.battleCardName(p.card);
    final close =
        selected
            ? l.learning('X ile kartı kapat. ', 'Close the card with X. ')
            : '';
    if (!view.ownHand.contains(p.card)) {
      if (view.rules.deckCounts[view.viewer] == 0) {
        return l.learning(
          'Bu denemede $name kalmadı. ${close}Menüden antrenmanı yeniden başlatıp birlikte deneyebiliriz.',
          'There is no $name left in this practice. ${close}Restart practice from the menu and we can try it together.',
        );
      }
      return l.learning(
        '$name henüz elinde değil. ${close}Taş hamleni sen seç; desteden yeni kart geldikçe elin yenilenir.',
        '$name is not in your hand yet. ${close}Choose your chess move; cards from your deck refill your hand.',
      );
    }
    if (BattleRulesCore.effectiveCost(view.rules, view.viewer, p.card) >
        view.rules.mana[view.viewer]!) {
      return l.learning(
        'Sıran geldiğinde mana artar, en fazla 6 olur. $name için biraz daha biriktirelim. ${close}Taş hamleni sen seç.',
        'Mana grows on your turn, up to 6. Let us save a little more for $name. ${close}Choose your chess move.',
      );
    }
    return l.learning(
      '$name şu anda oynanamıyor. ${close}Taş hamleni sen seç; kartı sonraki tur yeniden deneyebiliriz.',
      '$name cannot be played right now. ${close}Choose your chess move; we can try the card again next turn.',
    );
  }

  Widget _goal(String label, bool done, {Key? key, String? semanticsLabel}) =>
      Semantics(
        key: key,
        label: semanticsLabel,
        excludeSemantics: semanticsLabel != null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              done ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 14,
              color: done ? BattleTokens.mana : BattleTokens.secondary,
            ),
            const SizedBox(width: 3),
            Text(label, style: BattleTokens.caption),
          ],
        ),
      );
}

/// A persistent marker points at the actual interactive area, never a screenshot.
class BattleCoachTarget extends StatelessWidget {
  final bool active;
  final Widget child;
  final Alignment? arrowPosition;
  const BattleCoachTarget({
    super.key,
    required this.active,
    required this.child,
    this.arrowPosition,
  });
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    clipBehavior: Clip.none,
    children: [
      child,
      if (active)
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: BattleTokens.gold, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      if (active)
        Positioned(
          top: arrowPosition == null ? -7 : 0,
          left: arrowPosition == null ? 3 : 0,
          right: arrowPosition == null ? null : 0,
          bottom: arrowPosition == null ? null : 0,
          child: IgnorePointer(
            child: Align(
              alignment: arrowPosition ?? Alignment.topLeft,
              widthFactor: arrowPosition == null ? 1 : null,
              heightFactor: arrowPosition == null ? 1 : null,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration:
                    MediaQuery.disableAnimationsOf(context) ||
                            !TickerMode.valuesOf(context).enabled
                        ? Duration.zero
                        : const Duration(milliseconds: 1800),
                builder:
                    (_, t, child) => Transform.translate(
                      offset: Offset(
                        0,
                        -5 * math.sin(t * math.pi * 6) * (1 - t),
                      ),
                      child: child,
                    ),
                child: const Icon(
                  Icons.arrow_downward,
                  size: 24,
                  color: BattleTokens.gold,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
