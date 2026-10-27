import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/online.dart';
import '../helpers/battle_v1_response.dart';

Map<String, dynamic> receiptResponse({bool rated = true}) {
  final response = v1Response();
  response['status'] = 'finished';
  final view = response['view'] as Map;
  final public = view['public'] as Map;
  public['result'] = {'reason': 'resign', 'winner': 'w'};
  public['settlementStatus'] = 'complete';
  public['rated'] = rated;
  (view['private'] as Map)['settlementJson'] = jsonEncode({
    'protocolVersion': battleV1Protocol,
    'matchId': v1MatchId,
    'rated': rated,
    'trophyDelta': rated ? 30 : 0,
    'newTrophies': 300,
  });
  return response;
}

void main() {
  test('settlement is optional for active and pending result projections', () {
    expect(
      BattleV1Snapshot.fromResponse(v1Response(), 'self').settlement,
      isNull,
    );
    final pending = receiptResponse();
    final view = pending['view'] as Map;
    (view['public'] as Map)['settlementStatus'] = 'pending';
    (view['private'] as Map).remove('settlementJson');
    expect(BattleV1Snapshot.fromResponse(pending, 'self').settlement, isNull);
  });
  for (final rated in [false, true]) {
    test('validated own receipt is read-only: rated=$rated', () {
      final snapshot = BattleV1Snapshot.fromResponse(
        receiptResponse(rated: rated),
        'self',
      );
      expect(snapshot.settlement!.trophyDelta, rated ? 30 : 0);
      expect(snapshot.settlement!.newTrophies, 300);
      expect(snapshot.settlement!.rated, rated);
    });
  }
  for (final bad in [
    'match',
    'protocol',
    'rating',
    'negative',
    'decimal',
    'unratedDelta',
    'pending',
    'active',
  ]) {
    test('rejects malformed or premature own receipt: $bad', () {
      final response = receiptResponse(rated: bad != 'unratedDelta');
      final view = response['view'] as Map;
      final public = view['public'] as Map;
      final own = view['private'] as Map;
      final receipt = jsonDecode(own['settlementJson'] as String) as Map;
      switch (bad) {
        case 'match':
          receipt['matchId'] = 'bv1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
        case 'protocol':
          receipt['protocolVersion'] = 'legacy';
        case 'rating':
          receipt['rated'] = false;
        case 'negative':
          receipt['newTrophies'] = -1;
        case 'decimal':
          receipt['trophyDelta'] = 1.5;
        case 'unratedDelta':
          receipt['trophyDelta'] = 30;
        case 'pending':
          public['settlementStatus'] = 'pending';
        case 'active':
          public['result'] = null;
          response['status'] = 'active';
      }
      own['settlementJson'] = jsonEncode(receipt);
      expect(
        () => BattleV1Snapshot.fromResponse(response, 'self'),
        throwsFormatException,
      );
    });
  }
}
