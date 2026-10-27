import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/battle_deck_screen.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/services/ugc_text_safety.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'helpers/v216_1_social_before.dart';
import 'helpers/v216_1_social_deck_before.dart';
import 'online_request_session_test.dart' show TestAuth, TestUser;
import 'rc_screen_capture_test.dart' show capture;

Future<LunoOnlineService> socialOnline({
  TestAuth? auth,
  List<String>? calls,
}) async {
  final online = LunoOnlineService.forTesting(
    bootstrap: () async {},
    auth: auth ?? TestAuth(),
    appCheck: () async => 'local-test-only',
    databaseRead: (path) async {
      if (path.startsWith('friends/')) return {'friend': true};
      if (path.startsWith('publicProfiles/')) {
        return {
          'username': 'long_player_name',
          'trophies': 999999999,
          'avatarEmoji': 'av_knight',
        };
      }
      return {};
    },
    friendRequestStream: Stream.value(const []),
    matchInviteStream: Stream.value(const []),
    directMessageStream:
        (_) => Stream.value([
          {
            'messageId': 'received_1',
            'from': 'friend',
            'text': 'Ready for a friendly match? Yeni bir maca hazir misin?',
            'ts': 1,
          },
          {
            'messageId': 'own_1',
            'from': 'first',
            'text': 'Yes, let us play! Birlikte oynayalim.',
            'ts': 2,
          },
        ]),
    client: MockClient((request) async {
      final path = request.url.path.split('/').last;
      calls?.add(path);
      return http.Response(
        jsonEncode({
          'ok': true,
          if (path == 'openDirectMessage') 'conversationId': 'first_friend',
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  await online.start();
  return online;
}

void wholeLabel(WidgetTester tester, Finder parent, String label) {
  final finder = find.descendant(of: parent, matching: find.text(label));
  expect(finder, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
  )..layout();
  expect(
    paragraph.size.width + .1,
    greaterThanOrEqualTo(painter.width),
    reason: 'Whole label must fit: $label',
  );
  expect(paragraph.didExceedMaxLines, isFalse);
  painter.dispose();
}

Finder iconButtonWithTooltip(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == tooltip,
);

void main() {
  setupPracticeTestAssets();
  final phase = Platform.environment['LUNO_V216_1_SOCIAL_PHASE'] ?? 'after';
  if (!['before', 'after'].contains(phase)) {
    throw ArgumentError.value(phase, 'LUNO_V216_1_SOCIAL_PHASE');
  }
  final after = phase != 'before';
  final output = 'qa/v216_1/$phase/social';
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LunoSettings.instance.load();
  });

  for (final language in ['tr', 'en']) {
    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(768, 1024),
    ]) {
      for (final scale in [1.5, 2.0]) {
        for (final screen in [
          'profile',
          'friends',
          'inbox',
          'dm',
          'card-info',
        ]) {
          testWidgets('V216.1 social $screen $language ${size.width.toInt()} scale$scale', (
            tester,
          ) async {
            final online = await socialOnline();
            final store =
                GameStore.createForTesting()
                  ..accountUid = 'first'
                  ..loaded = true
                  ..data =
                      (PlayerData.initial()
                        ..username = 'luno_player'
                        ..country = 'AE'
                        ..bio = 'Every move matters.');
            addTearDown(online.dispose);
            addTearDown(store.dispose);
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            LunoSettings.instance.language = language;
            final page = switch (screen) {
              'profile' =>
                after
                    ? EditProfileScreen(online: online, playerStore: store)
                    : V216BeforeEditProfileScreen(
                      online: online,
                      playerStore: store,
                    ),
              'friends' =>
                after
                    ? FriendsScreen(online: online)
                    : V216BeforeFriendsScreen(online: online),
              'inbox' =>
                after
                    ? InboxScreen(online: online)
                    : V216BeforeInboxScreen(online: online),
              'dm' =>
                after
                    ? DirectMessageScreen(
                      online: online,
                      targetUid: 'friend',
                      targetName: 'long_player_name',
                    )
                    : V216BeforeDirectMessageScreen(
                      online: online,
                      targetUid: 'friend',
                      targetName: 'long_player_name',
                    ),
              _ => Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child:
                      after
                          ? BattleSelectedDeckGrid(
                            cards: CardId.values.take(10).toList(),
                          )
                          : V216BeforeBattleSelectedDeckGrid(
                            cards: CardId.values.take(10).toList(),
                          ),
                ),
              ),
            };
            await tester.pumpWidget(
              shell(page, language: language, scale: scale, reduced: true),
            );
            await tester.pump(const Duration(milliseconds: 600));
            await tester.pumpAndSettle();
            final name =
                '$screen-$language-${size.width.toInt()}x${size.height.toInt()}-$scale';
            Future<void> record(String name) async {
              await capture(tester, name, outputDirectory: output);
              await tester.runAsync(() async {
                final file = File('$output/$name.json');
                final metadata =
                    jsonDecode(await file.readAsString())
                        as Map<String, dynamic>;
                metadata['sourceProvenance'] = {
                  'phase': phase,
                  'kind':
                      after
                          ? 'current production owned classes'
                          : 'frozen pre-social-edit owned classes',
                  'sharedDependencies':
                      'Current checkout theme, assets, services and other shared widgets',
                  if (!after) ...{
                    'socialSnapshot':
                        'qa/v216_1/social-before/source/native_hubs_screen.dart.txt',
                    'socialSnapshotSha256':
                        'a860b4309e037e1281ac199e13ac1b72bcd5b42ae704c12c97064594a652fcad',
                    'deckSnapshot':
                        'qa/v216_1/social-before/source/battle_deck_screen.dart.txt',
                    'deckSnapshotSha256':
                        'f57dc582c8449eb95bb9248b6e41ad39e89f7a0bf611d96fc54238f8696f2c99',
                    'adaptations': 'Class identifiers and import paths only',
                    'notHistoricalV216PngReproduction': true,
                  },
                };
                await file.writeAsString(jsonEncode(metadata));
              });
            }

            if (screen == 'friends') {
              final labels =
                  language == 'en'
                      ? ['FRIENDS', 'REQUESTS', 'LEADERBOARD']
                      : ['ARKADAŞLAR', 'İSTEKLER', 'SIRALAMA'];
              for (var tab = 0; tab < 3; tab++) {
                final tabFinder =
                    after
                        ? find.byKey(ValueKey('friends-visual-tab-$tab'))
                        : find.text(labels[tab]).last;
                await tester.ensureVisible(tabFinder);
                if (after) {
                  wholeLabel(tester, tabFinder, labels[tab]);
                  expect(tabFinder.hitTestable(), findsOneWidget);
                  expect(
                    tester.getSize(tabFinder).height,
                    greaterThanOrEqualTo(48),
                  );
                }
                await tester.tap(tabFinder);
                await tester.pumpAndSettle();
                final dynamic state = tester.state(
                  find.byType(page.runtimeType),
                );
                expect(state.tab, tab);
                if (tab == 1) {
                  state.setState(
                    () =>
                        state.requestRows = <Map<String, dynamic>>[
                          {
                            'fromUid': 'requester',
                            'fromUsername': 'long_player_name',
                          },
                        ],
                  );
                  await tester.pump();
                }
                await record('$name-tab$tab');
              }
            } else if (screen == 'inbox') {
              final dynamic state = tester.state(find.byType(page.runtimeType));
              state.setState(() {
                state.error = null;
                state.notificationStream =
                    Stream<List<Map<String, dynamic>>>.value([]);
                state.inboxStream = Stream<List<Map<String, dynamic>>>.value(
                  [],
                );
              });
              await tester.pumpAndSettle();
              for (final tab in [0, 1]) {
                final finder = find.byKey(
                  ValueKey(
                    'inbox-tab-${tab == 0 ? 'notifications' : 'messages'}',
                  ),
                );
                await tester.tap(finder);
                await tester.pumpAndSettle();
                if (after) {
                  expect(find.byType(LunoBackdrop), findsNothing);
                  wholeLabel(
                    tester,
                    finder,
                    language == 'en'
                        ? (tab == 0 ? 'NOTIFICATIONS' : 'MESSAGES')
                        : (tab == 0 ? 'BİLDİRİMLER' : 'MESAJLAR'),
                  );
                }
                await record('$name-empty-tab$tab');
              }
              state.setState(() {
                state.tab = 0;
                state.notificationStream = Stream<
                  List<Map<String, dynamic>>
                >.value([
                  {
                    'notificationId': 'n1',
                    'type': 'general',
                    'read': false,
                    'message':
                        'A new invitation is waiting. Yeni bir davetin var.',
                    'ts': 1,
                  },
                ]);
              });
              await tester.pumpAndSettle();
              await record('$name-populated');
            } else {
              if (screen == 'profile' && after) {
                final dropdown = find.descendant(
                  of: find.byKey(const ValueKey('edit-profile-country')),
                  matching: find.byType(DropdownButton<String>),
                );
                expect(dropdown, findsOneWidget);
                final countryText = find.descendant(
                  of: dropdown,
                  matching: find.text('United Arab Emirates'),
                );
                expect(countryText, findsOneWidget);
                final paragraph = tester.renderObject<RenderParagraph>(
                  countryText,
                );
                expect(paragraph.didExceedMaxLines, isFalse);
                final visible = tester.getRect(dropdown);
                final boxes = paragraph.getBoxesForSelection(
                  const TextSelection(
                    baseOffset: 0,
                    extentOffset: 'United Arab Emirates'.length,
                  ),
                );
                for (final box in boxes) {
                  final top = paragraph.localToGlobal(
                    Offset(box.left, box.top),
                  );
                  final bottom = paragraph.localToGlobal(
                    Offset(box.right, box.bottom),
                  );
                  expect(top.dy, greaterThanOrEqualTo(visible.top - .5));
                  expect(
                    bottom.dy,
                    lessThanOrEqualTo(visible.bottom + .5),
                    reason: 'Selected country is vertically clipped',
                  );
                }
              }
              await record(name);
              if (screen == 'profile') {
                final saveLabel = find.text(
                  language == 'en' ? 'SAVE' : 'KAYDET',
                );
                await tester.scrollUntilVisible(
                  saveLabel,
                  240,
                  scrollable: find.byType(Scrollable).first,
                  maxScrolls: 50,
                );
                await tester.pumpAndSettle();
                final save = find.ancestor(
                  of: saveLabel,
                  matching: find.byWidgetPredicate(
                    (widget) => widget is ButtonStyleButton,
                  ),
                );
                expect(save.hitTestable(), findsOneWidget);
                await record('$name-tail');
                if (after) {
                  final lightning = find.byKey(
                    const ValueKey('profile-avatar-label-av_lightning'),
                  );
                  wholeLabel(
                    tester,
                    find
                        .ancestor(of: lightning, matching: find.byType(Column))
                        .first,
                    language == 'en' ? 'Lightning' : 'Yıldırım',
                  );
                }
              }
              if (screen == 'dm') {
                final input = find.byType(TextField);
                await tester.enterText(
                  input,
                  'Draft stays here. Taslak korunur.',
                );
                tester.view.viewInsets = const FakeViewPadding(bottom: 220);
                addTearDown(tester.view.resetViewInsets);
                await tester.pumpAndSettle();
                final send = iconButtonWithTooltip(
                  language == 'en' ? 'Send' : 'Gönder',
                );
                expect(send.hitTestable(), findsOneWidget);
                await record('$name-keyboard');
                tester.view.resetViewInsets();
                final dynamic state = tester.state(
                  find.byType(page.runtimeType),
                );
                state.setState(() {
                  state.messagesStream =
                      Stream<List<Map<String, dynamic>>>.value([]);
                });
                await tester.pumpAndSettle();
                expect(
                  tester.widget<TextField>(input).controller!.text,
                  'Draft stays here. Taslak korunur.',
                );
                await record('$name-empty-draft');
              }
              if (screen == 'card-info' && after) {
                final info =
                    find
                        .widgetWithIcon(IconButton, Icons.info_outline_rounded)
                        .first;
                final button = tester.widget<IconButton>(info);
                final foreground = button.style!.foregroundColor!.resolve({})!;
                final background = button.style!.backgroundColor!.resolve({})!;
                expect(background.a, 1);
                expect(
                  (foreground.computeLuminance() + .05) /
                      (background.computeLuminance() + .05),
                  greaterThanOrEqualTo(7),
                );
                expect(
                  tester.getSize(info).shortestSide,
                  greaterThanOrEqualTo(48),
                );
                await tester.tap(info);
                await tester.pumpAndSettle();
                expect(find.byType(BottomSheet), findsOneWidget);
                await record('$name-sheet');
              }
            }
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
          });
        }
      }
    }
  }

  if (!after) return;
  for (final language in ['tr', 'en']) {
    testWidgets('V216.1 profile draft, validation and save lock $language', (
      tester,
    ) async {
      final calls = <String>[];
      final online = await socialOnline(calls: calls);
      final store =
          GameStore.createForTesting()
            ..accountUid = 'first'
            ..loaded = true;
      addTearDown(online.dispose);
      addTearDown(store.dispose);
      final original = store.data.bio;
      await tester.pumpWidget(
        shell(
          EditProfileScreen(online: online, playerStore: store),
          language: language,
          scale: 2,
          reduced: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'a\u202Eb');
      await tester.tap(
        iconButtonWithTooltip(language == 'en' ? 'Save' : 'Kaydet'),
      );
      await tester.pumpAndSettle();
      expect(calls.where((call) => call == 'updateProfile'), isEmpty);
      expect(store.data.bio, original);
      expect(
        find.text(ugcTextError(english: language == 'en', bio: true)),
        findsOneWidget,
      );
      final dynamic state = tester.state(find.byType(EditProfileScreen));
      state.setState(() => state.saving = true);
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              iconButtonWithTooltip(language == 'en' ? 'Save' : 'Kaydet'),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'V216.1 DM unsafe input and stale account cannot send $language',
      (tester) async {
        final calls = <String>[];
        final auth = TestAuth();
        final online = await socialOnline(auth: auth, calls: calls);
        addTearDown(online.dispose);
        await tester.pumpWidget(
          shell(
            DirectMessageScreen(
              online: online,
              targetUid: 'friend',
              targetName: 'Friend',
            ),
            language: language,
            scale: 2,
            reduced: true,
          ),
        );
        await tester.pumpAndSettle();
        final input = find.byType(TextField);
        final send = iconButtonWithTooltip(
          language == 'en' ? 'Send' : 'Gönder',
        );
        await tester.enterText(input, '   ');
        await tester.pump();
        expect(tester.widget<IconButton>(send).onPressed, isNull);
        await tester.enterText(input, 'a\u202Eb');
        await tester.pump();
        await tester.tap(send);
        await tester.pumpAndSettle();
        expect(calls.where((call) => call == 'sendDirectMessage'), isEmpty);
        expect(tester.widget<TextField>(input).controller!.text, 'a\u202Eb');
        await tester.enterText(input, 'Keep this draft');
        await tester.pump();
        final staleSend = tester.widget<IconButton>(send).onPressed!;
        auth.currentUser = TestUser('second');
        staleSend();
        await tester.pump();
        expect(calls.where((call) => call == 'sendDirectMessage'), isEmpty);
        expect(
          tester.widget<TextField>(input).controller!.text,
          'Keep this draft',
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
