'use strict';
const {createRequire,Module}=require('node:module');
const {readFileSync,writeFileSync}=require('node:fs');
const {resolve,dirname}=require('node:path');
const assert=require('node:assert/strict');
const test=require('node:test');
const {createHash}=require('node:crypto');
const req=createRequire('/workspace/luno-chess/functions/package.json');
const namespace='demo-luno-billing-fence-r2-final-default-rtdb';
assert.equal(process.env.FIREBASE_DATABASE_EMULATOR_HOST,'127.0.0.1:19000');
assert.equal(process.env.LUNO_DB_EMULATOR_NAMESPACE,namespace);
assert.equal(process.env.GCLOUD_PROJECT,'demo-luno-billing-fence-r2-final');
assert.equal(process.env.GOOGLE_APPLICATION_CREDENTIALS,undefined);
assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,undefined);

// The Admin SDK embeds its own websocket client inside database-compat/standalone.
// Compile exactly one transport-condition change in memory. SDK files and all
// database data/transaction logic remain byte-identical on disk and in memory.
const standalonePath=req.resolve('@firebase/database-compat/standalone');
assert.equal(require.cache[standalonePath],undefined);
const standaloneOriginal=readFileSync(standalonePath,'utf8');
const transportNeedle="if (proxy) {\n                    options['proxy'] = { origin: proxy };\n                }";
assert.equal(standaloneOriginal.split(transportNeedle).length-1,1);
const transportAudit={selected_connections:0,rejected_other_urls:0,headers_or_proxy_environment_changed:false,smoke_pass:false};
const proxyKeys=['HTTP_PROXY','HTTPS_PROXY','http_proxy','https_proxy','NO_PROXY','no_proxy'];
const inheritedProxyValues=Object.fromEntries(proxyKeys.map(key=>[key,process.env[key]]));
assert.ok(process.env.HTTP_PROXY||process.env.http_proxy,'This proof diagnoses the inherited-proxy path.');
function saveAudit(){transportAudit.inherited_proxy_environment_unchanged=proxyKeys.every(key=>process.env[key]===inheritedProxyValues[key]);writeFileSync(resolve(dirname(__filename),'transport-audit.json'),JSON.stringify(transportAudit,null,2)+'\n');}
globalThis.__LUNO_PROOF_LOOPBACK__=url=>{
 const parsed=new URL(url);
 if(parsed.protocol!=='ws:'||parsed.hostname!=='127.0.0.1'||parsed.port!=='19000'||parsed.pathname!=='/.ws'||parsed.searchParams.get('ns')!==namespace||parsed.username||parsed.password){transportAudit.rejected_other_urls++;saveAudit();throw new Error('Proof refuses a non-local emulator socket.');}
 transportAudit.selected_connections++;saveAudit();return true;
};
const standalonePatched=standaloneOriginal.replace(transportNeedle,transportNeedle.replace('if (proxy)', 'if (proxy && !globalThis.__LUNO_PROOF_LOOPBACK__(this.connURL))'));
const standaloneModule=new Module(standalonePath,module);standaloneModule.filename=standalonePath;standaloneModule.paths=Module._nodeModulePaths(dirname(standalonePath));require.cache[standalonePath]=standaloneModule;standaloneModule._compile(standalonePatched,standalonePath);standaloneModule.loaded=true;
const transportProvenance={standalone_module:standalonePath,original_sha256:createHash('sha256').update(standaloneOriginal).digest('hex'),in_memory_sha256:createHash('sha256').update(standalonePatched).digest('hex'),exact_replaced_blocks:1,changed_transport_condition_only:true,repo_or_sdk_disk_files_modified:false};
writeFileSync(resolve(dirname(__filename),'transport-provenance.json'),JSON.stringify(transportProvenance,null,2)+'\n');

