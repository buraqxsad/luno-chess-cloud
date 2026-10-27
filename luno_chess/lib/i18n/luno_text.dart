import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart';

import 'luno_localizations.dart';

/// Text-compatible widget that resolves stable game copy at build time.
///
/// It deliberately keeps the same constructor surface used by Flutter's
/// material Text for the properties used in the game, so screens do not need
/// to trade layout fidelity for localization.
class Text extends StatelessWidget {
  final String? data;
  final InlineSpan? textSpan;
  final material.TextStyle? style;
  final material.StrutStyle? strutStyle;
  final material.TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final material.TextOverflow? overflow;
  final material.TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final material.TextWidthBasis? textWidthBasis;
  final material.TextHeightBehavior? textHeightBehavior;
  final material.Color? selectionColor;
  final bool localize;

  const Text(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
    this.localize = true,
  }) : textSpan = null;

  const Text.rich(
    this.textSpan, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
    this.localize = true,
  }) : data = null;

  @override
  Widget build(BuildContext context) {
    final translated =
        data == null
            ? null
            : localize
            ? LunoLocalizations.of(context).translate(data!)
            : data;
    if (textSpan != null) {
      return material.RichText(
        text:
            style == null
                ? textSpan!
                : TextSpan(style: style, children: [textSpan!]),
        strutStyle: strutStyle,
        textAlign: textAlign ?? material.TextAlign.start,
        textDirection: textDirection,
        locale: locale,
        softWrap: softWrap ?? true,
        overflow: overflow ?? material.TextOverflow.clip,
        textScaler: textScaler ?? MediaQuery.textScalerOf(context),
        maxLines: maxLines,
        textWidthBasis: textWidthBasis ?? material.TextWidthBasis.parent,
        textHeightBehavior: textHeightBehavior,
        selectionColor: selectionColor,
      );
    }
    return material.Text(
      translated ?? '',
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel:
          semanticsLabel == null || !localize
              ? semanticsLabel
              : LunoLocalizations.of(context).translate(semanticsLabel!),
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}
