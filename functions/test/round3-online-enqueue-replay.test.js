'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const {getDatabase}=require('firebase-admin/database');
const logger=require('firebase-functions/logger');
const api=require('../index')._test;
const {protocol}=require('../lib/battle-v1');
const {memoryDatabase}=require('./helpers/memory-database');

const first='round3_queue_first',retrying='round3_queue_retrying',third='round3_queue_third';
const client={platform:'android',build:19,protocolVersion:protocol.PROTOCOL};
const originalRequest='round3-enqueue-original-network-request';

function setup(t){
 const users={};
 for(const [i,uid] of [first,retrying,third].entries()){
  users[uid]=api.starterProfile(uid,'round3_queue_user_'+i);
  users[uid].legalConsent={uid,acceptedAt:1,termsVersion:api.LEGAL_TERMS_VERSION,privacyVersion:api.LEGAL_PRIVACY_VERSION,communityVersion:api.LEGAL_COMMUNITY_VERSION};
 }
 const db=memoryDatabase(t,{users,battleRollout:{config:{configVersion:2,configJson:JSON.stringify({...protocol.LEGACY_ONLY,configVersion:2,v1MatchmakingEnabled:true})}}});
 t.mock.method(getAuth(),'verifyIdToken',async uid=>({uid,auth_time:Math.floor(Date.now()/1000),firebase:{sign_in_provider:'anonymous'}}));
 t.mock.method(getAuth(),'deleteUser',async()=>{});
 t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
 for(const level of ['info','warn','error'])t.mock.method(logger,level,()=>{});
 return db;
}
async function request(uid,route,body,id){
 const headers={authorization:'Bearer '+uid,'x-firebase-appcheck':'local-round3-attestation','x-luno-request-id':id};
 let status,value;
 await api.handler({method:'POST',path:'/'+route,body,get:name=>headers[name.toLowerCase()]||''},
  {set(){return this;},status(code){status=code;return this;},json(result){value=result;}});
 return {status,body:value};
}
async function finishOriginal(firstAlreadyQueued=false){
 if(!firstAlreadyQueued){
 const waiting=await request(first,'enqueueBattleV1',{client},'round3-first-enqueue');assert.equal(waiting.status,200);assert.equal(waiting.body.status,'queued');
 }
 const original=await request(retrying,'enqueueBattleV1',{client},originalRequest);assert.equal(original.status,200);assert.equal(original.body.status,'active');
 // The original enqueue response can be lost in transport while its opponent
 // sees the match and resigns before the same client request is retried.
 const ended=await request(first,'resignBattleV1',{matchId:original.body.matchId,protocolVersion:protocol.PROTOCOL,expectedStateVersion:0,actionId:'a0_round3-network-retry-resign'},'round3-first-resign');
 assert.equal(ended.status,200,JSON.stringify(ended));assert.equal(ended.body.status,'finished');
 const queued=await request(third,'enqueueBattleV1',{client},'round3-third-waits');assert.equal(queued.status,200);assert.equal(queued.body.status,'queued');
 return original.body.matchId;
}

test('a fresh post-result enqueue can still pair a waiting third player',async t=>{
 const db=setup(t),oldId=await finishOriginal();
 const joined=await request(retrying,'enqueueBattleV1',{client},'round3-fresh-enqueue');
 assert.equal(joined.status,200,JSON.stringify(joined));assert.equal(joined.body.status,'active');assert.notEqual(joined.body.matchId,oldId);
 const resumed=await request(third,'getBattleV1',{matchId:'',protocolVersion:protocol.PROTOCOL},'round3-third-resume-fresh');
 assert.equal(resumed.status,200,JSON.stringify(resumed));assert.equal(resumed.body.matchId,joined.body.matchId);
 assert.equal(db.read('battleV1Control/active/'+third),joined.body.matchId);
});

test('a delayed enqueue replay cannot trap a third player behind a conflicting old reservation',async t=>{
 const db=setup(t),oldId=await finishOriginal();
 const before=structuredClone(db.read('battleV1Control/queue/'+third));
 const replay=await request(retrying,'enqueueBattleV1',{client},originalRequest);
 const after=structuredClone(db.read('battleV1Control/queue/'+third));
 const recovery=[];
 recovery.push(await request(third,'getBattleV1',{matchId:'',protocolVersion:protocol.PROTOCOL},'round3-third-get-after-replay'));
 recovery.push(await request(third,'cancelBattleV1Queue',{protocolVersion:protocol.PROTOCOL},'round3-third-cancel-after-replay'));
 recovery.push(await request(third,'enqueueBattleV1',{client},'round3-third-reenqueue-after-replay'));
 assert.ok(recovery.some(result=>result.status===200),'An unrelated waiting player must retain a working get/cancel/enqueue recovery path: '+JSON.stringify({replay,recovery,active:db.read('battleV1Control/active/'+third),oldId}));
 assert.equal(replay.status,200,JSON.stringify(replay));assert.equal(replay.body.matchId,oldId);
 for(const key of ['uid','player','deck','joinedAt','skill'])assert.deepEqual(after[key],before[key],'The unrelated peer queue entry must be preserved: '+key);
 const active=db.read('battleV1Control/active/'+third);
 if(active){const match=api.battleV1.hydrate(db.read('matchSecretsV1/'+active));assert.ok(Object.values(match.players).some(player=>player.uid===third),'Every active UID must belong to its canonical match.');}
});

