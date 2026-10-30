'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {google}=require('googleapis');
const {getDatabase}=require('firebase-admin/database');
const logger=require('firebase-functions/logger');
const {memoryDatabase}=require('./helpers/memory-database');
const {starterProfile,fulfillPurchase,reconcilePlayNotification,hash}=require('../index')._test;
const uid='system_subscription_owner',productId='luno_premium_month',token='system-local-subscription-token';
const key=hash(token),claimPath='purchaseClaims/'+key;
function holdTransaction(t,pathToHold,ordinal){
 const database=getDatabase(),original=database.ref.bind(database);let calls=0,enter,release;
 const entered=new Promise(resolve=>{enter=resolve;}),resume=new Promise(resolve=>{release=resolve;});
 t.mock.method(database,'ref',(path='',...args)=>{
  const ref=original(path,...args);if(path!==pathToHold)return ref;
  return {...ref,async transaction(...args){if(++calls===ordinal){enter();await resume;}return ref.transaction(...args);}};
 });
 return {entered,release};
}
for(const cold of [true,false])for(const phase of ['before-profile-grant','before-granted-claim'])test(`subscription on-hold wins over an older verified fulfillment (${phase},cold=${cold})`,async t=>{
 const at=Date.now(),expiry=at+86400000,profile=starterProfile(uid,'system_subscription_user');
 const db=memoryDatabase(t,{users:{[uid]:profile}},{cold});
 let status='SUBSCRIPTION_STATE_ACTIVE';
 t.mock.method(logger,'error',()=>{});
 t.mock.method(google,'androidpublisher',()=>({purchases:{subscriptionsv2:{async get(){return {data:{
  lineItems:[{productId,expiryTime:new Date(expiry).toISOString()}],
  subscriptionState:status,acknowledgementState:'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',
  externalAccountIdentifiers:{obfuscatedExternalAccountId:hash(uid)},
 }};}}}}));
 const gate=phase==='before-profile-grant'?holdTransaction(t,'users/'+uid,1):holdTransaction(t,claimPath,2);
 const old=fulfillPurchase(uid,{productId,purchaseToken:token});const settled=old.then(value=>({value}),error=>({error}));
 let latestClaim;
 try{
  await gate.entered;
  status='SUBSCRIPTION_STATE_ON_HOLD';
  const notification={packageName:'com.luno.chess',eventTimeMillis:String(Date.now()),subscriptionNotification:{purchaseToken:token,notificationType:5}};
  const revoked=await reconcilePlayNotification(notification,'system-concurrent-subscription-hold');
  assert.equal(revoked.active,false);
  assert.equal(db.read(claimPath+'/active'),false,'The current provider decision is already committed.');
  assert.equal(db.read('users/'+uid+'/premiumUntil'),0,'The newer reconciliation has removed access.');
  latestClaim=db.read(claimPath);
 }finally{gate.release();}
 const result=await settled;
 assert.equal(db.read('users/'+uid+'/premiumUntil'),0,'Older provider verification must not re-grant held subscription access.');
 assert.equal(db.read(claimPath+'/active'),false,'An older granted-claim write must not overwrite current provider lifecycle.');
 assert.equal(db.read(claimPath+'/entitlementStatus'),'SUBSCRIPTION_STATE_ON_HOLD');
 assert.ok(result.error,'A no-longer-active purchase must not report entitlementGranted success.');
 assert.deepEqual(db.read(claimPath),latestClaim,'A stale fulfillment failure must not change newer reconciliation metadata.');
});
function subscriptionProvider(t,{initialStatus='SUBSCRIPTION_STATE_ACTIVE',expiry=Date.now()+86400000,getHook,ackHook,account=uid}={}){
 const control={status:initialStatus,expiry,gets:0,acks:0};
 t.mock.method(logger,'error',()=>{});
 t.mock.method(google,'androidpublisher',()=>({purchases:{
  subscriptionsv2:{async get(){
   const data={lineItems:[{productId,expiryTime:new Date(control.expiry).toISOString()}],subscriptionState:control.status,
    acknowledgementState:ackHook?'ACKNOWLEDGEMENT_STATE_PENDING':'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',
    externalAccountIdentifiers:{obfuscatedExternalAccountId:hash(account)}};
   control.gets++;if(getHook)await getHook(control);
   return {data};
  }},
  subscriptions:{async acknowledge(){control.acks++;if(ackHook)await ackHook(control);}},
 }}));
 return control;
}
function subNotification(){return {packageName:'com.luno.chess',eventTimeMillis:String(Date.now()),subscriptionNotification:{purchaseToken:token,notificationType:5}};}
function legacyClaim(expiry,active=false){return {uid,productId,kind:'subs',status:'complete',active,expiry,entitlementStatus:active?'SUBSCRIPTION_STATE_ACTIVE':'SUBSCRIPTION_STATE_ON_HOLD'};}
test('zero-access reconciliation without any profile receipt creates a persistent fence',async t=>{
 const profile=starterProfile(uid,'system_subscription_user'),before=structuredClone(profile),expiry=Date.now()+86400000;
 const db=memoryDatabase(t,{users:{[uid]:profile},purchaseClaims:{[key]:legacyClaim(expiry)}});
 subscriptionProvider(t,{initialStatus:'SUBSCRIPTION_STATE_ON_HOLD',expiry});
 assert.equal(profile.premiumUntil||0,0);assert.equal(profile.serverEconomy.purchaseTokens,undefined);
 await reconcilePlayNotification(subNotification(),'system-zero-access-fence');
 assert.equal(db.read('users/'+uid+'/premiumUntil'),0);
 assert.equal(db.read('users/'+uid+'/serverEconomy/purchaseTokens/'+key),null);
 assert.equal(db.read('users/'+uid+'/serverEconomy/subscriptionClaimRevisions/'+key),db.read(claimPath+'/claimRevision'));
 assert.ok(db.read('users/'+uid+'/stateRevision')>(before.stateRevision||0),'The no-access reconciliation still changes durable profile authority.');
});
test('an on-hold legacy token can recover with a fresh active provider response',async t=>{
 const profile=starterProfile(uid,'system_subscription_user'),expiry=Date.now()+86400000;
 const db=memoryDatabase(t,{users:{[uid]:profile},purchaseClaims:{[key]:legacyClaim(expiry)}});
 const provider=subscriptionProvider(t,{initialStatus:'SUBSCRIPTION_STATE_ON_HOLD',expiry});
 await reconcilePlayNotification(subNotification(),'system-legacy-hold');
 const fence=db.read('users/'+uid+'/serverEconomy/subscriptionClaimRevisions/'+key);
 provider.status='SUBSCRIPTION_STATE_ACTIVE';
 assert.equal((await fulfillPurchase(uid,{productId,purchaseToken:token})).entitlementGranted,true);
 assert.equal(db.read('users/'+uid+'/premiumUntil'),expiry);
 assert.equal(db.read(claimPath+'/active'),true);
 assert.ok(db.read(claimPath+'/claimRevision')>fence,'A new provider proof advances past the inactive fence.');
});
for(const olderActive of [true,false])test(`older RTDN provider response cannot overwrite newer ${olderActive?'hold':'renewal'} (olderActive=${olderActive})`,async t=>{
 const profile=starterProfile(uid,'system_subscription_user'),expiry=Date.now()+86400000;
 if(olderActive)profile.premiumUntil=expiry;
 const db=memoryDatabase(t,{users:{[uid]:profile},purchaseClaims:{[key]:legacyClaim(expiry,olderActive)}});
 let entered,release,held=false;
 const gate=new Promise(resolve=>{entered=resolve;}),resume=new Promise(resolve=>{release=resolve;});
 const provider=subscriptionProvider(t,{initialStatus:olderActive?'SUBSCRIPTION_STATE_ACTIVE':'SUBSCRIPTION_STATE_ON_HOLD',expiry,getHook:async()=>{
  if(!held){held=true;entered();await resume;}
 }});
 const old=reconcilePlayNotification(subNotification(),'system-held-old-rtdn');const settled=old.then(value=>({value}),error=>({error}));
 try{
  await gate;
  provider.status=olderActive?'SUBSCRIPTION_STATE_ON_HOLD':'SUBSCRIPTION_STATE_ACTIVE';
  if(olderActive)await reconcilePlayNotification(subNotification(),'system-new-hold');
  else await fulfillPurchase(uid,{productId,purchaseToken:token});
 }finally{release();}
 const result=await settled;
 assert.equal(result.error?.code,'subscription-state-changed');
 assert.equal(result.error?.status,503,'Provider-version conflict must remain retriable.');
 assert.equal(db.read(claimPath+'/active'),!olderActive);
 assert.equal(db.read('users/'+uid+'/premiumUntil'),olderActive?0:expiry);
});
test('first claim registration rechecks a subscription whose earlier RTDN was unmatched',async t=>{
 const profile=starterProfile(uid,'system_subscription_user');const db=memoryDatabase(t,{users:{[uid]:profile}});
 let entered,release;const gate=new Promise(resolve=>{entered=resolve;}),resume=new Promise(resolve=>{release=resolve;});
 const provider=subscriptionProvider(t,{getHook:async control=>{if(control.gets===1){entered();await resume;}}});
 const old=fulfillPurchase(uid,{productId,purchaseToken:token});const settled=old.then(value=>({value}),error=>({error}));
 try{
  await gate;
  assert.equal(db.read(claimPath),null,'Unverified tokens cannot squat a global claim.');
  provider.status='SUBSCRIPTION_STATE_ON_HOLD';
  assert.equal((await reconcilePlayNotification(subNotification(),'system-before-first-claim')).deferred,true);
 }finally{release();}
 const result=await settled;
 assert.equal(result.error?.code,'purchase-not-active');
 assert.equal(provider.gets,2,'The now-owned claim is revalidated after it becomes matchable by RTDN.');
 assert.equal(db.read('users/'+uid+'/premiumUntil')||0,0);
 assert.equal(db.read('users/'+uid+'/serverEconomy/purchaseTokens/'+key),null);
 assert.notEqual(db.read(claimPath+'/active'),true);
});
test('first subscription account mismatch creates no global claim or player mutation',async t=>{
 const profile=starterProfile(uid,'system_subscription_user');const db=memoryDatabase(t,{users:{[uid]:profile}});
 const provider=subscriptionProvider(t,{account:'other-local-subscription-owner'});
 await assert.rejects(fulfillPurchase(uid,{productId,purchaseToken:token}),{code:'account-mismatch'});
 assert.equal(provider.gets,1);assert.equal(db.read(claimPath),null);assert.deepEqual(db.read('users/'+uid),profile);
});
test('late acknowledgement completion cannot mark a newer on-hold claim complete',async t=>{
 const profile=starterProfile(uid,'system_subscription_user'),expiry=Date.now()+86400000;
 const db=memoryDatabase(t,{users:{[uid]:profile}});
 let entered,release;const gate=new Promise(resolve=>{entered=resolve;}),resume=new Promise(resolve=>{release=resolve;});
 const provider=subscriptionProvider(t,{expiry,ackHook:async()=>{entered();await resume;}});
 const old=fulfillPurchase(uid,{productId,purchaseToken:token});const settled=old.then(value=>({value}),error=>({error}));
 try{
  await gate;provider.status='SUBSCRIPTION_STATE_ON_HOLD';
  await reconcilePlayNotification(subNotification(),'system-hold-before-ack-return');
 }finally{release();}
 assert.equal((await settled).error?.code,'subscription-state-changed');
 assert.equal(db.read('users/'+uid+'/premiumUntil'),0);assert.equal(db.read(claimPath+'/active'),false);
 assert.equal(db.read(claimPath+'/entitlementStatus'),'SUBSCRIPTION_STATE_ON_HOLD');
});
test('deletion during first-claim revalidation retires metadata without resurrecting the account',async t=>{
 const profile=starterProfile(uid,'system_subscription_user');const db=memoryDatabase(t,{users:{[uid]:profile}});
 subscriptionProvider(t,{getHook:async control=>{
  if(control.gets===2){db.write('deletedAccounts/'+hash(uid),{deletedAt:Date.now()});db.write('users/'+uid,null);}
 }});
 await assert.rejects(fulfillPurchase(uid,{productId,purchaseToken:token}));
 assert.equal(db.read('users/'+uid),null);assert.equal(db.read(claimPath+'/accountDeleted'),true);assert.equal(db.read(claimPath+'/active'),false);
});
test('a removed legacy zero-revision claim cannot be recreated by an old verification',async t=>{
 const profile=starterProfile(uid,'system_subscription_user'),expiry=Date.now()+86400000;
 const db=memoryDatabase(t,{users:{[uid]:profile},purchaseClaims:{[key]:legacyClaim(expiry)}});
 let entered,release;const gate=new Promise(resolve=>{entered=resolve;}),resume=new Promise(resolve=>{release=resolve;});
 const provider=subscriptionProvider(t,{expiry,getHook:async control=>{if(control.gets===1){entered();await resume;}}});
 const old=fulfillPurchase(uid,{productId,purchaseToken:token});const settled=old.then(value=>({value}),error=>({error}));
 try{await gate;provider.status='SUBSCRIPTION_STATE_ON_HOLD';db.write(claimPath,null);}finally{release();}
 const result=await settled;
 assert.equal(result.error?.code,'purchase-claim-changed');
 assert.equal(db.read(claimPath),null);assert.deepEqual(db.read('users/'+uid),profile);
});
test('cold cache still verifies an existing legacy zero-revision claim against real stored data',async t=>{
 const profile=starterProfile(uid,'system_subscription_user'),expiry=Date.now()+86400000;
 const db=memoryDatabase(t,{users:{[uid]:profile},purchaseClaims:{[key]:legacyClaim(expiry)}},{cold:true});
 const provider=subscriptionProvider(t,{expiry});
 assert.equal((await fulfillPurchase(uid,{productId,purchaseToken:token})).entitlementGranted,true);
 assert.equal(provider.gets,1,'Already registered legacy claims use a current provider check without reserving a new claim.');
 assert.equal(db.read(claimPath+'/active'),true);assert.ok(db.read(claimPath+'/claimRevision')>0);
 assert.equal(db.read('users/'+uid+'/premiumUntil'),expiry);
});
test('a competing recompute during first-claim publication cannot erase a completed subscription grant',async t=>{
 const profile=starterProfile(uid,'system_subscription_user'),expiry=Date.now()+86400000;
 const db=memoryDatabase(t,{users:{[uid]:profile}});subscriptionProvider(t,{expiry});
 const gate=holdTransaction(t,claimPath,2);
 const old=fulfillPurchase(uid,{productId,purchaseToken:token});const settled=old.then(value=>({value}),error=>({error}));
 try{
  await gate.entered;
  assert.equal(db.read('users/'+uid+'/premiumUntil'),expiry);
  assert.notEqual(db.read(claimPath+'/active'),true,'Profile grant is committed while global grant publication is still pending.');
  await require('../index')._test.recomputePremiumFromClaims(uid,Date.now());
  assert.equal(db.read('users/'+uid+'/premiumUntil'),0,'An unrelated reconciler cannot yet observe the unpublished claim.');
 }finally{gate.release();}
 const result=await settled;
 assert.equal(result.value?.entitlementGranted,true);
 assert.equal(db.read(claimPath+'/active'),true);
 assert.equal(db.read('users/'+uid+'/premiumUntil'),expiry,'Success must leave profile Premium synchronized with the now-complete owned claim.');
});

