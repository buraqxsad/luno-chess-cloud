'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {getDatabase}=require('firebase-admin/database');
const {starterProfile,transactExistingPlayer,authoritativeState}=require('../index')._test;
const snapshot=value=>({exists:()=>value!==null,val:()=>structuredClone(value)});

function database(t,initial){
  let current=structuredClone(initial);
  t.mock.method(getDatabase(),'ref',path=>{
    assert.equal(path,'users/player');
    return {
      async get(){return snapshot(current);},
      async transaction(update){
        const next=update(structuredClone(current));
        if(next!==undefined)current=structuredClone(next);
        return {committed:next!==undefined,snapshot:snapshot(current)};
      }
    };
  });
  return {get value(){return structuredClone(current);}};
}

test('player mutations get a monotonic revision independent of wall clock',async t=>{
  const initial=starterProfile('player','player_name');
  initial.stateRevision=8;initial.updatedAt=90000;
  const db=database(t,initial);
  const first=await transactExistingPlayer('player',p=>{p.gold+=500;p.updatedAt=100;return {commit:true};});
  const second=await transactExistingPlayer('player',p=>{p.bio='saved';p.updatedAt=50;return {commit:true};});
  assert.equal(first.profile.stateRevision,9);
  assert.equal(second.profile.stateRevision,10);
  assert.equal(db.value.stateRevision,10);
});

test('idempotent non-committing reads do not fabricate revisions',async t=>{
  const initial=starterProfile('player','player_name');initial.stateRevision=15;
  database(t,initial);
  const result=await transactExistingPlayer('player',()=>({commit:false,idempotent:true}));
  assert.equal(result.profile.stateRevision,15);
  assert.equal(result.committed,false);
});

test('a committing no-op does not fabricate a product state change',async t=>{
  const initial=starterProfile('player','player_name');initial.stateRevision=15;
  database(t,initial);
  const result=await transactExistingPlayer('player',()=>({commit:true}));
  assert.equal(result.profile.stateRevision,15);
  assert.deepEqual(result.profile,initial);
});

test('mutation cannot replace its transaction revision with a guessed value',async t=>{
  const initial=starterProfile('player','player_name');initial.stateRevision=5;
  database(t,initial);
  const result=await transactExistingPlayer('player',p=>{p.stateRevision=999;p.gold++;return {commit:true};});
  assert.equal(result.profile.stateRevision,6);
});

test('transaction callback retry uses the actual newer committed revision',async t=>{
  const initial=starterProfile('player','player_name');initial.stateRevision=5;
  t.mock.method(getDatabase(),'ref',()=>({
    async get(){return snapshot(initial);},
    async transaction(update){
      assert.equal(update(structuredClone(initial)).stateRevision,6);
      const concurrent={...initial,stateRevision:7,gold:2000};
      return {committed:true,snapshot:snapshot(update(concurrent))};
    }
  }));
  const result=await transactExistingPlayer('player',p=>{p.gold+=10;return {commit:true};});
  assert.equal(result.profile.stateRevision,8);
  assert.equal(result.profile.gold,2010);
});

test('legacy profiles acquire their first revision without a data reset',async t=>{
  const initial=starterProfile('player','player_name');delete initial.stateRevision;initial.gold=321;
  database(t,initial);
  const result=await transactExistingPlayer('player',p=>{p.bio='new';return {commit:true};});
  assert.equal(result.profile.stateRevision,1);
  assert.equal(result.profile.gold,321);
});

test('authoritative state exposes commit revision and projection time',t=>{
  t.mock.method(Date,'now',()=>1700000000000);
  const profile=starterProfile('player','player_name');profile.stateRevision=23;
  const state=authoritativeState(profile,1700000000000);
  assert.equal(state.stateRevision,23);
  assert.equal(state.stateObservedAt,1700000000000);
});

test('a delayed mutation response cannot project expired membership as active',t=>{
  t.mock.method(Date,'now',()=>5000);
  const profile=starterProfile('player','player_name');
  profile.stateRevision=24;profile.premiumUntil=2000;
  const state=authoritativeState(profile,1000);
  assert.equal(state.stateObservedAt,5000);
  assert.equal(state.membership.active,false);
});

test('revision exhaustion fails before a profile write can commit',async t=>{
  const initial=starterProfile('player','player_name');initial.stateRevision=Number.MAX_SAFE_INTEGER;
  const db=database(t,initial);
  await assert.rejects(transactExistingPlayer('player',p=>{p.gold=0;return {commit:true};}),{code:'player-state-revision-invalid'});
  assert.deepEqual(db.value,initial);
});

test('V1 settlement advances product state revision only on its recovery write',async()=>{
  const {fixture}=require('./helpers/battle-v1-fixture');
  const {authority}=require('../lib/battle-v1');
  const f=fixture();await f.enable();
  await f.api.enqueueBattleV1(f.context('alice',{client:f.client},'v234-alice'));
  const queued=await f.api.enqueueBattleV1(f.context('bob',{client:f.client},'v234-bob'));
  await f.api.transact(queued.matchId,'alice',m=>({match:authority.finishMatch(m,{reason:'resign',winner:'w',finishedAt:1000})}));
  await f.api.settle(queued.matchId,'alice');
  const saved=f.read('users/alice');
  assert.equal(saved.stateRevision,1);
  await f.api.settle(queued.matchId,'bob');
  assert.deepEqual(f.read('users/alice'),saved);
});
