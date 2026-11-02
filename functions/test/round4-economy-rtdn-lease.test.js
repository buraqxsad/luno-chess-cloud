'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {google}=require('googleapis');
const {memoryDatabase}=require('./helpers/memory-database');
const functions=require('../index'),api=functions._test;
const uid='round4_rtdn_owner',productId='luno_gold_1000',token='round4-local-rtdn-purchase';
const eventId='round4-interrupted-refund',eventKey=api.hash(eventId).slice(0,48),tokenHash=api.hash(token);
const eventPath='billingEvents/'+eventKey;
function fixture(t,{lease,loseLockResponse=false,providerFails=false,cold=true,confirmOverride}={}){
 const at=Date.UTC(2026,10,2,12),profile=api.starterProfile(uid,'round4_rtdn_owner');let clock=at;
 t.mock.method(Date,'now',()=>clock);
 profile.gold=1250;
 profile.serverEconomy.purchaseTokens={[tokenHash]:{productId,kind:'inapp',grantGold:1000,grantGems:0,active:true,entitlementStatus:'granted'}};
 let failLock=loseLockResponse;
 const db=memoryDatabase(t,{users:{[uid]:profile},purchaseClaims:{[tokenHash]:{uid,productId,kind:'inapp',status:'complete',active:true,entitlementStatus:'granted',grantGold:1000,grantGems:0}},...(lease?{billingEvents:{[eventKey]:lease}}:{})},{cold,afterTransaction(path,count,ops){
  if(path===eventPath&&failLock&&ops.read(path)?.status==='processing'){failLock=false;throw new Error('local-runtime-interrupted-after-lock-commit');}
 }});
 let confirmations=0;
 t.mock.method(google,'androidpublisher',()=>({purchases:{voidedpurchases:{async list(){
  confirmations++;
  if(confirmOverride)await confirmOverride(confirmations);
  if(providerFails)throw new Error('local-provider-unavailable');
  return {data:{voidedPurchases:[{purchaseToken:token,voidedTimeMillis:String(at),voidedReason:1}]}};
 }}}}));
 return {db,at,advance:duration=>{clock+=duration;},confirmations:()=>confirmations,run:()=>functions.playBillingNotifications.run({id:eventId,data:{message:{json:{packageName:'com.luno.chess',eventTimeMillis:String(at),voidedPurchaseNotification:{purchaseToken:token}}}}})};
}

for(const cold of [true,false])test(`a refund retry cannot ACK an interrupted processing lease (cold=${cold})`,async t=>{
 const f=fixture(t,{loseLockResponse:true,cold});
 await assert.rejects(f.run(),/local-runtime-interrupted-after-lock-commit/);
 assert.equal(f.db.read(eventPath+'/status'),'processing','The durable lease outlives the interrupted invocation.');
 assert.equal(f.confirmations(),0);
 await assert.rejects(f.run(),{code:'billing-event-in-progress'},'A normal return acknowledges Pub/Sub. A pending lease must keep retry delivery alive.');
 assert.equal(f.confirmations(),0);
 assert.equal(f.db.read('users/'+uid+'/gold'),1250);
 assert.equal(f.db.read('purchaseClaims/'+tokenHash+'/voided'),null);
 assert.equal(f.db.read(eventPath+'/status'),'processing');
 f.advance(300000);
 assert.equal((await f.run()).revoked,true,'Preserving retries must allow takeover when the abandoned lease expires.');
 assert.equal(f.db.read(eventPath+'/status'),'complete');
 assert.equal(f.db.read('users/'+uid+'/gold'),250);
 assert.equal(f.db.read(eventPath+'/attempts'),2);
 assert.deepEqual(await f.run(),{duplicate:true,eventKey});
 assert.equal(f.confirmations(),1,'The eventual duplicate must not debit or confirm again.');
});

test('an expired interrupted refund lease is reclaimed and the currency is reversed once',async t=>{
 const at=Date.UTC(2026,10,2,12),f=fixture(t,{lease:{status:'processing',startedAt:at-300000,attempts:1}});
 assert.equal((await f.run()).revoked,true);
 assert.equal(f.db.read('users/'+uid+'/gold'),250);
 assert.equal(f.db.read(eventPath+'/status'),'complete');
 assert.equal(f.db.read(eventPath+'/attempts'),2);
 assert.deepEqual(await f.run(),{duplicate:true,eventKey});
 assert.equal(f.confirmations(),1);
 assert.equal(f.db.read('users/'+uid+'/gold'),250);
});

