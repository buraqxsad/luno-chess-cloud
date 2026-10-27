import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/practice_coach.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/battle_v1/emotes.dart';
import 'package:luno_chess/battle_v1/online.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/screens/online_hub_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_v1/settlement_receipt_test.dart' show receiptResponse;
import 'helpers/battle_v1_response.dart';

Future<GlobalKey<NavigatorState>> mountBattle(
  WidgetTester tester,
  Widget battle, {
  String language = 'tr',
}) async {
  tester.view.physicalSize = const Size(390, 950);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      theme: LunoTheme.dark,
      locale: Locale(language),
      supportedLocales: LunoLocalizations.supportedLocales,
      localizationsDelegates: const [
        LunoLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Scaffold(body: Text('ROOT')),
    ),
  );
  unawaited(
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => battle),
    ),
  );
  await tester.pumpAndSettle();
  return navigator;
}

Future<void> cleanup(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 4));
}

void main() {
  for (final language in ['tr', 'en']) {
    testWidgets('a covered result cannot start acknowledgement: $language', (
      tester,
    ) async {
      var acknowledgements = 0;
      final controller = BattleV1Controller(
        uid: 'self',
        matchId: v1MatchId,
        initialResponse: receiptResponse(),
        persistPending: (_) async {},
        request: (path, _) async {
          if (path == '/ackBattleV1Result') acknowledgements++;
          return {'ok': true, 'acknowledged': true};
        },
      );
      addTearDown(controller.dispose);
      final navigator = await mountBattle(
        tester,
        BattleV1Screen(controllerOverride: controller),
        language: language,
      );
      final callback =
          tester
              .widget<BattleCommand>(
                find.byKey(const ValueKey('new-online-match')),
              )
              .onPressed!;
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('COVER')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      callback();
      await tester.pumpAndSettle();
      expect(acknowledgements, 0);
      expect(find.text('COVER'), findsOneWidget);
      await cleanup(tester);
    });
    testWidgets(
      'late result acknowledgement never replaces a covering route: $language',
      (tester) async {
        final ack = Completer<Map<String, dynamic>>();
        final controller = BattleV1Controller(
          uid: 'self',
          matchId: v1MatchId,
          initialResponse: receiptResponse(),
          persistPending: (_) async {},
          request:
              (path, _) =>
                  path == '/ackBattleV1Result'
                      ? ack.future
                      : Future.value(receiptResponse()),
        );
        addTearDown(controller.dispose);
        final navigator = await mountBattle(
          tester,
          BattleV1Screen(controllerOverride: controller),
          language: language,
        );
        final button = find.byKey(const ValueKey('new-online-match'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
        unawaited(
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('COVER')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        ack.complete({'ok': true, 'acknowledged': true});
        await tester.pumpAndSettle();
        expect(find.text('COVER'), findsOneWidget);
        expect(find.byType(OnlineHubScreen, skipOffstage: false), findsNothing);
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        final command = tester.widget<BattleCommand>(button);
        expect(
          command.onPressed,
          isNotNull,
          reason: 'An acknowledged result must remain usable after returning.',
        );
        await cleanup(tester);
      },
    );

    testWidgets('practice progress save failure is recoverable: $language', (
      tester,
    ) async {
      var attempts = 0;
      await mountBattle(
        tester,
        BattleV1Screen(
          practiceStage: 0,
          onPracticeComplete: () async {
            attempts++;
            if (attempts == 1) throw StateError('storage unavailable');
          },
        ),
        language: language,
      );
      final coach = tester.widget<BattlePracticeCoach>(
        find.byType(BattlePracticeCoach),
      );
      coach.progress
        ..moves = 4
        ..cast = true
        ..discarded = true;
      coach.onComplete!();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(attempts, 1);
      final retry = tester.widget<BattlePracticeCoach>(
        find.byType(BattlePracticeCoach),
      );
      expect(retry.onComplete, isNotNull);
      expect(find.byKey(const ValueKey('practice-save-error')), findsOneWidget);
      retry.onComplete!();
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.byKey(const ValueKey('practice-save-error')), findsNothing);
      await cleanup(tester);
    });
  }

  test('clearing emotes invalidates an already running feed', () async {
    final pending = Completer<Map<String, dynamic>>();
    var calls = 0;
    final channel = BattleEmoteChannel(
      matchId: v1MatchId,
      request: (_, _) async {
        if (++calls == 1) return {'ok': true, 'sequence': 0, 'events': []};
        return pending.future;
      },
    );
    addTearDown(channel.dispose);
    await channel.fetch();
    final fetch = channel.fetch();
    channel.clear();
    pending.complete({
      'ok': true,
      'sequence': 1,
      'events': [
        {'sequence': 1, 'emojiId': 'smile', 'side': 'b'},
      ],
    });
    await fetch;
    expect(channel.visible, isEmpty);
  });

  test(
    'clearing emotes prevents an in-flight send from reopening a bubble',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      final channel = BattleEmoteChannel(
        matchId: v1MatchId,
        request: (_, _) => pending.future,
      );
      addTearDown(channel.dispose);
      final send = channel.send('smile', PieceColor.white, {'smile'});
      channel.clear();
      pending.complete({
        'ok': true,
        'event': {'sequence': 1, 'emojiId': 'smile', 'side': 'w'},
      });
      await send;
      expect(channel.visible, isEmpty);
      expect(
        channel.canSend,
        isFalse,
        reason: 'An acknowledged server send must still respect its cooldown.',
      );
    },
  );
}
