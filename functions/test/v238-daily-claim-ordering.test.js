'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {getDatabase}=require('firebase-admin/database');
const api=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');

const uid='v238_daily_owner',midnight=Date.UTC(2026,9,29);
const context=requestId=>({uid,body:{},requestId});

test('a pre-midnight request cannot rewind a newer committed daily claim',async t=>{
  let at=midnight-1;
  t.mock.method(Date,'now',()=>at);
  const db=memoryDatabase(t,{users:{[uid]:api.starterProfile(uid,'v238_daily_owner')}});
  const database=getDatabase(),reference=database.ref.bind(database);
  let blocked=false,entered,release;
  const held=new Promise(resolve=>{entered=resolve;});
  const resume=new Promise(resolve=>{release=resolve;});
  t.mock.method(database,'ref',(path='',...args)=>{
    const node=reference(path,...args);
    return {...node,async get(){
      const snapshot=await node.get();
      if(path==='users/'+uid&&!blocked){blocked=true;entered();await resume;}
      return snapshot;
    }};
  });
  const earlier=api.claimDailyReward(context('v238-before-midnight'));
  let latest,committed;
  try{
    await held;
    at=midnight;
    latest=await api.claimDailyReward(context('v238-after-midnight'));
    assert.equal(latest.granted,true);
    committed=structuredClone(db.read('users/'+uid));
  }finally{release();}
  const stale=await earlier;
  assert.equal(stale.granted,false,'A stale server timestamp cannot authorize an older unclaimed day.');
  assert.equal(stale.state.economy.daily.canClaim,false);
  assert.equal(stale.state.economy.daily.lastClaimAt,midnight);
  assert.equal(stale.state.economy.daily.nextClaimAt,midnight+86400000);
  assert.deepEqual(db.read('users/'+uid),committed,'Keep the latest streak, cursor, ledger and balance.');
  assert.equal(stale.state.gold,latest.state.gold);
  assert.equal(stale.state.stateRevision,latest.state.stateRevision);
  assert.equal(Object.keys(committed.serverEconomy.claims).length,1);

  at=midnight+86400000;
  const next=await api.claimDailyReward(context('v238-next-daily'));
  assert.equal(next.granted,true);
  assert.deepEqual(next.reward,{gold:300});
  assert.equal(next.state.economy.daily.streak,2);
});

test('a future legacy client daily timestamp does not become a trusted server-time floor',()=>{
  const profile=api.starterProfile(uid,'v238_daily_owner');
  profile.inventory.lastDailyReward=midnight+7*86400000;
  profile.inventory.dailyStreak=3;
  const result=api.applyDailyRewardClaim(profile,uid,midnight);
  assert.equal(result.granted,true);
  assert.deepEqual(result.reward,{gold:200});
  assert.equal(result.daily.lastClaimAt,midnight);
  assert.equal(result.daily.streak,1);
});
