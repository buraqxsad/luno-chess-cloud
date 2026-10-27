import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/luno_font_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('all bundled font families expose complete notices offline', () async {
    final entries = await LunoFontLicenses.entries().toList();
    expect(entries, hasLength(3));
    for (final entry in entries) {
      final content = entry.paragraphs.map((p) => p.text).join('\n');
      expect(content, contains('SIL OPEN FONT LICENSE Version 1.1'));
      expect(content, contains('PERMISSION & CONDITIONS'));
      expect(content, contains('DISCLAIMER'));
      expect(content, contains('Copyright'));
    }
    for (final path in LunoFontLicenses.sources.values) {
      expect((await rootBundle.load(path)).lengthInBytes, greaterThan(4000));
    }
  });
}