test('a completed event remains a successful duplicate with no provider call or second debit',async t=>{
 const f=fixture(t,{lease:{status:'complete',completedAt:1,attempts:2}}),before=structuredClone(f.db.data);
 assert.deepEqual(await f.run(),{duplicate:true,eventKey});
 assert.equal(f.confirmations(),0);
 assert.deepEqual(f.db.data,before);
});

test('a fresh refund event confirms provider evidence and reverses the known grant',async t=>{
 const f=fixture(t);
 assert.equal((await f.run()).revoked,true);
 assert.equal(f.db.read(eventPath+'/status'),'complete');
 assert.equal(f.db.read('users/'+uid+'/gold'),250);
 assert.equal(f.db.read('purchaseClaims/'+tokenHash+'/voided'),true);
 assert.equal(f.confirmations(),1);
});

test('an ordinary provider failure remains failed and retryable rather than becoming a completed event',async t=>{
 const f=fixture(t,{providerFails:true});
 await assert.rejects(f.run(),{code:'play-billing-unavailable'});
 assert.equal(f.db.read(eventPath+'/status'),'failed');
 assert.equal(f.db.read('users/'+uid+'/gold'),1250);
 await assert.rejects(f.run(),{code:'play-billing-unavailable'});
 assert.equal(f.db.read(eventPath+'/attempts'),2);
 assert.equal(f.confirmations(),2);
});

function gate(){
 let enter,release;
 return {entered:new Promise(resolve=>{enter=resolve;}),resume:new Promise(resolve=>{release=resolve;}),enter:()=>enter(),release:()=>release()};
}

test('an expired worker failure cannot overwrite the takeover worker completed marker',async t=>{
 const first=gate();
 const f=fixture(t,{confirmOverride:async count=>{if(count===1){first.enter();await first.resume;throw new Error('local-expired-worker-provider-failure');}}});
 const old=f.run(),settled=old.then(value=>({value}),error=>({error}));let complete;
 try{
  await first.entered;
  f.advance(300000);
  assert.equal((await f.run()).revoked,true);
  complete=structuredClone(f.db.read(eventPath));
  assert.equal(complete.status,'complete');
  assert.equal(complete.attempts,2);
 }finally{first.release();}
 assert.equal((await settled).error?.code,'play-billing-unavailable');
 assert.deepEqual(f.db.read(eventPath),complete,'Only the takeover worker owns completion/failure publication after lease expiry.');
 assert.deepEqual(await f.run(),{duplicate:true,eventKey});
 assert.equal(f.confirmations(),2);
 assert.equal(f.db.read('users/'+uid+'/gold'),250);
});

test('an expired worker cannot ACK success while its takeover worker still owns processing',async t=>{
 const first=gate(),second=gate();
 const f=fixture(t,{confirmOverride:async count=>{
  if(count===1){first.enter();await first.resume;}
  if(count===2){second.enter();await second.resume;}
 }});
 const old=f.run(),oldSettled=old.then(value=>({value}),error=>({error}));let newer,newerSettled,newerResult;
 try{
  await first.entered;
  f.advance(300000);
  newer=f.run();newerSettled=newer.then(value=>({value}),error=>({error}));
  await second.entered;
  const owned=structuredClone(f.db.read(eventPath));
  assert.equal(owned.status,'processing');assert.equal(owned.attempts,2);
  first.release();
  assert.equal((await oldSettled).error?.code,'billing-event-lease-lost','An obsolete worker must reject rather than acknowledge the current delivery.');
  assert.deepEqual(f.db.read(eventPath),owned,'Old completion and its catch path must leave the takeover lease intact.');
 }finally{first.release();second.release();if(newerSettled)newerResult=await newerSettled;await oldSettled;}
 assert.equal(newerResult.value?.voided,true);
 assert.equal(f.db.read(eventPath+'/status'),'complete');
 assert.equal(f.db.read('users/'+uid+'/gold'),250,'Concurrent refund workers still reverse currency exactly once.');
});
