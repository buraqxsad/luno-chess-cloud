import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('invalid achievement cannot expose reward claim', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(theme: LunoTheme.dark, home: const AchievementsScreen()),
    );
    await tester.pump();
    final dynamic state = tester.state(find.byType(AchievementsScreen));
    state.setState(() {
      state.loading = false;
      state.error = null;
      state.serverAchievements = <Map<String, dynamic>>[
        {'id': 'broken', 'title': 'Invalid target', 'target': 0, 'progress': 0},
        {'id': '', 'title': 'Missing id', 'target': 1, 'progress': 2},
        {'id': 'valid', 'title': 'Valid reward', 'target': 1, 'progress': 1},
      ];
    });
    await tester.pump();
    expect(find.byTooltip('Ödülü al'), findsOneWidget);
    expect(find.byTooltip('Kilitli'), findsNWidgets(2));
    for (final title in ['Invalid target', 'Missing id']) {
      final row = find.ancestor(
        of: find.text(title),
        matching: find.byType(LunoSurface),
      );
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.byTooltip('Kilitli')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.byType(IconButton)),
        findsNothing,
      );
    }
    final validRow = find.ancestor(
      of: find.text('Valid reward'),
      matching: find.byType(LunoSurface),
    );
    final claim = find.descendant(
      of: validRow,
      matching: find.byType(IconButton),
    );
    expect(claim, findsOneWidget);
    expect(tester.widget<IconButton>(claim).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
