import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/collection_selection_result.dart';

void main() {
  Map<String, dynamic> pieces(Object? id) => {
    'ok': true,
    'state': {
      'inventory': {'activePieceSet': id},
    },
  };
  Map<String, dynamic> emojis(Object? ids) => {
    'ok': true,
    'state': {'emojiLoadout': ids},
  };
  test('piece sets require exact confirmation including standard alias', () {
    expect(validatePieceSetResult(pieces('std'), 'luno'), isNotEmpty);
    expect(validatePieceSetResult(pieces('ottoman'), 'ottoman'), isNotEmpty);
    for (final id in [null, 1, 'roma', 'luno']) {
      expect(
        () => validatePieceSetResult(pieces(id), 'luno'),
        throwsFormatException,
      );
    }
  });
  test('piece sets reject incomplete and unsuccessful envelopes', () {
    for (final result in <Map<String, dynamic>>[
      {},
      {'ok': true},
      {'ok': true, 'state': {}},
      {...pieces('std'), 'ok': false},
    ]) {
      expect(
        () => validatePieceSetResult(result, 'luno'),
        throwsFormatException,
      );
    }
  });
  test('emoji confirmation supports empty and ordered loadouts', () {
    for (final ids in <List<String>>[
      [],
      ['smile'],
      ['smile', 'heart'],
    ]) {
      expect(validateEmojiLoadoutResult(emojis(ids), ids), isNotEmpty);
    }
  });
  test(
    'emoji confirmation rejects stale malformed and duplicate selections',
    () {
      for (final ids in <Object?>[
        null,
        'smile',
        [],
        ['heart', 'smile'],
        [1, 'heart'],
      ]) {
        expect(
          () => validateEmojiLoadoutResult(emojis(ids), ['smile', 'heart']),
          throwsFormatException,
        );
      }
      for (final ids in [
        List.filled(2, 'smile'),
        ['a', 'b', 'c', 'd', 'e'],
      ]) {
        expect(
          () => validateEmojiLoadoutResult(emojis(ids), ids),
          throwsFormatException,
        );
      }
      expect(
        () => validateEmojiLoadoutResult({...emojis([]), 'ok': false}, []),
        throwsFormatException,
      );
    },
  );
}
