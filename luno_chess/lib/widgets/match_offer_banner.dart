import 'package:flutter/material.dart' hide Text;
import '../i18n/luno_text.dart';
import '../theme/luno_assets.dart';
import 'luno_surface.dart';

class MatchOfferBanner extends StatelessWidget {
  const MatchOfferBanner({
    super.key,
    required this.title,
    required this.firstLabel,
    this.secondLabel,
    required this.onFirst,
    this.onSecond,
    this.enabled = true,
  });
  final String title;
  final String firstLabel;
  final String? secondLabel;
  final VoidCallback onFirst;
  final VoidCallback? onSecond;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
    child: LunoSurface(
      color: const Color(0xF0264548),
      borderRadius: BorderRadius.circular(8),
      padding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .28,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SizedBox(
                    width: 36,
                    height: 36,
                    child: LunoArt(LunoAssets.matchDraw),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  LunoButton(
                    expand: false,
                    label: firstLabel,
                    onPressed: enabled ? onFirst : null,
                    kind:
                        secondLabel == null
                            ? LunoButtonKind.secondary
                            : LunoButtonKind.primary,
                  ),
                  if (secondLabel != null)
                    LunoButton(
                      expand: false,
                      label: secondLabel!,
                      kind: LunoButtonKind.secondary,
                      onPressed: enabled ? onSecond : null,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
