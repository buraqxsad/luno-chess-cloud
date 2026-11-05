'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const {getDatabase}=require('firebase-admin/database');
const logger=require('firebase-functions/logger');
const api=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');

const sender='round5_inviter',recipient='round5_invitee',other='round5_unrelated';
function setup(t){
  const users={};
  for(const [i,uid] of [sender,recipient,other].entries()){
    users[uid]=api.starterProfile(uid,'round5_user_'+i);
    users[uid].legalConsent={uid,acceptedAt:1,termsVersion:api.LEGAL_TERMS_VERSION,
      privacyVersion:api.LEGAL_PRIVACY_VERSION,communityVersion:api.LEGAL_COMMUNITY_VERSION};
  }
  const db=memoryDatabase(t,{users});
  t.mock.method(getAuth(),'verifyIdToken',async uid=>({uid,auth_time:Math.floor(Date.now()/1000),firebase:{sign_in_provider:'anonymous'}}));
  t.mock.method(getAuth(),'deleteUser',async()=>{});
  t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
  for(const level of ['info','warn','error'])t.mock.method(logger,level,()=>{});
  const original=getDatabase().ref.bind(getDatabase());let keys=0;
  t.mock.method(getDatabase(),'ref',(path='',...args)=>{
    const node=original(path,...args);
    return {...node,push(value){
      if(arguments.length)return node.push(value);
      const key='-round5notice'+String(++keys).padStart(8,'0');
      return {...original([path,key].filter(Boolean).join('/')),key};
    }};
  });
  return db;
}
async function request(uid,route,body,id){
  const headers={authorization:'Bearer '+uid,'x-firebase-appcheck':'local-app-check','x-luno-request-id':id};
  let status,value;
  await api.handler({method:'POST',path:'/'+route,body,get:name=>headers[name.toLowerCase()]||''},
    {set(){return this;},status(code){status=code;return this;},json(result){value=result;}});
  return {status,body:value};
}
async function befriend(){
  const sent=await request(sender,'sendFriendRequest',{targetUid:recipient},'round5-friend-request');
  assert.equal(sent.status,200,JSON.stringify(sent.body));
  const accepted=await request(recipient,'respondFriendRequest',{fromUid:sender,accept:true},'round5-friend-accept');
  assert.equal(accepted.status,200,JSON.stringify(accepted.body));
}
for(const erased of [sender,recipient])test('legacy invitation held until completed '+(erased===sender?'sender':'recipient')+' erasure cannot restore relationship metadata',async t=>{
  const db=setup(t);await befriend();
  let enter,release,held=false;
  const entered=new Promise(resolve=>{enter=resolve;}),resume=new Promise(resolve=>{release=resolve;});
  const original=getDatabase().ref.bind(getDatabase());
  t.mock.method(getDatabase(),'ref',(path='',...args)=>{
    const node=original(path,...args);
    return {...node,async update(values){
      if(!held&&path===''&&values['matchInvites/'+recipient+'/'+sender]?.status==='pending'){
        held=true;enter();await resume;
      }
      return node.update(values);
    }};
  });
  const sending=request(sender,'sendMatchInvite',{targetUid:recipient,durationMinutes:5},'round5-delayed-legacy-invite');
  let deletion;
  try{
    await entered;
    deletion=await request(erased,'deleteAccount',{confirm:true},'round5-erase-invite-owner');
    assert.equal(deletion.status,200,JSON.stringify(deletion.body));
    assert.equal(deletion.body.deleted,true);
    assert.equal(db.read('users/'+erased),null);
    assert.equal(db.read('matchInvites/'+recipient+'/'+sender),null,'Completed cleanup has removed the invitation before release.');
  }finally{release();}
  const result=await sending;
  t.diagnostic(JSON.stringify({erased:erased===sender?'sender':'recipient',sendStatus:result.status,sendError:result.body.error||null,
    inviteRestored:db.read('matchInvites/'+recipient+'/'+sender)!==null,
    noticeCount:Object.values(db.read('notifications/'+recipient)||{}).filter(notice=>notice.type==='match_invite').length}));
  assert.equal(result.status,erased===sender?403:404,'Late send must reject the erased participant.');
  assert.equal(db.read('matchInvites/'+recipient+'/'+sender),null,'Late send must not resurrect the erased relationship.');
  assert.equal(Object.values(db.read('notifications/'+recipient)||{}).some(notice=>notice.type==='match_invite'),false,'Late send must not leave an authored invitation notice.');
  assert.ok(db.read('users/'+other));
});
test('healthy legacy invitation still sends one live invite and notification',async t=>{
  const db=setup(t);await befriend();
  const result=await request(sender,'sendMatchInvite',{targetUid:recipient,durationMinutes:5},'round5-live-legacy-invite');
  assert.equal(result.status,200,JSON.stringify(result.body));assert.equal(result.body.sent,true);
  assert.equal(db.read('matchInvites/'+recipient+'/'+sender+'/durationMinutes'),5);
  assert.equal(Object.values(db.read('notifications/'+recipient)||{}).filter(notice=>notice.type==='match_invite').length,1);
});
test('blocked legacy invitation still rejects without delivery',async t=>{
  const db=setup(t);await befriend();
  const blocked=await request(recipient,'blockUser',{targetUid:sender},'round5-block-legacy-inviter');
  assert.equal(blocked.status,200,JSON.stringify(blocked.body));
  const result=await request(sender,'sendMatchInvite',{targetUid:recipient,durationMinutes:5},'round5-blocked-legacy-invite');
  assert.equal(result.status,403);assert.equal(result.body.error,'user-blocked');
  assert.equal(db.read('matchInvites/'+recipient+'/'+sender),null);
});
