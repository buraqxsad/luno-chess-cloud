import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/models/player_data.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/currency_bar.dart';

void main() {
  for (final width in [160.0, 320.0]) {
    testWidgets('Currency balances fit width $width at large text scale', (
      tester,
    ) async {
      final store = GameStore.instance;
      final original = store.data;
      addTearDown(() => store.data = original);
      store.data =
          PlayerData.initial()
            ..gold = 1234567890
            ..gems = 987654321;
      await tester.pumpWidget(
        MaterialApp(
          theme: LunoTheme.dark,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: const CurrencyBar(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('1234567890'), findsOneWidget);
      expect(find.text('987654321'), findsOneWidget);
    });
  }
}
