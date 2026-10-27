import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/battle_deck_screen.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'battle_deck_account_test.dart' show response;
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart'
    show shell, warm, boundaryKey, noOverflow;
import 'v215_progression_product_test.dart' show modernProgress;
import 'v214_deck_progression_result_test.dart' show ownership;

Map<String, dynamic> v216Deck({
  int matches = 0,
  int days = 1,
  bool welcome = false,
}) => {
  ...response(
    owned:
        {
          ...ownership(matches),
          if (welcome) CardId.mine,
          if (days >= 2) CardId.breakSeal,
          if (days >= 3) CardId.fog,
        }.map((c) => c.wire).toList(),
  ),
  'progression': modernProgress(matches, days, welcome),
};

Future<void> captureProgression(WidgetTester tester, String name) async {
  await warm(tester);
  await tester.runAsync(() async {
    final context = tester.element(find.byType(Scaffold).first);
    final images = <ImageProvider>{};
    for (final widget in tester.widgetList<DecoratedBox>(
      find.byType(DecoratedBox),
    )) {
      final decoration = widget.decoration;
      if (decoration is BoxDecoration && decoration.image != null) {
        images.add(decoration.image!.image);
      }
    }
    for (final provider in images) {
      await precacheImage(provider, context);
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
    final frame = await boundary.toImage(pixelRatio: 1);
    final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
    const phase = String.fromEnvironment('V216_PHASE', defaultValue: 'after');
    final file = File('qa/v216/$phase/progression/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    frame.dispose();
  });
}

void main() {
  setupPracticeTestAssets();
  setUp(() {
    GameStore.instance
      ..data = PlayerData.initial()
      ..loaded = true
      ..hasChosenUsername = true
      ..hasCompletedTutorial = true;
  });
  const phase = String.fromEnvironment('V216_PHASE', defaultValue: 'after');
  for (final scale in phase == 'before' ? [1.5] : [1.0, 1.5]) {
    for (final language in ['tr', 'en']) {
      for (final size in [
        const Size(320, 568),
        const Size(390, 844),
        const Size(430, 932),
        const Size(768, 1024),
      ]) {
        testWidgets(
          'V216 actual progression frames $language ${size.width} scale$scale',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final suffix =
                '$language-${size.width.toInt()}-text${(scale * 100).toInt()}';
            for (final entry
                in <String, Widget>{
                  'collection': CollectionScreen(
                    deckLoadOverride: () async => v216Deck(),
                  ),
                  'arenas': const ArenasScreen(),
                  'deck': BattleDeckScreen(
                    loadOverride: () async => v216Deck(),
                  ),
                  'cards': BattleDeckScreen(
                    catalogOnly: true,
                    loadOverride: () async => v216Deck(),
                  ),
                }.entries) {
              await tester.pumpWidget(
                shell(
                  entry.value,
                  language: language,
                  scale: scale,
                  reduced: true,
                ),
              );
              await tester.pumpAndSettle();
              noOverflow(tester);
              await captureProgression(tester, '${entry.key}-$suffix');
              if (phase != 'before' && entry.key == 'collection') {
                await tester.scrollUntilVisible(
                  find.text(language == 'tr' ? 'EMOJİLER' : 'EMOTES'),
                  240,
                  scrollable: find.byType(Scrollable).first,
                );
                await tester.pumpAndSettle();
                noOverflow(tester);
                await captureProgression(tester, 'collection-rest-$suffix');
              }
              if (phase != 'before' && entry.key == 'arenas') {
                GameStore.instance.applyServerState({
                  'trophies': 620,
                  'arenaIdx': 3,
                });
                await tester.pumpAndSettle();
                noOverflow(tester);
                await captureProgression(tester, 'arenas-progress-$suffix');
                GameStore.instance.applyServerState({
                  'trophies': 4000,
                  'arenaIdx': 8,
                });
                await tester.pumpAndSettle();
                noOverflow(tester);
                await captureProgression(tester, 'arenas-max-$suffix');
                GameStore.instance.applyServerState({
                  'trophies': 0,
                  'arenaIdx': 0,
                });
              }
              if (entry.key == 'deck') {
                await tester.scrollUntilVisible(
                  find.byKey(const ValueKey('selected-deck-grid')),
                  240,
                  scrollable: find.byType(Scrollable).first,
                );
                await tester.pumpAndSettle();
                noOverflow(tester);
                await captureProgression(tester, 'deck-cards-$suffix');
              }
              if (entry.key == 'cards') {
                final locked =
                    find
                        .byWidgetPredicate(
                          (w) => w is BattleCatalogCard && w.locked,
                        )
                        .first;
                await tester.ensureVisible(locked);
                await tester.pumpAndSettle();
                noOverflow(tester);
                await captureProgression(tester, 'cards-locked-$suffix');
                if (phase != 'before') {
                  tester.widget<BattleCatalogCard>(locked).onTap!();
                  await tester.pumpAndSettle();
                  noOverflow(tester);
                  await captureProgression(tester, 'card-condition-$suffix');
                  await tester.tap(
                    find.byTooltip(language == 'tr' ? 'Kapat' : 'Close'),
                  );
                  await tester.pumpAndSettle();
                  await tester.scrollUntilVisible(
                    find.byWidgetPredicate(
                      (w) => w is BattleCatalogCard && w.card == CardId.radar,
                    ),
                    -240,
                    scrollable: find.byType(Scrollable).first,
                  );
                  tester
                      .widget<BattleCatalogCard>(
                        find.byWidgetPredicate(
                          (w) =>
                              w is BattleCatalogCard && w.card == CardId.radar,
                        ),
                      )
                      .onTap!();
                  await tester.pumpAndSettle();
                  noOverflow(tester);
                  await captureProgression(tester, 'card-owned-$suffix');
                  await tester.ensureVisible(
                    find.byKey(const ValueKey('catalog-open-deck')),
                  );
                  await tester.pumpAndSettle();
                  noOverflow(tester);
                  await captureProgression(tester, 'card-owned-action-$suffix');
                }
              }
              await tester.pumpWidget(const SizedBox());
            }
            if (phase != 'before') {
              var saves = 0;
              await tester.pumpWidget(
                shell(
                  BattleDeckScreen(
                    focusCard: CardId.mine,
                    loadOverride: () async => v216Deck(welcome: true),
                    saveOverride:
                        (deck) async =>
                            ++saves == 1
                                ? {'ok': false}
                                : {'ok': true, 'deck': deck},
                  ),
                  language: language,
                  scale: scale,
                  reduced: true,
                ),
              );
              await tester.pumpAndSettle();
              noOverflow(tester);
              await captureProgression(tester, 'deck-replace-$suffix');
              tester
                  .widget<BattleSelectedDeckGrid>(
                    find.byType(BattleSelectedDeckGrid).last,
                  )
                  .onTap!(CardId.purify);
              await tester.pumpAndSettle();
              await tester.scrollUntilVisible(
                find.text(language == 'tr' ? 'DESTENİ KAYDET' : 'SAVE DECK'),
                240,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              await Scrollable.ensureVisible(
                tester.element(
                  find.byKey(const ValueKey('battle-deck-save-status')),
                ),
                alignment: .65,
              );
              await tester.pumpAndSettle();
              noOverflow(tester);
              await captureProgression(tester, 'deck-unsaved-$suffix');
              tester
                  .widgetList<LunoButton>(find.byType(LunoButton))
                  .singleWhere((button) => button.icon == Icons.save_rounded)
                  .onPressed!();
              await tester.pumpAndSettle();
              await Scrollable.ensureVisible(
                tester.element(
                  find.byKey(const ValueKey('battle-deck-save-error')),
                ),
                alignment: .65,
              );
              await tester.pumpAndSettle();
              noOverflow(tester);
              await captureProgression(tester, 'deck-save-error-$suffix');
              tester
                  .widgetList<LunoButton>(find.byType(LunoButton))
                  .singleWhere((button) => button.icon == Icons.save_rounded)
                  .onPressed!();
              await tester.pumpAndSettle();
              noOverflow(tester);
              await captureProgression(tester, 'deck-saved-$suffix');
              await tester.runAsync(
                () => GameStore.instance.bindAccount('v216-render-$suffix'),
              );
              await tester.pumpAndSettle();
              await tester.scrollUntilVisible(
                find.text(language == 'tr' ? 'Savaş destesi' : 'Battle deck'),
                -240,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              noOverflow(tester);
              await captureProgression(tester, 'deck-session-$suffix');
              await tester.pumpWidget(const SizedBox());

              await tester.pumpWidget(
                shell(
                  BattleDeckScreen(
                    loadOverride:
                        () async => response(
                          deck:
                              CardId.values
                                  .skip(14)
                                  .map((c) => c.wire)
                                  .toList(),
                          owned: CardId.values.map((c) => c.wire).toList(),
                        ),
                  ),
                  language: language,
                  scale: scale,
                  reduced: true,
                ),
              );
              await tester.pumpAndSettle();
              await tester.scrollUntilVisible(
                find.byKey(const ValueKey('selected-deck-grid')),
                240,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              noOverflow(tester);
              await captureProgression(tester, 'deck-longnames-$suffix');
              await tester.pumpWidget(const SizedBox());

              await tester.pumpWidget(
                shell(
                  BattleDeckScreen(
                    catalogOnly: true,
                    loadOverride: () async => throw StateError('offline'),
                  ),
                  language: language,
                  scale: scale,
                  reduced: true,
                ),
              );
              await tester.pumpAndSettle();
              noOverflow(tester);
              await captureProgression(tester, 'cards-offline-$suffix');
              await tester.pumpWidget(const SizedBox());
            }
          },
        );
      }
    }
  }
}
