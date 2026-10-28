import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/spell_motifs.dart';

void main() {
  testWidgets('V239 atlas decode and image-cache observations are host-only', (
    tester,
  ) async {
    final observations = <Map<String, Object>>[];
    final cache = PaintingBinding.instance.imageCache;
    final cacheBefore = cache.currentSizeBytes;
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox).first);
    await tester.runAsync(() async {
      for (final motif in BattleSpellMotif.values) {
        final asset = await rootBundle.load(motif.asset);
        final watch = Stopwatch()..start();
        final codec = await ui.instantiateImageCodec(
          asset.buffer.asUint8List(),
        );
        final frame = await codec.getNextFrame();
        watch.stop();
        try {
          expect(frame.image.width, 768);
          expect(frame.image.height, 768);
          observations.add({
            'asset': motif.asset,
            'compressed_bytes': asset.lengthInBytes,
            'decoded_rgba_bytes': frame.image.width * frame.image.height * 4,
            'host_decode_wall_microseconds': watch.elapsedMicroseconds,
          });
        } finally {
          frame.image.dispose();
          codec.dispose();
        }
        await precacheImage(AssetImage(motif.asset), context);
      }
    });
    await tester.pump();
    expect(
      observations.fold<int>(
        0,
        (sum, row) => sum + (row['decoded_rgba_bytes'] as int),
      ),
      9 * 1024 * 1024,
    );
    const output = String.fromEnvironment('LUNO_V239_ASSET_OBSERVATION');
    if (output.isNotEmpty) {
      final result = {
        'scope':
            'Flutter software widget worker, not an Android profile benchmark',
        'textures': observations,
        'image_cache_before_bytes': cacheBefore,
        'image_cache_after_bytes': cache.currentSizeBytes,
        'image_cache_live_count': cache.liveImageCount,
        'image_cache_pending_count': cache.pendingImageCount,
        'gpu_texture_allocation': null,
        'android_total_pss_bytes': null,
        'android_build_raster_p95_p99': null,
        'performance_acceptance': 'NOT RUN',
      };
      await tester.runAsync(() async {
        File(output)
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(result),
          );
      });
    }
    await tester.pumpWidget(const SizedBox());
  });
}
