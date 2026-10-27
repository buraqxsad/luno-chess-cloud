import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/screens/blocked_players_screen.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/screens/public_player_profile_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/services/social_safety_result.dart';
import 'package:luno_chess/widgets/social_safety_actions.dart';
import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart'
    show shell, warm, boundaryKey, noOverflow;
import 'online_request_session_test.dart' show TestAuth, TestUser;

const blockedRow = {
  'uid': 'target',
  'username': 'luno_friend',
  'blocked': true,
};
Future<void> tick(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

Future<void> capture(WidgetTester tester, String name) async {
  await warm(tester);
  // DecorationImage assets are not Image widgets and need their own warm-up.
  await tester.runAsync(() async {
    final context = tester.element(find.byType(Scaffold).first);
    final images = <ImageProvider>{};
    void include(Decoration? decoration) {
      if (decoration is BoxDecoration && decoration.image != null) {
        images.add(decoration.image!.image);
      }
    }

    for (final widget in tester.widgetList<Container>(find.byType(Container))) {
      include(widget.decoration);
    }
    for (final widget in tester.widgetList<AnimatedContainer>(
      find.byType(AnimatedContainer),
    )) {
      include(widget.decoration);
    }
    for (final widget in tester.widgetList<DecoratedBox>(
      find.byType(DecoratedBox),
    )) {
      include(widget.decoration);
    }
    for (final image in images) {
      await precacheImage(image, context);
    }
  });
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary =
        tester.element(find.byKey(boundaryKey)).renderObject!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('qa/v214/visual').create(recursive: true);
    await File(
      'qa/v214/visual/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

LunoOnlineService service({
  TestAuth? auth,
  Future<http.Response> Function(http.Request)? request,
}) => LunoOnlineService.forTesting(
  bootstrap: () async {},
  auth: auth ?? TestAuth(),
  appCheck: () async => 'check',
  databaseRead:
      (_) async => {'username': 'luno_friend', 'bio': 'Hello', 'country': 'TR'},
  directMessageStream:
      (_) => Stream.value([
        {
          'messageId': 'received_1',
          'from': 'target',
          'text': 'Received message',
          'ts': 1,
        },
        {'messageId': 'own_1', 'from': 'first', 'text': 'My message', 'ts': 2},
      ]),
  client: MockClient(
    request ??
        (req) async {
          final path = req.url.path.split('/').last;
          return http.Response(
            jsonEncode(switch (path) {
              'listBlockedUsers' => {
                'ok': true,
                'results': [blockedRow],
              },
              'blockUser' => {
                'ok': true,
                'blocked': true,
                'targetUid': 'target',
              },
              'unblockUser' => {
                'ok': true,
                'blocked': false,
                'targetUid': 'target',
              },
              'reportMessage' || 'reportUser' => {
                'ok': true,
                'reported': true,
                'reportId': 'rp_test',
              },
              'openDirectMessage' => {
                'ok': true,
                'conversationId': 'first_target',
              },
              _ => {'ok': true},
            }),
            200,
          );
        },
  ),
);

void main() {
  setupPracticeTestAssets();
  for (final english in [false, true]) {
    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(430, 932),
      const Size(768, 1024),
    ]) {
      testWidgets('safety layout ${size.width} ${english ? 'en' : 'tr'}', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final online = service();
        addTearDown(online.dispose);
        await online.start();
        final language = english ? 'en' : 'tr';
        await tester.pumpWidget(
          shell(
            BlockedPlayersScreen(online: online),
            language: language,
            scale: 1.5,
          ),
        );
        await tick(tester);
        expect(find.text('luno_friend'), findsOneWidget);
        noOverflow(tester);
        await capture(tester, 'blocked-$language-${size.width.toInt()}-150');
        await tester.pumpWidget(
          shell(
            Scaffold(
              appBar: AppBar(
                actions: [
                  SocialSafetyActions(
                    online: online,
                    targetUid: 'target',
                    messageId: 'message_1',
                  ),
                ],
              ),
            ),
            language: language,
            scale: 1.5,
          ),
        );
        await tester.tap(find.byType(IconButton));
        await tick(tester);
        noOverflow(tester);
        await capture(tester, 'report-$language-${size.width.toInt()}-150');
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
    }
  }
  testWidgets('public profile exposes safety actions on the loaded profile', (
    tester,
  ) async {
    final online = service();
    addTearDown(online.dispose);
    await online.start();
    await tester.pumpWidget(
      shell(PublicPlayerProfileScreen(targetUid: 'target', online: online)),
    );
    await tick(tester);
    expect(find.byTooltip('Oyuncu güvenliği'), findsOneWidget);
    await tester.tap(find.byTooltip('Oyuncu güvenliği'));
    await tick(tester);
    expect(find.text('Oyuncuyu engelle'), findsOneWidget);
    expect(find.text('Oyuncuyu şikâyet et'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets(
    'DM reports only received messages and block clears/disables draft',
    (tester) async {
      final calls = <String>[];
      final online = service(
        request: (req) async {
          final path = req.url.path.split('/').last;
          calls.add(path);
          return http.Response(
            jsonEncode(
              path == 'blockUser'
                  ? {'ok': true, 'blocked': true, 'targetUid': 'target'}
                  : {'ok': true, 'conversationId': 'first_target'},
            ),
            200,
          );
        },
      );
      addTearDown(online.dispose);
      await online.start();
      await tester.pumpWidget(
        shell(
          DirectMessageScreen(
            targetUid: 'target',
            targetName: 'luno_friend',
            online: online,
          ),
        ),
      );
      await tick(tester);
      expect(find.byTooltip('Mesajı şikâyet et'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'unsent draft');
      await tester.tap(find.byTooltip('Oyuncu güvenliği'));
      await tick(tester);
      await tester.tap(find.text('Oyuncuyu engelle'));
      await tick(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Engelle'));
      await tick(tester);
      expect(calls.where((path) => path == 'blockUser'), hasLength(1));
      final input = tester.widget<TextField>(find.byType(TextField));
      expect(input.enabled, isFalse);
      expect(input.controller!.text, isEmpty);
      expect(find.byTooltip('Mesajı şikâyet et'), findsNothing);
      expect(find.text('YENİDEN DENE'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  for (final scenario in [
    'repeat',
    'covered',
    'disposed',
    'account',
    'target',
  ]) {
    testWidgets('safety callback respects $scenario ownership', (tester) async {
      final auth = TestAuth();
      var requests = 0;
      final online = service(
        auth: auth,
        request: (_) async {
          requests++;
          return http.Response('{"ok":true}', 200);
        },
      );
      addTearDown(online.dispose);
      await online.start();
      Widget host(String target) => Scaffold(
        appBar: AppBar(
          actions: [
            SocialSafetyActions(
              key: const ValueKey('safety'),
              online: online,
              targetUid: target,
            ),
          ],
        ),
      );
      await tester.pumpWidget(shell(host('target')));
      final action =
          tester.widget<IconButton>(find.byType(IconButton)).onPressed!;
      if (scenario == 'covered') {
        Navigator.of(tester.element(find.byType(SocialSafetyActions))).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Cover')),
          ),
        );
        await tick(tester);
      }
      if (scenario == 'disposed') {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }
      if (scenario == 'account') auth.currentUser = TestUser('second');
      if (scenario == 'target') await tester.pumpWidget(shell(host('other')));
      action();
      if (scenario == 'repeat') action();
      await tick(tester);
      if (scenario == 'repeat') {
        expect(find.text('Oyuncuyu engelle'), findsOneWidget);
      }
      if (scenario != 'repeat') {
        expect(find.text('Oyuncuyu engelle'), findsNothing);
      }
      expect(requests, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
  for (final success in [true, false]) {
    testWidgets('unblock requires confirmed outcome $success', (tester) async {
      var requests = 0;
      final online = service(
        request: (req) async {
          if (req.url.path.endsWith('/listBlockedUsers')) {
            return http.Response(
              jsonEncode({
                'ok': true,
                'results': [blockedRow],
              }),
              200,
            );
          }
          requests++;
          return http.Response(
            jsonEncode({
              'ok': true,
              'targetUid': 'target',
              'blocked': !success,
            }),
            200,
          );
        },
      );
      addTearDown(online.dispose);
      await online.start();
      await tester.pumpWidget(shell(BlockedPlayersScreen(online: online)));
      await tick(tester);
      final action =
          tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed!;
      action();
      action();
      await tick(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Engeli kaldır'));
      await tick(tester);
      expect(requests, 1);
      expect(find.text('luno_friend'), success ? findsNothing : findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
  for (final success in [true, false]) {
    testWidgets(
      'message report selects a real reason and confirms server result $success',
      (tester) async {
        final bodies = <Map<String, dynamic>>[];
        final online = service(
          request: (req) async {
            bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
            return http.Response(
              jsonEncode(
                success
                    ? {'ok': true, 'reported': true, 'reportId': 'rp_test'}
                    : {'ok': true},
              ),
              200,
            );
          },
        );
        addTearDown(online.dispose);
        await online.start();
        await tester.pumpWidget(
          shell(
            Scaffold(
              appBar: AppBar(
                actions: [
                  SocialSafetyActions(
                    online: online,
                    targetUid: 'target',
                    messageId: 'received_1',
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.tap(find.byTooltip('Mesajı şikâyet et'));
        await tick(tester);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Şikâyeti gönder'),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(
          find.byType(DropdownButtonFormField<SocialReportReason>),
        );
        await tick(tester);
        await tester.tap(find.text('Taciz').last);
        await tick(tester);
        final submit =
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Şikâyeti gönder'),
                )
                .onPressed!;
        submit();
        submit();
        await tick(tester);
        expect(bodies, [
          {
            'targetUid': 'target',
            'messageId': 'received_1',
            'reason': 'harassment',
          },
        ]);
        expect(
          find.text('Şikâyetin incelemeye gönderildi.'),
          success ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('İşlem tamamlanamadı. Lütfen tekrar dene.'),
          success ? findsNothing : findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final scenario in ['covered', 'disposed', 'account', 'target']) {
    testWidgets('in-flight block completion respects $scenario owner', (
      tester,
    ) async {
      final auth = TestAuth();
      final pending = Completer<http.Response>();
      var requests = 0, applied = 0;
      final online = service(
        auth: auth,
        request: (_) {
          requests++;
          return pending.future;
        },
      );
      addTearDown(online.dispose);
      await online.start();
      Widget host(String target) => Scaffold(
        appBar: AppBar(
          actions: [
            SocialSafetyActions(
              key: const ValueKey('safety'),
              online: online,
              targetUid: target,
              onBlocked: (_) => applied++,
            ),
          ],
        ),
      );
      await tester.pumpWidget(shell(host('target')));
      await tester.tap(find.byTooltip('Oyuncu güvenliği'));
      await tick(tester);
      await tester.tap(find.text('Oyuncuyu engelle'));
      await tick(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Engelle'));
      await tick(tester);
      expect(requests, 1);
      if (scenario == 'covered') {
        Navigator.of(tester.element(find.byType(SocialSafetyActions))).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Cover')),
          ),
        );
        await tick(tester);
      }
      if (scenario == 'disposed') {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }
      if (scenario == 'account') auth.currentUser = TestUser('second');
      if (scenario == 'target') await tester.pumpWidget(shell(host('other')));
      pending.complete(
        http.Response('{"ok":true,"blocked":true,"targetUid":"target"}', 200),
      );
      await tick(tester);
      expect(applied, scenario == 'covered' ? 1 : 0);
      expect(find.text('Oyuncu engellendi.'), findsNothing);
      if (scenario == 'covered') expect(find.text('Cover'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('settings opens the blocked list once using the same service', (
    tester,
  ) async {
    final settings = LunoSettings(deviceLocale: const Locale('tr'));
    await tester.runAsync(settings.load);
    final online = service();
    addTearDown(online.dispose);
    await online.start();
    await tester.pumpWidget(
      shell(SettingsScreen(online: online, settings: settings)),
    );
    final tile = find.ancestor(
      of: find.text('Engellenen oyuncular'),
      matching: find.byType(ListTile),
    );
    final action = tester.widget<ListTile>(tile).onTap!;
    action();
    action();
    await tick(tester);
    expect(
      find.byType(BlockedPlayersScreen, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('luno_friend'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    action();
    expect(tester.takeException(), isNull);
  });
  for (final empty in [true, false]) {
    testWidgets('blocked list empty/error/retry state $empty', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var requests = 0;
      final online = service(
        request: (_) async {
          requests++;
          return http.Response(
            jsonEncode(
              empty
                  ? {'ok': true, 'results': []}
                  : requests == 1
                  ? {'ok': true}
                  : {
                    'ok': true,
                    'results': [blockedRow],
                  },
            ),
            200,
          );
        },
      );
      addTearDown(online.dispose);
      await online.start();
      await tester.pumpWidget(
        shell(BlockedPlayersScreen(online: online), scale: 1.5),
      );
      await tick(tester);
      noOverflow(tester);
      await capture(
        tester,
        empty ? 'blocked-empty-tr-320-150' : 'blocked-error-tr-320-150',
      );
      if (!empty) {
        final retry =
            tester.widget<FilledButton>(find.byType(FilledButton)).onPressed!;
        retry();
        retry();
        await tick(tester);
        expect(find.text('luno_friend'), findsOneWidget);
        expect(requests, 2);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
