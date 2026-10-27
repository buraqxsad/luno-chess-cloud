import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/cast_trail.dart';
import 'package:luno_chess/battle_ui/feedback.dart';
import 'package:luno_chess/battle_ui/spell_material.dart';
import 'package:luno_chess/battle_ui/spell_vfx.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'v219_battle_presentation_support.dart' show loadV219PresentationFonts;

Future<Uint8List> _pixels(void Function(Canvas) paint, {int size = 180}) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  try {
    return Uint8List.fromList((await image.toByteData())!.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}

int _visible(Uint8List data) {
  var result = 0;
  for (var i = 3; i < data.length; i += 4) {
    if (data[i] > 12) result++;
  }
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadV219PresentationFonts);
  for (final card in CardId.values) {
    testWidgets('V231 ${card.wire} has distinct animated material phases', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final signatures = <int>{};
        for (final progress in [.08, .42, .78]) {
          final pixels = await _pixels((canvas) {
            canvas.translate(90, 90);
            paintBattleSpellMaterial(
              canvas,
              card,
              44,
              progress,
              battleAbilityColor(card),
              .9,
            );
          });
          expect(
            _visible(pixels),
            greaterThan(20),
            reason: '${card.wire}/$progress',
          );
          expect(
            _visible(pixels),
            lessThan(180 * 180 ~/ 3),
            reason: 'No opaque board-covering flash',
          );
          signatures.add(Object.hashAll(pixels));
        }
        expect(signatures, hasLength(3), reason: 'Not a static sticker');
      });
    });
  }

  testWidgets(
    'V231 all 24 material identities differ and produce a review sheet',
    (tester) async {
      await tester.runAsync(() async {
        final identities = <int>{};
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        for (final card in CardId.values) {
          identities.add(
            Object.hashAll(
              await _pixels((c) {
                c.translate(90, 90);
                // Same color deliberately: identity must come from shape and motion.
                paintBattleSpellMaterial(c, card, 44, .42, Colors.cyan, .9);
              }),
            ),
          );
          final x = (card.index % 6) * 180.0;
          final y = (card.index ~/ 6) * 180.0;
          canvas.save();
          canvas.translate(x, y);
          canvas.clipRect(const Rect.fromLTWH(0, 0, 180, 180));
          for (var row = 0; row < 4; row++) {
            for (var col = 0; col < 4; col++) {
              canvas.drawRect(
                Rect.fromLTWH(col * 45.0, row * 45.0, 45, 45),
                Paint()
                  ..color =
                      (row + col).isEven
                          ? const Color(0xff647d78)
                          : const Color(0xff314d4a),
              );
            }
          }
          canvas.save();
          canvas.translate(90, 78);
          paintBattleSpellMaterial(
            canvas,
            card,
            44,
            .42,
            battleAbilityColor(card),
            .9,
          );
          canvas.restore();
          canvas.drawRect(
            const Rect.fromLTWH(0, 150, 180, 30),
            Paint()..color = const Color(0xff112824),
          );
          final label = TextPainter(
            text: TextSpan(
              text: card.wire,
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 13,
                color: Colors.white,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: 172);
          label.paint(canvas, Offset(4, 156));
          label.dispose();
          canvas.restore();
        }
        expect(identities, hasLength(24));
        final picture = recorder.endRecording();
        final image = await picture.toImage(1080, 720);
        try {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory('qa/v231/frames')
            ..createSync(recursive: true);
          File(
            '${directory.path}/material-identities.png',
          ).writeAsBytesSync(png!.buffer.asUint8List());
        } finally {
          image.dispose();
          picture.dispose();
        }
      });
    },
  );

  testWidgets('V231 nonfinite material inputs are safely ignored', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final input in [double.nan, double.infinity, -1.0]) {
        expect(
          _visible(
            await _pixels(
              (c) => paintBattleSpellMaterial(
                c,
                CardId.freeze,
                44,
                input,
                Colors.cyan,
                .9,
              ),
            ),
          ),
          0,
        );
        expect(
          _visible(
            await _pixels(
              (c) => paintBattleSpellMaterial(
                c,
                CardId.freeze,
                input,
                .5,
                Colors.cyan,
                .9,
              ),
            ),
          ),
          0,
        );
      }
    });
  });

  testWidgets('V231 real-origin trail moves, lands and disappears', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final signatures = <int>{};
      for (final progress in [.05, .15, .29, .35]) {
        final data = await _pixels(
          (c) => BattleCastTrailPainter(
            card: CardId.freeze,
            from: const Offset(30, 160),
            to: const Offset(135, 40),
            progress: progress,
            color: Colors.cyan,
          ).paint(c, const Size.square(180)),
        );
        expect(_visible(data), greaterThan(10));
        signatures.add(Object.hashAll(data));
      }
      expect(signatures, hasLength(4));
      for (final progress in [double.nan, -1.0, 0.0, .4, 1.0]) {
        expect(
          _visible(
            await _pixels(
              (c) => BattleCastTrailPainter(
                card: CardId.freeze,
                from: const Offset(30, 160),
                to: const Offset(135, 40),
                progress: progress,
                color: Colors.cyan,
              ).paint(c, const Size.square(180)),
            ),
          ),
          0,
        );
      }
    });
  });

  testWidgets('V231 completed impacts are empty and clipped at board edges', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final card in CardId.values) {
        for (final progress in [double.nan, -1.0, 0.0, 1.0, 2.0]) {
          expect(
            _visible(
              await _pixels(
                (c) => BattleSpellPainter(
                  cue: BattleSpellCue(card, PieceColor.white, const [0]),
                  viewer: PieceColor.white,
                  progress: progress,
                  color: battleAbilityColor(card),
                ).paint(c, const Size.square(120)),
              ),
            ),
            0,
          );
        }
        final data = await _pixels(
          (c) => BattleSpellPainter(
            cue: BattleSpellCue(card, PieceColor.white, const [0]),
            viewer: PieceColor.white,
            progress: .55,
            color: battleAbilityColor(card),
          ).paint(c, const Size.square(120)),
        );
        for (var y = 0; y < 180; y++) {
          for (var x = 0; x < 180; x++) {
            if (x >= 120 || y >= 120) {
              expect(
                data[(y * 180 + x) * 4 + 3],
                0,
                reason: '${card.wire} escaped board',
              );
            }
          }
        }
      }
    });
  });
}
