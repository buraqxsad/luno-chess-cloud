'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {fixture}=require('./helpers/battle-v1-fixture');
test('V1 room retry is stable, join consumes it once and uses no legacy match state',async()=>{
 const f=fixture();await f.enable();const c=f.context('alice',{client:f.client},'room-a'),room=await f.api.createBattleV1Room(c);assert.deepEqual(await f.api.createBattleV1Room(c),room);
 await assert.rejects(f.api.cancelBattleV1Room(f.context('bob',{roomCode:room.roomCode,protocolVersion:f.client.protocolVersion})),{code:'NOT_ROOM_OWNER'});
 const body={client:f.client,roomCode:room.roomCode},match=await f.api.joinBattleV1Room(f.context('bob',body));const again=await f.api.joinBattleV1Room(f.context('bob',body));assert.equal(again.matchId,match.matchId);assert.equal(match.view.public.rated,false);
 await assert.rejects(f.api.joinBattleV1Room(f.context('attacker',body)),{code:'ROOM_FULL'});assert.equal(f.read('rankedState'),undefined);
});
test('V1 invite acceptance is idempotent and rejects another account',async()=>{
 const f=fixture();await f.enable();await f.api.sendBattleV1Invite(f.context('alice',{client:f.client,targetUid:'bob'},'invite-a'));
 await assert.rejects(f.api.respondBattleV1Invite(f.context('attacker',{client:f.client,fromUid:'alice',accept:true})),{code:'INVITE_UNAVAILABLE'});
 const c=f.context('bob',{client:f.client,fromUid:'alice',accept:true}),a=await f.api.respondBattleV1Invite(c),b=await f.api.respondBattleV1Invite(c);assert.equal(a.matchId,b.matchId);assert.equal(a.view.public.protocolVersion,f.client.protocolVersion);assert.equal(f.read('matchInvites/bob/alice'),undefined);
});
test('expired room cannot create a match or bypass active/queued match guards',async()=>{
 const f=fixture();await f.enable();const r=await f.api.createBattleV1Room(f.context('alice',{client:f.client}));f.setTime(121001);await assert.rejects(f.api.joinBattleV1Room(f.context('bob',{client:f.client,roomCode:r.roomCode})),{code:'ROOM_UNAVAILABLE'});
 await f.api.enqueueBattleV1(f.context('bob',{client:f.client}));await assert.rejects(f.api.createBattleV1Room(f.context('bob',{client:f.client})),{code:'QUEUE_ACTIVE'});
});
