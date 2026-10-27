import 'package:flutter/material.dart';
import '../theme/luno_assets.dart';

/// Keep prices out of the text column when space or accessible text is tight.
class ShopOfferLayout extends StatelessWidget {
  final String art;
  final Widget copy, action;
  const ShopOfferLayout({
    super.key,
    required this.art,
    required this.copy,
    required this.action,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final stacked =
          box.maxWidth < 350 || MediaQuery.textScalerOf(context).scale(14) > 18;
      final summary = Row(
        children: [
          LunoArt(art, width: stacked ? 64 : 78, height: stacked ? 64 : 78),
          const SizedBox(width: 12),
          Expanded(child: copy),
        ],
      );
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [summary, const SizedBox(height: 12), action],
        );
      }
      return Row(
        children: [
          Expanded(child: summary),
          const SizedBox(width: 12),
          SizedBox(width: 124, child: action),
        ],
      );
    },
  );
}
