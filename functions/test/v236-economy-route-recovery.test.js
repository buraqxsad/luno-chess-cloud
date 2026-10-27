'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const api=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');

const uid='v236-route-owner',at=Date.UTC(2026,9,22,12);
const context=requestId=>({uid,body:{},requestId});
function setup(t,profile){
  t.mock.method(Date,'now',()=>at);
  return memoryDatabase(t,{users:{[uid]:profile}});
}

test('onboarding retry cannot mint against an orphaned committed credit',async t=>{
  const p=api.starterProfile(uid,'v236_route_owner');
  const first=api.applyRewardClaim(p,{uid,sourceType:'onboarding_reward',sourceId:'v1',reward:{gold:500},at});
  delete p.serverEconomy.claims[first.idempotencyKey];
  const db=setup(t,p),before=structuredClone(db.read('users/'+uid));
  await assert.rejects(api.claimOnboardingReward(context('v236-orphan-welcome')),/receipt.*incomplete/i);
  assert.deepEqual(db.read('users/'+uid),before);
});

test('daily retry with missing cursor and claim preserves the retained credit and profile',async t=>{
  const p=api.starterProfile(uid,'v236_route_owner');
  const first=api.applyDailyRewardClaim(p,uid,at);
  delete p.serverEconomy.claims[first.idempotencyKey];
  delete p.serverEconomy.daily;
  delete p.inventory.lastDailyReward;
  delete p.inventory.dailyStreak;
  const db=setup(t,p),before=structuredClone(db.read('users/'+uid));
  await assert.rejects(api.claimDailyReward(context('v236-orphan-daily')),/receipt.*incomplete/i);
  assert.deepEqual(db.read('users/'+uid),before);
});

test('valid onboarding delivery survives request-cache loss and remains paid exactly once',async t=>{
  const p=api.starterProfile(uid,'v236_route_owner'),db=setup(t,p);
  const first=await api.claimOnboardingReward(context('v236-welcome-delivery'));
  assert.equal(first.granted,true);
  const paid=structuredClone(db.read('users/'+uid));
  assert.equal(paid.gold,p.gold+500);
  db.write('serverRequests/'+uid,null);
  const replay=await api.claimOnboardingReward(context('v236-welcome-delivery'));
  assert.equal(replay.granted,false);
  assert.equal(replay.idempotent,true);
  assert.deepEqual(db.read('users/'+uid),paid);
});
