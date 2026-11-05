import 'package:flutter/foundation.dart';

Map<String, dynamic> validateDeckUpdateResult(
  Map<String, dynamic> result,
  List<String> submitted,
) {
  final state = result['state'];
  final deck = state is Map ? state['deck'] : null;
  if (result['ok'] != true ||
      state is! Map ||
      deck is! List ||
      submitted.length != 6 ||
      submitted.toSet().length != 6 ||
      !listEquals<Object?>(deck, submitted)) {
    throw const FormatException('Unconfirmed deck update');
  }
  return Map<String, dynamic>.from(state);
}
