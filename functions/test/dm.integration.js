'use strict';

const {authHost,databaseHost,functionsBase}=require('./helpers/local-emulators').requireLocalEmulators();
const assert=require('node:assert/strict');
const {deleteApp,getApps}=require('firebase-admin/app');

const namespace='luno-chess-default-rtdb';
const handler=require('../index.js')._test.handler;

async function anonymousUser(){
  const response=await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-key`,{
    method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({returnSecureToken:true}),signal:AbortSignal.timeout(15000)
  });
  const body=await response.json();
  assert.equal(response.status,200,JSON.stringify(body));
  return body;
}

async function api(path,token,body,id){
  const headers={authorization:'Bearer '+token,'content-type':'application/json','x-firebase-appcheck':'luno-emulator-app-check','x-luno-request-id':id,origin:'https://localhost'};
  if(functionsBase){
    const response=await fetch(functionsBase+path,{method:'POST',headers,body:JSON.stringify(body||{}),signal:AbortSignal.timeout(45000)});
    return {status:response.status,body:await response.json()};
  }
  const req={method:'POST',path,body:body||{},get:function(name){return headers[String(name||'').toLowerCase()]||'';}};
  let status=200,responseBody={};
  const res={set:function(){return this;},status:function(value){status=value;return this;},send:function(value){responseBody=value;return this;},json:function(value){responseBody=value;return this;}};
  let timer;
  try{
    await Promise.race([handler(req,res),new Promise(function(_,reject){timer=setTimeout(function(){reject(new Error('API timeout: '+path));},45000);})]);
  }finally{if(timer)clearTimeout(timer);}
  return {status,body:responseBody};
}

async function adminValue(path){
  const response=await fetch(`http://${databaseHost}/${path}.json?ns=${namespace}&access_token=owner`,{signal:AbortSignal.timeout(15000)});
  const body=await response.json();
  assert.equal(response.status,200,JSON.stringify(body));
  return body;
}

async function clientDb(path,token,method,value){
  const url=`http://${databaseHost}/${path}.json?ns=${namespace}`+(token?'&auth='+encodeURIComponent(token):'');
  const options={method:method||'GET',headers:{'content-type':'application/json'},signal:AbortSignal.timeout(15000)};
  if(value!==undefined)options.body=JSON.stringify(value);
  const response=await fetch(url,options);
  return {status:response.status,body:await response.json()};
}

function ok(result,label){
  assert.equal(result.status,200,label+': '+JSON.stringify(result.body));
  return result.body;
}

