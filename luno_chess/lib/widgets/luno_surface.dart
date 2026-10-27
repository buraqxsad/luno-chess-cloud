import 'package:flutter/material.dart' hide Text;

import '../i18n/luno_text.dart';
import '../i18n/luno_localizations.dart';
import '../services/luno_feedback.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';
import '../theme/luno_visual_assets.dart';
import 'luno_polish.dart';

class LunoSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final BorderRadius borderRadius;
  final Border? border;
  final String surfaceArt;
  final bool nineSlice;

  const LunoSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.border,
    this.surfaceArt = LunoVisualAssets.neutral,
    this.nineSlice = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? LunoColors.bgPanel,
        image:
            nineSlice
                ? lunoFace(surfaceArt, opacity: .72)
                : DecorationImage(
                  image: AssetImage(surfaceArt),
                  fit: BoxFit.fill,
                  opacity: .72,
                ),
        borderRadius: borderRadius,
        border: border ?? Border.all(color: LunoColors.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x42000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

enum LunoButtonKind { primary, secondary, danger, quiet, navigation, card }

enum LunoIconContext { hub, immersive, sheet, premium }

/// One icon language with context-specific backing, not four unrelated icons.
class LunoIconControl extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Widget? artwork;
  final LunoIconContext contextStyle;
  final bool loading;

  const LunoIconControl({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.artwork,
    this.contextStyle = LunoIconContext.hub,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    final enabled = onPressed != null && !loading;
    final title = l.translate(label);
    final fill = switch (contextStyle) {
      LunoIconContext.hub => LunoColors.bgRaised,
      LunoIconContext.immersive => LunoColors.bgDeep.withValues(alpha: .52),
      LunoIconContext.sheet => Colors.transparent,
      LunoIconContext.premium => LunoColors.bgPanel.withValues(alpha: .68),
    };
    final rim = switch (contextStyle) {
      LunoIconContext.hub => LunoColors.line,
      LunoIconContext.immersive => LunoColors.ivory.withValues(alpha: .16),
      LunoIconContext.sheet => Colors.transparent,
      LunoIconContext.premium => LunoColors.gold.withValues(alpha: .38),
    };
    return Tooltip(
      message: title,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: title,
        value: loading ? l.preparing : null,
        liveRegion: loading,
        onTap: enabled ? onPressed : null,
        child: ExcludeSemantics(
          child: LunoPressFeedback(
            enabled: enabled,
            child: SizedBox.square(
              dimension: 48,
              child: IconButton(
                onPressed: enabled ? onPressed : null,
                icon:
                    loading
                        ? const Icon(Icons.hourglass_top_rounded, size: 22)
                        : artwork == null
                        ? Icon(icon, size: 24)
                        : Opacity(opacity: enabled ? 1 : .55, child: artwork),
                style: ButtonStyle(
                  animationDuration: LunoMotion.adaptive(
                    context,
                    LunoMotion.press,
                  ),
                  padding: const WidgetStatePropertyAll(EdgeInsets.all(10)),
                  minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (states) =>
                        states.contains(WidgetState.disabled) && !loading
                            ? LunoColors.textDim
                            : LunoColors.ivory,
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) =>
                        states.contains(WidgetState.pressed)
                            ? LunoColors.bgRaised
                            : fill,
                  ),
                  overlayColor: WidgetStatePropertyAll(
                    LunoColors.cyan.withValues(alpha: .14),
                  ),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  side: WidgetStateProperty.resolveWith(
                    (states) => BorderSide(
                      color:
                          states.contains(WidgetState.focused)
                              ? LunoColors.cyan
                              : rim,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared tactile CTA. The press state is intentionally a transform/color
/// change instead of a shader so it remains cheap on lower-end phones.
class LunoButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? leading;
  final LunoButtonKind kind;
  final bool loading;
  final bool expand;
  final String? backgroundArt;

  const LunoButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.leading,
    this.kind = LunoButtonKind.primary,
    this.loading = false,
    this.expand = true,
    this.backgroundArt,
  });

  @override
  State<LunoButton> createState() => _LunoButtonState();
}

class _LunoButtonState extends State<LunoButton> {
  bool pressed = false;

  @override
  void didUpdateWidget(covariant LunoButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading || widget.onPressed == null) pressed = false;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    final isPrimary = widget.kind == LunoButtonKind.primary;
    final isDanger = widget.kind == LunoButtonKind.danger;
    final isQuiet = widget.kind == LunoButtonKind.quiet;
    final isCard = widget.kind == LunoButtonKind.card;
    final accent =
        isDanger
            ? LunoColors.danger
            : isPrimary
            ? LunoColors.gold
            : widget.kind == LunoButtonKind.navigation
            ? LunoColors.teal
            : LunoColors.cyan;
    final l = LunoLocalizations.of(context);
    final foreground =
        enabled || widget.loading ? LunoColors.ivory : LunoColors.textDim;
    final face =
        !enabled && !widget.loading && !isQuiet
            ? LunoVisualAssets.disabled
            : widget.backgroundArt ??
                (isQuiet || isCard
                    ? null
                    : isPrimary
                    ? LunoVisualAssets.primary
                    : isDanger
                    ? LunoVisualAssets.danger
                    : LunoVisualAssets.secondary);
    final child = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading)
          SizedBox(
            width: 17,
            height: 17,
            child:
                LunoMotion.adaptive(context, LunoMotion.micro) == Duration.zero
                    ? Icon(
                      Icons.hourglass_top_rounded,
                      size: 17,
                      color: foreground,
                    )
                    : CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
          )
        else if (widget.leading != null)
          widget.leading!
        else if (widget.icon != null)
          Icon(widget.icon, size: 18, color: foreground),
        if ((widget.icon != null || widget.leading != null || widget.loading) &&
            widget.label.isNotEmpty)
          const SizedBox(width: 8),
        if (widget.label.isNotEmpty)
          Flexible(
            child: Text(
              widget.label,
              textAlign: TextAlign.center,
              style: LunoType.button.copyWith(color: foreground),
            ),
          ),
      ],
    );
    return LunoPressFeedback(
      enabled: enabled,
      pressedScale: .975,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: l.translate(widget.label),
        value: widget.loading ? l.preparing : null,
        liveRegion: widget.loading,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap:
                enabled
                    ? () {
                      final action = widget.onPressed;
                      if (!mounted || widget.loading || action == null) return;
                      LunoFeedback.tap();
                      action();
                    }
                    : null,
            onHighlightChanged: (value) {
              final next = value && widget.onPressed != null && !widget.loading;
              if (mounted && pressed != next) setState(() => pressed = next);
            },
            borderRadius: BorderRadius.circular(8),
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            focusColor: LunoColors.gold.withValues(alpha: .18),
            child: AnimatedContainer(
              clipBehavior: Clip.antiAlias,
              duration: LunoMotion.adaptive(context, LunoMotion.press),
              curve: Curves.easeOut,
              constraints: const BoxConstraints(minHeight: 48),
              width: widget.expand ? double.infinity : null,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color:
                    pressed
                        ? LunoColors.bgRaised
                        : isQuiet
                        ? Colors.transparent
                        : isDanger
                        ? const Color(0xFF351D29)
                        : LunoColors.bgPanel,
                image:
                    face == null
                        ? null
                        : face.contains('polish-v203-')
                        ? lunoFace(
                          face,
                          button: true,
                          opacity:
                              widget.loading
                                  ? .64
                                  : pressed
                                  ? 1
                                  : .9,
                        )
                        : DecorationImage(
                          image: AssetImage(face),
                          fit: BoxFit.fill,
                        ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color:
                      isQuiet && !pressed
                          ? Colors.transparent
                          : enabled || widget.loading
                          ? accent.withValues(alpha: pressed ? .9 : .55)
                          : LunoColors.line,
                ),
                boxShadow:
                    enabled && !isQuiet
                        ? [
                          BoxShadow(
                            color: const Color(0x4D000000),
                            blurRadius: isPrimary ? 8 : 4,
                            offset: Offset(0, pressed ? 1 : 3),
                          ),
                        ]
                        : null,
              ),
              child: ExcludeSemantics(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// One current message, rather than a queue of stale action feedback.
void showLunoNotice(BuildContext context, String message) {
  if (!context.mounted) return;
  final text = message.trim();
  if (text.isEmpty) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: LunoColors.bgRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: LunoColors.cyan),
      ),
      duration: const Duration(seconds: 4),
      showCloseIcon: true,
      closeIconColor: LunoColors.ivory,
      content: Row(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: LunoArt(
              LunoAssets.settingsNotification,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: ((MediaQuery.sizeOf(context).height -
                            MediaQuery.viewInsetsOf(context).bottom) *
                        .25)
                    .clamp(48.0, 160.0),
              ),
              child: SingleChildScrollView(child: Text(text)),
            ),
          ),
        ],
      ),
    ),
  );
}

