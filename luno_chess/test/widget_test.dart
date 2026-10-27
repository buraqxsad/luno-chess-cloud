import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/home_screen.dart';
import 'package:luno_chess/battle_ui/layout.dart';
import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/match/match_state.dart';
import 'package:luno_chess/screens/game_screen.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/screens/online_hub_screen.dart';
import 'package:luno_chess/screens/online_match_screen.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:luno_chess/screens/play_mode_screen.dart';

void main() {
  testWidgets('Ana menü görsel hızlı erişim alanını gösterir', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    expect(find.text('ACEMİ KAMPI'), findsOneWidget);
  });

  testWidgets('Maç ekranı: durum + kart eli görünür', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(level: aiLevels.first)),
    );
    await tester.pump();
    expect(find.text('Sıra sende'), findsOneWidget);
    expect(find.text('Dondurma'), findsWidgets); // başlangıç destesinde freeze
  });

  testWidgets('Native oyun modu çevrimiçi ve AI seçeneklerini gösterir', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PlayModeScreen()));
    expect(find.text('SIRALI MAÇ'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('YAPAY ZEKÂYA KARŞI'),
      200,
      scrollable: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );
    expect(find.text('YAPAY ZEKÂYA KARŞI'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('ARKADAŞINLA OYNA'),
      200,
      scrollable: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );
    expect(find.text('ARKADAŞINLA OYNA'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('YÜZ YÜZE OYNA'),
      200,
      scrollable: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('YÜZ YÜZE OYNA'), findsOneWidget);
  });

  testWidgets('Yüz yüze maç iki tarafın hamle sırasını native motora bağlar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(level: aiLevels.first, local: true)),
    );
    await tester.pump();
    expect(find.text('YÜZ YÜZE OYNA'), findsOneWidget);
    expect(find.text('Beyaz'), findsOneWidget);
    expect(find.text('Siyah'), findsOneWidget);
    expect(find.text('Sıra: Beyaz'), findsOneWidget);
  });

  testWidgets('Yerel sonuç doğru kazananı gösterir ve tekrar süresini korur', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultScreen(
          result: MatchResult.blackWins,
          level: aiLevels.first,
          reward: 0,
          local: true,
          timeControlMinutes: 3,
        ),
      ),
    );
    expect(find.text('SİYAH KAZANDI'), findsOneWidget);
    expect(
      find.text('Yüz yüze maç tamamlandı. Kupa ve ödül değişmedi.'),
      findsOneWidget,
    );

    final replayButton = find.text('TEKRAR OYNA');
    await tester.ensureVisible(replayButton);
    await tester.tap(replayButton);
    await tester.pumpAndSettle();
    expect(find.byType(BattleV1Screen), findsOneWidget);
    final replay = tester.widget<BattleV1Screen>(find.byType(BattleV1Screen));
    expect(replay.local, isTrue);
    expect(replay.timeControlMinutes, 3);
    final clocks = tester.widgetList<BattleClock>(find.byType(BattleClock));
    expect(clocks, hasLength(2));
    // The active clock uses real elapsed time while the route settles.
    expect(clocks.singleWhere((clock) => !clock.active).remaining(), 180000);
    expect(
      clocks.singleWhere((clock) => clock.active).remaining(),
      inInclusiveRange(170000, 180000),
    );
  });

  testWidgets('Online merkez çevrimdışı durumda çökmek yerine yenileme sunar', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: OnlineHubScreen()));
    expect(find.text('SIRALI EŞLEŞME'), findsOneWidget);
    expect(find.text('BAĞLANTIYI YENİLE'), findsOneWidget);
  });

  testWidgets('Online maçta gelen beraberlik teklifi cevaplanabilir görünür', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OnlineMatchScreen(
          matchId: 'rm_test_match_0001',
          initialView: {
            'status': 'active',
            'sequence': 1,
            'viewerColor': 'W',
            'turn': 'W',
            'phase': 'card',
            'board': <Map<String, Object?>>[],
            'player': {'name': 'Sen', 'trophies': 100},
            'opponent': {'name': 'Rakip', 'trophies': 120},
            'drawOffer': {'bySelf': false, 'expiresAt': 9999999999999},
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text('KABUL ET'), findsOneWidget);
    expect(find.text('REDDET'), findsOneWidget);
  });

  testWidgets(
    'Koleksiyon hub dört native alt ekrana açılan kapıları gösterir',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: CollectionScreen()));
      expect(find.text('DESTE'), findsOneWidget);
      expect(find.text('KARTLAR'), findsOneWidget);
      expect(find.text('TAŞ KOSTÜMLERİ'), findsOneWidget);
      expect(find.text('EMOJİLER'), findsOneWidget);
    },
  );

  testWidgets('HTML overlay sözleşmesindeki arena ve seviye ekranları native', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ArenasScreen()));
    await tester.scrollUntilVisible(find.text('ARENA YOLU'), 100,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('ARENA YOLU'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Acemi Kampı'), 100,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Acemi Kampı'), findsOneWidget);
    expect(find.text('Acemi Kampı').hitTestable(), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: LevelRewardsScreen()));
    expect(find.text('SEVİYE ÖDÜLLERİ'), findsWidgets);
    expect(find.text('ANLADIM'), findsOneWidget);
  });

  testWidgets('Native sonuç destek ekranları kritik eylemleri gösterir', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ArenaPromotionScreen(
          arenaName: 'Piyon Vadisi',
          arenaArt: 'assets/native_art/arena-02-piyon-v24.webp',
        ),
      ),
    );
    expect(find.text('YENİ ARENA'), findsOneWidget);
    expect(find.text('DEVAM ET'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: SeasonEndRewardScreen(tier: 'HÜKÜMDAR', gold: 500, gems: 20),
      ),
    );
    expect(find.text('SEZON SONU ÖDÜLÜ'), findsOneWidget);
    expect(find.text('ÖDÜLÜ AL'), findsOneWidget);
  });
}
