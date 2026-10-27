// AI-vs-AI entegrasyon kontrolü: `dart run tool/aisim.dart [oyun]`
// MatchAi (kart + hamle) iki tarafı da oynar; çökme/invariant kontrolü.
// ignore_for_file: avoid_print
import 'dart:math';

import 'package:luno_chess/engine/ai.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/match/match_ai.dart';
import 'package:luno_chess/match/match_state.dart';

void main(List<String> args) {
  final games = args.isNotEmpty ? int.parse(args[0]) : 30;
  final ai = MatchAi(Random(7));
  final level = aiLevels[2]; // Şövalye (depth 3)
  int decisive = 0, draw = 0, cap = 0, totalPlies = 0;

  for (int g = 0; g < games; g++) {
    final m = MatchState.newGame();
    int plies = 0;
    while (!m.over && plies < 200) {
      final col = m.turn;
      ai.maybeCard(m, level);
      if (m.over) break;
      if (m.turn != col) {
        plies++;
        continue;
      }
      final mv = ai.chooseMove(m, level);
      if (mv == null) {
        m.forcePassTurn();
        plies++;
        continue;
      }
      m.makeMove(mv[0], mv[1]);
      if (m.kingIdx(PieceColor.white) < 0 || m.kingIdx(PieceColor.black) < 0) {
        throw StateError('Şah kayboldu! oyun $g hamle $plies');
      }
      plies++;
    }
    totalPlies += plies;
    if (m.result == MatchResult.draw) {
      draw++;
    } else if (m.over) {
      decisive++;
    } else {
      cap++;
    }
  }
  print('AI-vs-AI $games oyun | hamle: $totalPlies | kazanan: $decisive | berabere: $draw | süre dolan: $cap');
  print('--- AI ENTEGRASYONU SORUNSUZ ---');
}
