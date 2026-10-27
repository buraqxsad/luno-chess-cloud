'use strict';

const {authHost,databaseHost}=require('./helpers/local-emulators').requireLocalEmulators();
const assert=require('node:assert/strict');
const {fork}=require('node:child_process');
const {getApps,deleteApp}=require('firebase-admin/app');
const {getDatabase}=require('firebase-admin/database');
const {handler,purchaseSoftItem,hash,sourceClaimKey,periodSnapshot,PASS_CHEST_RECOVERY_MS}=require('../index')._test;
const db=getDatabase();
async function anonymousUser(){
  const response=await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-key`,{
    method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({returnSecureToken:true}),signal:AbortSignal.timeout(15000)
  });
  const body=await response.json();assert.equal(response.status,200,JSON.stringify(body));return body;
}
async function httpCall(user,route,body,id){
  const headers={authorization:'Bearer '+user.idToken,'x-firebase-appcheck':'luno-emulator-app-check','x-luno-request-id':id,origin:'https://localhost'};
  let status,result;
  await handler({method:'POST',path:'/'+route,body,get:name=>headers[name.toLowerCase()]||''},
    {set(){return this;},status(value){status=value;return this;},json(value){result=value;}});
  return {status,body:result};
}
async function createGuest(user,username,id){
  const {status,body:result}=await httpCall(user,'createGuestPlayer',{username},id);
  assert.equal(status,200,JSON.stringify(result));
  return result;
}
function requestPath(uid,id){return `serverRequests/${uid}/${hash(id).slice(0,48)}`;}
function receiptKey(uid,season){return sourceClaimKey(uid,'soft_purchase',season+':pass:premium');}
async function callPurchase(uid,id,season){
  try{return {status:200,body:await purchaseSoftItem({uid,requestId:id,body:{itemId:'pass:premium',seasonId:season}})};}
  catch(error){if(!error.status)throw error;return {status:error.status,body:{error:error.code}};}
}
function launch(uid,id,season,at,mode='normal'){
  const child=fork(__filename,['worker'],{stdio:['ignore','pipe','pipe','ipc'],windowsHide:true});
  let message,output='',intentionalStop=false,resolveReady,rejectReady;
  const ready=new Promise((resolve,reject)=>{resolveReady=resolve;rejectReady=reject;});ready.catch(()=>{});
  const result=new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>{child.kill();reject(new Error('Premium recovery worker timeout: '+mode));},55000);
    for(const stream of [child.stdout,child.stderr])stream.on('data',chunk=>{output=(output+chunk).slice(-4000);});
    child.on('message',value=>{if(value.ready)resolveReady();else message=value;});
    child.once('error',error=>{clearTimeout(timer);rejectReady(error);reject(error);});
    child.once('exit',code=>{
      clearTimeout(timer);
      if(intentionalStop){resolveReady();resolve({stopped:true});return;}
      if(code!==0||!message||message.error){const error=new Error(message&&message.error||'Premium worker failed: '+code+' '+output);rejectReady(error);reject(error);}
      else{resolveReady();resolve(message.result);}
    });
  });result.catch(()=>{});child.send({uid,id,season,at,mode});
  return {ready,result,resume:at=>child.send({resume:true,at}),stop:async()=>{intentionalStop=true;child.kill();await result;}};
}
async function main(){
  const user=await anonymousUser(),uid=user.localId,at=Date.now(),period=periodSnapshot(at),season=period.seasonId,
    nextAt=period.seasonEndAt+1000,nextSeason=periodSnapshot(nextAt).seasonId,suffix=at.toString(36),id='premium-killed-'+suffix;
  assert.notEqual(season,nextSeason);
  await createGuest(user,'pass_'+suffix,'create-'+suffix);
  await db.ref('users/'+uid+'/gems').set(30000);
  const killed=launch(uid,id,season,at,'after-purchase');
  try{
    await killed.ready;
    const committed=(await db.ref('users/'+uid).get()).val(),receipt=committed.serverEconomy.purchases[receiptKey(uid,season)];
    assert.equal(committed.gems,29550);assert.equal(receipt.requestIdHash,hash(id));
    assert.equal(committed.serverEconomy.passPurchaseRequests[hash(id)],season);
    assert.equal(committed.passState.premium,true);
    assert.equal((await db.ref(requestPath(uid,id)+'/status').get()).val(),'processing');
    await killed.stop();
    // Only the lease and worker clock are fixtures; profile transactions use the real emulator SDK.
    await db.ref(requestPath(uid,id)+'/startedAt').set(at-PASS_CHEST_RECOVERY_MS-1000);
    const recovered=await Promise.all(Array.from({length:5},()=>launch(uid,id,season,at).result));
    assert.ok(recovered.some(response=>response.status===200));
    for(const response of recovered){
      assert.ok(response.status===200||response.status===409&&response.body.error==='request-in-progress',JSON.stringify(response));
      if(response.status===200){assert.equal(response.body.purchased,false);assert.equal(response.body.transactionId,receipt.transactionId);assert.equal(response.body.passActive,true);}
    }
    assert.deepEqual((await db.ref('users/'+uid).get()).val(),committed);
    await db.ref('users/'+uid+'/gems').set(0);
    const cached=await launch(uid,id,season,nextAt).result;
    assert.equal(cached.status,200,JSON.stringify(cached));assert.equal(cached.body.passActive,false);
    assert.equal(cached.body.currentSeasonId,nextSeason);assert.equal(cached.body.state.gems,0);assert.equal(cached.body.state.passState.premium,false);
    await db.ref(requestPath(uid,id)).remove();
    const replay=await launch(uid,id,season,nextAt).result;
    assert.equal(replay.status,200,JSON.stringify(replay));assert.equal(replay.body.transactionId,receipt.transactionId);assert.equal(replay.body.passActive,false);
    const before=(await db.ref('users/'+uid).get()).val();
    const alias=await launch(uid,'expired-alias-'+suffix,season,nextAt).result;
    assert.equal(alias.status,200,JSON.stringify(alias));assert.equal(alias.body.purchased,false);assert.equal(alias.body.passActive,false);
    await db.ref(requestPath(uid,id)).remove();
    const wrong=await launch(uid,id,nextSeason,nextAt).result;
    assert.equal(wrong.status,409);assert.equal(wrong.body.error,'request-id-conflict');
    assert.deepEqual((await db.ref('users/'+uid).get()).val(),before);
  }finally{await killed.stop();}

  const second=await anonymousUser(),secondUid=second.localId,delayedId='premium-delayed-'+suffix;
  await createGuest(second,'pass2_'+suffix,'create2-'+suffix);await db.ref('users/'+secondUid+'/gems').set(30000);
  const delayed=launch(secondUid,delayedId,season,at,'before-purchase');
  try{
    await delayed.ready;await db.ref(requestPath(secondUid,delayedId)+'/startedAt').set(at-PASS_CHEST_RECOVERY_MS-1000);
    const winner=await launch(secondUid,delayedId,season,at).result;
    assert.equal(winner.status,200,JSON.stringify(winner));assert.equal(winner.body.purchased,true);
    const committed=(await db.ref('users/'+secondUid).get()).val();
    delayed.resume(at);const old=await delayed.result;
    assert.equal(old.status,503,JSON.stringify(old));assert.equal(old.body.error,'request-state-changed');
    assert.deepEqual((await db.ref('users/'+secondUid).get()).val(),committed);
    assert.equal((await db.ref(requestPath(secondUid,delayedId)+'/status').get()).val(),'complete');
  }finally{await delayed.stop();}

  const third=await anonymousUser(),thirdUid=third.localId,boundaryId='premium-boundary-'+suffix;
  await createGuest(third,'pass3_'+suffix,'create3-'+suffix);await db.ref('users/'+thirdUid+'/gems').set(30000);
  const boundary=launch(thirdUid,boundaryId,season,at,'before-purchase');
  try{
    await boundary.ready;const before=(await db.ref('users/'+thirdUid).get()).val();
    boundary.resume(nextAt);const changed=await boundary.result;
    assert.equal(changed.status,409,JSON.stringify(changed));assert.equal(changed.body.error,'pass-season-changed');
    assert.deepEqual((await db.ref('users/'+thirdUid).get()).val(),before);
    const unpaid=await launch(thirdUid,'expired-unpaid-'+suffix,season,nextAt).result;
    assert.equal(unpaid.status,409,JSON.stringify(unpaid));assert.equal(unpaid.body.error,'pass-season-changed');
    assert.deepEqual((await db.ref('users/'+thirdUid).get()).val(),before);
  }finally{await boundary.stop();}
  const fourth=await anonymousUser();await createGuest(fourth,'pass4_'+suffix,'create4-'+suffix);
  await db.ref('users/'+fourth.localId+'/gems').set(900);
  const refreshed=await httpCall(fourth,'getPlayerState',{},'state4-'+suffix);assert.equal(refreshed.status,200);
  const serverSeason=refreshed.body.state.economy.periods.seasonId;
  const oldClient=await httpCall(fourth,'purchaseSoftItem',{itemId:'pass:premium'},'legacy4-'+suffix);
  assert.equal(oldClient.status,409);assert.equal(oldClient.body.error,'pass-season-required');
  const fresh=await httpCall(fourth,'purchaseSoftItem',{itemId:'pass:premium',seasonId:serverSeason},'premium4-'+suffix);
  assert.equal(fresh.status,200,JSON.stringify(fresh));assert.equal(fresh.body.purchased,true);assert.equal(fresh.body.passActive,true);assert.equal(fresh.body.state.gems,450);
  await db.ref('users/'+fourth.localId+'/gems').set(0);
  const cachedHttp=await httpCall(fourth,'purchaseSoftItem',{itemId:'pass:premium',seasonId:serverSeason},'premium4-'+suffix);
  assert.equal(cachedHttp.status,200,JSON.stringify(cachedHttp));assert.equal(cachedHttp.body.purchased,false);assert.equal(cachedHttp.body.state.gems,0);
  console.log('PASS_PREMIUM_PURCHASE_RECOVERY_INTEGRATION_PASS '+JSON.stringify({killedAfterPurchase:1,independentRecoveryWorkers:5,heldBeforePurchase:2,secondDebit:false,expiredReplayInactive:true,currentPremiumNotGranted:true,transactionBoundaryRechecked:true,durableSeasonBinding:true,databaseHost,clockFixture:true,purchaseRouteDirect:true,freshAndCachedHttpHandler:true,missingSeasonDenied:true}));
}
if(process.argv[2]==='worker'){
  process.once('message',async request=>{
    const realNow=Date.now,original=db.ref.bind(db),target=requestPath(request.uid,request.id);let calls=0,paused=false,message,clock=request.at;
    Date.now=()=>clock;
    db.ref=function(path){
      const ref=original(path),matches=request.mode==='after-purchase'?path===target:request.mode==='before-purchase'&&path==='users/'+request.uid;
      if(matches){const transaction=ref.transaction.bind(ref);ref.transaction=async function(...args){
        calls++;if(!paused&&calls===(request.mode==='after-purchase'?2:1)){
          paused=true;const resumed=new Promise(resolve=>process.once('message',resolve));process.send({ready:true});const resume=await resumed;if(resume.at)clock=resume.at;
        }return transaction(...args);
      };}return ref;
    };
    try{message={result:await callPurchase(request.uid,request.id,request.season)};}
    catch(error){message={error:error.stack||String(error)};}
    finally{db.ref=original;Date.now=realNow;await Promise.all(getApps().map(deleteApp));}
    await new Promise(resolve=>process.send(message,resolve));process.disconnect();
  });
}else{
  main().catch(error=>{console.error(error);process.exitCode=1;}).finally(async()=>{await Promise.all(getApps().map(deleteApp));});
}
