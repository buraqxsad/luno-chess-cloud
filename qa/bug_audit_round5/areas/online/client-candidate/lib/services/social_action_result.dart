void validateFriendResponse(
  Map<String, dynamic> result, {
  required bool accept,
}) {
  if (result['ok'] != true || result['accepted'] != accept) {
    throw const FormatException('Unconfirmed friend response');
  }
}

void validateFriendRemoval(Map<String, dynamic> result) {
  if (result['ok'] != true || result['removed'] != true) {
    throw const FormatException('Unconfirmed friend removal');
  }
}

void validateMatchInviteResponse(
  Map<String, dynamic> result, {
  required bool accept,
}) {
  if (result['ok'] == false || result['accepted'] != accept) {
    throw const FormatException('Unconfirmed invitation response');
  }
  if (!accept) return;
  final id = result['matchId'];
  final view = result['view'];
  if (id is! String || id.trim().isEmpty || view is! Map || view.isEmpty) {
    throw const FormatException('Missing accepted match');
  }
  if (view['matchId'] != null && view['matchId'] != id) {
    throw const FormatException('Mismatched accepted match');
  }
}

String friendRequestStatus(Map<String, dynamic> result) {
  final status = result['status'];
  if (result['ok'] == true &&
      status is String &&
      const {'sent', 'pending', 'accepted', 'friends'}.contains(status)) {
    return status;
  }
  throw const FormatException('Unconfirmed friend request');
}

String matchInviteStatus(Map<String, dynamic> result) {
  final id = result['inviteId'];
  if (result['ok'] == false || id is! String || id.trim().isEmpty) {
    throw const FormatException('Unconfirmed match invitation');
  }
  if (result['sent'] == true && result['status'] == null) return 'sent';
  if (result['sent'] == false && result['status'] == 'pending') {
    return 'pending';
  }
  throw const FormatException('Invalid match invitation outcome');
}
