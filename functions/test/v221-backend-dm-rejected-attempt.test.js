'use strict';

const test=require('node:test'),assert=require('node:assert/strict');
const {getDatabase}=require('firebase-admin/database');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const api=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');
const uid='v221_dm_sender',target='v221_dm_recipient',key=api.conversationId(uid,target);
const baseTime=Date.UTC(2026,9,11,12),text='not previously delivered';

function setup(t){
  let at=baseTime,sequence=0;
  t.mock.method(Date,'now',()=>at);
  t.mock.method(getAuth(),'verifyIdToken',async()=>({uid,firebase:{sign_in_provider:'anonymous'}}));
  t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
  const users={};
  for(const player of [uid,target]){
    users[player]=api.starterProfile(player,player);
    users[player].legalConsent={uid:player,acceptedAt:1,termsVersion:api.LEGAL_TERMS_VERSION,
      privacyVersion:api.LEGAL_PRIVACY_VERSION,communityVersion:api.LEGAL_COMMUNITY_VERSION};
  }
  const db=memoryDatabase(t,{users}),database=getDatabase(),ref=database.ref.bind(database);
  // Match the existing social fixture's synchronous push-key allocation.
  t.mock.method(database,'ref',(path='',...args)=>{
    const node=ref(path,...args);
    return {...node,push(value){
      if(arguments.length)return node.push(value);
      const messageId='-v221_dm_'+(++sequence);
      return {...ref(path+'/'+messageId),key:messageId};
    }};
  });
  return {...db,setTime:value=>{at=value;}};
}
async function send(id,message=text){
  const headers={authorization:'Bearer mock','x-firebase-appcheck':'mock','x-luno-request-id':id};
  let status,body;
  await api.handler({method:'POST',path:'/sendDirectMessage',body:{targetUid:target,text:message},get:name=>headers[name.toLowerCase()]||''},
    {set(){return this;},status(value){status=value;return this;},json(value){body=value;}});
  return {status,body};
}

for(const cause of ['friends-only','conversation-conflict']){
  test(cause+' rejection retains attempt throttling without suppressing the unsent text after admission',async t=>{
    const db=setup(t),foreign={members:{foreign_one:true,foreign_two:true},msgs:{kept:{from:'foreign_one',text:'preserved',ts:1}}};
    if(cause==='friends-only')db.write('users/'+target+'/dmFriendsOnly',true);
    else db.write('dm/'+key,foreign);
    const denied=await send('v221-dm-denied');
    assert.equal(denied.status,cause==='friends-only'?403:409);assert.equal(denied.body.error,cause);
    assert.equal(db.read('dmInbox'),null);
    if(cause==='friends-only'){
      assert.equal(db.read('dm/'+key),null);
      db.write('friends/'+uid+'/'+target,{addedAt:baseTime});
    }else{
      assert.deepEqual(db.read('dm/'+key),foreign);
      // Fixture-only simulation of the conflicting conversation being retired.
      db.write('dm/'+key,null);
    }
    db.setTime(baseTime+200);
    const fast=await send('v221-dm-fast-retry','another unsent text');
    assert.equal(fast.status,429);assert.equal(fast.body.error,'message-rate-limited');
    db.setTime(baseTime+2000);
    const retry=await send('v221-dm-denied');
    assert.equal(retry.status,200,JSON.stringify(retry.body));
    const messages=Object.values(db.read('dm/'+key+'/msgs'));
    assert.equal(messages.length,1);assert.equal(messages[0].text,text);
    db.setTime(baseTime+4000);
    const duplicate=await send('v221-dm-new-request-same-text');
    assert.equal(duplicate.status,429);assert.equal(duplicate.body.error,'duplicate-message');
    assert.equal(Object.keys(db.read('dm/'+key+'/msgs')).length,1);
  });
}

test('a rejected different text cannot erase or extend the prior admitted-text duplicate window',async t=>{
  const db=setup(t),first=await send('v221-dm-first');assert.equal(first.status,200);
  db.write('users/'+target+'/dmFriendsOnly',true);db.setTime(baseTime+2000);
  const rejected=await send('v221-dm-rejected-different','different unsent text');
  assert.equal(rejected.status,403);assert.equal(rejected.body.error,'friends-only');
  db.write('friends/'+uid+'/'+target,{addedAt:baseTime});db.setTime(baseTime+4000);
  const duplicate=await send('v221-dm-original-duplicate');
  assert.equal(duplicate.status,429);assert.equal(duplicate.body.error,'duplicate-message');
  db.setTime(baseTime+31000);
  assert.equal((await send('v221-dm-after-window')).status,200);
  assert.equal(Object.keys(db.read('dm/'+key+'/msgs')).length,2);
});

test('legacy cooldown rows retain their attempt and duplicate limits',async t=>{
  const db=setup(t);db.write('messageThrottle/'+uid+'/'+target,{at:baseTime,textHash:api.hash(text)});
  db.setTime(baseTime+200);
  assert.equal((await send('v221-dm-legacy-fast','different')).body.error,'message-rate-limited');
  db.setTime(baseTime+2000);
  assert.equal((await send('v221-dm-legacy-duplicate')).body.error,'duplicate-message');
  db.setTime(baseTime+31000);
  assert.equal((await send('v221-dm-legacy-expired')).status,200);
});

test('account-wide 30-per-minute request limit still rejects before any DM write',async t=>{
  const db=setup(t),bucket=Math.floor(baseTime/60000);
  db.write('serverRateLimits/'+uid+'/sendDirectMessage/'+bucket,30);
  const result=await send('v221-dm-rate-limit');
  assert.equal(result.status,429);assert.equal(result.body.error,'rate-limited');
  assert.equal(db.read('dm'),null);assert.equal(db.read('dmInbox'),null);
  assert.equal(db.read('messageThrottle'),null);
});
