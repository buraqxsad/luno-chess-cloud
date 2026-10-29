'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {google}=require('googleapis');
const {getDatabase}=require('firebase-admin/database');
const {memoryDatabase}=require('./helpers/memory-database');
const {playBillingNotifications}=require('../index');
const {starterProfile,fulfillPurchase,recomputePremiumFromClaims,reconcilePlayNotification,hash}=require('../index')._test;

const uid='membership_race_owner';
const productId='luno_premium_month';
const token='local-concurrent-membership-token';

function verifiedSubscriptions(t,states){
  t.mock.method(google,'androidpublisher',()=>({purchases:{
    subscriptionsv2:{async get(request){
      const state=states[request.token];
      assert.ok(state,'Only a configured local receipt can be verified.');
      return {data:{
      lineItems:[{productId,expiryTime:new Date(state.expiry).toISOString()}],
      externalAccountIdentifiers:{obfuscatedExternalAccountId:hash(uid)},
      subscriptionState:state.status||'SUBSCRIPTION_STATE_ACTIVE',
      acknowledgementState:'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',
    }};}},
  }}));
}

function holdClaimSnapshot(t){
  const database=getDatabase(),ref=database.ref.bind(database);
  let entered,release,held=false;
  let queryReads=0;
  const captured=new Promise(resolve=>{entered=resolve;});
  const resume=new Promise(resolve=>{release=resolve;});
  t.mock.method(database,'ref',(path='',...args)=>{
    const node=ref(path,...args);
    if(path!=='purchaseClaims')return node;
    return {...node,orderByChild(child){
      const ordered=node.orderByChild(child);
      return {...ordered,equalTo(value){
        const filtered=ordered.equalTo(value);
        return {...filtered,async get(){
          const snapshot=await filtered.get();
          queryReads++;
          if(!held){held=true;entered();await resume;}
          return snapshot;
        }};
      }};
    }};
  });
  return {captured,release,queryReads:()=>queryReads};
}

test('a delayed membership refresh preserves a subscription granted after its claim snapshot',async t=>{
  const at=Date.now(),expiry=at+86400000;
  const db=memoryDatabase(t,{users:{[uid]:starterProfile(uid,'membership_race')}});
  verifiedSubscriptions(t,{[token]:{expiry}});
  const gate=holdClaimSnapshot(t);
  const refresh=recomputePremiumFromClaims(uid,at);
  try{
    await gate.captured;
    const purchase=await fulfillPurchase(uid,{productId,purchaseToken:token});
    assert.equal(purchase.entitlementGranted,true);
    assert.equal(db.read('users/'+uid+'/premiumUntil'),expiry,'Provider-verified purchase must first commit.');
  }finally{gate.release();}
  await refresh;
  assert.equal(db.read('users/'+uid+'/premiumUntil'),expiry,'The older claim snapshot cannot erase a newer owned grant.');
  assert.equal(gate.queryReads(),2,'The stale claim query must be refreshed after the revision changes.');
});

function subscriptionClaim(expiry,active=true){
  return {uid,productId,kind:'subs',status:'complete',active,expiry,
    entitlementStatus:active?'SUBSCRIPTION_STATE_ACTIVE':'SUBSCRIPTION_STATE_ON_HOLD'};
}
function notification(purchaseToken){
  return {packageName:'com.luno.chess',eventTimeMillis:String(Date.now()),
    subscriptionNotification:{purchaseToken,notificationType:5}};
}

for(const cold of [true,false])test(`completed fulfillment before refresh preserves Premium (cold=${cold})`,async t=>{
  const at=Date.now(),expiry=at+86400000;
  const db=memoryDatabase(t,{users:{[uid]:starterProfile(uid,'membership_race')}},{cold});
  verifiedSubscriptions(t,{[token]:{expiry}});
  await fulfillPurchase(uid,{productId,purchaseToken:token});
  assert.deepEqual(await recomputePremiumFromClaims(uid,at),{premiumUntil:expiry,active:true});
  assert.equal(db.read('users/'+uid+'/premiumUntil'),expiry);
});

