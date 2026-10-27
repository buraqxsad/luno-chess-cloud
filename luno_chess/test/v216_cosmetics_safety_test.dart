import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/battle_ui/art.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/data/card_pool.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/collection_screens.dart';
import 'package:luno_chess/services/cosmetic_catalog.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/widgets/cosmetic_match_preview.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'online_request_session_test.dart' show TestAuth, TestUser;
import 'v216_cosmetics_visual_test.dart' show captureCosmetic;

void main() {
  setupPracticeTestAssets();
  test('all fourteen canonical emotes have exact current acquisition metadata', () {
    expect(cosmeticEmotes.map((e) => e.id).toList(), kEmojiIds);
    expect(cosmeticEmotes.map((e) => e.id).toSet().length, 14);
    for (final item in cosmeticEmotes) {
      expect(item.title(true), isNotEmpty);
      expect(item.title(false), isNotEmpty);
      expect(item.piecesRequired, isIn([5, 10, 20]));
    }
    expect(cosmeticEmote('forged'), isNull);
    expect(cosmeticEmote('laugh')!.passLevel, 4);
    expect(cosmeticEmote('trophy')!.passLevel, 12);
    expect(cosmeticEmote('heart')!.passLevel, 24);
    expect(cosmeticEmote('angry')!.premium, isTrue);
    expect(costumeSource('ice', true), 'Shop · complete set');
    expect(costumeSource('ottoman', true), contains('Free Pass 20'));
  });

  test('preview uses battle resolver even for unknown legacy set IDs', () {
    for (final side in PieceColor.values) {
      for (final type in PieceType.values) {
        for (final id in [...kPieceSetIds, 'forged']) {
          expect(CostumeBoardPreview.assetFor(id, side, type),
            BattleArt.piecePath(side, type, set: id));
        }
      }
    }
  });

  Future<(GameStore, LunoOnlineService, TestAuth)> account(
      Future<http.Response> Function(http.Request) handler) async {
    final store = GameStore.createForTesting();
    await store.bindAccount('first');
    store.data = PlayerData.initial()
      ..ownedPieceSets.add('ottoman')
      ..ownedEmojis.addAll(['smile', 'heart'])
      ..emojiLoadout = ['smile'];
    final auth = TestAuth();
    final online = LunoOnlineService.forTesting(bootstrap: () async {},
      auth: auth, appCheck: () async => 'local-test-only',
      client: MockClient(handler));
    await online.start();
    addTearDown(online.dispose);
    addTearDown(store.dispose);
    return (store, online, auth);
  }

  for (final scenario in ['success', 'failure', 'account', 'covered', 'disposed', 'epoch', 'newer', 'same-uid', 'unowned-response']) {
    testWidgets('equip $scenario remains confirmed, single-flight and owner safe', (tester) async {
      final reply = Completer<http.Response>();
      var requests = 0;
      final paths = <String>[];
      final (store, online, auth) = await account((request) {
        requests++;
        paths.add(request.url.path);
        return reply.future;
      });
      await tester.pumpWidget(shell(PieceCostumeScreen(online: online, playerStore: store), reduced: true));
      final button = find.byKey(const ValueKey('costume-equip-ottoman'));
      await tester.ensureVisible(button);
      await tester.pump();
      final action = tester.widget<LunoButton>(button).onPressed!;
      action(); action();
      await tester.pump();
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 20 && requests == 0; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(requests, 1);
      expect(store.data.pieceSet, 'luno');
      expect(paths, [endsWith('/updateProfile')]);
      if (scenario == 'account') {
        auth.currentUser = TestUser('second');
        await store.bindAccount('second');
      }
      if (scenario == 'epoch') store.invalidateServerStates();
      if (scenario == 'newer') store.data.pieceSet = 'roma';
      if (scenario == 'same-uid') {
        await store.bindAccount('second');
        await store.bindAccount('first');
      }
      if (scenario == 'disposed') await tester.pumpWidget(const SizedBox());
      if (scenario == 'covered') {
        Navigator.of(tester.element(find.byType(PieceCostumeScreen))).push(
          MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('cover'))));
        await tester.pumpAndSettle();
      }
      reply.complete(http.Response(jsonEncode(scenario == 'failure'
          ? {'ok': false, 'code': 'rejected'}
          : {'ok': true, 'state': {'inventory': {
              'activePieceSet': 'ottoman', 'ownedSets': scenario == 'unowned-response'
                  ? ['std'] : ['std', 'ottoman']}}}),
          scenario == 'failure' ? 409 : 200));
      await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(store.data.pieceSet, scenario == 'newer' ? 'roma'
          : ['success', 'covered', 'disposed'].contains(scenario) ? 'ottoman' : 'luno');
      if (['covered', 'account', 'disposed', 'epoch', 'newer', 'same-uid', 'unowned-response'].contains(scenario)) {
        expect(find.text('Kuşanıldı. Taşların sonraki maç için hazır.'), findsNothing);
      }
      if (scenario == 'unowned-response') {
        expect(store.data.ownedPieceSets, contains('ottoman'));
      }
      if (['covered', 'account', 'disposed'].contains(scenario)) {
        action();
        await tester.pump();
        expect(requests, 1);
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  test('equip test transport uses actual updateProfile API', () async {
    var calls = 0;
    final (_, online, _) = await account((request) async {
      calls++;
      expect(request.url.path, endsWith('/updateProfile'));
      return http.Response('{"ok":true,"state":{"inventory":{"activePieceSet":"ottoman"}}}', 200);
    });
    expect((await online.setPieceSet('ottoman'))['ok'], true);
    expect(calls, 1);
  });

  for (final scenario in ['success', 'failure', 'mismatch', 'account', 'covered', 'disposed', 'newer', 'epoch-success', 'epoch-failure']) {
    testWidgets('emote save $scenario is single-flight and cannot overwrite a newer owner or choice', (tester) async {
      final reply = Completer<http.Response>();
      var requests = 0;
      final payloads = <Map<String, dynamic>>[];
      final paths = <String>[];
      final (store, online, auth) = await account((request) {
        requests++;
        paths.add(request.url.path);
        payloads.add(jsonDecode(request.body) as Map<String, dynamic>);
        return reply.future;
      });
      await tester.pumpWidget(shell(EmojiCollectionScreen(online: online, playerStore: store), reduced: true));
      final tile = find.byKey(const ValueKey('emote-select-heart'));
      await tester.ensureVisible(tile);
      await tester.pump();
      final action = tester.widget<InkWell>(tile).onTap!;
      action(); action();
      await tester.pump();
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 20 && requests == 0; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(requests, 1);
      expect(paths, [endsWith('/updatePreferences')]);
      expect(payloads.single['emojiLoadout'], ['smile', 'heart']);
      expect(store.data.emojiLoadout, ['smile', 'heart']);
      if (scenario == 'account') {
        auth.currentUser = TestUser('second');
        await store.bindAccount('second');
      }
      if (scenario == 'newer') {
        store.setEmojiLoadout(['heart']);
      }
      if (scenario.startsWith('epoch-')) store.invalidateServerStates();
      final replacement = List<String>.of(store.data.emojiLoadout);
      if (scenario == 'disposed') {
        await tester.pumpWidget(const SizedBox());
      }
      if (scenario == 'covered') {
        Navigator.of(tester.element(find.byType(EmojiCollectionScreen))).push(
          MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('cover'))));
        await tester.pumpAndSettle();
      }
      final failed = scenario == 'failure' || scenario == 'newer' || scenario == 'epoch-failure';
      reply.complete(http.Response(jsonEncode(failed
          ? {'ok': false, 'code': 'rejected'}
          : {'ok': true, 'state': {'gold': 999, 'emojiLoadout': scenario == 'mismatch'
              ? ['heart', 'smile'] : ['smile', 'heart']}}), failed ? 409 : 200));
      await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(store.data.emojiLoadout,
          scenario == 'account' || scenario == 'newer' || scenario.startsWith('epoch-') ? replacement
          : scenario == 'failure' || scenario == 'mismatch' ? ['smile']
          : ['smile', 'heart']);
      if (scenario == 'covered' || scenario == 'account' || scenario == 'disposed') {
        expect(find.text('İfadeler kaydedilemedi. Tekrar dene.'), findsNothing);
        action();
        await tester.pump();
        expect(requests, 1);
      }
      if (scenario.startsWith('epoch-')) {
        expect(find.text('İfadeler kaydedilemedi. Tekrar dene.'), findsNothing);
        expect(store.data.gold, isNot(999));
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('quick emote limit rejects a fifth selection without a request', (tester) async {
    var requests = 0;
    final (store, online, _) = await account((_) async {
      requests++;
      return http.Response('{"ok":false}', 409);
    });
    store.data.ownedEmojis.addAll(['laugh', 'cry', 'angry']);
    store.setEmojiLoadout(['smile', 'heart', 'laugh', 'cry']);
    await tester.pumpWidget(shell(EmojiCollectionScreen(online: online, playerStore: store), reduced: true));
    final tile = find.byKey(const ValueKey('emote-select-angry'));
    await tester.ensureVisible(tile);
    await tester.pump();
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(store.data.emojiLoadout, ['smile', 'heart', 'laugh', 'cry']);
    expect(requests, 0);
    expect(find.text('Maçta en fazla 4 hızlı ifade kullanabilirsin.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('locked emote previews source and confirmed server shard count without equip', (tester) async {
    var reads = 0;
    final (store, online, _) = await account((request) async {
      expect(request.url.path, endsWith('/getPlayerState'));
      reads++;
      return http.Response(jsonEncode({'ok': true, 'state': {
        'inventory': {'emojiPieces': {'laugh': 7}}}}), 200);
    });
    await tester.pumpWidget(shell(EmojiCollectionScreen(online: online, playerStore: store), language: 'en', reduced: true));
    final preview = find.byKey(const ValueKey('emote-preview-laugh'));
    await tester.ensureVisible(preview); await tester.pump();
    await tester.tap(preview); await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.text('7 / 20 pieces'), findsOneWidget);
    expect(find.textContaining('Free 4'), findsOneWidget);
    expect(find.text('ADD TO QUICK EMOTES'), findsNothing);
    expect(store.data.emojiLoadout, ['smile']);
    expect(tester.takeException(), isNull);
  });

  for (final scenario in ['negative', 'noninteger', 'epoch', 'null', 'string', 'epoch-failure']) {
    testWidgets('emote progress $scenario stays unknown and can retry a current confirmed count', (tester) async {
      final reply = Completer<http.Response>();
      var reads = 0;
      final (store, online, _) = await account((request) async {
        expect(request.url.path, endsWith('/getPlayerState'));
        reads++;
        if (reads == 1) return reply.future;
        return http.Response('{"ok":true,"state":{"inventory":{"emojiPieces":{"laugh":7}}}}', 200);
      });
      await tester.pumpWidget(shell(EmojiCollectionScreen(online: online, playerStore: store),
        language: 'en', reduced: true));
      final button = find.byKey(const ValueKey('emote-preview-laugh'));
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      // Do not advance an active loading spinner to the request timeout.
      await tester.pump(const Duration(milliseconds: 400));
      expect(reads, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      if (scenario.startsWith('epoch')) store.invalidateServerStates();
      reply.complete(http.Response(jsonEncode(scenario == 'epoch-failure'
          ? {'ok': false, 'error': 'rejected'} : {'ok': true, 'state': {
        'inventory': {'emojiPieces': {'laugh': scenario == 'negative' ? -1
            : scenario == 'noninteger' ? 1.5 : scenario == 'null' ? null
            : scenario == 'string' ? '9' : 9}}}}), scenario == 'epoch-failure' ? 409 : 200));
      await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pumpAndSettle();
      expect(find.text('9 / 20 pieces'), findsNothing);
      await tester.ensureVisible(find.text('Retry progress'));
      await tester.tap(find.text('Retry progress'));
      await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pumpAndSettle();
      expect(find.text('7 / 20 pieces'), findsOneWidget);
      expect(reads, 2);
      expect(store.data.ownedEmojis, isNot(contains('laugh')));
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final language in ['tr', 'en']) {
    for (final width in [320.0, 390.0, 430.0, 768.0]) {
      for (final type in ['costume-preview', 'emote-preview']) {
        testWidgets('$type $language $width large text real render', (tester) async {
          tester.view.physicalSize = Size(width, width == 320 ? 568 : 1024);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final (store, online, _) = await account((_) async => http.Response(jsonEncode({
            'ok': true, 'state': {'inventory': {'emojiPieces': {'heart': 5}}}}), 200));
          await tester.pumpWidget(shell(type == 'costume-preview'
              ? PieceCostumeScreen(online: online, playerStore: store)
              : EmojiCollectionScreen(online: online, playerStore: store),
              language: language, scale: 1.5, reduced: true));
          final button = find.byKey(ValueKey(type == 'costume-preview'
              ? 'costume-preview-ottoman' : 'emote-preview-heart'));
          await tester.scrollUntilVisible(button, 160,
              scrollable: find.byType(Scrollable).first);
          await tester.ensureVisible(button); await tester.pump();
          await tester.tap(button); await tester.pumpAndSettle();
          if (type == 'costume-preview') {
            expect(find.byType(CosmeticMatchPreview), findsOneWidget);
            expect(tester.widget<BattleBoard>(find.byType(BattleBoard)).pieceSet, 'ottoman');
            expect(tester.widget<BattleBoard>(find.byType(BattleBoard)).enabled, isFalse);
            final action = find.byKey(const ValueKey('costume-preview-equip-ottoman'));
            expect(tester.getRect(action).bottom, lessThanOrEqualTo(tester.view.physicalSize.height));
            expect(action.hitTestable(), findsOneWidget);
          }
          await captureCosmetic(tester, '$type-$language-${width.toInt()}-150');
          expect(store.data.pieceSet, 'luno');
          expect(store.data.emojiLoadout, ['smile']);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }

  for (final language in ['tr', 'en']) {
    for (final size in [const Size(320, 568), const Size(568, 320)]) {
      testWidgets('costume preview pinned $language 2x at $size', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final (store, online, _) = await account((_) async => http.Response('{"ok":false}', 409));
        await tester.pumpWidget(shell(PieceCostumeScreen(online: online, playerStore: store),
          language: language, scale: 2, reduced: true));
        final preview = find.byKey(const ValueKey('costume-preview-ottoman'));
        await tester.scrollUntilVisible(preview, 200,
            scrollable: find.byType(Scrollable).first);
        await tester.pump();
        await tester.tap(preview);
        await tester.pumpAndSettle();
        final action = find.byKey(const ValueKey('costume-preview-equip-ottoman'));
        expect(action.hitTestable(), findsOneWidget);
        expect(tester.getRect(action).bottom, lessThanOrEqualTo(size.height));
        await captureCosmetic(tester, 'costume-preview-$language-${size.width.toInt()}x${size.height.toInt()}-200');
        expect(store.data.pieceSet, 'luno');
        await tester.pumpWidget(const SizedBox());
      });
    }
    for (final item in cosmeticEmotes) {
      testWidgets('all-emote ${item.id} $language current detail real render', (tester) async {
        tester.view.physicalSize = const Size(390, 1024);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final (store, online, _) = await account((request) async {
          expect(request.url.path, endsWith('/getPlayerState'));
          return http.Response('{"ok":true,"state":{"inventory":{"emojiPieces":{}}}}', 200);
        });
        await tester.pumpWidget(shell(EmojiCollectionScreen(online: online, playerStore: store),
          language: language, scale: 1.5, reduced: true));
        final button = find.byKey(ValueKey('emote-preview-${item.id}'));
        await tester.ensureVisible(button);
        await tester.pump();
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.text(item.title(language == 'en')), findsWidgets);
        await captureCosmetic(tester, 'emote-detail-${item.id}-$language-390-150');
        expect(store.data.emojiLoadout, ['smile']);
        expect(store.data.ownedEmojis, isNot(contains('rainbow')));
        await tester.pumpWidget(const SizedBox());
      });
    }
    testWidgets('full four-slot loadout $language small phone real render', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (store, online, _) = await account((_) async => http.Response('{"ok":false}', 409));
      store.data.ownedEmojis.addAll(['laugh', 'cry']);
      store.setEmojiLoadout(['smile', 'heart', 'laugh', 'cry']);
      await tester.pumpWidget(shell(EmojiCollectionScreen(online: online, playerStore: store),
        language: language, scale: 1.5, reduced: true));
      await captureCosmetic(tester, 'emotes-full-$language-320-150');
      expect(store.data.emojiLoadout, ['smile', 'heart', 'laugh', 'cry']);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final id in kPieceSetIds) {
    for (final size in [28.0, 40.0, 52.0]) {
      testWidgets('$id all twelve piece variants at ${size.toInt()}px real render', (tester) async {
        tester.view.physicalSize = const Size(430, 400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(shell(Scaffold(body: Center(child: SizedBox(
          width: (size + 4) * 6,
          child: CostumeBoardPreview(setId: id, bothSides: true),
        ))), language: 'en', reduced: true));
        expect(find.byType(Image), findsNWidgets(12));
        expect(tester.getSize(find.byType(Image).first).width, size);
        await captureCosmetic(tester, 'pieces-$id-${size.toInt()}px');
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
