'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {google}=require('googleapis');
const {getDatabase}=require('firebase-admin/database');
const logger=require('firebase-functions/logger');
const {memoryDatabase}=require('./helpers/memory-database');
const {starterProfile,fulfillPurchase,reconcilePlayNotification,applyVerifiedPurchaseGrant,applyVoidedPurchaseRevocation,PRODUCT_CATALOG,hash}=require('../index')._test;
const uid='system_refund_owner',productId='luno_gold_1000',token='system-local-refund-grant-token';
const key=hash(token),claimPath='purchaseClaims/'+key;
function notification(){return {packageName:'com.luno.chess',eventTimeMillis:String(Date.now()),voidedPurchaseNotification:{purchaseToken:token}};}
function provider(t){
 const calls={consume:0,voided:0};
 t.mock.method(logger,'error',()=>{});
 t.mock.method(google,'androidpublisher',()=>({purchases:{
  productsv2:{async getproductpurchasev2(){return {data:{
   productLineItem:[{productId,productOfferDetails:{consumptionState:'CONSUMPTION_STATE_YET_TO_BE_CONSUMED'}}],
   purchaseStateContext:{purchaseState:'PURCHASED'},obfuscatedExternalAccountId:hash(uid),
  }};}},
  products:{async consume(){calls.consume++;}},
  voidedpurchases:{async list(){calls.voided++;return {data:{voidedPurchases:[{purchaseToken:token,voidedTimeMillis:String(Date.now()),voidedReason:1}]}};}},
 }}));
 return calls;
}
function holdFirstGrantTransaction(t){
 const db=getDatabase(),original=db.ref.bind(db);let held=false,enter,release;
 const entered=new Promise(resolve=>{enter=resolve;});const resume=new Promise(resolve=>{release=resolve;});
 t.mock.method(db,'ref',(path='',...args)=>{
  const node=original(path,...args);
  if(path!=='users/'+uid)return node;
  return {...node,async transaction(...args){
   if(!held){held=true;enter();await resume;}
   return node.transaction(...args);
  }};
 });
 return {entered,release};
}
for(const cold of [true,false])test(`confirmed pre-grant refund blocks an already verified suspended fulfillment (cold=${cold})`,async t=>{
 const profile=starterProfile(uid,'system_refund_user');const before=profile.gold;
 const db=memoryDatabase(t,{users:{[uid]:profile}},{cold});const calls=provider(t),gate=holdFirstGrantTransaction(t);
 const purchase=fulfillPurchase(uid,{productId,purchaseToken:token});const settled=purchase.then(value=>({value}),error=>({error}));
 try{
  await gate.entered;
  assert.equal(db.read(claimPath+'/status'),'verified','The old fulfillment has checked and captured its verified claim.');
  assert.equal(db.read('users/'+uid+'/serverEconomy/purchaseTokens/'+key),null);
  const refunded=await reconcilePlayNotification(notification(),'system-pregrant-refund');
  assert.equal(refunded.ungranted,true);
  assert.equal(refunded.revoked,false);
  assert.equal(db.read('users/'+uid+'/gold'),before,'A never-granted token must not debit unrelated funds.');
  assert.equal(db.read(claimPath+'/voided'),true,'The independently confirmed refund must commit first.');
 }finally{gate.release();}
 const result=await settled;
 assert.ok(result.error,'A suspended grant cannot succeed after a confirmed refund.');
 assert.equal(db.read('users/'+uid+'/gold'),before,'No currency may be minted after refund completion.');
 assert.equal(db.read('users/'+uid+'/serverEconomy/purchaseTokens/'+key),null,'No granted token receipt may appear after refund completion.');
 assert.equal(calls.consume,0,'A revoked purchase must never reach consume.');
 assert.equal(result.error.code,'purchase-revoked');
 assert.equal(db.read(claimPath+'/voided'),true);
});
test('normal grant then confirmed duplicate refund recovers only that grant once',async t=>{
 const profile=starterProfile(uid,'system_refund_user'),before=profile.gold;
 const db=memoryDatabase(t,{users:{[uid]:profile}});provider(t);
 assert.equal((await fulfillPurchase(uid,{productId,purchaseToken:token})).entitlementGranted,true);
 assert.equal(db.read('users/'+uid+'/gold'),before+1000);
 assert.equal((await reconcilePlayNotification(notification(),'system-postgrant-refund')).revoked,true);
 assert.equal(db.read('users/'+uid+'/gold'),before);
 assert.equal((await reconcilePlayNotification(notification(),'system-postgrant-refund-duplicate')).idempotent,true);
 assert.equal(db.read('users/'+uid+'/gold'),before);
});
test('pre-grant refund rejection also survives a completely fresh fulfillment request',async t=>{
 const profile=starterProfile(uid,'system_refund_user'),before=profile.gold;
 const db=memoryDatabase(t,{users:{[uid]:profile},purchaseClaims:{[key]:{uid,productId,status:'verified'}}});provider(t);
 assert.equal((await reconcilePlayNotification(notification(),'system-fresh-refund')).ungranted,true);
 await assert.rejects(fulfillPurchase(uid,{productId,purchaseToken:token}),{code:'purchase-revoked'});
 assert.equal(db.read('users/'+uid+'/gold'),before);
});
test('profile-side pre-grant revocation cannot be bypassed by an earlier verified grant decision',()=>{
 const profile=starterProfile(uid,'system_refund_user'),before=profile.gold;
 const claim={uid,productId,status:'verified'};
 assert.deepEqual(applyVoidedPurchaseRevocation(profile,claim,key,Date.now()),{revoked:false,ungranted:true});
 const decision=applyVerifiedPurchaseGrant(profile,uid,PRODUCT_CATALOG[productId],{kind:'inapp',productId,data:{}},key);
 assert.equal(decision.error,'purchase-revoked');
 assert.equal(profile.gold,before);
});
test('duplicate pre-grant refund keeps the durable guard and unrelated funds unchanged',async t=>{
 const profile=starterProfile(uid,'system_refund_user'),before=structuredClone(profile);
 const db=memoryDatabase(t,{users:{[uid]:profile},purchaseClaims:{[key]:{uid,productId,status:'verified'}}});provider(t);
 assert.equal((await reconcilePlayNotification(notification(),'system-first-ungranted')).ungranted,true);
 const guarded=db.read('users/'+uid);
 assert.equal(guarded.gold,before.gold);assert.equal(guarded.gems,before.gems);
 assert.equal(guarded.serverEconomy.billingReversals[key].ungranted,true);
 assert.equal((await reconcilePlayNotification(notification(),'system-duplicate-ungranted')).idempotent,true);
 assert.deepEqual(db.read('users/'+uid),guarded,'Duplicate refund must not change the guarded player.');
});
test('account deletion after pre-grant refund cannot be undone by the suspended fulfillment',async t=>{
 const profile=starterProfile(uid,'system_refund_user');
 const db=memoryDatabase(t,{users:{[uid]:profile}});provider(t);const gate=holdFirstGrantTransaction(t);
 const pending=fulfillPurchase(uid,{productId,purchaseToken:token});const settled=pending.then(value=>({value}),error=>({error}));
 try{
  await gate.entered;
  assert.equal((await reconcilePlayNotification(notification(),'system-refund-then-delete')).ungranted,true);
  db.write('deletedAccounts/'+hash(uid),{deletedAt:Date.now()});db.write('users/'+uid,null);
 }finally{gate.release();}
 assert.ok((await settled).error);
 assert.equal(db.read('users/'+uid),null);
 assert.equal(db.read(claimPath+'/accountDeleted'),true);
 assert.equal(db.read(claimPath+'/active'),false);
});
test('deletion immediately after the revocation transaction retires the claim without recreating profile',async t=>{
 const profile=starterProfile(uid,'system_refund_user');let deleted=false;
 const db=memoryDatabase(t,{users:{[uid]:profile},purchaseClaims:{[key]:{uid,productId,status:'verified'}}},{afterTransaction(path,count,ops){
  if(path==='users/'+uid&&!deleted){deleted=true;ops.write('deletedAccounts/'+hash(uid),{deletedAt:Date.now()});ops.write(path,null);}
 }});provider(t);
 assert.equal((await reconcilePlayNotification(notification(),'system-delete-during-refund')).status,'account-deleted');
 assert.equal(db.read('users/'+uid),null);assert.equal(db.read(claimPath+'/accountDeleted'),true);
});
test('lost voided-claim write keeps the profile guard and the same notification can finish later',async t=>{
 const profile=starterProfile(uid,'system_refund_user'),before=profile.gold;let fail=true;
 const db=memoryDatabase(t,{users:{[uid]:profile},purchaseClaims:{[key]:{uid,productId,status:'verified'}}},{beforeTransaction(path){
  if(path===claimPath&&fail){fail=false;throw new Error('local-void-claim-response-lost');}
 }});provider(t);
 await assert.rejects(reconcilePlayNotification(notification(),'system-refund-claim-loss'),/local-void-claim-response-lost/);
 assert.equal(db.read('users/'+uid+'/serverEconomy/billingReversals/'+key+'/ungranted'),true);
 await assert.rejects(fulfillPurchase(uid,{productId,purchaseToken:token}),{code:'purchase-revoked'});
 assert.equal(db.read('users/'+uid+'/gold'),before);
 assert.equal((await reconcilePlayNotification(notification(),'system-refund-claim-loss')).idempotent,true);
 assert.equal(db.read(claimPath+'/voided'),true);
});
test('a separate verified purchase still grants after the first ungranted token was refunded',async t=>{
 const profile=starterProfile(uid,'system_refund_user'),before=profile.gold;
 const db=memoryDatabase(t,{users:{[uid]:profile},purchaseClaims:{[key]:{uid,productId,status:'verified'}}});provider(t);
 await reconcilePlayNotification(notification(),'system-isolated-token-refund');
 const nextToken='system-local-separate-purchase';
 assert.equal((await fulfillPurchase(uid,{productId,purchaseToken:nextToken})).entitlementGranted,true);
 assert.equal(db.read('users/'+uid+'/gold'),before+1000);
 assert.equal(db.read('users/'+uid+'/serverEconomy/purchaseTokens/'+hash(nextToken)+'/active'),true);
 assert.equal(db.read(claimPath+'/voided'),true);
});
