'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {getDatabase}=require('firebase-admin/database');
const {memoryDatabase}=require('./helpers/memory-database');
const api=require('../index')._test;
const uid='round5_pass_rollover_owner',rollover=api.seasonBounds(8).startAt;
function fixture(t,{cold=true,at=rollover-1}={}){
 let clock=at;
 t.mock.method(Date,'now',()=>clock);
 const profile=api.starterProfile(uid,'round5_pass_owner');profile.gems=2000;
 api.syncServerPass(profile,clock);
 const db=memoryDatabase(t,{users:{[uid]:profile},usernames:{round5_pass_owner:uid}},{cold});
 const database=getDatabase(),original=database.ref.bind(database);
 let held=false,enter,release;
 const entered=new Promise(resolve=>{enter=resolve;}),resumed=new Promise(resolve=>{release=resolve;});
 t.mock.method(database,'ref',(path='',...args)=>{
  const ref=original(path,...args);
  if(path!=='users/'+uid)return ref;
  return {...ref,async get(){
   const snapshot=await ref.get();
   if(!held){held=true;enter();await resumed;}
   return snapshot;
  }};
 });
 return {db,entered,release,setClock:value=>{clock=value;},refresh:()=>api.getPlayerState({uid}),buy:()=>api.purchaseSoftItem({uid,requestId:'round5-new-pass',body:{itemId:'pass:premium',seasonId:api.periodSnapshot(clock).seasonId}})};
}
for(const cold of [true,false])test(`a delayed prior-season refresh preserves a newly purchased current Premium Pass (cold=${cold})`,async t=>{
 const f=fixture(t,{cold}),old=f.refresh(),settled=old.then(value=>({value}),error=>({error}));let paidPass,purchase;
 try{
  await f.entered;
  f.setClock(rollover);
  purchase=await f.buy();
  assert.equal(purchase.purchased,true);
  paidPass=structuredClone(f.db.read('users/'+uid+'/passState'));
  assert.equal(paidPass.season,8);assert.equal(paidPass.premium,true);
 }finally{f.release();}
 const result=await settled;assert.equal(result.error,undefined);
 const replay=await f.buy().then(value=>({value}),error=>({error}));
 t.diagnostic(JSON.stringify({paidSeason:paidPass.season,savedSeason:f.db.read('users/'+uid+'/passState/season'),savedPremium:f.db.read('users/'+uid+'/passState/premium'),responsePremium:result.value.state.passState.premium,remainingGems:f.db.read('users/'+uid+'/gems'),purchaseReplayError:replay.error?.code||null}));
 assert.deepEqual(f.db.read('users/'+uid+'/passState'),paidPass,'A read request begun before rollover must not erase a later committed paid entitlement.');
 assert.equal(result.value.state.passState.premium,true);
 assert.equal(f.db.read('users/'+uid+'/gems'),1550,'The paid debit remains exactly once.');
 assert.equal(replay.error,undefined);assert.equal(replay.value.idempotent,true);assert.equal(replay.value.state.passState.premium,true);
});
test('a delayed same-season refresh still preserves a concurrently purchased Pass',async t=>{
 const f=fixture(t,{at:rollover+1000}),old=f.refresh(),settled=old.then(value=>({value}),error=>({error}));let pass;
 try{await f.entered;await f.buy();pass=structuredClone(f.db.read('users/'+uid+'/passState'));}finally{f.release();}
 const result=await settled;assert.equal(result.error,undefined);
 assert.deepEqual(f.db.read('users/'+uid+'/passState'),pass);assert.equal(result.value.state.passState.premium,true);
});
test('a normal current refresh expires the previous season Pass without granting another season',async t=>{
 let clock=rollover-1;t.mock.method(Date,'now',()=>clock);
 const profile=api.starterProfile(uid,'round5_pass_owner');profile.gems=2000;
 const db=memoryDatabase(t,{users:{[uid]:profile},usernames:{round5_pass_owner:uid}});
 assert.equal((await api.purchaseSoftItem({uid,requestId:'round5-previous-pass',body:{itemId:'pass:premium',seasonId:'s7'}})).purchased,true);
 clock=rollover;
 const result=await api.getPlayerState({uid});
 assert.equal(result.state.passState.season,8);assert.equal(result.state.passState.premium,false);assert.equal(db.read('users/'+uid+'/gems'),1550);
});
test('a historical operational Pass sync cannot erase a canonical current-season paid Pass',t=>{
 t.mock.method(Date,'now',()=>rollover);
 const profile=api.starterProfile(uid,'round5_pass_owner');
 api.syncServerPass(profile,rollover);
 Object.assign(profile.passState,{premium:true,premiumSource:'soft_purchase',level:4,xp:91,claimed:{free:{1:rollover},premium:{1:rollover}},unlocks:['emoji:laugh']});
 const before=structuredClone(profile.passState),synced=api.syncServerPass(profile,rollover-1);
 assert.deepEqual(profile.passState,before);assert.equal(synced.periods.seasonId,'s8');
});
for(const key of ['ranked-s9-v2','client-fake-s9'])test(`a future Pass ${key} is still discarded`,t=>{
 t.mock.method(Date,'now',()=>rollover);
 const profile=api.starterProfile(uid,'round5_pass_owner');
 Object.assign(profile.passState,{seasonKey:key,season:9,premium:true,level:30});
 const synced=api.syncServerPass(profile,rollover);
 assert.equal(synced.pass.season,8);assert.equal(synced.pass.premium,false);assert.equal(synced.pass.level,0);
});
