'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {starterProfile,periodSnapshot,applyDailyRewardClaim,applyRewardClaim,
  applyRankedSettlement,rewardSchedule}=require('../index.js')._test;
const DAY=86400000;

test('UTC day and Monday week change at the exact millisecond',function(){
  for(const iso of ['2026-08-10T00:00:00Z','2027-01-04T00:00:00Z']){
    const at=Date.parse(iso),before=periodSnapshot(at-1),after=periodSnapshot(at);
    assert.notEqual(before.dayKey,after.dayKey);
    assert.notEqual(before.weekKey,after.weekKey);
    assert.equal(periodSnapshot(at+DAY-1).weekKey,after.weekKey);
  }
  const newYear=Date.parse('2027-01-01T00:00:00Z');
  assert.notEqual(periodSnapshot(newYear-1).dayKey,periodSnapshot(newYear).dayKey);
  assert.equal(periodSnapshot(newYear-1).weekKey,periodSnapshot(newYear).weekKey);
});

test('daily claims at midnight grant once per day and reject old-day replay',function(){
  const uid='boundary-daily',profile=starterProfile(uid,'boundary_daily');
  const at=Date.parse('2026-08-10T00:00:00Z');
  assert.equal(applyDailyRewardClaim(profile,uid,at-1).granted,true);
  assert.equal(applyDailyRewardClaim(profile,uid,at).granted,true);
  const balance=profile.gold;
  for(const time of [at,at+1,at-1,at-DAY]){
    assert.equal(applyDailyRewardClaim(profile,uid,time).granted,false);
  }
  assert.equal(profile.gold,balance);
  assert.equal(profile.inventory.dailyStreak,2);
});

test('daily rewards cycle after seven days without duplicate credits',function(){
  const uid='cycle-daily',profile=starterProfile(uid,'cycle_daily');
  const start=Date.parse('2026-08-01T00:00:00Z'),initial=profile.gold;
  const amounts=[200,300,450,600,800,1000,1500,200];
  amounts.forEach(function(amount,index){
    const at=start+index*DAY;
    assert.deepEqual(applyDailyRewardClaim(profile,uid,at).reward,{gold:amount});
    assert.equal(applyDailyRewardClaim(profile,uid,at+DAY-1).granted,false);
  });
  assert.equal(profile.gold,initial+amounts.reduce((sum,value)=>sum+value,0));
  assert.equal(profile.inventory.dailyStreak,8);
});

test('mission counters reset daily but retain the weekly progress until Monday',function(){
  const profile=starterProfile('boundary-missions','boundary_missions');
  const sunday=Date.parse('2026-08-09T00:00:00Z');
  function win(at,id){applyRankedSettlement(profile,{
    uid:profile.uid,matchId:id,outcome:'win',opponentTrophies:0,metrics:{},at,
  });}
  function progress(at,category,id){return rewardSchedule(profile,at).missions[category].find(row=>row.id===id).progress;}
  win(sunday-1,'boundary-saturday');
  assert.equal(progress(sunday-1,'daily','d1'),1);
  assert.equal(progress(sunday,'daily','d1'),0);
  assert.equal(progress(sunday,'weekly','w1'),1);
  win(sunday,'boundary-sunday');
  assert.equal(progress(sunday,'daily','d1'),1);
  assert.equal(progress(sunday,'weekly','w1'),2);
  const monday=sunday+DAY;
  assert.equal(progress(monday,'daily','d1'),0);
  assert.equal(progress(monday,'weekly','w1'),0);
  win(monday,'boundary-monday');
  assert.equal(progress(monday,'weekly','w1'),1);
});

test('mission claim keys isolate periods while rejecting repeated source credits',function(){
  const uid='boundary-ledger',profile=starterProfile(uid,'boundary_ledger');
  const start=Date.parse('2026-08-09T12:00:00Z'),initial=profile.gold;
  for(const at of [start,start+DAY]){
    const sourceId=['daily',periodSnapshot(at).dayKey,'d1'].join(':');
    for(let retry=0;retry<100;retry++){
      const result=applyRewardClaim(profile,{uid,sourceType:'mission_reward',sourceId,reward:{gold:150},at:at+retry});
      assert.equal(result.granted,retry===0);
    }
  }
  assert.equal(profile.gold,initial+300);
});