async function main(){
  const suffix=Date.now().toString(36),first=await anonymousUser(),second=await anonymousUser(),outsider=await anonymousUser();
  ok(await api('/createGuestPlayer',first.idToken,{username:'dm_a_'+suffix},'dm-create-a-'+suffix),'create sender');
  ok(await api('/createGuestPlayer',second.idToken,{username:'dm_b_'+suffix},'dm-create-b-'+suffix),'create recipient');
  ok(await api('/acceptLegalTerms',first.idToken,{},'dm-terms-a-'+suffix),'accept sender terms');
  ok(await api('/acceptLegalTerms',second.idToken,{},'dm-terms-b-'+suffix),'accept recipient terms');
  const preferences=ok(await api('/updatePreferences',first.idToken,{emojiLoadout:['smile']},'dm-emoji-'+suffix),'save emoji loadout');
  assert.deepEqual(preferences.state.emojiLoadout,['smile']);

  const opened=ok(await api('/openDirectMessage',first.idToken,{targetUid:second.localId},'dm-open-a-'+suffix),'open sender conversation');
  assert.match(opened.conversationId,/^[A-Za-z0-9_-]+_[A-Za-z0-9_-]+$/);
  const invalidMessages=[{},[],42,true,null,'','x'.repeat(501),'<script>'];
  for(const [index,text] of invalidMessages.entries()){
    const rejected=await api('/sendDirectMessage',first.idToken,{targetUid:second.localId,text},'dm-invalid-'+index+'-'+suffix);
    assert.equal(rejected.status,400,'invalid message '+index+': '+JSON.stringify(rejected.body));
    assert.equal(rejected.body.error,'invalid-message');
  }
  const sent=ok(await api('/sendDirectMessage',first.idToken,{targetUid:second.localId,text:'Merhaba Luno'},'dm-send-a-'+suffix),'send message');
  const stored=await adminValue(`dm/${opened.conversationId}/msgs/${sent.messageId}`);
  assert.equal(stored.text,'Merhaba Luno');
  assert.equal(await adminValue(`dmInbox/${second.localId}/${first.localId}/unread`),true);
  assert.equal(await adminValue(`dmInbox/${first.localId}/${second.localId}/unread`),false);
  const replay=ok(await api('/sendDirectMessage',first.idToken,{targetUid:second.localId,text:'Merhaba Luno'},'dm-send-a-'+suffix),'replay send');
  assert.equal(replay.messageId,sent.messageId);
  assert.equal(replay.idempotent,true);
  assert.equal(Object.keys(await adminValue(`dm/${opened.conversationId}/msgs`)).length,1);
  const throttled=await api('/sendDirectMessage',first.idToken,{targetUid:second.localId,text:'Too quick'},'dm-fast-'+suffix);
  assert.equal(throttled.status,429,JSON.stringify(throttled.body));
  assert.equal(throttled.body.error,'message-rate-limited');

  assert.equal((await clientDb(`dm/${opened.conversationId}/msgs`,second.idToken)).status,200);
  assert.equal((await clientDb(`dm/${opened.conversationId}/msgs`,outsider.idToken)).status,401);
  assert.equal((await clientDb(`dmInbox/${second.localId}`,first.idToken)).status,401);
  assert.equal((await clientDb(`dm/${opened.conversationId}/msgs/forged`,first.idToken,'PUT',{from:first.localId,text:'forged',ts:1})).status,401);
  assert.equal((await clientDb(`dmInbox/${second.localId}/${first.localId}/unread`,second.idToken,'PUT',false)).status,401);

  ok(await api('/openDirectMessage',second.idToken,{targetUid:first.localId},'dm-open-b-'+suffix),'open recipient conversation');
  assert.equal(await adminValue(`dmInbox/${second.localId}/${first.localId}/unread`),true);
  const noCursor=ok(await api('/markDirectMessageRead',second.idToken,{targetUid:first.localId,lastMessageId:null},'dm-read-null-'+suffix),'read without observed message');
  assert.equal(noCursor.marked,false);
  const read=ok(await api('/markDirectMessageRead',second.idToken,{targetUid:first.localId,lastMessageId:sent.messageId},'dm-read-b-'+suffix),'mark recipient read');
  assert.equal(read.marked,true);
  assert.equal(await adminValue(`dmInbox/${second.localId}/${first.localId}/unread`),false);

  await new Promise(resolve=>setTimeout(resolve,1300));
  const next=ok(await api('/sendDirectMessage',first.idToken,{targetUid:second.localId,text:'Second message'},'dm-send-next-'+suffix),'send newer message');
  const staleRead=ok(await api('/markDirectMessageRead',second.idToken,{targetUid:first.localId,lastMessageId:sent.messageId},'dm-stale-read-'+suffix),'acknowledge older message');
  assert.equal(staleRead.marked,false);
  assert.equal(await adminValue(`dmInbox/${second.localId}/${first.localId}/unread`),true);
  const latestRead=ok(await api('/markDirectMessageRead',second.idToken,{targetUid:first.localId,lastMessageId:next.messageId},'dm-latest-read-'+suffix),'acknowledge current message');
  assert.equal(latestRead.marked,true);
  const reply=ok(await api('/sendDirectMessage',second.idToken,{targetUid:first.localId,text:'Hello back'},'dm-reply-'+suffix),'reply');
  assert.equal(await adminValue(`dmInbox/${first.localId}/${second.localId}/messageId`),reply.messageId);
  assert.equal(await adminValue(`dmInbox/${first.localId}/${second.localId}/unread`),true);
  assert.equal(await adminValue(`dmInbox/${second.localId}/${first.localId}/unread`),false);

  ok(await api('/updateProfile',second.idToken,{dmFriendsOnly:true},'dm-friends-only-'+suffix),'restrict DM to friends');
  const restricted=await api('/openDirectMessage',first.idToken,{targetUid:second.localId},'dm-restricted-'+suffix);
  assert.equal(restricted.status,403,JSON.stringify(restricted.body));
  assert.equal(restricted.body.error,'friends-only');
  ok(await api('/sendFriendRequest',first.idToken,{targetUid:second.localId},'dm-friend-request-'+suffix),'request friendship');
  ok(await api('/respondFriendRequest',second.idToken,{fromUid:first.localId,accept:true},'dm-friend-accept-'+suffix),'accept friendship');
  ok(await api('/openDirectMessage',first.idToken,{targetUid:second.localId},'dm-friend-open-'+suffix),'friend can open restricted conversation');
  ok(await api('/blockUser',second.idToken,{targetUid:first.localId},'dm-block-'+suffix),'block sender');
  assert.equal(await adminValue(`dmInbox/${first.localId}/${second.localId}`),null);
  assert.equal(await adminValue(`dmInbox/${second.localId}/${first.localId}`),null);
  for(const path of ['/openDirectMessage','/sendDirectMessage','/markDirectMessageRead']){
    const body={targetUid:second.localId};
    if(path==='/sendDirectMessage')body.text='Blocked message';
    if(path==='/markDirectMessageRead')body.lastMessageId=reply.messageId;
    const denied=await api(path,first.idToken,body,'dm-blocked-'+path.slice(1)+'-'+suffix);
    assert.equal(denied.status,403,JSON.stringify(denied.body));
    assert.equal(denied.body.error,'user-blocked');
  }
  assert.equal(Object.keys(await adminValue(`dm/${opened.conversationId}/msgs`)).length,3);
  const leaderboard=ok(await api('/getLeaderboard',first.idToken,{mode:'collection',limit:10},'dm-collection-rank-'+suffix),'read collection leaderboard');
  assert.equal(leaderboard.mode,'collection');
  const rankedIds=new Set(leaderboard.results.map((row)=>row.uid));
  assert.equal(rankedIds.has(first.localId),true);
  assert.equal(rankedIds.has(second.localId),true);
  assert.equal(leaderboard.results.find((row)=>row.uid===first.localId).collectionScore,135);
  assert.equal(leaderboard.results.find((row)=>row.uid===second.localId).collectionScore,135);
  console.log('DM_INTEGRATION_PASS');
}

main().catch(function(error){console.error(error);process.exitCode=1;})
  .finally(async function(){await Promise.all(getApps().map(deleteApp));});
