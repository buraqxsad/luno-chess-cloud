'use strict';

const {authHost,databaseHost}=require('./helpers/local-emulators').requireLocalEmulators();
const assert=require('node:assert/strict');
const {fork}=require('node:child_process');
const {getApps,deleteApp}=require('firebase-admin/app');
const {getDatabase}=require('firebase-admin/database');
const {handler,playerCode,syncServerPass,idempotent,ONBOARDING_REWARD}=require('../index')._test;
const db=getDatabase();

async function anonymousUser(){
  const response=await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-key`,{
    method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({returnSecureToken:true}),signal:AbortSignal.timeout(15000),
  });
  const body=await response.json();assert.equal(response.status,200,JSON.stringify(body));return body;
}
async function api(path,token,body,id){
  const headers={authorization:'Bearer '+token,'x-firebase-appcheck':'luno-emulator-app-check','x-luno-request-id':id,origin:'https://localhost'};
  let status,responseBody,timer;
  const req={method:'POST',path,body:body||{},get:name=>headers[name.toLowerCase()]||''};
  const res={set(){return this;},status(value){status=value;return this;},json(value){responseBody=value;return this;},send(value){responseBody=value;return this;}};
  try{
    await Promise.race([handler(req,res),new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('API timeout: '+path)),45000);})]);
  }finally{clearTimeout(timer);}
  return {status,body:responseBody};
}
function crossInstance(path,user,body,id,onReady){
  return new Promise((resolve,reject)=>{
    const child=fork(__filename,['worker'],{stdio:['ignore','pipe','pipe','ipc'],windowsHide:true});
    let message,output='',settled=false;
    const timer=setTimeout(()=>{child.kill();finish(new Error('Cross-instance timeout: '+path));},55000);
    function finish(error){if(settled)return;settled=true;clearTimeout(timer);if(error)reject(error);else resolve(message.result);}
    child.stdout.on('data',chunk=>{output=(output+chunk).slice(-4000);});
    child.stderr.on('data',chunk=>{output=(output+chunk).slice(-4000);});
    child.on('message',value=>{
      if(value.ready){
        Promise.resolve().then(onReady).then(()=>child.send({resume:true})).catch(error=>{child.kill();finish(error);});
      }else message=value;
    });
    child.once('error',finish);
    child.once('exit',code=>{
      if(code!==0||!message||message.error)finish(new Error(message&&message.error||'Worker failed: '+code+' '+output));
      else finish();
    });
    child.send({path,token:user.idToken,uid:user.localId,body,id});
  });
}
function ok(result,label){assert.equal(result.status,200,label+': '+JSON.stringify(result.body));return result.body;}

async function main(){
  const suffix=Date.now().toString(36),first=await anonymousUser();
  const missing=await api('/getPlayerState',first.idToken,{},'missing-'+suffix);
  assert.equal(missing.status,404,JSON.stringify(missing.body));
  assert.equal((await db.ref(`users/${first.localId}`).get()).exists(),false);

  await db.ref(`users/${first.localId}`).set({serverActivity:{lastLoginDay:Math.floor(Date.now()/86400000),loginStreak:1},username:'remnant_'+suffix,name:'remnant_'+suffix});
  await db.ref('usernames/remnant_'+suffix).set(first.localId);
  const partial=await api('/getPlayerState',first.idToken,{},'partial-'+suffix);
  assert.equal(partial.status,404,JSON.stringify(partial.body));
  ok(await api('/createGuestPlayer',first.idToken,{username:'fresh_'+suffix},'create-'+suffix),'recover incomplete guest');
  assert.equal((await db.ref('usernames/remnant_'+suffix).get()).val(),null);
  const initial=ok(await api('/getPlayerState',first.idToken,{},'state-'+suffix),'read recovered guest');
  assert.equal(initial.state.uid,first.localId);assert.equal(initial.state.gold,1250);assert.equal(initial.state.gems,50);
  assert.equal((await db.ref(`users/${first.localId}/serverActivity/loginStreak`).get()).val(),1);
  ok(await api('/acceptLegalTerms',first.idToken,{},'consent-'+suffix),'accept UGC rules');

  const desired='renamed_'+suffix;
  const renames=await Promise.all(Array.from({length:5},(_,index)=>crossInstance('/changeUsername',first,{username:desired},'rename-'+index+'-'+suffix)));
  renames.forEach((result,index)=>ok(result,'cross-instance rename '+index));
  assert.equal(renames.filter(result=>result.body.changed===true).length,1);
  const renamed=(await db.ref(`users/${first.localId}`).get()).val();
  assert.equal(renamed.username,desired);assert.equal(renamed.name,desired);assert.equal(renamed.usernameChanges,0);assert.equal(renamed.gold,1250);
  assert.equal(renamed.usernameGenerated,false);
  const owned=(await db.ref('usernames').orderByValue().equalTo(first.localId).get()).val();
  assert.deepEqual(Object.keys(owned),[desired]);
  assert.equal((await db.ref(`usernameLocks/${first.localId}`).get()).val(),null);

  const passProfile={passState:null,premiumUntil:0};syncServerPass(passProfile,Date.now());
  passProfile.passState.premium=true;passProfile.passState.level=12;passProfile.passState.claimed.premium={3:true};
  await db.ref(`users/${first.localId}`).update({passState:passProfile.passState,gold:9876,deck:[...renamed.deck].reverse()});
  const refreshes=await Promise.all(Array.from({length:5},(_,index)=>crossInstance('/getPlayerState',first,{},'refresh-'+index+'-'+suffix)));
  for(const result of refreshes){
    const state=ok(result,'cold-instance player refresh').state;
    assert.equal(state.gold,9876);assert.equal(state.passState.premium,true);assert.equal(state.passState.level,12);
    assert.deepEqual(state.deck,[...renamed.deck].reverse());assert.equal(state.passState.claimed.premium[3],true);
  }
  assert.equal((await db.ref(`users/${first.localId}/serverActivity/loginStreak`).get()).val(),1);
  assert.equal((await db.ref('playerCodes/'+playerCode(first.localId).toLowerCase()).get()).val(),first.localId);

  const second=await anonymousUser(),third=await anonymousUser(),contested='shared_'+suffix;
  const creations=await Promise.all([second,third].map((user,index)=>crossInstance('/createGuestPlayer',user,{username:contested},'claim-'+index+'-'+suffix)));
  creations.forEach((result,index)=>{
    const created=ok(result,'server alias '+index);
    assert.equal(created.usernameGenerated,true);assert.notEqual(created.username,contested);
  });
  assert.notEqual(creations[0].body.username,creations[1].body.username);
  assert.equal((await db.ref('usernames/'+contested).get()).val(),null);
  for(const user of [second,third])ok(await api('/acceptLegalTerms',user.idToken,{},'consent-'+user.localId+'-'+suffix),'accept contested name rules');
  const choices=await Promise.all([second,third].map((user,index)=>crossInstance('/changeUsername',user,{username:contested},'choice-'+index+'-'+suffix)));
  assert.equal(choices.filter(result=>result.status===200).length,1);
  assert.equal(choices.filter(result=>result.status===409&&result.body.error==='username-taken').length,1);
  const owner=(await db.ref('usernames/'+contested).get()).val();
  assert.ok([second.localId,third.localId].includes(owner));
  const loser=owner===second.localId?third:second;
  const losingProfile=(await db.ref('users/'+loser.localId).get()).val();
  assert.equal(losingProfile.uid,loser.localId);assert.notEqual(losingProfile.username,contested);
  assert.equal(losingProfile.gold,1250);assert.equal(losingProfile.usernameGenerated,true);
  for(const user of [second,third])assert.equal((await db.ref('usernameLocks/'+user.localId).get()).val(),null);

  const originalCode=playerCode(first.localId);
  await db.ref(`playerCodes/${originalCode.toLowerCase()}`).set(owner);
  const codeRefreshes=await Promise.all(Array.from({length:5},(_,index)=>crossInstance('/getPlayerState',first,{},'code-refresh-'+index+'-'+suffix)));
  const codes=codeRefreshes.map(result=>ok(result,'recover colliding code').state.profile.playerCode);
  assert.equal(new Set(codes).size,1);assert.notEqual(codes[0],originalCode);
  assert.equal((await db.ref('playerCodes/'+originalCode.toLowerCase()).get()).val(),owner);
  assert.equal((await db.ref('playerCodes/'+codes[0].toLowerCase()).get()).val(),first.localId);
  assert.equal((await db.ref('publicProfiles/'+first.localId+'/playerCode').get()).val(),codes[0]);

  const rewardId='shared-onboarding-'+suffix;
  const claims=await Promise.all(Array.from({length:5},()=>crossInstance('/claimOnboardingReward',first,{},rewardId)));
  for(const claim of claims){
    assert.ok(claim.status===200||claim.status===409&&claim.body.error==='request-in-progress',JSON.stringify(claim));
  }
  assert.ok(claims.some(claim=>claim.status===200));
  const replay=ok(await api('/claimOnboardingReward',first.idToken,{},rewardId),'replay completed reward');
  assert.equal(replay.idempotent,true);
  assert.equal((await db.ref(`users/${first.localId}/gold`).get()).val(),9876+ONBOARDING_REWARD.gold);

  await db.ref('usernames/'+desired).set(owner);
  await db.ref(`users/${first.localId}/playerCode`).set(originalCode);
  const alias=playerCode(first.localId,15).toLowerCase();
  await db.ref('playerCodes/'+alias).set(first.localId);
  ok(await api('/deleteAccount',first.idToken,{confirm:true},'delete-corrupt-index-'+suffix),'delete legacy index mismatch');
  assert.equal((await db.ref('usernames/'+desired).get()).val(),owner);
  assert.equal((await db.ref('playerCodes/'+originalCode.toLowerCase()).get()).val(),owner);
  assert.equal((await db.ref('playerCodes/'+codes[0].toLowerCase()).get()).val(),null);
  assert.equal((await db.ref('playerCodes/'+alias).get()).val(),null);
  assert.equal((await db.ref(`serverRequests/${first.localId}`).get()).exists(),false);

  const delayed=await anonymousUser();
  ok(await api('/createGuestPlayer',delayed.idToken,{username:'delayed_'+suffix},'delayed-create-'+suffix),'create delayed account');
  const late=await crossInstance('__hold_request__',delayed,{},'held-'+suffix,async()=>{
    ok(await api('/deleteAccount',delayed.idToken,{confirm:true},'delete-held-'+suffix),'delete during held operation');
  });
  assert.equal(late.status,403,JSON.stringify(late.body));assert.equal(late.body.error,'account-deleted');
  assert.equal((await db.ref(`serverRequests/${delayed.localId}`).get()).exists(),false);
  assert.equal((await db.ref(`users/${delayed.localId}`).get()).exists(),false);
  console.log('PLAYER_STATE_INTEGRATION_PASS '+JSON.stringify({crossInstanceApiRequests:24,crossInstanceDelayedOperations:1,normalizationRemnantRecovered:true,usernameSingleOwner:true,codeCollisionRecovered:true,sharedRewardGrantedOnce:true,foreignIndexesPreserved:true,lateCacheNotRecreated:true,databaseHost}));
}

if(process.argv[2]==='worker'){
  process.once('message',async request=>{
    let message;
    try{
      if(request.path==='__hold_request__'){
        try{
          const result=await idempotent(request.uid,request.id,'test-delayed-operation',async()=>{
            const resumed=new Promise(resolve=>process.once('message',resolve));
            process.send({ready:true});await resumed;return {ok:true};
          });
          message={result:{status:200,body:result}};
        }catch(error){message={result:{status:error.status||500,body:{error:error.code||'internal'}}};}
      }else message={result:await api(request.path,request.token,request.body,request.id)};
    }
    catch(error){message={error:String(error.stack||error)};process.exitCode=1;}
    finally{await Promise.all(getApps().map(deleteApp));}
    await new Promise(resolve=>process.send(message,resolve));
    process.disconnect();
  });
}else{
  main().catch(error=>{console.error(error);process.exitCode=1;}).finally(async()=>{await Promise.all(getApps().map(deleteApp));});
}
