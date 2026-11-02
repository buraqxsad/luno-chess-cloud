'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path='/workspace/luno-chess';
const out='/workspace/luno-review/bug-audit-round3/rules';
const {initial}=require(path+'/functions/rules-v1/dist/test/fixture_support');
const {newBattle,applyAuthoritative,playerView}=require(path+'/functions/rules-v1/dist/src/authoritative');
const {legalActions,chooseBotAction}=require(path+'/functions/rules-v1/dist/src/core');
const {CARDS,STARTER,actionKey}=require(path+'/functions/rules-v1/dist/src/model');
const fixtures=JSON.parse(fs.readFileSync(path+'/battle_contract/v1/rules.json')).fixtures;
const clone=v=>JSON.parse(JSON.stringify(v));
const side=s=>s.rules.fen.split(' ')[1];
const enemy=s=>s==='w'?'b':'w';
const stats={fixturePaths:0,states:0,worldPairs:0,changedWorldPairs:0,privateSuffixPermutations:0,publicBranchesCompared:0,authoritativeCanonicalExtras:0,malformedAtomicRejections:0,serializationStates:0,cards:[]};
const cards=new Set(),wire=[];
let current;
function pairWorld(input,viewer){
  const s=clone(input),opponent=enemy(viewer);
  // Alter unseen opponent cards coherently; retain publicly used/discarded cards.
  // Existing observer Radar findings must remain truthful, so those states only
  // permute hands and deck suffixes rather than moving cards between zones.
  const observed=s.hidden.knowledge[viewer].radarObservations;
  if(!observed.length&&!s.hidden.knowledge[opponent].pendingCards.length&&!s.hidden.knowledge[opponent].knownUpcomingCards.length){
    const remaining=[...s.hidden.hands[opponent],...s.hidden.decks[opponent]].reverse();
    s.hidden.hands[opponent]=remaining.slice(0,s.rules.handCounts[opponent]);
    s.hidden.decks[opponent]=remaining.slice(s.rules.handCounts[opponent]);
  }else s.hidden.hands[opponent].reverse();
  for(const color of ['w','b']){
    const protectedPrefix=Math.max(s.hidden.knowledge[color].pendingCards.length,s.hidden.knowledge[color].knownUpcomingCards.length);
    const d=s.hidden.decks[color];
    if(d.length-protectedPrefix>1){s.hidden.decks[color]=[...d.slice(0,protectedPrefix),...d.slice(protectedPrefix).reverse()];stats.privateSuffixPermutations++;}
  }
  // Opponent knowledge is never a part of viewer's legal/bot input.
  s.hidden.knowledge[opponent].radarObservations=[];
  return s;
}
function malformed(state){
  const before=JSON.stringify(state),viewer=side(state),actions=legalActions(playerView(state,viewer));
  const candidates=[null,[],{},'pass',{type:'absent'},{type:'move',uci:'a0a9'},
    {type:'resolve',order:null},{type:'resolve',order:{}},{type:'resolve',order:['radar,prophecy']},
    {type:'play',card:'not-a-card'},{type:'discard',card:'not-a-card'}];
  const play=actions.find(a=>a.type==='play');
  if(play){
    for(const target of [true,false,[],{},-1,64,.25])candidates.push({...play,target});
    if(typeof play.target==='number')candidates.push({...play,target:String(play.target)});
    else if(typeof play.target==='string')candidates.push({...play,target:[play.target]});
    for(const sacrifice of [true,[],{},'not-a-card'])candidates.push({...play,sacrifice});
  }
  const resolve=actions.find(a=>a.type==='resolve');
  if(resolve){
    candidates.push({...resolve,order:[...resolve.order,'radar']}, {...resolve,selected:'not-a-card'});
    if(resolve.order.length>1)candidates.push({...resolve,order:Array(resolve.order.length).fill(resolve.order[0])});
  }
  for(const a of candidates){
    current={label:current.label,action:a};
    assert.throws(()=>applyAuthoritative(state,a),undefined,current.label+' malformed rejected '+JSON.stringify(a));
    assert.equal(JSON.stringify(state),before,'malformed rejection mutates input');stats.malformedAtomicRejections++;
  }
}
function inspect(state,label){
  current={label};stats.states++;
  const viewer=side(state),baseView=playerView(state,viewer),other=pairWorld(state,viewer),before=JSON.stringify(state),otherBefore=JSON.stringify(other);
  assert.deepEqual(playerView(other,viewer),baseView,label+' exact visible-view equivalence');
  const actions=legalActions(baseView);
  assert.deepEqual(legalActions(playerView(other,viewer)),actions,label+' complete legal set private noninterference');
  assert.deepEqual(chooseBotAction(playerView(other,viewer)),chooseBotAction(baseView),label+' bot private noninterference');
  stats.worldPairs++;if(otherBefore!==before)stats.changedWorldPairs++;
  const representatives=[];
  for(const type of ['move','play','discard','resolve','pass']){
    const group=actions.filter(a=>a.type===type);
    if(type==='play'){
      for(const card of new Set(group.map(a=>a.card)))representatives.push(group.find(a=>a.card===card));
    }else if(group.length)representatives.push(group[0],...(group.length>1?[group[group.length-1]]:[]));
  }
  for(const action of representatives){
    const next=applyAuthoritative(state,action),otherNext=applyAuthoritative(other,action);
    assert.deepEqual(otherNext.rules,next.rules,label+' public transition private noninterference '+actionKey(action));
    assert.equal(JSON.stringify(state),before);assert.equal(JSON.stringify(other),otherBefore);stats.publicBranchesCompared++;
    const extras={...action,fen:'ignored',mana:999,hidden:{hands:{w:['not-a-card']}},selectedCard:'ignored',uci:action.uci??'z9z9',order:action.order??['not-a-card']};
    assert.deepEqual(applyAuthoritative(state,extras),next,label+' canonical extra fields inert at full authority');stats.authoritativeCanonicalExtras++;
    if(action.type==='play')cards.add(action.card);
  }
  const decoded=clone(state);
  assert.deepEqual(decoded,state,label+' JSON round trip');
  assert.deepEqual(legalActions(playerView(decoded,viewer)),actions,label+' JSON restored legal set');stats.serializationStates++;
  wire.push({label,state:decoded,actions:representatives});
  malformed(state);
}
try{
  for(const f of fixtures){
    let state=initial(clone(f));stats.fixturePaths++;inspect(state,f.fixtureId+':initial');
    for(const [i,step] of f.steps.entries())if(step.action&&step.legal!==false){state=applyAuthoritative(state,step.action);inspect(state,f.fixtureId+':after'+i);}
  }
  stats.cards=[...cards].sort();assert.equal(stats.cards.length,24);
  fs.writeFileSync(out+'/round3-rules-wire-states.json',JSON.stringify(wire));
  fs.writeFileSync(out+'/private-worlds-result.json',JSON.stringify({status:'PASS',stats,limits:'Metamorphic noninterference, JSON round trips and malformed-action atomicity; no independent complete chess/card oracle.'},null,2)+'\n');
  console.log(JSON.stringify(stats));
}catch(error){fs.writeFileSync(out+'/private-worlds-failure.json',JSON.stringify({message:error.message,current,stats},null,2)+'\n');throw error;}
