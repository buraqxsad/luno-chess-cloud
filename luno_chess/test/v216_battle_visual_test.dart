import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/battle_ui/private.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/theme/luno_theme.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_ui/fixtures.dart';
import 'battle_ui/visual_test.dart'
    show renderBattle, captureKey, visualTap, editedFixture, effectFixture,
        warmBattleImages;

final phase = Platform.environment['LUNO_V216_BATTLE_PHASE'] ?? 'after';
final frames = <String, Uint8List>{};

Future<void> shot(WidgetTester tester, String name) async {
  await warmBattleImages(tester);
  for (final render in tester.allRenderObjects) {
    render.markNeedsPaint();
  }
  await tester.pump();
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(captureKey),
    );
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = Uint8List.fromList(data!.buffer.asUint8List());
    frames[name] = bytes;
    final dir = Directory('qa/v216/$phase/battle')..createSync(recursive: true);
    await File('${dir.path}/$name.png').writeAsBytes(bytes);
    image.dispose();
  });
  expect(tester.takeException(), isNull, reason: name);
}

Future<void> sheets() async {
  final groups = <String, List<MapEntry<String, Uint8List>>>{};
  for (final frame in frames.entries) {
    final group = frame.key.split('-').first;
    groups.putIfAbsent(group, () => []).add(frame);
  }
  for (final group in groups.entries) {
    for (var start = 0; start < group.value.length; start += 8) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(const Color(0xff202620), BlendMode.src);
      for (var i = 0; i < 8 && start + i < group.value.length; i++) {
        final frame = group.value[start + i];
        final codec = await ui.instantiateImageCodec(frame.value);
        final image = (await codec.getNextFrame()).image;
        final left = (i % 4) * 256.0, top = (i ~/ 4) * 580.0;
        final text = TextPainter(
          text: TextSpan(
            text: frame.key,
            style: const TextStyle(fontFamily: 'Nunito', color: Colors.white, fontSize: 13),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 250);
        text.paint(canvas, Offset(left + 3, top + 3));
        final scale = math.min(250 / image.width, 550 / image.height);
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          Rect.fromLTWH(left + (256 - image.width * scale) / 2,
            top + 25, image.width * scale, image.height * scale),
          Paint(),
        );
        image.dispose();
        codec.dispose();
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(1024, 1160);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'qa/v216/$phase/battle/sheet-${group.key}-${start ~/ 8 + 1}.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
    }
  }
  if (phase != 'after') return;
  final inventory = <Map<String, Object?>>[];
  final comparisons = Directory('qa/v216/after/battle/comparisons')
    ..createSync(recursive: true);
  for (final frame in frames.entries) {
    final before = File('qa/v216/before/battle/${frame.key}.png');
    if (!before.existsSync()) {
      inventory.add({'frame': frame.key, 'before': null,
        'after': 'qa/v216/after/battle/${frame.key}.png',
        'comparison': null, 'note': 'Additional after-only regression coverage'});
      continue;
    }
    final oldCodec = await ui.instantiateImageCodec(before.readAsBytesSync());
    final newCodec = await ui.instantiateImageCodec(frame.value);
    final oldImage = (await oldCodec.getNextFrame()).image;
    final newImage = (await newCodec.getNextFrame()).image;
    expect(newImage.width, oldImage.width);
    expect(newImage.height, oldImage.height);
    final oldPixels = (await oldImage.toByteData(format: ui.ImageByteFormat.rawRgba))!
      .buffer.asUint8List();
    final newPixels = (await newImage.toByteData(format: ui.ImageByteFormat.rawRgba))!
      .buffer.asUint8List();
    var changedPixels = 0, visiblePixels = 0;
    for (var i = 0; i < newPixels.length; i += 4) {
      if (newPixels[i + 3] > 0 && newPixels[i] + newPixels[i + 1] + newPixels[i + 2] > 50) {
        visiblePixels++;
      }
      if (oldPixels[i] != newPixels[i] || oldPixels[i + 1] != newPixels[i + 1] ||
          oldPixels[i + 2] != newPixels[i + 2] || oldPixels[i + 3] != newPixels[i + 3]) {
        changedPixels++;
      }
    }
    expect(visiblePixels, greaterThan(newImage.width * newImage.height * .05),
      reason: '${frame.key} must not be blank');
    final recorder = ui.PictureRecorder(), width = newImage.width;
    final canvas = Canvas(recorder)..drawColor(const Color(0xff202620), BlendMode.src);
    for (final entry in [(image: oldImage, label: 'BEFORE'), (image: newImage, label: 'AFTER')].indexed) {
      final left = entry.$1 * width.toDouble();
      final title = TextPainter(text: TextSpan(text: '${entry.$2.label} / ${frame.key}',
        style: const TextStyle(fontFamily: 'Nunito', color: Colors.white, fontSize: 13)),
        textDirection: TextDirection.ltr)..layout(maxWidth: width - 8);
      title.paint(canvas, Offset(left + 4, 4));
      canvas.drawImage(entry.$2.image, Offset(left, 28), Paint());
    }
    final picture = recorder.endRecording();
    final pair = await picture.toImage(width * 2, newImage.height + 28);
    final data = await pair.toByteData(format: ui.ImageByteFormat.png);
    await File('${comparisons.path}/${frame.key}.png').writeAsBytes(data!.buffer.asUint8List());
    inventory.add({'frame': frame.key, 'width': width, 'height': newImage.height,
      'before': before.path, 'after': 'qa/v216/after/battle/${frame.key}.png',
      'changedPixels': changedPixels, 'visiblePixels': visiblePixels,
      'comparison': '${comparisons.path}/${frame.key}.png'});
    pair.dispose(); picture.dispose(); oldImage.dispose(); newImage.dispose();
    oldCodec.dispose(); newCodec.dispose();
  }
  await File('${comparisons.path}/inventory.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert(inventory));
}

void main() {
  setupPracticeTestAssets();
  setUpAll(() async => LunoSettings.instance.load());
  setUp(() {
    LunoSettings.instance.effectsLevel = 0;
    LunoSettings.instance.musicLevel = 0;
    GameStore.instance.data = PlayerData.initial()
      ..ownedEmojis = {'smile', 'heart', 'think', 'crown'}
      ..emojiLoadout = ['smile', 'heart', 'think', 'crown'];
    GameStore.instance.loaded = true;
  });
  tearDownAll(sheets);
  for (final language in ['tr', 'en']) {
    for (final width in [320.0, 390.0, 430.0, 768.0]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets('V216 battle render $language $width $scale', (tester) async {
          final tag = '$language-${width.toInt()}-$scale';
          await renderBattle(
            tester,
            size: Size(width, width == 768 ? 1024 : 844),
            language: language,
            textScale: scale,
            theme: LunoTheme.darkFor(language),
          );
          await shot(tester, 'main-$tag');
          await visualTap(tester, 'hand-shelter');
          await shot(tester, 'selected-$tag');
          await visualTap(tester, 'square-12');
          await shot(tester, 'target-$tag');
          await visualTap(tester, 'open-emotes');
          await shot(tester, 'emotes-$tag');
          await tester.pumpWidget(const SizedBox());
          await renderBattle(
            tester,
            size: Size(width, width == 768 ? 1024 : 844),
            language: language,
            textScale: scale,
            theme: LunoTheme.darkFor(language),
            state: editedFixture((d) {
              d.phase = BattlePhase.terminal;
              d.terminal = const TerminalState('checkmate', winner: PieceColor.white);
            }),
          );
          await shot(tester, 'victory-$tag');
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
    for (final name in ['piece', 'multi', 'defeat', 'draw', 'four', 'pending']) {
      testWidgets('V216 battle focused render $name $language', (tester) async {
        final hold = name == 'pending' ? Completer<void>() : null;
        await renderBattle(
          tester,
          language: language,
          theme: LunoTheme.darkFor(language),
          hold: hold,
          state: name == 'multi'
              ? effectFixture(all: true)
              : name == 'four'
              ? battleFixture(hand: [CardId.shadowContract, CardId.fateExchange,
                  CardId.pawnDeviation, CardId.boardSeal])
              : ['defeat', 'draw'].contains(name)
              ? editedFixture((d) {
                  d.phase = BattlePhase.terminal;
                  d.terminal = TerminalState(name == 'draw' ? 'stalemate' : 'checkmate',
                      winner: name == 'draw' ? null : PieceColor.black);
                })
              : name == 'piece'
              ? editedFixture((d) => d.phase = BattlePhase.chess)
              : null,
        );
        if (name == 'piece') await visualTap(tester, 'square-12');
        if (name == 'pending') {
          final pass = find.byKey(const ValueKey('pass-card'));
          await tester.ensureVisible(pass);
          await tester.tap(pass);
          await tester.pump();
        }
        await shot(tester, '$name-$language-390-1.0');
        await tester.pumpWidget(const SizedBox());
        hold?.complete();
        await tester.pump();
      });
    }
    for (final width in [320.0, 390.0, 430.0, 768.0]) {
      testWidgets('V216 full-hand enlarged render $language $width', (tester) async {
        await renderBattle(tester,
          size: Size(width, width == 768 ? 1024 : 844),
          language: language, textScale: 1.5, theme: LunoTheme.darkFor(language),
          state: battleFixture(hand: [CardId.shelter, CardId.chain, CardId.slow, CardId.freeze]));
        await shot(tester, 'fullhand-$language-${width.toInt()}-1.5');
        await tester.pumpWidget(const SizedBox());
      });
    }
    for (final card in [CardId.prophecy, CardId.fateExchange]) {
      for (final width in [320.0, 390.0, 430.0, 768.0]) {
        testWidgets('V216 private choice render ${card.wire} $language $width', (tester) async {
          final state = DeckManager.apply(
            battleFixture(hand: [card, CardId.shelter, CardId.mine]),
            PlayCardAction(card,
              sacrifice: card == CardId.fateExchange ? CardId.shelter : null),
          );
          await renderBattle(tester, state: state,
            size: Size(width, width == 768 ? 1024 : 844),
            language: language, textScale: 1.5, theme: LunoTheme.darkFor(language));
          await visualTap(tester, 'open-private');
          final sheet = tester.widget<PrivateChoiceSheet>(find.byType(PrivateChoiceSheet));
          expect(sheet.view.rules.pending!.owner, sheet.view.viewer);
          expect(sheet.view.knowledge.pendingCards, isNotEmpty);
          for (final known in sheet.view.knowledge.pendingCards) {
            expect(find.byKey(ValueKey('private-${known.wire}')), findsOneWidget);
          }
          BattleCommand confirm() => tester.widget<BattleCommand>(
            find.byKey(const ValueKey('confirm-private')));
          if (card == CardId.fateExchange) {
            expect(confirm().onPressed, isNull);
            await visualTap(tester, 'private-${sheet.view.knowledge.pendingCards.first.wire}');
          }
          expect(confirm().onPressed, isNotNull);
          await shot(tester, 'private-${card.wire}-$language-${width.toInt()}-1.5');
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
