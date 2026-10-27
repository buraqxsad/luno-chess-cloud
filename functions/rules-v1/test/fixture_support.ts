import assert from 'node:assert/strict';
import {newBattle,applyAuthoritative,playerView} from '../src/authoritative.js';
import {legalActions} from '../src/core.js';
import {actionKey,clone,type Action,type CardId,type AuthoritativeBattleState} from '../src/model.js';

export interface FixtureStep {action?:Action;legal?:boolean;branch?:string;contains?:string[];excludes?:string[];exact?:string[];expect?:Record<string,unknown>}
export interface Fixture {fixtureId:string;intent:string;fen?:string;whiteDeckOrder:CardId[];blackDeckOrder:CardId[];ready?:boolean;setup?:{rules?:Record<string,unknown>;hidden?:Record<string,unknown>};steps:FixtureStep[]}
export function initial(f:Fixture):AuthoritativeBattleState {
  const s=clone(newBattle(f.whiteDeckOrder,f.blackDeckOrder,f.fen));
  if(f.ready){s.rules.phase='card';s.rules.mana={w:6,b:6};s.rules.ownTurns={w:2,b:2};s.rules.repetitions={};}
  Object.assign(s.rules,f.setup?.rules);Object.assign(s.hidden,f.setup?.hidden);return s;
}
export function at(value:unknown,path:string):unknown {
  return path.split('.').reduce<unknown>((v,k)=>v!==null&&typeof v==='object'?(v as Record<string,unknown>)[k]:undefined,value);
}
export function runFixture(f:Fixture):AuthoritativeBattleState {
  let state=initial(f);
  for(const [index,step] of f.steps.entries()){
    const keys=legalActions(playerView(state,state.rules.fen.split(' ')[1] as 'w'|'b')).map(actionKey).sort();
    for(const k of step.contains??[])assert.ok(keys.includes(k),`${f.fixtureId}:${index} missing ${k}`);
    for(const k of step.excludes??[])assert.ok(!keys.includes(k),`${f.fixtureId}:${index} extra ${k}`);
    if(step.exact)assert.deepEqual(keys,[...step.exact].sort(),`${f.fixtureId}:${index} complete legal set`);
    if(step.action){
      const before=JSON.stringify(state);
      if(step.legal===false){assert.throws(()=>applyAuthoritative(state,step.action!),/illegal-action/);assert.equal(JSON.stringify(state),before);}
      else state=applyAuthoritative(state,step.action);
    }
    for(const [path,expected] of Object.entries(step.expect??{}))assert.deepEqual(at(state,path),expected,`${f.fixtureId}:${index} ${path}`);
  }
  return state;
}
