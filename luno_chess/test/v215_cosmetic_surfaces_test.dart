import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/collection_screens.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/screens/pass_screen.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/services/luno_online_service.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell, boundaryKey;
import 'rc_screen_capture_test.dart' show visualOnline;
import 'battle_ui/fixtures.dart' show battleFixture;
import 'online_request_session_test.dart' show TestAuth;
import 'battle_deck_account_test.dart' show response;

Future<LunoOnlineService> currentVisualOnline() async {
  final online = LunoOnlineService.forTesting(
    bootstrap: () async {},
    auth: TestAuth(),
    appCheck: () async => 'local-test-only',
    client: MockClient(
      (request) async => http.Response(
        jsonEncode(
          request.url.path.endsWith('/getBattleV1Deck')
              ? response()
              : {
                'ok': true,
                'state': {
                  'membership': {'active': false, 'expiresAt': 0},
                  'economy': {
                    'periods': {
                      'seasonNumber': 1,
                      'seasonEndAt': 1793318400000,
                    },
                  },
                },
              },
        ),
        200,
      ),
    ),
  );
  await online.start();
  return online;
}

Future<void> capture(WidgetTester tester, String name) async {
  final context = tester.element(find.byType(Scaffold).first);
  final providers = <ImageProvider>{
    for (final image in tester.widgetList<Image>(find.byType(Image)))
      image.image,
    for (final box in tester.widgetList<DecoratedBox>(
      find.byType(DecoratedBox),
    ))
      if (box.decoration case final BoxDecoration decoration)
        if (decoration.image != null) decoration.image!.image,
  };
  await tester.runAsync(() async {
    for (final provider in providers) {
      await precacheImage(
        provider,
        context,
      ).timeout(const Duration(seconds: 20));
    }
  });
  for (final render in tester.allRenderObjects) {
    render.markNeedsPaint();
  }
  await tester.pump();
  expect(tester.takeException(), isNull, reason: name);
  final data = <String, Object?>{
    'name': name,
    'capturedAt': DateTime.now().toUtc().toIso8601String(),
    'sourceMark':
        Platform.environment['V215_SOURCE_MARK'] ?? 'mutable-unmarked',
    'fixture':
        'Actual local Flutter pixels, mocked server; not Billing/device proof',
    'viewport': {
      'width': tester.view.physicalSize.width,
      'height': tester.view.physicalSize.height,
    },
    'scaleAt14': MediaQuery.textScalerOf(context).scale(14) / 14,
    'text': [
      for (final text in tester.widgetList<RichText>(find.byType(RichText)))
        text.text.toPlainText(),
    ],
    'ellipsized': [
      for (final element in find.byType(RichText).evaluate())
        if (element.renderObject case final RenderParagraph paragraph)
          if (paragraph.hasSize && paragraph.didExceedMaxLines)
            paragraph.text.toPlainText(),
    ],
  };
  await tester.runAsync(() async {
    final stage = Platform.environment['V215_STAGE'] ?? 'after';
    final directory = Directory('qa/v215/$stage')..createSync(recursive: true);
    final boundary =
        tester.element(find.byKey(boundaryKey)).renderObject!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(
      '${directory.path}/$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
    File('${directory.path}/$name.json').writeAsStringSync(jsonEncode(data));
    image.dispose();
  });
}

void main() {
  setupPracticeTestAssets();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await GameStore.instance.bindAccount('first');
  });
  for (final set in [
    'luno',
    'ottoman',
    'roma',
    'brit',
    'viking',
    'tasdevri',
    'samuray',
    'ice',
    'dragon',
    'neon',
  ]) {
    testWidgets(
      'current BattleBoard uses costume $set at actual short-phone scale',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 568);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          shell(
            Scaffold(
              body: Center(
                child: SizedBox(
                  width: 248,
                  child: BattleBoard(
                    view: battleFixture().view(PieceColor.white),
                    pieceSet: set,
                    selected: 4,
                    targets: const {20, 28},
                    onTap: (_) {},
                  ),
                ),
              ),
            ),
            language: 'en',
            scale: 1.5,
            reduced: true,
          ),
        );
        await tester.pump();
        final paths =
            tester.widgetList<Image>(find.byType(Image)).map((w) {
              ImageProvider provider = w.image;
              while (provider is ResizeImage) {
                provider = provider.imageProvider;
              }
              return provider is AssetImage ? provider.assetName : '';
            }).toList();
        for (final side in PieceColor.values) {
          for (final type in PieceType.values) {
            expect(
              paths,
              contains(CostumeBoardPreview.assetFor(set, side, type)),
            );
          }
        }
        await capture(tester, 'battle-board-$set-320-150');
        expect(tester.getSize(find.byType(BattleBoard)).width, 248);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final language in ['tr', 'en']) {
    for (final width in [320.0, 390.0, 430.0, 768.0]) {
      for (final page in ['shop', 'pass', 'premium', 'costumes']) {
        testWidgets('$page $language width$width scale1.5 actual render', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(
            width,
            width == 320
                ? 568
                : width == 768
                ? 1024
                : 844,
          );
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final store = GameStore.instance;
          store.data =
              PlayerData.initial()
                ..gold = 12345
                ..gems = 1500
                ..passXp = 1250;
          store.loaded = true;
          final online = await tester.runAsync(
            Platform.environment['V215_STAGE'] == 'before'
                ? visualOnline
                : currentVisualOnline,
          );
          addTearDown(online!.dispose);
          final widget = switch (page) {
            'shop' => ShopScreen(online: online),
            'pass' => PassScreen(online: online),
            'premium' => LunoPremiumScreen(online: online),
            _ => const PieceCostumeScreen(),
          };
          await tester.pumpWidget(
            shell(widget, language: language, scale: 1.5, reduced: true),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 800));
          await capture(tester, '$page-$language-${width.toInt()}-150');
          final scroll = find.byType(Scrollable).first;
          await tester.drag(scroll, const Offset(0, -430));
          await tester.pump(const Duration(milliseconds: 800));
          await capture(tester, '$page-$language-${width.toInt()}-150-tail');
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        });
      }
    }
  }
}
