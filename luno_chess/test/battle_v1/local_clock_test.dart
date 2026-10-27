import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/local_clock.dart';
import 'package:luno_chess/engine/piece.dart';
void main(){
 test('card/pending consumes time; only chess turn transfer earns increment',(){var at=0;final c=BattleV1LocalClock(now:()=>at);at=1000;c.advance(PieceColor.white,chessMove:false);expect(c.remaining(PieceColor.white),299000);at=2000;c.advance(PieceColor.black,chessMove:true);expect(c.remaining(PieceColor.white),300000);expect(c.remaining(PieceColor.black),300000);});
 test('timeout cannot be revived by a late move or another increment',(){var at=0;final c=BattleV1LocalClock(now:()=>at,minutes:1);at=60001;expect(c.expired,true);c.advance(PieceColor.black,chessMove:true);expect(c.remaining(PieceColor.white),0);expect(c.ended,true);at=70000;c.advance(PieceColor.black,chessMove:true);expect(c.remaining(PieceColor.white),0);});
 test('terminal clock freezes and selected local duration is preserved',(){var at=0;final c=BattleV1LocalClock(now:()=>at,minutes:3);at=1000;c.advance(PieceColor.black,chessMove:true,terminal:true);final saved=c.remaining(PieceColor.black);at=90000;expect(c.remaining(PieceColor.black),saved);expect(c.remaining(PieceColor.white),181000);});
 test('monotonic source clamps backwards elapsed time',(){var at=1000;final c=BattleV1LocalClock(now:()=>at);at=0;expect(c.remaining(PieceColor.white),300000);});
}
