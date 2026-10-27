import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/art.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/theme/luno_assets.dart';

const _sets = [
  'ottoman',
  'roma',
  'brit',
  'viking',
  'tasdevri',
  'samuray',
  'ice',
  'dragon',
  'neon',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all nine costumes resolve to 108 unique packaged modern sprites',
    () async {
      final paths = <String>{};
      for (final set in _sets) {
        for (final side in PieceColor.values) {
          for (final type in PieceType.values) {
            final path = BattleArt.piecePath(side, type, set: set);
            expect(path, LunoAssets.pieceForSet(set, side, type));
            expect(path, endsWith('-v216.webp'));
            expect(paths.add(path), isTrue, reason: path);
            final bytes = await rootBundle.load(path);
            final codec = await ui.instantiateImageCodec(
              bytes.buffer.asUint8List(),
            );
            final image = (await codec.getNextFrame()).image;
            expect(image.width, 256, reason: path);
            expect(image.height, 320, reason: path);
            image.dispose();
            codec.dispose();
          }
        }
      }
      expect(paths, hasLength(108));
    },
  );

  test(
    'catalog covers use the corresponding modern complete-set atlas',
    () async {
      final paths = <String>{};
      for (final set in ['luno', ..._sets]) {
        final path = LunoAssets.setPreview(set);
        expect(path, 'assets/native_art/piece-set-$set-v216.webp');
        expect(paths.add(path), isTrue);
        final bytes = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(),
        );
        final image = (await codec.getNextFrame()).image;
        expect(image.width, 960);
        expect(image.height, 400);
        image.dispose();
        codec.dispose();
      }
    },
  );

  test(
    'unknown costume cover falls back to an existing current base atlas',
    () async {
      final fallback = LunoAssets.setPreview('retired-or-malformed');
      expect(fallback, LunoAssets.setPreview('luno'));
      expect((await rootBundle.load(fallback)).lengthInBytes, greaterThan(0));
      for (final side in PieceColor.values) {
        for (final type in PieceType.values) {
          expect(
            BattleArt.piecePath(side, type, set: 'unknown'),
            BattleArt.piecePath(side, type),
          );
        }
      }
    },
  );
}
