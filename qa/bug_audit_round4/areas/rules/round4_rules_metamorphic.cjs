"use strict";
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const base='/workspace/luno-chess/functions/rules-v1/dist';
const out='/workspace/luno-review/bug-audit-round4/rules';
const {initial}=require(base+'/test/fixture_support');
const {applyAuthoritative,playerView}=require(base+'/src/authoritative');
const {legalActions}=require(base+'/src/core');
const {actionKey}=require(base+'/src/model');
const fixtures=JSON.parse(fs.readFileSync('/workspace/luno-chess/battle_contract/v1/rules.json')).fixtures;
const clone=structuredClone;
let context={};
const stats={fixturePaths:fixtures.length,states:0,sourceLegalActions:0,cards:[],rename:{states:0,branches:0,assertions:0},clock:{states:0,changedStates:0,branches:0,assertions:0}};
const cards=new Set(),rows=[];
function side(s){return s.rules.fen.split(' ')[1];}
function keys(s){return legalActions(playerView(s,side(s))).map(actionKey).sort();}
function eq(actual,expected,message,kind){stats[kind].assertions++;assert.deepEqual(actual,expected,message);}
function mapIds(value,pieces,effects,key=''){
  if(value===null||typeof value!=='object'){
    if(typeof value==='string'&&['pieceId','pieceIds','movedPawns'].includes(key))return pieces[value]??value;
    if(typeof value==='string'&&key==='id')return effects[value]??value;
    return value;
  }
  if(Array.isArray(value))return value.map(v=>mapIds(v,pieces,effects,key));
  const result={};
  for(const [k,v] of Object.entries(value)){
    if(k==='repetitions'){
      result[k]=Object.fromEntries(Object.entries(v).map(([fingerprint,count])=>{
        try{return [JSON.stringify(mapIds(JSON.parse(fingerprint),pieces,effects)),count];}catch{return [fingerprint,count];}
      }));
    }else result[k]=mapIds(v,pieces,effects,k);
  }
  return result;
}
function actionIds(a,effects){const b=clone(a);if(b.type==='play'&&['purify','break_seal'].includes(b.card))b.target=effects[b.target]??b.target;return b;}
function clocks(s,offsets,direction=1){const b=clone(s);for(const c of ['w','b'])b.rules.ownTurns[c]+=direction*offsets[c];for(const m of b.rules.modifiers)m.ownTurn+=direction*offsets[m.responseSide];return b;}
for(const f of fixtures){
 let s=initial(clone(f));
 const inspect=label=>{
  const actions=legalActions(playerView(s,side(s)));
  const pieceNames=[...new Set([...s.rules.pieceIds,...s.rules.movedPawns,...s.rules.pieceEffects.map(e=>e.pieceId),...s.rules.vows.map(v=>v.pieceId)].filter(Boolean))];
  const effectNames=[...new Set([...s.rules.pieceEffects,...s.rules.boardEffects,...s.rules.modifiers,...s.rules.vows].map(e=>e.id))];
  const pieces=Object.fromEntries(pieceNames.map((v,i)=>[v,'round4/piece/'+i]));
  const effects=Object.fromEntries(effectNames.map((v,i)=>[v,'round4/effect/'+i]));
  const offsets=Object.fromEntries(['w','b'].map(c=>[c,s.rules.ownTurns[c]>=2?17:0]));
  rows.push({label,state:clone(s),actions,pieces,effects,offsets});stats.states++;stats.sourceLegalActions+=actions.length;
  for(const a of actions)if(a.type==='play')cards.add(a.card);
 };
 inspect(f.fixtureId+':initial');
 for(const [i,step] of f.steps.entries())if(step.action&&step.legal!==false){s=applyAuthoritative(s,step.action);inspect(f.fixtureId+':after'+i);}
}
fs.writeFileSync(out+'/round4_rules_states.json',JSON.stringify(rows));
function run(kind){
 for(const row of rows){
  context={kind,label:row.label};
  const state=row.state,before=JSON.stringify(state);
  const pieces=kind==='rename'?row.pieces:{},effects=kind==='rename'?row.effects:{};
  const invPieces=Object.fromEntries(Object.entries(pieces).map(([a,b])=>[b,a]));
  const invEffects=Object.fromEntries(Object.entries(effects).map(([a,b])=>[b,a]));
  const transformed=kind==='rename'?mapIds(state,pieces,effects):clocks(state,row.offsets);
  const restored=s=>kind==='rename'?mapIds(s,invPieces,invEffects):clocks(s,row.offsets,-1);
  const transformedBefore=JSON.stringify(transformed);
  eq(restored(transformed),state,'transformation invertibility',kind);
  const expectedActions=row.actions.map(a=>actionIds(a,effects));
  eq(legalActions(playerView(transformed,side(transformed))).map(actionKey).sort(),expectedActions.map(actionKey).sort(),'complete transformed legal set',kind);
  stats[kind].states++;if(kind==='clock'&&(row.offsets.w||row.offsets.b))stats.clock.changedStates++;
  for(const action of row.actions){
   context={kind,label:row.label,action};
   const next=applyAuthoritative(state,action);
   const changed=applyAuthoritative(transformed,actionIds(action,effects));
   eq(restored(changed),next,'complete transformed authoritative transition',kind);
   eq(keys(changed),legalActions(playerView(next,side(next))).map(a=>actionIds(a,effects)).map(actionKey).sort(),'complete transformed successor legal set',kind);
   eq(JSON.stringify(state),before,'retained source input',kind);
   eq(JSON.stringify(transformed),transformedBefore,'retained transformed input',kind);
   stats[kind].branches++;
  }
 }
}
test('round4 rules: arbitrary bijective piece/effect namespaces preserve every canonical outgoing branch',()=>run('rename'));
test('round4 rules: relative own-turn translation preserves every canonical outgoing branch',()=>run('clock'));
process.on('exit',code=>{stats.cards=[...cards].sort();fs.writeFileSync(out+'/metamorphic-node-result.json',JSON.stringify({status:code===0?'PASS':'FAIL',stats,context:code?context:undefined},null,2)+'\n');});
