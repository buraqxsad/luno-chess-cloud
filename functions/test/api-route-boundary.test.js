'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const logger=require('firebase-functions/logger');
const {handler}=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');
const uid='route_boundary_player';
async function request(t,path,{authenticated=false,method='POST',appId='1:955253747543:android:136188eaab561c9b29d812'}={}){
  const calls={auth:0,appCheck:0,database:0};
  const database=memoryDatabase(t,{}, {afterRead(){calls.database++;}});
  t.mock.method(getAuth(),'verifyIdToken',async()=>{calls.auth++;return {uid,privateClaim:'must-not-be-a-route-response'};});
  t.mock.method(getAppCheck(),'verifyToken',async()=>{calls.appCheck++;return {appId};});
  for(const level of ['info','warn','error'])t.mock.method(logger,level,()=>{});
  const headers={origin:'https://localhost','x-luno-request-id':'route-boundary-request','x-firebase-appcheck':'fake-app-check'};
  if(authenticated)headers.authorization='Bearer fake-token';
  let status,body;
  await handler({method,path,body:{},get:name=>headers[name.toLowerCase()]||''},{set(){return this;},status(value){status=value;return this;},json(value){body=value;}});
  return {status,body,calls,database};
}
for(const name of Object.getOwnPropertyNames(Object.prototype)){
  for(const authenticated of [false,true])test(`inherited API name ${name} is rejected before auth (${authenticated?'signed in':'guest request'})`,async t=>{
    const result=await request(t,'/'+name+'/',{authenticated});
    assert.equal(result.status,404);assert.equal(result.body.error,'route-not-found');assert.equal(result.body.ok,false);
    assert.deepEqual(result.calls,{auth:0,appCheck:0,database:0});assert.equal(result.database.writes.length,0);
    assert.equal(JSON.stringify(result.body).includes(uid),false);assert.equal(JSON.stringify(result.body).includes('must-not-be-a-route-response'),false);
  });
}
for(const path of ['/','/not-a-luno-operation/','/%5F%5Fproto%5F%5F'])test(`unknown API path ${path} is rejected before auth`,async t=>{
  const result=await request(t,path,{authenticated:true});assert.equal(result.status,404);assert.equal(result.body.error,'route-not-found');assert.deepEqual(result.calls,{auth:0,appCheck:0,database:0});
});
for(const name of ['createGuestPlayer','getPlayerState','verifyPurchase','submitMatchAction'])test(`registered API ${name} still enters authentication`,async t=>{
  const result=await request(t,'/'+name+'/');assert.equal(result.status,401);assert.equal(result.body.error,'auth-required');assert.equal(result.calls.database,0);
});
test('HTTP method gate still rejects GET before routing or authentication',async t=>{
  const result=await request(t,'/constructor',{authenticated:true,method:'GET'});assert.equal(result.status,405);assert.equal(result.body.error,'method-not-allowed');assert.deepEqual(result.calls,{auth:0,appCheck:0,database:0});
});

for(const appId of ['1:955253747543:web:136188eaab561c9b29d812','1:955253747543:android:aaaaaaaaaaaaaaaaaaaaaa','1:123456789:android:136188eaab561c9b29d812']){
  test(`verified but untrusted app cannot read or mutate a player (${appId})`,async t=>{
    const result=await request(t,'/getPlayerState',{authenticated:true,appId});
    assert.equal(result.status,403);
    assert.equal(result.body.error,'app-check-app-not-allowed');
    assert.deepEqual(result.calls,{auth:1,appCheck:1,database:0});
    assert.equal(result.database.writes.length,0);
    assert.equal(JSON.stringify(result.body).includes(appId),false);
  });
}
