'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {readFileSync}=require('node:fs');
const path=require('node:path');
const {TRUSTED_ANDROID_APP_ID,assertTrustedAppId}=require('../lib/app-check-policy');

const trusted='1:955253747543:android:136188eaab561c9b29d812';
const foreignWeb='1:955253747543:web:136188eaab561c9b29d812';
const siblingAndroid='1:955253747543:android:aaaaaaaaaaaaaaaaaaaaaa';
const emulatorResult={app_id:'com.luno.chess',tokenType:'emulator'};
const local={FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:9099',FIREBASE_DATABASE_EMULATOR_HOST:'localhost:9000'};

function rejected(value,env={}){
  assert.throws(()=>assertTrustedAppId(value,env),error=>{
    assert.equal(error.status,403);
    assert.equal(error.code,'app-check-app-not-allowed');
    assert.equal(error.message,'This app is not allowed to use the API.');
    assert.deepEqual(Object.keys(error).sort(),['code','status']);
    return true;
  });
}

test('V236 trusted App ID is the configured com.luno.chess Android Firebase app',()=>{
  const config=JSON.parse(readFileSync(path.join(__dirname,'../../luno_chess/android/app/google-services.json'),'utf8'));
  const clients=config.client.filter(client=>client.client_info.android_client_info.package_name==='com.luno.chess');
  assert.equal(clients.length,1);
  assert.equal(TRUSTED_ANDROID_APP_ID,trusted);
  assert.equal(clients[0].client_info.mobilesdk_app_id,trusted);
});

test('V236 policy accepts normalized current and legacy verified Android results unchanged',()=>{
  for(const result of [{appId:trusted,app_id:trusted,sub:trusted},{appId:trusted},{app_id:trusted}]){
    Object.freeze(result);
    assert.equal(assertTrustedAppId(result,{}),result);
    assert.equal(assertTrustedAppId(result,{NODE_ENV:'production',K_SERVICE:'lunoApi'}),result);
  }
});

for(const [name,appId] of [['same-project web',foreignWeb],['sibling Android',siblingAndroid],['foreign-project Android','1:123456789:android:136188eaab561c9b29d812']]){
  test(`V236 policy rejects a cryptographically verified ${name} identity`,()=>{
    rejected({appId,app_id:appId});
    rejected({app_id:appId});
    rejected({appId,sub:trusted,platform:'android'},local);
  });
}

test('V236 policy rejects absent, malformed and non-exact App IDs without coercion',()=>{
  for(const value of [undefined,null,false,7,trusted,[],{},Object.create({appId:trusted}),{sub:trusted},
    {token:{appId:trusted}}, {appId:undefined,app_id:trusted}, {appId:trusted,app_id:siblingAndroid}])rejected(value);
  for(const appId of [undefined,null,false,7,{},[],new String(trusted),'',' ',trusted+' ', ' '+trusted,
    trusted+'\n',trusted+'\u0000',trusted.toUpperCase(),'com.luno.chess','verified-app','*']){
    rejected({appId});
    rejected({app_id:appId});
  }
});

test('V236 policy never accepts Auth fallback, even with a trusted App ID or emulator environment',()=>{
  for(const result of [
    {appId:'firebase-auth-fallback',app_id:'firebase-auth-fallback',tokenType:'firebase-auth',degraded:true},
    {appId:trusted,tokenType:'firebase-auth'},
    {appId:trusted,degraded:true},
    {...emulatorResult,degraded:true},
  ]){
    rejected(result);
    rejected(result,local);
  }
});

test('V236 emulator result requires both explicit local Auth and Database emulator hosts',()=>{
  assert.equal(assertTrustedAppId(emulatorResult,local),emulatorResult);
  const alternate={...local,FIREBASE_AUTH_EMULATOR_HOST:'localhost:9099',FIREBASE_DATABASE_EMULATOR_HOST:'127.0.0.1:9000',FUNCTIONS_EMULATOR:'true'};
  assert.equal(assertTrustedAppId(emulatorResult,alternate),emulatorResult);
  for(const env of [{},{FUNCTIONS_EMULATOR:'true'},
    {FIREBASE_AUTH_EMULATOR_HOST:local.FIREBASE_AUTH_EMULATOR_HOST},
    {FIREBASE_DATABASE_EMULATOR_HOST:local.FIREBASE_DATABASE_EMULATOR_HOST},
  ])rejected(emulatorResult,env);
  for(const key of Object.keys(local)){
    for(const host of [undefined,null,true,42,'',' ','localhost','https://localhost:9000','localhost:0',
      '127.0.0.1:65536','localhost:9000/path','localhost:9000\n','0.0.0.0:9000','example.com:9000']){
      rejected(emulatorResult,{...local,[key]:host});
    }
  }
});

test('V236 production markers veto emulator results even when both emulator hosts are set',()=>{
  for(const marker of [{NODE_ENV:'production'},{K_SERVICE:'lunoApi'},{K_REVISION:'lunoApi-revision'}]){
    rejected(emulatorResult,{...local,...marker});
  }
});

test('V236 emulator identity must be the explicit verifier emulator result, not a raw ID or token',()=>{
  for(const result of [{app_id:'com.luno.chess'},{appId:'com.luno.chess'},'luno-emulator-app-check',
    {appId:trusted,tokenType:'emulator'}, {app_id:siblingAndroid,tokenType:'emulator'},
    {app_id:foreignWeb,tokenType:'emulator'}, {tokenType:'emulator'}])rejected(result,local);
});

test('V236 development and wildcard environment values cannot allow another app or an emulator result',()=>{
  for(const env of [{NODE_ENV:'test'},{NODE_ENV:'development'},{FUNCTIONS_EMULATOR:'true'},
    {LUNO_TRUSTED_APP_ID:'*',LUNO_APP_CHECK_ALLOWED_APP_IDS:'*'},
    {LUNO_TRUSTED_APP_ID:siblingAndroid,LUNO_APP_CHECK_ALLOWED_APP_IDS:siblingAndroid},
  ]){
    rejected({appId:siblingAndroid},env);
    rejected({appId:foreignWeb},env);
    rejected(emulatorResult,env);
    rejected({appId:siblingAndroid},{...local,...env});
  }
});

test('V236 default runtime environment applies the same strict policy',t=>{
  const keys=['FIREBASE_AUTH_EMULATOR_HOST','FIREBASE_DATABASE_EMULATOR_HOST','NODE_ENV','K_SERVICE','K_REVISION'];
  const previous=Object.fromEntries(keys.map(key=>[key,process.env[key]]));
  t.after(()=>{
    for(const key of keys){
      if(previous[key]===undefined)delete process.env[key];
      else process.env[key]=previous[key];
    }
  });
  for(const key of keys)delete process.env[key];
  assert.equal(assertTrustedAppId({appId:trusted}).appId,trusted);
  assert.throws(()=>assertTrustedAppId(emulatorResult),{code:'app-check-app-not-allowed'});
  Object.assign(process.env,local);
  assert.equal(assertTrustedAppId(emulatorResult),emulatorResult);
  process.env.NODE_ENV='production';
  assert.throws(()=>assertTrustedAppId(emulatorResult),{code:'app-check-app-not-allowed'});
});
