import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/cast_stage.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_ui/spell_vfx.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/piece.dart';

import '../tool/battle_fixture_support.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_ui/visual_test.dart' show captureKey, renderBattle;
import 'helpers/battle_v1_response.dart';

const _capture = bool.fromEnvironment('V220_CAPTURE_ACTUAL') ||
    String.fromEnvironment('V220_CAPTURE_ACTUAL') == '1';
bool get _writeFrames => _capture || Platform.environment['V220_CAPTURE_ACTUAL'] == '1';

typedef _Case = ({AuthoritativeBattleState before, PlayCardAction action});

// Reflect ranks and exchange colors, preserving opaque piece/effect identities.
// This lets the actual own-hand selection UI run for the black player too.
AuthoritativeBattleState _blackFixture(AuthoritativeBattleState white) {
  final old = white.rules.board;
  final board = Board(
    squares: [
      for (var square = 0; square < 64; square++)
        old.squares[square ^ 56]?.copyWith(
          color: old.squares[square ^ 56]!.color.opposite,
        ),
    ],
    turn: old.turn.opposite,
    castling: ((old.castling & 3) << 2) | ((old.castling & 12) >> 2),
    enPassant: old.enPassant == null ? null : old.enPassant! ^ 56,
    halfmoveClock: old.halfmoveClock,
    fullmoveNumber: old.fullmoveNumber,
  );
  Object? reflect(Object? value, [String? key]) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          switch (entry.key) { 'w' => 'b', 'b' => 'w', _ => entry.key }:
              reflect(entry.value, entry.key as String),
      };
    }
    if (value is List) {
      if (key == 'pieceIds') {
        return [for (var square = 0; square < 64; square++) value[square ^ 56]];
      }
      if (key == 'squares') return [for (final square in value) (square as int) ^ 56];
      return [for (final item in value) reflect(item)];
    }
    if (value is int && (key == 'square' || key == 'from')) return value ^ 56;
    if (key == 'owner' || key == 'responseSide' || key == 'winner') {
      return switch (value) { 'w' => 'b', 'b' => 'w', _ => value };
    }
    return value;
  }

  final json = reflect(white.toJson())! as Map;
  (json['rules'] as Map)['fen'] =
      '${board.positionKey()} ${board.halfmoveClock} ${board.fullmoveNumber}';
  return AuthoritativeBattleState.fromJson(json);
}

_Case _fixture(CardId card, PieceColor viewer) {
  final contract = jsonDecode(
    File('../battle_contract/v1/rules.json').readAsStringSync(),
  ) as Map;
  final fixture = (contract['fixtures'] as List).cast<Map>().singleWhere(
    (entry) => entry['fixtureId'] == 'card-${card.wire}',
  );
  final white = fixtureInitial(fixture);
  final action = BattleAction.fromJson(
    ((fixture['steps'] as List).first as Map)['action'] as Map,
  ) as PlayCardAction;
  return (
    before: viewer.isWhite ? white : _blackFixture(white),
    action: viewer.isWhite ? action : PlayCardAction(
      action.card,
      target: action.target is int ? (action.target as int) ^ 56 : action.target,
      sacrifice: action.sacrifice,
    ),
  );
}

Future<void> _warmCurrentImages(WidgetTester tester) async {
  final context = tester.element(find.byKey(captureKey));
  await tester.runAsync(() async {
    for (final image in tester.widgetList<Image>(find.byType(Image)).toList()) {
      await precacheImage(image.image, context);
    }
    for (final box in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).toList()) {
      final decoration = box.decoration;
      if (decoration is BoxDecoration && decoration.image != null) {
        await precacheImage(decoration.image!.image, context);
      }
    }
  });
  for (final render in tester.allRenderObjects) {
    render.markNeedsPaint();
  }
  // Pump no fake time: image decoding must not skip travel or impact frames.
  await tester.pump();
}

