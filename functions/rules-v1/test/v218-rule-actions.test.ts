import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdirSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {newBattle,playerView} from '../src/authoritative.js';
import {legalActions,transition} from '../src/core.js';
import {CARDS,STARTER,clone,type Action,type CardId,type PlayerView} from '../src/model.js';
import {initial,type Fixture} from './fixture_support.js';

function ready(cards:CardId[]):PlayerView {
  const deck=[...cards,...Object.keys(CARDS).map(c=>c as CardId).filter(c=>!cards.includes(c))].slice(0,10);
  const s=clone(newBattle(deck,STARTER));
  s.rules.phase='card';s.rules.ownTurns={w:2,b:2};s.rules.mana={w:6,b:6};s.rules.repetitions={};
  return playerView(s,'w');
}

test('numeric square targets cannot be spoofed by string/array coercion',()=>{
  const view=ready(['shelter']),before=JSON.stringify(view);
  for(const target of ['8',[8],{toString:()=> '8'},8.5,NaN,Infinity]){
    assert.throws(()=>transition(view,{type:'play',card:'shelter',target} as Action),/illegal-action/);
    assert.equal(JSON.stringify(view),before);
  }
  assert.deepEqual(transition(view,{type:'play',card:'shelter',target:8}).rules.used.w,['shelter']);
});

test('a no-target card rejects empty strings and arrays instead of spending mana',()=>{
  const view=ready(['prophecy','shadow_contract']);
  for(const action of [
    {type:'play',card:'prophecy',target:''},
    {type:'play',card:'prophecy',target:[]},
    {type:'play',card:'shadow_contract',target:'',sacrifice:'prophecy'},
    {type:'play',card:'shadow_contract',sacrifice:['prophecy']},
  ])assert.throws(()=>transition(view,action as Action),/illegal-action/);
  assert.equal(transition(view,{type:'play',card:'prophecy'}).rules.phase,'pending');
});

test('resolve validates the actual bounded card array, not its joined string',()=>{
  const base=ready(['prophecy']),played=transition(base,{type:'play',card:'prophecy'});
  const view:PlayerView={...base,rules:played.rules,ownHand:base.ownHand.filter(c=>c!=='prophecy'),knowledge:{...base.knowledge,pendingCards:['chain','slow']}};
  const before=JSON.stringify(view);
  for(const order of [['chain,slow'],'chain,slow',null,{},['chain','chain']]){
    assert.throws(()=>transition(view,{type:'resolve',order} as Action),/illegal-action/);
    assert.equal(JSON.stringify(view),before);
  }
  for(const action of legalActions(view))assert.equal(transition(view,action).rules.phase,'chess');
});

test('unknown extra fields remain inert on otherwise valid actions',()=>{
  const view=ready(['shelter']);
  const action={type:'play',card:'shelter',target:8} as const;
  assert.deepEqual(transition(view,{...action,mana:999} as Action),transition(view,action));
  for(const malformed of [null,undefined,[],{},'pass',{type:'resolve'}]){
    assert.throws(()=>transition(view,malformed as Action),/illegal-action/);
  }
});

test('fresh Dart/TS rejects the same coerced target payloads', {skip:!process.env.LUNO_DART_RUNNER},()=>{
  const f:Fixture={fixtureId:'v218-coerced-targets',intent:'Reject malformed targets without spending cards or mana',ready:true,whiteDeckOrder:[...STARTER],blackDeckOrder:[...STARTER],steps:[]};
  const before=initial(f),actions:Action[]=[{type:'play',card:'shelter',target:'8'},{type:'play',card:'prophecy',target:''}];
  const view=playerView(before,'w');
  for(const action of actions)assert.throws(()=>transition(view,action),/illegal-action/);
  const run=spawnSync(process.env.LUNO_DART_RUNNER!,JSON.parse(process.env.LUNO_DART_RUNNER_ARGS??'[]') as string[],{
    input:actions.map((action,id)=>JSON.stringify({id,state:before,action})).join('\n')+'\n',encoding:'utf8',timeout:120000,maxBuffer:4*1024*1024
  });
  assert.ifError(run.error);assert.equal(run.status,0,run.stderr);
  const replies=run.stdout.trim().split(/\r?\n/).map(line=>JSON.parse(line) as {error:unknown;state:unknown});
  assert.equal(replies.length,actions.length);
  for(const reply of replies){assert.equal(reply.error,'illegal-action');assert.deepEqual(reply.state,before);}
  if(process.env.LUNO_DIFFERENTIAL_QA){
    const qa=resolve(process.env.LUNO_DIFFERENTIAL_QA);mkdirSync(qa,{recursive:true});
    writeFileSync(resolve(qa,'v218-targeted-action-differential.json'),JSON.stringify({runner:process.env.LUNO_DART_RUNNER,actions,rejectedWithoutMutation:replies.length,divergences:0},null,2));
  }
});
