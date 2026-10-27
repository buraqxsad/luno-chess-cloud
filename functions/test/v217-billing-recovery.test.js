'use strict';

const test=require('node:test'),assert=require('node:assert/strict');
const {google}=require('googleapis');
const logger=require('firebase-functions/logger');
const {memoryDatabase}=require('./helpers/memory-database');
const {fulfillPurchase,starterProfile,hash}=require('../index')._test;
const uid='v217_billing_owner',productId='luno_gold_1000',token='v217-local-purchase-token';
const claimPath='purchaseClaims/'+hash(token);

function playFixture(t,{consumed=false,lostConsumeResponse=false}={}){
  const calls={get:0,consume:0};
  t.mock.method(logger,'error',()=>{});
  t.mock.method(google,'androidpublisher',()=>({purchases:{
    productsv2:{async getproductpurchasev2(){calls.get++;return {data:{
      productLineItem:[{productId,productOfferDetails:{consumptionState:consumed?'CONSUMPTION_STATE_CONSUMED':'CONSUMPTION_STATE_YET_TO_BE_CONSUMED'}}],
      purchaseStateContext:{purchaseState:'PURCHASED'},obfuscatedExternalAccountId:hash(uid)
    }};}},
    products:{async consume(){
      calls.consume++;
      if(consumed)throw new Error('already-consumed');
      consumed=true;
      if(lostConsumeResponse)throw new Error('response-lost-after-consume');
    }}
  }}));
  return calls;
}
function seed(){return {users:{[uid]:starterProfile(uid,'v217_billing')}};}

for(const lostAt of ['consume-response','completion-write'])test(`consumed purchase recovers after lost ${lostAt} without another grant or consume`,async t=>{
  let failCompletion=lostAt==='completion-write';
  const db=memoryDatabase(t,seed(),{beforeTransaction(path,count,ops){
    if(path===claimPath&&ops.read(path)?.status==='granted'&&failCompletion){failCompletion=false;throw new Error('completion-unavailable');}
  }});
  const calls=playFixture(t,{lostConsumeResponse:lostAt==='consume-response'}),before=db.read('users/'+uid+'/gold');
  await assert.rejects(fulfillPurchase(uid,{productId,purchaseToken:token}));
  assert.equal(db.read('users/'+uid+'/gold'),before+1000);
  assert.equal(db.read(claimPath+'/status'),'reconcile-required');
  const replay=await fulfillPurchase(uid,{productId,purchaseToken:token});
  assert.equal(replay.idempotent,true);
  assert.equal(db.read(claimPath+'/status'),'complete');
  assert.equal(db.read('users/'+uid+'/gold'),before+1000);
  assert.equal(calls.consume,1);
});

test('consumed token without a durable owned grant cannot mint currency',async t=>{
  const db=memoryDatabase(t,seed()),before=db.read('users/'+uid),calls=playFixture(t,{consumed:true});
  await assert.rejects(fulfillPurchase(uid,{productId,purchaseToken:token}),{code:'purchase-receipt-invalid'});
  assert.deepEqual(db.read('users/'+uid),before);
  assert.equal(calls.consume,0);
});
