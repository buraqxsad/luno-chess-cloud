// Hızlı motor doğrulaması: `dart run tool/selfcheck.dart`
// Flutter gerektirmez (motor saf Dart). Perft değerlerini bilinenlerle karşılaştırır.
// ignore_for_file: avoid_print
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/perft.dart';

void main() {
  const expected = {1: 20, 2: 400, 3: 8902, 4: 197281};
  var allOk = true;
  final sw = Stopwatch()..start();
  expected.forEach((depth, want) {
    final got = perft(Board.start(), depth);
    final ok = got == want;
    if (!ok) allOk = false;
    print('perft($depth) = $got  ${ok ? "OK" : "HATA (beklenen $want)"}');
  });
  sw.stop();
  print('--- ${allOk ? "TÜM PERFT DOĞRU" : "PERFT HATALI"} (${sw.elapsedMilliseconds}ms) ---');
}
