import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell, boundaryKey, warm;

void main() {
  setupPracticeTestAssets();
  setUpAll(() async {
    await LunoSettings.instance.load();
  });
  for (final language in ['tr', 'en']) {
    for (final width in [320.0, 390.0, 430.0, 768.0]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets('audio controls render $language $width $scale', (
          tester,
        ) async {
          final settings = LunoSettings.instance;
          settings.language =
              language == 'tr'
                  ? LunoSettings.languageTurkish
                  : LunoSettings.languageEnglish;
          settings.effectsLevel = 0;
          settings.musicLevel = 0;
          tester.view.physicalSize = Size(width, width == 768 ? 1024 : 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            shell(const SettingsScreen(), language: language, scale: scale),
          );
          await warm(tester);
          await tester.runAsync(() async {
            final context = tester.element(find.byType(Scaffold).first);
            final providers = <ImageProvider>{};
            for (final widget in tester.widgetList<DecoratedBox>(
              find.byType(DecoratedBox),
            )) {
              final decoration = widget.decoration;
              if (decoration is BoxDecoration && decoration.image != null) {
                providers.add(decoration.image!.image);
              }
            }
            for (final provider in providers) {
              await precacheImage(provider, context);
            }
          });
          for (final render in tester.allRenderObjects) {
            render.markNeedsPaint();
          }
          await tester.pumpAndSettle();
          final off = language == 'tr' ? 'KAPALI' : 'OFF';
          expect(find.text(off), findsNWidgets(2));
          for (final label
              in language == 'tr'
                  ? ['KAPALI', 'DÜŞÜK', 'ORTA', 'YÜKSEK']
                  : ['OFF', 'LOW', 'MEDIUM', 'HIGH']) {
            for (final element in find.text(label).evaluate()) {
              final paragraph = element.renderObject! as RenderParagraph;
              expect(paragraph.didExceedMaxLines, isFalse, reason: label);
            }
          }
          final phase =
              Platform.environment['LUNO_V216_AUDIO_PHASE'] ?? 'after';
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(boundaryKey),
            );
            final image = await boundary.toImage(pixelRatio: 1);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final dir = Directory('qa/v216/$phase/audio')
              ..createSync(recursive: true);
            await File(
              '${dir.path}/settings-$language-${width.toInt()}-$scale.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
