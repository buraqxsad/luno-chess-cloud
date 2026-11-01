'use strict';
const {createRequire,Module}=require('node:module');
const {readFileSync,writeFileSync}=require('node:fs');
const {resolve,dirname}=require('node:path');
const assert=require('node:assert/strict');
const test=require('node:test');
const {createHash}=require('node:crypto');
const req=createRequire('/workspace/luno-chess/functions/package.json');
const namespace='demo-luno-billing-fence-default-rtdb';
assert.equal(process.env.FIREBASE_DATABASE_EMULATOR_HOST,'127.0.0.1:19000');
assert.equal(process.env.LUNO_DB_EMULATOR_NAMESPACE,namespace);
assert.equal(process.env.GCLOUD_PROJECT,'demo-luno-billing-fence');
assert.equal(process.env.GOOGLE_APPLICATION_CREDENTIALS,undefined);
assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,undefined);
// The database SDK ignores NO_PROXY. Select the native loopback socket only;
// keep every proxy/header environment binding and all socket headers intact.
const proxyKeys=['HTTP_PROXY','HTTPS_PROXY','http_proxy','https_proxy','NO_PROXY','no_proxy'];
const inheritedProxyEnv=Object.fromEntries(proxyKeys.map(key=>[key,process.env[key]]));
const socketTransport=req('faye-websocket'),NativeClient=socketTransport.Client;
const transportAudit={adapter:'Exact loopback namespace only; delete options.proxy before native Client',selected_connections:0,rejected_other_urls:0,headers_preserved:true,protocols_preserved:true};
socketTransport.Client=class ExactLoopbackNativeClient extends NativeClient {
 constructor(url,protocols,options={}){
  const parsed=new URL(url);
  if(parsed.protocol!=='ws:'||parsed.hostname!=='127.0.0.1'||parsed.port!=='19000'||parsed.pathname!=='/.ws'||parsed.searchParams.get('ns')!==namespace||parsed.username||parsed.password){
   transportAudit.rejected_other_urls++;throw new Error('Only the isolated loopback database socket is allowed.');
  }
  const forwarded={...options};delete forwarded.proxy;
  transportAudit.selected_connections++;
  transportAudit.headers_preserved&&=forwarded.headers===options.headers;
  super(url,protocols,forwarded);
 }
};
assert.throws(()=>new socketTransport.Client('ws://example.invalid:19000/.ws?ns='+namespace,[],{}));
assert.throws(()=>new socketTransport.Client('ws://127.0.0.1:19000/.ws?ns=other-namespace',[],{}));

const root=dirname(__filename),original='/workspace/luno-chess/functions/index.js';
const captured=readFileSync(resolve(root,'fixed-index.cjs'),'utf8');
assert.equal(createHash('sha256').update(captured).digest('hex'),'5b0a8ef98fd05ee3d8414db884b617fdef44881c2c3c27ade8be5fbaa82aaf59');
const backend=new Module(original,module);backend.filename=original;
backend.paths=Module._nodeModulePaths(dirname(original));backend._compile(captured,original);
const api=backend.exports._test;
const {google}=req('googleapis');
const logger=req('firebase-functions/logger');
const {initializeApp,deleteApp,getApps}=req('firebase-admin/app');
const {getDatabase}=req('firebase-admin/database');
const db=getDatabase();
const checkerApp=initializeApp({projectId:'demo-luno-billing-fence',databaseURL:'http://127.0.0.1:19000?ns='+namespace},'billing-proof-independent-checker');
const checker=getDatabase(checkerApp),observations=[];
function record(value){observations.push(value);writeFileSync(resolve(root,'observations.json'),JSON.stringify(observations,null,2)+'\n');}
function proxied(target,methods){return new Proxy(target,{get(node,key){if(Object.hasOwn(methods,key))return methods[key];const v=Reflect.get(node,key,node);return typeof v==='function'?v.bind(node):v;}});}
function holdTransaction(t,pathToHold,ordinal=1){
 const originalRef=db.ref.bind(db);let calls=0,enter,release;
 const entered=new Promise(resolve=>{enter=resolve;}),resume=new Promise(resolve=>{release=resolve;});
 t.mock.method(db,'ref',(path='',...args)=>{
  const ref=originalRef(path,...args);if(path!==pathToHold)return ref;
  return proxied(ref,{async transaction(...transactionArgs){if(++calls===ordinal){enter();await resume;}return ref.transaction(...transactionArgs);}});
 });
 return {entered,release};
}
async function seed(uid){await checker.ref().set({users:{[uid]:api.starterProfile(uid,uid)}});assert.equal((await checker.ref('users/'+uid+'/uid').get()).val(),uid);}
function subNotification(token){return {packageName:'com.luno.chess',eventTimeMillis:String(Date.now()),subscriptionNotification:{purchaseToken:token,notificationType:5}};}
test.after(async()=>{
 await Promise.all(getApps().map(deleteApp));
 transportAudit.inherited_proxy_environment_unchanged=proxyKeys.every(key=>process.env[key]===inheritedProxyEnv[key]);
 transportAudit.native_client_used=true;
 writeFileSync(resolve(root,'transport-audit.json'),JSON.stringify(transportAudit,null,2)+'\n');
 assert.equal(transportAudit.inherited_proxy_environment_unchanged,true);
 assert.equal(transportAudit.headers_preserved,true);
 assert.ok(transportAudit.selected_connections>=2);
});

