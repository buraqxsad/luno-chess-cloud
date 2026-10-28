import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_ui/spell_halo.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';

import '../tool/battle_fixture_support.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_ui/visual_test.dart'
    show captureKey, renderBattle, expectNoBattleLayoutError;
import 'helpers/battle_v1_response.dart';

const captures = String.fromEnvironment('LUNO_V238_CAPTURE_DIRECTORY');

void main() {
  setupPracticeTestAssets();
  for (final card in [
    CardId.chain,
    CardId.shelter,
    CardId.fog,
    CardId.shadowPass,
    CardId.fateExchange,
    CardId.boardSeal,
  ]) {
    testWidgets('${card.wire} actual effect preserves one accepted result', (
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
      var requests = 0;
      final controller = await renderBattle(
        tester,
        state: state,
        reducedMotion: false,
        requestOverride: (path, payload) async {
          if (path == '/submitBattleV1Action') {
            requests++;
            state = DeckManager.apply(
              state,
              BattleAction.fromJson(payload['intent'] as Map),
            );
          }
          return v1Response(state: state, version: requests);
        },
      );
      // A snapshot for presentation immutability, not an independent rules oracle.
      final accepted = DeckManager.apply(state, action).toJson();
      expect(await controller.submit(action), isTrue);
      await tester.pump();
      await tester.pump();
      await tester.runAsync(() async {
        final context = tester.element(find.byKey(captureKey));
        for (final image in tester.widgetList<Image>(find.byType(Image))) {
          await precacheImage(image.image, context);
        }
      });
      await tester.pump();
      final duration = battleEffectDuration(card).inMicroseconds;
      var elapsed = 0;
      for (var i = 0; i < 16; i++) {
        final target = (duration * (i + .5) / 16).round();
        await tester.pump(Duration(microseconds: target - elapsed));
        elapsed = target;
        expect(state.toJson(), accepted);
        expectNoBattleLayoutError(tester);
        if (captures.isNotEmpty) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(captureKey),
            );
            final image = await boundary.toImage(pixelRatio: 1);
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final dir = Directory('$captures/${card.wire}')
                ..createSync(recursive: true);
              File(
                '${dir.path}/frame-${i.toString().padLeft(2, '0')}.png',
              ).writeAsBytesSync(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
      }
      expect(requests, 1);
      await tester.pump(Duration(microseconds: duration - elapsed + 100000));
      expect(find.byType(BattleSpellHalo), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  }
}
