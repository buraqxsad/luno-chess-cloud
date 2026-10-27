'use strict';

const test=require('node:test'),assert=require('node:assert/strict');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const {google}=require('googleapis');
const logger=require('firebase-functions/logger');
const api=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');

const uid='v221_sender',at=Date.UTC(2026,9,11,12);
function setup(t){
  t.mock.method(Date,'now',()=>at);
  t.mock.method(getAuth(),'verifyIdToken',async value=>({uid:value,firebase:{sign_in_provider:'anonymous'}}));
  t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
  for(const level of ['info','warn','error'])t.mock.method(logger,level,()=>{});
  const users={};
  for(const player of [uid]){
    users[player]=api.starterProfile(player,player);
    users[player].legalConsent={uid:player,acceptedAt:1,termsVersion:api.LEGAL_TERMS_VERSION,
      privacyVersion:api.LEGAL_PRIVACY_VERSION,communityVersion:api.LEGAL_COMMUNITY_VERSION};
  }
  return memoryDatabase(t,{users});
}
async function request(route,body,id){
  const headers={authorization:'Bearer '+uid,'x-firebase-appcheck':'local-check','x-luno-request-id':id};
  let status,result;
  await api.handler({method:'POST',path:'/'+route,body,get:key=>headers[key.toLowerCase()]||''},
    {set(){return this;},status(value){status=value;return this;},json(value){result=value;}});
  return {status,body:result};
}

function play(t){
  const calls={verify:0,consume:0};
  t.mock.method(google,'androidpublisher',()=>({purchases:{
    productsv2:{async getproductpurchasev2(){calls.verify++;return {data:{
      productLineItem:[{productId:'luno_gold_1000',productOfferDetails:{consumptionState:'CONSUMPTION_STATE_YET_TO_BE_CONSUMED'}}],
      purchaseStateContext:{purchaseState:'PURCHASED'},obfuscatedExternalAccountId:api.hash(uid)
    }};}},products:{async consume(){calls.consume++;}}
  }}));
  return calls;
}
for(const malformed of [null,{productId:'luno_gold_1000',purchaseToken:'second-local-token',unexpected:true}]){
  test('restore rejects a malformed later item before fulfilling an earlier valid purchase: '+JSON.stringify(malformed),async t=>{
    const db=setup(t),calls=play(t),before=structuredClone(db.read('users/'+uid));
    const result=await request('restorePurchases',{purchases:[{productId:'luno_gold_1000',purchaseToken:'v221-local-token'},malformed]},'v221-restore-invalid');
    assert.equal(result.status,400);
    assert.equal(result.body.error,malformed===null?'invalid-purchase':'unexpected-field');
    assert.deepEqual(db.read('users/'+uid),before);
    assert.equal(db.read('purchaseClaims'),null);
    assert.deepEqual(calls,{verify:0,consume:0});
  });
}

test('valid duplicate-token restore still grants once and reports one restored purchase',async t=>{
  const db=setup(t),calls=play(t),before=db.read('users/'+uid+'/gold');
  const item={productId:'luno_gold_1000',purchaseToken:'v221-local-token'};
  const result=await request('restorePurchases',{purchases:[item,item]},'v221-restore-valid');
  assert.equal(result.status,200);assert.equal(result.body.restored,1);
  assert.equal(db.read('users/'+uid+'/gold'),before+1000);
  assert.deepEqual(calls,{verify:1,consume:1});
  const replay=await request('restorePurchases',{purchases:[item]},'v221-restore-replay');
  assert.equal(replay.status,200);assert.equal(replay.body.results[0].idempotent,true);
  assert.equal(db.read('users/'+uid+'/gold'),before+1000);
  assert.deepEqual(calls,{verify:1,consume:1});
});

test('structurally valid restore keeps item-level verification failures isolated',async t=>{
  const db=setup(t),calls=play(t),before=db.read('users/'+uid+'/gold');
  const result=await request('restorePurchases',{purchases:[
    {productId:'unknown_product',purchaseToken:'v221-unknown-token'},
    {productId:'luno_gold_1000',purchaseToken:'v221-local-token'}
  ]},'v221-restore-mixed');
  assert.equal(result.status,200);assert.equal(result.body.restored,1);
  assert.deepEqual(result.body.results[0],{productId:'unknown_product',restored:false,error:'invalid-product'});
  assert.equal(result.body.results[1].restored,true);
  assert.equal(db.read('users/'+uid+'/gold'),before+1000);
  assert.deepEqual(calls,{verify:1,consume:1});
});
