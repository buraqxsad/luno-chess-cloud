'use strict';

const fs=require('node:fs');
const path=require('node:path');
const net=require('node:net');
const {spawn}=require('node:child_process');
const {root,qa,projectId,namespace,databaseHost,runtimeStamp,saveJson}=require('./v220-support.cjs');

const mode=process.argv[2]||'baseline';
if(!['baseline','emulator','capacity','unit'].includes(mode))throw new Error('Use baseline, emulator, capacity, or unit.');
fs.mkdirSync(qa,{recursive:true});

function runNode(args,log,env=process.env,timeoutMs=180000){
  return new Promise((resolve,reject)=>{
    args=['--max-old-space-size=192',...args];
    if(fs.existsSync(path.join(qa,log)))log=path.parse(log).name+'-'+Date.now()+path.extname(log);
    const output=fs.createWriteStream(path.join(qa,log));
    output.write(JSON.stringify({command:[process.execPath,...args],cwd:path.join(root,'functions'),startedAt:new Date().toISOString()})+'\n');
    const child=spawn(process.execPath,args,{cwd:path.join(root,'functions'),env,windowsHide:true,stdio:['ignore','pipe','pipe']});
    child.stdout.on('data',chunk=>output.write(chunk));child.stderr.on('data',chunk=>output.write(chunk));
    const timer=setTimeout(()=>child.kill(),timeoutMs);
    child.on('error',error=>{clearTimeout(timer);output.end(String(error));reject(error);});
    child.on('close',(code,signal)=>{clearTimeout(timer);output.end(JSON.stringify({exitCode:code,signal,finishedAt:new Date().toISOString()})+'\n',()=>resolve({code,signal,log}));});
  });
}

async function assertPortFree(){
  await new Promise((resolve,reject)=>{
    const socket=net.connect({host:'127.0.0.1',port:19000});
    socket.once('connect',()=>{socket.destroy();reject(new Error('Port 19000 is occupied; refusing to reuse another service.'));});
    socket.once('error',error=>error.code==='ECONNREFUSED'?resolve():reject(error));
    socket.setTimeout(2000,()=>{socket.destroy();reject(new Error('Port check timed out.'));});
  });
}

async function emulator(){
  if(process.env.V220_EMULATOR_APPROVED!=='1')throw new Error('Wait for parent build-complete notification, then explicitly set V220_EMULATOR_APPROVED=1.');
  if(process.env.V220_QUERY_COMPAT_CANDIDATE==='1')throw new Error('The exploratory query override was removed. Unset V220_QUERY_COMPAT_CANDIDATE for actual runtime verification.');
  await assertPortFree();
  const java='C:\\Program Files\\Microsoft\\jdk-21.0.12.8-hotspot\\bin\\java.exe';
  const jar=path.join(process.env.USERPROFILE,'.cache/firebase/emulators/firebase-database-emulator-v4.11.2.jar');
  if(!fs.existsSync(java)||!fs.existsSync(jar))throw new Error('Existing JDK21/emulator JAR not found; no download attempted.');
  const args=['-Xms32m','-Xmx256m','-jar',jar,'--host','127.0.0.1','--port','19000','--single_project_mode','Error'];
  const serverLog=fs.existsSync(path.join(qa,'emulator-server.log'))?'emulator-server-'+Date.now()+'.log':'emulator-server.log';
  const output=fs.createWriteStream(path.join(qa,serverLog));
  const child=spawn(java,args,{cwd:qa,windowsHide:true,stdio:['ignore','pipe','pipe']});
  const stopped=new Promise(resolve=>child.once('close',(code,signal)=>resolve({code,signal})));
  child.stdout.on('data',chunk=>output.write(chunk));child.stderr.on('data',chunk=>output.write(chunk));
  let launchError=null;child.once('error',error=>{launchError=error;});
  const env={...process.env,V220_DB_INTEGRATION:'1',V220_RED_REPRO:'1',GCLOUD_PROJECT:projectId,
    GOOGLE_CLOUD_PROJECT:projectId,FIREBASE_DATABASE_EMULATOR_HOST:databaseHost,LUNO_DB_EMULATOR_NAMESPACE:namespace};
  for(const key of ['FIREBASE_AUTH_EMULATOR_HOST','GOOGLE_APPLICATION_CREDENTIALS','FIREBASE_CONFIG'])delete env[key];
  saveJson('emulator-command.json',{java,args,serverLog,host:databaseHost,projectId,namespace,heapLimitMiB:256,
    queryCompatibilityCandidate:env.V220_QUERY_COMPAT_CANDIDATE==='1',
    rules:'database.rules.production.json loaded into isolated namespace only',auth:'mocked handler identity and emulator-only unsigned JWTs for rules',
    appCheck:'mocked verifier; no Play Integrity verification',googlePlay:'mocked Android Publisher; no real receipts'});
  try{
    let ready=false;
    for(let attempt=0;attempt<80;attempt++){
      if(launchError)throw launchError;
      if(child.exitCode!==null)throw new Error('Emulator exited before readiness.');
      try{
        const response=await fetch(`http://${databaseHost}/.json?ns=${namespace}`,{signal:AbortSignal.timeout(500)});
        if(response.ok){ready=true;break;}
      }catch(_){}
      await new Promise(resolve=>setTimeout(resolve,250));
    }
    if(!ready)throw new Error('Local emulator readiness timed out.');
    return await runNode(['--test','--test-concurrency=1','test/v220-firebase-integration.test.js'],'firebase-integration.log',env);
  }finally{
    child.kill();
    const status=await stopped;
    await new Promise(resolve=>output.end(resolve));
    saveJson('emulator-stop.json',{...status,stoppedAt:new Date().toISOString()});
  }
}

