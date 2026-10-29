'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {fixture}=require('./helpers/battle-v1-fixture');

for(const elapsed of [120000,120001,600000]){
 test(`expired V1 search cannot block a newly created friendly room after ${elapsed}ms`,async()=>{
  const f=fixture();await f.enable();
  const search=await f.api.enqueueBattleV1(f.context('alice',{client:f.client},'room-stale-search'));
  assert.equal(search.status,'queued');
  f.setTime(1000+elapsed);
  const room=await f.api.createBattleV1Room(f.context('alice',{client:f.client},'room-after-expired-search'));
  assert.equal(room.created,true,'Expired search must permit switching to a friendly room.');
  const joined=await f.api.joinBattleV1Room(f.context('bob',{client:f.client,roomCode:room.roomCode},'join-new-friendly-room'));
  assert.equal(joined.joined,true,'A room that was successfully created must be joinable.');
  assert.equal(joined.view.public.rated,false);
  assert.equal(f.read('battleV1Control/queue/alice'),undefined,'An expired search must not remain eligible for ranked matching.');
  assert.equal(f.read('battleV1Control/active/alice'),joined.matchId);
  assert.equal(f.read('battleV1Control/active/bob'),joined.matchId);
 });
}

test('a live V1 search still blocks room creation and is not discarded',async()=>{
 const f=fixture();await f.enable();
 await f.api.enqueueBattleV1(f.context('alice',{client:f.client},'room-live-search'));
 f.setTime(120999);
 await assert.rejects(f.api.createBattleV1Room(f.context('alice',{client:f.client},'room-during-live-search')),{code:'QUEUE_ACTIVE'});
 assert.ok(f.read('battleV1Control/queue/alice'));
 assert.equal(f.read('battleV1Control/roomByUser/alice'),undefined);
});

test('a guest with a live V1 search cannot join a friendly room',async()=>{
 const f=fixture();await f.enable();
 const room=await f.api.createBattleV1Room(f.context('alice',{client:f.client},'room-before-guest-search'));
 await f.api.enqueueBattleV1(f.context('bob',{client:f.client},'guest-live-search'));
 await assert.rejects(f.api.joinBattleV1Room(f.context('bob',{client:f.client,roomCode:room.roomCode},'guest-join-while-queued')),{code:'QUEUE_ACTIVE'});
 assert.equal(f.read('battleV1Control/rooms/'+room.roomCode).matchId,undefined);
 assert.ok(f.read('battleV1Control/queue/bob'));
});
