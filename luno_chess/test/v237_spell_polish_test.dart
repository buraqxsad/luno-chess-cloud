import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_ui/spell_halo.dart';
import 'package:luno_chess/battle_ui/spell_vfx.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/widgets/luno_arcane_halo.dart';

import '../tool/battle_fixture_support.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_ui/visual_test.dart'
    show captureKey, expectNoBattleLayoutError, renderBattle;
import 'helpers/battle_v1_response.dart';

const _haloCapture = ValueKey('halo-capture');
const _reviewDirectory = String.fromEnvironment('LUNO_VFX_REVIEW_DIRECTORY');

Widget _shell(Widget child, {bool reduced = false}) => MaterialApp(
  builder:
      (context, content) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: content!,
      ),
  home: Center(child: RepaintBoundary(key: _haloCapture, child: child)),
);

Future<Uint8List> _rgba(WidgetTester tester, Key key) async {
  late Uint8List result;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      result =
          (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  });
  return result;
}

void main() {
  setupPracticeTestAssets();

  testWidgets(
    'halo atlas has bounded memory and an open centre in every frame',
    (tester) async {
      await tester.runAsync(() async {
        final bytes = await rootBundle.load(LunoArcaneHalo.asset);
        expect(bytes.lengthInBytes, lessThan(256 * 1024));
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(),
        );
        final frame = await codec.getNextFrame();
        try {
          expect(frame.image.width, 768);
          expect(frame.image.height, 768);
          final pixels =
              (await frame.image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!.buffer.asUint8List();
          for (var index = 0; index < 16; index++) {
            final left = index % 4 * 192, top = index ~/ 4 * 192;
            final centerAlpha = pixels[((top + 96) * 768 + left + 96) * 4 + 3];
            expect(
              centerAlpha,
              lessThan(24),
              reason: 'Piece centre stays readable',
            );
            var visible = 0;
            for (var y = top; y < top + 192; y++) {
              for (var x = left; x < left + 192; x++) {
                if (pixels[(y * 768 + x) * 4 + 3] > 12) visible++;
              }
            }
            expect(visible, greaterThan(400));
            expect(visible, lessThan(192 * 192 ~/ 2));
          }
        } finally {
          frame.image.dispose();
          codec.dispose();
        }
      });
    },
  );

  testWidgets(
    'finite atlas playback changes frame without a repeating ticker',
    (tester) async {
      final signatures = <int>{};
      for (final progress in [.15, .5, .7]) {
        await tester.pumpWidget(
          _shell(LunoArcaneHalo(progress: progress, size: 96)),
        );
        await tester.runAsync(
          () => precacheImage(
            const AssetImage(LunoArcaneHalo.asset),
            tester.element(find.byKey(_haloCapture)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(Image), findsOneWidget);
        signatures.add(Object.hashAll(await _rgba(tester, _haloCapture)));
        expect(tester.binding.hasScheduledFrame, isFalse);
      }
      expect(signatures, hasLength(3));
    },
  );

  testWidgets(
    'completed invalid transparent and reduced-motion halos are empty',
    (tester) async {
      for (final progress in [0.0, 1.0, -1.0, double.nan, double.infinity]) {
        await tester.pumpWidget(
          _shell(LunoArcaneHalo(progress: progress, size: 72)),
        );
        expect(find.byType(Image), findsNothing);
      }
      await tester.pumpWidget(
        _shell(
          const LunoArcaneHalo(
            progress: .5,
            size: 72,
            color: Colors.transparent,
          ),
        ),
      );
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(
        _shell(const LunoArcaneHalo(progress: .5, size: 72), reduced: true),
      );
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'halo and vector spell share mirrored public square/resource anchors',
    () {
      const size = Size.square(320);
      final corner = BattleSpellCue(CardId.freeze, PieceColor.white, [0]);
      expect(
        battleSpellTarget(corner, PieceColor.white, size),
        const Offset(20, 300),
      );
      expect(
        battleSpellTarget(corner, PieceColor.black, size),
        const Offset(300, 20),
      );
      final radar = BattleSpellCue(CardId.radar, PieceColor.white, []);
      final prophecy = BattleSpellCue(CardId.prophecy, PieceColor.white, []);
      expect(
        battleSpellTarget(radar, PieceColor.white, size),
        const Offset(160, 44),
      );
      expect(
        battleSpellTarget(prophecy, PieceColor.white, size),
        const Offset(160, 276),
      );
    },
  );

  testWidgets(
    'real cast keeps one rules result through all rendered effect frames',
    (tester) async {
      final contract =
          jsonDecode(
                File('../battle_contract/v1/rules.json').readAsStringSync(),
              )
              as Map;
      final fixture = (contract['fixtures'] as List).cast<Map>().singleWhere(
        (f) => f['fixtureId'] == 'card-freeze',
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
      final expected = DeckManager.apply(state, action).toJson();
      expect(await controller.submit(action), isTrue);
      await tester.pump();
      await tester.pump();
      final duration = battleEffectDuration(CardId.freeze).inMicroseconds;
      var elapsed = 0;
      for (var frame = 0; frame < 16; frame++) {
        final target = (duration * (frame + .5) / 16).round();
        await tester.pump(Duration(microseconds: target - elapsed));
        elapsed = target;
        expect(
          state.toJson(),
          expected,
          reason: 'Rendering must never change rules',
        );
        expectNoBattleLayoutError(tester);
        if (_reviewDirectory.isNotEmpty) {
          await tester.runAsync(() async {
            final context = tester.element(find.byKey(captureKey));
            for (final image
                in tester.widgetList<Image>(find.byType(Image)).toList()) {
              await precacheImage(image.image, context);
            }
          });
          await tester.pump();
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(captureKey),
            );
            final image = await boundary.toImage(pixelRatio: 1);
            try {
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final dir = Directory(_reviewDirectory)
                ..createSync(recursive: true);
              File(
                '${dir.path}/freeze-${frame.toString().padLeft(2, '0')}.png',
              ).writeAsBytesSync(data!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
      }
      await tester.pump(Duration(microseconds: duration - elapsed + 100000));
      expect(find.byType(BattleSpellHalo), findsNothing);
      expect(requests, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );
}
