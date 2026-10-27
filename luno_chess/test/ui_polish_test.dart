import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:luno_chess/widgets/luno_surface.dart';

void main() {
  testWidgets(
    'buttons keep disabled/loading guards and notices replace stale feedback',
    (tester) async {
      for (final channel in [
        'xyz.luan/audioplayers.global/events',
        'xyz.luan/audioplayers.global',
        'xyz.luan/audioplayers',
        for (final id in ['luno_music', 'luno_sfx_0', 'luno_sfx_1', 'luno_sfx_2'])
          'xyz.luan/audioplayers/events/$id',
      ]) {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          MethodChannel(channel), (_) async => null,
        );
      }
      await tester.runAsync(() async {
        for (final entry
            in {
              'Cinzel': 'assets/fonts/cinzel-latin.ttf',
              'Nunito': 'assets/fonts/nunito/nunito-variable.ttf',
              'CinzelTurkish': 'assets/fonts/cinzel-turkish.ttf',
              'Spectral': 'assets/fonts/spectral/spectral-regular-latin.ttf',
              'SpectralTurkish':
                  'assets/fonts/spectral/spectral-regular-turkish.ttf',
            }.entries) {
          await (FontLoader(entry.key)
            ..addFont(rootBundle.load(entry.value))).load();
        }
        await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var taps = 0;
      final boundaryKey = GlobalKey();
      late BuildContext noticeContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: LunoTheme.dark,
          home: RepaintBoundary(
            key: boundaryKey,
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  noticeContext = context;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(24, 100, 24, 24),
                    child: Column(
                      children: [
                        LunoButton(
                          label: 'SAVAŞA GİR',
                          icon: Icons.sports_esports,
                          onPressed: () => taps++,
                        ),
                        const SizedBox(height: 16),
                        LunoButton(
                          label: 'ARKADAŞINI DAVET ET',
                          kind: LunoButtonKind.secondary,
                          onPressed: () => taps++,
                        ),
                        const SizedBox(height: 16),
                        const LunoButton(label: 'ÖDÜL ALINDI', onPressed: null),
                        const SizedBox(height: 16),
                        LunoButton(
                          label: 'BAĞLAN',
                          loading: true,
                          onPressed: () => taps++,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ÖDÜL ALINDI'));
      await tester.tap(find.byType(LunoButton).last);
      expect(taps, 0);
      await tester.tap(find.text('SAVAŞA GİR'));
      await tester.pump(const Duration(milliseconds: 180));
      expect(taps, 1);
      await tester.runAsync(
        () => precacheImage(
          const ResizeImage(
            AssetImage(LunoAssets.settingsNotification),
            width: 32,
          ),
          noticeContext,
        ),
      );
      showLunoNotice(noticeContext, 'Eski bildirim');
      await tester.pump(const Duration(milliseconds: 300));
      showLunoNotice(noticeContext, 'Desten kaydedildi. Savaşa hazırsın!');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Eski bildirim'), findsNothing);
      expect(find.text('Desten kaydedildi. Savaşa hazırsın!'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('qa').create(recursive: true);
        await File(
          'qa/ui-polish-2026-09-08.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
