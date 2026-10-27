import 'package:flutter/material.dart';
import '../battle_v1/model.dart';
import '../i18n/battle_v1_copy.dart';
import '../i18n/luno_localizations.dart';
import '../i18n/battle_learning_copy.dart';
import 'art.dart';
import 'cards.dart';
import 'primitives.dart';
import 'sheets.dart';
import 'tokens.dart';

class PrivateChoiceSheet extends StatefulWidget {
  final PlayerView view;
  final List<ResolveAction> actions;
  final void Function(CardId card, Rect bounds)? onTakeOrigin;
  const PrivateChoiceSheet({
    super.key,
    required this.view,
    required this.actions,
    this.onTakeOrigin,
  });
  @override
  State<PrivateChoiceSheet> createState() => _PrivateChoiceSheetState();
}

class _PrivateChoiceSheetState extends State<PrivateChoiceSheet> {
  late List<CardId> order = [...widget.view.knowledge.pendingCards];
  CardId? taken;
  final _cardOrigins = <CardId, GlobalKey>{};
  bool get fate => widget.view.rules.pending?.card == CardId.fateExchange;
  bool get _active => mounted && ModalRoute.of(context)?.isCurrent == true;
  void shift(int index, int delta) {
    if (!_active || index < 0 || index >= order.length) return;
    final other = index + delta;
    if (other < 0 || other >= order.length) return;
    setState(() {
      final item = order.removeAt(index);
      order.insert(other, item);
    });
  }

