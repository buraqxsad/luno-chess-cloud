'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {google}=require('googleapis');
const logger=require('firebase-functions/logger');
const {getDatabase}=require('firebase-admin/database');
const {memoryDatabase}=require('./helpers/memory-database');
const api=require('../index')._test;
const uid='round2_inactive_owner',productId='luno_premium_month',token='round2-owned-subscription-token',key=api.hash(token);
function fixture(t,{status='SUBSCRIPTION_STATE_ON_HOLD',providerExpiry=Date.now()+86400000,otherActive=false,foreignAccount=false,existing=true,getHook}={}){
 const originalExpiry=Date.now()+86400000,profile=api.starterProfile(uid,'round2_inactive');
 const claim={uid,productId,kind:'subs',status:'complete',active:true,expiry:originalExpiry,entitlementStatus:'SUBSCRIPTION_STATE_ACTIVE',claimRevision:4};
 if(existing){
  profile.premiumUntil=originalExpiry;profile.premiumSince=Date.now()-86400000;
  profile.serverEconomy.purchaseTokens={[key]:{productId,kind:'subs',expiry:originalExpiry,active:true,entitlementStatus:'SUBSCRIPTION_STATE_ACTIVE'}};
 }
 const claims=existing?{[key]:claim}:{};let preservedExpiry=null;
 if(otherActive){
  preservedExpiry=Date.now()+3*86400000;profile.premiumUntil=preservedExpiry;
  const otherKey=api.hash('round2-other-active-subscription');
  claims[otherKey]={uid,productId:'luno_premium_year',kind:'subs',status:'complete',active:true,expiry:preservedExpiry,entitlementStatus:'SUBSCRIPTION_STATE_ACTIVE',claimRevision:7};
 }
 const db=memoryDatabase(t,{users:{[uid]:profile},purchaseClaims:claims});let gets=0;
 const control={status,providerExpiry,foreignAccount};
 t.mock.method(logger,'error',()=>{});
 t.mock.method(google,'androidpublisher',()=>({purchases:{subscriptionsv2:{async get(){gets++;const data={
  lineItems:[{productId,expiryTime:new Date(control.providerExpiry).toISOString()}],subscriptionState:control.status,
  acknowledgementState:'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',externalAccountIdentifiers:{obfuscatedExternalAccountId:api.hash(control.foreignAccount?'round2_foreign_owner':uid)}
 };if(getHook)await getHook(control);return {data};}}}}));
 return {db,control,originalExpiry,preservedExpiry,gets:()=>gets,invoke:()=>api.fulfillPurchase(uid,{productId,purchaseToken:token})};
}
for(const status of ['SUBSCRIPTION_STATE_ON_HOLD','SUBSCRIPTION_STATE_EXPIRED'])test(`fresh owned ${status} verification reconciles the previously active token without waiting for RTDN`,async t=>{
 const f=fixture(t,{status,providerExpiry:status==='SUBSCRIPTION_STATE_EXPIRED'?Date.now()-1000:Date.now()+86400000});
 await assert.rejects(f.invoke(),{code:'purchase-not-active'});
 assert.equal(f.gets(),1,'The current provider reply already proves the owned token is inactive.');
 assert.equal(f.db.read('purchaseClaims/'+key+'/active'),false,'A fresh authoritative inactive verdict must not leave this token active in retained claims.');
 assert.equal(f.db.read('purchaseClaims/'+key+'/entitlementStatus'),status);
 assert.equal(f.db.read('users/'+uid+'/premiumUntil'),0,'This was the only subscription; access cannot survive its fresh inactive verdict.');
});
test('an inactive owned restore cannot revoke another active subscription token',async t=>{
 const f=fixture(t,{otherActive:true});await assert.rejects(f.invoke(),{code:'purchase-not-active'});
 assert.equal(f.db.read('purchaseClaims/'+key+'/active'),false);
 assert.equal(f.db.read('users/'+uid+'/premiumUntil'),f.preservedExpiry,'Unrelated verified subscription remains membership authority.');
});
test('an inactive response for a foreign provider account cannot revoke the local player claim',async t=>{
 const f=fixture(t,{foreignAccount:true}),before=structuredClone(f.db.data);
 await assert.rejects(f.invoke(),error=>['account-mismatch','purchase-not-active'].includes(error.code));
 assert.deepEqual(f.db.data,before,'Without provider ownership proof, mutate no profile or claim.');
});
test('an unclaimed inactive subscription creates no global token claim or player mutation',async t=>{
 const f=fixture(t,{existing:false}),before=structuredClone(f.db.data);
 await assert.rejects(f.invoke(),{code:'purchase-not-active'});assert.deepEqual(f.db.data,before);
});
test('a currently active owned subscription remains restorable',async t=>{
 const expiry=Date.now()+2*86400000,f=fixture(t,{status:'SUBSCRIPTION_STATE_ACTIVE',providerExpiry:expiry});
 assert.equal((await f.invoke()).entitlementGranted,true);
 assert.equal(f.db.read('purchaseClaims/'+key+'/active'),true);
 assert.equal(f.db.read('users/'+uid+'/premiumUntil'),expiry);
});

function holdFirstProfileTransaction(t){
 const db=getDatabase(),original=db.ref.bind(db);let held=false,enter,release;
 const entered=new Promise(r=>{enter=r;}),resumed=new Promise(r=>{release=r;});
 t.mock.method(db,'ref',(path='',...args)=>{
  const ref=original(path,...args);if(path!=='users/'+uid)return ref;
  return {...ref,async transaction(...args){if(!held){held=true;enter();await resumed;}return ref.transaction(...args);}};
 });
 return {entered,release};
}
test('fresh inactive verification fences an older ACTIVE profile grant without an RTDN',async t=>{
 const f=fixture(t,{status:'SUBSCRIPTION_STATE_ACTIVE'}),gate=holdFirstProfileTransaction(t);
 const old=f.invoke(),settled=old.then(value=>({value}),error=>({error}));let latest;
 try{
  await gate.entered;f.control.status='SUBSCRIPTION_STATE_ON_HOLD';
  await assert.rejects(f.invoke(),{code:'purchase-not-active'});
  latest=f.db.read('purchaseClaims/'+key);
  assert.equal(f.db.read('users/'+uid+'/premiumUntil'),0);
 }finally{gate.release();}
 const result=await settled;assert.equal(result.error?.code,'subscription-state-changed');
 assert.equal(f.db.read('users/'+uid+'/premiumUntil'),0);assert.deepEqual(f.db.read('purchaseClaims/'+key),latest);
});
test('a held inactive provider response cannot revoke a newer valid renewal',async t=>{
 let enter,release,held=false;const entered=new Promise(r=>{enter=r;}),resumed=new Promise(r=>{release=r;});
 const f=fixture(t,{getHook:async()=>{if(!held){held=true;enter();await resumed;}}});
 const old=f.invoke(),settled=old.then(value=>({value}),error=>({error}));let latest;
 try{
  await entered;f.control.status='SUBSCRIPTION_STATE_ACTIVE';f.control.providerExpiry=Date.now()+4*86400000;
  assert.equal((await f.invoke()).entitlementGranted,true);latest=structuredClone(f.db.data);
 }finally{release();}
 assert.equal((await settled).error?.code,'subscription-state-changed');assert.deepEqual(f.db.data,latest);
});
