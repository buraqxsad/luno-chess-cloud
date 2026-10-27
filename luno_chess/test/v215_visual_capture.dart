import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'battle_tutorial_v207_test.dart' show boundaryKey, warm;

Future<void> captureV215(WidgetTester tester, String name) async {
  await warm(tester);
  await tester.runAsync(() async {
    final context = tester.element(find.byType(Scaffold).first);
    final images = <ImageProvider>{};
    void include(Decoration? decoration) {
      if (decoration is BoxDecoration && decoration.image != null) {
        images.add(decoration.image!.image);
      }
    }

    for (final widget in tester.widgetList<Container>(find.byType(Container))) {
      include(widget.decoration);
    }
    for (final widget in tester.widgetList<AnimatedContainer>(
      find.byType(AnimatedContainer),
    )) {
      include(widget.decoration);
    }
    for (final widget in tester.widgetList<DecoratedBox>(
      find.byType(DecoratedBox),
    )) {
      include(widget.decoration);
    }
    for (final image in images) {
      await precacheImage(image, context);
    }
  });
  await tester.pumpAndSettle();
  for (final render in tester.allRenderObjects) {
    render.markNeedsPaint();
  }
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        tester.element(find.byKey(boundaryKey)).renderObject!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('qa/v215/visual').create(recursive: true);
    await File(
      'qa/v215/visual/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}