test('real SDK: confirmed pre-grant refund blocks a suspended currency transaction',{timeout:12000},async t=>{
 const uid='sdk_fence_refund',productId='luno_gold_1000',token='local-sdk-fence-refund-token',key=api.hash(token),claimPath='purchaseClaims/'+key;
 await seed(uid);const before=(await checker.ref('users/'+uid+'/gold').get()).val();let consumed=0;
 t.mock.method(logger,'error',()=>{});
 t.mock.method(google,'androidpublisher',()=>({purchases:{
  productsv2:{async getproductpurchasev2(){return {data:{productLineItem:[{productId,productOfferDetails:{consumptionState:'CONSUMPTION_STATE_YET_TO_BE_CONSUMED'}}],purchaseStateContext:{purchaseState:'PURCHASED'},obfuscatedExternalAccountId:api.hash(uid)}};}},
  products:{async consume(){consumed++;}},
  voidedpurchases:{async list(){return {data:{voidedPurchases:[{purchaseToken:token,voidedTimeMillis:String(Date.now()),voidedReason:1}]}};}},
 }}));
 const gate=holdTransaction(t,'users/'+uid),pending=api.fulfillPurchase(uid,{productId,purchaseToken:token});
 const completion=pending.then(value=>({value}),error=>({error}));
 try{
  await gate.entered;assert.equal((await checker.ref(claimPath+'/status').get()).val(),'verified');
  await api.reconcilePlayNotification({packageName:'com.luno.chess',eventTimeMillis:String(Date.now()),voidedPurchaseNotification:{purchaseToken:token}},'sdk-confirmed-pregrant-refund');
  assert.equal((await checker.ref(claimPath+'/voided').get()).val(),true);
  assert.equal((await checker.ref('users/'+uid+'/gold').get()).val(),before);
 }finally{gate.release();}
 const result=await completion;
 const actual=(await checker.ref('users/'+uid+'/gold').get()).val(),marker=(await checker.ref('users/'+uid+'/serverEconomy/billingReversals/'+key).get()).val(),receipt=(await checker.ref('users/'+uid+'/serverEconomy/purchaseTokens/'+key).get()).val();
 record({case:'pregrant-refund',expected_gold:before,actual_gold:actual,ungranted_marker:marker?.ungranted===true,purchase_receipt_absent:receipt===null,error_code:result.error?.code,provider_consume_calls:consumed});
 assert.equal(result.error?.code,'purchase-revoked');assert.equal(actual,before);assert.equal(marker.ungranted,true);assert.equal(receipt,null);assert.equal(consumed,0);
});

for(const phase of ['profile-grant','granted-claim'])test('real SDK: ON_HOLD fences suspended '+phase,{timeout:12000},async t=>{
 const uid=phase==='profile-grant'?'sdk_fence_profile':'sdk_fence_claim',productId='luno_premium_month',token='local-sdk-fence-'+phase,key=api.hash(token),claimPath='purchaseClaims/'+key,expiry=Date.now()+86400000;
 await seed(uid);let status='SUBSCRIPTION_STATE_ACTIVE',lookups=0;
 t.mock.method(logger,'error',()=>{});
 t.mock.method(google,'androidpublisher',()=>({purchases:{subscriptionsv2:{async get(){lookups++;return {data:{lineItems:[{productId,expiryTime:new Date(expiry).toISOString()}],subscriptionState:status,acknowledgementState:'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',externalAccountIdentifiers:{obfuscatedExternalAccountId:api.hash(uid)}}};}}}}));
 const gate=holdTransaction(t,phase==='profile-grant'?'users/'+uid:claimPath,phase==='profile-grant'?1:2),pending=api.fulfillPurchase(uid,{productId,purchaseToken:token});
 const completion=pending.then(value=>({value}),error=>({error}));let committedHold;
 try{
  await gate.entered;
  assert.equal((await checker.ref('users/'+uid+'/premiumUntil').get()).val()||0,phase==='granted-claim'?expiry:0);
  status='SUBSCRIPTION_STATE_ON_HOLD';const held=await api.reconcilePlayNotification(subNotification(token),'sdk-on-hold-'+phase);assert.equal(held.active,false);
  committedHold=(await checker.ref(claimPath).get()).val();assert.equal(committedHold.active,false);
  assert.equal((await checker.ref('users/'+uid+'/premiumUntil').get()).val(),0);
 }finally{gate.release();}
 const result=await completion,actual=(await checker.ref('users/'+uid+'/premiumUntil').get()).val(),currentClaim=(await checker.ref(claimPath).get()).val(),fence=(await checker.ref('users/'+uid+'/serverEconomy/subscriptionClaimRevisions/'+key).get()).val();
 record({case:'stale-subscription-'+phase,premium_until:actual,current_claim_active:currentClaim.active,current_claim_revision:currentClaim.claimRevision,installed_profile_fence:fence,error_code:result.error?.code,provider_lookups:lookups,newer_claim_unchanged:JSON.stringify(currentClaim)===JSON.stringify(committedHold)});
 assert.equal(result.error?.code,'subscription-state-changed');assert.equal(result.error?.status,503);assert.equal(actual,0);assert.equal(currentClaim.active,false);assert.deepEqual(currentClaim,committedHold);assert.equal(fence,currentClaim.claimRevision);
});
