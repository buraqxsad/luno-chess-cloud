import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {Chess} from 'chess.js';
import {perft,divide,PureChessGame,legalChessMoves,repetitionKey} from '../src/chess.js';

const reference = JSON.parse(readFileSync(resolve(__dirname,'../../../../battle_contract/v1/perft.json'),'utf8')) as {
  positions:{id:string,fen:string,fast:number[],slow:Record<string,number>}[]
};
for (const position of reference.positions) {
  const cases = position.fast.map((expected,i)=>({depth:i+1,expected}));
  if (process.env.LUNO_SLOW_PERFT==='1') {
    cases.push(...Object.entries(position.slow).map(([depth,expected])=>({depth:Number(depth),expected})));
  }
  for (const {depth,expected} of cases) test(`${position.id} depth ${depth}`,()=> {
    const actual=perft(new Chess(position.fen),depth);
    assert.equal(actual,expected,JSON.stringify(actual===expected?{}:divide(position.fen,depth)));
    console.log(JSON.stringify({position:position.id,depth,expected,actual,pass:true}));
  });
}
test('divide sums to perft and invalid depth rejects',()=> {
  const fen=reference.positions[0]!.fen;
  assert.equal(Object.values(divide(fen,3)).reduce((a,b)=>a+b,0),8902);
  assert.throws(()=>perft(new Chess(),-1),RangeError);
  assert.throws(()=>divide(fen,0),RangeError);
});
test('fifty claim is not automatic; seventy-five is',()=> {
  const g=new PureChessGame('7k/8/8/8/8/8/8/KR6 w - - 100 1');
  assert.equal(g.status,'ongoing'); assert.equal(g.canClaimFifty,true);
  assert.equal(g.claimFifty(),true); assert.equal(g.play('b1b2'),false);
  assert.equal(new PureChessGame('7k/8/8/8/8/8/8/KR6 w - - 150 1').status,'seventy_five_moves');
});
test('mate precedes 75 and stalemate is distinct',()=> {
  assert.equal(new PureChessGame('7k/6Q1/5K2/8/8/8/8/8 b - - 150 1').status,'checkmate');
  assert.equal(new PureChessGame('7k/5K2/6Q1/8/8/8/8/8 b - - 0 1').status,'stalemate');
});
test('fivefold automatic, threefold claimable, invalid move atomic',()=> {
  const g=new PureChessGame(); const fen=g.fen;
  assert.equal(g.play('e2e5'),false); assert.equal(g.fen,fen);
  for (let cycle=0;cycle<4;cycle++) {
    for (const m of ['g1f3','g8f6','f3g1','f6g8']) assert.equal(g.play(m),true);
    if (cycle===1) { assert.equal(g.canClaimThreefold,true); assert.equal(g.status,'ongoing'); }
  }
  assert.equal(g.status,'fivefold');
});
test('pinned EP forbidden; irrelevant EP omitted from repetition',()=> {
  const fen='k3r3/8/8/3pP3/8/8/8/4K3 w - d6 0 1';
  assert.equal(legalChessMoves(fen).includes('e5d6'),false);
  assert.equal(repetitionKey(new Chess(fen)),repetitionKey(new Chess(fen.replace('d6','-'))));
});
test('all four capture/noncapture promotions; cannot castle through check',()=> {
  const moves=legalChessMoves('k6r/6P1/8/8/8/8/8/4K3 w - - 0 1');
  for (const to of ['g8','h8']) for (const p of ['q','r','b','n']) assert.ok(moves.includes('g7'+to+p));
  assert.equal(legalChessMoves('k4r2/8/8/8/8/8/8/4K2R w K - 0 1').includes('e1g1'),false);
});
