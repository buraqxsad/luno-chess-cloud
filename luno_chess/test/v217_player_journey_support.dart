import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/services/cosmetic_catalog.dart';
import 'package:luno_chess/services/luno_online_service.dart';

import 'battle_deck_account_test.dart' as deck;
import 'online_request_session_test.dart' show TestAuth, TestUser;
import 'v215_progression_product_test.dart' show modernProgress;

/// Transport fixture only. It does not prove server reward or pricing logic.
/// Deck legality, response validation, screen transitions and persistence use
/// production implementations in the acceptance tests.
class JourneyTransport {
  JourneyTransport(this.store)
    : gold = store.data.gold,
      gems = store.data.gems {
    auth.currentUser = TestUser(store.accountUid ?? 'first');
  }

  final GameStore store;
  final TestAuth auth = TestAuth();
  List<CardId> savedDeck = List.of(starterDeck);
  final Set<CardId> ownedCards = {...starterDeck};
  final Set<String> ownedSets = {'std'};
  final Set<String> ownedEmotes = {'smile'};
  List<String> loadout = [];
  String activeSet = 'std';
  int gold, gems;
  bool welcomeClaimed = false;
  int deckReads = 0, deckWrites = 0, welcomeRequests = 0;
  int purchases = 0, profileWrites = 0, preferenceWrites = 0;
  final Map<String, dynamic> extraState = {};

  Map<String, dynamic> get state => {
    'gold': gold,
    'gems': gems,
    'inventory': {
      'ownedSets': ownedSets.toList(),
      'activePieceSet': activeSet,
      'ownedEmojis': ownedEmotes.toList(),
    },
    'emojiLoadout': loadout,
    ...extraState,
  };

  LunoOnlineService service({GameStore? playerStore}) =>
      LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        playerStore: playerStore ?? store,
        appCheck: () async => 'journey-test-only',
        client: MockClient(_request),
      );

  Future<http.Response> _request(http.Request request) async {
    final body = jsonDecode(request.body) as Map;
    final path = request.url.path.split('/').last;
    Map<String, dynamic> result;
    switch (path) {
      case 'getPlayerState':
        result = {'ok': true, 'state': state};
      case 'getBattleV1Deck':
        deckReads++;
        result = deck.response(
          deck: savedDeck.map((card) => card.wire).toList(),
          owned: ownedCards.map((card) => card.wire).toList(),
        );
        if (ownedCards.length == starterDeck.length || welcomeClaimed) {
          result['progression'] = modernProgress(0, 0, welcomeClaimed);
        }
      case 'setBattleV1Deck':
        deckWrites++;
        final cards =
            (body['deck'] as List).cast<String>().map(CardId.parse).toList();
        validateDeck(cards);
        if (!ownedCards.containsAll(cards)) {
          throw StateError('Transport was asked to save an unowned card');
        }
        savedDeck = cards;
        result = {'ok': true, 'deck': body['deck']};
      case 'claimOnboardingReward':
        welcomeRequests++;
        final duplicate = welcomeClaimed;
        if (!duplicate) {
          welcomeClaimed = true;
          ownedCards.add(CardId.mine);
          gold += 500;
        }
        result = {
          'ok': true,
          'granted': !duplicate,
          'idempotent': duplicate,
          'welcome': {
            'version': 1,
            'claimed': true,
            'card': 'mine',
            'eligibility': 'account_welcome',
          },
          'reward': {'gold': 500},
          'state': state,
        };
      case 'purchaseSoftItem':
        purchases++;
        final item = body['itemId'] as String;
        final parts = item.split(':');
        if (item != 'emoji:heart') {
          throw StateError('Unexpected journey purchase: $item');
        }
        ownedEmotes.add('heart');
        gold -= cosmeticEmote('heart')!.goldPrice;
        result = {
          'ok': true,
          'purchased': true,
          'itemId': item,
          'transactionId': 'journey-emote-receipt',
          'grant': {'kind': parts[0], 'id': parts[1]},
          'state': state,
        };
      case 'updateProfile':
        profileWrites++;
        final next = body['activePieceSet'] as String;
        if (!ownedSets.contains(next)) {
          throw StateError('Transport was asked to equip an unowned set');
        }
        activeSet = next;
        result = {'ok': true, 'state': state};
      case 'updatePreferences':
        preferenceWrites++;
        loadout = (body['emojiLoadout'] as List).cast<String>();
        result = {'ok': true, 'state': state};
      case 'getBattleV1':
        result = {
          'ok': true,
          'protocolVersion': 'LUNO_BATTLE_V1',
          'match': null,
        };
      default:
        throw StateError('Unexpected journey endpoint: $path');
    }
    return http.Response(jsonEncode(result), 200);
  }

  void useAccount(String uid) => auth.currentUser = TestUser(uid);
}

Future<void> journeyPump(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
  }
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

Future<void> journeyFlush(WidgetTester tester, GameStore store) async {
  await journeyAwait(tester, store.flush);
}

Future<T> journeyAwait<T>(
  WidgetTester tester,
  Future<T> Function() operation,
) async {
  var done = false;
  T? value;
  Object? failure;
  await tester.runAsync(() async {
    operation().then(
      (result) {
        value = result;
        done = true;
      },
      onError: (Object error) {
        failure = error;
        done = true;
      },
    );
  });
  for (var i = 0; i < 100 && !done; i++) {
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(
    done,
    isTrue,
    reason: 'Fixture operation exceeded 100 bounded I/O turns',
  );
  if (failure != null) throw failure!;
  return value as T;
}

Future<void> journeyTap(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await journeyPump(tester);
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await journeyPump(tester);
}

void journeyViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
