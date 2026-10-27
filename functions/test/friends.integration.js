'use strict';

const {authHost,databaseHost}=require('./helpers/local-emulators').requireLocalEmulators();
const assert=require('node:assert/strict');
const {initializeApp,deleteApp,getApps}=require('firebase-admin/app');
const {getDatabase}=require('firebase-admin/database');

const namespace='luno-chess-default-rtdb';
const adminApp=initializeApp({projectId:'luno-chess',databaseURL:`http://${databaseHost}?ns=${namespace}`},'friends-integration-test');
const db=getDatabase(adminApp);
const handler=require('../index.js')._test.handler;

async function json(response){
  const body=await response.json().catch(function(){return {};});
  return {status:response.status,body};
}
async function anonymousUser(){
  const response=await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-key`,{
    method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({returnSecureToken:true}),signal:AbortSignal.timeout(15000)
  });
  const result=await json(response);assert.equal(result.status,200,JSON.stringify(result.body));return result.body;
}
async function api(path,token,body,id){
  const headers={authorization:'Bearer '+token,'content-type':'application/json','x-firebase-appcheck':'luno-emulator-app-check','x-luno-request-id':id,origin:'https://localhost'};
  const req={method:'POST',path,body:body||{},get:function(name){return headers[String(name||'').toLowerCase()]||'';}};
  let status=200,responseBody={};
  const res={set:function(){return this;},status:function(value){status=value;return this;},send:function(value){responseBody=value;return this;},json:function(value){responseBody=value;return this;}};
  let timer;
  try{
    await Promise.race([handler(req,res),new Promise(function(_,reject){timer=setTimeout(function(){reject(new Error('API timeout: '+path));},45000);})]);
  }finally{if(timer)clearTimeout(timer);}
  return {status,body:responseBody};
}
async function countNotifications(uid,type){
  const value=(await db.ref(`notifications/${uid}`).get()).val()||{};
  return Object.values(value).filter(function(notification){return notification&&notification.type===type;}).length;
}
async function main(){
  const first=await anonymousUser(),second=await anonymousUser();
  const firstCreated=await api('/createGuestPlayer',first.idToken,{username:'friend_flow_a'},'friends-create-a');
  const secondCreated=await api('/createGuestPlayer',second.idToken,{username:'friend_flow_b'},'friends-create-b');
  assert.equal(firstCreated.status,200,JSON.stringify(firstCreated.body));
  assert.equal(secondCreated.status,200,JSON.stringify(secondCreated.body));
  for(const [user,name] of [[first,'friend_flow_a'],[second,'friend_flow_b']]){
    const consent=await api('/acceptLegalTerms',user.idToken,{},'friends-consent-'+name);
    assert.equal(consent.status,200,JSON.stringify(consent.body));
    const chosen=await api('/changeUsername',user.idToken,{username:name},'friends-name-'+name);
    assert.equal(chosen.status,200,JSON.stringify(chosen.body));
    assert.equal(chosen.body.state.profile.usernameGenerated,false);
  }

  const sent=await api('/sendFriendRequest',first.idToken,{targetUid:second.localId},'friends-send-1');
  assert.equal(sent.status,200,JSON.stringify(sent.body));
  assert.equal(sent.body.status,'sent');
  assert.equal(await countNotifications(second.localId,'friend_request'),1);

  const duplicate=await api('/sendFriendRequest',first.idToken,{targetUid:second.localId},'friends-send-2');
  assert.equal(duplicate.status,200,JSON.stringify(duplicate.body));
  assert.equal(duplicate.body.status,'pending');
  assert.equal(await countNotifications(second.localId,'friend_request'),1);

  const invalidResponse=await api('/respondFriendRequest',second.idToken,{fromUid:first.localId,accept:'true'},'friends-accept-invalid');
  assert.equal(invalidResponse.status,400,JSON.stringify(invalidResponse.body));
  assert.equal(invalidResponse.body.error,'invalid-request-response');

  const accepted=await api('/respondFriendRequest',second.idToken,{fromUid:first.localId,accept:true},'friends-accept-1');
  assert.equal(accepted.status,200,JSON.stringify(accepted.body));
  assert.equal(accepted.body.accepted,true);
  assert.equal((await db.ref(`friends/${first.localId}/${second.localId}`).get()).exists(),true);
  assert.equal((await db.ref(`friends/${second.localId}/${first.localId}`).get()).exists(),true);
  assert.equal(await countNotifications(first.localId,'friend_accepted'),1);

  const search=await api('/searchPlayers',first.idToken,{query:'friend_flow_b'},'friends-search');
  assert.equal(search.status,200,JSON.stringify(search.body));
  assert.equal(search.body.results[0].relationship,'friends');

  const senderRoom=await api('/createFriendlyRoom',first.idToken,{durationMinutes:3},'friends-room-sender');
  assert.equal(senderRoom.status,200,JSON.stringify(senderRoom.body));
  const senderRoomInvite=await api('/sendMatchInvite',first.idToken,{targetUid:second.localId,durationMinutes:3},'friends-room-sender-invite');
  assert.equal(senderRoomInvite.status,409,JSON.stringify(senderRoomInvite.body));
  assert.equal(senderRoomInvite.body.error,'friendly-room-active');
  const senderRoomCancelled=await api('/cancelFriendlyRoom',first.idToken,{roomCode:senderRoom.body.roomCode},'friends-room-sender-cancel');
  assert.equal(senderRoomCancelled.status,200,JSON.stringify(senderRoomCancelled.body));
  assert.equal(senderRoomCancelled.body.cancelled,true);

  const targetRoom=await api('/createFriendlyRoom',second.idToken,{durationMinutes:3},'friends-room-target');
  assert.equal(targetRoom.status,200,JSON.stringify(targetRoom.body));
  const targetRoomInvite=await api('/sendMatchInvite',first.idToken,{targetUid:second.localId,durationMinutes:3},'friends-room-target-invite');
  assert.equal(targetRoomInvite.status,409,JSON.stringify(targetRoomInvite.body));
  assert.equal(targetRoomInvite.body.error,'opponent-room-active');
  const targetRoomCancelled=await api('/cancelFriendlyRoom',second.idToken,{roomCode:targetRoom.body.roomCode},'friends-room-target-cancel');
  assert.equal(targetRoomCancelled.status,200,JSON.stringify(targetRoomCancelled.body));
  assert.equal(targetRoomCancelled.body.cancelled,true);

  const invite=await api('/sendMatchInvite',first.idToken,{targetUid:second.localId,durationMinutes:3},'friends-invite-1');
  assert.equal(invite.status,200,JSON.stringify(invite.body));
  assert.equal(invite.body.sent,true);
  assert.equal(await countNotifications(second.localId,'match_invite'),1);
  const duplicateInvite=await api('/sendMatchInvite',first.idToken,{targetUid:second.localId,durationMinutes:3},'friends-invite-2');
  assert.equal(duplicateInvite.status,200,JSON.stringify(duplicateInvite.body));
  assert.equal(duplicateInvite.body.status,'pending');
  assert.equal(await countNotifications(second.localId,'match_invite'),1);

  const acceptRoom=await api('/createFriendlyRoom',second.idToken,{durationMinutes:3},'friends-room-accept');
  assert.equal(acceptRoom.status,200,JSON.stringify(acceptRoom.body));
  const blockedAccept=await api('/respondMatchInvite',second.idToken,{fromUid:first.localId,accept:true},'friends-invite-accept-room');
  assert.equal(blockedAccept.status,409,JSON.stringify(blockedAccept.body));
  assert.equal(blockedAccept.body.error,'friendly-room-active');
  const acceptRoomCancelled=await api('/cancelFriendlyRoom',second.idToken,{roomCode:acceptRoom.body.roomCode},'friends-room-accept-cancel');
  assert.equal(acceptRoomCancelled.status,200,JSON.stringify(acceptRoomCancelled.body));
  assert.equal(acceptRoomCancelled.body.cancelled,true);

  const responses=await Promise.all([
    api('/respondMatchInvite',second.idToken,{fromUid:first.localId,accept:true},'friends-invite-accept-a'),
    api('/respondMatchInvite',second.idToken,{fromUid:first.localId,accept:true},'friends-invite-accept-b')
  ]);
  const successful=responses.filter(function(result){return result.status===200&&result.body.accepted===true;});
  assert.equal(successful.length,1,JSON.stringify(responses));
  const acceptedInvite=successful[0].body;
  assert.equal(acceptedInvite.view.mode,'friendly');
  assert.equal(await countNotifications(first.localId,'match_invite_accepted'),1);

  const resigned=await api('/submitMatchAction',first.idToken,{matchId:acceptedInvite.matchId,type:'resign',actionId:'friends-resign-1',expectedSequence:0},'friends-resign-1');
  assert.equal(resigned.status,200,JSON.stringify(resigned.body));
  assert.equal(resigned.body.view.status,'finished');

  const joinRoom=await api('/createFriendlyRoom',first.idToken,{durationMinutes:5},'friends-room-join-create');
  assert.equal(joinRoom.status,200,JSON.stringify(joinRoom.body));
  const foreignCancel=await api('/cancelFriendlyRoom',second.idToken,{roomCode:joinRoom.body.roomCode},'friends-room-foreign-cancel');
  assert.equal(foreignCancel.status,403,JSON.stringify(foreignCancel.body));
  assert.equal(foreignCancel.body.error,'room-owner-required');
  const joined=await api('/joinFriendlyRoom',second.idToken,{roomCode:joinRoom.body.roomCode},'friends-room-join');
  assert.equal(joined.status,200,JSON.stringify(joined.body));
  assert.equal(joined.body.joined,true);
  assert.equal(joined.body.durationMinutes,5);
  assert.equal((await db.ref('friendlyRooms/'+joinRoom.body.roomCode).get()).exists(),false);
  assert.equal((await db.ref('friendlyRoomByUser/'+first.localId).get()).exists(),false);
  const joinedResign=await api('/submitMatchAction',second.idToken,{matchId:joined.body.matchId,type:'resign',actionId:'friends-room-resign',expectedSequence:0},'friends-room-resign');
  assert.equal(joinedResign.status,200,JSON.stringify(joinedResign.body));
  assert.equal(joinedResign.body.view.status,'finished');

  const removed=await api('/removeFriend',first.idToken,{targetUid:second.localId},'friends-remove-1');
  assert.equal(removed.status,200,JSON.stringify(removed.body));
  assert.equal(removed.body.removed,true);
  assert.equal((await db.ref(`friends/${first.localId}/${second.localId}`).get()).exists(),false);
  assert.equal((await db.ref(`friends/${second.localId}/${first.localId}`).get()).exists(),false);

  const inviteAfterRemoval=await api('/sendMatchInvite',first.idToken,{targetUid:second.localId},'friends-invite-after-remove');
  assert.equal(inviteAfterRemoval.status,403,JSON.stringify(inviteAfterRemoval.body));
  assert.equal(inviteAfterRemoval.body.error,'friend-required');
  console.log('FRIENDS_INTEGRATION_PASS');
}

main().catch(function(error){console.error(error);process.exitCode=1;})
  .finally(async function(){await Promise.all(getApps().map(deleteApp));});
