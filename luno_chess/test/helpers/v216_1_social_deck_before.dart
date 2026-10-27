// Frozen pre-social-edit owned classes. Do not mirror production fixes.
// Source: qa/v216_1/social-before/source/battle_deck_screen.dart.txt
// Raw source SHA-256: f57dc582c8449eb95bb9248b6e41ad39e89f7a0bf611d96fc54238f8696f2c99
// Only class identifiers and import paths are adapted; shared dependencies remain current.
// ignore_for_file: unused_import
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_v1/deck_account.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/i18n/battle_learning_copy.dart';
import 'package:luno_chess/i18n/battle_v1_copy.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/navigation/luno_account_scope.dart';
import 'package:luno_chess/navigation/luno_account_modal.dart';
import 'package:luno_chess/services/account_operation_guard.dart';
import 'package:luno_chess/services/luno_feedback.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/theme/luno_visual_assets.dart';
import 'package:luno_chess/widgets/luno_polish.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:luno_chess/widgets/battle_deck_mana.dart';
import 'package:luno_chess/widgets/battle_collection_progress.dart';
import 'package:luno_chess/services/battle_v1_deck_result.dart';
import 'package:luno_chess/services/first_session_telemetry.dart';
import 'package:luno_chess/screens/battle_deck_screen.dart' show showBattleCatalogDetail;

class V216BeforeBattleSelectedDeckGrid extends StatelessWidget {
  final List<CardId> cards;
  final ValueChanged<CardId>? onTap;
  const V216BeforeBattleSelectedDeckGrid({super.key, required this.cards, this.onTap});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final l = LunoLocalizations.of(context);
      const labelStyle = TextStyle(
        fontSize: 11,
        height: 1.12,
        fontWeight: FontWeight.w800,
      );
      final scaler = MediaQuery.textScalerOf(context);
      final style = DefaultTextStyle.of(context).style.merge(labelStyle);
      var minimumWidth = 52.0;
      for (final card in cards) {
        for (final word in l.battleCardName(card).split(RegExp(r'\s+'))) {
          final painter = TextPainter(
            text: TextSpan(text: word, style: style),
            textDirection: Directionality.of(context),
            textScaler: scaler,
          )..layout();
          minimumWidth = math.max(minimumWidth, painter.width + 2);
          painter.dispose();
        }
      }
      final columns = ((box.maxWidth + 6) / (minimumWidth + 6)).floor().clamp(
        1,
        5,
      );
      final width = (box.maxWidth - 6 * (columns - 1)) / columns;
      return Wrap(
        key: const ValueKey('selected-deck-grid'),
        spacing: 6,
        runSpacing: 10,
        children: [
          for (final card in cards)
            SizedBox(
              width: width,
              child: LunoPressFeedback(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: ValueKey('deck-slot-${card.wire}'),
                    onTap:
                        () =>
                            onTap == null
                                ? showBattleCatalogDetail(context, card)
                                : onTap!(card),
                    onLongPress: () => showBattleCatalogDetail(context, card),
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      children: [
                        AspectRatio(
                          aspectRatio: .75,
                          child: Container(
                            decoration: BoxDecoration(
                              image: const DecorationImage(
                                image: AssetImage(
                                  'assets/native_art/v205-card-face.png',
                                ),
                                fit: BoxFit.fill,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: battleRarityColor(
                                  cardDefinitions[card]!.rarity,
                                ),
                              ),
                            ),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      4,
                                      17,
                                      4,
                                      4,
                                    ),
                                    child: BattleCardArt(card: card),
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  left: 5,
                                  child: Text(
                                    '${cardDefinitions[card]!.cost}',
                                    textScaler: TextScaler.noScaling,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      color: LunoColors.cyan,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: IconButton(
                                    tooltip: l.learning(
                                      '${l.battleCardName(card)} bilgisi',
                                      '${l.battleCardName(card)} info',
                                    ),
                                    icon: const Icon(
                                      Icons.info_outline_rounded,
                                      size: 18,
                                    ),
                                    color: LunoColors.ivory,
                                    onPressed:
                                        () => showBattleCatalogDetail(
                                          context,
                                          card,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: scaler.scale(11) * 1.12 * 2,
                          child: Text(
                            l.battleCardName(card),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            style: labelStyle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
