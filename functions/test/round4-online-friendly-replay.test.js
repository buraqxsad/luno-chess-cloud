'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const logger=require('firebase-functions/logger');
const api=require('../index')._test;
const {protocol}=require('../lib/battle-v1');
const {memoryDatabase}=require('./helpers/memory-database');
const host='round4_friendly_host',first='round4_friendly_first',third='round4_friendly_third';
const client={platform:'android',build:19,protocolVersion:protocol.PROTOCOL};
function setup(t,options={}){
 let at=Date.UTC(2026,10,2,12);t.mock.method(Date,'now',()=>at);
 const users={};for(const uid of [host,first,third])users[uid]=api.starterProfile(uid,uid);
 const db=memoryDatabase(t,{users,friends:{[host]:{[first]:true,[third]:true},[first]:{[host]:true},[third]:{[host]:true}},battleRollout:{config:{...protocol.LEGACY_ONLY,configVersion:2,v1MatchmakingEnabled:true}}},options);
 t.mock.method(getAuth(),'verifyIdToken',async uid=>({uid,auth_time:Math.floor(at/1000),firebase:{sign_in_provider:'anonymous'}}));
 t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
 for(const level of ['info','warn','error'])t.mock.method(logger,level,()=>{});
 return {...db,advance:ms=>{at+=ms;}};
}
async function request(uid,route,body,id){
 const headers={authorization:'Bearer '+uid,'x-firebase-appcheck':'local-round4-attestation','x-luno-request-id':id};
 let status,value;await api.handler({method:'POST',path:'/'+route,body,get:name=>headers[name.toLowerCase()]||''},{set(){return this;},status(code){status=code;return this;},json(result){value=result;}});return {status,body:value};
}
async function finish(matchId){
 const ended=await request(first,'resignBattleV1',{matchId,protocolVersion:protocol.PROTOCOL,expectedStateVersion:0,actionId:'a0_round4-friendly-resign'},'round4-friendly-first-resign');assert.equal(ended.status,200,JSON.stringify(ended));assert.equal(ended.body.status,'finished');
}
async function oldRoom(){
 const room=await request(host,'createBattleV1Room',{client},'round4-room-original');assert.equal(room.status,200,JSON.stringify(room));
 const joined=await request(first,'joinBattleV1Room',{client,roomCode:room.body.roomCode},'round4-first-room-join');assert.equal(joined.status,200,JSON.stringify(joined));await finish(joined.body.matchId);return joined.body.matchId;
}
async function assertThirdRecovery(db,details){
 const recovery=[];
 recovery.push(await request(third,'getBattleV1',{matchId:'',protocolVersion:protocol.PROTOCOL},'round4-third-recovery-get'));
 recovery.push(await request(third,'cancelBattleV1Queue',{protocolVersion:protocol.PROTOCOL},'round4-third-recovery-cancel'));
 recovery.push(await request(third,'enqueueBattleV1',{client},'round4-third-recovery-enqueue'));
 assert.ok(recovery.some(r=>r.status===200),'A third player must retain a get/cancel/enqueue recovery path: '+JSON.stringify({details,recovery,active:db.read('battleV1Control/active/'+third)}));
 const id=db.read('battleV1Control/active/'+third);
 if(id){const match=api.battleV1.hydrate(db.read('matchSecretsV1/'+id));assert.ok(Object.values(match.players).some(p=>p.uid===third),'An active mapping must identify a canonical participant.');}
}
test('a fresh room after its previous room lease and result can admit a different guest',async t=>{
 const db=setup(t),oldId=await oldRoom();db.advance(120001);
 const room=await request(host,'createBattleV1Room',{client},'round4-room-fresh');assert.equal(room.status,200,JSON.stringify(room));
 const joined=await request(third,'joinBattleV1Room',{client,roomCode:room.body.roomCode},'round4-fresh-third-room-join');assert.equal(joined.status,200,JSON.stringify(joined));assert.notEqual(joined.body.matchId,oldId);assert.equal(joined.body.status,'active');
 await assertThirdRecovery(db,{room,joined});
});
test('a delayed create-room replay after lease expiry cannot strand its new guest against the old canonical match',async t=>{
 const db=setup(t),oldId=await oldRoom();db.advance(120001);
 const replay=await request(host,'createBattleV1Room',{client},'round4-room-original');
 let joined=null;
 if(replay.status===200){assert.equal(replay.body.created,true);joined=await request(third,'joinBattleV1Room',{client,roomCode:replay.body.roomCode},'round4-replayed-third-room-join');}
 else assert.equal(replay.status,409,JSON.stringify(replay));
 assert.equal(joined.status,200,JSON.stringify(joined));
 assert.notEqual(joined.body.matchId,oldId);assert.equal(joined.body.status,'active');
 await assertThirdRecovery(db,{oldId,replay,joined});
});
test('pending room and invitation retries preserve their original lease and canonical admission',async t=>{
 const db=setup(t);
 const room=await request(host,'createBattleV1Room',{client},'round4-room-pending');assert.equal(room.status,200,JSON.stringify(room));
 assert.deepEqual(await request(host,'createBattleV1Room',{client},'round4-room-pending'),room);
 assert.equal((await request(host,'cancelBattleV1Room',{roomCode:room.body.roomCode,protocolVersion:protocol.PROTOCOL},'round4-pending-room-cancel')).status,200);
 const sent=await request(host,'sendBattleV1Invite',{client,targetUid:first},'round4-pending-invite');assert.equal(sent.status,200,JSON.stringify(sent));
 assert.deepEqual(await request(host,'sendBattleV1Invite',{client,targetUid:first},'round4-pending-invite'),sent);
 const one=await request(first,'respondBattleV1Invite',{client,fromUid:host,accept:true},'round4-pending-invite-accept');assert.equal(one.status,200,JSON.stringify(one));
 const two=await request(first,'respondBattleV1Invite',{client,fromUid:host,accept:true},'round4-pending-invite-accept');assert.equal(two.status,200,JSON.stringify(two));assert.equal(two.body.matchId,one.body.matchId);assert.equal(Object.keys(db.read('matchSecretsV1')).length,1);
});
test('a reused invitation request ID for a later friend cannot strand that friend in a conflicting canonical reservation',async t=>{
 const db=setup(t);
 assert.equal((await request(host,'sendBattleV1Invite',{client,targetUid:first},'round4-original-invite')).status,200);
 const original=await request(first,'respondBattleV1Invite',{client,fromUid:host,accept:true},'round4-original-invite-accept');assert.equal(original.status,200,JSON.stringify(original));await finish(original.body.matchId);
 const sent=await request(host,'sendBattleV1Invite',{client,targetUid:third},'round4-original-invite');
 let accepted=null;
 if(sent.status===200)accepted=await request(third,'respondBattleV1Invite',{client,fromUid:host,accept:true},'round4-third-invite-accept');else assert.equal(sent.status,409,JSON.stringify(sent));
 assert.equal(accepted.status,200,JSON.stringify(accepted));assert.notEqual(accepted.body.matchId,original.body.matchId);assert.equal(accepted.body.status,'active');
 await assertThirdRecovery(db,{oldId:original.body.matchId,sent,accepted});
});