function holdFirstClaimQuery(t,{snapshot}={}){
 const database=getDatabase(),original=database.ref.bind(database);let held=false,enter,release,reads=0;
 const entered=new Promise(resolve=>{enter=resolve;}),resume=new Promise(resolve=>{release=resolve;});
 t.mock.method(database,'ref',(path='',...args)=>{
  const ref=original(path,...args);if(path!=='purchaseClaims')return ref;
  return {...ref,orderByChild(child){const query=ref.orderByChild(child);return {...query,equalTo(value){const filtered=query.equalTo(value);return {...filtered,async get(){
   reads++;const result=await filtered.get();
   if(!held){held=true;enter();await resume;if(snapshot!==undefined)return {val:()=>structuredClone(snapshot),exists:()=>true};}
   return result;
  }};}};}};
 });
 return {entered,release,reads:()=>reads};
}

test('a newer hold during final projection cannot produce stale purchase success',async t=>{
 const profile=starterProfile(uid,'system_subscription_user'),expiry=Date.now()+86400000;
 const db=memoryDatabase(t,{users:{[uid]:profile}});const provider=subscriptionProvider(t,{expiry});
 const gate=holdFirstClaimQuery(t);
 const old=fulfillPurchase(uid,{productId,purchaseToken:token});const settled=old.then(value=>({value}),error=>({error}));
 let latestClaim;
 try{
  await gate.entered;
  assert.equal(db.read(claimPath+'/status'),'granted','The owned grant is projected before the final completion CAS.');
  provider.status='SUBSCRIPTION_STATE_ON_HOLD';
  await reconcilePlayNotification(subNotification(),'system-hold-during-final-projection');
  latestClaim=db.read(claimPath);
  assert.equal(latestClaim.active,false);assert.equal(db.read('users/'+uid+'/premiumUntil'),0);
 }finally{gate.release();}
 const result=await settled;
 assert.equal(result.error?.code,'subscription-state-changed','Current inactive access cannot be reported as entitlementGranted success.');
 assert.equal(result.error?.status,503);
 assert.deepEqual(db.read(claimPath),latestClaim,'The old completion/error path cannot change the newer hold.');
 assert.equal(db.read('users/'+uid+'/premiumUntil'),0);
});

