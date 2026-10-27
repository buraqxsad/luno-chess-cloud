'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {openPassChest,starterProfile,hash}=require('../index')._test;
const {rollChest,applyChestInventoryRewards}=require('../lib/chests');
const {memoryDatabase}=require('./helpers/memory-database');
const uid='entropy_player',requestId='client-chosen-request';
test('earned Pass chest uses server entropy rather than a client-searchable request seed',async t=>{
 const profile=starterProfile(uid,'entropy_player');profile.inventory.pendingChests=['rare'];
 const data={users:{[uid]:profile}},expected=applyChestInventoryRewards(structuredClone(profile),rollChest(profile,'rare',Buffer.alloc(32,7).toString('hex')));
 let draws=0;t.mock.method(crypto,'randomBytes',size=>{assert.equal(size,32);draws++;return Buffer.alloc(size,7);});
 const db=memoryDatabase(t,data),result=await openPassChest({uid,body:{chestId:'rare'},requestId});
 assert.equal(draws,1,'The server must draw an unpredictable chest seed.');
 assert.deepEqual(result.rewards,expected);assert.equal(db.read('users/'+uid+'/inventory/pendingChests').length,0);
});
test('new entropy on retry cannot reroll a durably granted Pass chest',async t=>{
 const profile=starterProfile(uid,'entropy_player');profile.inventory.pendingChests=['rare','rare'];
 let draws=0;t.mock.method(crypto,'randomBytes',size=>Buffer.alloc(size,++draws));
 const db=memoryDatabase(t,{users:{[uid]:profile}}),context={uid,body:{chestId:'rare'},requestId};
 const first=await openPassChest(context),before=structuredClone(db.read('users/'+uid));
 db.write('serverRequests/'+uid+'/'+hash(requestId).slice(0,48),null);
 const replay=await openPassChest(context);
 assert.equal(draws,2);assert.equal(replay.idempotent,true);assert.equal(replay.opened,false);
 assert.deepEqual(replay.rewards,first.rewards);assert.deepEqual(db.read('users/'+uid),before);
});
