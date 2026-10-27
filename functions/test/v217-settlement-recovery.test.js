'use strict';

const test=require('node:test'),assert=require('node:assert/strict');
const {fixture}=require('./helpers/battle-v1-fixture');
const {authority}=require('../lib/battle-v1');
const {seasonBounds}=require('../lib/economy');
const {syncPassState}=require('../lib/pass');

test('late V1 settlement preserves a newer purchased Pass and still rewards the match exactly once',async()=>{
  const f=fixture(),rollover=seasonBounds(7).startAt;
  f.setTime(rollover-1000);await f.enable();
  await f.api.enqueueBattleV1(f.context('alice',{client:f.client},'v217-late-a'));
  const queued=await f.api.enqueueBattleV1(f.context('bob',{client:f.client},'v217-late-b'));
  await f.api.transact(queued.matchId,'alice',m=>({match:authority.finishMatch(m,{reason:'resign',winner:'w',finishedAt:rollover-1})}));
  f.setTime(rollover+1000);
  const profile=f.read('users/alice'),pass=syncPassState(profile,rollover+1000).pass;
  Object.assign(pass,{premium:true,premiumSource:'soft_purchase',level:12,xp:41,unlocks:['emoji:laugh'],claimed:{free:{2:rollover+10},premium:{2:rollover+11}}});
  profile.productEntitlementVersion=2;
  f.write('users/alice',profile);
  const expected=structuredClone(pass),goldBefore=profile.gold;
  const settled=await f.api.settle(queued.matchId,'alice');
  assert.equal(settled.settlementStatus,'complete');
  assert.deepEqual(f.read('users/alice/passState'),expected);
  const rewarded=f.read('users/alice');
  assert.ok(rewarded.gold>goldBefore);
  assert.equal((rewarded.stats.wins||0)+(rewarded.stats.losses||0),1);
  await f.api.settle(queued.matchId,'bob');
  assert.deepEqual(f.read('users/alice'),rewarded);
});
