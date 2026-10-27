import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/cosmetic_catalog.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:luno_chess/widgets/cosmetic_emote_art.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell, boundaryKey;

// Frozen V216 art implementation read before this worker's production changes.
// Render it without swapping a shared production file beneath the parent runner.
class _BeforeEmoteArt extends StatelessWidget {
  const _BeforeEmoteArt({required this.id, required this.size});
  final String id;
  final double size;
  @override
  Widget build(BuildContext context) {
    final artwork = LunoArt(LunoAssets.emoji(id), width: size, height: size);
    if (MediaQuery.disableAnimationsOf(context)) return artwork;
    final tilt = switch (id) {
      'cry' || 'think' => -.08,
      'laugh' || 'smile' || 'star' => .08,
      'angry' || 'fire' || 'thunder' => -.035,
      _ => .035,
    };
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 640),
      curve: Curves.easeOutCubic,
      child: artwork,
      builder:
          (_, value, child) => Transform.translate(
            offset: Offset(0, -8 * math.sin(value * math.pi)),
            child: Transform.rotate(
              angle: tilt * math.sin(value * math.pi),
              child: Transform.scale(scale: .78 + .22 * value, child: child),
            ),
          ),
    );
  }
}

void main() {
  setupPracticeTestAssets();
  final phase = Platform.environment['LUNO_V216_1_EMOTE_PHASE'] ?? 'after';
  if (!['before', 'after'].contains(phase)) {
    throw ArgumentError('Expected before/after');
  }
  final sources = [
    'lib/widgets/cosmetic_emote_art.dart',
    'lib/services/luno_audio_service.dart',
    'test/v216_1_emote_capture_test.dart',
  ];
  final sourceSnapshot = {
    for (final source in sources) source: File(source).readAsStringSync(),
  };

  test('all fourteen motion signatures are distinct, bounded and settle', () {
    final signatures = <String>{};
    for (final item in cosmeticEmotes) {
      final signature = <double>[];
      for (var i = 0; i <= 100; i++) {
        final pose = cosmeticEmotePose(item.id, i / 100);
        expect(pose.x.abs(), lessThanOrEqualTo(.06));
        expect(pose.y.abs(), lessThanOrEqualTo(.061));
        expect(pose.angle.abs(), lessThanOrEqualTo(.17));
        expect(pose.scale, inInclusiveRange(.80, 1.08));
        signature.addAll([pose.x, pose.y, pose.angle, pose.scale]);
      }
      signatures.add(signature.map((v) => v.toStringAsFixed(5)).join(','));
      expect(cosmeticEmotePose(item.id, 1), (
        x: 0.0,
        y: 0.0,
        angle: 0.0,
        scale: 1.0,
      ));
      expect(
        cosmeticEmoteDuration(item.id).inMilliseconds,
        inInclusiveRange(500, 1100),
      );
    }
    expect(signatures.length, 14);
    expect(cosmeticEmoteDuration('unknown'), Duration.zero);
  });

  for (final language in ['tr', 'en']) {
    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(768, 1024),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('real emote frames $phase $language $size text$scale', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            shell(
              const Scaffold(body: SizedBox()),
              language: language,
              scale: scale,
            ),
          );
          final context = tester.element(find.byType(Scaffold));
          await tester.runAsync(() async {
            for (final item in cosmeticEmotes) {
              for (final pixels in [54, 64]) {
                await precacheImage(
                  ResizeImage.resizeIfNeeded(
                    pixels,
                    null,
                    AssetImage(LunoAssets.emoji(item.id)),
                  ),
                  context,
                );
              }
            }
          });
          await tester.pumpWidget(
            shell(
              Scaffold(
                body: SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          language == 'tr' ? 'İfadeler' : 'Emotes',
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                      Expanded(
                        child: GridView.count(
                          crossAxisCount: size.width < 600 ? 4 : 7,
                          padding: const EdgeInsets.all(12),
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          children: [
                            for (final item in cosmeticEmotes)
                              Center(
                                child: Semantics(
                                  label: item.title(language == 'en'),
                                  child:
                                      phase == 'before'
                                          ? _BeforeEmoteArt(
                                            id: item.id,
                                            size: 64,
                                          )
                                          : CosmeticEmoteArt(
                                            id: item.id,
                                            size: 64,
                                          ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              language: language,
              scale: scale,
            ),
          );
          final name =
              '$language-${size.width.toInt()}x${size.height.toInt()}-$scale';
          var elapsed = 0;
          for (final at in [0, 120, 300, 600, 1200]) {
            await tester.pump(Duration(milliseconds: at - elapsed));
            elapsed = at;
            final raw =
                tester.widgetList<RawImage>(find.byType(RawImage)).toList();
            expect(raw.length, 14);
            expect(
              raw.every((image) => image.image != null),
              isTrue,
              reason: 'All actual emote assets must decode',
            );
            for (final render in tester.allRenderObjects) {
              render.markNeedsPaint();
            }
            await tester.pump();
            await tester.runAsync(() async {
              final dir = Directory('qa/v216_1/$phase/emotes')
                ..createSync(recursive: true);
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(boundaryKey),
              );
              final image = await boundary.toImage(pixelRatio: 1);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              File(
                '${dir.path}/$name-$at.png',
              ).writeAsBytesSync(bytes!.buffer.asUint8List());
              image.dispose();
              File('${dir.path}/$name-source.json').writeAsStringSync(
                jsonEncode({
                  'phase': phase,
                  'baseline':
                      phase == 'before'
                          ? 'frozen V216 implementation in this test'
                          : null,
                  'order': cosmeticEmotes.map((e) => e.id).toList(),
                  'sources': sourceSnapshot,
                }),
              );
            });
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox());
          for (final source in sources) {
            expect(
              File(source).readAsStringSync(),
              sourceSnapshot[source],
              reason: 'Source changed during capture: $source',
            );
          }
        });
      }
    }
  }

  for (final item in cosmeticEmotes) {
    testWidgets('real 160px reveal frame $phase ${item.id}', (tester) async {
      tester.view.physicalSize = const Size(320, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(shell(const Scaffold(body: SizedBox())));
      final context = tester.element(find.byType(Scaffold));
      await tester.runAsync(() async {
        for (final pixels in [135, 160]) {
          await precacheImage(
            ResizeImage.resizeIfNeeded(
              pixels,
              null,
              AssetImage(LunoAssets.emoji(item.id)),
            ),
            context,
          );
        }
      });
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: Center(
              child:
                  phase == 'before'
                      ? _BeforeEmoteArt(id: item.id, size: 160)
                      : CosmeticEmoteArt(id: item.id, size: 160),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      await tester.runAsync(() async {
        final dir = Directory('qa/v216_1/$phase/emotes')
          ..createSync(recursive: true);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundaryKey),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          '${dir.path}/reveal-${item.id}-160px-300.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
        File('${dir.path}/reveal-${item.id}-source.json').writeAsStringSync(
          jsonEncode({
            'phase': phase,
            'id': item.id,
            'sources': sourceSnapshot,
            'baseline':
                phase == 'before'
                    ? 'frozen V216 implementation in this test'
                    : null,
          }),
        );
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      for (final source in sources) {
        expect(
          File(source).readAsStringSync(),
          sourceSnapshot[source],
          reason: 'Source changed during capture: $source',
        );
      }
    });
  }

  for (final stop in ['reduced', 'hidden', 'paused']) {
    testWidgets('$stop settles one-shot art and never resumes stale motion', (
      tester,
    ) async {
      // No MaterialApp/AnimatedTheme: only the art controller is under test.
      Widget page({bool reduced = false, bool visible = true}) => MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: TickerMode(
            enabled: visible,
            child: const Center(child: CosmeticEmoteArt(id: 'rainbow')),
          ),
        ),
      );
      AnimationController artController() =>
          tester
                  .widget<AnimatedBuilder>(
                    find.descendant(
                      of: find.byType(CosmeticEmoteArt),
                      matching: find.byType(AnimatedBuilder),
                    ),
                  )
                  .animation
              as AnimationController;
      void expectSettled() {
        expect(artController().value, 1);
        expect(artController().status, AnimationStatus.completed);
        expect(artController().isAnimating, isFalse);
        final transforms = tester.widgetList<Transform>(
          find.descendant(
            of: find.byType(CosmeticEmoteArt),
            matching: find.byType(Transform),
          ),
        );
        expect(transforms, hasLength(3));
        expect(transforms.every((t) => t.transform.isIdentity()), isTrue);
      }

      await tester.pumpWidget(page());
      await tester.pump(const Duration(milliseconds: 120));
      expect(artController().isAnimating, isTrue);
      expect(artController().value, inExclusiveRange(0, 1));
      if (stop == 'reduced') await tester.pumpWidget(page(reduced: true));
      if (stop == 'hidden') await tester.pumpWidget(page(visible: false));
      if (stop == 'paused') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      }
      await tester.pump();
      expectSettled();
      await tester.pumpWidget(page());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expectSettled();
      await tester.pump(const Duration(milliseconds: 120));
      expectSettled();
      await tester.pump(const Duration(milliseconds: 1100));
      expectSettled();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
}
