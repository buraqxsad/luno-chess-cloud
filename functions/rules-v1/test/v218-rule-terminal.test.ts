import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdirSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {applyAuthoritative,playerView} from '../src/authoritative.js';
import {legalActions} from '../src/core.js';
import {STARTER,actionKey,type Side} from '../src/model.js';
import {initial,type Fixture} from './fixture_support.js';

const cases=[
  {id:'white-quiet-149-150',fen:'7k/8/8/8/8/8/8/R3K3 w - - 149 1',uci:'a1a2',reason:'seventy_five_moves',half:150},
  {id:'black-quiet-149-150',fen:'r3k3/8/8/8/8/8/8/7K b - - 149 1',uci:'a8a7',reason:'seventy_five_moves',half:150},
  {id:'white-mate-149-150',fen:'7k/8/5KQ1/8/8/8/8/8 w - - 149 1',uci:'g6g7',reason:'checkmate',half:150},
  {id:'black-mate-149-150',fen:'8/8/8/8/8/5kq1/8/7K b - - 149 1',uci:'g3g2',reason:'checkmate',half:150},
  {id:'pawn-resets-149',fen:'7k/8/8/8/8/8/4P3/4K3 w - - 149 1',uci:'e2e3',reason:null,half:0},
  {id:'battle-bare-kings-not-dead-draw',fen:'7k/8/8/8/8/8/8/4K3 w - - 0 1',uci:'e1f1',reason:null,half:1},
] as const;

function fixture(c:typeof cases[number]):Fixture {
  return {fixtureId:c.id,intent:c.id,fen:c.fen,ready:true,whiteDeckOrder:[...STARTER],blackDeckOrder:[...STARTER],setup:{rules:{phase:'chess'}},steps:[]};
}

for(const c of cases)test(`battle terminal boundary: ${c.id}`,()=>{
  const before=initial(fixture(c)),side=before.rules.fen.split(' ')[1] as Side;
  assert.equal(before.rules.terminal,null);
  const after=applyAuthoritative(before,{type:'move',uci:c.uci});
  assert.equal(after.rules.terminal?.reason??null,c.reason);
  assert.equal(Number(after.rules.fen.split(' ')[4]),c.half);
  if(c.reason){
    assert.equal(after.rules.phase,'terminal');
    assert.equal(after.rules.drawCounts[side],before.rules.drawCounts[side]);
    assert.equal(after.rules.handCounts[side],before.rules.handCounts[side]);
    assert.equal(after.rules.terminal!.winner,c.reason==='checkmate'?side:null);
    assert.deepEqual(legalActions(playerView(after,side==='w'?'b':'w')),[]);
  }
});

test('fresh Dart/TS targeted terminal differential', {skip:!process.env.LUNO_DART_RUNNER},()=>{
  const requests:unknown[]=[],expected:{state:unknown;legal:string[]}[]=[];
  for(const c of cases){
    const f=fixture(c),before=initial(f),after=applyAuthoritative(before,{type:'move',uci:c.uci});
    requests.push({id:requests.length,initial:f},{id:requests.length+1,state:before,action:{type:'move',uci:c.uci}});
    for(const state of [before,after]){
      expected.push({state,legal:legalActions(playerView(state,state.rules.fen.split(' ')[1] as Side)).map(actionKey).sort()});
    }
  }
  const run=spawnSync(process.env.LUNO_DART_RUNNER!,JSON.parse(process.env.LUNO_DART_RUNNER_ARGS??'[]') as string[],{
    input:requests.map(r=>JSON.stringify(r)).join('\n')+'\n',encoding:'utf8',timeout:120000,maxBuffer:4*1024*1024
  });
  assert.ifError(run.error);
  assert.equal(run.status,0,run.stderr);
  const replies=run.stdout.trim().split(/\r?\n/).map(line=>JSON.parse(line) as {error:unknown;state:unknown;legal:string[]});
  assert.equal(replies.length,expected.length);
  replies.forEach((reply,i)=>{
    assert.equal(reply.error,null);
    assert.deepEqual(reply.state,expected[i]!.state,`state ${i}`);
    assert.deepEqual(reply.legal,expected[i]!.legal,`complete legal set ${i}`);
  });
  if(process.env.LUNO_DIFFERENTIAL_QA){
    const qa=resolve(process.env.LUNO_DIFFERENTIAL_QA);mkdirSync(qa,{recursive:true});
    writeFileSync(resolve(qa,'v218-targeted-terminal-differential.json'),JSON.stringify({runner:process.env.LUNO_DART_RUNNER,cases:cases.map(c=>c.id),statesCompared:expected.length,completeLegalSetsCompared:expected.length,divergences:0},null,2));
  }
});
