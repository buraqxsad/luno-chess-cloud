import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/online_match_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';

void main() {
  final cases = <(String?, String?, String, String)>[
    ('W', 'W', 'finished', 'ZAFER'),
    ('B', 'B', 'finished', 'ZAFER'),
    ('W', 'B', 'finished', 'YENİLGİ'),
    ('B', 'W', 'finished', 'YENİLGİ'),
    ('draw', 'W', 'finished', 'BERABERE'),
    (null, 'W', 'finished', 'MAÇ TAMAMLANDI'),
    ('unknown', 'W', 'finished', 'MAÇ TAMAMLANDI'),
    ('W', null, 'finished', 'MAÇ TAMAMLANDI'),
    ('draw', 'W', 'cancelled', 'MAÇ İPTAL'),
  ];
  for (final c in cases) {
    testWidgets('Online result $c and home return', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          theme: LunoTheme.dark,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
          home: const Scaffold(body: Text('Root')),
        ),
      );
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Lobby')),
        ),
      );
      await tester.pumpAndSettle();
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder:
              (_) => OnlineMatchScreen(
                matchId: 'fixture-result',
                initialView: {
                  'status': c.$3,
                  'viewerColor': c.$2,
                  'turn': 'W',
                  'phase': 'card',
                  if (c.$1 != null) 'result': {'winner': c.$1},
                  'board': <Object?>[],
                  'player': {'name': 'Player'},
                  'opponent': {'name': 'Opponent'},
                },
              ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(c.$4), findsOneWidget);
      expect(tester.takeException(), isNull);
      final button = tester.widget<LunoButton>(
        find.byWidgetPredicate((w) => w is LunoButton && w.label == 'ANA MENÜ'),
      );
      button.onPressed!();
      button.onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('Root'), findsOneWidget);
      expect(find.text('Lobby'), findsNothing);
      expect(find.byType(OnlineMatchScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
