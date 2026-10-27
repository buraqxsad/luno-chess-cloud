/// Username rules shared by the native onboarding and local persistence.
/// The server remains authoritative for reserved names and uniqueness.
const usernamePattern = r'^[A-Za-z0-9][A-Za-z0-9_]{2,15}$';

String normalizeUsernameValue(String value) => value.trim().toLowerCase();

bool isUsernameShapeValid(String value) =>
    RegExp(usernamePattern).hasMatch(normalizeUsernameValue(value));

String usernameFromMap(
  Map<String, dynamic>? data, {
  String fallback = 'Oyuncu',
}) {
  for (final key in const ['username', 'name']) {
    final raw = data?[key];
    if (raw is! String) continue;
    final normalized = normalizeUsernameValue(raw);
    if (normalized.isNotEmpty && isUsernameShapeValid(normalized)) {
      return normalized;
    }
  }
  return fallback;
}
