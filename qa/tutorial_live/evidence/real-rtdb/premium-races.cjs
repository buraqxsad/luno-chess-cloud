'use strict';
const {createRequire,Module}=require('node:module');
const {readFileSync,writeFileSync}=require('node:fs');
const {resolve,dirname}=require('node:path');
const assert=require('node:assert/strict');
const test=require('node:test');
const req=createRequire('/workspace/luno-chess/functions/package.json');
const namespace='demo-luno-premium-race-default-rtdb';
assert.equal(process.env.FIREBASE_DATABASE_EMULATOR_HOST,'127.0.0.1:19000');
assert.equal(process.env.LUNO_DB_EMULATOR_NAMESPACE,namespace);
assert.equal(process.env.GCLOUD_PROJECT,'demo-luno-premium-race');
assert.equal(process.env.GOOGLE_APPLICATION_CREDENTIALS,undefined);
const variant=process.argv[2];assert.ok(['baseline','fixed'].includes(variant));
const root=dirname(__filename),original='/workspace/luno-chess/functions/index.js';
const backend=new Module(original,module);backend.filename=original;
backend.paths=Module._nodeModulePaths(dirname(original));
backend._compile(readFileSync(resolve(root,variant+'-index.cjs'),'utf8'),original);
const api=backend.exports._test;
const {google}=req('googleapis');
const {initializeApp,deleteApp,getApps}=req('firebase-admin/app');
const {getDatabase}=req('firebase-admin/database');
const db=getDatabase();
const writerApp=initializeApp({projectId:'demo-luno-premium-race',databaseURL:'http://127.0.0.1:19000?ns='+namespace},'premium-proof-independent-writer');
const writer=getDatabase(writerApp);
const productId='luno_premium_month',day=86400000;
const observations=[];
function record(value){observations.push(value);writeFileSync(resolve(root,variant+'-observations.json'),JSON.stringify(observations,null,2)+'\n');}
function fixturePlay(t,uid,states){
 t.mock.method(google,'androidpublisher',()=>({purchases:{subscriptionsv2:{async get(request){
  const state=states[request.token];assert.ok(state,'Unconfigured local receipt');
  return {data:{lineItems:[{productId,expiryTime:new Date(state.expiry).toISOString()}],
   externalAccountIdentifiers:{obfuscatedExternalAccountId:api.hash(uid)},
   subscriptionState:state.status||'SUBSCRIPTION_STATE_ACTIVE',
   acknowledgementState:'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED'}};
 }}}}));
}
function proxied(target,methods){
 return new Proxy(target,{get(node,key){
  if(Object.hasOwn(methods,key))return methods[key];
  const value=Reflect.get(node,key,node);return typeof value==='function'?value.bind(node):value;
 }});
}
function holdRealClaimSnapshot(t){
 const ref=db.ref.bind(db);let held=false,entered,release,queries=0;
 const captured=new Promise(r=>{entered=r;}),resume=new Promise(r=>{release=r;});
 t.mock.method(db,'ref',(path='',...args)=>{
  const node=ref(path,...args);if(path!=='purchaseClaims')return node;
  return proxied(node,{orderByChild(child){
   const ordered=node.orderByChild(child);
   return proxied(ordered,{equalTo(value){
    const filtered=ordered.equalTo(value);
    return proxied(filtered,{async get(){
     const snapshot=await filtered.get();queries++;
     if(!held){held=true;entered();await resume;}
     return snapshot;
    }});
   }});
  }});
 });
 return {captured,release,queries:()=>queries};
}
function claim(uid,expiry){return {uid,productId,kind:'subs',status:'complete',active:true,expiry,entitlementStatus:'SUBSCRIPTION_STATE_ACTIVE'};}
function notification(purchaseToken){return {packageName:'com.luno.chess',eventTimeMillis:String(Date.now()),subscriptionNotification:{purchaseToken,notificationType:5}};}
async function seed(uid,profile,claims={}){
 await writer.ref().set({users:{[uid]:profile},purchaseClaims:claims});
 assert.equal((await writer.ref('users/'+uid+'/uid').get()).val(),uid);
}
test.after(async()=>{await Promise.all(getApps().map(app=>deleteApp(app)));});

