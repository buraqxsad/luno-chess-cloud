import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_ui/fixtures.dart';
import 'battle_ui/visual_test.dart'
    show
        VisualScene,
        renderBattle,
        captureKey,
        visualTap,
        editedFixture,
        knowledgeFixture;
import 'rc_screen_capture_test.dart' show capture;

void main() {
  setupPracticeTestAssets();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GameStore.instance.data =
        PlayerData.initial()
          ..ownedEmojis = {'smile', 'heart', 'think', 'crown'}
          ..emojiLoadout = ['smile', 'heart', 'think', 'crown'];
    GameStore.instance.loaded = true;
  });
  final scenes = <VisualScene>[
    const VisualScene('main'),
    VisualScene('first-turn', fixture: () => battleFixture(firstTurn: true)),
    const VisualScene('selected', taps: ['hand-shelter']),
    const VisualScene('target', taps: ['hand-shelter', 'square-12']),
    const VisualScene('menu', taps: ['open-menu']),
    const VisualScene('resign', taps: ['open-menu', 'resign-menu']),
    const VisualScene('own-deck', taps: ['open-own-deck']),
    const VisualScene('opponent-cards', taps: ['open-arsenal']),
    const VisualScene('emotes', taps: ['open-emotes']),
    VisualScene('knowledge', fixture: () => knowledgeFixture(false)),
    for (final card in CardId.values)
      VisualScene(
        'card-${card.wire}',
        fixture:
            () => battleFixture(
              hand: [card, ...CardId.values.where((c) => c != card).take(2)],
            ),
        taps: ['detail-${card.wire}'],
      ),
    for (final (name, winner) in [
      ('victory', PieceColor.white),
      ('defeat', PieceColor.black),
      ('draw', null),
    ])
      VisualScene(
        name,
        fixture:
            () => editedFixture((draft) {
              draft.phase = BattlePhase.terminal;
              draft.terminal = TerminalState(
                winner == null ? 'stalemate' : 'checkmate',
                winner: winner,
              );
            }),
      ),
    const VisualScene('compact', size: Size(320, 568)),
    const VisualScene(
      'compact-selected',
      size: Size(320, 568),
      taps: ['hand-shelter'],
    ),
    const VisualScene(
      'compact-target',
      size: Size(320, 568),
      taps: ['hand-shelter', 'square-12'],
    ),
    VisualScene(
      'compact-four',
      size: const Size(320, 568),
      fixture:
          () => battleFixture(
            hand: [
              CardId.shelter,
              CardId.chain,
              CardId.lockedSquare,
              CardId.slow,
            ],
          ),
    ),
    const VisualScene('compact-text', size: Size(320, 568), scale: 1.1),
    const VisualScene('scaled', size: Size(320, 640), scale: 1.5),
    const VisualScene('tablet', size: Size(768, 1024)),
    const VisualScene('landscape', size: Size(844, 390)),
  ];
  for (final language in ['tr', 'en']) {
    for (final scene in scenes) {
      testWidgets('RC battle rendered ${scene.name} $language', (tester) async {
        await renderBattle(
          tester,
          state: scene.fixture?.call(),
          size: scene.size,
          textScale: scene.scale,
          language: language,
          theme: LunoTheme.darkFor(language),
        );
        for (final tap in scene.taps) {
          await visualTap(tester, tap);
        }
        if (scene.name == 'knowledge') {
          final button = find.byTooltip(
            language == 'tr' ? 'Özel bilgiler' : 'Private knowledge',
          );
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pumpAndSettle();
        }
        await capture(
          tester,
          'battle-${scene.name}-$language',
          repaintKey: captureKey,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
    }
  }
}
