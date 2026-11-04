'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const {getDatabase}=require('firebase-admin/database');
const logger=require('firebase-functions/logger');
const api=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');
const owner='round5_legacy_erased_owner',peer='round5_legacy_surviving_peer';
function setup(t){
 const at=Date.UTC(2026,10,3,12);t.mock.method(Date,'now',()=>at);
 const db=memoryDatabase(t,{users:{[owner]:api.starterProfile(owner,'Legacy deleted alias'),[peer]:api.starterProfile(peer,'Legacy surviving peer')}});
 t.mock.method(getAuth(),'verifyIdToken',async uid=>({uid,auth_time:Math.floor(at/1000),firebase:{sign_in_provider:'anonymous'}}));
 t.mock.method(getAuth(),'deleteUser',async()=>{});
 t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
 for(const level of ['info','warn','error'])t.mock.method(logger,level,()=>{});
 return db;
}
async function request(uid,route,body,id){
 const headers={authorization:'Bearer '+uid,'x-firebase-appcheck':'local-round5-attestation','x-luno-request-id':id};
 let status,value;await api.handler({method:'POST',path:'/'+route,body,get:name=>headers[name.toLowerCase()]||''},
  {set(){return this;},status(code){status=code;return this;},json(result){value=result;}});
 assert.equal(status,200,JSON.stringify({route,status,body:value}));return value;
}
async function completed(){
 const room=await request(owner,'createFriendlyRoom',{durationMinutes:5},'round5-legacy-create-room');
 const joined=await request(peer,'joinFriendlyRoom',{roomCode:room.roomCode},'round5-legacy-join-room');
 const result=await request(owner,'submitMatchAction',{matchId:joined.matchId,type:'resign',actionId:'round5-legacy-resign-action',expectedSequence:0},'round5-legacy-resign');
 assert.equal(result.view.result.reason,'resignation');return joined.matchId;
}
async function active(){
 const room=await request(owner,'createFriendlyRoom',{durationMinutes:5},'round5-legacy-pending-room');
 return (await request(peer,'joinFriendlyRoom',{roomCode:room.roomCode},'round5-legacy-pending-join')).matchId;
}
const privateTrees=['matchHistory','rankedReplays','rankedMatchViews','rankedPlayers'];
test('legacy friendly terminal heartbeat keeps the surviving account result available',async t=>{
 const db=setup(t),id=await completed();
 await request(peer,'heartbeatRankedMatch',{matchId:id},'round5-legacy-live-heartbeat');
 for(const tree of privateTrees)assert.ok(db.read(tree+'/'+peer),'Surviving peer keeps '+tree);
});
test('surviving peer heartbeat cannot recreate erased legacy friendly account records',async t=>{
 const db=setup(t),id=await completed();
 assert.equal((await request(owner,'deleteAccount',{confirm:true},'round5-legacy-delete')).deleted,true);
 for(const tree of privateTrees)assert.equal(db.read(tree+'/'+owner),null,'Actual deletion first removes '+tree);
 await request(peer,'heartbeatRankedMatch',{matchId:id},'round5-legacy-post-delete-heartbeat');
 for(const tree of privateTrees)assert.equal(db.read(tree+'/'+owner),null,'A surviving peer cannot restore erased '+tree);
 assert.equal(db.read('users/'+owner),null);assert.ok(db.read('users/'+peer));
});

test('a pending legacy friendly worker cannot republish erased private state after actual deletion completes',async t=>{
 const db=setup(t),id=await active(),database=getDatabase(),ref=database.ref.bind(database);
 let entered,release,held=false;
 const reached=new Promise(resolve=>{entered=resolve;}),resume=new Promise(resolve=>{release=resolve;});
 t.mock.method(database,'ref',(path='',...args)=>{
  const node=ref(path,...args);if(path!=='')return node;
  return {...node,async update(values){
   if(!held&&Object.hasOwn(values,'matchHistory/'+owner+'/'+id)){held=true;entered();await resume;}
   return node.update(values);
  }};
 });
 const resigning=request(peer,'submitMatchAction',{matchId:id,type:'resign',actionId:'round5-legacy-held-resign',expectedSequence:0},'round5-legacy-held-resign');
 try{
  await reached;
  assert.equal((await request(owner,'deleteAccount',{confirm:true},'round5-legacy-delete-during-worker')).deleted,true);
  for(const tree of privateTrees)assert.equal(db.read(tree+'/'+owner),null);
 }finally{release();}
 await resigning;
 for(const tree of privateTrees)assert.equal(db.read(tree+'/'+owner),null,'A delayed already-running settlement must not restore '+tree);
 assert.equal(db.read('rankedState/pendingSettlementsByUser/'+owner),null);
 assert.equal(db.read('users/'+owner),null);assert.ok(db.read('users/'+peer));
 assert.ok(db.read('matchHistory/'+peer+'/'+id));
 assert.equal(db.read('rankedState/matches/'+id+'/settlementStatus'),'complete');
});