test('a concurrent same-ID admission held before control commit cannot poison a later peer after its twin finishes',async t=>{
 const db=setup(t),database=getDatabase(),original=database.ref.bind(database);
 const waiting=await request(first,'enqueueBattleV1',{client},'round3-first-enqueue');assert.equal(waiting.status,200);
 let entered,release,held=false;
 const reached=new Promise(resolve=>{entered=resolve;}),resume=new Promise(resolve=>{release=resolve;});
 t.mock.method(database,'ref',(path='',...args)=>{
  const node=original(path,...args);if(path!=='battleV1Control')return node;
  return {...node,async transaction(...txArgs){if(!held){held=true;entered();await resume;}return node.transaction(...txArgs);}};
 });
 // This request starts before the canonical old match exists. A pre-read of
 // matchSecrets alone cannot fence it across the following control boundary.
 const delayed=request(retrying,'enqueueBattleV1',{client},originalRequest);
 let oldId,before;
 try{await reached;oldId=await finishOriginal(true);before=structuredClone(db.read('battleV1Control/queue/'+third));}
 finally{release();}
 const replay=await delayed;
 const after=structuredClone(db.read('battleV1Control/queue/'+third));
 const recovered=await request(third,'cancelBattleV1Queue',{protocolVersion:protocol.PROTOCOL},'round3-concurrent-third-cancel');
 assert.equal(recovered.status,200,'The peer must keep its cancellation path after concurrent same-ID admission: '+JSON.stringify({replay,recovered,oldId,active:db.read('battleV1Control/active/'+third)}));
 assert.equal(replay.status,200,JSON.stringify(replay));assert.equal(replay.body.matchId,oldId);
 for(const key of ['uid','player','deck','joinedAt','skill'])assert.deepEqual(after[key],before[key],'Conflict rollback must restore the same waiting peer: '+key);
 assert.equal(db.read('battleV1Control/active/'+third),null);
});

for(const legacy of [false,true])test('an older successful reservation completion cannot remove a newer same-ID reservation token '+(legacy?'legacy-record':'token-record'),async t=>{
 const db=setup(t),oldId=await finishOriginal(),old=api.battleV1.hydrate(db.read('matchSecretsV1/'+oldId));
 const w=await api.battleV1.entry(old.players.w.uid,client),b=await api.battleV1.entry(old.players.b.uid,client);
 const initial={w,b,rated:true,configVersion:2,requestUid:retrying,reservationToken:'round3-old-completion-token'};
 if(legacy){delete initial.requestUid;delete initial.reservationToken;}
 db.write('battleV1Control/reservations/'+oldId,initial);
 const replacement={...initial,requestUid:retrying,reservationToken:'round3-new-completion-token'};
 const create=api.battleV1.create;
 t.mock.method(api.battleV1,'create',async(...args)=>{
  const match=await create(...args);
  // Another admission commits a different attempt at the same deterministic
  // ID while the old successful create Promise is waiting to be delivered.
  db.write('battleV1Control/reservations/'+oldId,replacement);
  return match;
 });
 await api.battleV1.completeReservation(oldId);
 assert.deepEqual(db.read('battleV1Control/reservations/'+oldId),replacement,'An old completion must remove only the reservation it read.');
});

test('conflict recovery cannot cancel a newer attempt or replace its active match',async t=>{
 const db=setup(t),oldId=await finishOriginal();
 const w=await api.battleV1.entry(retrying,client),b=await api.battleV1.entry(third,client);
 const initial={w,b,rated:true,configVersion:2,requestUid:retrying,reservationToken:'round3-old-conflict-token'};
 db.write('battleV1Control/reservations/'+oldId,initial);
 db.write('battleV1Control/active/'+retrying,oldId);db.write('battleV1Control/active/'+third,oldId);
 const newerId='bv1_'+'7b'.repeat(16),replacement={...initial,reservationToken:'round3-new-conflict-token'};
 const create=api.battleV1.create;let replaced=false;
 t.mock.method(api.battleV1,'create',async(...args)=>{
  try{return await create(...args);}
  catch(error){
   if(error.code==='MATCH_CREATION_CONFLICT'){
    replaced=true;db.write('battleV1Control/reservations/'+oldId,replacement);
    db.write('battleV1Control/active/'+third,newerId);
   }
   throw error;
  }
 });
 try{await api.battleV1.completeReservation(oldId);}catch(error){assert.equal(error.code,'MATCH_CREATION_CONFLICT');}
 assert.equal(replaced,true);assert.deepEqual(db.read('battleV1Control/reservations/'+oldId),replacement);
 assert.equal(db.read('battleV1Control/active/'+third),newerId,'Late rollback must not clear a newer active match.');
});