async function main(){
  const before=runtimeStamp();saveJson('source-before-'+mode+'.json',before);
  let result;
  if(mode==='baseline')result=await runNode(['--test','--test-concurrency=1','test/v219-sidecar-social-integrity.test.js',
    'test/v219-sidecar-product-integrity.test.js','test/v217-billing-recovery.test.js','test/dm-receipt-race.test.js',
    'test/v220-mock-gaps.test.js'],'baseline-focused.log');
  if(mode==='unit')result=await runNode(['--test','--test-concurrency=1','test/v220-query-compat.test.js',
    'test/v220-mock-gaps.test.js','test/v220-rules-contract.test.js'],'v220-unit.log');
  if(mode==='emulator')result=await emulator();
  if(mode==='capacity'){
    const synthetic=await runNode(['tools/v220-capacity.cjs'],'capacity.log');
    if(synthetic.code!==0)result=synthetic;
    else result=await runNode(['--test','--test-concurrency=1',path.join(qa,'capacity-proposal-experiment.cjs')],'capacity-red.log',
      {...process.env,V220_RED_REPRO:'1'});
  }
  const after=runtimeStamp();saveJson('source-after-'+mode+'.json',after);
  const mutated=Object.keys(before.files).filter(key=>before.files[key].sha256!==after.files[key].sha256);
  for(const key of new Set([...Object.keys(before.sidecarFiles),...Object.keys(after.sidecarFiles)])){
    if(before.sidecarFiles[key]!==after.sidecarFiles[key])mutated.push(key);
  }
  const summary={mode,...result,sourceFilesChecked:Object.keys(before.files).length,
    sidecarSourceFilesChecked:Object.keys(before.sidecarFiles).length,queryCompatibilityCandidate:process.env.V220_QUERY_COMPAT_CANDIDATE==='1',
    v219Differences:before.changed,mutatedDuringRun:mutated};
  saveJson('result-'+mode+'.json',summary);
  console.log(JSON.stringify(summary,null,2));
  process.exitCode=result.code===0&&mutated.length===0?0:1;
}
main().catch(error=>{
  saveJson('failure-'+mode+'.json',{mode,error:String(error),stack:error.stack,at:new Date().toISOString()});
  console.error(error);process.exitCode=1;
});