test('legacy room without a lease nonce retains its original canonical ID',async t=>{
 const db=setup(t),room=await request(host,'createBattleV1Room',{client},'round4-legacy-room');
 const path='battleV1Control/rooms/'+room.body.roomCode,row=db.read(path);delete row.matchNonce;db.write(path,row);
 const joined=await request(first,'joinBattleV1Room',{client,roomCode:room.body.roomCode},'round4-legacy-room-join');
 assert.equal(joined.status,200,JSON.stringify(joined));assert.equal(joined.body.matchId,api.battleV1.matchId(host,'round4-legacy-room|room'));
 const repeated=await request(first,'joinBattleV1Room',{client,roomCode:room.body.roomCode},'round4-legacy-room-join-again');
 assert.equal(repeated.status,200);assert.equal(repeated.body.matchId,joined.body.matchId);assert.equal(Object.keys(db.read('matchSecretsV1')).length,1);
});
test('legacy invitation without a lease nonce retains its original canonical ID',async t=>{
 const db=setup(t);assert.equal((await request(host,'sendBattleV1Invite',{client,targetUid:first},'round4-legacy-invite')).status,200);
 const path='battleV1Control/invites/'+host+'|'+first,row=db.read(path);delete row.matchNonce;db.write(path,row);
 const accepted=await request(first,'respondBattleV1Invite',{client,fromUid:host,accept:true},'round4-legacy-invite-accept');
 assert.equal(accepted.status,200,JSON.stringify(accepted));assert.equal(accepted.body.matchId,api.battleV1.matchId(host,'round4-legacy-invite|invite'));
});
test('a room join honors an already persisted legacy canonical ID when nonce metadata also exists',async t=>{
 const db=setup(t),room=await request(host,'createBattleV1Room',{client},'round4-mixed-room');
 const path='battleV1Control/rooms/'+room.body.roomCode,row=db.read(path),guest=await api.battleV1.entry(first,client),legacyId=api.battleV1.matchId(host,row.requestId+'|room');
 await api.battleV1.create(legacyId,row.host.player,guest.player,row.host.deck,guest.deck,false);
 row.matchId=legacyId;row.guestUid=first;db.write(path,row);db.write('battleV1Control/active',{[host]:legacyId,[first]:legacyId});
 const joined=await request(first,'joinBattleV1Room',{client,roomCode:room.body.roomCode},'round4-mixed-room-join');
 assert.equal(joined.status,200,JSON.stringify(joined));assert.equal(joined.body.matchId,legacyId);assert.equal(Object.keys(db.read('matchSecretsV1')).length,1);
});
test('a stale room snapshot cannot reserve against a replacement lease with identical code and createdAt',async t=>{
 let replaced=false;
 const db=setup(t,{afterRead(path,count,ops){
  if(!path.startsWith('battleV1Control/rooms/')||count!==1||replaced)return;
  replaced=true;const row=ops.read(path);ops.write(path,{...row,matchNonce:require('node:crypto').randomUUID(),requestId:'round4-replacement-room'});
 }});
 const room=await request(host,'createBattleV1Room',{client},'round4-original-room-snapshot');
 const joined=await request(first,'joinBattleV1Room',{client,roomCode:room.body.roomCode},'round4-stale-room-join');
 assert.equal(replaced,true);assert.equal(joined.status,404);assert.equal(joined.body.error,'ROOM_UNAVAILABLE');
 assert.deepEqual(Object.keys(db.read('battleV1Control/active')||{}),[]);assert.equal(db.read('matchSecretsV1'),null);
 assert.equal(db.read('battleV1Control/rooms/'+room.body.roomCode+'/requestId'),'round4-replacement-room');
});

