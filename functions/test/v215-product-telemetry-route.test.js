'use strict';

const test=require('node:test'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const {getDatabase}=require('firebase-admin/database');
const logger=require('firebase-functions/logger');
const {handler,starterProfile}=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');
const uid='telemetry_route_player';
const routes=['getProductTelemetryConsent','setProductTelemetryConsent','submitProductTelemetry'];

function setup(t){
  const profile=starterProfile(uid,'telemetry_player');
  const db=memoryDatabase(t,{users:{[uid]:profile}});
  const reference=getDatabase().ref.bind(getDatabase());
  function ref(path=''){
    return {...reference(path),child:key=>ref([path,key].filter(Boolean).join('/'))};
  }
  t.mock.method(getDatabase(),'ref',ref);
  t.mock.method(getAuth(),'verifyIdToken',async()=>({uid}));
  t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
  for(const level of ['info','warn','error'])t.mock.method(logger,level,()=>{});
  return db;
}
async function request(route,body={},options={}){
  const headers={origin:'https://localhost','x-luno-request-id':'telemetry-route-request'};
  if(options.auth!==false)headers.authorization='Bearer fake-token';
  if(options.appCheck!==false)headers['x-firebase-appcheck']='verified-check';
  let status,result;
  await handler({method:'POST',path:'/'+route,body,get:name=>headers[name.toLowerCase()]||''},
    {set(){return this;},status(value){status=value;return this;},json(value){result=value;}});
  return {status,body:result};
}
const delivery=()=>({version:1,kind:'analytics',consentRevision:1,deliveryId:'a'.repeat(32),
  samples:[{event:'card_played',elapsedMs:12000,mode:'ai'}]});

for(const route of routes){
  test(`${route} is registered and requires Auth before a database operation`,async t=>{
    const db=setup(t),result=await request(route,{}, {auth:false});
    assert.equal(result.status,401);assert.equal(result.body.error,'auth-required');
    assert.equal(db.writes.length,0);
  });
  test(`${route} requires production App Check, not Auth fallback`,async t=>{
    const db=setup(t),result=await request(route,{}, {appCheck:false});
    assert.equal(result.status,401);assert.equal(result.body.error,'app-check-required');
    assert.equal(db.writes.length,0);
  });
}
test('invalid App Check cannot reach consent mutation',async t=>{
  const db=setup(t);
  t.mock.method(getAppCheck(),'verifyToken',async()=>{throw new Error('private token');});
  const result=await request('setProductTelemetryConsent',{version:1,expectedRevision:0,analytics:true,diagnostics:true});
  assert.equal(result.status,401);assert.equal(result.body.error,'invalid-app-check');
  assert.equal(db.writes.length,0);assert.ok(!JSON.stringify(result.body).includes('private token'));
});
test('real handler confirms opt-in and idempotent aggregate delivery without public publication',async t=>{
  const db=setup(t),initial=structuredClone(db.read('users/'+uid));
  const before=await request('getProductTelemetryConsent');
  assert.equal(before.status,200);
  assert.deepEqual(before.body.consent,{version:1,revision:0,analytics:false,diagnostics:false});
  const denied=await request('submitProductTelemetry',delivery());
  assert.equal(denied.status,403);assert.equal(denied.body.error,'telemetry-consent-required');
  const choice=await request('setProductTelemetryConsent',{version:1,expectedRevision:0,analytics:true,diagnostics:false});
  assert.equal(choice.status,200,JSON.stringify(choice.body));assert.equal(choice.body.consent.revision,1);
  const first=await request('submitProductTelemetry',delivery()),again=await request('submitProductTelemetry',delivery());
  assert.equal(first.status,200,JSON.stringify(first.body));assert.equal(first.body.idempotent,false);
  assert.equal(again.status,200);assert.equal(again.body.idempotent,true);
  const saved=db.read('users/'+uid);delete saved.productTelemetryConsent;
  assert.equal(saved.stateRevision,1);
  delete saved.stateRevision;
  assert.deepEqual(saved,initial);assert.equal(db.read('publicProfiles'),null);
  const records=JSON.stringify(db.read('productTelemetryDaily'));
  for(const value of [uid,'telemetry_player','samples','cardId','token'])assert.ok(!records.includes(value));
});
test('deleted account cannot read, consent or submit optional metrics',async t=>{
  const db=setup(t),key=crypto.createHash('sha256').update(uid).digest('hex');
  db.write('deletedAccounts/'+key,{deletedAt:1});
  for(const route of routes){
    const result=await request(route);
    assert.equal(result.status,403);assert.equal(result.body.error,'account-deleted');
  }
  assert.equal(db.writes.length,0);
});
