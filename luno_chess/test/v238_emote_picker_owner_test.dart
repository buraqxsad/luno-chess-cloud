import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/emotes.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/battle_ui/sheets.dart';
import 'package:luno_chess/battle_v1/emotes.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'battle_ui/fixtures.dart' show battleFixture;
import 'battle_ui/visual_test.dart' show renderBattle, visualTap;
import 'helpers/battle_v1_response.dart' show v1Response;

Map<String, dynamic> _acceptedEmote() => {
  'ok': true,
  'event': {'sequence': 1, 'emojiId': 'smile', 'side': 'w'},
};

Future<ValueChanged<String>> _openPicker(WidgetTester tester) async {
  await visualTap(tester, 'open-emotes');
  expect(find.byType(BattleEmotePicker), findsOneWidget);
  return tester.widget<BattleEmotePicker>(find.byType(BattleEmotePicker)).onSend;
}

Future<void> _closePicker(WidgetTester tester) async {
  await tester.tap(
    find.byWidgetPredicate(
      (widget) => widget is BattleIconControl && widget.icon == Icons.close,
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(BattleEmotePicker), findsNothing);
}

void main() {
  setupPracticeTestAssets();
  setUp(() {
    GameStore.instance
      ..loaded = true
      ..data = PlayerData.initial()
      ..hasCompletedTutorial = true
      ..hasChosenUsername = true
      ..firstSessionMatchesStarted = 2;
  });

  testWidgets('late emote response cannot close a replacement match sheet', (
    tester,
  ) async {
    final response = Completer<Map<String, dynamic>>();
    var requests = 0;
    final battle = battleFixture();
    await renderBattle(
      tester,
      state: battle,
      theme: LunoTheme.darkFor('en'),
      language: 'en',
      requestOverride: (path, _) async {
        if (path == '/sendBattleV1Emote') {
          requests++;
          return response.future;
        }
        return v1Response(state: battle);
      },
    );
    await _openPicker(tester);
    await tester.tap(find.byKey(const ValueKey('send-emote-smile')));
    await tester.pump();
    expect(requests, 1);
    await _closePicker(tester);
    await visualTap(tester, 'open-own-deck');
    expect(find.byType(OpponentArsenalSheet), findsOneWidget);
    final replacement = ModalRoute.of(
      tester.element(find.byType(OpponentArsenalSheet)),
    );

    response.complete(_acceptedEmote());
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.byType(OpponentArsenalSheet), findsOneWidget);
    expect(replacement!.isCurrent, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final boundary in ['replacement sheet', 'background']) {
    testWidgets('old picker cannot send after $boundary', (tester) async {
      var requests = 0;
      final battle = battleFixture();
      await renderBattle(
        tester,
        state: battle,
        theme: LunoTheme.darkFor('en'),
        language: 'en',
        requestOverride: (path, _) async {
          if (path == '/sendBattleV1Emote') {
            requests++;
            return _acceptedEmote();
          }
          if (path == '/getBattleV1Emotes') {
            return {'ok': true, 'sequence': 0, 'events': []};
          }
          return v1Response(state: battle);
        },
      );
      final oldSend = await _openPicker(tester);
      if (boundary == 'replacement sheet') {
        await _closePicker(tester);
        await visualTap(tester, 'open-own-deck');
      } else {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      }

      oldSend('smile');
      await tester.pump();
      expect(requests, 0);
      if (boundary == 'replacement sheet') {
        expect(find.byType(OpponentArsenalSheet), findsOneWidget);
      } else {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();
        expect(find.byType(BattleEmotePicker), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('current picker sends once and closes its own sheet', (
    tester,
  ) async {
    final response = Completer<Map<String, dynamic>>();
    var requests = 0;
    await renderBattle(
      tester,
      theme: LunoTheme.darkFor('en'),
      language: 'en',
      requestOverride: (path, _) async {
        expect(path, '/sendBattleV1Emote');
        requests++;
        return response.future;
      },
    );
    final send = await _openPicker(tester);
    send('smile');
    send('smile');
    await tester.pump();
    expect(requests, 1);
    response.complete(_acceptedEmote());
    await tester.pumpAndSettle();
    expect(find.byType(BattleEmotePicker), findsNothing);
    send('smile');
    await tester.pump();
    expect(requests, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('old hotseat picker cannot act for the next acknowledged player', (
    tester,
  ) async {
    await tester.pumpWidget(
      shell(const BattleV1Screen(local: true), language: 'en', reduced: true),
    );
    await tester.pumpAndSettle();
    await visualTap(tester, 'hotseat-ready');
    final oldSend = await _openPicker(tester);
    final dynamic state = tester.state(find.byType(BattleV1Screen));
    final channel = state.emotes as BattleEmoteChannel;
    await _closePicker(tester);
    await visualTap(tester, 'square-12');
    await visualTap(tester, 'square-28');
    await visualTap(tester, 'hotseat-ready');
    await visualTap(tester, 'open-own-deck');
    expect(find.byType(OpponentArsenalSheet), findsOneWidget);

    oldSend('smile');
    await tester.pumpAndSettle();
    expect(channel.visible, isEmpty);
    expect(find.byType(OpponentArsenalSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
