'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {getDatabase}=require('firebase-admin/database');
const api=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');
const midnight=Date.UTC(2026,9,29),day=86400000;

for(const at of [midnight-1,midnight,midnight+1]){
  test('two independent request IDs racing at UTC '+at+' pay one daily source',async t=>{
    const uid='v239_two_clients_'+at;
    t.mock.method(Date,'now',()=>at);
    const db=memoryDatabase(t,{users:{[uid]:api.starterProfile(uid,uid)}});
    const replies=await Promise.all(Array.from({length:12},(_,i)=>
      api.claimDailyReward({uid,body:{},requestId:'v239-device-'+i})));
    assert.equal(replies.filter(r=>r.granted).length,1);
    const profile=db.read('users/'+uid);
    assert.equal(profile.serverEconomy.daily.streak,1);
    assert.equal(profile.serverEconomy.daily.lastClaimAt,at);
    assert.equal(Object.keys(profile.serverEconomy.claims).length,1);
    const saved=structuredClone(profile);
    await Promise.all(Array.from({length:12},(_,i)=>
      api.claimDailyReward({uid,body:{},requestId:'v239-device-'+i})));
    assert.deepEqual(db.read('users/'+uid),saved,'Response replay cannot mint or mutate the profile.');
  });
}

test('daily commit followed by lost durable response cannot grant twice on retry',async t=>{
  const uid='v239_daily_lost_response';
  t.mock.method(Date,'now',()=>midnight);
  let dropped=false;
  const db=memoryDatabase(t,{users:{[uid]:api.starterProfile(uid,uid)}},{
    afterTransaction(path,count,store){
      if(!dropped&&path.startsWith('serverRequests/'+uid+'/')&&store.read(path)?.status==='complete'){
        dropped=true;throw new Error('v239-simulated-response-loss');
      }
    },
  });
  const context={uid,body:{},requestId:'v239-lost-daily'};
  await assert.rejects(api.claimDailyReward(context),/v239-simulated-response-loss/);
  assert.equal(dropped,true);
  const committed=structuredClone(db.read('users/'+uid));
  assert.equal(committed.serverEconomy.daily.streak,1);
  assert.equal(Object.keys(committed.serverEconomy.claims).length,1);
  const retry=await api.claimDailyReward(context);
  assert.equal(retry.granted,false,'The committed ledger authorizes no second grant.');
  assert.deepEqual(db.read('users/'+uid),committed);
});

test('a request delayed across two UTC boundaries cannot rewind either committed claim',async t=>{
  const uid='v239_daily_two_midnights';
  let at=midnight-1;
  t.mock.method(Date,'now',()=>at);
  const db=memoryDatabase(t,{users:{[uid]:api.starterProfile(uid,uid)}});
  const database=getDatabase(),ref=database.ref.bind(database);
  let held=false,entered,release;
  const gate=new Promise(resolve=>{entered=resolve;});
  const resumed=new Promise(resolve=>{release=resolve;});
  t.mock.method(database,'ref',(path='',...args)=>{
    const node=ref(path,...args);
    return {...node,async get(){
      const snapshot=await node.get();
      if(path==='users/'+uid&&!held){held=true;entered();await resumed;}
      return snapshot;
    }};
  });
  const request=requestId=>({uid,body:{},requestId});
  const old=api.claimDailyReward(request('v239-held-old'));
  let latest;
  try{
    await gate;
    at=midnight;
    assert.deepEqual((await api.claimDailyReward(request('v239-new-day'))).reward,{gold:200});
    at=midnight+day;
    assert.deepEqual((await api.claimDailyReward(request('v239-next-day'))).reward,{gold:300});
    latest=structuredClone(db.read('users/'+uid));
  }finally{release();}
  const stale=await old;
  assert.equal(stale.granted,false);
  assert.equal(stale.state.economy.daily.lastClaimAt,midnight+day);
  assert.equal(stale.state.economy.daily.nextClaimAt,midnight+2*day);
  assert.deepEqual(db.read('users/'+uid),latest);
  assert.equal(Object.keys(latest.serverEconomy.claims).length,2);
});
