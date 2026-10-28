'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const logger=require('firebase-functions/logger');
const {handler}=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');
const uid='route_boundary_player';
const trustedApp='1:955253747543:android:136188eaab561c9b29d812';
async function request(t,path,{authenticated=false,method='POST',appId=trustedApp,verifiedResult,
  appCheckToken='fake-app-check',verificationError}={}){
  const calls={auth:0,appCheck:0,database:0};
  const database=memoryDatabase(t,{}, {afterRead(){calls.database++;}});
  t.mock.method(getAuth(),'verifyIdToken',async()=>{calls.auth++;return {uid,privateClaim:'must-not-be-a-route-response'};});
  t.mock.method(getAppCheck(),'verifyToken',async()=>{
    calls.appCheck++;
    if(verificationError)throw verificationError;
    return verifiedResult===undefined?{appId}:verifiedResult;
  });
  for(const level of ['info','warn','error'])t.mock.method(logger,level,()=>{});
  const headers={origin:'https://localhost','x-luno-request-id':'route-boundary-request'};
  if(appCheckToken!==null)headers['x-firebase-appcheck']=appCheckToken;
  if(authenticated)headers.authorization='Bearer fake-token';
  let status,body;
  await handler({method,path,body:{},get:name=>headers[name.toLowerCase()]||''},{set(){return this;},status(value){status=value;return this;},json(value){body=value;}});
  return {status,body,calls,database};
}

function emulatorEnvironment(t,values){
  const keys=['FIREBASE_AUTH_EMULATOR_HOST','FIREBASE_DATABASE_EMULATOR_HOST','NODE_ENV','K_SERVICE','K_REVISION'];
  const previous=Object.fromEntries(keys.map(key=>[key,process.env[key]]));
  t.after(()=>{for(const key of keys){
    if(previous[key]===undefined)delete process.env[key];else process.env[key]=previous[key];
  }});
  for(const key of keys)delete process.env[key];
  Object.assign(process.env,values);
}
for(const name of Object.getOwnPropertyNames(Object.prototype)){
  for(const authenticated of [false,true])test(`inherited API name ${name} is rejected before auth (${authenticated?'signed in':'guest request'})`,async t=>{
    const result=await request(t,'/'+name+'/',{authenticated});
    assert.equal(result.status,404);assert.equal(result.body.error,'route-not-found');assert.equal(result.body.ok,false);
    assert.deepEqual(result.calls,{auth:0,appCheck:0,database:0});assert.equal(result.database.writes.length,0);
    assert.equal(JSON.stringify(result.body).includes(uid),false);assert.equal(JSON.stringify(result.body).includes('must-not-be-a-route-response'),false);
  });
}

for(const path of ['/createGuestPlayer','/claimDailyReward']){
  test(`untrusted signed app cannot reach writes for ${path}`,async t=>{
    const result=await request(t,path,{authenticated:true,appId:'1:955253747543:web:136188eaab561c9b29d812'});
    assert.equal(result.status,403);assert.equal(result.body.error,'app-check-app-not-allowed');
    assert.deepEqual(result.calls,{auth:1,appCheck:1,database:0});
    assert.equal(result.database.writes.length,0);
  });
}

for(const [name,verifiedResult] of [
  ['current',{appId:trustedApp,token:{sub:trustedApp}}],
  ['legacy',{app_id:trustedApp}],
])test(`trusted ${name} verified app still reaches player lookup`,async t=>{
  const result=await request(t,'/getPlayerState',{authenticated:true,verifiedResult});
  assert.equal(result.status,404);assert.equal(result.body.error,'profile-not-found');
  assert.equal(result.calls.auth,1);assert.equal(result.calls.appCheck,1);assert.ok(result.calls.database>0);
});

for(const [name,verifiedResult] of [
  ['padded',{appId:' '+trustedApp+' '}],
  ['boxed',{appId:new String(trustedApp)}],
  ['array',{appId:[trustedApp]}],
  ['conflicting subject',{appId:trustedApp,token:{sub:'1:955253747543:android:aaaaaaaaaaaaaaaaaaaaaa'}}],
  ['conflicting legacy ID',{appId:trustedApp,token:{app_id:'1:955253747543:web:136188eaab561c9b29d812',sub:trustedApp}}],
])test(`${name} verifier identity is rejected before player data`,async t=>{
  const result=await request(t,'/getPlayerState',{authenticated:true,verifiedResult});
  assert.equal(result.status,401);assert.equal(result.body.error,'invalid-app-check');
  assert.deepEqual(result.calls,{auth:1,appCheck:1,database:0});assert.equal(result.database.writes.length,0);
});

test('a signed identity cannot impersonate the unavailable Auth fallback',async t=>{
  const result=await request(t,'/getPlayerState',{authenticated:true,
    verifiedResult:{appId:trustedApp,token:{sub:trustedApp,tokenType:'firebase-auth',degraded:true}}});
  assert.equal(result.status,403);assert.equal(result.body.error,'app-check-app-not-allowed');
  assert.deepEqual(result.calls,{auth:1,appCheck:1,database:0});assert.equal(result.database.writes.length,0);
});

test('signature verification failure stays a 401 before the identity policy and player data',async t=>{
  const result=await request(t,'/getPlayerState',{authenticated:true,verificationError:new Error('bad-signature')});
  assert.equal(result.status,401);assert.equal(result.body.error,'invalid-app-check');
  assert.deepEqual(result.calls,{auth:1,appCheck:1,database:0});assert.equal(result.database.writes.length,0);
});

for(const route of ['/createGuestPlayer','/prepareGoogleLink','/completeGoogleLink','/getPlayerState']){
  test(`current production route ${route} never falls back without attestation`,async t=>{
    const result=await request(t,route,{authenticated:true,appCheckToken:null});
    assert.equal(result.status,401);assert.equal(result.body.error,'app-check-required');
    assert.deepEqual(result.calls,{auth:1,appCheck:0,database:0});assert.equal(result.database.writes.length,0);
  });
}

test('the explicit local Auth and Database emulator request can reach player lookup',async t=>{
  emulatorEnvironment(t,{FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:9099',FIREBASE_DATABASE_EMULATOR_HOST:'localhost:9000'});
  const result=await request(t,'/getPlayerState',{authenticated:true,appCheckToken:'luno-emulator-app-check'});
  assert.equal(result.status,404);assert.equal(result.body.error,'profile-not-found');
  assert.equal(result.calls.auth,1);assert.equal(result.calls.appCheck,0);assert.ok(result.calls.database>0);
});

for(const markers of [
  {FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:9099'},
  {FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:9099',FIREBASE_DATABASE_EMULATOR_HOST:'remote.invalid:9000'},
  {FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:9099',FIREBASE_DATABASE_EMULATOR_HOST:'localhost:9000',K_SERVICE:'lunoApi'},
])test(`incomplete or production emulator markers cannot bypass App ID policy ${JSON.stringify(markers)}`,async t=>{
  emulatorEnvironment(t,markers);
  const result=await request(t,'/getPlayerState',{authenticated:true,appCheckToken:'luno-emulator-app-check'});
  assert.equal(result.status,403);assert.equal(result.body.error,'app-check-app-not-allowed');
  assert.deepEqual(result.calls,{auth:1,appCheck:0,database:0});assert.equal(result.database.writes.length,0);
});
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
