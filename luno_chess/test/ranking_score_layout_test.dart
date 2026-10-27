import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';

void main() {
  for (final mode in ['trophies', 'season']) {
    testWidgets('large $mode scores fit narrow ranking rows', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: LunoTheme.dark,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
          home: const RankingScreen(),
        ),
      );
      await tester.pump();
      expect(find.text('KOLEKSİYON'), findsNothing);
      expect(find.textContaining('KOLEKSİYON SIRALAMASI'), findsNothing);
      final dynamic state = tester.state(find.byType(RankingScreen));
      state.setState(() {
        state.mode = mode;
        state.loading = false;
        state.error = null;
        state.rows = <Map<String, dynamic>>[
          {
            'uid': 'fixture',
            'username': 'long_player_name',
            'trophies': 999999999,
            'collectionScore': 999999999,
            'seasonScore': 999999999,
          },
        ];
      });
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
