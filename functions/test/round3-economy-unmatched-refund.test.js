'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {google}=require('googleapis');
const {getDatabase}=require('firebase-admin/database');
const logger=require('firebase-functions/logger');
const {memoryDatabase}=require('./helpers/memory-database');
const functions=require('../index'),api=functions._test;
const uid='round3_unmatched_refund_owner',productId='luno_gold_1000',token='round3-unmatched-refund-token',key=api.hash(token);
function fixture(t,{refundBeforeClaim=false,cold=true,foreignAccount=false,wrongProduct=false}={}){
 let purchased=true,consumed=false,gets=0,consumes=0,hold,release;
 const entered=new Promise(resolve=>{hold=resolve;}),resume=new Promise(resolve=>{release=resolve;});
 const profile=api.starterProfile(uid,'round3_refund_owner'),before=structuredClone(profile);
 const db=memoryDatabase(t,{users:{[uid]:profile}},{cold});
 t.mock.method(logger,'error',()=>{});
 t.mock.method(google,'androidpublisher',()=>({purchases:{
  productsv2:{async getproductpurchasev2(){
   gets++;
   const data={productLineItem:[{productId:wrongProduct?'luno_gem_80':productId,productOfferDetails:{consumptionState:consumed?'CONSUMPTION_STATE_CONSUMED':'CONSUMPTION_STATE_YET_TO_BE_CONSUMED'}}],purchaseStateContext:{purchaseState:purchased?'PURCHASED':'CANCELED'},obfuscatedExternalAccountId:api.hash(foreignAccount?'round3_foreign_owner':uid)};
   if(refundBeforeClaim&&gets===1){hold();await resume;}
   return {data};
  }},
  products:{async consume(){consumes++;if(consumed)throw new Error('already-consumed');if(!purchased)throw new Error('refunded-purchase-cannot-be-consumed');consumed=true;}},
  voidedpurchases:{async list(){return {data:{voidedPurchases:purchased?[]:[{purchaseToken:token,voidedTimeMillis:String(Date.now()),voidedReason:1}]}};}},
 }}));
 return {db,before,entered,release,refund(){purchased=false;},consumeExternally(){consumed=true;},getCount:()=>gets,consumeCount:()=>consumes,
  invoke:()=>api.fulfillPurchase(uid,{productId,purchaseToken:token}),
  notification:()=>({packageName:'com.luno.chess',eventTimeMillis:String(Date.now()),voidedPurchaseNotification:{purchaseToken:token}})};
}

for(const cold of [true,false])test(`a refund arriving before first claim registration cannot be lost behind a stale purchased lookup (cold=${cold})`,async t=>{
 const f=fixture(t,{refundBeforeClaim:true,cold});
 const eventId='round3-preclaim-refund-event',eventKey=api.hash(eventId).slice(0,48);
 const pending=f.invoke(),settled=pending.then(value=>({value}),error=>({error}));let notificationResult;
 try{
  await f.entered;
  assert.equal(f.db.read('purchaseClaims/'+key),null,'The initial provider lookup is in flight before any global claim.');
  f.refund();
  notificationResult=await functions.playBillingNotifications.run({id:eventId,data:{message:{json:f.notification()}}});
  assert.equal(notificationResult.deferred,true);
  assert.equal(f.db.read('billingSignals/unmatched/'+eventKey+'/status'),'awaiting-client-claim');
  assert.equal(f.db.read('billingEvents/'+eventKey+'/status'),'complete','The only refund event is acknowledged despite deferring it.');
 }finally{f.release();}
 const outcome=await settled;
 assert.ok(outcome.error,'A provider-refunded purchase must not complete.');
 await assert.rejects(f.invoke(),{code:'purchase-not-complete'});
 assert.deepEqual(await functions.playBillingNotifications.run({id:eventId,data:{message:{json:f.notification()}}}),{duplicate:true,eventKey},'Redelivery of the only refund does not retry deferred reconciliation.');
 assert.equal(f.db.read('users/'+uid+'/gold'),f.before.gold,'The only refund was deferred before ownership existed. Later rejected retries cannot repair a stale unbacked grant.');
 assert.equal(f.db.read('users/'+uid+'/serverEconomy/purchaseTokens/'+key),null,'No currency receipt may be minted from the stale pre-registration provider response.');
 assert.equal(f.consumeCount(),0,'Fresh provider proof after claim registration must reject before grant/consume.');
});

