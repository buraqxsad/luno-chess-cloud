import 'package:flutter/material.dart' hide Text;
import '../engine/piece.dart';
import '../i18n/luno_text.dart';
import '../services/luno_feedback.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';

Future<PieceType?> showPromotionSheet(
  BuildContext context, {
  required PieceColor color,
  required String pieceSet,
}) {
  if (!context.mounted || ModalRoute.of(context)?.isCurrent == false) {
    return Future.value();
  }
  var chosen = false;
  const choices = [
    (PieceType.queen, 'Vezir'),
    (PieceType.rook, 'Kale'),
    (PieceType.bishop, 'Fil'),
    (PieceType.knight, 'At'),
  ];
  return showModalBottomSheet<PieceType>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFF263F43),
    builder:
        (ctx) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('PİYON TERFİSİ', style: LunoType.sectionTitle),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisExtent: 106 + MediaQuery.textScalerOf(ctx).scale(48),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  children: [
                    for (final choice in choices)
                      Material(
                        color: const Color(0xFF36565A),
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            if (chosen ||
                                !ctx.mounted ||
                                ModalRoute.of(ctx)?.isCurrent != true) {
                              return;
                            }
                            chosen = true;
                            LunoFeedback.tap();
                            Navigator.of(ctx).pop(choice.$1);
                          },
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 76,
                                height: 82,
                                child: LunoArt(
                                  LunoAssets.pieceForSet(
                                    pieceSet,
                                    color,
                                    choice.$1,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                choice.$2,
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 16,
                                  height: 1.2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
  );
}
