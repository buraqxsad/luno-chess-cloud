import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/spell_choreography.dart';
import 'package:luno_chess/battle_ui/spell_motifs.dart';
import 'package:luno_chess/battle_v1/model.dart';

Future<Uint8List> pixels(
  CardId card,
  double t, {
  double r = 44,
  Color color = Colors.cyan,
  double strength = 1,
  bool up = true,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..translate(90, 90);
  paintBattleSpellChoreography(
    canvas,
    card,
    r,
    t,
    color,
    strength,
    forwardUp: up,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(180, 180);
  try {
    return Uint8List.fromList((await image.toByteData())!.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}

int visible(Uint8List bytes) {
  var count = 0;
  for (var i = 3; i < bytes.length; i += 4) {
    if (bytes[i] > 12) count++;
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('24 secondary silhouettes animate with a clear piece centre', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final identities = <int>{};
      for (final card in CardId.values) {
        final phases = <int>{};
        for (final t in [.12, .46, .8]) {
          final data = await pixels(card, t);
          expect(visible(data), greaterThan(20), reason: '${card.wire}/$t');
          expect(visible(data), lessThan(180 * 180 ~/ 3));
          phases.add(Object.hashAll(data));
          for (var y = 82; y < 98; y++) {
            for (var x = 82; x < 98; x++) {
              expect(
                data[(y * 180 + x) * 4 + 3],
                0,
                reason:
                    '${card.wire}: added accents must leave the piece visible',
              );
            }
          }
          if (t == .46) identities.add(Object.hashAll(data));
        }
        expect(phases, hasLength(3), reason: '${card.wire} must move');
        expect(visible(await pixels(card, .46, up: false)), greaterThan(20));
      }
      expect(
        identities,
        hasLength(24),
        reason: 'Identity must differ even at identical color',
      );
    });
  });
  testWidgets('invalid, finished and transparent choreography is empty', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final card in CardId.values) {
        for (final t in [double.nan, double.infinity, -1.0, 0.0, 1.0, 2.0]) {
          expect(visible(await pixels(card, t)), 0);
        }
        expect(visible(await pixels(card, .5, r: double.nan)), 0);
        expect(visible(await pixels(card, .5, color: Colors.transparent)), 0);
        expect(visible(await pixels(card, .5, strength: double.infinity)), 0);
      }
    });
  });
  testWidgets('new Blender textures stay within a shared 9MiB decoded budget', (
    tester,
  ) async {
    await tester.runAsync(() async {
      var decodedBytes = 0, compressedBytes = 0;
      for (final motif in BattleSpellMotif.values) {
        final asset = await rootBundle.load(motif.asset);
        compressedBytes += asset.lengthInBytes;
        expect(asset.lengthInBytes, lessThan(256 * 1024));
        final codec = await ui.instantiateImageCodec(
          asset.buffer.asUint8List(),
        );
        final frame = await codec.getNextFrame();
        try {
          expect(frame.image.width, 768);
          expect(frame.image.height, 768);
          decodedBytes += frame.image.width * frame.image.height * 4;
          final rgba = (await frame.image.toByteData())!.buffer.asUint8List();
          final phases = <int>{};
          for (var i = 0; i < 16; i++) {
            final left = i % 4 * 192, top = i ~/ 4 * 192;
            var opaque = 0;
            final signature = <int>[];
            for (var y = 0; y < 192; y++) {
              for (var x = 0; x < 192; x++) {
                final alpha = rgba[((top + y) * 768 + left + x) * 4 + 3];
                signature.add(alpha);
                if (alpha > 12) opaque++;
                if ((x - 96).abs() < 8 && (y - 96).abs() < 8) {
                  expect(alpha, lessThan(16));
                }
              }
            }
            expect(opaque, greaterThan(200));
            expect(opaque, lessThan(192 * 192 ~/ 2));
            phases.add(Object.hashAll(signature));
          }
          expect(phases, hasLength(16), reason: motif.name);
        } finally {
          frame.image.dispose();
          codec.dispose();
        }
      }
      expect(decodedBytes, lessThanOrEqualTo(9 * 1024 * 1024));
      expect(compressedBytes, lessThan(640 * 1024));
      expect(CardId.values.map(battleSpellMotif).toSet(), hasLength(4));
    });
  });
}
