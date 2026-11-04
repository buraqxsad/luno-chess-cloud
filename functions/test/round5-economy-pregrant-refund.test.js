'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {google}=require('googleapis');
const logger=require('firebase-functions/logger');
const {memoryDatabase}=require('./helpers/memory-database');
const functions=require('../index'),api=functions._test;
const uid='round5_pregrant_refund_owner',productId='luno_gold_1000',token='round5-local-pregrant-refund',key=api.hash(token);
function fixture(t,{cold=true}={}){
 const profile=api.starterProfile(uid,'round5_refund_owner'),before=structuredClone(profile);
 const db=memoryDatabase(t,{users:{[uid]:profile}},{cold});let gets=0,failRegistrationRefresh=true,refunded=false,consumes=0;
 t.mock.method(logger,'error',()=>{});
 t.mock.method(google,'androidpublisher',()=>({purchases:{
  productsv2:{async getproductpurchasev2(){
   gets++;
   if(gets===2&&failRegistrationRefresh)throw new Error('local-provider-unavailable-after-registration');
   return {data:{productLineItem:[{productId,productOfferDetails:{consumptionState:'CONSUMPTION_STATE_YET_TO_BE_CONSUMED'}}],purchaseStateContext:{purchaseState:refunded?'CANCELED':'PURCHASED'},obfuscatedExternalAccountId:api.hash(uid)}};
  }},
  products:{async consume(){consumes++;}},
  voidedpurchases:{async list(){return {data:{voidedPurchases:refunded?[{purchaseToken:token,voidedTimeMillis:String(Date.now()),voidedReason:1}]:[]}};}},
 }}));
 const eventId='round5-ungranted-refund-event',eventKey=api.hash(eventId).slice(0,48);
 return {db,before,eventKey,consumes:()=>consumes,refund:()=>{refunded=true;},repairProvider:()=>{failRegistrationRefresh=false;},
  buy:()=>api.fulfillPurchase(uid,{productId,purchaseToken:token}),
  notify:()=>functions.playBillingNotifications.run({id:eventId,data:{message:{json:{packageName:'com.luno.chess',eventTimeMillis:String(Date.now()),voidedPurchaseNotification:{purchaseToken:token}}}}})};
}
for(const cold of [true,false])test(`a confirmed refund completes after fulfillment fails before the first grant (cold=${cold})`,async t=>{
 const f=fixture(t,{cold});
 await assert.rejects(f.buy(),{code:'play-billing-unavailable'});
 assert.equal(f.db.read('purchaseClaims/'+key+'/status'),'reconcile-required');
 assert.equal(f.db.read('users/'+uid+'/serverEconomy/purchaseTokens/'+key),null);
 assert.equal(f.db.read('users/'+uid+'/gold'),f.before.gold);
 f.refund();
 const refunded=await f.notify();assert.equal(refunded.ungranted,true);
 assert.equal(f.db.read('billingEvents/'+f.eventKey+'/status'),'complete');
 assert.equal(f.db.read('purchaseClaims/'+key+'/voided'),true);
 assert.equal(f.db.read('users/'+uid+'/serverEconomy/billingReversals/'+key+'/ungranted'),true);
 assert.equal(f.db.read('users/'+uid+'/gold'),f.before.gold);assert.equal(f.consumes(),0);
 await assert.rejects(f.buy(),{code:'purchase-revoked'});
 assert.equal((await f.notify()).duplicate,true);
});
test('a temporary pre-grant provider failure still recovers an unrefunded purchase once',async t=>{
 const f=fixture(t);await assert.rejects(f.buy(),{code:'play-billing-unavailable'});f.repairProvider();
 assert.equal((await f.buy()).entitlementGranted,true);assert.equal((await f.buy()).idempotent,true);
 assert.equal(f.db.read('users/'+uid+'/gold'),f.before.gold+1000);assert.equal(f.consumes(),1);
});
test('a missing receipt for a completed consumable still fails closed',t=>{
 const profile=api.starterProfile(uid,'round5_refund_owner'),before=structuredClone(profile);
 assert.equal(api.applyVoidedPurchaseRevocation(profile,{uid,productId,status:'complete'},key,Date.now()).error,'purchase-receipt-invalid');
 assert.deepEqual(profile,before);
});
