import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/cast_stage.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_ui/visual_test.dart' show renderBattle, captureKey;
import 'helpers/battle_v1_response.dart';
import 'v219_battle_presentation_support.dart' show v219Cast;

Future<void> frame(WidgetTester tester, String name, int elapsedMs) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(captureKey),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('qa/v219/full-battle-frames')
      ..createSync(recursive: true);
    File(
      '${directory.path}/$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
    File('${directory.path}/$name.json').writeAsStringSync(
      jsonEncode({
        'fixture':
            'Rendered native BattleV1Screen, mocked authoritative transport',
        'elapsedPresentationMs': elapsedMs,
        'logicalViewport': {'width': 390, 'height': 844},
        'devicePixelRatio': 1,
        'capturePixelRatio': 2,
      }),
    );
    image.dispose();
  });
}

void main() {
  setupPracticeTestAssets();
  for (final card in [
    CardId.shelter,
    CardId.mine,
    CardId.freeze,
    CardId.boardSeal,
  ]) {
    for (final viewer in PieceColor.values) {
      testWidgets('V219 accepted ${card.wire} full battle ${viewer.name}', (
        tester,
      ) async {
        final pair = v219Cast(card);
        var state = pair.before;
        var version = 0;
        final controller = await renderBattle(
          tester,
          state: state,
          viewer: viewer,
          reducedMotion: false,
          requestOverride: (path, payload) async {
            if (path == '/submitBattleV1Action') {
              state = DeckManager.apply(
                state,
                BattleAction.fromJson(payload['intent'] as Map),
              );
              version++;
            }
            return v1Response(state: state, version: version, side: viewer);
          },
        );
        final prefix = '${card.wire}-${viewer.name}';
        await frame(tester, '$prefix-before', 0);
        if (viewer == PieceColor.white) {
          final action = controller.legalActions.firstWhere(
            (action) => action is PlayCardAction && action.card == card,
          );
          expect(await controller.submit(action), isTrue);
        } else {
          state = pair.after;
          version++;
          await controller.reconnect(synchronization: false);
        }
        await tester.pump();
        await tester.pump();
        expect(controller.snapshot!.stateVersion, 1);
        expect(find.byType(BattleCastStage), findsOneWidget);
        final duration = battleEffectDuration(card).inMilliseconds;
        final travel = (duration * .35).round();
        await tester.pump(Duration(milliseconds: travel));
        expect(
          find.byKey(ValueKey('card-flight-${card.wire}')),
          findsOneWidget,
        );
        await frame(tester, '$prefix-travel', travel);
        final impact = battleImpactDelay(card) + 20;
        await tester.pump(Duration(milliseconds: impact - travel));
        await frame(tester, '$prefix-impact', impact);
        await tester.pump(Duration(milliseconds: duration - impact + 100));
        await frame(tester, '$prefix-cleared', duration + 100);
        expect(find.byKey(ValueKey('card-flight-${card.wire}')), findsNothing);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey &&
                (widget.key as ValueKey).value.toString().startsWith(
                  'impact-ring-',
                ),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
