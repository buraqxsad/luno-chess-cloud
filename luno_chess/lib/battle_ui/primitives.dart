import 'package:flutter/material.dart';
import '../widgets/luno_polish.dart';
import '../widgets/luno_surface.dart';
import '../theme/luno_visual_assets.dart';
import '../i18n/luno_localizations.dart';
import '../i18n/battle_learning_copy.dart';
import 'tokens.dart';
import 'art.dart';

class BattleManaGlyph extends StatelessWidget {
  final double size;
  final Color color;
  const BattleManaGlyph({
    super.key,
    this.size = 24,
    this.color = BattleTokens.mana,
  });
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(dimension: size, child: const BattleArt('mana')),
  );
}

class BattleIconControl extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? art;
  final VoidCallback? onPressed;
  final LunoIconContext? contextStyle;
  const BattleIconControl({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.art,
    this.contextStyle,
  });
  @override
  Widget build(BuildContext context) => LunoIconControl(
    icon: icon,
    label: label,
    onPressed: onPressed,
    artwork: art == null ? null : BattleArt(art!, size: 28),
    contextStyle:
        contextStyle ??
        (icon == Icons.close || icon == Icons.close_rounded
            ? LunoIconContext.sheet
            : LunoIconContext.immersive),
  );
}

class BattleCommand extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool danger;
  final bool primary;
  final String? art;
  final bool loading;
  final bool quiet;
  const BattleCommand({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
    this.danger = false,
    this.primary = false,
    this.art,
    this.loading = false,
    this.quiet = false,
  });
  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final isPrimary = primary && !danger;
    final isQuiet =
        (quiet || icon == Icons.close || icon == Icons.close_rounded) &&
        !primary &&
        !danger;
    final accent =
        danger
            ? BattleTokens.danger
            : isPrimary
            ? BattleTokens.gold
            : BattleTokens.mana;
    return Semantics(
      button: true,
      label: label,
      enabled: enabled,
      value: loading ? LunoLocalizations.of(context).preparing : null,
      liveRegion: loading,
      onTap: enabled ? onPressed : null,
      child: ExcludeSemantics(
        child: LunoPressFeedback(
          enabled: enabled,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: BattleTokens.touch),
            child: FilledButton.icon(
              onPressed: enabled ? onPressed : null,
              icon:
                  loading
                      ? const Icon(Icons.hourglass_top_rounded, size: 20)
                      : art == null
                      ? Icon(icon, size: 20)
                      : BattleArt(art!, size: 24),
              label: Text(label, textAlign: TextAlign.center),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: BattleTokens.ivory,
                disabledBackgroundColor: Colors.transparent,
                disabledForegroundColor: BattleTokens.secondary,
                minimumSize: const Size(0, BattleTokens.touch),
                elevation: 0,
                shadowColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                animationDuration: BattleTokens.duration(context),
                textStyle: BattleTokens.body.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(BattleTokens.radius),
                  side: BorderSide.none,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ).copyWith(
                backgroundBuilder: (_, states, child) {
                  final pressed = states.contains(WidgetState.pressed);
                  final inactive =
                      states.contains(WidgetState.disabled) && !loading;
                  final focused = states.contains(WidgetState.focused);
                  final face =
                      inactive
                          ? LunoVisualAssets.disabled
                          : danger
                          ? LunoVisualAssets.danger
                          : isPrimary
                          ? BattleArt.path('action-face')
                          : null;
                  return AnimatedContainer(
                    key: const ValueKey('battle-command-face'),
                    duration: BattleTokens.duration(context),
                    decoration: BoxDecoration(
                      color:
                          isQuiet && !pressed
                              ? Colors.transparent
                              : danger
                              ? const Color(0xFF351D29)
                              : pressed
                              ? BattleTokens.raised
                              : BattleTokens.surface,
                      image:
                          face == null
                              ? null
                              : face.contains('polish-v203-')
                              ? lunoFace(
                                face,
                                button: true,
                                opacity: loading ? .64 : 1,
                              )
                              : DecorationImage(
                                image: AssetImage(face),
                                centerSlice: const Rect.fromLTRB(
                                  32,
                                  12,
                                  688,
                                  121,
                                ),
                                fit: BoxFit.fill,
                                opacity: loading ? .64 : 1,
                              ),
                      borderRadius: BorderRadius.circular(BattleTokens.radius),
                      border: Border.all(
                        color:
                            focused
                                ? BattleTokens.ivory
                                : inactive
                                ? BattleTokens.border
                                : isQuiet && !pressed
                                ? Colors.transparent
                                : accent.withValues(alpha: pressed ? .95 : .55),
                        width: focused ? 2 : 1,
                      ),
                      boxShadow:
                          enabled && isPrimary
                              ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: .25),
                                  blurRadius: pressed ? 2 : 5,
                                  offset: Offset(0, pressed ? 1 : 3),
                                ),
                              ]
                              : null,
                    ),
                    child: child ?? const SizedBox(),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BattleMana extends StatelessWidget {
  final int value;
  final int? previewCost;
  final String label;
  final bool compact;
  const BattleMana({
    super.key,
    required this.value,
    required this.label,
    this.compact = false,
    this.previewCost,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    value: previewCost == null ? '$value / 6' :
        '$value / 6, ${LunoLocalizations.of(context).learning(
          'seçili kart $previewCost mana', 'selected card $previewCost mana')}',
    child: ExcludeSemantics(
      child: Container(
        key: const ValueKey('battle-mana-meter'),
        width:
            (compact ? 82 : 100) *
            (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 1.6),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: BattleTokens.background.withValues(alpha: .78),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: BattleTokens.mana.withValues(alpha: .35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BattleManaGlyph(size: compact ? 18 : 24),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height:
                        MediaQuery.textScalerOf(
                          context,
                        ).scale(compact ? 13 : 14) *
                        1.2,
                    child: AnimatedSwitcher(
                      duration: BattleTokens.duration(context),
                      layoutBuilder:
                          (current, previous) => Stack(
                            alignment: Alignment.center,
                            children: [
                              ...previous,
                              if (current != null) current,
                            ],
                          ),
                      child: FittedBox(
                        key: ValueKey(value),
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${value.clamp(0, 6)} / 6',
                          maxLines: 1,
                          style: BattleTokens.body.copyWith(
                            fontSize: compact ? 13 : 14,
                            color: BattleTokens.ivory,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      for (var i = 0; i < 6; i++) ...[
                        if (i > 0) const SizedBox(width: 2),
                        Expanded(
                          child: AnimatedContainer(
                            key: ValueKey('mana-cell-$i'),
                            duration: BattleTokens.duration(context),
                            height: 3,
                            decoration: BoxDecoration(
                              color:
                                  i < value
                                      ? previewCost != null &&
                                          i >= value - previewCost! &&
                                          previewCost! <= value
                                          ? BattleTokens.gold
                                          : BattleTokens.mana
                                      : BattleTokens.border,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
