'use strict';

const TRUSTED_ANDROID_APP_ID='1:955253747543:android:136188eaab561c9b29d812';
const EMULATOR_APP_ID='com.luno.chess';

function localEmulatorHost(value){
  if(typeof value!=='string')return false;
  const match=/^(?:127\.0\.0\.1|localhost):([0-9]{1,5})$/.exec(value);
  return !!match&&Number(match[1])>=1&&Number(match[1])<=65535;
}

function explicitEmulatorEnvironment(env){
  if(!env||typeof env!=='object')return false;
  if(env.NODE_ENV==='production'||env.K_SERVICE||env.K_REVISION)return false;
  return localEmulatorHost(env.FIREBASE_AUTH_EMULATOR_HOST)&&
    localEmulatorHost(env.FIREBASE_DATABASE_EMULATOR_HOST);
}

function appPolicyError(){
  const error=new Error('This app is not allowed to use the API.');
  error.status=403;
  error.code='app-check-app-not-allowed';
  return error;
}

// Apply only to the server result of verifyAppAttestation, never request data.
// This identity policy does not verify signatures or authenticate a user.
function assertTrustedAppId(appCheck,env=process.env){
  if(!appCheck||typeof appCheck!=='object'||Array.isArray(appCheck)||
     appCheck.degraded||appCheck.tokenType==='firebase-auth')throw appPolicyError();
  const hasAppId=Object.hasOwn(appCheck,'appId');
  const hasLegacyAppId=Object.hasOwn(appCheck,'app_id');
  const appId=hasAppId?appCheck.appId:appCheck.app_id;
  if((!hasAppId&&!hasLegacyAppId)||typeof appId!=='string'||
     hasLegacyAppId&&appCheck.app_id!==appId)throw appPolicyError();
  if(appCheck.tokenType==='emulator'){
    if(appId!==EMULATOR_APP_ID||!explicitEmulatorEnvironment(env))throw appPolicyError();
    return appCheck;
  }
  if(appId!==TRUSTED_ANDROID_APP_ID)throw appPolicyError();
  return appCheck;
}

module.exports={TRUSTED_ANDROID_APP_ID,assertTrustedAppId};
