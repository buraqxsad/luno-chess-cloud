import 'package:flutter/material.dart';
import '../battle_v1/model.dart';
import '../engine/piece.dart';
import '../i18n/luno_localizations.dart';
import 'tokens.dart';

class BattleDrawCounters extends StatelessWidget {
  final PlayerView view;
  final PieceColor side;
  final GlobalKey? deckSource, handTarget;
  const BattleDrawCounters({
    super.key,
    required this.view,
    required this.side,
    this.deckSource,
    this.handTarget,
  });
  @override
  Widget build(BuildContext context) {
    final english = LunoLocalizations.of(context).isEnglish;
    return Wrap(
      spacing: 5,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/native_art/battle-draw-pile-v208.webp',
              key: deckSource,
              width: 18,
              height: 24,
              cacheWidth: 72,
            ),
            Text(
              '${english ? 'Deck' : 'Deste'} ${view.rules.deckCounts[side]}',
              key: ValueKey('deck-count-${side.name}'),
              textScaler: TextScaler.noScaling,
              style: BattleTokens.caption.copyWith(fontSize: 11),
            ),
          ],
        ),
        Text(
          '${english ? 'Hand' : 'El'} ${view.rules.handCounts[side]}',
          key: handTarget,
          textScaler: TextScaler.noScaling,
          style: BattleTokens.caption.copyWith(fontSize: 11),
        ),
      ],
    );
  }
}
