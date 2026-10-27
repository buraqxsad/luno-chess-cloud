import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/widgets/resource_amount.dart';

void main() {
  final resources = <String, ResourceAmount>{
    'gold': const ResourceAmount.coin(123456789, iconSize: 24, fontSize: 14),
    'gems': const ResourceAmount.gem(123456789, iconSize: 24, fontSize: 14),
    'mana': const ResourceAmount.mana(10, iconSize: 24, fontSize: 14),
  };
  for (final entry in resources.entries) {
    for (final bounded in [true, false]) {
      testWidgets('${entry.key} fits bounded=$bounded with large text', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child:
                      bounded
                          ? SizedBox(width: 72, child: entry.value)
                          : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [entry.value],
                          ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('${entry.value.value}'), findsOneWidget);
      });
    }
  }
}
