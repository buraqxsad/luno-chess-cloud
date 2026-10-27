import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell, boundaryKey, warm;

void main() {
  setupPracticeTestAssets();
  for (final language in ['tr', 'en']) {
    for (final width in [320.0, 390.0, 430.0, 768.0]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets('four audio controls $language $width scale $scale', (
          tester,
        ) async {
          SharedPreferences.setMockInitialValues({});
          final settings = LunoSettings(deviceLocale: Locale(language));
          await tester.runAsync(settings.load);
          settings.effectsLevel = 3;
          settings.musicLevel = 3;
          tester.view.physicalSize = Size(width, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            shell(
              SettingsScreen(settings: settings),
              language: language,
              scale: scale,
            ),
          );
          await warm(tester);
          final labels =
              language == 'tr'
                  ? ['KAPALI', 'DÜŞÜK', 'ORTA', 'YÜKSEK']
                  : ['OFF', 'LOW', 'MEDIUM', 'HIGH'];
          for (final label in labels) {
            expect(find.text(label), findsNWidgets(2));
            for (final element in find.text(label).evaluate()) {
              final paragraph = element.renderObject! as RenderParagraph;
              expect(paragraph.didExceedMaxLines, isFalse);
              expect(paragraph.text.style?.fontFamily, 'Nunito');
              final target =
                  find
                      .ancestor(
                        of: find.byElementPredicate((e) => e == element),
                        matching: find.byType(InkWell),
                      )
                      .first;
              expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
              expect(tester.getSize(target).width, greaterThanOrEqualTo(48));
            }
          }
          await tester.ensureVisible(find.text(labels.first).first);
          await tester.tap(find.text(labels.first).first);
          await tester.pumpAndSettle();
          expect(settings.effectsLevel, 0);
          expect(settings.soundEnabled, isFalse);
          await tester.ensureVisible(find.text(labels.first).last);
          await tester.tap(find.text(labels.first).last);
          await tester.pumpAndSettle();
          expect(settings.musicLevel, 0);
          expect(settings.musicEnabled, isFalse);
          if (Platform.environment['LUNO_V215_CAPTURE'] == '1') {
            for (final render in tester.allRenderObjects) {
              render.markNeedsPaint();
            }
            await tester.pump();
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(boundaryKey),
              );
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final dir = Directory('qa/v215/audio-captures')
                ..createSync(recursive: true);
              await File(
                '${dir.path}/settings-$language-${width.toInt()}-$scale.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
