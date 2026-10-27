import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/app.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/battle_deck_screen.dart';
import 'package:luno_chess/screens/battle_practice_campaign.dart';
import 'package:luno_chess/screens/collection_screens.dart';
import 'package:luno_chess/screens/difficulty_screen.dart';
import 'package:luno_chess/screens/friendly_online_screen.dart';
import 'package:luno_chess/screens/home_screen.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/screens/online_hub_screen.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:luno_chess/screens/pass_screen.dart';
import 'package:luno_chess/screens/play_mode_screen.dart';
import 'package:luno_chess/screens/profile_screen.dart';
import 'package:luno_chess/screens/public_player_profile_screen.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luno_chess/services/luno_online_service.dart';

import 'battle_deck_account_test.dart' show response;
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell, boundaryKey;
import 'online_request_session_test.dart' show TestAuth;

Map<String, dynamic> profile(String name, int score) => {
  'username': name,
  'trophies': score,
  'collectionScore': score + 200,
  'seasonScore': score + 100,
  'wins': 12,
  'losses': 7,
  'draws': 2,
  'gamesPlayed': 21,
  'country': 'GB',
  'bio': 'Every move matters.',
  'avatarEmoji': 'av_pawn',
};

Future<LunoOnlineService> visualOnline() async {
  final service = LunoOnlineService.forTesting(
    bootstrap: () async {},
    auth: TestAuth(),
    appCheck: () async => 'local-test-only',
    databaseRead: (path) async {
      if (path.startsWith('friends/')) return {'friend': true};
      if (path.startsWith('publicProfiles/')) {
        return profile('luno_friend', 740);
      }
      if (path.startsWith('friendRequests/')) {
        return {
          'other': {
            'fromUsername': 'new_friend',
            'fromTrophies': 450,
            'fromCountry': 'TR',
          },
        };
      }
      if (path.startsWith('dm/')) return {};
      return {};
    },
    friendRequestStream: Stream.value(const []),
    matchInviteStream: Stream.value(const []),
    directMessageStream:
        (_) => Stream.value([
          {
            'messageId': 'm1',
            'fromUid': 'friend',
            'toUid': 'first',
            'text': 'Ready for a friendly match?',
            'ts': 1000,
            'read': true,
          },
          {
            'messageId': 'm2',
            'fromUid': 'first',
            'toUid': 'friend',
            'text': 'Yes, let us play!',
            'ts': 1001,
            'read': true,
          },
        ]),
    client: MockClient((request) async {
      final body = jsonDecode(request.body) as Map;
      final data =
          request.url.path.endsWith('openDirectMessage')
              ? {'ok': true, 'conversationId': 'first_friend'}
              : request.url.path.endsWith('getBattleDeckV1')
              ? response(owned: CardId.values.map((c) => c.wire).toList())
              : request.url.path.endsWith('getLeaderboard')
              ? {
                'ok': true,
                'mode': body['mode'],
                'results': [
                  for (var i = 0; i < 6; i++)
                    {
                      'uid': 'rank$i',
                      ...profile('luno_player_$i', 1500 - i * 100),
                    },
                ],
              }
              : {
                'ok': true,
                'state': {
                  'season': {
                    'status': 'active',
                    'seasonNumber': 1,
                    'seasonEndAt': 1800000000000 + 86400000 + 3600000,
                    'serverTime': 1800000000000,
                    'score': 450,
                    'nextTrophies': 1000,
                    'progress': .75,
                    'claimableCount': 1,
                    'path': [
                      {
                        'id': 'tier1',
                        'title': 'İlk adım',
                        'state': 'claimable',
                        'canClaim': true,
                        'minTrophies': 0,
                        'reward': {'gold': 100},
                      },
                      {
                        'id': 'tier2',
                        'title': 'İmparator tacı',
                        'state': 'locked',
                        'canClaim': false,
                        'minTrophies': 1000,
                        'reward': {'gems': 20},
                      },
                    ],
                  },
                  'rewards': {
                    'missions': {
                      'daily': [
                        {
                          'id': 'd1',
                          'title': 'Tahtaya çık',
                          'description': 'Bir maç oyna.',
                          'target': 1,
                          'progress': 0,
                          'claimed': false,
                          'reward': {'gold': 100},
                        },
                      ],
                      'weekly': [],
                      'special': [],
                    },
                    'achievements': [
                      {
                        'id': 'first_win',
                        'title': 'İlk Zafer',
                        'description': 'İlk maçını kazan.',
                        'target': 1,
                        'progress': 1,
                        'statKey': 'wins',
                        'claimed': false,
                        'reward': {'gold': 100},
                      },
                      {
                        'id': 'win_10',
                        'title': 'Acemi Savaşçı',
                        'description': '10 maç kazan.',
                        'target': 10,
                        'progress': 12,
                        'statKey': 'wins',
                        'claimed': true,
                        'reward': {'gold': 300},
                      },
                      {
                        'id': 'win_50',
                        'title': 'Tahta Ustası',
                        'description': '50 maç kazan.',
                        'target': 50,
                        'progress': 12,
                        'statKey': 'wins',
                        'claimed': false,
                        'reward': {'gold': 1500},
                      },
                    ],
                    'periods': {},
                  },
                },
              };
      return http.Response(
        jsonEncode(data),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  await service.start();
  return service;
}

Future<void> capture(
  WidgetTester tester,
  String name, {
  Key repaintKey = boundaryKey,
  String outputDirectory = const String.fromEnvironment(
    'LUNO_QA_CAPTURE_DIRECTORY',
    defaultValue: 'qa/rc/screens',
  ),
}) async {
  final renderedAssets = <String>{};
  await tester.runAsync(() async {
    final context = tester.element(find.byKey(repaintKey));
    final providers = <ImageProvider>{
      for (final image in tester.widgetList<Image>(find.byType(Image)))
        image.image,
      for (final box in tester.widgetList<DecoratedBox>(
        find.byType(DecoratedBox),
      ))
        if (box.decoration case final BoxDecoration decoration)
          if (decoration.image != null) decoration.image!.image,
    };
    for (final provider in providers) {
      ImageProvider base = provider;
      while (base is ResizeImage) {
        base = base.imageProvider;
      }
      if (base is AssetImage && base.assetName.startsWith('assets/')) {
        renderedAssets.add(base.assetName);
      } else if (base is ExactAssetImage &&
          base.assetName.startsWith('assets/')) {
        renderedAssets.add(base.assetName);
      }
      debugPrint('RC warm $name $provider');
      await precacheImage(
        provider,
        context,
      ).timeout(const Duration(seconds: 15));
    }
  });
  await tester.pump(const Duration(milliseconds: 400));
  expect(tester.takeException(), isNull, reason: name);
  for (final render in tester.allRenderObjects) {
    render.markNeedsPaint();
  }
  await tester.pump();
  final metadata = {
    'name': name,
    'fixture': 'Local deterministic visual fixture, not live Firebase proof',
    'assets': renderedAssets.toList()..sort(),
    'logicalViewport': {
      'width': tester.view.physicalSize.width / tester.view.devicePixelRatio,
      'height': tester.view.physicalSize.height / tester.view.devicePixelRatio,
    },
    'textScaleAt14':
        MediaQuery.textScalerOf(
          tester.element(find.byKey(repaintKey)),
        ).scale(14) /
        14,
    'text': [
      for (final widget in tester.widgetList<RichText>(find.byType(RichText)))
        widget.text.toPlainText(),
    ],
    'ellipsizedText': [
      for (final element in find.byType(RichText).evaluate())
        if (element.renderObject case final RenderParagraph paragraph)
          if (paragraph.hasSize && paragraph.didExceedMaxLines)
            paragraph.text.toPlainText(),
    ],
  };
  await tester.runAsync(() async {
    final boundary =
        tester.element(find.byKey(repaintKey)).renderObject!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory(outputDirectory)..createSync(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    await File(
      '${directory.path}/$name.json',
    ).writeAsString(jsonEncode(metadata));
    image.dispose();
  });
}

void main() {
  setupPracticeTestAssets();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await GameStore.instance.bindAccount('first');
  });
  setUp(() {
    final store = GameStore.instance;
    store.data =
        PlayerData.initial()
          ..username = 'luno_player'
          ..bio = 'Every move matters.'
          ..country = 'GB'
          ..gold = 12345
          ..gems = 250
          ..trophies = 450
          ..wins = 12
          ..losses = 7
          ..draws = 2
          ..gamesPlayed = 21
          ..passXp = 250
          ..ownedEmojis = {'smile', 'heart', 'think', 'crown'};
    store.loaded = true;
    store.hasCompletedTutorial = true;
    store.hasChosenUsername = true;
    store.practiceStage = null;
  });
  final screens = <String, Widget Function(LunoOnlineService)>{
    'loading': (_) => const Scaffold(body: LunoLoadingArtwork()),
    'username': (online) => UsernameSetupScreen(online: online),
    'home': (_) => const HomeScreen(),
    'play': (_) => const PlayModeScreen(),
    'difficulty': (_) => const DifficultyScreen(),
    'friendly': (_) => const FriendlyOnlineScreen(),
    'online':
        (_) => OnlineHubScreen(
          onlineOverride: true,
          requestOverride: (_, _) async => {'ok': true, 'status': 'waiting'},
        ),
    'shop': (online) => ShopScreen(online: online),
    'pass': (online) => PassScreen(online: online),
    'premium': (online) => LunoPremiumScreen(online: online),
    'profile': (_) => const ProfileScreen(),
    'history': (_) => const MatchHistoryScreen(),
    'achievements': (online) => AchievementsScreen(online: online),
    'edit-profile': (online) => EditProfileScreen(online: online),
    'public-profile':
        (online) =>
            PublicPlayerProfileScreen(targetUid: 'friend', online: online),
    'ranking': (online) => RankingScreen(online: online),
    'season': (online) => SeasonScreen(online: online),
    'missions': (online) => MissionsScreen(online: online),
    'friends': (online) => FriendsScreen(online: online),
    'inbox': (online) => InboxScreen(online: online),
    'dm':
        (online) => DirectMessageScreen(
          targetUid: 'friend',
          targetName: 'luno_friend',
          online: online,
        ),
    'deck':
        (_) => BattleDeckScreen(
          loadOverride:
              () async =>
                  response(owned: CardId.values.map((c) => c.wire).toList()),
        ),
    'collection':
        (_) => CollectionScreen(deckLoadOverride: () async => response()),
    'cards':
        (_) => BattleDeckScreen(
          catalogOnly: true,
          loadOverride: () async => response(),
        ),
    'costumes': (_) => const PieceCostumeScreen(),
    'emojis': (_) => const EmojiCollectionScreen(),
    'arenas': (_) => const ArenasScreen(),
    'levels': (_) => const LevelRewardsScreen(),
    'settings': (_) => const SettingsScreen(),
    'tutorial': (_) => const TutorialScreen(),
    'practice': (_) => const BattlePracticeCampaign(replay: true),
  };
  final viewports = [
    (name: 'phone', size: const Size(390, 844), scale: 1.0),
    if (Platform.environment['RC_CAPTURE_EXTENDED'] == '1') ...[
      (name: 'compact', size: const Size(320, 568), scale: 1.0),
      (name: 'scaled', size: const Size(320, 640), scale: 1.5),
      (name: 'tablet', size: const Size(768, 1024), scale: 1.0),
      (name: 'landscape', size: const Size(844, 390), scale: 1.0),
    ],
  ];
  for (final viewport in viewports) {
    for (final language in ['tr', 'en']) {
      for (final entry in screens.entries) {
        testWidgets('RC rendered ${entry.key} $language ${viewport.name}', (
          tester,
        ) async {
          final online = await visualOnline();
          addTearDown(online.dispose);
          LunoSettings.instance.language =
              language == 'en'
                  ? LunoSettings.languageEnglish
                  : LunoSettings.languageTurkish;
          tester.view.physicalSize = viewport.size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            shell(
              entry.value(online),
              language: language,
              scale: viewport.scale,
              reduced: true,
            ),
          );
          await tester.pump(const Duration(milliseconds: 600));
          if (entry.key == 'inbox') {
            // Visual-only deterministic snapshots; transport is covered separately.
            final dynamic state = tester.state(find.byType(InboxScreen));
            state.setState(() {
              state.error = null;
              state.notificationStream = Stream.value([
                {
                  'notificationId': 'n1',
                  'read': false,
                  'type': 'general',
                  'message': 'Your Luno journey begins here.',
                  'ts': 1800000000000,
                },
              ]);
              state.inboxStream = Stream.value([
                {
                  'uid': 'friend',
                  'username': 'luno_friend',
                  'lastMessage': 'Ready for a friendly match?',
                  'unread': 2,
                  'lastTs': 1800000000000,
                },
              ]);
            });
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 100));
          }
          final suffix = viewport.name == 'phone' ? '' : '-${viewport.name}';
          await capture(tester, '${entry.key}-$language$suffix');
          if (viewport.name == 'phone') {
            final scrolls =
                tester
                    .stateList<ScrollableState>(find.byType(Scrollable))
                    .where(
                      (s) =>
                          s.widget.axisDirection == AxisDirection.down &&
                          s.position.hasContentDimensions &&
                          s.position.maxScrollExtent > 16,
                    )
                    .toList()
                  ..sort(
                    (a, b) => b.position.maxScrollExtent.compareTo(
                      a.position.maxScrollExtent,
                    ),
                  );
            if (scrolls.isNotEmpty) {
              final scroll = scrolls.first;
              for (var attempt = 0; attempt < 12; attempt++) {
                scroll.position.jumpTo(scroll.position.maxScrollExtent);
                await tester.pump(const Duration(milliseconds: 400));
                if (scroll.position.extentAfter < .5 &&
                    !scroll.position.outOfRange) {
                  break;
                }
              }
              expect(
                scroll.position.extentAfter,
                lessThan(.5),
                reason: 'Tail capture must reach the real lazy-list end',
              );
              expect(
                scroll.position.outOfRange,
                false,
                reason: 'A tail capture must not overshoot the lazy-list end',
              );
              await capture(tester, '${entry.key}-$language-tail');
            }
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        });
      }
    }
  }
}
