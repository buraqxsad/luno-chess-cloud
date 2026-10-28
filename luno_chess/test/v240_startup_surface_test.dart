import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/app.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/theme/luno_theme.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;

void main() {
  setupPracticeTestAssets();
  for (final language in ['tr', 'en']) {
    for (final width in [320.0, 430.0]) {
      for (final scale in [1.0, 2.0]) {
        final name = '$language-${width.toInt()}-text$scale';
        testWidgets('V240 real startup surface $name has no fallback underlines', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          const captureKey = ValueKey('v240-loader-capture');
          // StartupGate renders this directly, without an enclosing Scaffold.
          // Adding a Scaffold here would conceal the production inheritance bug.
          await tester.pumpWidget(
            RepaintBoundary(
              key: captureKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: LunoTheme.darkFor(language),
                locale: Locale(language),
                supportedLocales: LunoLocalizations.supportedLocales,
                localizationsDelegates: const [
                  LunoLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                builder:
                    (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    ),
                home: const LunoLoadingArtwork(),
              ),
            ),
          );
          await tester.runAsync(() async {
            final context = tester.element(find.byType(LunoLoadingArtwork));
            for (final widget in tester.widgetList<Image>(find.byType(Image))) {
              await precacheImage(widget.image, context);
            }
          });
          await tester.pump();
          const output = String.fromEnvironment('LUNO_V240_CAPTURE_DIRECTORY');
          if (output.isNotEmpty) {
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(captureKey),
              );
              final image = await boundary.toImage(pixelRatio: 1);
              try {
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                File('$output/$name.png')
                  ..parent.createSync(recursive: true)
                  ..writeAsBytesSync(bytes!.buffer.asUint8List());
              } finally {
                image.dispose();
              }
            });
          }
          final texts = find.descendant(
            of: find.byType(LunoLoadingArtwork),
            matching: find.byType(RichText),
          );
          expect(texts, findsNWidgets(3));
          for (final text in tester.widgetList<RichText>(texts)) {
            expect(
              (text.text.style?.decoration ?? TextDecoration.none).contains(
                TextDecoration.underline,
              ),
              isFalse,
              reason:
                  'Startup text must not inherit DefaultTextStyle.fallback double yellow underline.',
            );
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
