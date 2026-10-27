import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../tool/battle_fixture_support.dart';

void main() {
  final fixtures =
      (jsonDecode(File('../battle_contract/v1/rules.json').readAsStringSync())
              as Map)['fixtures']
          as List;
  for (final value in fixtures) {
    final f = value as Map;
    test('${f['fixtureId']} - ${f['intent']}', () {
      runFixture(f);
    });
  }
}
