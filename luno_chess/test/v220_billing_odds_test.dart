import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/chest_odds.dart';
import 'package:luno_chess/widgets/chest_odds_dialog.dart';

import 'v220_billing_odds_fixture.dart';

void main() {
  final fixtures = jsonDecode(v220ChestOddsFixturesJson) as List;
  for (final fixture in fixtures) {
    test('exact backend odds oracle: ${fixture['name']}', () {
      final expected = fixture['expected'] as Map;
      final odds = ChestOdds.fromPlayerState(expected['chestId'] as String, {
        'inventory': fixture['inventory'],
      });
      expect(odds.currency, expected['currency']);
      expect(odds.price, expected['price']);
      expect(odds.goldMin, expected['goldMin']);
      expect(odds.goldMax, expected['goldMax']);
      expect(
        odds.fallbackChance,
        closeTo(expected['fallbackChance'] as num, 1e-12),
      );
      expect(odds.items.length, (expected['items'] as List).length);
      for (var i = 0; i < odds.items.length; i++) {
        final item = odds.items[i], target = expected['items'][i] as Map;
        expect(item.type, target['type']);
        expect(item.id, target['id']);
        expect(item.rarity, target['rarity']);
        final amounts = target['amountOdds'] as Map;
        expect(
          item.amountOdds.keys.map((n) => '$n').toList(),
          amounts.keys.toList(),
        );
        for (final entry in item.amountOdds.entries) {
          expect(entry.value, closeTo(amounts['${entry.key}'] as num, 1e-12));
        }
      }
      final goldTotal = [
        for (var n = odds.goldMin; n <= odds.goldMax; n++)
          odds.goldAmountChance(n),
      ].fold<double>(0, (a, b) => a + b);
      expect(goldTotal, closeTo(1, 1e-12));
      expect(odds.goldAmountChance(odds.goldMin - 1), 0);
    });
  }
  for (final malformed in [
    <String, dynamic>{},
    {'inventory': {}},
    {
      'inventory': {
        ...(v220ChestState('first')['inventory'] as Map),
        'frameShards': {'galaxy': -1},
      },
    },
    {
      'inventory': {
        ...(v220ChestState('first')['inventory'] as Map),
        'ownedEmojis': ['smile', 7],
      },
    },
  ]) {
    test(
      'incomplete or malformed inventory never invents odds: $malformed',
      () {
        expect(
          () => ChestOdds.fromPlayerState('common', malformed),
          throwsFormatException,
        );
      },
    );
  }
  for (final english in [false, true]) {
    testWidgets(
      'pre-debit disclosure fits 320px at 1.5 and can be cancelled: $english',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        bool? result;
        final odds = ChestOdds.fromPlayerState(
          'royal',
          v220ChestState('first'),
        );
        await tester.pumpWidget(
          MaterialApp(
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.5)),
                  child: child!,
                ),
            home: Scaffold(
              body: Builder(
                builder:
                    (context) => TextButton(
                      onPressed: () async {
                        result = await showDialog<bool>(
                          context: context,
                          builder:
                              (_) =>
                                  ChestOddsDialog(odds: odds, english: english),
                        );
                      },
                      child: const Text('show'),
                    ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('show'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('chest-odds-dialog')), findsOneWidget);
        final confirm = find.byKey(const ValueKey('chest-odds-confirm'));
        expect(tester.getRect(confirm).right, lessThanOrEqualTo(320));
        expect(tester.getRect(confirm).bottom, lessThanOrEqualTo(640));
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('chest-odds-cancel')));
        await tester.pumpAndSettle();
        expect(result, false);
      },
    );
  }
}
