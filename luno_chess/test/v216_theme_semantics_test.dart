import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/theme/luno_theme.dart';

double _contrast(Color first, Color second) {
  final a = first.computeLuminance(), b = second.computeLuminance();
  return a >= b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}

void main() {
  for (final language in ['tr', 'en']) {
    test(
      '$language native containers use the Luno palette and legible on-colors',
      () {
        final scheme = LunoTheme.darkFor(language).colorScheme;
        expect(scheme.primary, LunoColors.gold);
        expect(scheme.secondary, LunoColors.teal);
        expect(scheme.tertiary, LunoColors.cyan);
        expect(scheme.primaryContainer, LunoColors.bgRaised);
        expect(scheme.secondaryContainer, LunoColors.bgRaised);
        expect(scheme.tertiaryContainer, LunoColors.bgPanel2);
        expect(scheme.surfaceTint, Colors.transparent);
        for (final pair in [
          (scheme.primary, scheme.onPrimary),
          (scheme.secondary, scheme.onSecondary),
          (scheme.tertiary, scheme.onTertiary),
          (scheme.primaryContainer, scheme.onPrimaryContainer),
          (scheme.secondaryContainer, scheme.onSecondaryContainer),
          (scheme.tertiaryContainer, scheme.onTertiaryContainer),
          (scheme.surface, scheme.onSurface),
          (scheme.error, scheme.onError),
          (scheme.errorContainer, scheme.onErrorContainer),
        ]) {
          expect(_contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
        }
      },
    );
  }
}