test('an already stranded legacy room reservation retains a recovery path after backend upgrade',async t=>{
 const db=setup(t),requestId='round4-legacy-stranded-room';
 const old=await request(host,'createBattleV1Room',{client},requestId),oldPath='battleV1Control/rooms/'+old.body.roomCode;
 const firstRow=db.read(oldPath);delete firstRow.matchNonce;db.write(oldPath,firstRow);
 const original=await request(first,'joinBattleV1Room',{client,roomCode:old.body.roomCode},'round4-stranded-room-original-join');assert.equal(original.status,200);await finish(original.body.matchId);
 const canonicalBefore=db.read('matchSecretsV1/'+original.body.matchId);db.advance(120001);
 const fresh=await request(host,'createBattleV1Room',{client},requestId),path='battleV1Control/rooms/'+fresh.body.roomCode;
 const legacy=db.read(path);delete legacy.matchNonce;db.write(path,legacy);
 const joined=await request(third,'joinBattleV1Room',{client,roomCode:fresh.body.roomCode},'round4-stranded-room-third-join');
 await assertThirdRecovery(db,{original,fresh,joined});
 assert.deepEqual(db.read('matchSecretsV1/'+original.body.matchId),canonicalBefore,'Retiring a bad reservation cannot mutate the prior canonical match.');
});
test('an already stranded legacy invitation reservation retains a recovery path after backend upgrade',async t=>{
 const db=setup(t),requestId='round4-legacy-stranded-invite';
 assert.equal((await request(host,'sendBattleV1Invite',{client,targetUid:first},requestId)).status,200);
 const oldPath='battleV1Control/invites/'+host+'|'+first,old=db.read(oldPath);delete old.matchNonce;db.write(oldPath,old);
 const original=await request(first,'respondBattleV1Invite',{client,fromUid:host,accept:true},'round4-stranded-invite-first');assert.equal(original.status,200);await finish(original.body.matchId);
 const canonicalBefore=db.read('matchSecretsV1/'+original.body.matchId);
 assert.equal((await request(host,'sendBattleV1Invite',{client,targetUid:third},requestId)).status,200);
 const path='battleV1Control/invites/'+host+'|'+third,legacy=db.read(path);delete legacy.matchNonce;db.write(path,legacy);
 const accepted=await request(third,'respondBattleV1Invite',{client,fromUid:host,accept:true},'round4-stranded-invite-third');
 await assertThirdRecovery(db,{original,accepted});
 assert.deepEqual(db.read('matchSecretsV1/'+original.body.matchId),canonicalBefore);
});

