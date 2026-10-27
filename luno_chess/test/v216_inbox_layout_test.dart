import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;
import 'battle_tutorial_v207_test.dart' show shell;
import 'rc_screen_capture_test.dart' show visualOnline, capture;

void main() {
  setupPracticeTestAssets();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LunoSettings.instance.load();
  });
  for (final language in ['tr', 'en']) {
    testWidgets('V216 narrow inbox preserves whole tab words $language',
        (tester) async {
      final online = await visualOnline();
      addTearDown(online.dispose);
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(shell(InboxScreen(online: online),
        language: language, scale: 1.5, reduced: true));
      await tester.pump(const Duration(milliseconds: 600));
      final dynamic state = tester.state(find.byType(InboxScreen));
      state.setState(() {
        state.error = null;
        state.notificationStream = Stream<List<Map<String, dynamic>>>.value([]);
        state.inboxStream = Stream<List<Map<String, dynamic>>>.value([]);
      });
      await tester.pumpAndSettle();
      final firstTab = find.byKey(const ValueKey('inbox-tab-notifications'));
      final secondTab = find.byKey(const ValueKey('inbox-tab-messages'));
      for (final (tab, label) in language == 'tr'
          ? [(firstTab, 'BİLDİRİMLER'), (secondTab, 'MESAJLAR')]
          : [(firstTab, 'NOTIFICATIONS'), (secondTab, 'MESSAGES')]) {
        final title = find.descendant(of: tab, matching: find.text(label));
        final paragraph = tester.renderObject<RenderParagraph>(title);
        final painter = TextPainter(text: paragraph.text,
          textDirection: paragraph.textDirection, textScaler: paragraph.textScaler)
          ..layout();
        expect(paragraph.size.width + .1, greaterThanOrEqualTo(painter.width),
          reason: label);
        painter.dispose();
        expect(paragraph.didExceedMaxLines, isFalse);
      }
      final first = tester.getRect(firstTab);
      final second = tester.getRect(secondTab);
      expect(first.bottom, lessThan(second.top));
      await tester.tap(secondTab);
      await tester.pumpAndSettle();
      expect(state.tab, 1);
      expect(tester.takeException(), isNull);
      await capture(tester, 'inbox-$language-320-whole-tabs',
        outputDirectory: 'qa/v216/after/inbox-edges');
      await tester.pumpWidget(const SizedBox());
    });
    for (final tab in [0, 1]) {
      testWidgets(
        'V216 empty inbox remains reachable in landscape text180 $language tab$tab',
        (tester) async {
          final online = await visualOnline();
          addTearDown(online.dispose);
          tester.view.physicalSize = const Size(640, 320);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            shell(
              InboxScreen(online: online),
              language: language,
              scale: 1.8,
              reduced: true,
            ),
          );
          await tester.pump(const Duration(milliseconds: 600));
          final dynamic state = tester.state(find.byType(InboxScreen));
          state.setState(() {
            state.error = null;
            state.tab = tab;
            state.notificationStream = Stream<List<Map<String, dynamic>>>.value(
              [],
            );
            state.inboxStream = Stream<List<Map<String, dynamic>>>.value([]);
          });
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull);
          final description =
              language == 'en'
                  ? (tab == 0
                      ? 'Friend and match activity will appear here.'
                    : 'Your conversations with friends will appear here.')
                  : (tab == 0
                      ? 'Arkadaşlık ve maç hareketlerin burada görünecek.'
                      : 'Arkadaşlarınla mesajlaştıkça gelen kutun burada dolacak.');
          expect(find.text(description), findsOneWidget);
          final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
          scroll.position.jumpTo(scroll.position.maxScrollExtent);
          await tester.pump();
          expect(scroll.position.extentAfter, lessThan(.5));
          await capture(
            tester,
            'inbox-$language-tab$tab-landscape-180',
            outputDirectory: 'qa/v216/after/inbox-edges',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        },
      );
    }
  }
}
