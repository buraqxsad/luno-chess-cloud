'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const {getDatabase}=require('firebase-admin/database');
const logger=require('firebase-functions/logger');
const api=require('../index')._test;
const {protocol,authority}=require('../lib/battle-v1');
const {STARTER}=require('../rules-v1/dist/src/model');
const {memoryDatabase}=require('./helpers/memory-database');
const owner='round5_history_owner',peer='round5_history_peer';
const client={platform:'android',build:19,protocolVersion:protocol.PROTOCOL};
function setup(t){
 const at=Date.UTC(2026,10,3,12);t.mock.method(Date,'now',()=>at);
 const db=memoryDatabase(t,{users:{[owner]:api.starterProfile(owner,'Retired history name'),[peer]:api.starterProfile(peer,'Surviving peer')},
  battleRollout:{config:{...protocol.LEGACY_ONLY,configVersion:2,v1MatchmakingEnabled:true}}});
 t.mock.method(getAuth(),'verifyIdToken',async uid=>({uid,auth_time:Math.floor(at/1000),firebase:{sign_in_provider:'anonymous'}}));
 t.mock.method(getAuth(),'deleteUser',async()=>{});
 t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
 for(const level of ['info','warn','error'])t.mock.method(logger,level,()=>{});
 return db;
}
async function request(uid,route,body,id,expectedStatus=200){
 const headers={authorization:'Bearer '+uid,'x-firebase-appcheck':'local-round5-attestation','x-luno-request-id':id};
 let status,value;await api.handler({method:'POST',path:'/'+route,body,get:name=>headers[name.toLowerCase()]||''},
  {set(){return this;},status(code){status=code;return this;},json(result){value=result;}});
 assert.equal(status,expectedStatus,JSON.stringify({route,status,body:value}));return value;
}
async function match(number){
 assert.equal((await request(owner,'enqueueBattleV1',{client},'round5-history-owner-'+number)).status,'queued');
 const joined=await request(peer,'enqueueBattleV1',{client},'round5-history-peer-'+number);
 const ended=await request(owner,'resignBattleV1',{matchId:joined.matchId,protocolVersion:protocol.PROTOCOL,expectedStateVersion:0,
  actionId:'a0_round5-history-resign-'+number},'round5-history-resign-'+number);
 assert.equal(ended.status,'finished');assert.equal(ended.view.public.settlementStatus,'complete');return joined.matchId;
}
async function ack(id,number){return request(owner,'ackBattleV1Result',{matchId:id,protocolVersion:protocol.PROTOCOL},'round5-history-ack-'+number);}
async function erase(){assert.equal((await request(owner,'deleteAccount',{confirm:true},'round5-history-delete')).deleted,true);}
function assertRetired(db,id,originalResult){
 const canonical=api.battleV1.hydrate(db.read('matchSecretsV1/'+id)),projected=db.read('matchesV1/'+id),side=canonical.players.w.uid===owner?'w':'b';
 assert.deepEqual(canonical.result,originalResult,'Result and surviving player history are retained.');
 assert.equal(projected.public.participants[peer],true);assert.ok(projected.private[peer]);
 assert.equal(canonical.players[side].name,'Deleted player','Historical result cannot retain the deleted account display name.');
 assert.equal(canonical.deletedParticipants?.[owner],true);
 assert.equal(projected.public.players[side].name,'Deleted player');
 assert.equal(projected.public.participants[owner],undefined);assert.equal(projected.private[owner],undefined);
 assert.equal(db.read('matchEmotesV1/'+id),null);
}
test('deleting an account retires its current unacknowledged completed V1 result',async t=>{
 const db=setup(t),id=await match(1),result=api.battleV1.hydrate(db.read('matchSecretsV1/'+id)).result;
 await erase();assertRetired(db,id,result);assert.equal(db.read('users/'+owner),null);
});
test('acknowledging a completed V1 result cannot exempt it from later account erasure',async t=>{
 const db=setup(t),id=await match(1),result=api.battleV1.hydrate(db.read('matchSecretsV1/'+id)).result;
 await ack(id,1);assert.equal(db.read('battleV1Control/lastMatch/'+owner),null);
 await erase();assertRetired(db,id,result);
});
test('two legal completed matches retain peer results while erasing the account from both histories',async t=>{
 const db=setup(t),older=await match(1),olderResult=api.battleV1.hydrate(db.read('matchSecretsV1/'+older)).result;
 await ack(older,1);
 const latest=await match(2),latestResult=api.battleV1.hydrate(db.read('matchSecretsV1/'+latest)).result;
 assert.notEqual(older,latest);await erase();assertRetired(db,latest,latestResult);assertRetired(db,older,olderResult);
});

