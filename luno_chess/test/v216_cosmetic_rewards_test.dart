import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/cards.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:luno_chess/widgets/cosmetic_emote_art.dart';
import 'package:luno_chess/widgets/cosmetic_match_preview.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'v216_cosmetics_visual_test.dart' show captureCosmetic;

void main() {
  setupPracticeTestAssets();
  for (final language in ['tr', 'en']) {
    for (final width in [320.0, 390.0, 430.0, 768.0]) {
      for (final type in ['card', 'set']) {
        testWidgets('confirmed $type reward $language $width real render', (tester) async {
          final height = width == 320 ? 568.0 : 1024.0;
          tester.view.physicalSize = Size(width, height);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final en = language == 'en';
          await tester.pumpWidget(shell(Scaffold(body: ShopRewardDialog(
            title: en ? 'COLLECTION UPDATED' : 'KOLEKSİYONUN YENİLENDİ',
            art: LunoAssets.shopDaily,
            message: type == 'set'
                ? (en ? 'Your complete Ottoman set is ready.' : 'Tam Osmanlı taş setin hazır.')
                : (en ? 'A new battle card is ready for your deck.' : 'Yeni savaş kartın desten için hazır.'),
            pieceSet: type == 'set' ? 'ottoman' : null,
            cardUnlock: type == 'card' ? CardId.prophecy : null,
          )), language: language, scale: 1.5, reduced: true));
          final action = find.byKey(const ValueKey('shop-reward-action'));
          expect(tester.getRect(action).bottom, lessThanOrEqualTo(height));
          expect(tester.getRect(action).top, greaterThanOrEqualTo(0));
          expect(find.byType(CosmeticMatchPreview), type == 'set' ? findsOneWidget : findsNothing);
          expect(find.byType(BattleCardArt), type == 'card' ? findsOneWidget : findsNothing);
          if (type == 'card') {
            expect(tester.widget<BattleCardTile>(find.byType(BattleCardTile)).cost,
              cardDefinitions[CardId.prophecy]!.cost);
          }
          await captureCosmetic(tester, 'reward-$type-$language-${width.toInt()}-150');
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }

  for (final language in ['tr', 'en']) {
    testWidgets('chest distinguishes emote unlock from fragments in $language', (tester) async {
      await tester.pumpWidget(shell(const Scaffold(body: ChestRevealDialog(
        chestId: 'royal', rewards: [
          {'type': 'emoji', 'id': 'crown', 'amount': 2, 'unlocked': true},
          {'type': 'emoji', 'id': 'heart', 'amount': 3},
          {'type': 'skin', 'id': 'obsidian', 'amount': 1},
          {'type': 'battle_card', 'id': 'radar', 'amount': 1},
        ],
      )), language: language, reduced: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reward-unlocked-emote-crown')), findsOneWidget);
      expect(find.byKey(const ValueKey('reward-unlocked-emote-heart')), findsNothing);
      expect(find.byType(CosmeticEmoteArt), findsOneWidget);
      expect(find.byType(CosmeticMatchPreview), findsNothing);
      expect(find.textContaining(language == 'en' ? 'Loving Luno · pieces' : 'Kalpli Luno · parça'), findsOneWidget);
      expect(find.textContaining(language == 'en'
          ? 'Obsidian · board-frame pieces'
          : 'Obsidyen · tahta çerçevesi parçası'), findsOneWidget);
      expect(find.textContaining(language == 'en'
          ? 'Collection > Piece sets > Board frames'
          : 'Koleksiyon > Taş kostümleri > Tahta çerçeveleri'), findsOneWidget);
      expect(find.byType(BattleCardArt), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final size in [const Size(320, 568), const Size(568, 320)]) {
    testWidgets('chest primary action stays visible with 2x text at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(shell(const Scaffold(body: ChestRevealDialog(
        chestId: 'legendary', rewards: [
          {'type': 'emoji', 'id': 'rainbow', 'unlocked': true},
          {'type': 'gold', 'amount': 10000},
        ],
      )), language: 'en', scale: 2, reduced: true));
      await tester.pumpAndSettle();
      final action = find.byKey(const ValueKey('chest-reveal-continue'));
      expect(tester.getRect(action).bottom, lessThanOrEqualTo(size.height));
      expect(tester.getRect(action).top, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('reveal skip and retained close cannot grant twice or pop underlying route', (tester) async {
    final store = GameStore.instance;
    final previousSets = Set<String>.of(store.data.ownedPieceSets);
    final previousEmotes = Set<String>.of(store.data.ownedEmojis);
    await tester.pumpWidget(shell(const Scaffold(body: Text('collection underneath')), language: 'en'));
    final context = tester.element(find.text('collection underneath'));
    final closed = showDialog<void>(context: context, builder: (_) => const ChestRevealDialog(
      chestId: 'rare', rewards: [{'type': 'emoji', 'id': 'heart', 'unlocked': true}],
    ));
    await tester.pump();
    final action = find.byKey(const ValueKey('chest-reveal-continue'));
    tester.widget<LunoButton>(action).onPressed!();
    await tester.pumpAndSettle();
    final close = tester.widget<LunoButton>(action).onPressed!;
    close(); close();
    await tester.pumpAndSettle();
    await closed;
    close();
    await tester.pump();
    expect(find.text('collection underneath'), findsOneWidget);
    expect(store.data.ownedPieceSets, previousSets);
    expect(store.data.ownedEmojis, previousEmotes);
    expect(tester.takeException(), isNull);
  });

  testWidgets('emote entrance settles and reduced motion stays static', (tester) async {
    await tester.pumpWidget(shell(const Scaffold(body: CosmeticEmoteArt(id: 'fire'))));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(shell(const Scaffold(body: CosmeticEmoteArt(id: 'fire')), reduced: true));
    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('malformed reward records remain inert and do not crash the reveal', (tester) async {
    await tester.pumpWidget(shell(Scaffold(body: ChestRevealDialog(chestId: 'rare', rewards: [
      null, 'bad', {7: 'not a JSON key'},
      {'type': 'gold', 'amount': double.infinity},
      {'type': 'gems', 'amount': -2},
    ])), language: 'en', reduced: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Reward details unavailable.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('duplicate unlock records reveal the emote once', (tester) async {
    await tester.pumpWidget(shell(const Scaffold(body: ChestRevealDialog(chestId: 'rare', rewards: [
      {'type': 'emoji', 'id': 'heart', 'amount': 2, 'unlocked': true},
      {'type': 'emoji', 'id': 'heart', 'amount': 2, 'unlocked': true},
      {'type': 'emoji', 'id': 'heart', 'amount': 3, 'unlocked': true},
      {'type': 'emoji', 'id': 'heart', 'amount': 3, 'unlocked': true},
    ])), reduced: true));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reward-unlocked-emote-heart')), findsOneWidget);
    expect(find.byType(CosmeticEmoteArt), findsOneWidget);
    expect(find.textContaining('Kalpli Luno · parça  x3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unsafe or malformed reward scalars cannot announce an unlock', (tester) async {
    await tester.pumpWidget(shell(Scaffold(body: ChestRevealDialog(chestId: 'rare', rewards: [
      {'type': 'gold', 'amount': 1e300},
      {'type': 'gems', 'amount': null},
      {'type': null, 'unlocked': true},
      {'type': 'emoji', 'id': ['heart'], 'unlocked': true},
      {'type': 'emoji', 'id': 'heart', 'unlocked': 'true'},
      {'type': 'gold', 'amount': 1, 'name': {'private': 'not display text'}},
    ])), language: 'en', reduced: true));
    await tester.pumpAndSettle();
    expect(find.text('Reward details unavailable.'), findsOneWidget);
    expect(find.byType(CosmeticEmoteArt), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unknown emote rewards never borrow a known character or unlock marker', (tester) async {
    await tester.pumpWidget(shell(const Scaffold(body: ChestRevealDialog(chestId: 'rare', rewards: [
      {'type': 'emoji', 'id': 'forged', 'amount': 1, 'unlocked': true},
    ])), language: 'en', reduced: true));
    await tester.pumpAndSettle();
    expect(find.byType(CosmeticEmoteArt), findsNothing);
    expect(find.byWidgetPredicate((w) => w is LunoArt && w.path == LunoAssets.emoji('smile')), findsNothing);
    expect(find.byWidgetPredicate((w) => w is LunoArt && w.path == 'assets/native_art/arena-unlocked-v41.png'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
