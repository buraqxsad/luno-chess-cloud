'use strict';
const assert=require('node:assert/strict');
const {newBattle,applyAuthoritative,playerView}=require('/workspace/luno-chess/functions/rules-v1/dist/src/authoritative.js');
const {legalActions}=require('/workspace/luno-chess/functions/rules-v1/dist/src/core.js');
const {CARDS}=require('/workspace/luno-chess/functions/rules-v1/dist/src/model.js');
const {squares}=require('/workspace/luno-chess/functions/rules-v1/dist/src/board.js');
const cards=Object.keys(CARDS);let states=0,moves=0,rejects=0;const cast={};
function rng(seed){let n=seed;return()=>((n=(Math.imul(n,1664525)+1013904223)>>>0)/4294967296);}
function shuffle(a,r){a=[...a];for(let i=a.length-1;i>0;i--){const j=Math.floor(r()*(i+1));[a[i],a[j]]=[a[j],a[i]];}return a;}
function inspect(s,original){states++;const board=squares(s.rules.fen),ids=s.rules.pieceIds;
 assert.equal(board.length,64);assert.equal(ids.length,64);
 assert.equal(new Set(ids.filter(Boolean)).size,ids.filter(Boolean).length);
 for(let i=0;i<64;i++)assert.equal(Boolean(ids[i]),Boolean(board[i]));
 assert.equal(board.filter(p=>p==='K').length,1);assert.equal(board.filter(p=>p==='k').length,1);
 for(const side of ['w','b']){
  const pool=[...s.hidden.hands[side],...s.hidden.decks[side],...s.rules.used[side],...s.rules.discarded[side]].sort();
  assert.deepEqual(pool,[...original[side]].sort(),'unique deck cards must be conserved across all four destinations');
  assert.equal(new Set(pool).size,10);assert.equal(s.hidden.hands[side].length,s.rules.handCounts[side]);assert.equal(s.hidden.decks[side].length,s.rules.deckCounts[side]);
  assert.ok(s.rules.mana[side]>=0&&s.rules.mana[side]<=6);
  const k=s.hidden.knowledge[side];assert.deepEqual(k.knownUpcomingCards,s.hidden.decks[side].slice(0,k.knownUpcomingCards.length));
  if(k.pendingCards.length)assert.deepEqual(k.pendingCards,s.hidden.decks[side].slice(0,k.pendingCards.length));
  for(const observation of k.radarObservations)if(!observation.stale){
   const enemy=side==='w'?'b':'w';
   assert.equal(observation.result==='IN_HAND',s.hidden.hands[enemy].includes(observation.queriedCardId));
  }
  assert.ok(!Object.hasOwn(playerView(s,side),'hidden'));
 }
}
for(let seed=1;seed<=48;seed++){
 const random=rng(938000+seed),white=shuffle(cards,random).slice(0,10),black=shuffle(cards,random).slice(0,10),original={w:white,b:black};
 let s=newBattle(white,black);inspect(s,original);
 for(let step=0;step<180&&s.rules.phase!=='terminal';step++){
  const side=s.rules.fen.split(' ')[1],all=legalActions(playerView(s,side));assert.ok(all.length,'nonterminal cannot be stuck');
  const plays=all.filter(a=>a.type==='play');const pool=plays.length&&random()<.8?plays:all;const a=pool[Math.floor(random()*pool.length)];
  const saved=JSON.stringify(s);assert.throws(()=>applyAuthoritative(s,{type:'move',uci:'a1a1'}));assert.equal(JSON.stringify(s),saved);rejects++;
  s=applyAuthoritative(s,a);assert.equal(JSON.stringify(JSON.parse(saved)),saved);
  if(a.type==='play')cast[a.card]=(cast[a.card]||0)+1;if(a.type==='move')moves++;inspect(s,original);
 }
}
console.log(JSON.stringify({scope:'bounded independently stated conservation/identity/known-prefix/nonstale-radar invariants; TS engine only',seedCount:48,statesInspected:states,chessMoves:moves,atomicIllegalRejections:rejects,cardsCast:cast,passed:true},null,2));
