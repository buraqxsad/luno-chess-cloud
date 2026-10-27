'use strict';

const {authHost,databaseHost}=require('./helpers/local-emulators').requireLocalEmulators();
const assert=require('node:assert/strict');
const {fork}=require('node:child_process');
const {getApps,deleteApp}=require('firebase-admin/app');
const {getDatabase}=require('firebase-admin/database');
const {handler,writeAccountAudit,writeAccountLinkTicket,rateLimit}=require('../index')._test;
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
  assert.equal(status,200,route+': '+JSON.stringify(result));return result;
}
async function deniedClient(user,root,key,method='GET'){
  const response=await fetch(`http://${databaseHost}/${root}/${key}.json?ns=luno-chess-default-rtdb&auth=${encodeURIComponent(user.idToken)}`,{
    method,headers:method==='GET'?{}:{'content-type':'application/json'},...(method==='GET'?{}:{body:JSON.stringify({uid:user.localId})}),signal:AbortSignal.timeout(15000)
  });
  assert.ok([401,403].includes(response.status),root+' client '+method+' unexpectedly permitted: '+await response.text());
}
function heldWorker(mode,user,suffix,onReady){
  return new Promise((resolve,reject)=>{
    const child=fork(__filename,['worker'],{stdio:['ignore','pipe','pipe','ipc'],windowsHide:true});
    let message,output='',settled=false;
    const timer=setTimeout(()=>{child.kill();finish(new Error('Metadata worker timeout: '+mode));},55000);
    function finish(error){if(settled)return;settled=true;clearTimeout(timer);if(error)reject(error);else resolve(message.result);}
    for(const stream of [child.stdout,child.stderr])stream.on('data',chunk=>{output=(output+chunk).slice(-4000);});
    child.on('message',value=>{
      if(value.ready)Promise.resolve().then(onReady).then(()=>child.send({resume:true})).catch(error=>{child.kill();finish(error);});
      else message=value;
    });
    child.once('error',finish);
    child.once('exit',code=>{
      if(code!==0||!message||message.error)finish(new Error(message&&message.error||'Metadata worker failed: '+code+' '+output));else finish();
    });
    child.send({mode,uid:user.localId,suffix});
  });
}
async function main(){
  const suffix=Date.now().toString(36),foreign=await anonymousUser();
  await api('createGuestPlayer',foreign,{username:'foreign_'+suffix},'foreign-'+suffix);
  await db.ref('accountLinkTickets/foreign_'+suffix).set({uid:foreign.localId,status:'open'});
  for(const [index,mode] of ['audit','ticket','rate'].entries()){
    const user=await anonymousUser(),uid=user.localId;
    await api('createGuestPlayer',user,{username:'meta'+index+'_'+suffix},'create-'+index+'-'+suffix);
    if(index===0){
      const conflict=await api('recordGoogleLinkConflict',user,{},'conflict-'+suffix);
      assert.equal((await db.ref('accountLinkTickets/'+conflict.ticketId).get()).val().uid,uid);
      for(const root of ['auditLogs','serverRateLimits']){
        await deniedClient(user,root,uid);await deniedClient(user,root,uid,'PUT');
      }
      await deniedClient(user,'accountLinkTickets',conflict.ticketId);await deniedClient(user,'accountLinkTickets',conflict.ticketId,'PUT');
    }
    await db.ref(`auditLogs/${uid}/legacy`).set({type:'username-changed',oldUsername:'legacy',newUsername:'meta'+index+'_'+suffix});
    await db.ref('accountLinkTickets/legacy_'+uid).set({uid,status:'open'});
    const late=await heldWorker(mode,user,suffix,async()=>{
      await api('deleteAccount',user,{confirm:true},'delete-'+index+'-'+suffix);
      assert.equal((await db.ref('auditLogs/'+uid).get()).exists(),false);
      assert.equal((await db.ref('accountLinkTickets').orderByChild('uid').equalTo(uid).get()).exists(),false);
    });
    assert.equal(late.code,'account-deleted',mode+': '+JSON.stringify(late));
    for(const root of ['users','auditLogs','serverRequests','serverRateLimits'])assert.equal((await db.ref(root+'/'+uid).get()).exists(),false,mode+' orphan '+root);
    assert.equal((await db.ref('accountLinkTickets').orderByChild('uid').equalTo(uid).get()).exists(),false);
    assert.equal((await db.ref('accountLinkTickets/foreign_'+suffix).get()).val().uid,foreign.localId);
    assert.equal((await db.ref('auditLogs/'+foreign.localId).get()).exists(),true);
  }
  console.log('ACCOUNT_METADATA_INTEGRATION_PASS '+JSON.stringify({apiRequests:8,separateProcessHeldWrites:3,deniedClientReads:3,deniedClientWrites:3,auditErased:true,ticketsErased:true,foreignMetadataPreserved:true,lateWritesCleaned:true,databaseHost}));
}

if(process.argv[2]==='worker'){
  process.once('message',async request=>{
    const original=db.ref.bind(db);let paused=false,message;
    const target=request.mode==='audit'?`auditLogs/${request.uid}/held`:
      request.mode==='ticket'?`accountLinkTickets/held_${request.uid}`:`serverRateLimits/${request.uid}/heldRate/`;
    // Hold the real SDK write after the helper's first gate in another process.
    db.ref=function(path){
      const ref=original(path);
      if(path&&(path===target||request.mode==='rate'&&path.startsWith(target))){
        const method=request.mode==='audit'?'set':'transaction',write=ref[method].bind(ref);
        ref[method]=async function(...args){
          if(!paused){paused=true;const resumed=new Promise(resolve=>process.once('message',resolve));process.send({ready:true});await resumed;}
          return write(...args);
        };
      }
      return ref;
    };
    try{
      if(request.mode==='audit')await writeAccountAudit(request.uid,{type:'held',username:'must-erase'},'held');
      else if(request.mode==='ticket')await writeAccountLinkTicket(request.uid,'held_'+request.uid,{status:'open'});
      else await rateLimit(request.uid,'heldRate',2,60000);
      message={result:{ok:true}};
    }catch(error){message={result:{code:error.code||'internal',status:error.status||500}};}
    finally{db.ref=original;await Promise.all(getApps().map(deleteApp));}
    await new Promise(resolve=>process.send(message,resolve));process.disconnect();
  });
}else{
  main().catch(error=>{console.error(error);process.exitCode=1;}).finally(async()=>{await Promise.all(getApps().map(deleteApp));});
}
