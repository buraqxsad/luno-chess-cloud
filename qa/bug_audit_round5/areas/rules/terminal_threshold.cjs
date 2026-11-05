const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = '/workspace/luno-chess/functions/rules-v1/dist/src/';
const {newBattle, playerView, applyAuthoritative} = require(path+'authoritative.js');
const {legalActions, legalRuleMoves} = require(path+'core.js');
const {CARDS, clone} = require(path+'model.js');
const {squares} = require(path+'board.js');
const out = __dirname;
const cards = Object.keys(CARDS);
const deck = first => [...new Set([first, ...cards])].slice(0,10);
const fen = half => `3nk2r/pp3ppp/8/1p6/3N4/8/PP2PP1P/R3K2R w KQ - ${half} 1`;
const traces=[];
const coverage={cases:0,states:0,prefixTransitions:0,finalMoves:0,quietThreshold:0,pawnReset:0,captureReset:0,pendingResolutions:0,played:{},enemyEffects:{},mineDebuffConsumedAtTerminal:0,freshMineRetainedAtTerminal:0};
function actions(state){return legalActions(playerView(state,state.rules.fen.split(' ')[1]));}
function apply(state,action){const before=JSON.stringify(state);const result=applyAuthoritative(state,action);assert.equal(JSON.stringify(state),before);return result;}
function normalized(s){const n=clone(s), f=n.rules.fen.split(' ');f[4]='0';n.rules.fen=f.join(' ');return n;}
function run(card,effect){
  const white=deck(card), black=deck(effect==='oldmine'||effect==='freshmine'?'mine':effect==='none'?'radar':effect);
  const trace={id:card+'-'+effect,white,black,lowFen:fen(0),highFen:fen(137),actions:[],finalMoves:[]};
  let low=newBattle(white,black,trace.lowFen), high=newBattle(white,black,trace.highFen);
  const step = a => { low=apply(low,a);high=apply(high,a);trace.actions.push(a);coverage.prefixTransitions+=2;assert.deepEqual(normalized(low),normalized(high)); };
  const enemyAction = round => {
    if(effect==='oldmine'&&round===4)return {type:'play',card:'mine',target:27};
    if(round!==5)return {type:'pass'};
    if(effect==='freshmine')return {type:'play',card:'mine',target:21};
    if(['chain','freeze'].includes(effect))return {type:'play',card:effect,target:27};
    if(effect==='slow')return {type:'play',card:'slow',target:7};
    if(effect==='locked_square')return {type:'play',card:'locked_square',target:21};
    if(effect==='board_seal')return {type:'play',card:'board_seal',target:21};
    return {type:'pass'};
  };
  for(let round=0;round<6;round++){
    if(high.rules.phase==='card')step({type:'pass'});
    step({type:'move',uci:round%2?'f3d4':'d4f3'});
    if(high.rules.phase==='card')step(enemyAction(round));
    step({type:'move',uci:round%2?'c6d8':'d8c6'});
  }
  assert.equal(high.rules.fen.split(' ')[4],'149');
  assert.equal(high.rules.phase,'card');assert.equal(high.rules.mana.w,6);
  const plays=actions(high).filter(a=>a.type==='play'&&a.card===card);
  assert.ok(plays.length,trace.id+' must actually offer the card after legal history');
  const preferred=plays.find(a=>a.target===27)||plays[0];step(preferred);
  coverage.played[card]=(coverage.played[card]||0)+1;
  if(high.rules.phase==='pending'){
    const resolutions=actions(high);assert.ok(resolutions.length);step(resolutions.at(-1));coverage.pendingResolutions++;
  }
  assert.equal(high.rules.phase,'chess');
  const moves=legalRuleMoves(high.rules,'w',high.rules.special);
  // Check every outgoing final move from this newly reached boundary.
  assert.ok(moves.length);
  for(const m of moves){
    const action={type:'move',uci:m.uci},lo=apply(low,action),hi=apply(high,action);
    const mover=squares(high.rules.fen)[m.from],capture=!!squares(high.rules.fen)[m.to]||m.ep;
    trace.finalMoves.push(action);coverage.finalMoves++;coverage.states+=2;
    if(mover.toLowerCase()==='p'||capture){assert.deepEqual(hi,lo);if(capture)coverage.captureReset++;else coverage.pawnReset++;continue;}
    assert.equal(lo.rules.terminal,null,'fixture must not accidentally produce a different terminal cause');
    assert.deepEqual(hi.rules.terminal,{reason:'seventy_five_moves',winner:null,mateByRestriction:false,mateBySpecialMove:false,stalemateByRestriction:false});
    assert.equal(hi.rules.phase,'terminal');assert.deepEqual(actions(hi),[]);
    // Stop before the documented draw/next-turn boundary, preserving every
    // capture/entry/final-position trigger and expiry already evaluated by lo.
    const expected=clone(lo), draw=lo.rules.drawCounts.w-low.rules.drawCounts.w;
    expected.rules.fen=hi.rules.fen;
    expected.rules.phase='terminal';expected.rules.terminal=hi.rules.terminal;
    expected.rules.handCounts.w-=draw;expected.rules.deckCounts.w+=draw;expected.rules.drawCounts.w-=draw;
    expected.rules.ownTurns.b--;expected.rules.mana.b=low.rules.mana.b;
    expected.rules.repetitions=clone(low.rules.repetitions);
    expected.hidden.hands.w=clone(low.hidden.hands.w);expected.hidden.decks.w=clone(low.hidden.decks.w);
    expected.hidden.knowledge.w.knownUpcomingCards=clone(low.hidden.knowledge.w.knownUpcomingCards);
    assert.deepEqual(hi,expected,trace.id+':'+m.uci+' terminal must preserve already-completed triggers/expiry and suppress draw/next turn');
    if(high.rules.pieceEffects.some(e=>e.type==='mine_debuff'&&e.pieceId===high.rules.pieceIds[m.from])&&!hi.rules.pieceEffects.some(e=>e.type==='mine_debuff'&&e.pieceId===high.rules.pieceIds[m.from]))coverage.mineDebuffConsumedAtTerminal++;
    if(high.rules.boardEffects.some(e=>e.type==='mine'&&e.owner==='b'&&e.squares.includes(m.to))&&hi.rules.pieceEffects.some(e=>e.type==='mine_debuff'&&e.pieceId===high.rules.pieceIds[m.from]))coverage.freshMineRetainedAtTerminal++;
    coverage.quietThreshold++;
  }
  traces.push(trace);coverage.cases++;coverage.enemyEffects[effect]=(coverage.enemyEffects[effect]||0)+1;
  fs.writeFileSync(out+'/terminal-threshold-traces.json',JSON.stringify(traces,null,2));
  fs.writeFileSync(out+'/terminal-threshold-coverage.json',JSON.stringify(coverage,null,2));
}
for(const card of cards){
  const effect=card==='break_seal'?'locked_square':'oldmine';
  test(`reachable threshold: ${card} after ${effect}`,()=>run(card,effect));
}
for(const effect of ['freshmine','freeze','chain','slow','locked_square','board_seal'])test(`reachable threshold: radar after ${effect}`,()=>run('radar',effect));
