/// Classify one-time item identities. The server remains the catalog authority.
(String, String)? permanentPurchaseIdentity(String itemId) {
  final match = RegExp(
    r'^(piece_set|skin|emoji|frame|bio_frame|costume|costume_pack):([a-z0-9_]{1,64})$',
  ).firstMatch(itemId);
  if (match == null) return null;
  final kind = match.group(1)!, id = match.group(2)!;
  if (kind == 'costume_pack' && id != 'all') return null;
  return (kind, id);
}
