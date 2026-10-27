'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const {getDatabase}=require('firebase-admin/database');
const logger=require('firebase-functions/logger');
const {handler,starterProfile,conversationId,LEGAL_TERMS_VERSION,LEGAL_PRIVACY_VERSION,LEGAL_COMMUNITY_VERSION}=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');
const {fixture}=require('./helpers/battle-v1-fixture');
const first='safety_first',second='safety_second',other='safety_other';
function seed(){
 const users={};
 for(const uid of [first,second,other]){
  users[uid]=starterProfile(uid,uid);
  users[uid].legalConsent={uid,acceptedAt:1,termsVersion:LEGAL_TERMS_VERSION,privacyVersion:LEGAL_PRIVACY_VERSION,communityVersion:LEGAL_COMMUNITY_VERSION};
 }
 return {users,friends:{[first]:{[second]:true},[second]:{[first]:true}}};
}
function setup(t,data=seed()){
 const db=memoryDatabase(t,data);
 t.mock.method(getAuth(),'verifyIdToken',async token=>({uid:token}));
 t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
 for(const level of ['info','warn','error'])t.mock.method(logger,level,()=>{});
 return db;
}
async function api(uid,path,body,id='v214-request'){
 const headers={authorization:'Bearer '+uid,'x-firebase-appcheck':'check','x-luno-request-id':id,origin:'https://localhost'};
 let status,result;
 await handler({method:'POST',path:'/'+path,body,get:name=>headers[name.toLowerCase()]||''},
  {set(){return this;},status(value){status=value;return this;},json(value){result=value;}});
 return {status,body:result};
}
test('deleted blocked target remains removable without recreating its account',async t=>{
 const data=seed();delete data.users[second];
 data.blocks={[first]:{[second]:{at:1}}};data.blockedBy={[second]:{[first]:true}};
 const db=setup(t,data),result=await api(first,'unblockUser',{targetUid:second});
 assert.equal(result.status,200,JSON.stringify(result.body));
 assert.equal(result.body.blocked,false);
 assert.equal(db.read(`blocks/${first}/${second}`),null);
 assert.equal(db.read(`blockedBy/${second}/${first}`),null);
 assert.equal(db.read(`users/${second}`),null);
});
test('block removes both V1 invite directions but not unrelated invitations or active matches',async t=>{
 const data=seed();data.battleV1Control={
  invites:{[first+'|'+second]:{from:{uid:first},to:second},[second+'|'+first]:{from:{uid:second},to:first},[first+'|'+other]:{from:{uid:first},to:other}},
  active:{[first]:'existing_match'},
 };
 const db=setup(t,data),result=await api(first,'blockUser',{targetUid:second});
 assert.equal(result.status,200,JSON.stringify(result.body));
 assert.equal(db.read('battleV1Control/invites/'+first+'|'+second),null);
 assert.equal(db.read('battleV1Control/invites/'+second+'|'+first),null);
 assert.ok(db.read('battleV1Control/invites/'+first+'|'+other));
 assert.equal(db.read('battleV1Control/active/'+first),'existing_match');
});
test('block and in-flight DM serialize; block cannot be followed by revived inbox',async t=>{
 const db=setup(t),original=getDatabase().ref.bind(getDatabase());
 let enter,release;const entered=new Promise(resolve=>enter=resolve),pause=new Promise(resolve=>release=resolve);
 t.mock.method(getDatabase(),'ref',path=>{
  const ref=original(path);
  if(path===`friends/${first}/${second}`){const get=ref.get;ref.get=async()=>{enter();await pause;return get();};}
  return ref;
 });
 const sending=api(first,'sendDirectMessage',{targetUid:second,text:'Serialized message'},'v214-send');
 await entered;
 let completed=false;const blocking=api(second,'blockUser',{targetUid:first},'v214-block').then(result=>{completed=true;return result;});
 let completedWhilePaused;
 try{
  for(let i=0;i<10;i++)await new Promise(resolve=>setImmediate(resolve));
  completedWhilePaused=completed;
 }finally{release();}
 const [sent,blocked]=await Promise.all([sending,blocking]);
 assert.equal(completedWhilePaused,false,'Block completed while the DM pair operation was still in flight');
 assert.equal(sent.status,200,JSON.stringify(sent.body));assert.equal(blocked.status,200,JSON.stringify(blocked.body));
 assert.equal(db.read(`dmInbox/${first}/${second}`),null);assert.equal(db.read(`dmInbox/${second}/${first}`),null);
 assert.ok(db.read(`blocks/${second}/${first}`));
 const rejected=await api(first,'sendDirectMessage',{targetUid:second,text:'Cannot bypass block'},'v214-send-blocked');
 assert.equal(rejected.status,403);assert.equal(rejected.body.error,'user-blocked');
});
test('blocked list uses actual results contract and includes missing-account placeholder',async t=>{
 const data=seed();data.blocks={[first]:{[second]:true,[other]:true}};
 data.publicProfiles={[second]:{username:second}};
 setup(t,data);const result=await api(first,'listBlockedUsers',{});
 assert.equal(result.status,200);assert.equal(result.body.results.length,2);assert.equal(result.body.users,undefined);
 const missing=result.body.results.find(row=>row.uid===other);assert.equal(missing.name,'Silinmiş oyuncu');
 assert.equal(missing.username,'');
});
for(const [messageId,from,expected] of [['received',second,200],['own',first,404],['foreign',other,404],['missing',null,404]]){
 test(`report message ${messageId} resolves only the server's actual received message`,async t=>{
  const data=seed(),key=conversationId(first,second);
  data.dm={[key]:{msgs:from?{[messageId]:{from,text:'Server snapshot',ts:1}}:{}}};
  const db=setup(t,data),result=await api(first,'reportMessage',{targetUid:second,messageId,reason:'harassment'});
  assert.equal(result.status,expected,JSON.stringify(result.body));
  const reports=Object.values(db.read('moderationReports')||{});
  assert.equal(reports.length,expected===200?1:0);
  if(expected===200){assert.equal(reports[0].messageText,'Server snapshot');assert.equal(result.body.messageText,undefined);}
 });
}
test('client cannot attach forged message text to a moderation report',async t=>{
 const db=setup(t),result=await api(first,'reportMessage',{targetUid:second,messageId:'received',reason:'spam',text:'forged'});
 assert.equal(result.status,400);assert.equal(result.body.error,'unexpected-field');assert.equal(db.read('moderationReports'),null);
});
test('reports are private and subject to rate limits',async t=>{
 const db=setup(t);
 for(let i=0;i<8;i++){
  const result=await api(first,'reportUser',{targetUid:second,reason:'spam'},'v214-report-'+i);
  assert.equal(result.status,200,JSON.stringify(result.body));
  assert.deepEqual(Object.keys(result.body).sort(),['ok','reportId','reported']);
 }
 const limited=await api(first,'reportUser',{targetUid:second,reason:'spam'},'v214-report-extra');
 assert.equal(limited.status,429);assert.equal(Object.keys(db.read('moderationReports')).length,8);
});
test('replayed moderation request creates exactly one queue record',async t=>{
 const db=setup(t),body={targetUid:second,reason:'spam'};
 const firstResult=await api(first,'reportUser',body,'v214-replay');
 const replay=await api(first,'reportUser',body,'v214-replay');
 assert.equal(firstResult.status,200);assert.equal(replay.status,200);
 assert.equal(firstResult.body.reportId,replay.body.reportId);
 assert.equal(replay.body.idempotent,true);
 assert.equal(Object.keys(db.read('moderationReports')).length,1);
});
for(const mode of ['room','send-invite','accept-invite']){
 test(`V1 ${mode} waits for pair lock and rechecks a concurrent block`,async()=>{
  const f=fixture();await f.enable();let room;
  if(mode==='room')room=await f.api.createBattleV1Room(f.context('alice',{client:f.client}));
  if(mode==='accept-invite')await f.api.sendBattleV1Invite(f.context('alice',{client:f.client,targetUid:'bob'},'before-block'));
  let enter,release;const entered=new Promise(resolve=>enter=resolve),pause=new Promise(resolve=>release=resolve);
  const blocking=f.withSocialPairLock('alice','bob',async()=>{enter();await pause;f.write('blocks/alice/bob',true);});
  await entered;
  let settled=false;
  const operation=(mode==='room'
   ?f.api.joinBattleV1Room(f.context('bob',{client:f.client,roomCode:room.roomCode}))
   :mode==='send-invite'
    ?f.api.sendBattleV1Invite(f.context('bob',{client:f.client,targetUid:'alice'}))
    :f.api.respondBattleV1Invite(f.context('bob',{client:f.client,fromUid:'alice',accept:true})))
   .then(value=>({value}),error=>({error})).finally(()=>{settled=true;});
  for(let i=0;i<4;i++)await new Promise(resolve=>setImmediate(resolve));
  const completedBeforeBlock=settled;release();await blocking;
  const result=await operation;
  assert.equal(completedBeforeBlock,false);assert.equal(result.error?.code,'user-blocked');
  assert.equal(f.read('battleV1Control/active/bob'),undefined);
  assert.equal(f.read('matchInvites/alice/bob'),undefined);
 });
}
