import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/app.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/difficulty_screen.dart';
import 'package:luno_chess/screens/friendly_online_screen.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/screens/online_hub_screen.dart';
import 'package:luno_chess/screens/parity_extra_screens.dart';
import 'package:luno_chess/screens/pass_screen.dart';
import 'package:luno_chess/screens/play_mode_screen.dart';
import 'package:luno_chess/screens/profile_screen.dart';
import 'package:luno_chess/screens/public_player_profile_screen.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'rc_screen_capture_test.dart' show visualOnline, capture;

void main() {
  setupPracticeTestAssets();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LunoSettings.instance.load();
    await GameStore.instance.bindAccount('first');
  });
  setUp(() {
    GameStore.instance
      ..data =
          (PlayerData.initial()
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
            ..ownedEmojis = {'smile', 'heart', 'think', 'crown'})
      ..loaded = true
      ..hasCompletedTutorial = true
      ..hasChosenUsername = true
      ..practiceStage = null;
  });
  final screens = <String, Widget Function(LunoOnlineService)>{
    'loading': (_) => const Scaffold(body: LunoLoadingArtwork()),
    'username': (online) => UsernameSetupScreen(online: online),
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
    'inbox-populated': (online) => InboxScreen(online: online),
    'inbox-empty': (online) => InboxScreen(online: online),
    'dm':
        (online) => DirectMessageScreen(
          targetUid: 'friend',
          targetName: 'luno_friend',
          online: online,
        ),
    'levels': (_) => const LevelRewardsScreen(),
    'settings': (_) => const SettingsScreen(),
  };
  final outputDirectory =
      Platform.environment['LUNO_V216_GENERAL_PHASE'] == 'before'
          ? 'qa/v216/inventory/general'
          : 'qa/v216/after/general';
  for (final language in ['tr', 'en']) {
    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(430, 932),
      const Size(768, 1024),
    ]) {
      for (final entry in screens.entries) {
        testWidgets(
          'V216 inventory ${entry.key} $language ${size.width.toInt()} text150',
          (tester) async {
            final online = await visualOnline();
            addTearDown(online.dispose);
            LunoSettings.instance.language =
                language == 'en'
                    ? LunoSettings.languageEnglish
                    : LunoSettings.languageTurkish;
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(
              shell(
                entry.value(online),
                language: language,
                scale: 1.5,
                reduced: true,
              ),
            );
            await tester.pump(const Duration(milliseconds: 600));
            if (entry.key == 'friendly') {
              expect(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is LunoArt &&
                      widget.path ==
                          'assets/native_art/friends-welcome-v216.webp',
                ),
                findsOneWidget,
              );
              expect(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is LunoButton &&
                      widget.label ==
                          (language == 'en'
                              ? 'CREATE ROOM'
                              : 'ODA KODU OLUŞTUR'),
                ),
                findsOneWidget,
              );
              expect(
                find.text(
                  language == 'en'
                      ? '5 minutes per player'
                      : 'Oyuncu başına 5 dakika',
                ),
                findsOneWidget,
              );
            }
            if (entry.key == 'inbox-populated' || entry.key == 'inbox-empty') {
              // Render deterministic UI states; transport is tested separately.
              final populated = entry.key == 'inbox-populated';
              final dynamic state = tester.state(find.byType(InboxScreen));
              state.setState(() {
                state.error = null;
                state.notificationStream = Stream.value([
                  if (populated)
                    {
                      'notificationId': 'n1',
                      'read': false,
                      'type': 'general',
                      'message':
                          language == 'en'
                              ? 'Your Luno journey begins here.'
                              : 'Luno yolculuğun burada başlıyor.',
                      'ts': 1800000000000,
                    },
                ]);
                state.inboxStream = Stream.value([
                  if (populated)
                    {
                      'uid': 'friend',
                      'username': 'luno_friend',
                      'lastMessage':
                          language == 'en'
                              ? 'Ready for a friendly match?'
                              : 'Dostluk maçına hazır mısın?',
                      'unread': 2,
                      'lastTs': 1800000000000,
                    },
                ]);
              });
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 100));
              final tabs =
                  tester.allRenderObjects
                      .whereType<RenderParagraph>()
                      .where(
                        (paragraph) => [
                          'BİLDİRİMLER',
                          'MESAJLAR',
                          'NOTIFICATIONS',
                          'MESSAGES',
                        ].contains(paragraph.text.toPlainText()),
                      )
                      .toList();
              expect(tabs.length, greaterThanOrEqualTo(2));
              expect(
                tabs.every((paragraph) => !paragraph.didExceedMaxLines),
                isTrue,
                reason: 'Inbox tab names must remain readable, not ellipsized',
              );
            }
            final name = '${entry.key}-$language-${size.width.toInt()}';
            await capture(tester, name, outputDirectory: outputDirectory);
            final scrolls =
                tester
                    .stateList<ScrollableState>(find.byType(Scrollable))
                    .where(
                      (state) =>
                          state.widget.axisDirection == AxisDirection.down &&
                          state.position.hasContentDimensions &&
                          state.position.maxScrollExtent > 16,
                    )
                    .toList()
                  ..sort(
                    (a, b) => b.position.maxScrollExtent.compareTo(
                      a.position.maxScrollExtent,
                    ),
                  );
            if (size.width == 320 && scrolls.isNotEmpty) {
              final scroll = scrolls.first;
              for (var attempt = 0; attempt < 12; attempt++) {
                scroll.position.jumpTo(scroll.position.maxScrollExtent);
                await tester.pump(const Duration(milliseconds: 400));
                if (scroll.position.extentAfter < .5) break;
              }
              expect(scroll.position.extentAfter, lessThan(.5));
              await capture(
                tester,
                '$name-tail',
                outputDirectory: outputDirectory,
              );
            }
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
            tester.binding.imageCache.clear();
            tester.binding.imageCache.clearLiveImages();
          },
        );
      }
    }
  }
}