test('a cached older claim revision cannot lower an already installed profile fence',async t=>{
 const profile=starterProfile(uid,'system_subscription_user'),expiry=Date.now()+86400000;
 profile.serverEconomy.subscriptionClaimRevisions={[key]:7};
 profile.premiumUntil=0;
 const current={...legacyClaim(expiry,false),claimRevision:7};
 const stale={...legacyClaim(expiry,true),claimRevision:6};
 const db=memoryDatabase(t,{users:{[uid]:profile},purchaseClaims:{[key]:current}});
 const gate=holdFirstClaimQuery(t,{snapshot:{[key]:stale}});
 const refresh=require('../index')._test.recomputePremiumFromClaims(uid,Date.now());
 await gate.entered;gate.release();await refresh;
 assert.equal(db.read('users/'+uid+'/serverEconomy/subscriptionClaimRevisions/'+key),7,'Installed claim fencing must never move backwards.');
 assert.equal(db.read('users/'+uid+'/premiumUntil'),0,'Older active claim data cannot restore held access.');
 assert.equal(gate.reads(),2,'A snapshot older than the committed fence must trigger a fresh query.');
});

test('another active token cannot justify success for the purchase put on hold during final projection',async t=>{
 const profile=starterProfile(uid,'system_subscription_user'),expiry=Date.now()+86400000,otherExpiry=expiry+86400000;
 profile.premiumUntil=otherExpiry;
 const otherKey=hash('system-local-other-active-subscription');
 const db=memoryDatabase(t,{users:{[uid]:profile},purchaseClaims:{[otherKey]:legacyClaim(otherExpiry,true)}});
 const provider=subscriptionProvider(t,{expiry}),gate=holdFirstClaimQuery(t);
 const old=fulfillPurchase(uid,{productId,purchaseToken:token});const settled=old.then(value=>({value}),error=>({error}));
 try{
  await gate.entered;provider.status='SUBSCRIPTION_STATE_ON_HOLD';
  await reconcilePlayNotification(subNotification(),'system-other-active-token');
  assert.equal(db.read('users/'+uid+'/premiumUntil'),otherExpiry,'Unrelated owned subscription access must stay valid.');
 }finally{gate.release();}
 const result=await settled;
 assert.equal(result.error?.code,'subscription-state-changed','The current purchase itself must remain active to report success.');
 assert.equal(db.read(claimPath+'/active'),false);
 assert.equal(db.read('users/'+uid+'/premiumUntil'),otherExpiry,'Rejecting stale purchase success cannot revoke another valid token.');
});

