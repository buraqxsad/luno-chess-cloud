'use strict';
const {authHost,databaseHost}=require('./helpers/local-emulators').requireLocalEmulators();
const assert=require('node:assert/strict');
const {getApps,deleteApp}=require('firebase-admin/app');
const {getDatabase}=require('firebase-admin/database');
const {google}=require('googleapis');
const {handler,hash,writePurchaseClaim,reconcilePlayNotification}=require('../index')._test;
const db=getDatabase(),productId='luno_gold_1000',suffix=Date.now().toString(36);
async function timed(promise,label){
  let timer;
  try{return await Promise.race([promise,new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error(label+' timeout')),45000);})]);}
  finally{clearTimeout(timer);}
}
async function api(user,route,body,id){
  const headers={authorization:'Bearer '+user.idToken,'x-firebase-appcheck':'luno-emulator-app-check','x-luno-request-id':id,origin:'https://localhost'};
  let status,result;
  await timed(handler({method:'POST',path:'/'+route,body,get:name=>headers[name.toLowerCase()]||''},{set(){return this;},status(value){status=value;return this;},json(value){result=value;}}),route);
  return {status,body:result};
}
async function guest(prefix){
  const response=await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-key`,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({returnSecureToken:true}),signal:AbortSignal.timeout(15000)});
  const user=await response.json();assert.equal(response.status,200,JSON.stringify(user));
  assert.equal((await api(user,'createGuestPlayer',{username:prefix+'_'+suffix},'create-'+prefix+'-'+suffix)).status,200);return user;
}
function holdTransaction(path){
  const original=db.ref.bind(db);let enter,release,held=false;
  const entered=new Promise(resolve=>{enter=resolve;}),resume=new Promise(resolve=>{release=resolve;});
  db.ref=function(current){const ref=original(current);if(current===path){const tx=ref.transaction.bind(ref);ref.transaction=async function(...args){assert.equal(args[2],false);if(!held){held=true;enter();await resume;}return tx(...args);};}return ref;};
  return {entered,release,restore(){release();db.ref=original;}};
}
async function main(){
  const late=await guest('late'),lateKey=hash('late-'+suffix),latePath='purchaseClaims/'+lateKey,hold=holdTransaction(latePath);
  let pending;
  try{
    pending=writePurchaseClaim(late.localId,lateKey,productId,{status:'verified',verifiedAt:Date.now(),email:'private@example.com'},true);
    const rejected=assert.rejects(pending,{code:'account-deleted'});await timed(hold.entered,'late claim entry');
    assert.equal((await api(late,'deleteAccount',{confirm:true},'delete-late-'+suffix)).status,200);
    assert.equal((await db.ref(latePath).get()).exists(),false);hold.release();await timed(rejected,'late claim completion');
  }finally{hold.restore();}
  const retired=(await db.ref(latePath).get()).val();assert.equal(retired.uid,hash(late.localId));assert.equal(retired.accountDeleted,true);assert.equal(retired.active,false);assert.equal(retired.email,undefined);

  const reporter=await guest('rep'),target=await guest('tgt'),reportRequest='late-report-'+suffix,reportId='rp_'+hash(reporter.localId+':'+reportRequest).slice(0,30),reportPath='moderationReports/'+reportId;
  const reportHold=holdTransaction(reportPath);let reportResponse;
  try{
    const pendingReport=api(reporter,'reportUser',{targetUid:target.localId,reason:'harassment',details:'private@example.com'},reportRequest);
    await timed(reportHold.entered,'late report entry');assert.equal((await api(target,'deleteAccount',{confirm:true},'delete-target-'+suffix)).status,200);
    reportHold.release();reportResponse=await pendingReport;
  }finally{reportHold.restore();}
  assert.equal(reportResponse.status,403,JSON.stringify(reportResponse));assert.equal(reportResponse.body.error,'account-deleted');
  const report=(await db.ref(reportPath).get()).val();assert.equal(report.reporterUid,reporter.localId);assert.equal(report.targetUid,hash(target.localId));assert.equal(report.targetDeleted,true);assert.equal(report.reporterDeleted,undefined);assert.equal(report.details,undefined);
  assert.equal((await db.ref('users/'+reporter.localId).get()).exists(),true);

  // Provider responses are mocked; Auth, HTTP middleware, SDK transactions and
  // account deletion use the real local emulators. No Google Play request runs.
  const originalPublisher=google.androidpublisher;let buyer,failConsume=false,deleteDuringConsume=false;
  const calls={get:0,consume:0};
  google.androidpublisher=()=>({purchases:{
    productsv2:{async getproductpurchasev2(){calls.get++;return {data:{productLineItem:[{productId}],purchaseStateContext:{purchaseState:'PURCHASED'},obfuscatedExternalAccountId:hash(buyer.localId),orderId:'GPA-local-fixture'}};}},
    products:{async consume(){calls.consume++;if(failConsume){failConsume=false;throw new Error('private@example.com provider failure');}if(deleteDuringConsume){deleteDuringConsume=false;assert.equal((await api(buyer,'deleteAccount',{confirm:true},'delete-buyer-'+suffix)).status,200);}}}
  }});
  try{
    buyer=await guest('buy');const purchaseToken='local-retry-'+suffix,before=(await db.ref('users/'+buyer.localId+'/gold').get()).val();failConsume=true;
    const failed=await api(buyer,'verifyPurchase',{productId,purchaseToken},'purchase-first-'+suffix);assert.equal(failed.status,503);assert.equal(failed.body.error,'play-billing-unavailable');
    assert.equal((await db.ref('purchaseClaims/'+hash(purchaseToken)+'/lastError').get()).exists(),false);
    const complete=await api(buyer,'verifyPurchase',{productId,purchaseToken},'purchase-retry-'+suffix);assert.equal(complete.status,200,JSON.stringify(complete));
    const beforeReplay={...calls};assert.equal((await api(buyer,'verifyPurchase',{productId,purchaseToken},'purchase-replay-'+suffix)).status,200);assert.deepEqual(calls,beforeReplay);
    assert.equal((await db.ref('users/'+buyer.localId+'/gold').get()).val(),before+1000);
    assert.equal((await db.ref('purchaseClaims/'+hash(purchaseToken)+'/status').get()).val(),'complete');

    buyer=await guest('gone');const deletedToken='local-delete-'+suffix;deleteDuringConsume=true;
    const deletedPurchase=await api(buyer,'verifyPurchase',{productId,purchaseToken:deletedToken},'purchase-delete-'+suffix);
    assert.equal(deletedPurchase.status,403,JSON.stringify(deletedPurchase));assert.equal(deletedPurchase.body.error,'account-deleted');
    const deletedClaim=(await db.ref('purchaseClaims/'+hash(deletedToken)).get()).val();assert.equal(deletedClaim.uid,hash(buyer.localId));assert.equal(deletedClaim.accountDeleted,true);assert.equal(deletedClaim.active,false);
    assert.equal((await db.ref('users/'+buyer.localId).get()).exists(),false);
    const beforeNotification={...calls};const notification=await reconcilePlayNotification({packageName:'com.luno.chess',eventTimeMillis:String(Date.now()),oneTimeProductNotification:{sku:productId,purchaseToken:deletedToken,notificationType:1}},'retired-'+suffix);
    assert.equal(notification.status,'account-deleted');assert.equal(notification.handled,true);assert.deepEqual(calls,beforeNotification);assert.deepEqual((await db.ref('purchaseClaims/'+hash(deletedToken)).get()).val(),deletedClaim);
  }finally{google.androidpublisher=originalPublisher;}
  console.log('RETAINED_RECORD_RACE_INTEGRATION_PASS '+JSON.stringify({lateClaimAfterCompletedDeletion:true,lateReportAfterTargetDeletion:true,liveReporterPreserved:true,coldSdkFulfillment:true,consumeFailureRetryCreditedOnce:true,providerErrorsRedacted:true,consumptionDuringDeletionBlocked:true,retiredRtdnReadOnly:true,googlePlay:'mocked-no-live-calls',databaseHost}));
}
main().catch(error=>{console.error(error);process.exitCode=1;}).finally(async()=>{await Promise.all(getApps().map(deleteApp));});
