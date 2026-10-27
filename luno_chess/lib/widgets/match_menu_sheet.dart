import 'package:flutter/material.dart' hide Text;
import '../i18n/luno_text.dart';
import '../services/luno_feedback.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';

class MatchMenuEntry {
  const MatchMenuEntry(this.id, this.label, this.art);
  final String id;
  final String label;
  final String art;
}

Future<String?> showMatchMenuSheet(
  BuildContext context,
  List<MatchMenuEntry> entries,
) {
  if (!context.mounted || ModalRoute.of(context)?.isCurrent == false) {
    return Future.value();
  }
  var selected = false;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFF263F43),
    builder:
        (ctx) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Maç menüsü', style: LunoType.sectionTitle),
                const SizedBox(height: 14),
                for (final entry in entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: const Color(0xFF315457),
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          if (selected ||
                              !ctx.mounted ||
                              ModalRoute.of(ctx)?.isCurrent != true) {
                            return;
                          }
                          selected = true;
                          LunoFeedback.tap();
                          Navigator.of(ctx).pop(entry.id);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 44,
                                height: 44,
                                child: LunoArt(entry.art),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  entry.label,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.chevron_right_rounded,
                                size: 20,
                                color: LunoColors.textDim,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
  );
}
