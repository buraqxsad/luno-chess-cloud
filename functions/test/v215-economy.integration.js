'use strict';

const {authHost,databaseHost}=require('./helpers/local-emulators').requireLocalEmulators();
if(!/^demo-luno(?:-|$)/.test(process.env.GCLOUD_PROJECT||''))throw new Error('Explicit demo-luno emulator project required.');
const assert=require('node:assert/strict');
const {fork}=require('node:child_process');
const {getApps,deleteApp}=require('firebase-admin/app');
const {getDatabase}=require('firebase-admin/database');
const api=require('../index')._test;
const {verifiedEarlyProgress}=require('../lib/battle-v1-progression');
const {STARTER}=require('../rules-v1/dist/src/model');
const db=getDatabase(),DAY=86400000;
const client={platform:'android',build:17,protocolVersion:'LUNO_BATTLE_V1'};

async function anonymousUser(){
  const response=await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-key`,{
    method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({returnSecureToken:true}),signal:AbortSignal.timeout(15000),
  });
  const body=await response.json();assert.equal(response.status,200,JSON.stringify(body));return body;
}
async function call(user,route,body,id){
  const headers={authorization:'Bearer '+user.idToken,'x-firebase-appcheck':'luno-emulator-app-check',
    'x-luno-request-id':id,origin:'https://localhost'};
  let status,result,timer;
  try{
    await Promise.race([
      api.handler({method:'POST',path:'/'+route,body,get:name=>headers[name.toLowerCase()]||''},
        {set(){return this;},status(value){status=value;return this;},json(value){result=value;}}),
      new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('Economy API timeout: '+route)),45000);}),
    ]);
  }finally{clearTimeout(timer);}
  return {status,body:result};
}
async function readProfile(uid){return (await db.ref('users/'+uid).get()).val();}
function requestPath(uid,id){return `serverRequests/${uid}/${api.hash(id).slice(0,48)}`;}
function sourceEntries(profile,type){return Object.values(profile.serverEconomy.ledger||{}).filter(entry=>entry.sourceType===type);}
function successful(response){assert.equal(response.status,200,JSON.stringify(response));return response.body;}
function launch(user,id){
  const child=fork(__filename,['worker'],{stdio:['ignore','pipe','pipe','ipc'],windowsHide:true});
  return new Promise((resolve,reject)=>{
    let output='',message;
    const timer=setTimeout(()=>{child.kill();reject(new Error('Economy worker timed out.'));},55000);
    for(const stream of [child.stdout,child.stderr])stream.on('data',chunk=>{output=(output+chunk).slice(-4000);});
    child.on('message',value=>{message=value;});
    child.once('error',error=>{clearTimeout(timer);reject(error);});
    child.once('exit',code=>{
      clearTimeout(timer);
      if(code!==0||!message||message.error)reject(new Error(message?.error||'Economy worker failed: '+code+' '+output));
      else resolve(message.result);
    });
    child.send({user,id});
  });
}
async function withServerClock(at,operation){
  const realNow=Date.now;Date.now=()=>at;
  try{return await operation();}finally{Date.now=realNow;}
}
async function daily(uid,id,at){
  // Exercise the real route transaction with a server-clock fixture. Auth is
  // separately exercised through handler; advancing JWT expiry is not the test.
  return withServerClock(at,()=>api.claimDailyReward({uid,requestId:id,body:{}}));
}
async function deck(uid,at){
  return withServerClock(at,()=>api.battleV1.getBattleV1Deck({uid,requestId:'deck-'+at,body:{client}}));
}

async function main(){
  const [user,other]=await Promise.all([anonymousUser(),anonymousUser()]);
  const uid=user.localId,otherUid=other.localId,suffix=Date.now().toString(36),sameId='v215-welcome-same-'+suffix;
  successful(await call(user,'createGuestPlayer',{},'v215-create-'+suffix));
  successful(await call(other,'createGuestPlayer',{},'v215-other-create-'+suffix));
  const before=await readProfile(uid),otherBefore=await readProfile(otherUid);
  assert.equal(before.gold,1250);assert.equal(before.gems,50);

  const competing=await Promise.all(Array.from({length:5},()=>launch(user,sameId)));
  assert(competing.some(response=>response.status===200));
  for(const response of competing){
    assert(response.status===200||response.status===409&&response.body.error==='request-in-progress',JSON.stringify(response));
    if(response.status===200){assert.equal(response.body.welcome.claimed,true);assert.equal(response.body.welcome.card,'mine');}
  }
  let stored=await readProfile(uid);
  assert.equal(stored.gold,before.gold+500);assert.equal(sourceEntries(stored,'onboarding_reward').length,1);
  assert.equal(stored.battleV1UnlockedCards.mine,true);
  const distinct=await Promise.all(Array.from({length:3},(_,n)=>launch(user,'v215-welcome-distinct-'+n+'-'+suffix)));
  for(const response of distinct){const body=successful(response);assert.equal(body.granted,false);assert.equal(body.welcome.claimed,true);}
  assert.deepEqual(await readProfile(uid),stored);

  await db.ref(requestPath(uid,sameId)).remove();
  const replay=successful(await call(user,'claimOnboardingReward',{},sameId));
  assert.equal(replay.granted,false);assert.equal(replay.idempotent,true);
  assert.deepEqual(await readProfile(uid),stored);

  // Simulate an existing paid welcome receipt from before Mine delivery existed.
  const receipt=structuredClone(stored.serverEconomy.claims),ledger=structuredClone(stored.serverEconomy.ledger);
  await db.ref('users/'+uid+'/battleV1UnlockedCards/mine').remove();
  await db.ref(requestPath(uid,sameId)).remove();
  const repaired=successful(await call(user,'claimOnboardingReward',{},sameId));
  assert.equal(repaired.granted,false);assert.equal(repaired.welcome.claimed,true);
  stored=await readProfile(uid);assert.equal(stored.gold,before.gold+500);assert.equal(stored.battleV1UnlockedCards.mine,true);
  assert.deepEqual(stored.serverEconomy.claims,receipt);assert.deepEqual(stored.serverEconomy.ledger,ledger);

  const now=Date.now(),midnight=(Math.floor(now/DAY)+1)*DAY;
  const dailyTimes=[midnight-1,midnight,midnight+DAY];
  for(let n=0;n<dailyTimes.length;n++){
    const time=dailyTimes[n];
    const first=await daily(uid,'v215-day-'+n+'-'+suffix,time);assert.equal(first.granted,true);
    const snapshot=await readProfile(uid),again=await daily(uid,'v215-day-repeat-'+n+'-'+suffix,time);
    assert.equal(again.granted,false);assert.deepEqual(await readProfile(uid),snapshot);
    const view=await deck(uid,time);
    assert.equal(view.progression.version,2);assert.equal(view.progression.meaningfulMatches,0);
    assert.equal(view.progression.early.welcomeClaimed,true);
    assert.equal(view.progression.early.distinctDailyClaims,n+1);
    assert.equal(view.entitlements.includes('break_seal'),n>=1);
    assert.equal(view.entitlements.includes('fog'),n>=2);
  }
  stored=await readProfile(uid);
  assert.equal(sourceEntries(stored,'daily_reward').length,3);
  assert.deepEqual(verifiedEarlyProgress(stored,uid,midnight+DAY+1),{welcomeClaimed:true,distinctDailyClaims:3});
  const currentDeck=await deck(uid,midnight+DAY+1);
  for(const card of ['mine','break_seal','fog'])assert(currentDeck.entitlements.includes(card));
  assert.equal(currentDeck.deck.length,10);
  assert(currentDeck.deck.every(card=>currentDeck.entitlements.includes(card)));
  assert.deepEqual(new Set(currentDeck.entitlements),new Set([...STARTER,'mine','break_seal','fog']));

  const otherDeck=await deck(otherUid,midnight+DAY+1);
  assert.deepEqual(otherDeck.progression.early,{welcomeClaimed:false,distinctDailyClaims:0});
  assert.equal(otherDeck.entitlements.includes('mine'),false);assert.deepEqual(await readProfile(otherUid),otherBefore);
  const current=await readProfile(uid);
  const spoof=await call(user,'claimOnboardingReward',{wonOffline:true,uid:otherUid,at:midnight+DAY},'v215-spoof-'+suffix);
  assert.equal(spoof.status,400);assert.deepEqual(await readProfile(uid),current);
  console.log('V215_ECONOMY_INTEGRATION_PASS '+JSON.stringify({sameRequestWorkers:5,distinctRequestWorkers:3,
    welcomeLedgerEntries:1,additionalWelcomeCredit:500,historicMineRepairNoRecredit:true,cacheLossReplay:true,
    dailyLedgerEntries:3,utcDays:true,earlyCards:['mine','break_seal','fog'],meaningfulRankedMatches:0,
    accountIsolation:true,spoofedOfflineWinRejected:true,databaseHost,serverClockFixture:true,liveChange:false}));
}

if(process.argv[2]==='worker'){
  process.once('message',async request=>{
    let result;
    try{result={result:await call(request.user,'claimOnboardingReward',{},request.id)};}
    catch(error){result={error:error.stack||String(error)};}
    finally{await Promise.all(getApps().map(deleteApp));}
    await new Promise(resolve=>process.send(result,resolve));process.disconnect();
  });
}else{
  main().catch(error=>{console.error(error);process.exitCode=1;}).finally(async()=>{await Promise.all(getApps().map(deleteApp));});
}
