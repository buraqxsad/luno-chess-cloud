'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {getAuth}=require('firebase-admin/auth');
const {getDatabase}=require('firebase-admin/database');
const logger=require('firebase-functions/logger');
const api=require('../index')._test;
const {authority}=require('../lib/battle-v1');
const {memoryDatabase}=require('./helpers/memory-database');

const owner='round3_settlement_owner',peer='round3_settlement_peer';
const id='bv1_'+'3a'.repeat(16);

async function setup(t){
 const db=memoryDatabase(t,{users:{
  [owner]:api.starterProfile(owner,'round3_erased_name'),
  [peer]:api.starterProfile(peer,'round3_survivor_name'),
 }});
 t.mock.method(getAuth(),'deleteUser',async()=>{});
 for(const level of ['info','warn','error'])t.mock.method(logger,level,()=>{});
 const white=await api.battleV1.entry(owner,{}),black=await api.battleV1.entry(peer,{});
 await api.battleV1.create(id,white.player,black.player,white.deck,black.deck,true);
 db.write('battleV1Control',{active:{[owner]:id,[peer]:id}});
 await api.battleV1.transact(id,peer,m=>({match:authority.finishMatch(m,{reason:'resign',winner:'b',finishedAt:Date.now()})}));
 return db;
}
async function erase(){
 const response=await api.deleteAccount({uid:owner,body:{confirm:true},requestId:'round3-terminal-erasure',
  token:{auth_time:Math.floor(Date.now()/1000),firebase:{sign_in_provider:'anonymous'}}});
 assert.equal(response.deleted,true);
}
function assertErased(db){
 assert.equal(db.read('accountDeletions/'+api.hash(owner)+'/status'),'complete');
 assert.equal(db.read('users/'+owner),null);
 assert.equal(db.read('battleV1Accounts/'+owner),null);
 assert.equal(db.read('battleV1Ratings/'+owner),null,'A delayed terminal settlement must not republish the erased UID/name in the V1 rating index.');
 assert.equal(db.read('matchesV1/'+id+'/private/'+owner),null);
 assert.equal(db.read('matchesV1/'+id+'/public/participants/'+owner),null);
 assert.equal(db.read('users/'+peer+'/uid'),peer);
 assert.ok(db.read('battleV1Ratings/'+peer));
 const match=api.battleV1.hydrate(db.read('matchSecretsV1/'+id));
 assert.equal(match.settlementStatus,'complete');
 assert.equal(match.deletedParticipants[owner],true,'A stale settlement receipt must preserve revoked membership.');
 assert.equal(match.players.w.name,'Deleted player');
 assert.equal(db.read('matchesV1/'+id+'/public/stateVersion'),match.stateVersion);
}

test('terminal settlement followed by complete account deletion erases its public rating row',async t=>{
 const db=await setup(t);await api.battleV1.settle(id,peer);await erase();assertErased(db);
});

for(const point of ['before-rating-write','after-rating-write'])test('completed erasure fences a delayed terminal rating projection '+point,async t=>{
 const db=await setup(t),database=getDatabase(),original=database.ref.bind(database);
 let entered,release,held=false;
 const reached=new Promise(resolve=>{entered=resolve;}),resume=new Promise(resolve=>{release=resolve;});
 t.mock.method(database,'ref',(path='',...args)=>{
  const node=original(path,...args);if(path!=='battleV1Ratings/'+owner)return node;
  return {...node,async transaction(...txArgs){
   if(held)return node.transaction(...txArgs);
   held=true;
   if(point==='before-rating-write'){entered();await resume;return node.transaction(...txArgs);}
   // Preserve the SDK's actual committed snapshot while another invocation
   // completes deletion before this transaction Promise is delivered.
   const committed=await node.transaction(...txArgs);entered();await resume;return committed;
  }};
 });
 const settling=api.battleV1.settle(id,peer);
 try{await reached;await erase();assert.equal(db.read('battleV1Ratings/'+owner),null);}
 finally{release();}
 await settling;
 assert.equal(held,true);assertErased(db);
});

test('a transient rating publication failure stays retryable and does not double-rate players',async t=>{
 const db=await setup(t),database=getDatabase(),original=database.ref.bind(database);let failed=false;
 t.mock.method(database,'ref',(path='',...args)=>{
  const node=original(path,...args);if(path!=='battleV1Ratings/'+owner)return node;
  return {...node,async transaction(...txArgs){
   if(!failed){failed=true;const error=new Error('Local rating index unavailable');error.code='ROUND3_INDEX_UNAVAILABLE';throw error;}
   return node.transaction(...txArgs);
  }};
 });
 await assert.rejects(api.battleV1.settle(id,peer),{code:'ROUND3_INDEX_UNAVAILABLE'});
 assert.equal(api.battleV1.hydrate(db.read('matchSecretsV1/'+id)).settlementStatus,'pending');
 await api.battleV1.settle(id,peer);
 assert.equal(api.battleV1.hydrate(db.read('matchSecretsV1/'+id)).settlementStatus,'complete');
 for(const uid of [owner,peer]){
  assert.equal(JSON.parse(db.read('battleV1Accounts/'+uid).accountJson).games,1);
  assert.equal(JSON.parse(db.read('battleV1Accounts/'+uid).accountJson).ratingRevision,1);
  assert.equal(db.read('battleV1Ratings/'+uid+'/revision'),1);
 }
});
