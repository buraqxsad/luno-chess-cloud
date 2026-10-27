import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/data/pass.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/screens/pass_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Pass stale claim rejects already claimed and disposed state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = GameStore.instance;
    final original = store.data;
    addTearDown(() => store.data = original);
    store.data = PlayerData.initial()..passXp = kPassXpPerLevel;
    await tester.pumpWidget(
      MaterialApp(theme: LunoTheme.dark, home: const PassScreen()),
    );
    await tester.pump();
    final claim =
        find.byWidgetPredicate((w) => w is LunoButton && w.label == 'AL').first;
    final callback = tester.widget<LunoButton>(claim).onPressed!;
    store.data.passFreeClaimed.add(1);
    callback();
    await tester.pump();
    expect(
      find.byWidgetPredicate((w) => w is LunoButton && w.loading),
      findsNothing,
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    callback();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
