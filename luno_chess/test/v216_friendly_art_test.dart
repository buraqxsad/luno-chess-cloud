import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('V216 friendly art is in the actual Flutter asset bundle', () async {
    final bytes = await rootBundle.load(
      'assets/native_art/friends-welcome-v216.webp',
    );
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 512);
    expect(frame.image.height, 512);
    frame.image.dispose();
    codec.dispose();
  });
  for (final language in ['tr', 'en']) {
    test(
      'V216 friendly room duration is separate from its command: $language',
      () {
        final copy = LunoLocalizations(Locale(language));
        expect(
          copy.friendlyRoomCreate,
          language == 'en' ? 'CREATE ROOM' : 'ODA KODU OLUŞTUR',
        );
        expect(
          copy.friendlyRoomDuration(5),
          language == 'en' ? '5 minutes per player' : 'Oyuncu başına 5 dakika',
        );
        expect(copy.friendlyRoomCreate, isNot(contains('5')));
      },
    );
  }
}
