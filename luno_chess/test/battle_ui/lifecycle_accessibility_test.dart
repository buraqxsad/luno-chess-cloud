import 'dart:async';
import 'dart:ui' show SemanticsAction;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_ui/layout.dart';
import 'package:luno_chess/battle_ui/private.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/battle_ui/sheets.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/local_session.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/screens/online_hub_screen.dart';
import '../helpers/battle_v1_response.dart';
import 'interaction_test.dart' show Harness, mount, tap, cleanup;

Widget app(Widget child) => MaterialApp(
  locale: const Locale('tr'),
  supportedLocales: LunoLocalizations.supportedLocales,
  localizationsDelegates: const [
    LunoLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: child,
);

Map<String, dynamic> finishedResponse() {
  final response = v1Response();
  response['status'] = 'finished';
  final public = (response['view'] as Map)['public'] as Map;
  public['result'] = {'reason': 'resign', 'winner': 'w'};
  public['settlementStatus'] = 'pending';
  return response;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    for (final channel in [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers/events',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
      for (final id in ['luno_music', 'luno_sfx_0', 'luno_sfx_1', 'luno_sfx_2'])
        'xyz.luan/audioplayers/events/$id',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
    }
  });

  testWidgets(
    'clock updates once per displayed second without rebuilding siblings',
    (tester) async {
      var reads = 0, siblings = 0, millis = 60000;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Column(
              children: [
                Builder(
                  builder: (_) {
                    siblings++;
                    return const SizedBox();
                  },
                ),
                BattleClock(
                  label: 'Clock',
                  active: true,
                  remaining: () {
                    reads++;
                    return millis;
                  },
                ),
              ],
            ),
          ),
        ),
      );
      final initialText = tester.widget<Text>(find.text('1:00'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        identical(initialText, tester.widget<Text>(find.text('1:00'))),
        true,
      );
      expect(reads, 2);
      millis = 59000;
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('0:59'), findsOneWidget);
      expect(siblings, 1);
      await cleanup(tester);
    },
  );

  for (final terminal in [false, true]) {
    testWidgets('inactive/terminal clock has no periodic work: $terminal', (
      tester,
    ) async {
      var reads = 0;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: BattleClock(
              label: 'Clock',
              active: terminal,
              terminal: terminal,
              remaining: () {
                reads++;
                return 300000;
              },
            ),
          ),
        ),
      );
      final before = reads;
      await tester.pump(const Duration(seconds: 2));
      expect(reads, before);
      await cleanup(tester);
    });
  }

  testWidgets(
    'background clock stays stopped across widget updates and resumes fresh',
    (tester) async {
      var reads = 0, millis = 60000;
      Widget clock(bool active) => app(
        Scaffold(
          body: BattleClock(
            label: 'Clock',
            active: active,
            remaining: () {
              reads++;
              return millis;
            },
          ),
        ),
      );
      await tester.pumpWidget(clock(true));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpWidget(clock(false));
      await tester.pumpWidget(clock(true));
      final pausedReads = reads;
      await tester.pump(const Duration(seconds: 2));
      expect(reads, pausedReads);
      millis = 51000;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('0:51'), findsOneWidget);
      await cleanup(tester);
      final disposedReads = reads;
      await tester.pump(const Duration(seconds: 2));
      expect(reads, disposedReads);
    },
  );

  testWidgets(
    'local session accepts only legal actions and freezes after resignation',
    (tester) async {
      final session = BattleV1LocalSession(hotseat: true);
      expect(await session.submit(const ChessMoveAction('e2e5')), false);
      expect(await session.submit(const ChessMoveAction('e2e4')), true);
      expect(session.view.viewer, PieceColor.black);
      expect(session.version, 1);
      session.observe(false);
      session.observe(true);
      session.resign();
      final remaining = session.remaining(PieceColor.black);
      expect(session.terminal!.reason, 'resign');
      expect(session.legalActions, isEmpty);
      expect(await session.submit(const PassAction()), false);
      await tester.pump(const Duration(seconds: 2));
      expect(session.remaining(PieceColor.black), remaining);
      session.dispose();
      session.observe(true);
    },
  );

  testWidgets(
    'disposing during an AI turn cannot mutate or notify the closed session',
    (tester) async {
      final session = BattleV1LocalSession();
      var notifications = 0;
      session.addListener(() => notifications++);
      await session.submit(const ChessMoveAction('e2e4'));
      expect(session.busy, true);
      session.dispose();
      final before = notifications, version = session.version;
      await tester.pump(const Duration(seconds: 2));
      expect(notifications, before);
      expect(session.version, version);
    },
  );

  testWidgets('board, mana and deck expose meaningful accessible values', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final h = Harness();
      await mount(tester, h);
      expect(find.bySemanticsLabel('e2, Beyaz Piyon'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Rakibin Kartları, 10 kart'),
        findsOneWidget,
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Rakibin Kartları, 10 kart'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        true,
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Maç menüsü'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        true,
      );
      expect(find.bySemanticsLabel('Siper, Mana 2'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.byType(BattleMana).last)
            .getSemanticsData()
            .value,
        '6 / 6',
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('open-arsenal'))).height,
        greaterThanOrEqualTo(48),
      );
      for (final control in find.byType(BattleIconControl).evaluate()) {
        final size = tester.getSize(find.byWidget(control.widget));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      await cleanup(tester);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'loading uses an empty 64-square skeleton rather than an invented match',
    (tester) async {
      await tester.pumpWidget(
        app(const BattleLoadingStage(message: 'Loading')),
      );
      final grid = tester.widget<GridView>(find.byType(GridView));
      expect(
        (grid.childrenDelegate as SliverChildBuilderDelegate).childCount,
        64,
      );
      expect(find.byType(BattleBoard), findsNothing);
      expect(find.byType(BattleClock), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await cleanup(tester);
    },
  );

  testWidgets(
    'advanced projection dismisses a stale private choice without submitting',
    (tester) async {
      final h = Harness(hand: [CardId.prophecy, CardId.shelter, CardId.mine]);
      h.state = DeckManager.apply(
        h.state,
        const PlayCardAction(CardId.prophecy),
      );
      await h.controller.reconnect();
      await mount(tester, h);
      await tap(tester, 'open-private');
      expect(find.byType(PrivateChoiceSheet), findsOneWidget);
      h.version++;
      await h.controller.reconnect();
      await tester.pumpAndSettle();
      expect(find.byType(PrivateChoiceSheet), findsNothing);
      expect(h.sent, isEmpty);
      await cleanup(tester);
    },
  );

  testWidgets(
    'stale owned sheet removal preserves an unrelated covering route',
    (tester) async {
      final h = Harness();
      await mount(tester, h);
      await tap(tester, 'open-arsenal');
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Covering route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      h.version++;
      await h.controller.reconnect();
      await tester.pumpAndSettle();
      expect(find.text('Covering route'), findsOneWidget);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.byType(OpponentArsenalSheet), findsNothing);
      expect(find.byType(BattleV1Screen), findsOneWidget);
      await cleanup(tester);
    },
  );

  testWidgets('local rematch starts a fresh board, hand, phase and clock', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(const BattleV1Screen(local: true)));
    await tester.pumpAndSettle();
    await tap(tester, 'hotseat-ready');
    await tester.tap(find.byTooltip('Maç menüsü'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Teslim ol'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Teslim ol'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('local-rematch')), findsOneWidget);
    await tap(tester, 'local-rematch');
    await tap(tester, 'hotseat-ready');
    final board = tester.widget<BattleBoard>(find.byType(BattleBoard));
    expect(
      board.view.rules.toJson()['fen'],
      startsWith('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w'),
    );
    expect(board.view.rules.phase, BattlePhase.chess);
    expect(board.view.ownHand, hasLength(3));
    expect(find.byKey(const ValueKey('local-rematch')), findsNothing);
    await cleanup(tester);
  });

  testWidgets(
    'failed result acknowledgement is retryable and double taps cannot start two requests',
    (tester) async {
      final wait = Completer<Map<String, dynamic>>();
      var requests = 0;
      final controller = BattleV1Controller(
        uid: 'self',
        matchId: v1MatchId,
        initialResponse: finishedResponse(),
        persistPending: (_) async {},
        request: (path, _) {
          expect(path, '/ackBattleV1Result');
          requests++;
          return wait.future;
        },
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        app(BattleV1Screen(controllerOverride: controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-online-match')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('new-online-match')));
      await tester.pump();
      expect(requests, 1);
      wait.complete({'ok': false});
      await tester.pumpAndSettle();
      expect(find.byType(BattleV1Screen), findsOneWidget);
      expect(find.text('Maç verisi şu anda doğrulanamıyor'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('new-online-match')));
      await tester.pumpAndSettle();
      expect(requests, 2);
      await cleanup(tester);
    },
  );

  testWidgets(
    'acknowledged result opens the existing ranked flow without replaying rewards',
    (tester) async {
      final paths = <String>[];
      final controller = BattleV1Controller(
        uid: 'self',
        matchId: v1MatchId,
        initialResponse: finishedResponse(),
        persistPending: (_) async {},
        request: (path, _) async {
          paths.add(path);
          return {'ok': true};
        },
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        app(BattleV1Screen(controllerOverride: controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-online-match')));
      await tester.pumpAndSettle();
      expect(paths, ['/ackBattleV1Result']);
      expect(find.byType(OnlineHubScreen), findsOneWidget);
      expect(find.byType(BattleV1Screen), findsNothing);
      await cleanup(tester);
    },
  );
}
