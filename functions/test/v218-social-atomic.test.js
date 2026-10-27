'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const logger=require('firebase-functions/logger');
const {handler,starterProfile,conversationId,LEGAL_TERMS_VERSION,LEGAL_PRIVACY_VERSION,LEGAL_COMMUNITY_VERSION}=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');
const first='alpha1_beta22',second='gamma3',third='alpha1',fourth='beta22_gamma3';
function seed(){
 const users={};
 for(const uid of [first,second,third,fourth]){
  users[uid]=starterProfile(uid,uid);
  users[uid].legalConsent={uid,acceptedAt:1,termsVersion:LEGAL_TERMS_VERSION,privacyVersion:LEGAL_PRIVACY_VERSION,communityVersion:LEGAL_COMMUNITY_VERSION};
 }
 return {users};
}
function setup(t,data=seed(),options={}){
 const db=memoryDatabase(t,data,options);
 t.mock.method(getAuth(),'verifyIdToken',async uid=>({uid}));
 t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
 for(const level of ['info','warn','error'])t.mock.method(logger,level,()=>{});
 return db;
}
async function api(uid,route,body,id='v218-request'){
 const headers={authorization:'Bearer '+uid,'x-firebase-appcheck':'check','x-luno-request-id':id};
 let status,result;
 await handler({method:'POST',path:'/'+route,body,get:name=>headers[name.toLowerCase()]||''},
  {set(){return this;},status(value){status=value;return this;},json(value){result=value;}});
 return {status,body:result};
}
test('colliding legacy DM IDs cannot merge two different participant pairs',async t=>{
 const key=conversationId(first,second);assert.equal(key,conversationId(third,fourth));
 const data=seed();data.dm={[key]:{members:{[first]:true,[second]:true},msgs:{private:{from:first,text:'private history',ts:1}}}};
 const db=setup(t,data),before=structuredClone(db.read('dm/'+key));
 const opened=await api(third,'openDirectMessage',{targetUid:fourth});
 assert.equal(opened.status,409,JSON.stringify(opened.body));assert.equal(opened.body.error,'conversation-conflict');
 assert.deepEqual(db.read('dm/'+key),before);
});
test('a normal DM reopen preserves its messages and only its two members',async t=>{
 const key=conversationId(first,second),data=seed();data.dm={[key]:{members:{[first]:true,[second]:true},msgs:{old:{from:second,text:'kept',ts:1}}}};
 const db=setup(t,data),opened=await api(second,'openDirectMessage',{targetUid:first});
 assert.equal(opened.status,200,JSON.stringify(opened.body));assert.equal(opened.body.conversationId,key);
 assert.deepEqual(Object.keys(db.read('dm/'+key+'/members')).sort(),[first,second].sort());
 assert.equal(db.read('dm/'+key+'/msgs/old/text'),'kept');
});
test('notification read does not recreate a row deleted after its initial read',async t=>{
 const path='notifications/'+first+'/notice1',data=seed();data.notifications={[first]:{notice1:{type:'friend_request',read:false}}};
 const db=setup(t,data,{afterRead(p,n,store){if(p===path)store.write(path,null);}});
 const result=await api(first,'markNotificationRead',{notificationId:'notice1'});
 assert.equal(result.status,200,JSON.stringify(result.body));assert.equal(result.body.updated,false);assert.equal(db.read(path),null);
});
test('notification read preserves existing contents and reports a missing row',async t=>{
 const data=seed();data.notifications={[first]:{notice1:{type:'friend_request',fromUid:second,read:false}}};
 const db=setup(t,data),result=await api(first,'markNotificationRead',{notificationId:'notice1'});
 assert.equal(result.status,200);assert.equal(result.body.updated,true);assert.equal(db.read('notifications/'+first+'/notice1/fromUid'),second);
 assert.equal(db.read('notifications/'+first+'/notice1/read'),true);
 const missing=await api(first,'markNotificationRead',{notificationId:'missing'},'v218-missing');
 assert.equal(missing.status,200);assert.equal(missing.body.updated,false);assert.equal(db.read('notifications/'+first+'/missing'),null);
});
test('removing a friend clears both authoritative V1 invites without touching active matches',async t=>{
 const data=seed();data.friends={[first]:{[second]:true},[second]:{[first]:true}};
 data.battleV1Control={invites:{[first+'|'+second]:{from:{uid:first},to:second},[second+'|'+first]:{from:{uid:second},to:first},[first+'|'+third]:{from:{uid:first},to:third}},active:{[first]:'active-match'}};
 const db=setup(t,data),result=await api(first,'removeFriend',{targetUid:second});
 assert.equal(result.status,200,JSON.stringify(result.body));assert.equal(db.read('battleV1Control/invites/'+first+'|'+second),null);
 assert.equal(db.read('battleV1Control/invites/'+second+'|'+first),null);assert.ok(db.read('battleV1Control/invites/'+first+'|'+third));
 assert.equal(db.read('battleV1Control/active/'+first),'active-match');
});
test('sending a reciprocal friend request accepts the incoming request atomically',async t=>{
 const data=seed();data.friendRequests={[second]:{[first]:{fromUid:first,sentAt:1}}};
 data.outgoingFriendRequests={[first]:{[second]:{sentAt:1}}};
 const db=setup(t,data),result=await api(second,'sendFriendRequest',{targetUid:first});
 assert.equal(result.status,200,JSON.stringify(result.body));assert.equal(result.body.status,'accepted');
 assert.ok(db.read('friends/'+first+'/'+second));assert.ok(db.read('friends/'+second+'/'+first));
 for(const root of ['friendRequests','outgoingFriendRequests']){
  assert.equal(db.read(root+'/'+first+'/'+second),null);assert.equal(db.read(root+'/'+second+'/'+first),null);
 }
});
test('sending an existing outgoing friend request stays pending',async t=>{
 const data=seed();data.friendRequests={[second]:{[first]:{fromUid:first,sentAt:1}}};
 data.outgoingFriendRequests={[first]:{[second]:{sentAt:1}}};
 const db=setup(t,data),result=await api(first,'sendFriendRequest',{targetUid:second});
 assert.equal(result.status,200,JSON.stringify(result.body));assert.equal(result.body.status,'pending');
 assert.equal(db.read('friends/'+first+'/'+second),null);assert.ok(db.read('friendRequests/'+second+'/'+first));
});
