import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:luno_chess/data/card_pool.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/collection_screens.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:luno_chess/theme/luno_theme.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show boundaryKey;
import 'v215_cosmetic_surfaces_test.dart' show capture;

void main() {
  setupPracticeTestAssets();
  test('every costume has both colors for all six piece types', () {
    for (final id in kPieceSetIds) {
      for (final color in PieceColor.values) {
        for (final type in PieceType.values) {
          final path = LunoAssets.pieceForSet(id, color, type);
          expect(
            File(path).existsSync(),
            true,
            reason: '$id $color $type: $path',
          );
        }
      }
    }
  });
  for (final language in ['tr', 'en']) {
    for (final size in [
      const Size(320, 568),
      const Size(568, 320),
      const Size(800, 1280),
    ]) {
      testWidgets('$language all costume previews fit $size with double text', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = GameStore.instance;
        final original = store.data;
        addTearDown(() => store.data = original);
        store.data = PlayerData.initial();
        await tester.pumpWidget(
          MaterialApp(
            theme: LunoTheme.dark,
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
                  ).copyWith(textScaler: const TextScaler.linear(2)),
                  child: RepaintBoundary(key: boundaryKey, child: child!),
                ),
            home: const PieceCostumeScreen(),
          ),
        );
        await tester.pump();
        for (final color in PieceColor.values) {
          final selector = find.byType(SegmentedButton<PieceColor>);
          await tester.scrollUntilVisible(
            selector,
            -200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pump();
          await tester.tap(
            find.text(
              color == PieceColor.white
                  ? (language == 'en' ? 'White' : 'Beyaz')
                  : (language == 'en' ? 'Black' : 'Siyah'),
            ),
          );
          await tester.pumpAndSettle();
          expect(store.data.pieceSet, 'luno');
          expect(
            tester.widget<SegmentedButton<PieceColor>>(selector).selected,
            {color},
          );
          await capture(
            tester,
            'costumes-double-$language-${size.width.toInt()}-${size.height.toInt()}-${color.name}-first',
          );
          for (final id in kPieceSetIds) {
            final preview = find.byWidgetPredicate(
              (w) => w is CostumeBoardPreview && w.setId == id,
            );
            await tester.scrollUntilVisible(
              preview,
              180,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pump();
            final board = find.descendant(
              of: preview,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is SizedBox &&
                    widget.width != null &&
                    widget.height != null &&
                    widget.width == widget.height! * 6,
              ),
            );
            expect(board, findsOneWidget, reason: id);
            final previewRect = tester.getRect(board);
            final cell = previewRect.height;
            expect(cell, inInclusiveRange(40, 64), reason: id);
            expect(previewRect.width, closeTo(cell * 6, .01), reason: id);
            expect(previewRect.left, greaterThanOrEqualTo(0), reason: id);
            expect(
              previewRect.right,
              lessThanOrEqualTo(size.width),
              reason: id,
            );
            for (final type in CostumeBoardPreview.types) {
              final path = CostumeBoardPreview.assetFor(id, color, type);
              final piece = find.descendant(
                of: preview,
                matching: find.byWidgetPredicate((w) {
                  if (w is! Image) return false;
                  ImageProvider provider = w.image;
                  while (provider is ResizeImage) {
                    provider = provider.imageProvider;
                  }
                  return provider is AssetImage && provider.assetName == path;
                }),
              );
              expect(piece, findsOneWidget, reason: '$id $color $type');
              final rect = tester.getRect(piece);
              expect(rect.width, closeTo(cell - 4, .01), reason: path);
              expect(rect.height, closeTo(cell - 4, .01), reason: path);
              expect(previewRect.contains(rect.topLeft), isTrue, reason: path);
              expect(
                previewRect.contains(rect.bottomRight),
                isTrue,
                reason: path,
              );
            }
            expect(tester.takeException(), isNull, reason: id);
          }
          await capture(
            tester,
            'costumes-double-$language-${size.width.toInt()}-${size.height.toInt()}-${color.name}-last',
          );
        }
      });
    }
  }
}