for(const event of ['hold','erasure'])test(`the final completion transaction rejects a concurrent ${event}`,async t=>{
 const profile=starterProfile(uid,'system_subscription_user'),expiry=Date.now()+86400000;
 const db=memoryDatabase(t,{users:{[uid]:profile}}),provider=subscriptionProvider(t,{expiry});
 const gate=holdTransaction(t,claimPath,3);
 const old=fulfillPurchase(uid,{productId,purchaseToken:token});const settled=old.then(value=>({value}),error=>({error}));
 let latestClaim;
 try{
  await gate.entered;
  assert.equal(db.read(claimPath+'/status'),'granted');
  assert.equal(db.read('users/'+uid+'/serverEconomy/subscriptionClaimRevisions/'+key),db.read(claimPath+'/claimRevision'),'Projection must precede the final completion transaction.');
  if(event==='hold'){
   provider.status='SUBSCRIPTION_STATE_ON_HOLD';await reconcilePlayNotification(subNotification(),'system-final-commit-hold');
   latestClaim=db.read(claimPath);
  }else{
   db.write('deletedAccounts/'+hash(uid),{deletedAt:Date.now()});db.write('users/'+uid,null);
  }
 }finally{gate.release();}
 const result=await settled;
 assert.equal(result.error?.code,event==='hold'?'subscription-state-changed':'account-deleted');
 if(event==='hold'){
  assert.deepEqual(db.read(claimPath),latestClaim);assert.equal(db.read('users/'+uid+'/premiumUntil'),0);
 }else{
  assert.equal(db.read('users/'+uid),null);assert.equal(db.read(claimPath+'/accountDeleted'),true);assert.equal(db.read(claimPath+'/active'),false);
 }
});