test('an unrefunded first consumable purchase grants and consumes once across replay',async t=>{
 const f=fixture(t);
 assert.equal((await f.invoke()).entitlementGranted,true);
 assert.equal((await f.invoke()).idempotent,true);
 assert.equal(f.db.read('users/'+uid+'/gold'),f.before.gold+1000);
 assert.equal(f.consumeCount(),1);
});

test('an already canceled first consumable lookup creates no claim or grant',async t=>{
 const f=fixture(t);f.refund();
 await assert.rejects(f.invoke(),{code:'purchase-not-complete'});
 assert.deepEqual(f.db.read('users/'+uid),f.before);
 assert.equal(f.db.read('purchaseClaims/'+key),null);
 assert.equal(f.consumeCount(),0);
});

for(const guard of ['owner','product'])test(`a first consumable ${guard} mismatch cannot register a claim or mint currency`,async t=>{
 const f=fixture(t,{foreignAccount:guard==='owner',wrongProduct:guard==='product'});
 await assert.rejects(f.invoke(),{code:guard==='owner'?'account-mismatch':'purchase-product-mismatch'});
 assert.deepEqual(f.db.read('users/'+uid),f.before);
 assert.equal(f.db.read('purchaseClaims/'+key),null);
 assert.equal(f.consumeCount(),0);
});

test('a refund after registration remains fenced even while initial fulfillment is suspended',async t=>{
 const f=fixture(t),database=getDatabase(),original=database.ref.bind(database);
 let held=false,enter,release;
 const entered=new Promise(resolve=>{enter=resolve;}),resume=new Promise(resolve=>{release=resolve;});
 t.mock.method(database,'ref',(path='',...args)=>{
  const ref=original(path,...args);if(path!=='purchaseClaims/'+key)return ref;
  return {...ref,async transaction(...transactionArgs){
   const result=await ref.transaction(...transactionArgs);
   if(!held&&result.snapshot.val()?.status==='verified'){held=true;enter();await resume;}
   return result;
  }};
 });
 const pending=f.invoke(),settled=pending.then(value=>({value}),error=>({error}));
 try{
  await entered;
  assert.equal(f.db.read('purchaseClaims/'+key+'/status'),'verified');
  f.refund();
  const result=await api.reconcilePlayNotification(f.notification(),'round3-post-registration-refund');
  assert.equal(result.ungranted,true);
  assert.equal(f.db.read('users/'+uid+'/serverEconomy/billingReversals/'+key+'/ungranted'),true);
 }finally{release();}
 assert.ok((await settled).error);
 assert.equal(f.db.read('users/'+uid+'/gold'),f.before.gold);
 assert.equal(f.db.read('users/'+uid+'/serverEconomy/purchaseTokens/'+key),null);
 assert.equal(f.db.read('purchaseClaims/'+key+'/voided'),true);
 assert.equal(f.consumeCount(),0);
});


test('fresh consumed state after claim registration cannot mint an unowned grant from the old unconsumed response',async t=>{
 const f=fixture(t),database=getDatabase(),original=database.ref.bind(database);
 let held=false,enter,release;
 const entered=new Promise(resolve=>{enter=resolve;}),resume=new Promise(resolve=>{release=resolve;});
 t.mock.method(database,'ref',(path='',...args)=>{
  const ref=original(path,...args);if(path!=='purchaseClaims/'+key)return ref;
  return {...ref,async transaction(...transactionArgs){
   const result=await ref.transaction(...transactionArgs);
   if(!held&&result.snapshot.val()?.status==='verified'){held=true;enter();await resume;}
   return result;
  }};
 });
 const pending=f.invoke(),settled=pending.then(value=>({value}),error=>({error}));
 try{
  await entered;
  assert.equal(f.db.read('users/'+uid+'/serverEconomy/purchaseTokens/'+key),null);
  // The provider consumes the purchase outside this fulfillment. The server
  // has no committed grant, so its consumed-token recovery contract forbids
  // inventing one from the earlier not-yet-consumed response.
  f.consumeExternally();
 }finally{release();}
 const outcome=await settled;
 assert.equal(f.db.read('users/'+uid+'/gold'),f.before.gold);
 assert.equal(outcome.error?.code,'purchase-receipt-invalid');
 assert.equal(f.db.read('users/'+uid+'/serverEconomy/purchaseTokens/'+key),null);
 assert.equal(f.consumeCount(),0);
});
