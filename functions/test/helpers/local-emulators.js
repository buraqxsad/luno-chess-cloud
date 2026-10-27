'use strict';

function localHost(env,name){
  const value=env[name];
  if(typeof value!=='string'||!/^(127\.0\.0\.1|localhost):\d+$/.test(value)){
    throw new Error(name+' must explicitly target a local emulator; refusing integration tests.');
  }
  const port=Number(value.slice(value.lastIndexOf(':')+1));
  if(port<1||port>65535)throw new Error('Invalid local emulator port: '+name);
  return value;
}

function requireLocalEmulators(env=process.env){
  const authHost=localHost(env,'FIREBASE_AUTH_EMULATOR_HOST');
  const databaseHost=localHost(env,'FIREBASE_DATABASE_EMULATOR_HOST');
  const functionsBase=env.LUNO_FUNCTIONS_BASE_URL||'';
  if(functionsBase){
    let url;
    try{url=new URL(functionsBase);}catch(_){throw new Error('Invalid local Functions emulator URL.');}
    if(url.protocol!=='http:'||!['localhost','127.0.0.1'].includes(url.hostname)||
       !url.port||Number(url.port)<1||url.username||url.password||url.search||url.hash){
      throw new Error('LUNO_FUNCTIONS_BASE_URL must target a local Functions emulator.');
    }
  }
  return {authHost,databaseHost,functionsBase};
}

module.exports={requireLocalEmulators};
