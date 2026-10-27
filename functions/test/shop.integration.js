'use strict';

const {authHost,databaseHost}=require('./helpers/local-emulators').requireLocalEmulators();
const assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getDatabase}=require('firebase-admin/database');

const namespace='luno-chess-default-rtdb';
const adminApp=initializeApp({projectId:'luno-chess',databaseURL:`http://${databaseHost}?ns=${namespace}`},'shop-integration-test');
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

async function main(){
  const user=await anonymousUser();
  const created=await api('/createGuestPlayer',user.idToken,{username:'shop'+String(Date.now()).slice(-8)},'shop-create');
  assert.equal(created.status,200,JSON.stringify(created.body));
  const path='users/'+user.localId;
  await db.ref(path).update({gold:100000,gems:1000});

  const common=await api('/openChest',user.idToken,{chestId:'common'},'shop-common-1');
  assert.equal(common.status,200,JSON.stringify(common.body));
  assert.equal(common.body.opened,true);
  assert.equal(common.body.chestId,'common');
  assert.ok(Array.isArray(common.body.rewards));
  const commonGold=common.body.state.gold;
  const commonReplay=await api('/openChest',user.idToken,{chestId:'common'},'shop-common-1');
  assert.equal(commonReplay.status,200,JSON.stringify(commonReplay.body));
  assert.equal(commonReplay.body.idempotent,true);
  assert.equal(commonReplay.body.state.gold,commonGold);

  for(const [chestId,requestId] of [['rare','shop-rare-1'],['legendary','shop-legendary-1'],['royal','shop-royal-1']]){
    const result=await api('/openChest',user.idToken,{chestId},requestId);
    assert.equal(result.status,200,JSON.stringify(result.body));
    assert.equal(result.body.opened,true);
    assert.equal(result.body.chestId,chestId);
    assert.ok(Array.isArray(result.body.rewards));
  }

  const beforeGems=(await db.ref(path+'/gems').get()).val();
  const set=await api('/purchaseSoftItem',user.idToken,{itemId:'piece_set:roma'},'shop-set-roma-1');
  assert.equal(set.status,200,JSON.stringify(set.body));
  assert.equal(set.body.purchased,true);
  assert.equal(set.body.state.inventory.ownedSets.includes('roma'),true);
  assert.equal(set.body.state.inventory.activePieceSet,'roma');
  assert.equal(set.body.state.gems,beforeGems-480);

  const setReplay=await api('/purchaseSoftItem',user.idToken,{itemId:'piece_set:roma'},'shop-set-roma-1');
  assert.equal(setReplay.status,200,JSON.stringify(setReplay.body));
  assert.equal(setReplay.body.idempotent,true);
  assert.equal(setReplay.body.state.gems,beforeGems-480);

  const duplicate=await api('/purchaseSoftItem',user.idToken,{itemId:'piece_set:roma'},'shop-set-roma-2');
  assert.equal(duplicate.status,200,JSON.stringify(duplicate.body));
  assert.equal(duplicate.body.idempotent,true);
  assert.equal(duplicate.body.state.gems,beforeGems-480);

  console.log('SHOP_INTEGRATION_PASS');
}

main().then(async function(){await deleteApp(adminApp);process.exit(0);}).catch(async function(error){console.error(error);await deleteApp(adminApp).catch(function(){});process.exitCode=1;});
