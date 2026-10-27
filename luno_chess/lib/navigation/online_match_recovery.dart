import 'package:flutter/material.dart';
import '../screens/battle_v1_screen.dart';
import '../battle_v1/online.dart';
import 'luno_route.dart';

/// Only open a server match belonging to the still-authenticated player.
bool openRecoveredOnlineMatch(
  BuildContext context,
  Map<String, dynamic> response, {
  required String requestedUid,
  required String? currentUid,
}) {
  if (!context.mounted ||
      ModalRoute.of(context)?.isCurrent != true ||
      requestedUid.isEmpty ||
      currentUid != requestedUid ||
      response['ok'] != true) {
    return false;
  }
  final id = response['matchId'];
  final raw = response['view'];
  if (id is! String ||
      !RegExp(r'^bv1_[a-f0-9]{32}$').hasMatch(id) ||
      raw is! Map ||
      raw.keys.any((key) => key is! String)) {
    return false;
  }
  final view = Map<String, dynamic>.from(raw);
  try {
    BattleV1Snapshot.fromResponse(response, requestedUid);
  } catch (_) {
    return false;
  }
  // Keep Home underneath so leaving a restored match can actually return home.
  Navigator.of(
    context,
  ).push(lunoRoute(BattleV1Screen(matchId: id, initialView: view)));
  return true;
}
