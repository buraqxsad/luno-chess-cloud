/// Tahta indeksleme yardımcıları.
///
/// idx = rank * 8 + file
///   file 0=a .. 7=h
///   rank 0 = beyazın ilk sırası (cebirsel "1") .. rank 7 = siyahın ilk sırası ("8")
/// Beyaz "yukarı" (artan rank) ilerler, siyah "aşağı" (azalan rank).
class Square {
  static const int count = 64;

  static int of(int file, int rank) => rank * 8 + file;
  static int fileOf(int idx) => idx & 7; // idx % 8
  static int rankOf(int idx) => idx >> 3; // idx ~/ 8

  static bool onBoard(int file, int rank) =>
      file >= 0 && file < 8 && rank >= 0 && rank < 8;

  static const List<String> _fileNames = [
    'a',
    'b',
    'c',
    'd',
    'e',
    'f',
    'g',
    'h',
  ];

  /// "e4" gibi cebirsel gösterim.
  static String algebraic(int idx) =>
      '${_fileNames[fileOf(idx)]}${rankOf(idx) + 1}';
}