test('interrupted historical projection retirement retries the same page without rating twice',async t=>{
 const db=setup(t),id=await match(1),result=api.battleV1.hydrate(db.read('matchSecretsV1/'+id)).result;
 await ack(id,1);
 const peerAccount=structuredClone(db.read('battleV1Accounts/'+peer)),publish=api.battleV1.publish;
 let failed=false;
 t.mock.method(api.battleV1,'publish',async match=>{
  if(!failed&&match.matchId===id&&match.deletedParticipants?.[owner]){
   failed=true;throw Object.assign(new Error('Local projection interruption'),{code:'ROUND5_PROJECTION_UNAVAILABLE',status:503});
  }
  return publish(match);
 });
 await request(owner,'deleteAccount',{confirm:true},'round5-history-interrupted-delete',503);
 assert.equal(failed,true);assert.equal(db.read('accountDeletions/'+api.hash(owner)+'/status'),'processing');
 assert.equal(db.read('accountDeletions/'+api.hash(owner)+'/battleV1HistoryCursor'),null,'An unfinished page must remain retryable.');
 assert.ok(db.read('users/'+owner));
 await erase();assertRetired(db,id,result);
 assert.deepEqual(db.read('battleV1Accounts/'+peer),peerAccount,'Retry preserves the already committed surviving peer settlement.');
});

test('historical erasure bounds each scan and resumes beyond a full unrelated backlog',async t=>{
 const db=setup(t),id=await match(1),result=api.battleV1.hydrate(db.read('matchSecretsV1/'+id)).result;
 await ack(id,1);
 const template=authority.createServerMatch('bv1_'+'1'.repeat(32),{uid:peer,name:'Surviving peer',bot:false},
  {uid:'round5_unrelated_player',name:'Unrelated player',bot:false},STARTER,STARTER,Date.now(),false);
 const ids=[];
 for(let number=1;number<=201;number++){
  const key='bv1_'+number.toString(16).padStart(32,'0');ids.push(key);
  assert.ok(key<id,'The existing unrelated backlog precedes the historical owner match.');
  db.write('matchSecretsV1/'+key,api.battleV1.stored({...template,matchId:key}));
 }
 const unrelated=structuredClone(db.read('matchSecretsV1/'+ids[0]));
 const database=getDatabase(),ref=database.ref.bind(database),limits=[];
 function watched(node,limit){return {...node,
  orderByKey(){return watched(node.orderByKey(),limit);},
  startAfter(key){return watched(node.startAfter(key),limit);},
  limitToFirst(next){return watched(node.limitToFirst(next),next);},
  async get(){limits.push(limit);return node.get();},
 };}
 t.mock.method(database,'ref',(path='',...args)=>path==='matchSecretsV1'?watched(ref(path,...args)):ref(path,...args));
 const first=await request(owner,'deleteAccount',{confirm:true},'round5-history-bounded-delete',503);
 assert.equal(first.error,'account-deletion-in-progress');assert.ok(db.read('users/'+owner));
 assert.equal(db.read('accountDeletions/'+api.hash(owner)+'/battleV1HistoryCursor'),ids[199]);
 assert.equal(limits.length,41,'One request reads at most 40 pages plus one bounded tail probe.');
 assert.ok(limits.every(limit=>limit>=1&&limit<=5));
 await erase();assertRetired(db,id,result);
 assert.deepEqual(db.read('matchSecretsV1/'+ids[0]),unrelated,'An unrelated canonical match is never rewritten.');
 assert.equal(db.read('accountDeletions/'+api.hash(owner)+'/battleV1HistoryErased'),true);
});

test('an admission captured before erasure retires a late canonical match after the historical cursor finishes',async t=>{
 const db=setup(t);
 assert.equal((await request(peer,'enqueueBattleV1',{client},'round5-history-waiting-peer')).status,'queued');
 const database=getDatabase(),ref=database.ref.bind(database);
 let entered,release,held=false;
 const reached=new Promise(resolve=>{entered=resolve;}),resume=new Promise(resolve=>{release=resolve;});
 t.mock.method(database,'ref',(path='',...args)=>{
  const node=ref(path,...args);if(path!=='battleV1Control')return node;
  return {...node,async transaction(...txArgs){if(!held){held=true;entered();await resume;}return node.transaction(...txArgs);}};
 });
 const admission=request(owner,'enqueueBattleV1',{client},'round5-history-held-admission',403);
 try{
  await reached;await erase();
  assert.equal(db.read('matchSecretsV1'),null);
  assert.equal(db.read('accountDeletions/'+api.hash(owner)+'/battleV1HistoryErased'),true,'The deletion scan finishes before the captured admission creates its match.');
 }finally{release();}
 const rejected=await admission;assert.equal(rejected.error,'account-deleted');
 const matches=Object.entries(db.read('matchSecretsV1')||{});assert.equal(matches.length,1);
 const [id,value]=matches[0],match=api.battleV1.hydrate(value);
 assert.equal(match.result.reason,'account-deleted');assertRetired(db,id,match.result);
 assert.equal(db.read('battleV1Control/active/'+owner),null);assert.equal(db.read('battleV1Control/queue/'+owner),null);
 assert.equal(db.read('users/'+owner),null);assert.ok(db.read('users/'+peer));
});
