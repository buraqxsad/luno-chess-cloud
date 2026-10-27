'use strict';

const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');

const root=path.resolve(__dirname,'../..');
const qa=path.join(root,'luno_chess/qa/v220/backend');
const projectId='demo-luno-v220';
const namespace='demo-luno-v220-default-rtdb';
const databaseHost='127.0.0.1:19000';
const bytes=value=>Buffer.byteLength(JSON.stringify(value??null),'utf8');
const hash=value=>crypto.createHash('sha256').update(value).digest('hex');

function guardEmulator(env=process.env){
  if(env.V220_DB_INTEGRATION!=='1'||env.GCLOUD_PROJECT!==projectId||
     env.FIREBASE_DATABASE_EMULATOR_HOST!==databaseHost||env.LUNO_DB_EMULATOR_NAMESPACE!==namespace||
     env.FIREBASE_AUTH_EMULATOR_HOST||env.GOOGLE_APPLICATION_CREDENTIALS){
    throw new Error('V220 refuses anything except its explicit credential-free demo DB emulator.');
  }
  return {projectId,namespace,databaseHost};
}

function runtimeStamp(){
  const lock=JSON.parse(fs.readFileSync(path.join(root,'luno_chess/qa/v219/source-lock-final.json'),'utf8'));
  const files={};
  for(const [relative,expected] of Object.entries(lock.files)){
    if(!relative.startsWith('../functions/')&&!['../database.rules.production.json','../firebase.json'].includes(relative))continue;
    const absolute=path.resolve(root,'luno_chess',relative);
    const current=hash(fs.readFileSync(absolute));
    files[relative]={sha256:current,v219:expected,unchanged:current===expected};
  }
  const sidecarFiles={};
  for(const folder of ['functions/test','functions/tools']){
    for(const name of fs.readdirSync(path.join(root,folder))){
      if(!/^v220.*\.(test\.js|cjs)$/.test(name))continue;
      const relative=folder+'/'+name;sidecarFiles[relative]=hash(fs.readFileSync(path.join(root,relative)));
    }
  }
  return {recordedAt:new Date().toISOString(),files,sidecarFiles,changed:Object.keys(files).filter(key=>!files[key].unchanged)};
}

function syntheticConversation(api,sender,recipient,count,textLength=240){
  const value={members:{[sender]:true,[recipient]:true},updatedAt:1,msgs:{},sendRequests:{[api.hash(sender)]:{}}};
  for(let index=0;index<count;index++){
    const messageId='-v220_'+String(index).padStart(13,'0');
    const text=('synthetic-'+index+' ').padEnd(textLength,'x');
    const requestIdHash=api.hash('synthetic-request-'+index),createdAt=1700000000000+index;
    value.msgs[messageId]={from:sender,text,ts:createdAt};
    value.sendRequests[api.hash(sender)][requestIdHash]={version:1,requestIdHash,uidHash:api.hash(sender),
      targetUidHash:api.hash(recipient),textHash:api.hash(text),messageId,createdAt};
  }
  return value;
}

function profiles(api,uids){
  return Object.fromEntries(uids.map((uid,index)=>{
    const value=api.starterProfile(uid,'v220_user_'+index);
    value.legalConsent={uid,acceptedAt:1,termsVersion:api.LEGAL_TERMS_VERSION,
      privacyVersion:api.LEGAL_PRIVACY_VERSION,communityVersion:api.LEGAL_COMMUNITY_VERSION};
    return [uid,value];
  }));
}

async function request(api,uid,route,body={},id='v220-request'){
  const headers={authorization:'Bearer '+uid,'x-firebase-appcheck':'v220-mocked-attestation','x-luno-request-id':id};
  let status,result;
  await api.handler({method:'POST',path:'/'+route,body,get:name=>headers[name.toLowerCase()]||''},
    {set(){return this;},status(value){status=value;return this;},json(value){result=value;}});
  return {status,body:result};
}

function recordReferences(t,db,options={}){
  const original=db.ref.bind(db),records=[];
  function wrap(ref,location,query=null){
    return new Proxy(ref,{get(target,key){
      if(key==='get')return async()=>{
        const snapshot=await target.get();
        records.push({kind:'get',path:location,query,strategy:'runtime get',
          bytes:bytes(snapshot.val()),children:snapshot.numChildren()});
        if(options.afterGet)await options.afterGet(location,snapshot,query);
        return snapshot;
      };
      if(key==='once')return async(event,...args)=>{
        const snapshot=await target.once(event,...args);
        records.push({kind:'once',path:location,query,strategy:'runtime once',bytes:bytes(snapshot.val()),children:snapshot.numChildren()});
        return snapshot;
      };
      if(key==='transaction')return async(update,onComplete,applyLocally)=>{
        if(options.beforeTransaction)await options.beforeTransaction(location);
        const record={kind:'transaction',path:location,applyLocally,callbacks:0,inputBytes:0,outputBytes:0,maxInputBytes:0};
        records.push(record);
        const result=await target.transaction(value=>{
          record.callbacks++;record.inputBytes+=bytes(value);record.maxInputBytes=Math.max(record.maxInputBytes,bytes(value));
          const next=update(value);if(next!==undefined)record.outputBytes+=bytes(next);return next;
        },onComplete,applyLocally);
        record.committed=result.committed;
        return result;
      };
      if(['orderByChild','orderByKey','orderByValue','equalTo','limitToFirst','limitToLast','startAfter'].includes(key)){
        return (...args)=>wrap(target[key](...args),location,{...(query||{}),[key]:args[0]??true});
      }
      if(key==='update')return async values=>{
        records.push({kind:'update',path:location,keys:Object.keys(values),bytes:bytes(values)});
        const result=await target.update(values);
        if(options.afterUpdate)await options.afterUpdate(location,values);
        return result;
      };
      const value=Reflect.get(target,key,target);
      return typeof value==='function'?value.bind(target):value;
    }});
  }
  t.mock.method(db,'ref',(location='')=>wrap(location===''?original():original(location),location));
  return records;
}

function saveJson(name,value){
  fs.mkdirSync(qa,{recursive:true});
  if(fs.existsSync(path.join(qa,name))){
    const history=path.join(qa,'history');fs.mkdirSync(history,{recursive:true});
    fs.copyFileSync(path.join(qa,name),path.join(history,path.parse(name).name+'-'+Date.now()+path.extname(name)));
  }
  fs.writeFileSync(path.join(qa,name),JSON.stringify(value,null,2)+'\n');
}

module.exports={root,qa,projectId,namespace,databaseHost,bytes,hash,guardEmulator,runtimeStamp,
  syntheticConversation,profiles,request,recordReferences,saveJson};
