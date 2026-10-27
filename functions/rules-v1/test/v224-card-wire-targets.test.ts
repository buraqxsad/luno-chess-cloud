import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdirSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {newBattle,applyAuthoritative,playerView} from '../src/authoritative.js';
import {legalActions} from '../src/core.js';
import {boardFen,squares} from '../src/board.js';
import {CARDS,STARTER,clone,actionKey,type Action,type CardId,type Side} from '../src/model.js';

const numericTargets=new Set([
  'own_piece','opponent_piece','opponent_slider','own_pawn','empty_square',
  'zone','own_rook','own_knight','own_bishop_rook',
]);
const baseFen='4k3/rnbq1p2/8/3p4/3P4/8/1PNR1B2/4K3 w - - 0 10';
function ready(card:CardId,side:Side){
  const deck=[card,...(Object.keys(CARDS) as CardId[]).filter(c=>c!==card)].slice(0,10);
  const board=squares(baseFen);
  const fen=side==='w'?baseFen:boardFen(
    board.reverse().map(p=>p?(p===p.toUpperCase()?p.toLowerCase():p.toUpperCase()):null),
    side,'-','-',0,10,
  );
  const state=clone(newBattle(side==='w'?deck:STARTER,side==='b'?deck:STARTER,fen));
  state.rules.phase='card';state.rules.ownTurns={w:2,b:2};
  state.rules.mana={w:6,b:6};state.rules.repetitions={};
  return state;
}
for(const side of ['w','b'] as const){
  for(const card of Object.keys(CARDS) as CardId[]){
    if(!numericTargets.has(CARDS[card].target))continue;
    test(`${side}/${card}: equivalent JSON integer spellings agree`,()=>{
      const state=ready(card,side),before=clone(state);
      const action=legalActions(playerView(state,side)).find(
        (a):a is Extract<Action,{type:'play'}>=>a.type==='play'&&a.card===card,
      );
      assert.ok(action);assert.equal(typeof action.target,'number');
      const target=action.target as number,expected=applyAuthoritative(state,action);
      for(const number of [String(target),`${target}.0`,`${target}e0`]){
        const parsed=JSON.parse(`{"type":"play","card":"${card}","target":${number}}`) as Action;
        assert.deepEqual(applyAuthoritative(state,parsed),expected);
      }
      for(const target of [String(action.target),[action.target],{square:action.target},
        (action.target as number)+.5,true,-1,64]){
        assert.throws(()=>applyAuthoritative(state,{type:'play',card,target} as Action),/illegal-action/);
        assert.deepEqual(state,before);
      }
    });
  }
}

test('fresh Dart/TS compare raw equivalent and malformed card target JSON',
  {skip:!process.env.LUNO_DART_RUNNER},()=>{
    const requests:string[]=[],expected:Array<{state:ReturnType<typeof ready>;error:string|null}>=[];
    let valid=0,rejected=0;
    for(const side of ['w','b'] as const)for(const card of Object.keys(CARDS) as CardId[]){
      if(!numericTargets.has(CARDS[card].target))continue;
      const state=ready(card,side);
      const action=legalActions(playerView(state,side)).find(
        (a):a is Extract<Action,{type:'play'}>=>a.type==='play'&&a.card===card,
      );
      assert.ok(action);const target=action.target as number;
      const forms=[String(target),`${target}.0`,`${target}e0`,
        JSON.stringify(String(target)),`[${target}]`,`{"square":${target}}`,String(target+.5)];
      for(const [index,number] of forms.entries()){
        const raw=`{"type":"play","card":"${card}","target":${number}}`;
        const parsed=JSON.parse(raw) as Action;
        const success=index<3;
        if(success){expected.push({state:applyAuthoritative(state,parsed),error:null});valid++;}
        else {assert.throws(()=>applyAuthoritative(state,parsed),/illegal-action/);
          expected.push({state,error:'illegal-action'});rejected++;}
        requests.push(`{"id":${requests.length},"state":${JSON.stringify(state)},"action":${raw}}`);
      }
    }
    const run=spawnSync(process.env.LUNO_DART_RUNNER!,
      JSON.parse(process.env.LUNO_DART_RUNNER_ARGS??'[]') as string[],{
        input:requests.join('\n')+'\n',encoding:'utf8',timeout:120000,maxBuffer:20*1024*1024,
      });
    assert.ifError(run.error);assert.equal(run.status,0,run.stderr);
    const replies=run.stdout.trim().split(/\r?\n/).map(line=>JSON.parse(line) as {
      state:ReturnType<typeof ready>;error:string|null;legal:string[];
    });
    assert.equal(replies.length,expected.length);
    for(const [index,reply] of replies.entries()){
      assert.equal(reply.error,expected[index]!.error,`request ${index} disposition`);
      assert.deepEqual(reply.state,expected[index]!.state,`request ${index} complete state`);
      const state=expected[index]!.state,side=state.rules.fen.split(' ')[1] as Side;
      assert.deepEqual(reply.legal,legalActions(playerView(state,side)).map(actionKey).sort(),
        `request ${index} complete legal action set`);
    }
    if(process.env.LUNO_DIFFERENTIAL_QA){
      const qa=resolve(process.env.LUNO_DIFFERENTIAL_QA);mkdirSync(qa,{recursive:true});
      writeFileSync(resolve(qa,'v224-card-wire-differential.json'),JSON.stringify({
        requests:requests.length,valid,rejected,completeStatesCompared:replies.length,
        completeLegalSetsCompared:replies.length,divergences:0,
      },null,2));
    }
  });
