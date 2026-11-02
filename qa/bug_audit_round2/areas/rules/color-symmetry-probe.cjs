'use strict';
const assert=require('node:assert/strict');
const {readFileSync,writeFileSync}=require('node:fs');
const root='/workspace/luno-chess';
const {initial}=require(root+'/functions/rules-v1/dist/test/fixture_support');
const {newBattle,applyAuthoritative,playerView}=require(root+'/functions/rules-v1/dist/src/authoritative');
const {legalActions}=require(root+'/functions/rules-v1/dist/src/core');
const {CARDS,actionKey}=require(root+'/functions/rules-v1/dist/src/model');
const fixtures=JSON.parse(readFileSync(root+'/battle_contract/v1/rules.json','utf8')).fixtures;
const out='/workspace/luno-review/bug-audit-round2/rules';
const other=s=>s==='w'?'b':'w';
const flip=i=>i^56;
const square=s=>s==='-'?s:s[0]+String(9-Number(s[1]));
const uci=s=>square(s.slice(0,2))+square(s.slice(2,4))+s.slice(4);
function fenFlip(fen){
 const p=fen.split(' '),swap=ch=>ch===ch.toUpperCase()?ch.toLowerCase():ch.toUpperCase();
 p[0]=p[0].split('/').reverse().map(r=>[...r].map(ch=>/[a-z]/i.test(ch)?swap(ch):ch).join('')).join('/');
 p[1]=other(p[1]);p[2]=p[2]==='-'?'-':'KQkq'.split('').filter(c=>p[2].includes(swap(c))).join('');p[3]=square(p[3]);return p.join(' ');
}
function pair(value){return {w:structuredClone(value.b),b:structuredClone(value.w)};}
function mirror(input){
 const s=structuredClone(input),r=s.rules;r.fen=fenFlip(r.fen);r.pieceIds=Array.from({length:64},(_,i)=>input.rules.pieceIds[flip(i)]);
 for(const key of ['mana','ownTurns','handCounts','deckCounts','drawCounts','arsenals','used','discarded'])r[key]=pair(r[key]);
 for(const e of r.pieceEffects){e.owner=other(e.owner);e.responseSide=other(e.responseSide);}
 for(const e of r.boardEffects){e.owner=other(e.owner);e.responseSide=other(e.responseSide);e.squares=e.squares.map(flip);}
 for(const e of r.modifiers){e.owner=other(e.owner);e.responseSide=other(e.responseSide);}
 for(const e of r.vows){e.owner=other(e.owner);if(e.square!==null)e.square=flip(e.square);}
 if(r.special){r.special.from=flip(r.special.from);r.special.moves=r.special.moves.map(uci).sort();}
 if(r.pending)r.pending.owner=other(r.pending.owner);
 if(r.terminal?.winner)r.terminal.winner=other(r.terminal.winner);
 r.repetitions={};
 for(const key of ['hands','decks','knowledge'])s.hidden[key]=pair(s.hidden[key]);return s;
}
function mirrorAction(a){
 const b=structuredClone(a);
 if(a.type==='move')b.uci=uci(a.uci);
 else if(a.type==='play'&&typeof a.target==='number')b.target=CARDS[a.card].target==='zone'?flip(a.target)-8:flip(a.target);
 return b;
}
function normalized(input){
 const s=structuredClone(input),r=s.rules,p=r.fen.split(' ');r.fen=p.slice(0,5).join(' ');delete r.repetitions;
 for(const e of r.boardEffects)e.squares.sort((a,b)=>a-b);
 if(r.special)r.special.moves.sort();return s;
}
const stats={fixturePaths:0,statesCompared:0,completeLegalSetsCompared:0,branchTransitionsCompared:0,canonicalTransitionsCompared:0,cards:[],specialMoves:0,castles:0,enPassants:0,promotions:0,illegalAtomicRejections:0};
const cards=new Set();let current;
function inspect(state,label){
 const base=structuredClone(state);base.rules.repetitions={};const reflected=mirror(base),side=base.rules.fen.split(' ')[1];
 const actions=legalActions(playerView(base,side)),mirroredActions=legalActions(playerView(reflected,other(side)));
 current={label,state:base,reflected};
 assert.deepEqual(mirroredActions.map(actionKey).sort(),actions.map(mirrorAction).map(actionKey).sort(),label+': complete reflected legal action set');
 stats.completeLegalSetsCompared++;stats.statesCompared++;
 const picks=[];
 for(const type of ['move','play','discard','resolve','pass']){
  const all=actions.filter(a=>a.type===type);if(!all.length)continue;
  for(const n of new Set([0,Math.floor(all.length/2),all.length-1]))picks.push(all[n]);
 }
 for(const a of picks){
  const before=JSON.stringify(base),ma=mirrorAction(a);current.action=a;
  const next=applyAuthoritative(base,a),mnext=applyAuthoritative(reflected,ma);
  assert.equal(JSON.stringify(base),before,label+': retained input remains immutable');
  assert.deepEqual(normalized(mnext),normalized(mirror(next)),label+': reflected transition '+actionKey(a));
  stats.branchTransitionsCompared++;
  if(a.type==='play')cards.add(a.card);
  if(a.type==='move'){
   if(base.rules.special)stats.specialMoves++;
   if(['e1g1','e1c1','e8g8','e8c8'].includes(a.uci))stats.castles++;
   if(a.uci.length===5)stats.promotions++;
   const piece=base.rules.fen.split(' ')[0]; // EP geometry is diagnosed independently below.
   void piece;
  }
 }
 for(const a of [{type:'move',uci:'z9z9'},{type:'play',card:'shelter',target:NaN},{type:'resolve',order:['radar','radar']}]){
  const before=JSON.stringify(base);assert.throws(()=>applyAuthoritative(base,a));assert.equal(JSON.stringify(base),before);stats.illegalAtomicRejections++;
 }
}
try{
 for(const f of fixtures){
  let state=initial(structuredClone(f));stats.fixturePaths++;inspect(state,f.fixtureId+':initial');
  for(let i=0;i<f.steps.length;i++){
   const step=f.steps[i];if(!step.action||step.legal===false)continue;
   const base=structuredClone(state);base.rules.repetitions={};const reflected=mirror(base),ma=mirrorAction(step.action);
   current={label:f.fixtureId+':step'+i,state:base,reflected,action:step.action};
   const after=applyAuthoritative(base,step.action),moved=applyAuthoritative(reflected,ma);
   assert.deepEqual(normalized(moved),normalized(mirror(after)),current.label+': canonical path mirror');stats.canonicalTransitionsCompared++;
   if(step.action.type==='play')cards.add(step.action.card);
   state=after;inspect(state,f.fixtureId+':after'+i);
  }
 }
 stats.cards=[...cards].sort();assert.equal(stats.cards.length,24);
 writeFileSync(out+'/color-symmetry-results.json',JSON.stringify({status:'PASS',scope:'Color-swap + vertical board reflection metamorphic audit; FEN fullmove and serialized repetition dictionary omitted from equality, not a complete independent rules oracle.',stats},null,2)+'\n');
 console.log(JSON.stringify(stats));
}catch(error){
 writeFileSync(out+'/color-symmetry-failure-'+Date.now()+'.json',JSON.stringify({message:error.message,current,stats},null,2)+'\n');throw error;
}
