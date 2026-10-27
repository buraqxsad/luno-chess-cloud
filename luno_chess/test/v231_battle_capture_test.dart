import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/cast_stage.dart';
import 'package:luno_chess/battle_ui/cast_trail.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import '../tool/battle_fixture_support.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_ui/visual_test.dart'
    show renderBattle, captureKey, expectNoBattleLayoutError;
import 'helpers/battle_v1_response.dart';

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final context = tester.element(find.byKey(captureKey));
    for (final image in tester.widgetList<Image>(find.byType(Image)).toList()) {
      await precacheImage(image.image, context);
    }
  });
  for (final render in tester.allRenderObjects) {
    render.markNeedsPaint();
  }
  await tester.pump();
  expectNoBattleLayoutError(tester);
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(captureKey),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('qa/v231/frames')
        ..createSync(recursive: true);
      File(
        '${directory.path}/$name.png',
      ).writeAsBytesSync(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setupPracticeTestAssets();
  for (final card in [
    CardId.freeze,
    CardId.shelter,
    CardId.chain,
    CardId.radar,
    CardId.boardSeal,
  ]) {
    testWidgets('V231 actual ${card.wire} accepted cast trail and impact', (
      tester,
    ) async {
      final contract =
          jsonDecode(
                File('../battle_contract/v1/rules.json').readAsStringSync(),
              )
              as Map;
      final fixture = (contract['fixtures'] as List).cast<Map>().singleWhere(
        (f) => f['fixtureId'] == 'card-${card.wire}',
      );
      var state = fixtureInitial(fixture);
      final action = BattleAction.fromJson(
        ((fixture['steps'] as List).first as Map)['action'] as Map,
      );
      var version = 0;
      final controller = await renderBattle(
        tester,
        state: state,
        reducedMotion: false,
        requestOverride: (path, payload) async {
          if (path == '/submitBattleV1Action') {
            state = DeckManager.apply(
              state,
              BattleAction.fromJson(payload['intent'] as Map),
            );
            version++;
          }
          return v1Response(state: state, version: version);
        },
      );
      final expected = DeckManager.apply(state, action).toJson();
      final stage = tester.widget<BattleCastStage>(
        find.byType(BattleCastStage),
      );
      final origin = tester.getCenter(find.byKey(stage.cards[card]!));
      expect(await controller.submit(action), isTrue);
      await tester.pump();
      await tester.pump();
      final flight = find.byKey(ValueKey('card-flight-${card.wire}'));
      expect(flight, findsOneWidget);
      expect((tester.getCenter(flight) - origin).distance, lessThan(1));
      final duration = battleEffectDuration(card).inMilliseconds;
      await tester.pump(Duration(milliseconds: (duration * .16).round()));
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is BattleCastTrailPainter,
        ),
        findsOneWidget,
      );
      await _capture(tester, '${card.wire}-travel');
      await tester.pump(Duration(milliseconds: (duration * .39).round()));
      await _capture(tester, '${card.wire}-impact');
      expect(find.byKey(ValueKey('card-flight-${card.wire}')), findsNothing);
      expect(
        state.toJson(),
        expected,
        reason: 'Effects cannot change rules, costs or timing',
      );
      await tester.pump(Duration(milliseconds: duration));
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is BattleCastTrailPainter,
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  }
}
