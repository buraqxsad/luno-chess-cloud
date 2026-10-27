import 'ugc_text_safety.dart';

Map<String, dynamic> validateProfileUpdateResult(
  Map<String, dynamic> result,
  Map<String, String> submitted,
) {
  final state = result['state'];
  final profile = state is Map ? state['profile'] : null;
  if (result['ok'] != true || state is! Map || profile is! Map) {
    throw const FormatException('Unconfirmed profile update');
  }
  for (final entry in submitted.entries) {
    final expected =
        entry.key == 'bio'
            ? normalizeUgcText(
              entry.value,
              maxLength: bioMaxLength,
              allowEmpty: true,
            )
            : entry.value;
    if (expected == null || profile[entry.key] != expected) {
      throw const FormatException('Profile update does not match submission');
    }
  }
  return Map<String, dynamic>.from(state);
}
