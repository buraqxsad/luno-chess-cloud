'use strict';

const {authHost,databaseHost}=require('./helpers/local-emulators').requireLocalEmulators();
const assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getDatabase}=require('firebase-admin/database');

const namespace='luno-chess-default-rtdb';
const adminApp=initializeApp({projectId:'luno-chess',databaseURL:`http://${databaseHost}?ns=${namespace}`},'pass-integration-test');
const db=getDatabase(adminApp);
const handler=require('../index.js')._test.handler;

async function json(response){
  const body=await response.json().catch(function(){return {};});
  return {status:response.status,body};
}
async function anonymousUser(){
  const response=await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-key`,{
    method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({returnSecureToken:true}),signal:AbortSignal.timeout(15000)
  });
  const result=await json(response);assert.equal(result.status,200,JSON.stringify(result.body));return result.body;
}
async function api(path,token,body,id){
  const headers={authorization:'Bearer '+token,'content-type':'application/json','x-firebase-appcheck':'luno-emulator-app-check','x-luno-request-id':id,origin:'https://localhost'};
  const req={method:'POST',path,body:body||{},get:function(name){return headers[String(name||'').toLowerCase()]||'';}};
  let status=200,responseBody={};
  const res={set:function(){return this;},status:function(value){status=value;return this;},send:function(value){responseBody=value;return this;},json:function(value){responseBody=value;return this;}};
  let timer;
  try{
    await Promise.race([handler(req,res),new Promise(function(_,reject){timer=setTimeout(function(){reject(new Error('API timeout: '+path));},45000);})]);
  }finally{if(timer)clearTimeout(timer);}
  return {status,body:responseBody};
}
function count(items,id){return (items||[]).filter(function(value){return value===id;}).length;}

async function main(){
  const user=await anonymousUser();
  const testUsername='ptest'+String(Date.now()).slice(-8);
  const created=await api('/createGuestPlayer',user.idToken,{username:testUsername},'pass-create');
  assert.equal(created.status,200,JSON.stringify(created.body));
  const state=await api('/getPlayerState',user.idToken,{},'pass-state');
  assert.equal(state.status,200,JSON.stringify(state.body));
  const seasonId=state.body.state.economy.periods.seasonId;
  const seasonNumber=Number(seasonId.slice(1));
  const passPath='users/'+user.localId+'/passState';

  await db.ref(passPath).set({seasonKey:'ranked-'+seasonId+'-v2',season:seasonNumber,seasonStartedAt:Date.now(),level:1,xp:0,premium:false,claimed:{free:{},premium:{}},unlocks:[]});
  const before=(await db.ref('users/'+user.localId).get()).val();
  const first=await api('/claimPassReward',user.idToken,{level:1,track:'free'},'pass-claim-free-1');
  assert.equal(first.status,200,JSON.stringify(first.body));
  assert.equal(first.body.granted,true);
  assert.equal((await db.ref('users/'+user.localId+'/gold').get()).val(),before.gold+120);
  assert.equal((await db.ref(passPath+'/claimed/free/1').get()).exists(),true);
  const replay=await api('/claimPassReward',user.idToken,{level:1,track:'free'},'pass-claim-free-replay');
  assert.equal(replay.status,200,JSON.stringify(replay.body));
  assert.equal(replay.body.granted,false);
  assert.equal(replay.body.idempotent,true);
  assert.equal((await db.ref('users/'+user.localId+'/gold').get()).val(),before.gold+120);

  await db.ref(passPath).update({level:8,premium:true,claimed:{free:{},premium:{}},unlocks:[]});
  await db.ref('users/'+user.localId+'/inventory/pendingChests').set([]);
  const freeRare=await api('/claimPassReward',user.idToken,{level:8,track:'free'},'pass-free-rare');
  const premiumRare=await api('/claimPassReward',user.idToken,{level:5,track:'premium'},'pass-premium-rare');
  assert.equal(freeRare.status,200,JSON.stringify(freeRare.body));
  assert.equal(premiumRare.status,200,JSON.stringify(premiumRare.body));
  let profile=(await db.ref('users/'+user.localId).get()).val();
  assert.equal(count(profile.inventory.pendingChests,'rare'),2);
  const openedA=await api('/openPassChest',user.idToken,{chestId:'rare'},'pass-open-rare-a');
  const openedB=await api('/openPassChest',user.idToken,{chestId:'rare'},'pass-open-rare-b');
  assert.equal(openedA.status,200,JSON.stringify(openedA.body));
  assert.equal(openedB.status,200,JSON.stringify(openedB.body));
  profile=(await db.ref('users/'+user.localId).get()).val();
  assert.equal((profile.inventory.pendingChests||[]).length,0);
  const noChest=await api('/openPassChest',user.idToken,{chestId:'rare'},'pass-open-rare-c');
  assert.equal(noChest.status,409,JSON.stringify(noChest.body));

  await db.ref(passPath).update({level:4,premium:true,claimed:{free:{},premium:{}},unlocks:[]});
  await db.ref('users/'+user.localId+'/inventory/ownedEmojis').set(['smile','laugh']);
  const beforeDuplicate=(await db.ref('users/'+user.localId+'/gold').get()).val();
  const duplicate=await api('/claimPassReward',user.idToken,{level:4,track:'free'},'pass-duplicate-emoji');
  assert.equal(duplicate.status,200,JSON.stringify(duplicate.body));
  assert.equal((await db.ref('users/'+user.localId+'/gold').get()).val(),beforeDuplicate+180+250);
  assert.equal(duplicate.body.content.duplicate,true);
  assert.deepEqual(duplicate.body.content.compensation,{gold:250});

  await db.ref(passPath).update({level:20,premium:false,claimed:{free:{},premium:{}},unlocks:[]});
  await db.ref('users/'+user.localId+'/inventory/ownedSets').set(['std']);
  const setReward=await api('/claimPassReward',user.idToken,{level:20,track:'free'},'pass-piece-set');
  assert.equal(setReward.status,200,JSON.stringify(setReward.body));
  assert.equal(setReward.body.content.kind,'piece_set');
  assert.equal(setReward.body.content.id,'ottoman');
  assert.equal(setReward.body.state.inventory.ownedSets.includes('ottoman'),true);

  console.log('PASS_INTEGRATION_PASS');
}

main().then(async function(){await deleteApp(adminApp);process.exit(0);}).catch(async function(error){console.error(error);await deleteApp(adminApp).catch(function(){});process.exitCode=1;});
