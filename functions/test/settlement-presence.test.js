'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {settlePlayerPresence}=require('../lib/settlement-presence');

function database(values,retry,cold=false){
  return {values,ref(path){return {async transaction(update,onComplete,applyLocally){
    if(cold){
      const probe=update(null);
      if(probe===undefined)return {committed:false};
      assert.equal(probe,null);
      assert.equal(onComplete,undefined);
      assert.equal(applyLocally,false);
    }
    const first=update(values[path]);
    if(retry)retry(values,path);
    const next=retry?update(values[path]):first;
    if(next!==undefined)values[path]=next;
    return {committed:next!==undefined};
  }};}};
}
const pointer='rankedState/activeByUser/player';
const presence='rankedPlayers/player';
const finished={matchId:'old',status:'finished'};

test('settlement clears only its own pointer and is safe to repeat',async()=>{
  const db=database({[pointer]:'old',[presence]:{matchId:'old',status:'active'}});
  await settlePlayerPresence(db,'player','old',finished);
  assert.equal(db.values[pointer],null);
  assert.deepEqual(db.values[presence],finished);
  await settlePlayerPresence(db,'player','old',finished);
  assert.equal(db.values[pointer],null);
  assert.deepEqual(db.values[presence],finished);
});

test('old settlement preserves a newer active match',async()=>{
  const values={[pointer]:'new',[presence]:{matchId:'new',status:'active'}};
  const expected=structuredClone(values),db=database(values);
  await settlePlayerPresence(db,'player','old',finished);
  assert.deepEqual(values,expected);
});

test('old settlement preserves a new queue and missing presence',async()=>{
  for(const current of [{status:'queued'},null]){
    const values={[pointer]:null,[presence]:current},expected=structuredClone(values);
    await settlePlayerPresence(database(values),'player','old',finished);
    assert.deepEqual(values,expected);
  }
});

test('transaction retries observe a match created between read and commit',async()=>{
  const values={[pointer]:'old',[presence]:{matchId:'old',status:'active'}};
  const db=database(values,(state,path)=>{
    state[path]=path===pointer?'new':{matchId:'new',status:'active'};
  });
  await settlePlayerPresence(db,'player','old',finished);
  assert.equal(values[pointer],'new');
  assert.deepEqual(values[presence],{matchId:'new',status:'active'});
});

test('cold-cache settlement clears its server pointer and finishes presence',async()=>{
  const db=database({[pointer]:'old',[presence]:{matchId:'old',status:'active'}},null,true);
  await settlePlayerPresence(db,'player','old',finished);
  assert.equal(db.values[pointer],null);
  assert.deepEqual(db.values[presence],finished);
});

test('cold-cache settlement preserves a newer server match',async()=>{
  const values={[pointer]:'new',[presence]:{matchId:'new',status:'active'}},expected=structuredClone(values);
  await settlePlayerPresence(database(values,null,true),'player','old',finished);
  assert.deepEqual(values,expected);
});

test('cold-cache settlement preserves missing server records',async()=>{
  const values={[pointer]:null,[presence]:null};
  await settlePlayerPresence(database(values,null,true),'player','old',finished);
  assert.deepEqual(values,{[pointer]:null,[presence]:null});
});

test('cold-cache settlement preserves a match created during transaction retry',async()=>{
  const values={[pointer]:'old',[presence]:{matchId:'old',status:'active'}};
  const db=database(values,(state,path)=>{state[path]=path===pointer?'new':{matchId:'new',status:'active'};},true);
  await settlePlayerPresence(db,'player','old',finished);
  assert.equal(values[pointer],'new');
  assert.deepEqual(values[presence],{matchId:'new',status:'active'});
});