async function conflictingLegacyReservation(db,id,{rated=false}={}){
 const own=await api.battleV1.entry(host,client),peer=await api.battleV1.entry(third,client);
 const reservation={w:own,b:peer,rated};db.write('battleV1Control/reservations/'+id,reservation);
 db.write('battleV1Control/active/'+host,id);db.write('battleV1Control/active/'+third,id);return reservation;
}
test('legacy conflict recovery never removes a newer reservation owner',async t=>{
 const db=setup(t),id=await oldRoom();await conflictingLegacyReservation(db,id);
 const create=api.battleV1.create.bind(api.battleV1);let changed=false,replacement;
 t.mock.method(api.battleV1,'create',async(...args)=>{
  try{return await create(...args);}
  catch(error){
   if(!changed){changed=true;const captured=db.read('battleV1Control/reservations/'+id);replacement={...captured,reservationToken:require('node:crypto').randomUUID(),requestUid:third};db.write('battleV1Control/reservations/'+id,replacement);}
   throw error;
  }
 });
 await api.battleV1.completeReservation(id);
 assert.equal(changed,true);assert.deepEqual(db.read('battleV1Control/reservations/'+id),replacement);
 assert.equal(db.read('battleV1Control/active/'+third),id);
});
test('legacy conflict recovery preserves legitimate active participants of the canonical match',async t=>{
 const db=setup(t),room=await request(host,'createBattleV1Room',{client},'round4-live-canonical');
 const joined=await request(first,'joinBattleV1Room',{client,roomCode:room.body.roomCode},'round4-live-canonical-first');assert.equal(joined.status,200);
 const id=joined.body.matchId,canonicalBefore=db.read('matchSecretsV1/'+id);await conflictingLegacyReservation(db,id);
 await api.battleV1.completeReservation(id);
 assert.equal(db.read('battleV1Control/active/'+host),id);assert.equal(db.read('battleV1Control/active/'+first),id);
 assert.equal(db.read('battleV1Control/active/'+third),null);assert.equal(db.read('battleV1Control/reservations/'+id),null);
 assert.deepEqual(db.read('matchSecretsV1/'+id),canonicalBefore);assert.equal(db.read('battleV1Control/queue/'+third),null,'Friendly recovery cannot silently enqueue ranked play.');
});
test('legacy ranked conflict restores the unrelated waiting peer without rewriting a canonical result',async t=>{
 const db=setup(t),id=await oldRoom(),canonicalBefore=db.read('matchSecretsV1/'+id),reservation=await conflictingLegacyReservation(db,id,{rated:true});
 await api.battleV1.completeReservation(id);
 assert.equal(db.read('battleV1Control/active/'+third),null);assert.equal(db.read('battleV1Control/reservations/'+id),null);
 const queued=db.read('battleV1Control/queue/'+third);assert.equal(queued.uid,third);assert.deepEqual(queued.deck,reservation.b.deck);assert.equal(queued.joinedAt,reservation.b.joinedAt);
 assert.deepEqual(db.read('matchSecretsV1/'+id),canonicalBefore);
 assert.equal((await request(third,'cancelBattleV1Queue',{protocolVersion:protocol.PROTOCOL},'round4-recovered-queue-cancel')).status,200);
 assert.equal(db.read('battleV1Control/queue/'+third),null);
});
