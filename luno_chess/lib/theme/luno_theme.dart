import 'package:flutter/material.dart';
import 'luno_visual_assets.dart';

/// Shared materials and accents, aligned with the board-first battle UI.
class LunoColors {
  static const bgDeep = Color(0xFF080F18);
  static const bgStage = Color(0xFF0C1520);
  static const bgPanel = Color(0xFF152331);
  static const bgPanel2 = Color(0xFF1C2B39);
  static const bgRaised = Color(0xFF263A48);
  static const gold = Color(0xFFE5C47D);
  static const goldDeep = Color(0xFFB8934F);
  static const ivory = Color(0xFFF3EFE5);
  static const teal = Color(0xFF89CBB0);
  static const cyan = Color(0xFF91CFDE);
  static const boardLight = Color(0xFFE9D7B0); // açık kare
  static const boardDark = Color(0xFF9C6F43); // koyu kare
  static const textDim = Color(0xFFB7C4CD);
  static const line = Color(0x55596D7D);
  static const danger = Color(0xFFE58287);
  static const success = Color(0xFF89CBB0);
  static const warning = Color(0xFFFFB95E);

  static const pieceWhite = Color(0xFFFDFCF7);
  static const pieceBlack = Color(0xFF1A1206);
}

/// Shared motion values keep menus, overlays and result screens feeling like
/// one game instead of a collection of unrelated pages.
class LunoMotion {
  static const pressDown = Duration(milliseconds: 70);
  static const press = Duration(milliseconds: 120);
  static const micro = Duration(milliseconds: 140);
  static const panelEnter = Duration(milliseconds: 210);
  static const panelExit = Duration(milliseconds: 180);
  static const screenForward = Duration(milliseconds: 240);
  static const screenBack = Duration(milliseconds: 200);
  static const modalEnter = Duration(milliseconds: 190);
  static const modalExit = Duration(milliseconds: 160);
  static const pieceSelect = Duration(milliseconds: 120);
  static const pieceMove = Duration(milliseconds: 180);
  static const capture = Duration(milliseconds: 160);
  static const cardSelect = Duration(milliseconds: 140);
  static const cardCast = Duration(milliseconds: 190);
  static const cardImpact = Duration(milliseconds: 240);
  static const reward = Duration(milliseconds: 260);
  static const matchFound = Duration(milliseconds: 220);
  static const result = Duration(milliseconds: 260);
  static const phase = Duration(milliseconds: 180);
  static const screenCurve = Cubic(0.2, 0.82, 0.2, 1.0);
  static const screenExitCurve = Cubic(0.4, 0.0, 1.0, 1.0);
  static const vfxBurst = Duration(milliseconds: 220);

  static Duration adaptive(BuildContext context, Duration duration) {
    final media = MediaQuery.maybeOf(context);
    return media?.disableAnimations == true ? Duration.zero : duration;
  }

  // Compatibility aliases for screens that still use the earlier names.
  static const screen = screenForward;
  static const screenReverse = screenBack;
  static const panel = panelEnter;
}

/// A small, deliberate type scale. Display type is reserved for identity;
/// rounded body type keeps controls readable without competing with headings.
class LunoType {
  const LunoType._();

  static const displayLarge = TextStyle(
    fontFamily: 'Cinzel',
    fontFamilyFallback: ['CinzelTurkish'],
    fontSize: 28,
    fontWeight: FontWeight.w900,
    color: LunoColors.ivory,
    height: 1.08,
  );
  static const displayMedium = TextStyle(
    fontFamily: 'Cinzel',
    fontFamilyFallback: ['CinzelTurkish'],
    fontSize: 22,
    fontWeight: FontWeight.w900,
    color: LunoColors.ivory,
    height: 1.1,
  );
  static const screenTitle = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 17,
    fontWeight: FontWeight.w800,
    color: LunoColors.ivory,
    height: 1.15,
  );
  static const sectionTitle = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 13,
    fontWeight: FontWeight.w800,
    color: LunoColors.gold,
    height: 1.15,
  );
  static const body = TextStyle(
    fontFamily: 'Nunito',
    fontFamilyFallback: ['SpectralTurkish'],
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: Colors.white,
    height: 1.25,
  );
  static const bodyMuted = TextStyle(
    fontFamily: 'Nunito',
    fontFamilyFallback: ['SpectralTurkish'],
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: LunoColors.textDim,
    height: 1.25,
  );
  static const button = TextStyle(
    fontFamily: 'Nunito',
    fontFamilyFallback: ['SpectralTurkish'],
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: LunoColors.bgDeep,
    height: 1.2,
  );
  static const label = TextStyle(
    fontFamily: 'Nunito',
    fontFamilyFallback: ['SpectralTurkish'],
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: LunoColors.textDim,
    height: 1.15,
  );
  static const statNumber = TextStyle(
    fontFamily: 'Cinzel',
    fontFamilyFallback: ['CinzelTurkish'],
    fontSize: 19,
    fontWeight: FontWeight.w900,
    color: LunoColors.gold,
    height: 1,
  );
  static const timer = TextStyle(
    fontFamily: 'Spectral',
    fontFamilyFallback: ['SpectralTurkish'],
    fontSize: 17,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    height: 1,
  );
}

