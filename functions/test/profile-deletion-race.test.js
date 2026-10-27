'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {getDatabase}=require('firebase-admin/database');
const {transactExistingPlayer,starterProfile}=require('../index')._test;
const snapshot=value=>({exists:()=>value!==null,val:()=>structuredClone(value)});

test('profile deleted after initial read is not recreated',async(t)=>{
  let reads=0,mutations=0;
  t.mock.method(getDatabase(),'ref',()=>({
    async get(){return snapshot(reads++===0?starterProfile('player','playername'):null);},
    async transaction(update){
      assert.equal(update(null),null);
      return {committed:true,snapshot:snapshot(null)};
    },
  }));
  await assert.rejects(transactExistingPlayer('player',()=>{mutations++;return {commit:true};}),
    error=>error.code==='profile-not-found');
  assert.equal(mutations,0);
});

test('initial cached null retries using server profile, not stale snapshot',async(t)=>{
  const before=starterProfile('player','playername');before.gold=10;
  const current=structuredClone(before);current.gold=90;
  t.mock.method(getDatabase(),'ref',()=>({
    async get(){return snapshot(before);},
    async transaction(update){
      assert.equal(update(null),null);
      const saved=update(current);
      return {committed:true,snapshot:snapshot(saved)};
    },
  }));
  const result=await transactExistingPlayer('player',profile=>{profile.gold+=5;return {commit:true};});
  assert.equal(result.profile.gold,95);
});

test('deletion on transaction retry discards previous decision',async(t)=>{
  const profile=starterProfile('player','playername');
  t.mock.method(getDatabase(),'ref',()=>({
    async get(){return snapshot(profile);},
    async transaction(update){
      assert.ok(update(structuredClone(profile)));
      assert.equal(update(null),null);
      return {committed:true,snapshot:snapshot(null)};
    },
  }));
  await assert.rejects(transactExistingPlayer('player',value=>{value.gold+=5;return {commit:true};}),
    error=>error.code==='profile-not-found');
});

test('missing profile rejects before any transaction',async(t)=>{
  t.mock.method(getDatabase(),'ref',()=>({
    async get(){return snapshot(null);},
    async transaction(){assert.fail('must not transact on missing account');},
  }));
  await assert.rejects(transactExistingPlayer('player',()=>({commit:true})),
    error=>error.code==='profile-not-found');
});

test('profile transaction does not expose speculative writes to concurrent reads',async t=>{
  const profile=starterProfile('player','playername');
  t.mock.method(getDatabase(),'ref',()=>({
    async get(){return snapshot(profile);},
    async transaction(update,onComplete,applyLocally){
      assert.equal(onComplete,undefined);
      assert.equal(applyLocally,false);
      assert.equal(update(null),null);
      assert.ok(profile,'speculative null must not replace the cached profile');
      return {committed:true,snapshot:snapshot(update(structuredClone(profile)))};
    },
  }));
  const result=await transactExistingPlayer('player',value=>{value.gold+=5;return {commit:true};});
  assert.equal(result.profile.gold,profile.gold+5);
});

test('profile contention retry re-evaluates fresh data without double mutation',async t=>{
  const profile=starterProfile('player','playername');profile.gold=100;
  let attempts=0;
  t.mock.method(getDatabase(),'ref',()=>({
    async get(){return snapshot(profile);},
    async transaction(update){
      attempts++;
      const next=update(structuredClone(profile));
      if(attempts===1)throw Object.assign(new Error('maxretry'),{code:'MAXRETRY'});
      return {committed:true,snapshot:snapshot(next)};
    },
  }));
  const result=await transactExistingPlayer('player',value=>{value.gold+=5;return {commit:true};});
  assert.equal(attempts,2);
  assert.equal(result.profile.gold,105);
});

test('profile contention has a bounded retry budget and returns a retryable error',async t=>{
  const profile=starterProfile('player','playername');let attempts=0;
  t.mock.method(getDatabase(),'ref',()=>({
    async get(){return snapshot(profile);},
    async transaction(){attempts++;throw new Error('maxretry');},
  }));
  await assert.rejects(transactExistingPlayer('player',()=>({commit:true})),
    error=>error.status===503&&error.code==='profile-busy');
  assert.equal(attempts,3);
});

test('profile write failures other than maxretry are not blindly retried',async t=>{
  const profile=starterProfile('player','playername');let attempts=0;
  t.mock.method(getDatabase(),'ref',()=>({
    async get(){return snapshot(profile);},
    async transaction(){attempts++;throw new Error('injected-write-failure');},
  }));
  await assert.rejects(transactExistingPlayer('player',()=>({commit:true})),/injected-write-failure/);
  assert.equal(attempts,1);
});

test('profile deletion during contention retry remains missing',async t=>{
  const profile=starterProfile('player','playername');let attempts=0,mutations=0;
  t.mock.method(getDatabase(),'ref',()=>({
    async get(){return snapshot(profile);},
    async transaction(update){
      attempts++;
      if(attempts===1){update(structuredClone(profile));throw new Error('maxretry');}
      assert.equal(update(null),null);
      return {committed:true,snapshot:snapshot(null)};
    },
  }));
  await assert.rejects(transactExistingPlayer('player',()=>{mutations++;return {commit:true};}),
    error=>error.code==='profile-not-found');
  assert.equal(attempts,2);
  assert.equal(mutations,1);
});