test('a delayed old-token revocation cannot erase a newly fulfilled subscription',async t=>{
  const at=Date.now(),oldToken='local-old-membership-token',oldKey=hash(oldToken);
  const oldExpiry=at+86400000,newExpiry=at+3*86400000;
  const profile=starterProfile(uid,'membership_race');profile.premiumUntil=oldExpiry;
  const db=memoryDatabase(t,{users:{[uid]:profile},purchaseClaims:{[oldKey]:subscriptionClaim(oldExpiry)}});
  verifiedSubscriptions(t,{[oldToken]:{expiry:oldExpiry,status:'SUBSCRIPTION_STATE_ON_HOLD'},[token]:{expiry:newExpiry}});
  const gate=holdClaimSnapshot(t);
  const revocation=reconcilePlayNotification(notification(oldToken),'local-old-revocation');
  try{
    await gate.captured;
    assert.equal(db.read('purchaseClaims/'+oldKey+'/active'),false,'Revoked claim is already provider-confirmed.');
    await fulfillPurchase(uid,{productId,purchaseToken:token});
  }finally{gate.release();}
  const result=await revocation;
  assert.equal(result.active,false,'The old token stays revoked.');
  assert.equal(result.premiumUntil,newExpiry,'A separate verified subscription still supplies access.');
  assert.equal(db.read('users/'+uid+'/premiumUntil'),newExpiry);
  assert.equal(db.read('purchaseClaims/'+oldKey+'/active'),false);
});

test('a delayed active snapshot cannot restore membership after a completed revocation',async t=>{
  const at=Date.now(),expiry=at+86400000;
  const profile=starterProfile(uid,'membership_race');profile.premiumUntil=expiry;
  const db=memoryDatabase(t,{users:{[uid]:profile},purchaseClaims:{[hash(token)]:subscriptionClaim(expiry)}});
  verifiedSubscriptions(t,{[token]:{expiry,status:'SUBSCRIPTION_STATE_ON_HOLD'}});
  const gate=holdClaimSnapshot(t),refresh=recomputePremiumFromClaims(uid,at);
  try{
    await gate.captured;
    const revoked=await reconcilePlayNotification(notification(token),'local-completed-revocation');
    assert.equal(revoked.premiumUntil,0);
    assert.equal(db.read('users/'+uid+'/premiumUntil'),0);
  }finally{gate.release();}
  assert.deepEqual(await refresh,{premiumUntil:0,active:false});
  assert.equal(db.read('users/'+uid+'/premiumUntil'),0);
});

test('legacy owned claims still supply membership without a profile token receipt',async t=>{
  const at=Date.now(),expiry=at+86400000,profile=starterProfile(uid,'membership_race');
  const db=memoryDatabase(t,{users:{[uid]:profile},purchaseClaims:{[hash(token)]:subscriptionClaim(expiry)}});
  assert.equal(db.read('users/'+uid+'/serverEconomy/purchaseTokens'),null);
  assert.deepEqual(await recomputePremiumFromClaims(uid,at),{premiumUntil:expiry,active:true});
});

for(const retired of [false,true])test(`inactive or retired claim overrides a stale active profile receipt (retired=${retired})`,async t=>{
  const at=Date.now(),expiry=at+86400000,profile=starterProfile(uid,'membership_race');
  profile.premiumUntil=expiry;
  profile.serverEconomy.purchaseTokens={[hash(token)]:{productId,kind:'subs',active:true,expiry,entitlementStatus:'SUBSCRIPTION_STATE_ACTIVE'}};
  const claim=subscriptionClaim(expiry,retired);
  if(retired)claim.accountDeleted=true;
  const db=memoryDatabase(t,{users:{[uid]:profile},purchaseClaims:{[hash(token)]:claim}});
  assert.deepEqual(await recomputePremiumFromClaims(uid,at),{premiumUntil:0,active:false});
  assert.equal(db.read('users/'+uid+'/premiumUntil'),0,'A stale local receipt is not permission to extend access.');
});

