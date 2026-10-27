import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_ui/feedback.dart';
import 'package:luno_chess/battle_ui/sheets.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/cast_stage.dart';
import 'package:flutter/rendering.dart';
import 'package:luno_chess/battle_ui/spell_vfx.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/battle_v1_copy.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'helpers/v222_card_scenarios.dart';

Widget feedback(PlayerView view, {bool reduced = false, int epoch = 0}) =>
    MaterialApp(
      locale: const Locale('tr'),
      supportedLocales: LunoLocalizations.supportedLocales,
      localizationsDelegates: const [
        LunoLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 320,
              child: BattleAcceptedFeedback(
                view: view,
                showProjectiles: false,
                synchronizationEpoch: epoch,
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets(
    'opposing casts of the same card keep independent visible flight keys',
    (tester) async {
      var state = cardScenario(CardId.radar, PieceColor.white);
      final board = GlobalKey(), own = GlobalKey(), opponent = GlobalKey();
      final card = GlobalKey();
      Widget stage(AuthoritativeBattleState data) => MaterialApp(
        home: Scaffold(
          body: BattleCastStage(
            view: data.view(PieceColor.white),
            board: board,
            own: own,
            opponent: opponent,
            cards: {CardId.radar: card},
            child: Column(
              children: [
                SizedBox(key: opponent, width: 100, height: 40),
                SizedBox(key: board, width: 320, height: 320),
                SizedBox(key: own, width: 100, height: 40),
                SizedBox(key: card, width: 58, height: 76),
              ],
            ),
          ),
        ),
      );
      await tester.pumpWidget(stage(state));
      await tester.pump();
      final ours = BattleRulesCore.legalActions(
        state.view(PieceColor.white),
      ).whereType<PlayCardAction>().firstWhere((a) => a.card == CardId.radar);
      state = DeckManager.apply(state, ours);
      await tester.pumpWidget(stage(state));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('card-flight-radar')), findsOneWidget);
      state = DeckManager.apply(
        state,
        BattleRulesCore.legalActions(
          state.view(PieceColor.white),
        ).whereType<ChessMoveAction>().first,
      );
      final theirs = BattleRulesCore.legalActions(
        state.view(PieceColor.black),
      ).whereType<PlayCardAction>().firstWhere((a) => a.card == CardId.radar);
      state = DeckManager.apply(state, theirs);
      await tester.pumpWidget(stage(state));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final flights = find.byWidgetPredicate(
        (widget) =>
            widget is Positioned &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'card-flight-radar',
            ),
      );
      expect(flights, findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pump(battleEffectDuration(CardId.radar));
      expect(flights, findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'all card explanations remain readable and scrollable on small phones',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final language in ['tr', 'en']) {
        for (final card in CardId.values) {
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(language),
              supportedLocales: LunoLocalizations.supportedLocales,
              localizationsDelegates: const [
                LunoLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder:
                  (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(1.8)),
                    child: child!,
                  ),
              home: Scaffold(
                body: CardDetailSheet(
                  card: card,
                  view: cardScenario(
                    card,
                    PieceColor.white,
                  ).view(PieceColor.white),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final l = LunoLocalizations(Locale(language));
          await tester.ensureVisible(find.text(l.battleCardCautionLabel));
          await tester.pump();
          expect(
            find.text(l.battleCardExplanation(card).caution),
            findsOneWidget,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '${card.wire}/$language at 320px and 1.8 text scale',
          );
        }
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'accepted effects are rendered on the actual board for visual review',
    (tester) async {
      final directory = Directory('qa/v222/board-frames')
        ..createSync(recursive: true);
      final key = GlobalKey();
      for (final card in [
        CardId.chain,
        CardId.freeze,
        CardId.mine,
        CardId.boardSeal,
        CardId.pawnAdvance,
        CardId.prophecy,
      ]) {
        final state = cardScenario(card, PieceColor.white);
        final action = BattleRulesCore.legalActions(
          state.view(PieceColor.white),
        ).whereType<PlayCardAction>().firstWhere((a) => a.card == card);
        final after = DeckManager.apply(state, action);
        Widget board(AuthoritativeBattleState data) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox.square(
                  dimension: 360,
                  child: BattleBoard(
                    view: data.view(PieceColor.white),
                    enabled: false,
                    onTap: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(board(state));
        await tester.pumpAndSettle();
        final imageContext = key.currentContext!;
        final images = tester.widgetList<Image>(find.byType(Image)).toList();
        await tester.runAsync(() async {
          for (final image in images) {
            await precacheImage(image.image, imageContext);
          }
          for (final box in tester.widgetList<DecoratedBox>(
            find.byType(DecoratedBox),
          )) {
            final decoration = box.decoration;
            if (decoration is BoxDecoration && decoration.image != null) {
              await precacheImage(decoration.image!.image, imageContext);
            }
          }
        });
        await tester.pump();
        await tester.pumpWidget(board(after));
        await tester.pump();
        await tester.pump(
          Duration(
            milliseconds:
                (battleEffectDuration(card).inMilliseconds * .5).round(),
          ),
        );
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await tester.runAsync(() => boundary.toImage());
        final bytes = await tester.runAsync(
          () => image!.toByteData(format: ui.ImageByteFormat.png),
        );
        File(
          '${directory.path}/${card.wire}.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image!.dispose();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  test(
    'all cards have readable impact time and actionable bilingual descriptions',
    () {
      for (final card in CardId.values) {
        final timing = battleEffectTiming(card);
        expect(timing.total.inMilliseconds, inInclusiveRange(1400, 2200));
        expect(timing.impact.inMilliseconds, greaterThanOrEqualTo(700));
        expect(timing.travel + timing.impact + timing.settle, timing.total);
        for (final locale in ['tr', 'en']) {
          final l = LunoLocalizations(Locale(locale));
          final explanation = l.battleCardExplanation(card);
          for (final section in [
            explanation.selection,
            explanation.effect,
            explanation.duration,
            explanation.caution,
          ]) {
            expect(
              section.trim().length,
              greaterThan(15),
              reason: '${card.wire}/$locale',
            );
          }
        }
      }
    },
  );

  testWidgets(
    'every card has a nonblank, changing and distinct native impact',
    (tester) async {
      final signatures = <String>{};
      final directory = Directory('qa/v222/effect-frames')
        ..createSync(recursive: true);
      for (final card in CardId.values) {
        final state = cardScenario(card, PieceColor.white);
        final action = BattleRulesCore.legalActions(
          state.view(PieceColor.white),
        ).whereType<PlayCardAction>().firstWhere((a) => a.card == card);
        final after = DeckManager.apply(state, action);
        final cue = BattleSpellCue.fromViews(
          card,
          PieceColor.white,
          state.view(PieceColor.white),
          after.view(PieceColor.white),
        );
        final signaturesForCard = <String>[];
        for (final progress in [.4, .65]) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          BattleSpellPainter(
            cue: cue,
            viewer: PieceColor.white,
            progress: progress,
            color: battleAbilityColor(card),
            showProjectile: false,
          ).paint(canvas, const Size(240, 240));
          final picture = recorder.endRecording();
          final image = await tester.runAsync(() => picture.toImage(240, 240));
          final rgba = await tester.runAsync(
            () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
          );
          final bytes = rgba!.buffer.asUint8List();
          final visible = [
            for (var i = 3; i < bytes.length; i += 4)
              if (bytes[i] > 8) i,
          ];
          expect(
            visible.length,
            greaterThan(60),
            reason: '${card.wire} must visibly paint its effect.',
          );
          signaturesForCard.add(bytes.join(','));
          final png = await tester.runAsync(
            () => image!.toByteData(format: ui.ImageByteFormat.png),
          );
          File(
            '${directory.path}/${card.wire}-${(progress * 100).round()}.png',
          ).writeAsBytesSync(png!.buffer.asUint8List());
          image!.dispose();
          picture.dispose();
        }
        expect(
          signaturesForCard[0],
          isNot(signaturesForCard[1]),
          reason: '${card.wire} must animate.',
        );
        expect(
          signatures.add(signaturesForCard[1]),
          isTrue,
          reason: '${card.wire} must have its own rendered identity.',
        );
      }
      expect(signatures, hasLength(24));
    },
  );

  testWidgets(
    'a rapid move and another cast do not restart or erase the first effect',
    (tester) async {
      final before = cardScenario(CardId.chain, PieceColor.white);
      final action = BattleRulesCore.legalActions(
        before.view(PieceColor.white),
      ).whereType<PlayCardAction>().firstWhere((a) => a.card == CardId.chain);
      var after = DeckManager.apply(before, action);
      await tester.pumpWidget(feedback(before.view(PieceColor.white)));
      await tester.pumpWidget(feedback(after.view(PieceColor.white)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 550));
      final first = find.byKey(const ValueKey('spell-chain-0'));
      final firstProgress =
          (tester.widget<CustomPaint>(first).painter! as BattleSpellPainter)
              .progress;
      after = DeckManager.apply(
        after,
        BattleRulesCore.legalActions(
          after.view(PieceColor.white),
        ).whereType<ChessMoveAction>().first,
      );
      await tester.pumpWidget(feedback(after.view(PieceColor.white)));
      expect(first, findsOneWidget);
      expect(
        (tester.widget<CustomPaint>(first).painter! as BattleSpellPainter)
            .progress,
        greaterThanOrEqualTo(firstProgress),
      );
      final radar = BattleRulesCore.legalActions(
        after.view(PieceColor.black),
      ).whereType<PlayCardAction>().firstWhere((a) => a.card == CardId.radar);
      after = DeckManager.apply(after, radar);
      final next = after.view(PieceColor.white);
      await tester.pumpWidget(feedback(next));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(first, findsOneWidget);
      expect(find.byKey(const ValueKey('spell-radar-0')), findsOneWidget);
      expect(
        (tester.widget<CustomPaint>(first).painter! as BattleSpellPainter)
            .progress,
        greaterThan(firstProgress),
      );
      final opponentMove =
          BattleRulesCore.legalActions(
            after.view(PieceColor.black),
          ).whereType<ChessMoveAction>().first;
      after = DeckManager.apply(after, opponentMove);
      await tester.pumpWidget(feedback(after.view(PieceColor.white)));
      expect(
        after.rules.pieceEffects.where((e) => e.type == PieceEffectType.chain),
        isEmpty,
      );
      expect(
        first,
        findsOneWidget,
        reason:
            'Effect expiration is not a new cast and must not truncate the existing timeline.',
      );
      await tester.pumpWidget(feedback(next, reduced: true));
      expect(first, findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