class LunoTheme {
  static ThemeData get dark => darkFor('tr');

  static Widget _buttonFace(
    BuildContext context,
    Set<WidgetState> states,
    Widget? child, {
    bool secondary = false,
  }) => DecoratedBox(
    decoration: BoxDecoration(
      image: DecorationImage(
        image: AssetImage(
          states.contains(WidgetState.disabled)
              ? LunoVisualAssets.disabled
              : secondary
              ? LunoVisualAssets.secondary
              : LunoVisualAssets.primary,
        ),
        centerSlice: LunoVisualAssets.buttonSlice,
        fit: BoxFit.fill,
        opacity: states.contains(WidgetState.pressed) ? 1 : .9,
      ),
    ),
    child: child,
  );

  /// Builds the shared theme with a language-aware primary font.
  ///
  /// Nunito contains both Latin and Turkish glyphs; the existing display
  /// families preserve the game's identity in screen headings.
  static ThemeData darkFor(String language) {
    final isEnglish = language == 'English' || language == 'en';
    const bodyFamily = 'Nunito';
    final bodyFallback = isEnglish ? 'SpectralTurkish' : 'Spectral';

    TextStyle body(TextStyle style) => style.copyWith(
      fontFamily: bodyFamily,
      fontFamilyFallback: [bodyFallback],
    );

    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: LunoColors.bgDeep,
      colorScheme: base.colorScheme.copyWith(
        primary: LunoColors.gold,
        onPrimary: LunoColors.bgDeep,
        primaryContainer: LunoColors.bgRaised,
        onPrimaryContainer: LunoColors.gold,
        secondary: LunoColors.teal,
        onSecondary: LunoColors.bgDeep,
        secondaryContainer: LunoColors.bgRaised,
        onSecondaryContainer: LunoColors.ivory,
        tertiary: LunoColors.cyan,
        onTertiary: LunoColors.bgDeep,
        tertiaryContainer: LunoColors.bgPanel2,
        onTertiaryContainer: LunoColors.cyan,
        surface: LunoColors.bgPanel,
        onSurface: LunoColors.ivory,
        surfaceTint: Colors.transparent,
        outline: LunoColors.textDim,
        outlineVariant: LunoColors.line,
        error: LunoColors.danger,
        onError: LunoColors.bgDeep,
        errorContainer: const Color(0xFF482A30),
        onErrorContainer: const Color(0xFFFFDADD),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: LunoColors.bgPanel,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: body(LunoType.screenTitle),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: LunoColors.bgRaised,
        behavior: SnackBarBehavior.floating,
        elevation: 8,
        contentTextStyle: body(
          LunoType.body.copyWith(fontSize: 14, height: 1.35),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: LunoColors.goldDeep.withValues(alpha: .45)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: LunoColors.bgPanel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: LunoColors.goldDeep.withValues(alpha: .55)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: LunoColors.bgPanel,
          foregroundColor: LunoColors.ivory,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: body(LunoType.button),
          elevation: 3,
          shadowColor: Colors.black54,
        ).copyWith(backgroundBuilder: _buttonFace),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: LunoColors.ivory,
          side: const BorderSide(color: LunoColors.goldDeep),
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: body(LunoType.button.copyWith(color: LunoColors.gold)),
        ).copyWith(
          backgroundBuilder:
              (context, states, child) =>
                  _buttonFace(context, states, child, secondary: true),
        ),
      ),
      cardTheme: CardThemeData(
        color: LunoColors.bgPanel,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: LunoColors.line),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: LunoColors.line,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: LunoColors.bgStage,
        labelStyle: body(LunoType.label),
        hintStyle: body(LunoType.bodyMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: LunoColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: LunoColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: LunoColors.gold, width: 1.5),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: LunoColors.gold,
        textColor: LunoColors.ivory,
        subtitleTextStyle: body(LunoType.bodyMuted),
        minVerticalPadding: 8,
      ),
      textTheme: base.textTheme.apply(
        fontFamily: bodyFamily,
        fontFamilyFallback: [bodyFallback],
        bodyColor: LunoColors.ivory,
        displayColor: LunoColors.ivory,
      ),
    );
  }

  static const menuGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [LunoColors.bgPanel2, LunoColors.bgDeep],
  );
}
