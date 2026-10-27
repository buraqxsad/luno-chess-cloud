'use strict';

const {authHost,databaseHost}=require('./helpers/local-emulators').requireLocalEmulators();
const assert=require('node:assert/strict');
const {fork}=require('node:child_process');
const {getApps,deleteApp}=require('firebase-admin/app');
const {getDatabase}=require('firebase-admin/database');
const {handler,hash,sourceClaimKey,PASS_CHEST_RECOVERY_MS}=require('../index')._test;
const db=getDatabase();
async function anonymousUser(){
  const response=await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-key`,{
    method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({returnSecureToken:true}),signal:AbortSignal.timeout(15000)
  });
  const body=await response.json();assert.equal(response.status,200,JSON.stringify(body));return body;
}
async function api(route,user,body,id){
  const headers={authorization:'Bearer '+user.idToken,'x-firebase-appcheck':'luno-emulator-app-check','x-luno-request-id':id,origin:'https://localhost'};
  let status,result,timer;
  try{
    await Promise.race([
      handler({method:'POST',path:'/'+route,body,get:name=>headers[name.toLowerCase()]||''},
        {set(){return this;},status(value){status=value;return this;},json(value){result=value;}}),
      new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('API timeout: '+route)),45000);})
    ]);
  }finally{clearTimeout(timer);}
  return {status,body:result};
}
function launch(user,id,mode='normal'){
  const child=fork(__filename,['worker'],{stdio:['ignore','pipe','pipe','ipc'],windowsHide:true});
  let message,output='',intentionalStop=false,resolveReady,rejectReady;
  const ready=new Promise((resolve,reject)=>{resolveReady=resolve;rejectReady=reject;});ready.catch(()=>{});
  const result=new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>{child.kill();reject(new Error('Shop recovery worker timeout: '+mode));},55000);
    for(const stream of [child.stdout,child.stderr])stream.on('data',chunk=>{output=(output+chunk).slice(-4000);});
    child.on('message',value=>{if(value.ready)resolveReady();else message=value;});
    child.once('error',error=>{clearTimeout(timer);rejectReady(error);reject(error);});
    child.once('exit',code=>{
      clearTimeout(timer);
      if(intentionalStop){resolveReady();resolve({stopped:true});return;}
      if(code!==0||!message||message.error){const error=new Error(message&&message.error||'Shop worker failed: '+code+' '+output);rejectReady(error);reject(error);}
      else{resolveReady();resolve(message.result);}
    });
  });result.catch(()=>{});child.send({user,id,mode});
  return {ready,result,resume:()=>child.send({resume:true}),stop:async()=>{intentionalStop=true;child.kill();await result;}};
}
function requestPath(uid,id){return `serverRequests/${uid}/${hash(id).slice(0,48)}`;}
function purchaseKey(uid,id){return sourceClaimKey(uid,'chest_purchase','rare:'+hash(id).slice(0,32));}
async function main(){
  const user=await anonymousUser(),uid=user.localId,suffix=Date.now().toString(36),id='shop-killed-'+suffix;
  const created=await api('createGuestPlayer',user,{username:'shop_'+suffix},'create-'+suffix);
  assert.equal(created.status,200,JSON.stringify(created.body));
  await db.ref('users/'+uid).update({gold:30000,gems:3000});
  const killed=launch(user,id,'after-purchase');
  try{
    await killed.ready;
    const committed=(await db.ref('users/'+uid).get()).val(),receipt=committed.serverEconomy.purchases[purchaseKey(uid,id)];
    assert.equal(committed.stats.chestsOpened,1);assert.ok(receipt.outcome.rewards.length>0);
    const gold=receipt.outcome.rewards.filter(reward=>reward.type==='gold').reduce((sum,reward)=>sum+reward.amount,0);
    assert.equal(committed.gold,30000-1500+gold);
    assert.equal((await db.ref(requestPath(uid,id)+'/status').get()).val(),'processing');
    await killed.stop();
    // Age only the processing lease, keeping the real debit/drop receipt intact.
    await db.ref(requestPath(uid,id)+'/startedAt').set(Date.now()-PASS_CHEST_RECOVERY_MS-1000);
    const recovered=await Promise.all(Array.from({length:5},()=>launch(user,id).result));
    assert.ok(recovered.some(response=>response.status===200));
    for(const response of recovered){
      assert.ok(response.status===200||response.status===409&&response.body.error==='request-in-progress',JSON.stringify(response));
      if(response.status===200){assert.deepEqual(response.body.rewards,receipt.outcome.rewards);assert.equal(response.body.transactionId,receipt.transactionId);}
    }
    assert.deepEqual((await db.ref('users/'+uid).get()).val(),committed);
    await db.ref('users/'+uid+'/gold').set(0);
    const replay=await api('openChest',user,{chestId:'rare'},id);
    assert.equal(replay.status,200,JSON.stringify(replay.body));assert.equal(replay.body.state.gold,0);
    assert.equal(replay.body.opened,false);assert.deepEqual(replay.body.rewards,receipt.outcome.rewards);
    const noFunds=await api('openChest',user,{chestId:'rare'},'no-funds-'+suffix);
    assert.equal(noFunds.status,409,JSON.stringify(noFunds.body));assert.equal(noFunds.body.error,'insufficient-balance');
  }finally{await killed.stop();}

  await db.ref('users/'+uid+'/gold').set(30000);
  const delayedId='shop-delayed-'+suffix,delayed=launch(user,delayedId,'before-purchase');
  try{
    await delayed.ready;await db.ref(requestPath(uid,delayedId)+'/startedAt').set(Date.now()-PASS_CHEST_RECOVERY_MS-1000);
    const winner=await launch(user,delayedId).result;
    assert.equal(winner.status,200,JSON.stringify(winner.body));assert.equal(winner.body.opened,true);
    const committed=(await db.ref('users/'+uid).get()).val();assert.equal(committed.stats.chestsOpened,2);
    delayed.resume();const old=await delayed.result;
    assert.equal(old.status,503,JSON.stringify(old.body));assert.equal(old.body.error,'request-state-changed');
    assert.deepEqual((await db.ref('users/'+uid).get()).val(),committed);
    assert.equal((await db.ref(requestPath(uid,delayedId)+'/status').get()).val(),'complete');
    await db.ref(requestPath(uid,delayedId)).remove();
    const replay=await api('openChest',user,{chestId:'rare'},delayedId);
    assert.equal(replay.status,200,JSON.stringify(replay.body));assert.equal(replay.body.opened,false);
    assert.deepEqual(replay.body.rewards,winner.body.rewards);
    assert.deepEqual((await db.ref('users/'+uid).get()).val(),committed);
  }finally{await delayed.stop();}
  console.log('SHOP_CHEST_RECOVERY_INTEGRATION_PASS '+JSON.stringify({killedAfterPurchase:1,independentRecoveryWorkers:5,heldBeforePurchase:1,leaseAgedInFixture:true,secondDebit:false,reroll:false,zeroBalanceReplay:true,freshBalances:true,databaseHost}));
}
if(process.argv[2]==='worker'){
  process.once('message',async request=>{
    const original=db.ref.bind(db),target=requestPath(request.user.localId,request.id);let calls=0,paused=false,message;
    db.ref=function(path){
      const ref=original(path),matches=request.mode==='after-purchase'?path===target:request.mode==='before-purchase'&&path==='users/'+request.user.localId;
      if(matches){const transaction=ref.transaction.bind(ref);ref.transaction=async function(...args){
        calls++;if(!paused&&calls===(request.mode==='after-purchase'?2:1)){
          paused=true;const resumed=new Promise(resolve=>process.once('message',resolve));process.send({ready:true});await resumed;
        }return transaction(...args);
      };}return ref;
    };
    try{message={result:await api('openChest',request.user,{chestId:'rare'},request.id)};}
    catch(error){message={error:error.stack||String(error)};}
    finally{db.ref=original;await Promise.all(getApps().map(deleteApp));}
    await new Promise(resolve=>process.send(message,resolve));process.disconnect();
  });
}else{
  main().catch(error=>{console.error(error);process.exitCode=1;}).finally(async()=>{await Promise.all(getApps().map(deleteApp));});
}