Finder _transient(String prefix) => find.byWidgetPredicate((widget) =>
    widget.key is ValueKey &&
    (widget.key as ValueKey).value.toString().startsWith(prefix));

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  expect(finder, findsOneWidget, reason: key);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _selectTarget(WidgetTester tester, _Case fixture) async {
  final action = fixture.action;
  final targetType = cardDefinitions[action.card]!.target;
  if (targetType == CardTargetType.opponentCard) {
    await _tapKey(tester, 'arsenal-${action.target}');
  } else if (targetType == CardTargetType.sacrifice) {
    if (find.byKey(ValueKey(action.key)).evaluate().isNotEmpty) {
      await _tapKey(tester, action.key);
    }
  } else if (action.target is int) {
    await _tapKey(tester, 'square-${action.target}');
  } else if (action.target != null) {
    final rules = fixture.before.rules;
    final squares = [
      for (final effect in rules.boardEffects)
        if (effect.id == action.target) ...effect.squares,
      for (final effect in rules.pieceEffects)
        if (effect.id == action.target) rules.pieceIds.indexOf(effect.pieceId),
    ];
    expect(squares, isNotEmpty);
    await _tapKey(tester, 'square-${squares.first}');
    if (find.byKey(ValueKey(action.key)).evaluate().isNotEmpty) {
      await _tapKey(tester, action.key);
    }
  }
}

Future<void> _frame(
  WidgetTester tester, {
  required String tag,
  required String stage,
  required int elapsed,
  required _Case fixture,
  required PieceColor viewer,
  required bool reduced,
  required BattleSpellCue cue,
}) async {
  await _warmCurrentImages(tester);
  if (!_writeFrames) return;
  final board = tester.getRect(find.byType(BattleBoard));
  final flight = find.byKey(ValueKey('card-flight-${fixture.action.card.wire}'));
  final metadata = {
    'method': 'Actual native BattleV1Screen in Flutter widget test; mocked authoritative transport',
    'physicalDevice': false,
    'liveBackend': false,
    'card': fixture.action.card.wire,
    'viewer': viewer.name,
    'caster': viewer.name,
    'reducedMotion': reduced,
    'stage': stage,
    'elapsedPresentationMs': elapsed,
    'accepted': stage != 'selection',
    'logicalViewport': {'width': 390, 'height': 844},
    'capturePixelRatio': 1,
    'action': fixture.action.toJson(),
    'cueSquares': cue.squares,
    'resourceSide': cue.resourceSide?.name,
    'boardRect': {'x': board.left, 'y': board.top, 'width': board.width, 'height': board.height},
    'flightCenter': flight.evaluate().isEmpty ? null : {
      'x': tester.getCenter(flight).dx, 'y': tester.getCenter(flight).dy,
    },
    'impactRings': _transient('impact-ring-').evaluate().length,
    'stageMeaning': switch (stage) {
      'selection' => 'Actual own-hand tap and target selection; no accepted cast yet',
      'persistent' => 'Accepted rule/knowledge/special-move state after transient animation; not every card creates a board marker',
      'cleanup' => 'Synchronization invalidation and no transient replay; persistent rules are not artificially expired',
      _ => reduced ? 'Reduced-motion accepted state at equivalent normal-motion deadline; no flight/impact animation expected' : 'Accepted cast timeline',
    },
    'inputBoundary': 'Exact contract action submitted through controller; movement-card chess destination is not submitted by this presentation fixture',
  };
  await tester.runAsync(() async {
    final directory = Directory('qa/v220/visual/frames/$tag')..createSync(recursive: true);
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(captureKey));
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('${directory.path}/$stage.png').writeAsBytesSync(png!.buffer.asUint8List());
      File('${directory.path}/$stage.json').writeAsStringSync('${jsonEncode(metadata)}\n');
    } finally {
      image.dispose();
    }
  });
  expect(tester.takeException(), isNull, reason: '$tag/$stage');
}