test('a server transaction retry re-reads claims after a concurrent subscription commit',async t=>{
  const at=Date.now(),expiry=at+86400000;
  const db=memoryDatabase(t,{users:{[uid]:starterProfile(uid,'membership_race')}},{retry(path,count,update,next,ops){
    if(path!=='users/'+uid||count!==1)return next;
    const newer=structuredClone(ops.read(path));
    newer.stateRevision=(newer.stateRevision||0)+1;
    newer.premiumUntil=expiry;
    ops.write(path,newer);
    ops.write('purchaseClaims/'+hash(token),subscriptionClaim(expiry));
    return update(newer);
  }});
  assert.deepEqual(await recomputePremiumFromClaims(uid,at),{premiumUntil:expiry,active:true});
  assert.equal(db.read('users/'+uid+'/premiumUntil'),expiry);
  assert.equal(db.transactions.filter(row=>row.path==='users/'+uid).length,2);
  assert.equal(db.writes.filter(row=>row.path==='users/'+uid).length,1,'The stale transaction callback must not commit.');
});

test('contention on every refresh exhausts retries without overwriting the current entitlement',async t=>{
  const at=Date.now(),expiry=at+86400000,profile=starterProfile(uid,'membership_race');
  profile.premiumUntil=expiry;
  const db=memoryDatabase(t,{users:{[uid]:profile}},{beforeTransaction(path,count,ops){
    if(path!=='users/'+uid)return;
    const newer=structuredClone(ops.read(path));
    newer.stateRevision=(newer.stateRevision||0)+1;
    ops.write(path,newer);
  }});
  await assert.rejects(recomputePremiumFromClaims(uid,at),{status:503,code:'subscription-state-changed'});
  assert.equal(db.transactions.filter(row=>row.path==='users/'+uid).length,3,'Retry work is bounded.');
  assert.equal(db.read('users/'+uid+'/premiumUntil'),expiry,'None of the stale attempts may commit.');
  assert.equal(db.writes.filter(row=>row.path==='users/'+uid).length,0);
  assert.equal(db.read('publicProfiles/'+uid),null,'No stale entitlement is published.');
});

for(const grant of [true,false])test(`the same RTDN event retries persisted claim reconciliation after contention (grant=${grant})`,async t=>{
  const at=Date.now(),expiry=at+86400000,profile=starterProfile(uid,'membership_race');
  const initialPremium=grant?0:expiry;
  profile.premiumUntil=initialPremium;
  let contending=true;
  const db=memoryDatabase(t,{users:{[uid]:profile},purchaseClaims:{[hash(token)]:subscriptionClaim(expiry,!grant)}},{beforeTransaction(path,count,ops){
    if(path!=='users/'+uid||!contending)return;
    const newer=structuredClone(ops.read(path));
    newer.stateRevision=(newer.stateRevision||0)+1;
    ops.write(path,newer);
  }});
  verifiedSubscriptions(t,{[token]:{expiry,status:grant?'SUBSCRIPTION_STATE_ACTIVE':'SUBSCRIPTION_STATE_ON_HOLD'}});
  const id='local-rtdn-contention-'+grant,eventKey=hash(id).slice(0,48);
  const event={id,data:{message:{messageId:id,json:notification(token)}}};
  for(let attempt=1;attempt<=2;attempt++){
    await assert.rejects(playBillingNotifications.run(event),{status:503,code:'subscription-state-changed'});
    assert.equal(db.read('purchaseClaims/'+hash(token)+'/active'),grant,'The provider claim was persisted before the retriable profile conflict.');
    assert.equal(db.read('users/'+uid+'/premiumUntil'),initialPremium,'Contended callbacks cannot write an old entitlement.');
    assert.equal(db.read('billingEvents/'+eventKey+'/status'),'failed','Failure must remain retryable rather than deduplicated as complete.');
    assert.equal(db.read('billingEvents/'+eventKey+'/errorCode'),'subscription-state-changed');
    assert.equal(db.read('billingEvents/'+eventKey+'/attempts'),attempt);
    assert.equal(db.read('publicProfiles/'+uid),null);
  }
  contending=false;
  const result=await playBillingNotifications.run(event);
  assert.equal(result.active,grant);
  assert.equal(result.premiumUntil,grant?expiry:0);
  assert.equal(db.read('users/'+uid+'/premiumUntil'),grant?expiry:0);
  assert.equal(db.read('billingEvents/'+eventKey+'/status'),'complete');
  assert.equal(db.read('billingEvents/'+eventKey+'/attempts'),3);
  assert.deepEqual(await playBillingNotifications.run(event),{duplicate:true,eventKey});
  assert.equal(db.read('billingEvents/'+eventKey+'/attempts'),3,'Only a successfully completed event is suppressed.');
});
