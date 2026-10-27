import 'package:flutter/material.dart';
import '../battle_v1/model.dart';
import '../i18n/battle_learning_copy.dart';
import '../i18n/luno_localizations.dart';
import 'cards.dart';
import 'tokens.dart';
import 'primitives.dart';
import 'sheets.dart';

/// The same turn vocabulary is used in the live match and the teaching sandbox.
class BattleActionGuide extends StatelessWidget {
  final BattlePhase phase;
  final bool ownTurn, firstTurn;
  final String instruction;
  final CardId? selectedCard;
  final ValueChanged<String>? onInstruction;
  const BattleActionGuide({
    super.key,
    required this.phase,
    required this.ownTurn,
    required this.instruction,
    this.firstTurn = false,
    this.selectedCard,
    this.onInstruction,
  });

  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    final ended = phase == BattlePhase.terminal;
    final active = ownTurn && !ended;
    final cardDone = firstTurn || phase == BattlePhase.chess;
    final tight = BattleTokens.shortPortrait(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('battle-action-guide'),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: tight ? 2 : 7),
        decoration: BoxDecoration(
          color: BattleTokens.background.withValues(alpha: .9),
          border: Border(
            left: BorderSide(
              color: active ? BattleTokens.mana : BattleTokens.border,
              width: 3,
            ),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            if ((BattleTokens.sideDock(context) && box.maxWidth < 240) ||
                box.maxWidth < 120 ||
                (box.maxWidth < 180 && !BattleTokens.compactText(context))) {
              final phaseLabel =
                  ended
                      ? l.learning('Maç bitti', 'Match ended')
                      : !ownTurn
                      ? l.learning('Rakip oynuyor', "Opponent's turn")
                      : phase == BattlePhase.pending
                      ? l.learning('Seçimini yap', 'Make your choice')
                      : phase == BattlePhase.chess
                      ? l.learning('2 · Taş hamlesi', '2 · Chess move')
                      : l.learning('Kart / geç', 'Card / skip');
              final compactLabel =
                  ended
                      ? l.learning('Bitti', 'Ended')
                      : !ownTurn
                      ? l.learning('Rakip', 'Rival')
                      : phase == BattlePhase.pending
                      ? l.learning('Seçim', 'Choose')
                      : phase == BattlePhase.chess
                      ? l.learning('2\nHamle', '2\nMove')
                      : l.learning('1\nKart', '1\nCard');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    label: phaseLabel,
                    child: ExcludeSemantics(
                      child: Tooltip(
                        message: phaseLabel,
                        excludeFromSemantics: true,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            compactLabel,
                            key: const ValueKey('battle-compact-phase-label'),
                            maxLines: 2,
                            softWrap: false,
                            style: BattleTokens.caption.copyWith(
                              color:
                                  active
                                      ? BattleTokens.mana
                                      : BattleTokens.secondary,
                              fontSize: 12,
                              height: 1.15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (instruction.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    BattleIconControl(
                      key: const ValueKey('battle-narrow-instruction'),
                      icon: Icons.info_outline_rounded,
                      art: 'info',
                      label: instruction,
                      onPressed: () {
                        if (ModalRoute.of(context)?.isCurrent != true) return;
                        if (onInstruction != null) {
                          onInstruction!(instruction);
                          return;
                        }
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder:
                              (_) => BattleSheet(
                                title: l.learning(
                                  'Sıradaki hamlen',
                                  'Your next action',
                                ),
                                child: Text(
                                  instruction,
                                  key: const ValueKey('battle-next-action'),
                                  style: BattleTokens.body,
                                ),
                              ),
                        );
                      },
                    ),
                  ],
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _Step(
                        number: 1,
                        label: l.learning('Kart / geç', 'Card / skip'),
                        active: active && phase == BattlePhase.card,
                        done: active && cardDone,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: BattleTokens.disabled,
                      ),
                    ),
                    Expanded(
                      child: _Step(
                        number: 2,
                        label: l.learning('Taş hamlesi', 'Chess move'),
                        active: active && phase == BattlePhase.chess,
                        done: false,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: tight ? 2 : 4),
                if (instruction.isNotEmpty)
                  AnimatedSwitcher(
                    duration: BattleTokens.duration(context),
                    layoutBuilder:
                        (child, previous) => child ?? const SizedBox(),
                    transitionBuilder:
                        (child, animation) => FadeTransition(
                          opacity: Tween<double>(
                            begin: .7,
                            end: 1,
                          ).animate(animation),
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, .12),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                    child: Row(
                      key: ValueKey(instruction),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (selectedCard != null) ...[
                          SizedBox.square(
                            dimension: 24,
                            child: BattleCardArt(card: selectedCard!),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            instruction,
                            key: const ValueKey('battle-next-action'),
                            style: BattleTokens.body.copyWith(
                              color:
                                  active
                                      ? BattleTokens.ivory
                                      : BattleTokens.secondary,
                              fontSize: 13,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String label;
  final bool active, done;
  const _Step({
    required this.number,
    required this.label,
    required this.active,
    required this.done,
  });
  @override
  Widget build(BuildContext context) => AnimatedDefaultTextStyle(
    duration: BattleTokens.duration(context),
    style: BattleTokens.caption.copyWith(
      color:
          active
              ? BattleTokens.mana
              : done
              ? BattleTokens.success
              : BattleTokens.disabled,
    ),
    child: Row(
      children: [
        SizedBox.square(
          dimension: 18,
          child: Center(
            child:
                done
                    ? const Icon(
                      Icons.check_rounded,
                      color: BattleTokens.success,
                      size: 16,
                    )
                    : Text('$number', textScaler: TextScaler.noScaling),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(child: Text(label)),
      ],
    ),
  );
}
