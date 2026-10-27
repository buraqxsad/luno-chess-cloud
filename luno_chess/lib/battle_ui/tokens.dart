import 'package:flutter/material.dart';
import '../theme/luno_theme.dart';

class BattleTokens {
  const BattleTokens._();
  static bool compactText(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(14) <= 15.4 + 1e-6;
  static bool shortPortrait(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width <= 430 && size.height < 700 && size.height > size.width;
  }

  static bool sideDock(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return shortPortrait(context) ||
        (size.width <= 430 &&
            size.height > size.width &&
            !compactText(context));
  }

  static const background = LunoColors.bgDeep;
  static const surface = Color(0xff121d29);
  static const raised = LunoColors.bgPanel2;
  static const border = Color(0xff425665);
  static const gold = Color(0xffd9b775);
  static const moon = LunoColors.cyan;
  static const mana = Color(0xff52d2cf);
  static const ivory = LunoColors.ivory;
  static const secondary = LunoColors.textDim;
  static const disabled = Color(0xff71818e);
  static const danger = LunoColors.danger;
  static const success = LunoColors.success;
  static const lightSquare = Color(0xffd8d8cd);
  static const darkSquare = Color(0xff263c50);
  static const gap = 8.0;
  static const radius = 8.0;
  static const touch = 48.0;
  static const micro = Duration(milliseconds: 160);
  static const title = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 17,
    fontWeight: FontWeight.w800,
    color: ivory,
    letterSpacing: 0,
  );
  static const body = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: secondary,
    letterSpacing: 0,
  );
  static const card = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 14,
    fontWeight: FontWeight.w800,
    color: ivory,
    letterSpacing: 0,
  );
  static const caption = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: secondary,
    letterSpacing: 0,
  );
  static const clock = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 24,
    fontWeight: FontWeight.w800,
    color: ivory,
    letterSpacing: 0,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static Duration duration(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : micro;
}
