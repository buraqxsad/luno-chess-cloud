import 'dart:convert';

String directMessageReadKey(List<Map<String, dynamic>> rows) {
  if (rows.isEmpty) return '';
  return jsonEncode(
    rows.map((row) {
      final id = row['messageId'];
      final rawTime = row['ts'];
      final numeric =
          rawTime is num
              ? rawTime
              : rawTime is String
              ? num.tryParse(rawTime)
              : null;
      final timestamp =
          numeric != null &&
                  numeric.isFinite &&
                  numeric >= 0 &&
                  numeric <= 9007199254740991
              ? numeric.toInt()
              : 0;
      return [id is String ? id : '', timestamp];
    }).toList(),
  );
}