const root=dirname(__filename),original='/workspace/luno-chess/functions/index.js';
const captured=readFileSync(resolve(root,'fixed-index.cjs'),'utf8');
const sourceTarget=JSON.parse(readFileSync(resolve(root,'source-target.json'),'utf8'));
assert.equal(createHash('sha256').update(captured).digest('hex'),sourceTarget.index_sha256);
const backend=new Module(original,module);backend.filename=original;
backend.paths=Module._nodeModulePaths(dirname(original));backend._compile(captured,original);
const api=backend.exports._test;
const {google}=req('googleapis');
const logger=req('firebase-functions/logger');
const {initializeApp,deleteApp,getApps}=req('firebase-admin/app');
const {getDatabase}=req('firebase-admin/database');
const db=getDatabase();
const checkerApp=initializeApp({projectId:'demo-luno-billing-fence-r2-final',databaseURL:'http://127.0.0.1:19000?ns='+namespace},'billing-proof-independent-checker');
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
test.before(async()=>{
 const timer=setTimeout(()=>{},3000);clearTimeout(timer);
 let timeout;
 try{
  await Promise.race([(async()=>{await checker.ref('round2Smoke').set({value:7});assert.equal((await checker.ref('round2Smoke/value').get()).val(),7);await checker.ref('round2Smoke').remove();})(),new Promise((_,reject)=>{timeout=setTimeout(()=>reject(new Error('3s isolated SDK seed/read smoke failed.')),3000);})]);
  transportAudit.smoke_pass=true;saveAudit();
 }finally{clearTimeout(timeout);}
});
test.after(async()=>{await Promise.all(getApps().map(deleteApp));saveAudit();assert.equal(transportAudit.inherited_proxy_environment_unchanged,true);assert.equal(createHash('sha256').update(readFileSync(standalonePath)).digest('hex'),transportProvenance.original_sha256);});

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


test('real SDK: owned fresh ON_HOLD verification revokes access without an RTDN',{timeout:12000},async t=>{
 const uid='sdk_fence_owned_inactive',productId='luno_premium_month',token='local-sdk-owned-inactive-token',key=api.hash(token),claimPath='purchaseClaims/'+key,expiry=Date.now()+86400000;
 await seed(uid);
 const beforeGold=(await checker.ref('users/'+uid+'/gold').get()).val();
 let status='SUBSCRIPTION_STATE_ACTIVE',lookups=0;
 t.mock.method(logger,'error',()=>{});
 t.mock.method(google,'androidpublisher',()=>({purchases:{subscriptionsv2:{async get(){lookups++;return {data:{lineItems:[{productId,expiryTime:new Date(expiry).toISOString()}],subscriptionState:status,acknowledgementState:'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',externalAccountIdentifiers:{obfuscatedExternalAccountId:api.hash(uid)}}};}}}}));
 const granted=await api.fulfillPurchase(uid,{productId,purchaseToken:token});
 assert.equal(granted.entitlementGranted,true);
 assert.equal((await checker.ref('users/'+uid+'/premiumUntil').get()).val(),expiry);
 const activeClaim=(await checker.ref(claimPath).get()).val();
 assert.equal(activeClaim.uid,uid);assert.equal(activeClaim.productId,productId);assert.equal(activeClaim.active,true);
 const lookupsAfterGrant=lookups;
 status='SUBSCRIPTION_STATE_ON_HOLD';
 // No RTDN is invoked. The owned token's fresh provider reply is the authority.
 await assert.rejects(api.fulfillPurchase(uid,{productId,purchaseToken:token}),{code:'purchase-not-active',status:409});
 const currentClaim=(await checker.ref(claimPath).get()).val();
 const premium=(await checker.ref('users/'+uid+'/premiumUntil').get()).val();
 const fence=(await checker.ref('users/'+uid+'/serverEconomy/subscriptionClaimRevisions/'+key).get()).val();
 const actualGold=(await checker.ref('users/'+uid+'/gold').get()).val();
 record({case:'fresh-owned-inactive-without-rtdn',initial_owned_grant:true,initial_claim_revision:activeClaim.claimRevision,current_claim_revision:currentClaim.claimRevision,installed_profile_fence:fence,premium_until:premium,current_claim_active:currentClaim.active,entitlement_status:currentClaim.entitlementStatus,provider_lookups_for_inactive:lookups-lookupsAfterGrant,rtdn_invoked_by_test:false,expected_gold:beforeGold,actual_gold:actualGold});
 assert.equal(currentClaim.uid,uid);assert.equal(currentClaim.productId,productId);assert.equal(currentClaim.active,false);
 assert.equal(currentClaim.entitlementStatus,'SUBSCRIPTION_STATE_ON_HOLD');
 assert.ok(currentClaim.claimRevision>activeClaim.claimRevision);
 assert.equal(premium,0);assert.equal(fence,currentClaim.claimRevision);assert.equal(actualGold,beforeGold);
 assert.equal(lookups-lookupsAfterGrant,1);
});
