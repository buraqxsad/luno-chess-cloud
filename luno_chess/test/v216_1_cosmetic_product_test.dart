import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/data/board_finishes.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/board_finishes_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'battle_ui/fixtures.dart' show battleFixture;
import 'online_request_session_test.dart' show TestAuth;
import 'rc_screen_capture_test.dart' show capture;

void main() {
  setupPracticeTestAssets();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('legacy rights round trip and malformed pieces cannot create ownership', () {
    final p = PlayerData.fromJson({...PlayerData.initial().toJson(),
      'ownedSkins': ['classic', 'jade', 'historic_unknown'], 'activeSkin': 'jade',
      'skinPieces': {'jade': 10, 'ruby': 5, 'obsidian': -1, 'celestial': double.infinity}});
    final copy = PlayerData.fromJson(p.toJson());
    expect(copy.ownedSkins, containsAll(['jade', 'historic_unknown']));
    expect(copy.activeSkin, 'jade');
    expect(copy.skinPieces, {'jade': 10, 'ruby': 5});
    expect(copy.ownedSkins, isNot(contains('ruby')));
    expect(PlayerData.fromJson({...p.toJson(), 'activeSkin': 'ruby'}).activeSkin, 'classic');
  });
  for (final failure in ['success', 'wrong-active', 'unowned', 'account', 'epoch', 'newer']) {
    testWidgets('server confirmed frame selection $failure', (tester) async {
      final store = GameStore.createForTesting();
      await store.bindAccount('first');
      store.data.ownedSkins.add('jade');
      final held = Completer<http.Response>();
      var requests = 0;
      final service = LunoOnlineService.forTesting(bootstrap: () async {}, auth: TestAuth(),
        appCheck: () async => 'test-only', client: MockClient((request) async {
          if (request.url.path.endsWith('updateProfile')) {
            requests++;
            expect(jsonDecode(request.body)['activeSkin'], 'jade');
            return held.future;
          }
          return http.Response(jsonEncode({'ok': true, 'state': {}}), 200);
        }));
      await service.start();
      addTearDown(service.dispose); addTearDown(store.dispose);
      await tester.pumpWidget(shell(BoardFinishesScreen(online: service, playerStore: store)));
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('finish-equip-jade'));
      await tester.scrollUntilVisible(button, 200, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button); await tester.pump();
      expect(store.data.activeSkin, 'classic');
      if (failure == 'account') await store.bindAccount('other');
      if (failure == 'epoch') store.invalidateServerStates();
      if (failure == 'newer') store.data.activeSkin = 'ruby';
      held.complete(http.Response(jsonEncode({'ok': true, 'state': {'inventory': {
        'activeSkin': failure == 'wrong-active' ? 'ruby' : 'jade',
        'ownedSkins': failure == 'unowned' ? ['classic'] : ['classic', 'jade'],
        'skinPieces': {'jade': 10},
      }}}), 200));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(store.data.activeSkin, failure == 'success' ? 'jade' : failure == 'newer' ? 'ruby' : 'classic');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final finish in boardFinishes) {
    testWidgets('actual board preserves pieces and legal input with ${finish.id} rim', (tester) async {
      int? tapped;
      await tester.pumpWidget(shell(Scaffold(body: Center(child: SizedBox(width: 280,
        child: BattleBoard(view: battleFixture().view(PieceColor.white), finish: finish.id,
          onTap: (square) => tapped = square))))));
      expect(find.byKey(ValueKey('board-finish-${finish.id}')),
          finish.id == 'classic' ? findsNothing : findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('square-8')));
      expect(tapped, 8);
      await capture(tester, 'board-${finish.id}', outputDirectory: 'qa/v216_1/after/legacy');
      expect(tester.takeException(), isNull);
    });
  }
  for (final lang in ['tr', 'en']) {
    for (final size in [const Size(320,568), const Size(390,844), const Size(768,1024)]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('frame collection $lang ${size.width} text$scale', (tester) async {
          final store=GameStore.createForTesting(); await store.bindAccount('first');
          store.data.ownedSkins.add('jade'); store.data.skinPieces['ruby']=5;
          final online=LunoOnlineService.forTesting(bootstrap: () async {}, auth: TestAuth(),
              appCheck: () async=>'test-only', client: MockClient((_) async =>
                http.Response(jsonEncode({'ok':true,'state':{}}),200)));
          await online.start(); addTearDown(online.dispose); addTearDown(store.dispose);
          tester.view.physicalSize=size; tester.view.devicePixelRatio=1;
          addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(shell(BoardFinishesScreen(online:online,playerStore:store),
              language:lang,scale:scale,reduced:true));
          await tester.pumpAndSettle();
          await capture(tester,'collection-$lang-${size.width.toInt()}-$scale',outputDirectory:'qa/v216_1/after/legacy');
          await tester.scrollUntilVisible(find.byKey(const ValueKey('finish-progress-ruby')),200,
              scrollable:find.byType(Scrollable).first);
          expect(find.text('5 / 10 ${lang=='en'?'pieces':'parça'}'),findsOneWidget);
          expect(tester.takeException(),isNull);
        });
      }
    }
  }
}