test('real RTDB: delayed claim snapshot cannot erase a newly fulfilled subscription',{timeout:25000},async t=>{
 const uid='premium_sdk_grant',token='local-sdk-new-token',at=Date.now(),expiry=at+day;
 await seed(uid,api.starterProfile(uid,uid));fixturePlay(t,uid,{[token]:{expiry}});
 const gate=holdRealClaimSnapshot(t),pending=api.recomputePremiumFromClaims(uid,at);let granted;
 try{
  await gate.captured;
  assert.equal((await api.fulfillPurchase(uid,{productId,purchaseToken:token})).entitlementGranted,true);
  granted=(await writer.ref('users/'+uid+'/premiumUntil').get()).val();
  assert.equal(granted,expiry,'Independent SDK confirms the provider-mocked grant committed first.');
 }finally{gate.release();}
 await pending;
 const actual=(await writer.ref('users/'+uid+'/premiumUntil').get()).val();
 record({case:'concurrent-fulfillment',variant,expected:expiry,grant_before_release:granted,actual_after_refresh:actual,claim_query_reads:gate.queries()});
 assert.equal(actual,expiry);
});

test('real RTDB: delayed old-token revocation preserves a separate new subscription',{timeout:25000},async t=>{
 const uid='premium_sdk_revoke_new',oldToken='local-sdk-old-token',token='local-sdk-renewed-token';
 const at=Date.now(),oldExpiry=at+day,newExpiry=at+3*day,profile=api.starterProfile(uid,uid);profile.premiumUntil=oldExpiry;
 await seed(uid,profile,{[api.hash(oldToken)]:claim(uid,oldExpiry)});
 fixturePlay(t,uid,{[oldToken]:{expiry:oldExpiry,status:'SUBSCRIPTION_STATE_ON_HOLD'},[token]:{expiry:newExpiry}});
 const gate=holdRealClaimSnapshot(t),pending=api.reconcilePlayNotification(notification(oldToken),'local-sdk-old-revocation');
 try{
  await gate.captured;
  assert.equal((await writer.ref('purchaseClaims/'+api.hash(oldToken)+'/active').get()).val(),false);
  assert.equal((await api.fulfillPurchase(uid,{productId,purchaseToken:token})).entitlementGranted,true);
  assert.equal((await writer.ref('users/'+uid+'/premiumUntil').get()).val(),newExpiry);
 }finally{gate.release();}
 await pending;
 const actual=(await writer.ref('users/'+uid+'/premiumUntil').get()).val();
 const oldActive=(await writer.ref('purchaseClaims/'+api.hash(oldToken)+'/active').get()).val();
 record({case:'old-revocation-new-purchase',variant,expected:newExpiry,actual_after_refresh:actual,old_claim_active:oldActive,claim_query_reads:gate.queries()});
 assert.equal(oldActive,false);assert.equal(actual,newExpiry);
});

test('real RTDB: delayed active snapshot cannot restore a completed revocation',{timeout:25000},async t=>{
 const uid='premium_sdk_reverse',token='local-sdk-held-token',at=Date.now(),expiry=at+day;
 const profile=api.starterProfile(uid,uid);profile.premiumUntil=expiry;
 await seed(uid,profile,{[api.hash(token)]:claim(uid,expiry)});
 fixturePlay(t,uid,{[token]:{expiry,status:'SUBSCRIPTION_STATE_ON_HOLD'}});
 const gate=holdRealClaimSnapshot(t),pending=api.recomputePremiumFromClaims(uid,at);let revoked;
 try{
  await gate.captured;
  await api.reconcilePlayNotification(notification(token),'local-sdk-reverse-revocation');
  revoked=(await writer.ref('users/'+uid+'/premiumUntil').get()).val();assert.equal(revoked,0);
 }finally{gate.release();}
 await pending;
 const actual=(await writer.ref('users/'+uid+'/premiumUntil').get()).val();
 record({case:'stale-active-after-revocation',variant,expected:0,revoked_before_release:revoked,actual_after_refresh:actual,claim_query_reads:gate.queries()});
 assert.equal(actual,0);
});
