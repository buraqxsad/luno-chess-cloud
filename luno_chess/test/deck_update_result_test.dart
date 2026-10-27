import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/data/card_pool.dart';
import 'package:luno_chess/services/deck_update_result.dart';

void main() {
  final deck = kStarterOwned.take(6).toList();
  Map<String, dynamic> response(Object? confirmed) => {
    'ok': true,
    'state': {'deck': confirmed},
  };

  test('accepts only the exact confirmed six-card deck', () {
    expect(validateDeckUpdateResult(response(deck), deck), {'deck': deck});
  });

  test('rejects absent and unsuccessful confirmations', () {
    for (final result in <Map<String, dynamic>>[
      {},
      {'ok': true},
      {'ok': true, 'state': {}},
      {...response(deck), 'ok': false},
    ]) {
      expect(
        () => validateDeckUpdateResult(result, deck),
        throwsFormatException,
      );
    }
  });

  test('rejects truncated, reordered, stale and malformed decks', () {
    for (final confirmed in <Object?>[
      null,
      'deck',
      deck.take(5).toList(),
      deck.reversed.toList(),
      [...deck.take(5), 'unknown'],
      [...deck.take(5), 1],
    ]) {
      expect(
        () => validateDeckUpdateResult(response(confirmed), deck),
        throwsFormatException,
      );
    }
  });

  test('rejects duplicate or incomplete submitted decks', () {
    for (final invalid in [deck.take(5).toList(), List.filled(6, deck.first)]) {
      expect(
        () => validateDeckUpdateResult(response(invalid), invalid),
        throwsFormatException,
      );
    }
  });
}
