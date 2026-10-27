import 'package:flutter/material.dart';
import '../theme/luno_visual_assets.dart';
import '../widgets/luno_polish.dart';
import '../battle_v1/core.dart';
import '../battle_v1/model.dart';
import '../engine/piece.dart';
import '../i18n/battle_v1_copy.dart';
import '../i18n/luno_localizations.dart';
import 'art.dart';
import 'cards.dart';
import 'primitives.dart';
import 'tokens.dart';

void dismissBattleSheet<T>(BuildContext context, [T? result]) {
  if (!context.mounted || ModalRoute.of(context)?.isCurrent != true) return;
  Navigator.of(context).pop<T>(result);
}

class BattleSheet extends StatelessWidget {
  final String title;
  final Widget child;
  const BattleSheet({super.key, required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Material(
    color: BattleTokens.background,
    child: Container(
      decoration: BoxDecoration(
        image: lunoFace(LunoVisualAssets.neutral, opacity: .6),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: BattleTokens.title)),
                  BattleIconControl(
                    icon: Icons.close,
                    art: 'close',
                    label: LunoLocalizations.of(
                      context,
                    ).battle(BattleCopy.close),
                    onPressed: () => dismissBattleSheet(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      ),
    ),
  );
}

class CardDetailSheet extends StatelessWidget {
  final CardId card;
  final PlayerView view;
  const CardDetailSheet({super.key, required this.card, required this.view});
  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context),
        definition = cardDefinitions[card]!;
    final cost = BattleRulesCore.effectiveCost(view.rules, view.viewer, card);
    final explanation = l.battleCardExplanation(card);
    return BattleSheet(
      title: l.battleCardName(card),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 110, child: BattleCardArt(card: card)),
          Text(
            '${l.battleRarity(definition.rarity)} · ${l.battle(BattleCopy.mana)} $cost',
            style: BattleTokens.body,
          ),
          if (cost != definition.cost)
            Text(
              l.isEnglish
                  ? 'Base cost: ${definition.cost} mana'
                  : 'Temel bedel: ${definition.cost} mana',
              style: BattleTokens.caption,
            ),
          const SizedBox(height: 12),
          for (final section in [
            (l.battleCardSelectionLabel, explanation.selection),
            (l.battleCardEffectLabel, explanation.effect),
            (l.battleCardDurationLabel, explanation.duration),
            (l.battleCardCautionLabel, explanation.caution),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    section.$1,
                    style: BattleTokens.card.copyWith(color: BattleTokens.mana),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    section.$2,
                    style: BattleTokens.body.copyWith(height: 1.4),
                  ),
                ],
              ),
            ),
          for (final modifier in view.rules.modifiers.where(
            (m) =>
                m.responseSide == view.viewer &&
                (m.targetCard == card || m.targetCard == null),
          ))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const BattleArt('phase-card', size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.battleCardName(switch (modifier.type) {
                        ModifierType.cardBlock => CardId.cardBlock,
                        ModifierType.manaSabotage => CardId.manaSabotage,
                        ModifierType.echo => CardId.echo,
                        ModifierType.discount => CardId.shadowContract,
                      }),
                      style: BattleTokens.body,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class OpponentArsenalSheet extends StatelessWidget {
  final bool own;
  final RuleState rules;
  final PieceColor opponent;
  final Set<CardId> eligible;
  final Set<CardId> ownHand;
  const OpponentArsenalSheet({
    super.key,
    required this.rules,
    required this.opponent,
    this.eligible = const {},
    this.ownHand = const {},
    this.own = false,
  });
  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    return BattleSheet(
      title:
          '${own ? (l.locale.languageCode == 'en' ? 'My Cards' : 'Kartlarım') : l.battle(BattleCopy.arsenal)} · ${rules.arsenals[opponent]!.length}',
      child: Column(
        children: [
          for (final card in rules.arsenals[opponent]!)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: BattleSkin(
                name: 'command-panel',
                child: InkWell(
                  key: ValueKey('arsenal-${card.wire}'),
                  onTap:
                      eligible.contains(card)
                          ? () => dismissBattleSheet(context, card)
                          : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        SizedBox.square(
                          dimension: 34,
                          child: BattleCardArt(card: card),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l.battleCardName(card),
                                style: BattleTokens.card,
                              ),
                              Text(
                                own && ownHand.contains(card)
                                    ? (l.locale.languageCode == 'en'
                                        ? 'In your hand'
                                        : 'Elinde')
                                    : l.battle(
                                      rules.used[opponent]!.contains(card)
                                          ? BattleCopy.used
                                          : rules.discarded[opponent]!.contains(
                                            card,
                                          )
                                          ? BattleCopy.discarded
                                          : BattleCopy.unused,
                                    ),
                                style: BattleTokens.body,
                              ),
                              BattleModifierMarks(
                                modifiers:
                                    rules.modifiers
                                        .where(
                                          (m) =>
                                              m.responseSide == opponent &&
                                              (m.targetCard == null ||
                                                  m.targetCard == card),
                                        )
                                        .toList(),
                              ),
                            ],
                          ),
                        ),
                        if (eligible.contains(card))
                          const BattleArt('confirm', size: 22),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class BattleActionChoices extends StatelessWidget {
  final String title;
  final List<BattleAction> actions;
  final String Function(BattleAction) label;
  final String pieceSet;
  final PieceColor pieceSide;
  const BattleActionChoices({
    super.key,
    required this.title,
    required this.actions,
    required this.label,
    this.pieceSet = 'luno',
    this.pieceSide = PieceColor.white,
  });
  PieceType? _promotion(BattleAction action) =>
      action is ChessMoveAction && action.uci.length == 5
          ? switch (action.uci[4]) {
            'q' => PieceType.queen,
            'r' => PieceType.rook,
            'b' => PieceType.bishop,
            'n' => PieceType.knight,
            _ => null,
          }
          : null;
  @override
  Widget build(BuildContext context) => BattleSheet(
    title: title,
    child: Column(
      children: [
        for (final action in actions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                if (_promotion(action) case final type?)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Image.asset(
                      BattleArt.piecePath(pieceSide, type, set: pieceSet),
                      width: 40,
                      height: 40,
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                    ),
                  ),
                Expanded(
                  child: BattleCommand(
                    key: ValueKey(action.key),
                    label: label(action),
                    icon: Icons.check,
                    art: 'confirm',
                    onPressed: () => dismissBattleSheet(context, action),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
