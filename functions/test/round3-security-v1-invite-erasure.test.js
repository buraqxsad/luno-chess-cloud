'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const {getDatabase}=require('firebase-admin/database');
const logger=require('firebase-functions/logger');
const api=require('../index')._test;
const {protocol}=require('../lib/battle-v1');
const {memoryDatabase}=require('./helpers/memory-database');
const sender='round3_invite_sender',recipient='round3_invite_recipient',other='round3_invite_other';
const client={platform:'android',build:19,protocolVersion:protocol.PROTOCOL};
function setup(t,hook,options={}){
 const users={};for(const uid of [sender,recipient,other])users[uid]=api.starterProfile(uid,uid);
 const seed={users,friends:{[sender]:{[recipient]:true},[recipient]:{[sender]:true}},
  battleRollout:{config:{...protocol.LEGACY_ONLY,configVersion:2,v1MatchmakingEnabled:true}}};
 const db=memoryDatabase(t,seed,options),database=getDatabase(),ref=database.ref.bind(database);
 db.hook=hook;
 t.mock.method(getAuth(),'verifyIdToken',async uid=>({uid,auth_time:Math.floor(Date.now()/1000),firebase:{sign_in_provider:'anonymous'}}));
 t.mock.method(getAuth(),'deleteUser',async()=>{});
 t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
 for(const level of ['info','warn','error'])t.mock.method(logger,level,()=>{});
 t.mock.method(database,'ref',(path='',...args)=>{
  const node=ref(path,...args);return {...node,
   async get(){if(db.hook)await db.hook(path,'get',db);return node.get();},
   async transaction(change,...rest){if(db.hook)await db.hook(path,'transaction',db);return node.transaction(change,...rest);},
   async set(value){if(db.hook)await db.hook(path,'set',db);return node.set(value);}
  };
 });
 return db;
}
async function request(uid,route,body,id){
 const headers={authorization:'Bearer '+uid,'x-firebase-appcheck':'local-check','x-luno-request-id':id};
 let status,value;await api.handler({method:'POST',path:'/'+route,body,get:name=>headers[name.toLowerCase()]||''},
 {set(){return this;},status(code){status=code;return this;},json(result){value=result;}});
 return {status,body:value};
}
function assertErased(db,uid){
 assert.equal(db.read('users/'+uid),null);
 assert.equal(db.read('accountDeletions/'+api.hash(uid)+'/status'),'complete');
 const invites=Object.values(db.read('battleV1Control/invites')||{});
 assert.equal(invites.some(row=>row.from.uid===uid||row.to===uid),false,'A completed erasure must leave no late private V1 invite involving its UID.');
 for(const [owner,rows] of Object.entries(db.read('matchInvites')||{})){
  assert.notEqual(owner,uid,'Erased recipient cannot gain a new match invite inbox.');
  assert.equal(Object.values(rows).some(row=>row.fromUid===uid),false,'Erased sender cannot leave a newly delivered named invite.');
 }
}
for(const erased of [sender,recipient])for(const boundary of ['control','delivery']){
 test('actual '+erased+' account deletion before late V1 invite '+boundary+' write erases all pair metadata',async t=>{
  let triggered=false;
  const db=setup(t,async(path,kind)=>{
   const hit=boundary==='control'?path==='battleV1Control'&&kind==='transaction':path==='matchInvites/'+recipient+'/'+sender&&kind==='set';
   if(!hit||triggered)return;triggered=true;
   const result=await request(erased,'deleteAccount',{confirm:true},'round3-real-delete-'+boundary+'-'+erased);
   assert.equal(result.status,200,JSON.stringify(result.body));assert.equal(result.body.deleted,true);
  });
  const result=await request(sender,'sendBattleV1Invite',{client,targetUid:recipient},'round3-late-invite-'+boundary+'-'+erased);
  assert.equal(triggered,true,'The real API reached the intended mutation boundary.');
  assertErased(db,erased);
  assert.equal(result.status,erased===sender?403:404,'No request can confirm a delivery to or from an erased account.');
  assert.ok(db.read('users/'+other),'Unrelated live account is preserved.');
 });
}
test('live mutual friends retain V1 invite delivery and idempotent pending replay',async t=>{
 const db=setup(t),body={client,targetUid:recipient};
 const first=await request(sender,'sendBattleV1Invite',body,'round3-live-invite');
 assert.equal(first.status,200,JSON.stringify(first.body));assert.equal(first.body.sent,true);
 const repeated=await request(sender,'sendBattleV1Invite',body,'round3-live-invite');
 assert.equal(repeated.status,200);assert.equal(db.read('matchInvites/'+recipient+'/'+sender+'/fromUid'),sender);
 assert.equal(Object.keys(db.read('battleV1Control/invites')).length,1);
});
test('block continues to reject V1 invitation before private or inbox writes',async t=>{
 const db=setup(t);db.write('blocks/'+recipient+'/'+sender,{createdAt:1});
 const result=await request(sender,'sendBattleV1Invite',{client,targetUid:recipient},'round3-blocked-invite');
 assert.equal(result.status,403);assert.equal(result.body.error,'user-blocked');
 assert.equal(db.read('battleV1Control/invites'),null);assert.equal(db.read('matchInvites'),null);
});
for(const erased of [sender,recipient])for(const boundary of ['control','reservation','create']){
 test('actual '+erased+' erasure during V1 invitation acceptance at '+boundary+' preserves the deletion fence',async t=>{
  // This instance just sends the seed invitation; acceptance cases model its
  // warmed control cache. Cold standalone SDK behavior has a separate probe.
  const db=setup(t,null,{cold:false});
  assert.equal((await request(sender,'sendBattleV1Invite',{client,targetUid:recipient},'round3-accept-seed')).status,200);
  let triggered=false;
  db.hook=async(path,kind)=>{
   const hit=boundary==='control'?path==='battleV1Control'&&kind==='transaction':
    boundary==='reservation'?path.startsWith('battleV1Control/reservations/')&&kind==='get':
    path.startsWith('matchSecretsV1/')&&kind==='transaction';
   if(!hit||triggered)return;triggered=true;
   const result=await request(erased,'deleteAccount',{confirm:true},'round3-real-delete-accept-'+boundary+'-'+erased);
   assert.equal(result.status,200,JSON.stringify(result.body));
  };
  const result=await request(recipient,'respondBattleV1Invite',{client,fromUid:sender,accept:true},'round3-accept-'+boundary+'-'+erased);
  assert.equal(triggered,true);
  assertErased(db,erased);
  assert.equal(db.read('battleV1Control/active/'+erased),null,'An erased account cannot remain in an active invitation match.');
  for(const value of Object.values(db.read('matchSecretsV1')||{})){
   const match=JSON.parse(value.recordJson);
   assert.equal(match.deletedParticipants?.[erased],true,'Any match already reserved by deletion must preserve its erased-participant marker.');
   assert.equal(Object.values(match.players).find(player=>player.uid===erased)?.name,'Deleted player');
  }
  if(boundary==='control')assert.equal(result.body.error,'INVITE_UNAVAILABLE');
 });
}
