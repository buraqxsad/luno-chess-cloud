'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {getDatabase}=require('firebase-admin/database');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const logger=require('firebase-functions/logger');
const api=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');
const {LEGACY_ONLY}=require('../lib/battle-v1').protocol;
const uid='round2_erased_player',other='round2_other_player';
const client={platform:'android',build:19,protocolVersion:'LUNO_BATTLE_V1'};
const marker={status:'complete',completedAt:12345};
function erase(db){
 db.write('accountDeletions/'+api.hash(uid),marker);
 db.write('deletedAccounts/'+api.hash(uid),{deletedAt:12345});
 db.write('users/'+uid,null);db.write('battleV1Accounts/'+uid,null);db.write('battleV1Ratings/'+uid,null);
 const control=db.read('battleV1Control');
 if(control){
  const next=structuredClone(control);
  for(const key of ['queue','active','lastMatch','roomByUser'])if(next[key])delete next[key][uid];
  for(const [code,room] of Object.entries(next.rooms||{}))if(room.host.uid===uid||room.guestUid===uid)delete next.rooms[code];
  for(const [key,invite] of Object.entries(next.invites||{}))if(invite.from.uid===uid||invite.to===uid)delete next.invites[key];
  db.write('battleV1Control',next);
 }
}
function setup(t,hook){
 const seed={users:{[uid]:api.starterProfile(uid,'round2_erased'),[other]:api.starterProfile(other,'round2_other')},battleRollout:{config:{configVersion:2,configJson:JSON.stringify({...LEGACY_ONLY,configVersion:2,v1MatchmakingEnabled:true})}}};
 const db=memoryDatabase(t,seed,hook);
 t.mock.method(getAuth(),'verifyIdToken',async()=>({uid}));
 t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
 for(const level of ['info','warn','error'])t.mock.method(logger,level,()=>{});
 return db;
}
async function request(route){
 const headers={authorization:'Bearer local-test-identity','x-firebase-appcheck':'local-test-attestation','x-luno-request-id':'round2-admission-erasure'};
 let status,body;
 await api.handler({method:'POST',path:'/'+route,body:{client},get:n=>headers[n.toLowerCase()]||''},{set(){return this;},status(n){status=n;return this;},json(x){body=x;}});
 return {status,body};
}
for(const route of ['enqueueBattleV1','createBattleV1Room'])for(const timing of ['before-control-commit','after-control-commit'])test(`${route}: ${timing} erasure cannot leave late V1 admission data`,async t=>{
 let erased=false;
 const db=setup(t,{
  beforeTransaction(path,count,store){if(!erased&&timing==='before-control-commit'&&path==='battleV1Control'){erased=true;erase(store);}},

 });
 if(timing==='after-control-commit'){
  // Actual SDK returns its committed snapshot even when another client erases
  // the node before the Promise is delivered; do not reread after erasure.
  const database=getDatabase(),ref=database.ref.bind(database);
  t.mock.method(database,'ref',(path='',...args)=>{
   const node=ref(path,...args);if(path!=='battleV1Control')return node;
   return {...node,async transaction(...args){const committed=await node.transaction(...args);if(!erased){erased=true;erase(db);}return committed;}};
  });
 }
 const result=await request(route);assert.equal(erased,true);
 assert.equal(result.status,403,JSON.stringify(result));assert.equal(result.body.error,'account-deleted');
 assert.equal(db.read('users/'+uid),null);assert.equal(db.read('battleV1Accounts/'+uid),null);
 assert.equal(db.read('battleV1Control/queue/'+uid),null,'Deleted account queue metadata must not be recreated by a captured entry.');
 assert.equal(db.read('battleV1Control/roomByUser/'+uid),null,'Deleted account room membership must not be recreated.');
 assert.equal(Object.values(db.read('battleV1Control/rooms')||{}).some(room=>room.host.uid===uid||room.guestUid===uid),false,'Erased host details must not remain in any room; unrelated rooms may remain.');
 assert.equal(db.read('users/'+other+'/uid'),other);
 assert.deepEqual(db.read('accountDeletions/'+api.hash(uid)),marker);
});
for(const route of ['enqueueBattleV1','createBattleV1Room'])test(`${route}: healthy admission remains usable`,async t=>{
 const db=setup(t,{}),result=await request(route);
 assert.equal(result.status,200,JSON.stringify(result));assert.equal(db.read('users/'+uid+'/uid'),uid);
 if(route==='enqueueBattleV1')assert.equal(result.body.status,'queued');
 else assert.equal(result.body.created,true);
});
