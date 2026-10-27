// Kart sistemi fuzz self-play: `dart run tool/cardsim.dart [oyunSayısı]`
// Rastgele kart + rastgele hamle oynar; invariant ihlalinde fırlatır.
// ignore_for_file: avoid_print
import 'dart:math';

import 'package:luno_chess/cards/card_catalog.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/engine/square.dart';
import 'package:luno_chess/match/match_state.dart';

// Test için her iki tarafa da geniş bir kart havuzu verelim (tüm 29 kart kapsansın).
const allKeys = [
  'trap1', 'trap2', 'trap3', 'radar1', 'radar2', 'radar3',
  'resist1', 'resist2', 'resist3', 'shield1', 'shield2', 'shield3',
  'deploy1', 'deploy2', 'deploy3', 'freeze', 'poison_q', 'card_block',
  'medium', 'barbarian', 'glue', 'archer', 'fog', 'angry_n', 'angry_b',
  'plague', 'reinforce', 'ghosts', 'immunity',
];

void check(bool cond, String msg) {
  if (!cond) throw StateError('INVARIANT İHLALİ: $msg');
}

void main(List<String> args) {
  final games = args.isNotEmpty ? int.parse(args[0]) : 400;
  final rng = Random(12345);
  final played = <String, int>{};
  int totalPlies = 0, mates = 0, draws = 0, ongoing = 0;

  for (int g = 0; g < games; g++) {
    final m = MatchState.newGame(white: allKeys, black: allKeys);
    int plies = 0;
    while (!m.over && plies < 260) {
      final col = m.turn;

      // Kart fazı (bazen)
      if (!m.cardUsed && rng.nextDouble() < 0.55) {
        final hand = m.handOf(col)..shuffle(rng);
        for (final key in hand) {
          final c = kCards[key]!;
          if (m.manaOf(col) < c.mana) continue;
          if (c.skipMove && m.inCheck(col)) continue;
          bool ok = false;
          if (c.target.name == 'none') {
            ok = m.playCard(key);
          } else if (key == 'glue') {
            final pair = _findPawnPair(m, col, rng);
            if (pair != null) ok = m.playCard(key, idx: pair[0], idx2: pair[1]);
          } else {
            final t = m.cardTargets(key);
            if (t.isNotEmpty) ok = m.playCard(key, idx: t[rng.nextInt(t.length)]);
          }
          if (ok) {
            played[key] = (played[key] ?? 0) + 1;
            break;
          }
        }
      }

      _invariants(m);
      if (m.over) break;
      if (m.turn != col) {
        plies++;
        continue;
      } // skipMove sırayı geçirdi

      final moves = m.allLegal(m.turn);
      if (moves.isEmpty) {
        m.forcePassTurn();
        plies++;
        continue;
      }
      final mv = moves[rng.nextInt(moves.length)];
      m.makeMove(mv[0], mv[1]);
      _invariants(m);
      plies++;
    }
    totalPlies += plies;
    switch (m.result) {
      case MatchResult.whiteWins:
      case MatchResult.blackWins:
        mates++;
        break;
      case MatchResult.draw:
        draws++;
        break;
      case MatchResult.ongoing:
        ongoing++;
        break;
    }
  }

  print('Oyun: $games | toplam hamle: $totalPlies | mat/pat: $mates | berabere: $draws | süre dolan: $ongoing');
  final missing = allKeys.where((k) => !played.containsKey(k)).toList();
  print('Oynanan kart türü: ${played.length}/29');
  if (missing.isNotEmpty) print('Hiç oynanmayan: $missing');
  print('--- FUZZ TAMAM, INVARIANT İHLALİ YOK ---');
}

void _invariants(MatchState m) {
  check(m.kingIdx(PieceColor.white) >= 0, 'beyaz şah kayboldu');
  check(m.kingIdx(PieceColor.black) >= 0, 'siyah şah kayboldu');
  check(m.manaOf(PieceColor.white) >= 0 && m.manaOf(PieceColor.white) <= 10, 'beyaz mana sınırı');
  check(m.manaOf(PieceColor.black) >= 0 && m.manaOf(PieceColor.black) <= 10, 'siyah mana sınırı');
  for (int i = 0; i < 64; i++) {
    final p = m.board[i];
    if (p == null) continue;
    check(p.frozen >= 0 && p.trapped >= 0 && p.resist >= 0, 'negatif efekt sayacı @$i');
  }
}

List<int>? _findPawnPair(MatchState m, PieceColor col, Random rng) {
  final pawns = <int>[];
  for (int i = 0; i < 64; i++) {
    final p = m.board[i];
    if (p != null &&
        p.color == col &&
        p.type == PieceType.pawn &&
        p.linkTo == null) {
      pawns.add(i);
    }
  }
  pawns.shuffle(rng);
  for (final a in pawns) {
    for (final b in pawns) {
      if (a == b) continue;
      if (Square.rankOf(a) == Square.rankOf(b) &&
          (Square.fileOf(a) - Square.fileOf(b)).abs() == 1) {
        return [a, b];
      }
    }
  }
  return null;
}
