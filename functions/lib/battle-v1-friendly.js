'use strict';
const crypto=require('node:crypto');
const {protocol}=require('./battle-v1');
const {PROTOCOL,BattleError,requireRecord,exactKeys,validUid}=protocol;
const TTL=120000,ALPHABET='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
function installBattleV1Friendly(api,deps){
 const {db,now}=api;
 const roomCode=()=>Array.from({length:6},()=>ALPHABET[crypto.randomInt(ALPHABET.length)]).join('');
 function state(value){const v={...value,queue:value?.queue||{},active:value?.active||{},reservations:value?.reservations||{},rooms:value?.rooms||{},roomByUser:value?.roomByUser||{},invites:value?.invites||{}};for(const [code,r] of Object.entries(v.rooms))if(r.expiresAt<=now()){delete v.rooms[code];if(v.roomByUser[r.host.uid]===code)delete v.roomByUser[r.host.uid];}for(const [key,i] of Object.entries(v.invites))if(i.expiresAt<=now())delete v.invites[key];return v;}
 function available(v,uid){
  if(v.active[uid])throw new BattleError('MATCH_ALREADY_ACTIVE');
  if(v.queue[uid]&&now()-v.queue[uid].lastSeenAt<TTL)throw new BattleError('QUEUE_ACTIVE');
  const room=v.rooms[v.roomByUser[uid]];if(room&&room.expiresAt>now()&&!room.matchId)throw new BattleError('ROOM_ACTIVE');
 }
 async function transact(change){let error;const tx=await db.ref('battleV1Control').transaction(value=>{error=null;try{return change(state(value));}catch(e){error=e;return;}},undefined,false);if(!tx.committed){throw error||new BattleError('TEMPORARILY_UNAVAILABLE',503);}return tx.snapshot.val();}
 async function prepare(context,required){const b=requireRecord(context.body);exactKeys(b,['client',...required]);await api.admission(b);await deps.requirePlayer(context.uid);await deps.rateLimit(context.uid,'battleV1Friendly',20,60000);if(deps.resolveLegacyForV1)await deps.resolveLegacyForV1(context.uid);return b;}
 async function createBattleV1Room(context){
  await prepare(context,[]);const owner=await api.entry(context.uid,context.body.client),code=roomCode(),at=now();
  const v=await transact(v=>{const previous=v.rooms[v.roomByUser[context.uid]];if(previous?.requestId===context.requestId&&previous.expiresAt>at)return v;available(v,context.uid);if(v.rooms[code]?.expiresAt>at)throw new BattleError('ROOM_CODE_CONFLICT');v.rooms[code]={code,host:owner,createdAt:at,expiresAt:at+TTL,requestId:context.requestId};v.roomByUser[context.uid]=code;return v;});
  const room=v.rooms[v.roomByUser[context.uid]];return {ok:true,created:true,roomCode:room.code,durationMinutes:5,expiresAt:room.expiresAt,protocolVersion:PROTOCOL};
 }
 async function cancelBattleV1Room(context){
  const b=requireRecord(context.body);exactKeys(b,['roomCode','protocolVersion']);if(b.protocolVersion!==PROTOCOL||typeof b.roomCode!=='string')throw new BattleError('INVALID_ACTION',400);await deps.requirePlayer(context.uid);await deps.rateLimit(context.uid,'cancelBattleV1Room',20,60000);
  let cancelled=false;await transact(v=>{cancelled=false;const r=v.rooms[b.roomCode];if(!r)return v;if(r.host.uid!==context.uid)throw new BattleError('NOT_ROOM_OWNER',403);if(r.matchId)throw new BattleError('MATCH_ALREADY_ACTIVE');delete v.rooms[b.roomCode];if(v.roomByUser[context.uid]===b.roomCode)delete v.roomByUser[context.uid];cancelled=true;return v;});return {ok:true,cancelled};
 }
 async function joinBattleV1Room(context){
  const b=await prepare(context,['roomCode']);if(typeof b.roomCode!=='string'||!/^[A-Z0-9]{6}$/.test(b.roomCode))throw new BattleError('INVALID_ROOM_CODE',400);
  const first=(await db.ref('battleV1Control/rooms/'+b.roomCode).get()).val();if(!first||first.host.uid===context.uid||first.expiresAt<=now())throw new BattleError('ROOM_UNAVAILABLE',404);
  return deps.withSocialPairLock(context.uid,first.host.uid,async()=>{
  await deps.assertInteractionAllowed(context.uid,first.host.uid);
  const guest=await api.entry(context.uid,b.client),id=api.matchId(first.host.uid,first.requestId+'|room');
  const v=await transact(v=>{const r=v.rooms[b.roomCode];if(!r||r.host.uid!==first.host.uid||r.createdAt!==first.createdAt||r.expiresAt<=now())throw new BattleError('ROOM_UNAVAILABLE',404);if(r.matchId){if(r.guestUid!==context.uid)throw new BattleError('ROOM_FULL');return v;}available(v,context.uid);if(v.active[r.host.uid]||v.queue[r.host.uid])throw new BattleError('OPPONENT_BUSY');v.reservations[id]={w:r.host,b:guest,rated:false};v.active[r.host.uid]=id;v.active[context.uid]=id;r.matchId=id;r.guestUid=context.uid;return v;});
  const match=await api.completeReservation(id)||await api.load(id,context.uid);return {...api.snapshot(match,context.uid),joined:true,durationMinutes:5};
  });
 }
 async function sendBattleV1Invite(context){
  const b=await prepare(context,['targetUid']);if(!validUid(b.targetUid)||b.targetUid===context.uid)throw new BattleError('INVALID_PLAYER',400);
  return deps.withSocialPairLock(context.uid,b.targetUid,async()=>{
  await deps.assertInteractionAllowed(context.uid,b.targetUid);await deps.requireFriendship(context.uid,b.targetUid);
  const from=await api.entry(context.uid,b.client),at=now(),key=context.uid+'|'+b.targetUid;
  const v=await transact(v=>{available(v,context.uid);available(v,b.targetUid);const previous=v.invites[key];if(previous&&previous.expiresAt>at)return v;v.invites[key]={from,to:b.targetUid,requestId:context.requestId,expiresAt:at+TTL};return v;});
  const invite=v.invites[key],safe={fromUid:context.uid,fromUsername:from.player.name,fromName:from.player.name,expiresAt:invite.expiresAt,sentAt:at,status:'pending',durationMinutes:5,protocolVersion:PROTOCOL};
  await db.ref('matchInvites/'+b.targetUid+'/'+context.uid).set(safe);return {ok:true,sent:true,status:'pending',expiresAt:invite.expiresAt};
  });
 }
 async function respondBattleV1Invite(context){
  const b=await prepare(context,['fromUid','accept']);if(!validUid(b.fromUid)||b.fromUid===context.uid||typeof b.accept!=='boolean')throw new BattleError('INVALID_ACTION',400);
  return deps.withSocialPairLock(context.uid,b.fromUid,async()=>{
  const key=b.fromUid+'|'+context.uid;await deps.assertInteractionAllowed(context.uid,b.fromUid);await deps.requireFriendship(context.uid,b.fromUid);
  const guest=await api.entry(context.uid,b.client);let id=null;
  const v=await transact(v=>{id=null;const invite=v.invites[key];if(!invite||invite.expiresAt<=now())throw new BattleError('INVITE_UNAVAILABLE',404);if(!b.accept){delete v.invites[key];return v;}if(invite.matchId){id=invite.matchId;return v;}available(v,context.uid);available(v,b.fromUid);id=api.matchId(b.fromUid,invite.requestId+'|invite');v.reservations[id]={w:invite.from,b:guest,rated:false};v.active[b.fromUid]=id;v.active[context.uid]=id;invite.matchId=id;return v;});
  await db.ref('matchInvites/'+context.uid+'/'+b.fromUid).remove();if(!b.accept)return {ok:true,accepted:false};
  const match=await api.completeReservation(id)||await api.load(id,context.uid);return {...api.snapshot(match,context.uid),accepted:true,durationMinutes:5};
  });
 }
 async function leaveAccount(uid){
  const id=(await db.ref('battleV1Control/active/'+uid).get()).val()||(await db.ref('battleV1Control/lastMatch/'+uid).get()).val();
  if(id){await api.completeReservation(id);const tx=await api.transact(id,uid,m=>({match:require('./battle-v1').authority.finishMatch(m,{reason:'account-deleted',winner:protocol.sideForUid(m,uid)==='w'?'b':'w',finishedAt:now()})}));await api.settle(tx.match.matchId,uid);const deleted=await api.transact(id,uid,m=>{m.deletedParticipants={...m.deletedParticipants,[uid]:true};m.players[protocol.sideForUid(m,uid)].name='Deleted player';m.stateVersion++;return {match:m};});await api.publish(deleted.match);}
  await transact(v=>{delete v.queue[uid];delete v.active[uid];if(v.lastMatch)delete v.lastMatch[uid];for(const [code,r] of Object.entries(v.rooms))if(r.host.uid===uid||r.guestUid===uid)delete v.rooms[code];delete v.roomByUser[uid];for(const [key,i] of Object.entries(v.invites))if(i.from.uid===uid||i.to===uid)delete v.invites[key];return v;});
  if(id)await db.ref('matchEmotesV1/'+id).remove();
 }
 Object.assign(api,{createBattleV1Room,cancelBattleV1Room,joinBattleV1Room,sendBattleV1Invite,respondBattleV1Invite,leaveAccount});return api;
}
module.exports={installBattleV1Friendly};
