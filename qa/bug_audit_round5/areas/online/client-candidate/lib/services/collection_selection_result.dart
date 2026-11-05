import 'package:flutter/foundation.dart';

Map<String, dynamic> validatePieceSetResult(
  Map<String, dynamic> result,
  String submitted,
) {
  final state = result['state'];
  final inventory = state is Map ? state['inventory'] : null;
  final expected = submitted == 'luno' ? 'std' : submitted;
  if (result['ok'] != true ||
      state is! Map ||
      inventory is! Map ||
      inventory['activePieceSet'] != expected) {
    throw const FormatException('Unconfirmed piece set');
  }
  return Map<String, dynamic>.from(state);
}

Map<String, dynamic> validateEmojiLoadoutResult(
  Map<String, dynamic> result,
  List<String> submitted,
) {
  final state = result['state'];
  final loadout = state is Map ? state['emojiLoadout'] : null;
  if (result['ok'] != true ||
      state is! Map ||
      loadout is! List ||
      submitted.length > 4 ||
      submitted.toSet().length != submitted.length ||
      !listEquals<Object?>(loadout, submitted)) {
    throw const FormatException('Unconfirmed emoji loadout');
  }
  return Map<String, dynamic>.from(state);
}
