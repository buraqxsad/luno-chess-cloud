import 'package:flutter/material.dart' hide Text;
import '../i18n/luno_text.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';
import 'luno_surface.dart';

Future<bool> showMatchConfirmation(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'VAZGEÇ',
  String art = LunoAssets.matchResign,
  LunoButtonKind confirmKind = LunoButtonKind.danger,
}) async {
  if (!context.mounted || ModalRoute.of(context)?.isCurrent == false) {
    return false;
  }
  var answered = false;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      void answer(bool value) {
        if (answered || !ctx.mounted || ModalRoute.of(ctx)?.isCurrent != true) {
          return;
        }
        answered = true;
        Navigator.of(ctx).pop(value);
      }

      return AlertDialog(
        scrollable: true,
        backgroundColor: const Color(0xFF29423F),
        titleTextStyle: LunoType.sectionTitle,
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 84, height: 84, child: LunoArt(art)),
            const SizedBox(height: 12),
            Text(message, style: const TextStyle(fontSize: 15, height: 1.45)),
          ],
        ),
        actions: [
          LunoButton(
            expand: false,
            label: cancelLabel,
            kind: LunoButtonKind.secondary,
            onPressed: () => answer(false),
          ),
          LunoButton(
            expand: false,
            label: confirmLabel,
            kind: confirmKind,
            onPressed: () => answer(true),
          ),
        ],
      );
    },
  );
  return result == true;
}