class LunoBackdrop extends StatelessWidget {
  final String? art;
  final Widget child;
  final Alignment focalPoint;
  final Color overlay;
  final bool useSafeArea;
  final bool safeTop;

  const LunoBackdrop({
    super.key,
    this.art,
    required this.child,
    this.focalPoint = Alignment.center,
    this.overlay = const Color(0x990B071C),
    this.useSafeArea = true,
    this.safeTop = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = useSafeArea ? SafeArea(top: safeTop, child: child) : child;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: LunoColors.bgStage),
        if (art != null)
          LunoArt(art!, fit: BoxFit.cover, alignment: focalPoint),
        ColoredBox(color: Color.fromARGB((overlay.a * 255).round(), 8, 15, 24)),
        content,
      ],
    );
  }
}

class LunoSectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const LunoSectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: LunoColors.gold,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: LunoColors.textDim),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class LunoStatusDot extends StatelessWidget {
  final bool active;
  const LunoStatusDot({super.key, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: active ? LunoColors.success : LunoColors.danger,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: (active ? LunoColors.success : LunoColors.danger).withValues(
              alpha: .55,
            ),
            blurRadius: 7,
          ),
        ],
      ),
    );
  }
}

class LunoIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const LunoIconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 38,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: .16),
        border: Border.all(color: color.withValues(alpha: .6)),
      ),
      child: Icon(icon, color: color, size: size * .52),
    );
  }
}