  ResolveAction? get choice {
    final remainder = order.where((c) => c != taken).toList();
    for (final action in widget.actions) {
      if (action.selected == taken &&
          action.order.map((c) => c.wire).join(',') ==
              remainder.map((c) => c.wire).join(',')) {
        return action;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    if (widget.view.rules.pending?.owner != widget.view.viewer) {
      return const SizedBox.shrink();
    }
    return BattleSheet(
      title: l.battleCardName(widget.view.rules.pending!.card),
      child: Column(
        children: [
          Text(
            fate
                ? l.learning(
                  'Bir kartı eline al; kalanların deste sırasını belirle.',
                  'Take one card into your hand; order the rest back into the deck.',
                )
                : l.learning(
                  'Destenin üstünü inceliyorsun. Sırayı belirle; bu işlem eline kart çekmez.',
                  'Inspect the top of your deck and choose its order. This does not draw a card into your hand.',
                ),
            style: BattleTokens.body,
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < order.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: BattleSkin(
                name: 'command-panel',
                child: InkWell(
                  key: ValueKey('private-${order[i].wire}'),
                  onTap:
                      fate
                          ? () {
                            if (!_active) return;
                            setState(() => taken = order[i]);
                          }
                          : null,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        SizedBox.square(
                          key: _cardOrigins.putIfAbsent(
                            order[i],
                            GlobalKey.new,
                          ),
                          dimension: 64,
                          child: BattleCardArt(card: order[i]),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l.battleCardName(order[i]),
                                style: BattleTokens.card,
                              ),
                              Text(
                                taken == order[i]
                                    ? l.battle(BattleCopy.take)
                                    : '${i + 1}',
                                style: BattleTokens.body,
                              ),
                            ],
                          ),
                        ),
                        if (taken != order[i]) ...[
                          BattleIconControl(
                            icon: Icons.arrow_upward,
                            label: l.battle(BattleCopy.earlier),
                            onPressed: i == 0 ? null : () => shift(i, -1),
                          ),
                          BattleIconControl(
                            icon: Icons.arrow_downward,
                            label: l.battle(BattleCopy.later),
                            onPressed:
                                i == order.length - 1
                                    ? null
                                    : () => shift(i, 1),
                          ),
                        ] else
                          const BattleArt('confirm', size: 28),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          BattleCommand(
            key: const ValueKey('confirm-private'),
            label: l.battle(BattleCopy.confirm),
            icon: Icons.check,
            art: 'confirm',
            onPressed:
                choice == null
                    ? null
                    : () {
                      if (!_active) return;
                      final render =
                          _cardOrigins[taken]?.currentContext
                              ?.findRenderObject();
                      if (fate &&
                          taken != null &&
                          render is RenderBox &&
                          render.hasSize) {
                        widget.onTakeOrigin?.call(
                          taken!,
                          render.localToGlobal(Offset.zero) & render.size,
                        );
                      }
                      dismissBattleSheet(context, choice);
                    },
          ),
        ],
      ),
    );
  }
}

class PrivateKnowledgeSheet extends StatelessWidget {
  final PlayerKnowledgeState knowledge;
  const PrivateKnowledgeSheet({super.key, required this.knowledge});
  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    return BattleSheet(
      title: l.battle(BattleCopy.privateKnowledge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (knowledge.knownUpcomingCards.isNotEmpty) ...[
            Text(l.battle(BattleCopy.upcoming), style: BattleTokens.title),
            for (var i = 0; i < knowledge.knownUpcomingCards.length; i++)
              Row(
                children: [
                  SizedBox.square(
                    dimension: 64,
                    child: BattleCardArt(card: knowledge.knownUpcomingCards[i]),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${i + 1}. ${l.battleCardName(knowledge.knownUpcomingCards[i])}',
                      style: BattleTokens.body,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
          ],
          for (final observation in knowledge.radarObservations)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const BattleArt('knowledge', size: 30),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.battleCardName(observation.queriedCardId),
                      style: BattleTokens.card,
                    ),
                  ),
                  Text(
                    l.battle(
                      observation.stale
                          ? BattleCopy.stale
                          : observation.inHand
                          ? BattleCopy.inHand
                          : BattleCopy.notInHand,
                    ),
                    style: BattleTokens.body,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class BattleKnowledgePreview extends StatelessWidget {
  final PlayerKnowledgeState knowledge;
  final bool pending;
  final VoidCallback? onOpen;
  final Key? commandKey;
  const BattleKnowledgePreview({
    super.key,
    required this.knowledge,
    required this.pending,
    required this.onOpen,
    this.commandKey,
  });
  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    final cards =
        pending ? knowledge.pendingCards : knowledge.knownUpcomingCards;
    if (cards.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('battle-knowledge-preview'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF153E43),
        border: Border.all(color: BattleTokens.mana),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.learning(
              pending ? 'KART SIRASINI SEN SEÇ' : 'SIRADAKİ KARTLARIN',
              pending ? 'CHOOSE YOUR CARD ORDER' : 'YOUR UPCOMING CARDS',
            ),
            style: BattleTokens.card,
          ),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (final (index, card) in cards.indexed)
                SizedBox(
                  width: 84,
                  child: Column(
                    children: [
                      SizedBox.square(
                        dimension: 56,
                        child: BattleCardArt(card: card),
                      ),
                      Text(
                        '${index + 1}. ${l.battleCardName(card)}',
                        textAlign: TextAlign.center,
                        style: BattleTokens.caption,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          TextButton.icon(
            key: commandKey,
            onPressed: onOpen,
            icon: const BattleArt('knowledge', size: 22),
            label: Text(
              l.learning(
                pending ? 'Sırayı düzenle ve onayla' : 'Bilgiyi aç',
                pending ? 'Arrange and confirm' : 'View knowledge',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class BattleRadarPreview extends StatelessWidget {
  final RadarObservation observation;
  final VoidCallback onOpen;
  const BattleRadarPreview({
    super.key,
    required this.observation,
    required this.onOpen,
  });
  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    return InkWell(
      key: const ValueKey('battle-radar-result'),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 36,
              child: BattleCardArt(card: observation.queriedCardId),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${l.battleCardName(CardId.radar)} · ${l.battleCardName(observation.queriedCardId)}\n${l.battle(observation.stale
                    ? BattleCopy.stale
                    : observation.inHand
                    ? BattleCopy.inHand
                    : BattleCopy.notInHand)}',
                style: BattleTokens.body.copyWith(height: 1.3),
              ),
            ),
            const BattleArt('knowledge', size: 22),
          ],
        ),
      ),
    );
  }
}
