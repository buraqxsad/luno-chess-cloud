import 'package:flutter/material.dart' hide Text;

import '../i18n/luno_text.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';

const gameTimeControls = <int>[1, 3, 5, 10, 30];

/// Local and AI choices only. V1 online timing is fixed by the server.
Future<int?> showGameTimeControlPicker(
  BuildContext context, {
  int initial = 5,
}) {
  if (!context.mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) {
    return Future.value();
  }
  final selected = gameTimeControls.contains(initial) ? initial : 5;
  var choosing = false;
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: const Color(0xFF263F43),
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Text('SÜRE SEÇ', style: LunoType.sectionTitle),
              ),
              for (final minutes in gameTimeControls)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color:
                        minutes == selected
                            ? const Color(0xFF3B6059)
                            : const Color(0xFF304F53),
                    borderRadius: BorderRadius.circular(8),
                    child: ListTile(
                      minVerticalPadding: 12,
                      selected: minutes == selected,
                      selectedColor: LunoColors.gold,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      enableFeedback: true,
                      leading: SizedBox(
                        width: 32,
                        height: 32,
                        child:
                            minutes == selected
                                ? const ClipOval(
                                  child: LunoArt(
                                    'assets/native_art/arena-unlocked-v41.png',
                                  ),
                                )
                                : const Icon(
                                  Icons.radio_button_unchecked_rounded,
                                  color: Color(0xFFB8D2CD),
                                ),
                      ),
                      title: Text(
                        '$minutes dakika / oyuncu',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle:
                          minutes == selected
                              ? const Text(
                                'Seçili süre',
                                style: TextStyle(fontSize: 13),
                              )
                              : null,
                      onTap: () {
                        if (choosing ||
                            !ctx.mounted ||
                            ModalRoute.of(ctx)?.isCurrent != true) {
                          return;
                        }
                        choosing = true;
                        Navigator.of(ctx).pop(minutes);
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
