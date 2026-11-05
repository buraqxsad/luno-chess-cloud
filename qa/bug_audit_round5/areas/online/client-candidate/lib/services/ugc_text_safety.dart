const bioMaxLength = 160;
const directMessageMaxLength = 500;

final _unsafeUgcText = RegExp(
  r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F\u200B\u200E\u200F\u202A-\u202E\u2060-\u206F\uFEFF<>]',
);

/// The server additionally inspects compatibility forms and is authoritative.
String? normalizeUgcText(
  String value, {
  required int maxLength,
  bool allowEmpty = false,
}) {
  if (value.length > 4096 || _unsafeUgcText.hasMatch(value)) return null;
  final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if ((!allowEmpty && text.isEmpty) || text.length > maxLength) return null;
  return text;
}

String safePublicBio(Object? value) =>
    value is String
        ? normalizeUgcText(value, maxLength: bioMaxLength, allowEmpty: true) ??
            ''
        : '';

String ugcTextError({required bool english, required bool bio}) =>
    english
        ? bio
            ? 'Use up to 160 characters without hidden formatting or markup.'
            : 'Use up to 500 characters without hidden formatting or markup.'
        : bio
        ? 'Gizli biçimlendirme veya işaretleme olmadan en fazla 160 karakter yaz.'
        : 'Gizli biçimlendirme veya işaretleme olmadan en fazla 500 karakter yaz.';
