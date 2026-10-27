import {test} from 'node:test';
import assert from 'node:assert/strict';
import {Chess} from 'chess.js';
import {normalMoves} from '../src/board.js';
import {legalChessMoves,PureChessGame,repetitionKey} from '../src/chess.js';

for(const [side,placement,ep,forbidden] of [
  ['w','4k3/8/8/4P3/8/8/8/4K3','d6','e5d6'],
  ['w','4k3/8/8/3nP3/8/8/8/4K3','d6','e5d6'],
  ['w','4k3/8/8/3PP3/8/8/8/4K3','d6','e5d6'],
  ['w','4k3/8/3N4/3pP3/8/8/8/4K3','d6','e5d6'],
  ['b','4k3/8/8/8/4p3/8/8/4K3','d3','e4d3'],
  ['b','4k3/8/8/8/3Np3/8/8/4K3','d3','e4d3'],
  ['b','4k3/8/8/8/3pp3/8/8/4K3','d3','e4d3'],
  ['b','4k3/8/8/8/3Pp3/3n4/8/4K3','d3','e4d3'],
] as const)test(`invalid EP cannot remove a missing/wrong victim: ${side} ${placement}`,()=>{
  const fen=`${placement} ${side} - ${ep} 0 1`,withoutEp=`${placement} ${side} - - 0 1`;
  assert.equal(normalMoves(fen,side).some(m=>m.uci===forbidden),false);
  assert.deepEqual(legalChessMoves(fen),legalChessMoves(withoutEp));
  assert.equal(repetitionKey(new Chess(fen)),repetitionKey(new Chess(withoutEp)));
  const game=new PureChessGame(fen),before=game.fen;
  assert.equal(game.play(forbidden),false);
  assert.equal(game.fen,before);
});

for(const [fen,forbidden] of [
  ['4k3/8/8/8/8/8/8/4K3 w KQ - 0 1',['e1g1','e1c1']],
  ['4k3/8/8/8/8/8/8/N3K2N w KQ - 0 1',['e1g1','e1c1']],
  ['4k3/8/8/8/8/8/8/3K3R w K - 0 1',['d1f1']],
  ['n3k2n/8/8/8/8/8/8/4K3 b kq - 0 1',['e8g8','e8c8']],
  ['3k3r/8/8/8/8/8/8/4K3 b k - 0 1',['d8f8']],
] as const)test(`castling requires home king and same-side rook: ${fen}`,()=>{
  const side=fen.split(' ')[1] as 'w'|'b';
  assert.equal(normalMoves(fen,side).some(m=>m.castle),false);
  const game=new PureChessGame(fen);
  for(const uci of forbidden){
    const before=game.fen;
    assert.equal(game.play(uci),false);
    assert.equal(game.fen,before);
  }
});

test('valid EP, occupied enemy captures, and both castling sides remain available',()=>{
  for(const [fen,expected,ep] of [
    ['4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1','e5d6',true],
    ['4k3/8/8/8/3Pp3/8/8/4K3 b - d3 0 1','e4d3',true],
    ['4k3/8/3b4/3pP3/8/8/8/4K3 w - d6 0 1','e5d6',false],
  ] as const){
    const move=normalMoves(fen,fen.split(' ')[1] as 'w'|'b').find(m=>m.uci===expected);
    assert.ok(move);
    assert.equal(move.ep,ep);
  }
  const castle='r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1';
  assert.deepEqual(normalMoves(castle,'w').filter(m=>m.castle).map(m=>m.uci).sort(),['e1c1','e1g1']);
  assert.deepEqual(normalMoves(castle,'b').filter(m=>m.castle).map(m=>m.uci).sort(),['e8c8','e8g8']);
});
