'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const api=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');
const {applyV1Rating}=require('../lib/battle-v1-rating');
const {PRODUCT_PROGRESS_FIELD,projectBattleV1ProductProgress}=require('../lib/battle-v1-product-progress');
const uid='player01',at=Date.parse('2026-10-10T12:00:00Z');
const current=api.periodSnapshot(at).seasonNumber;
function fixture(season=current){
 const settledAt=api.seasonBounds(season).startAt+1000;
 const profile=api.starterProfile(uid,'player_one');
 profile.trophies=9000;profile.arenaIdx=8;
 profile.serverSeason={number:season,seasonId:'s'+season,peakTrophies:9000,startedAt:settledAt,claimed:{}};
 profile.serverProgress={battleProtocol:'LUNO_BATTLE_V1'};
 const account={migrationVersion:1,rating:600,ratingRevision:0,games:0};
 const match={protocolVersion:'LUNO_BATTLE_V1',matchId:'settled_match',rated:true,
  players:{w:{uid,bot:false},b:{uid:'player02',bot:false}},
  result:{reason:'resign',winner:'w',finishedAt:settledAt},battle:{rules:{ply:12}},
  metrics:{'player:w:moveCount':6,'player:b:moveCount':6},ratingAtStart:{w:600,b:600}};
 applyV1Rating(account,match,uid);account.ratingRevision=1;
 projectBattleV1ProductProgress(profile,account,match.matchId,at);
 return {profile,account};
}
function setup(t,profile,account){
 t.mock.method(Date,'now',()=>at);
 t.mock.method(getAuth(),'verifyIdToken',async()=>({uid}));
 t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
 return memoryDatabase(t,{users:{[uid]:profile},battleV1Accounts:{[uid]:{accountJson:JSON.stringify(account)}}});
}
async function request(route,body={},id='v218-product-request'){
 const headers={authorization:'Bearer token','x-firebase-appcheck':'check','x-luno-request-id':id};
 let status,result;
 await api.handler({method:'POST',path:'/'+route,body,get:key=>headers[key.toLowerCase()]||''},
  {set(){return this;},status(value){status=value;return this;},json(value){result=value;}});
 return {status,body:result};
}
test('product schedules use the receipt-backed V1 rank, not legacy trophy values',()=>{
 const {profile,account}=fixture(),schedule=api.rewardSchedule(profile,at);
 assert.equal(api.seasonState(profile,at).score,account.rating);
 assert.equal(api.achievementValue(profile,'arenaIdx',at,{}),profile[PRODUCT_PROGRESS_FIELD].arenaIdx+1);
 assert.equal(schedule.missions.special.find(row=>row.id==='s1').progress,1);
 assert.equal(profile.trophies,9000);
});
test('season path claim pays the real V1 tier once and rejects a legacy-only tier',async t=>{
 const {profile,account}=fixture(),db=setup(t,profile,account),gold=profile.gold;
 const claimed=await request('claimSeasonPathReward',{tierId:'path_4'});
 assert.equal(claimed.status,200,JSON.stringify(claimed.body));assert.equal(claimed.body.granted,true);
 assert.equal(db.read('users/'+uid+'/gold'),gold+api.SEASON_PATH_REWARDS.find(row=>row.id==='path_4').reward.gold);
 assert.equal(claimed.body.state.season.path.find(row=>row.id==='path_4').state,'claimed');
 const replay=await request('claimSeasonPathReward',{tierId:'path_4'},'v218-path-replay');
 assert.equal(replay.status,200);assert.equal(replay.body.granted,false);
 const locked=await request('claimSeasonPathReward',{tierId:'path_5'},'v218-path-locked');
 assert.equal(locked.status,409);assert.equal(locked.body.error,'season-tier-locked');
 assert.equal(db.read('users/'+uid+'/trophies'),9000);
});
test('V1 arena mission and achievement claims agree with their advertised progress',async t=>{
 const {profile,account}=fixture(),db=setup(t,profile,account);
 const mission=await request('claimMissionReward',{category:'special',missionId:'s1'});
 assert.equal(mission.status,200,JSON.stringify(mission.body));assert.equal(mission.body.granted,true);
 const achievement=await request('claimAchievementReward',{achievementId:'arena_3'},'v218-achievement');
 assert.equal(achievement.status,200,JSON.stringify(achievement.body));assert.equal(achievement.body.granted,true);
 const locked=await request('claimAchievementReward',{achievementId:'arena_5'},'v218-achievement-locked');
 assert.equal(locked.status,409);assert.equal(locked.body.error,'achievement-not-complete');
 assert.equal(db.read('users/'+uid+'/trophies'),9000);
});
test('V1 season end advances the reward cursor without resetting either rank store',async t=>{
 const {profile,account}=fixture(current-1),db=setup(t,profile,account),before=structuredClone(profile.serverSeason);
 const claimed=await request('claimSeasonReward');
 assert.equal(claimed.status,200,JSON.stringify(claimed.body));assert.equal(claimed.body.granted,true);
 assert.equal(claimed.body.state.season.seasonNumber,current);
 assert.equal(db.read('users/'+uid+'/'+PRODUCT_PROGRESS_FIELD+'/rewardSeasonNumber'),current);
 assert.deepEqual(db.read('users/'+uid+'/serverSeason'),before);
 assert.equal(db.read('users/'+uid+'/trophies'),9000);
 assert.equal(JSON.parse(db.read('battleV1Accounts/'+uid+'/accountJson')).rating,account.rating);
 const balance=db.read('users/'+uid+'/gold');
 const replay=await request('claimSeasonReward',{},'v218-season-replay');
 assert.equal(replay.status,200);assert.equal(replay.body.granted,false);assert.equal(replay.body.idempotent,true);
 assert.equal(db.read('users/'+uid+'/gold'),balance);
});
test('a shared legacy end-reward receipt repairs the V1 cursor without a second payment',async t=>{
 const {profile,account}=fixture(current-1);
 api.applyRewardClaim(profile,{uid,sourceType:'season_reward',sourceId:'s'+(current-1),reward:api.SEASON_REWARDS[0].reward,at});
 const db=setup(t,profile,account),gold=profile.gold,gems=profile.gems;
 const result=await request('claimSeasonReward');
 assert.equal(result.status,200,JSON.stringify(result.body));assert.equal(result.body.granted,false);
 assert.equal(result.body.idempotent,true);assert.equal(result.body.tier,'Bronze');
 assert.equal(db.read('users/'+uid+'/gold'),gold);assert.equal(db.read('users/'+uid+'/gems'),gems);
 assert.equal(db.read('users/'+uid+'/'+PRODUCT_PROGRESS_FIELD+'/rewardSeasonNumber'),current);
});
test('an older V1 account backfills from committed receipts without changing legacy rank',async t=>{
 const {profile,account}=fixture();delete profile[PRODUCT_PROGRESS_FIELD];
 const db=setup(t,profile,account);
 const repaired=await api.repairBattleV1ProductProgress(uid,profile,at);
 assert.equal(repaired[PRODUCT_PROGRESS_FIELD].trophies,account.rating);
 assert.equal(repaired.trophies,9000);assert.equal(db.read('users/'+uid+'/'+PRODUCT_PROGRESS_FIELD+'/ratingRevision'),1);
 const writes=db.writes.length;
 assert.equal(await api.repairBattleV1ProductProgress(uid,repaired,at),repaired);
 assert.equal(db.writes.length,writes);
});
test('the player-state route repairs older V1 product eligibility before returning schedules',async t=>{
 const {profile,account}=fixture();delete profile[PRODUCT_PROGRESS_FIELD];setup(t,profile,account);
 const result=await request('getPlayerState');
 assert.equal(result.status,200,JSON.stringify(result.body));
 assert.equal(result.body.state.battleV1Rank.trophies,account.rating);
 assert.equal(result.body.state.season.score,account.rating);
 assert.equal(result.body.state.rewards.missions.special.find(row=>row.id==='s1').progress,1);
});
for(const malformed of ['null','[]','{"ratingSettlements":[]}']){
 test('malformed account backfill fails closed with a defined service error: '+malformed,async t=>{
  const {profile,account}=fixture();delete profile[PRODUCT_PROGRESS_FIELD];
  const db=setup(t,profile,account);db.write('battleV1Accounts/'+uid+'/accountJson',malformed);
  const before=structuredClone(db.read('users/'+uid));
  await assert.rejects(api.repairBattleV1ProductProgress(uid,profile,at),{code:'battle-v1-product-progress-unavailable',status:503});
  assert.deepEqual(db.read('users/'+uid),before);
 });
}
test('cancelled-only V1 accounts cannot unlock products through unrelated legacy rank',async t=>{
 const {profile,account}=fixture();delete profile[PRODUCT_PROGRESS_FIELD];
 account.ratingSettlements.settled_match.outcome='cancelled';setup(t,profile,account);
 const repaired=await api.repairBattleV1ProductProgress(uid,profile,at);
 assert.equal(repaired[PRODUCT_PROGRESS_FIELD],undefined);assert.equal(api.seasonState(repaired,at).score,0);
 assert.equal(api.missionProgress(repaired,'special','all','s1',api.MISSION_CATALOG.special.s1,at),0);
 assert.equal(api.achievementValue(repaired,'arenaIdx',at,{}),1);
});