void main() {
  setupPracticeTestAssets();

  test('V220 all 24 presentation fixtures are legal for both player colors', () {
    expect(CardId.values.length, 24);
    for (final card in CardId.values) {
      for (final viewer in PieceColor.values) {
        final fixture = _fixture(card, viewer);
        expect(fixture.before.rules.board.turn, viewer);
        expect(fixture.before.view(viewer).ownHand, contains(card));
        expect(BattleRulesCore.legalActions(fixture.before.view(viewer)).map((a) => a.key),
          contains(fixture.action.key), reason: '${card.wire}/${viewer.name}');
        final after = DeckManager.apply(fixture.before, fixture.action);
        expect(after.rules.used[viewer], contains(card));
      }
    }
  });

  for (final card in CardId.values) {
    for (final viewer in PieceColor.values) {
      for (final reduced in [false, true]) {
        final tag = '${card.wire}-${viewer.name}-${reduced ? 'reduced' : 'normal'}';
        testWidgets('V220 actual six-stage $tag', (tester) async {
          final fixture = _fixture(card, viewer);
          var state = fixture.before;
          var version = 0;
          final permit = Completer<void>();
          final controller = await renderBattle(
            tester, state: state, viewer: viewer, language: 'en',
            reducedMotion: reduced,
            requestOverride: (path, payload) async {
              if (path == '/submitBattleV1Action') {
                await permit.future;
                state = DeckManager.apply(state, BattleAction.fromJson(payload['intent'] as Map));
                version++;
              }
              return v1Response(state: state, version: version,
                uid: viewer.isWhite ? 'self' : 'other', side: viewer);
            },
          );
          final accepted = DeckManager.apply(state, fixture.action);
          final cue = BattleSpellCue.fromViews(card, viewer, state.view(viewer), accepted.view(viewer));
          await _tapKey(tester, 'hand-${card.wire}');
          await _selectTarget(tester, fixture);
          await _warmCurrentImages(tester);
          Future<void> shot(String stage, int elapsed) => _frame(tester,
            tag: tag, stage: stage, elapsed: elapsed, fixture: fixture,
            viewer: viewer, reduced: reduced, cue: cue);
          await shot('selection', 0);
          expect(find.byType(BattleCastStage), findsOneWidget);
          expect(_transient('card-flight-'), findsNothing);
          final ownAnchor = tester.widget<BattleCastStage>(find.byType(BattleCastStage)).cards[card]!;
          final origin = tester.getCenter(find.byKey(ownAnchor));
          final submission = controller.submit(fixture.action);
          await tester.pump();
          expect(controller.snapshot!.stateVersion, 0);
          expect(_transient('card-flight-'), findsNothing,
            reason: 'Never present an unaccepted action as approved');
          permit.complete();
          expect(await submission, isTrue);
          await tester.pump();
          await tester.pump();
          await _warmCurrentImages(tester);
          expect(controller.snapshot!.stateVersion, 1);
          final flight = find.byKey(ValueKey('card-flight-${card.wire}'));
          expect(flight, reduced ? findsNothing : findsOneWidget);
          if (!reduced) {
            expect((tester.getCenter(flight) - origin).distance, lessThan(1),
              reason: 'Actual cast origin must be the measured selected own-hand card');
          }
          final duration = battleEffectDuration(card).inMilliseconds;
          var elapsed = 0;
          Future<void> advance(String stage, int deadline) async {
            await tester.pump(Duration(milliseconds: deadline - elapsed));
            elapsed = deadline;
            await shot(stage, elapsed);
          }
          await advance('cast', (duration * .08).round());
          await advance('travel', (duration * .35).round());
          expect(_transient('impact-ring-'), findsNothing,
            reason: 'Impact must not precede card arrival');
          await advance('impact', battleImpactDelay(card) + 20);
          if (!reduced) {
            for (final square in cue.squares) {
              expect(find.byKey(ValueKey('impact-ring-$square')), findsOneWidget);
            }
            final castStage = tester.widget<BattleCastStage>(find.byType(BattleCastStage));
            final resourceSide = cue.resourceSide ??
                (cardDefinitions[card]!.target == CardTargetType.opponentCard
                    ? viewer.opposite : viewer);
            final target = cue.squares.isNotEmpty
                ? cue.squares.map((s) => tester.getCenter(find.byKey(ValueKey('square-$s'))))
                    .reduce((a, b) => a + b) / cue.squares.length.toDouble()
                : tester.getCenter(find.byKey(resourceSide == viewer
                    ? castStage.own : castStage.opponent));
            expect((tester.getCenter(flight) - target).distance, lessThan(1),
              reason: 'Actual flight must arrive at the oriented square/zone/resource center');
          } else {
            expect(_transient('card-flight-'), findsNothing);
            expect(_transient('impact-ring-'), findsNothing);
          }
          await advance('persistent', duration + 100);
          expect(_transient('card-flight-'), findsNothing);
          expect(_transient('impact-ring-'), findsNothing);
          expect(state.toJson(), accepted.toJson(),
            reason: 'Presentation cannot mutate accepted rules or private state');
          for (final effect in accepted.rules.boardEffects) {
            for (final square in effect.squares) {
              expect(find.byKey(ValueKey('effect-${effect.id}-$square')), findsOneWidget);
            }
          }
          final beforeSync = jsonEncode(state.toJson());
          await controller.reconnect(synchronization: true);
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          await shot('cleanup', elapsed + 1000);
          expect(_transient('card-flight-'), findsNothing);
          expect(_transient('impact-ring-'), findsNothing);
          expect(jsonEncode(state.toJson()), beforeSync);
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
