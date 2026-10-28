import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/audio_feedback.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_ui/spell_halo.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/widgets/luno_arcane_halo.dart';
import 'package:luno_chess/theme/luno_theme.dart';

import '../tool/battle_fixture_support.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_ui/visual_test.dart'
    show captureKey, renderBattle, expectNoBattleLayoutError;
import 'helpers/battle_v1_response.dart';

const captureDirectory = String.fromEnvironment('LUNO_V239_CAPTURE_DIRECTORY');
const acceptanceLanguage = String.fromEnvironment(
  'LUNO_V239_LANGUAGE',
  defaultValue: 'tr',
);

// Public design acceptance, independent of runtime motif selection.
const crystal = {'shelter', 'freeze', 'purify', 'pawn_advance', 'angry_n'};
const binding = {
  'chain',
  'slow',
  'locked_square',
  'mine',
  'break_seal',
  'card_block',
  'rook_bend',
  'hunt_vow',
  'board_seal',
};
const veil = {
  'prophecy',
  'fog',
  'mana_sabotage',
  'shadow_pass',
  'echo',
  'fate_exchange',
  'shadow_contract',
};

Future<void> capture(WidgetTester tester, String card, String stage) async {
  if (captureDirectory.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(captureKey),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('$captureDirectory/$card')
        ..createSync(recursive: true);
      File(
        '${directory.path}/$stage.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setupPracticeTestAssets();
  for (final card in CardId.values) {
    testWidgets(
      'V239 ${card.wire} identity target duplicate audio and background',
      (tester) async {
        final contract =
            jsonDecode(
                  File('../battle_contract/v1/rules.json').readAsStringSync(),
                )
                as Map;
        final fixture = (contract['fixtures'] as List).cast<Map>().singleWhere(
          (f) => f['fixtureId'] == 'card-${card.wire}',
        );
        var state = fixtureInitial(fixture);
        final before = state.view(PieceColor.white);
        final action = BattleAction.fromJson(
          ((fixture['steps'] as List).first as Map)['action'] as Map,
        );
        var submits = 0;
        final controller = await renderBattle(
          tester,
          state: state,
          language: acceptanceLanguage,
          theme: LunoTheme.darkFor(acceptanceLanguage),
          reducedMotion: false,
          requestOverride: (path, payload) async {
            if (path == '/submitBattleV1Action') {
              submits++;
              state = DeckManager.apply(
                state,
                BattleAction.fromJson(payload['intent'] as Map),
              );
            }
            return v1Response(state: state, version: submits);
          },
        );
        expect(await controller.submit(action), isTrue);
        await tester.pump();
        await tester.pump();
        await tester.runAsync(() async {
          final context = tester.element(find.byKey(captureKey));
          for (final widget in tester.widgetList<Image>(find.byType(Image))) {
            await precacheImage(widget.image, context);
          }
        });
        final duration = battleEffectDuration(card);
        await tester.pump(Duration(microseconds: duration.inMicroseconds ~/ 2));
        final halo = tester.widget<BattleSpellHalo>(
          find.byType(BattleSpellHalo),
        );
        expect(halo.cue.card, card);
        expect(halo.cue.side, PieceColor.white);
        final name = card.wire;
        final motif =
            crystal.contains(name)
                ? 'crystal'
                : binding.contains(name)
                ? 'binding'
                : veil.contains(name)
                ? 'veil'
                : 'arcane';
        final expectedAsset =
            motif == 'arcane'
                ? 'assets/native_art/v237-arcane-halo-atlas.webp'
                : 'assets/native_art/v238-$motif-atlas.webp';
        expect(
          tester.widget<LunoArcaneHalo>(find.byType(LunoArcaneHalo)).atlasAsset,
          expectedAsset,
        );
        final target = (action as PlayCardAction).target;
        if (target is int) expect(halo.cue.squares, contains(target));
        if (card == CardId.purify) expect(halo.cue.squares, [0]);
        if (card == CardId.breakSeal) expect(halo.cue.squares, [20]);
        if ([
          'radar',
          'prophecy',
          'mana_sabotage',
          'card_block',
          'echo',
          'fate_exchange',
          'shadow_contract',
        ].contains(name)) {
          expect(
            halo.cue.squares,
            isEmpty,
            reason: 'Private card identities are not board targets.',
          );
        }
        final sounds = battleSoundCues(before, state.view(PieceColor.white));
        expect(
          sounds.where(
            (cue) =>
                cue.sound == battleImpactSound(card) &&
                cue.delayMs == battleImpactDelay(card),
          ),
          hasLength(1),
        );
        expect(
          battleSoundCues(
            state.view(PieceColor.white),
            state.view(PieceColor.white),
          ),
          isEmpty,
        );
        await capture(tester, name, 'impact');
        var accepted = jsonEncode(state.toJson());
        await controller.reconnect(synchronization: false);
        await tester.pump();
        expect(
          find.byType(BattleSpellHalo),
          findsOneWidget,
          reason: 'Duplicate state must not add or cancel the active cast.',
        );
        expect(submits, 1);
        expect(jsonEncode(state.toJson()), accepted);
        if ([
          CardId.pawnDeviation,
          CardId.pawnAdvance,
          CardId.rookBend,
          CardId.angryN,
          CardId.shadowPass,
        ].contains(card)) {
          final id = state.rules.pieceIds[target as int];
          final move =
              BattleRulesCore.legalActions(
                state.view(PieceColor.white),
              ).whereType<ChessMoveAction>().first;
          final destination =
              move.uci.codeUnitAt(2) - 97 + (int.parse(move.uci[3]) - 1) * 8;
          expect(await controller.submit(move), isTrue);
          await tester.pump();
          await tester.pump();
          expect(submits, 2);
          expect(state.rules.pieceIds[destination], id);
          expect(
            tester
                .widget<BattleSpellHalo>(find.byType(BattleSpellHalo))
                .cue
                .squares,
            [destination],
          );
          accepted = jsonEncode(state.toJson());
          await capture(tester, name, 'moved-target');
        }
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(find.byType(BattleSpellHalo), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        await tester.pump(duration);
        expect(
          find.byType(BattleSpellHalo),
          findsNothing,
          reason: 'Resume must not replay stale accepted events.',
        );
        expect(jsonEncode(state.toJson()), accepted);
        await capture(tester, name, 'resumed');
        expectNoBattleLayoutError(tester);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
      },
    );
  }
  registerBoundaryCases();
}

AuthoritativeBattleState acceptanceFixture(CardId card, {String? fen}) {
  final contract =
      jsonDecode(File('../battle_contract/v1/rules.json').readAsStringSync())
          as Map;
  final input = Map<String, dynamic>.from(
    (contract['fixtures'] as List).cast<Map>().singleWhere(
      (f) => f['fixtureId'] == 'card-${card.wire}',
    ),
  );
  if (fen != null) input['fen'] = fen;
  return fixtureInitial(input);
}

class AcceptanceServer {
  AcceptanceServer(this.state);
  AuthoritativeBattleState state;
  int version = 0;
  void apply(BattleAction action) {
    state = DeckManager.apply(state, action);
    version++;
  }

  Future<Map<String, dynamic>> request(
    String path,
    Map<String, dynamic> body,
  ) async {
    if (path == '/submitBattleV1Action') {
      apply(BattleAction.fromJson(body['intent'] as Map));
    }
    final response = v1Response(state: state, version: version);
    if (state.rules.terminal case final terminal?) {
      response['status'] = 'finished';
      final public = (response['view'] as Map)['public'] as Map;
      public['result'] = {
        'reason': terminal.reason,
        'winner': sideWire(PieceColor.black),
      };
      public['settlementStatus'] = 'pending';
      if (terminal.reason == 'timeout') (public['clock'] as Map)['w'] = 0;
    }
    return response;
  }
}

Finder acceptedHalo(CardId card) =>
    find.byWidgetPredicate((w) => w is BattleSpellHalo && w.cue.card == card);

void registerBoundaryCases() {
  for (final movement in ['castling', 'promotion', 'capture']) {
    testWidgets('V239 accepted shelter anchor follows $movement', (
      tester,
    ) async {
      final server = AcceptanceServer(
        acceptanceFixture(
          CardId.shelter,
          fen: switch (movement) {
            'promotion' => '4k3/P7/8/8/8/8/8/4K3 w - - 0 10',
            'capture' => '4k3/Pr6/8/8/8/8/8/4K3 w - - 0 10',
            _ => '4k3/8/8/8/8/8/8/R3K2R w KQ - 0 10',
          },
        ),
      );
      final controller = await renderBattle(
        tester,
        state: server.state,
        language: acceptanceLanguage,
        theme: LunoTheme.darkFor(acceptanceLanguage),
        reducedMotion: false,
        requestOverride: server.request,
      );
      final from = movement == 'castling' ? 0 : 48;
      final id = server.state.rules.pieceIds[from];
      expect(
        await controller.submit(PlayCardAction(CardId.shelter, target: from)),
        isTrue,
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 650));
      expect(acceptedHalo(CardId.shelter), findsOneWidget);
      final uci =
          movement == 'castling'
              ? 'e1c1'
              : movement == 'promotion'
              ? 'a7a8q'
              : 'e1f1';
      expect(await controller.submit(ChessMoveAction(uci)), isTrue);
      await tester.pump();
      await tester.pump();
      if (movement == 'capture') {
        server.apply(const PassAction());
        server.apply(const ChessMoveAction('b7a7'));
        await controller.reconnect(synchronization: false);
        await tester.pump();
        await tester.pump();
        expect(server.state.rules.pieceIds, isNot(contains(id)));
        expect(acceptedHalo(CardId.shelter), findsNothing);
      } else {
        final destination = movement == 'castling' ? 3 : 56;
        expect(server.state.rules.pieceIds[destination], id);
        expect(
          tester
              .widget<BattleSpellHalo>(acceptedHalo(CardId.shelter))
              .cue
              .squares,
          [destination],
        );
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    });
  }
  for (final card in CardId.values) {
    for (final reason in ['timeout', 'resign']) {
      testWidgets('V239 ${card.wire} $reason clears active accepted feedback', (
        tester,
      ) async {
        final server = AcceptanceServer(acceptanceFixture(card));
        final controller = await renderBattle(
          tester,
          state: server.state,
          language: acceptanceLanguage,
          theme: LunoTheme.darkFor(acceptanceLanguage),
          reducedMotion: false,
          requestOverride: server.request,
        );
        final action = BattleRulesCore.legalActions(
          server.state.view(PieceColor.white),
        ).whereType<PlayCardAction>().firstWhere((a) => a.card == card);
        expect(await controller.submit(action), isTrue);
        await tester.pump();
        await tester.pump();
        await tester.pump(
          Duration(
            microseconds: battleEffectDuration(card).inMicroseconds ~/ 2,
          ),
        );
        expect(acceptedHalo(card), findsOneWidget);
        // Valid finished-server projections test presentation cleanup. Authority
        // admission itself is checked by the clock and real-SDK backend suites.
        final draft = RuleDraft(server.state.rules)
          ..terminal = TerminalState(reason, winner: PieceColor.black);
        server.state = AuthoritativeBattleState(
          draft.freeze(),
          server.state.hidden,
        );
        server.version++;
        await controller.reconnect(synchronization: false);
        await tester.pump();
        await tester.pump();
        expect(find.byType(BattleSpellHalo), findsNothing);
        await tester.pump(const Duration(seconds: 3));
        expect(find.byType(BattleSpellHalo), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('V239 three close accepted casts retain three bounded effects', (
    tester,
  ) async {
    final server = AcceptanceServer(acceptanceFixture(CardId.shelter));
    final controller = await renderBattle(
      tester,
      state: server.state,
      language: acceptanceLanguage,
      theme: LunoTheme.darkFor(acceptanceLanguage),
      reducedMotion: false,
      requestOverride: server.request,
    );
    expect(
      await controller.submit(const PlayCardAction(CardId.shelter, target: 0)),
      isTrue,
    );
    await tester.pump();
    await tester.pump();
    final move =
        BattleRulesCore.legalActions(
          server.state.view(PieceColor.white),
        ).whereType<ChessMoveAction>().first;
    expect(await controller.submit(move), isTrue);
    await tester.pump();
    await tester.pump();
    final blackCast =
        BattleRulesCore.legalActions(
          server.state.view(PieceColor.black),
        ).whereType<PlayCardAction>().first;
    server.apply(blackCast);
    await controller.reconnect(synchronization: false);
    await tester.pump();
    await tester.pump();
    if (server.state.rules.pending != null) {
      final resolutions =
          BattleRulesCore.legalActions(
            server.state.view(PieceColor.black),
          ).whereType<ResolveAction>().toList();
      expect(resolutions, isNotEmpty);
      server.apply(resolutions.first);
      expect(server.state.rules.pending, isNull);
      // Deliver each accepted version: skipping the resolution intentionally
      // resets the presentation baseline, like a polling/reconnect gap.
      await controller.reconnect(synchronization: false);
      await tester.pump();
      await tester.pump();
    }
    server.apply(
      BattleRulesCore.legalActions(
        server.state.view(PieceColor.black),
      ).whereType<ChessMoveAction>().first,
    );
    await controller.reconnect(synchronization: false);
    await tester.pump();
    await tester.pump();
    final whiteCast =
        BattleRulesCore.legalActions(
          server.state.view(PieceColor.white),
        ).whereType<PlayCardAction>().first;
    expect(await controller.submit(whiteCast), isTrue);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(find.byType(BattleSpellHalo), findsNWidgets(3));
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(BattleSpellHalo), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });
}
