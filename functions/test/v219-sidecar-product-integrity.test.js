'use strict';

const test=require('node:test'),assert=require('node:assert/strict');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const logger=require('firebase-functions/logger');
const api=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');
const {fixture}=require('./helpers/battle-v1-fixture');
const {authority}=require('../lib/battle-v1');
const {applyV1Rating}=require('../lib/battle-v1-rating');
const {normalizeProductEntitlements,LEGACY_PASS_COSTUMES}=require('../lib/membership');
const {syncPassState}=require('../lib/pass');
const {PRODUCT_PROGRESS_FIELD,projectBattleV1ProductProgress,readBattleV1ProductProgress}=require('../lib/battle-v1-product-progress');
const uid='v219_product',current=6,at=api.seasonBounds(current).startAt+20*86400000;

function setup(t,profile,account){
  t.mock.method(Date,'now',()=>at);
  t.mock.method(getAuth(),'verifyIdToken',async()=>({uid}));
  t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
  for(const level of ['info','warn','error'])t.mock.method(logger,level,()=>{});
  return memoryDatabase(t,{users:{[uid]:profile},...(account?{battleV1Accounts:{[uid]:{accountJson:JSON.stringify(account)}}}:{})});
}
async function request(route,body={},id='v219-product-request'){
  const headers={authorization:'Bearer token','x-firebase-appcheck':'check','x-luno-request-id':id};
  let status,result;
  await api.handler({method:'POST',path:'/'+route,body,get:key=>headers[key.toLowerCase()]||''},
    {set(){return this;},status(value){status=value;return this;},json(value){result=value;}});
  return {status,body:result};
}

for(const shape of ['ownership-map','numeric-map','array']){
  test('legacy premium migration preserves '+shape+' cosmetics without changing progression or membership',()=>{
    const p=api.starterProfile(uid,'v219_product');delete p.productEntitlementVersion;
    p.passState={seasonKey:'ranked-s6-v2',season:6,premium:true,premiumSource:'subscription',level:12,xp:41,claimed:{premium:{2:at}}};
    const lists={ownedFrames:['rainbow','galaxy'],ownedBioFrames:['galaxy','aurora'],ownedCostumes:['k_dragon']};
    for(const [field,ids] of Object.entries(lists))p.inventory[field]=shape==='array'?ids:
      shape==='ownership-map'?Object.fromEntries(ids.map(id=>[id,true])):Object.fromEntries(ids.map((id,i)=>[i*3,id]));
    const before=structuredClone(p);
    assert.equal(normalizeProductEntitlements(p),true);
    for(const [field,ids] of Object.entries(lists))for(const id of ids)assert.ok(p.inventory[field].includes(id),field+' '+id);
    for(const id of LEGACY_PASS_COSTUMES)assert.ok(p.inventory.ownedCostumes.includes(id));
    for(const key of ['gold','gems','trophies','xp','lvl','premiumUntil'])assert.deepEqual(p[key],before[key]);
    for(const key of ['level','xp','claimed','seasonKey'])assert.deepEqual(p.passState[key],before.passState[key]);
    const migrated=structuredClone(p);assert.equal(normalizeProductEntitlements(p),false);assert.deepEqual(p,migrated);
  });
}
test('player-state refresh persists legacy map ownership instead of erasing an earned frame',async t=>{
  const p=api.starterProfile(uid,'v219_product');delete p.productEntitlementVersion;
  Object.assign(syncPassState(p,at).pass,{premium:true,level:3});delete p.productEntitlementVersion;
  p.inventory.ownedFrames={rainbow:true};p.inventory.ownedBioFrames={galaxy:true};
  const db=setup(t,p),result=await request('getPlayerState');
  assert.equal(result.status,200,JSON.stringify(result.body));
  assert.ok(db.read('users/'+uid+'/inventory/ownedFrames').includes('rainbow'));
  assert.ok(db.read('users/'+uid+'/inventory/ownedBioFrames').includes('galaxy'));
  assert.ok(result.body.state.inventory.ownedFrames.includes('rainbow'));
});

for(const category of ['daily','weekly']){
  test('old V1 settlement completes with a full '+category+' mission retention window and pays once',async()=>{
    const f=fixture(),finishedAt=api.seasonBounds(4).startAt+1000,recoveredAt=at;
    f.setTime(finishedAt);await f.enable();
    await f.api.enqueueBattleV1(f.context('alice',{client:f.client},'v219-old-a-'+category));
    const queued=await f.api.enqueueBattleV1(f.context('bob',{client:f.client},'v219-old-b-'+category));
    await f.api.transact(queued.matchId,'alice',m=>({match:authority.finishMatch(m,{reason:'resign',winner:'w',finishedAt})}));
    f.setTime(recoveredAt);
    const profile=f.read('users/alice');profile.serverProgress={missions:{[category]:{}}};
    const count=category==='daily'?14:8,step=category==='daily'?86400000:7*86400000;
    for(let i=0;i<count;i++){
      const period=api.periodSnapshot(recoveredAt-i*step),key=category==='daily'?period.dayKey:period.weekKey;
      profile.serverProgress.missions[category][key]={selected:['preserved'],counters:{existing:i+1}};
    }
    Object.assign(syncPassState(profile,recoveredAt).pass,{premium:true,premiumSource:'soft_purchase',level:12,xp:41});
    profile.productEntitlementVersion=2;
    const pass=structuredClone(profile.passState),periods=structuredClone(profile.serverProgress.missions[category]);
    f.write('users/alice',profile);
    const result=await f.api.settle(queued.matchId,'alice');
    assert.equal(result.settlementStatus,'complete');
    const paid=structuredClone(f.read('users/alice'));assert.ok(paid.gold>profile.gold);
    assert.equal((paid.stats.wins||0)+(paid.stats.losses||0),1);
    assert.deepEqual(paid.passState,pass);assert.deepEqual(paid.serverProgress.missions[category],periods);
    await f.api.settle(queued.matchId,'bob');assert.deepEqual(f.read('users/alice'),paid);
  });
}

function seasonFixture(numbers){
  const profile=api.starterProfile(uid,'v219_product');profile.trophies=9000;profile.arenaIdx=8;
  profile.serverProgress={battleProtocol:'LUNO_BATTLE_V1'};
  const account={migrationVersion:1,rating:600,ratingRevision:0,games:0};
  for(const number of numbers){
    const match={protocolVersion:'LUNO_BATTLE_V1',matchId:'v219-season-'+number,rated:true,
      players:{w:{uid,bot:false},b:{uid:'other',bot:false}},result:{reason:'resign',winner:'w',finishedAt:api.seasonBounds(number).startAt+1000},
      battle:{rules:{ply:12}},metrics:{'player:w:moveCount':6,'player:b:moveCount':6},ratingAtStart:{w:account.rating,b:account.rating}};
    applyV1Rating(account,match,uid);account.ratingRevision++;
    projectBattleV1ProductProgress(profile,account,match.matchId,at);
  }
  return {profile,account};
}
test('season claims visit every recorded outstanding season without resetting rank or inventing gap rewards',async t=>{
  const {profile,account}=seasonFixture([2,4,5]);
  const db=setup(t,profile,account),rank=structuredClone(profile[PRODUCT_PROGRESS_FIELD]),legacy=profile.trophies;
  for(const [number,next] of [[2,4],[4,5],[5,6]]){
    const result=await request('claimSeasonReward',{},'v219-season-claim-'+number);
    assert.equal(result.status,200,JSON.stringify(result.body));assert.equal(result.body.granted,true);
    const progress=db.read('users/'+uid+'/'+PRODUCT_PROGRESS_FIELD);
    assert.equal(progress.lastRewardSeason,number);assert.equal(progress.rewardSeasonNumber,next);
    assert.equal(progress.trophies,rank.trophies);assert.equal(progress.ratingRevision,rank.ratingRevision);
    assert.equal(db.read('users/'+uid+'/trophies'),legacy);
    assert.ok(readBattleV1ProductProgress(db.read('users/'+uid),at));
  }
  assert.equal(db.read('users/'+uid+'/serverEconomy/claims/'+api.sourceClaimKey(uid,'season_reward','s3')),null);
  const paid=structuredClone(db.read('users/'+uid));
  const replay=await request('claimSeasonReward',{},'v219-season-finished-replay');
  assert.equal(replay.status,200);assert.equal(replay.body.granted,false);assert.deepEqual(db.read('users/'+uid),paid);
  assert.deepEqual(JSON.parse(db.read('battleV1Accounts/'+uid+'/accountJson')),account);
});
test('a shared legacy payment advances just one historical season without paying it twice',async t=>{
  const {profile,account}=seasonFixture([4,5]);
  api.applyRewardClaim(profile,{uid,sourceType:'season_reward',sourceId:'s4',reward:api.SEASON_REWARDS[0].reward,at});
  const db=setup(t,profile,account),gold=profile.gold,gems=profile.gems;
  const result=await request('claimSeasonReward',{},'v219-paid-legacy-season');
  assert.equal(result.status,200);assert.equal(result.body.granted,false);assert.equal(result.body.idempotent,true);
  assert.equal(db.read('users/'+uid+'/'+PRODUCT_PROGRESS_FIELD+'/rewardSeasonNumber'),5);
  assert.equal(db.read('users/'+uid+'/gold'),gold);assert.equal(db.read('users/'+uid+'/gems'),gems);
  const next=await request('claimSeasonReward',{},'v219-next-earned-season');
  assert.equal(next.status,200);assert.equal(next.body.granted,true);
  assert.equal(db.read('users/'+uid+'/'+PRODUCT_PROGRESS_FIELD+'/rewardSeasonNumber'),6);
});

test('an already-skipped legitimate cursor repairs unpaid recorded seasons without replaying prior payment',async t=>{
  const {profile,account}=seasonFixture([2,4,5]),progress=profile[PRODUCT_PROGRESS_FIELD];
  const tier=api.SEASON_REWARDS.filter(tier=>progress.seasons.s2.peakTrophies>=tier.minTrophies).at(-1);
  api.applyRewardClaim(profile,{uid,sourceType:'season_reward',sourceId:'s2',reward:tier.reward,at});
  Object.assign(progress,{seasonNumber:6,rewardSeasonNumber:6,lastRewardSeason:2,lastRewardTier:tier.tier});
  progress.seasons.s6={number:6,seasonId:'s6',peakTrophies:0,startedAt:api.seasonBounds(6).startAt};
  const db=setup(t,profile,account),rank=progress.trophies,revision=progress.ratingRevision,paidClaim=structuredClone(profile.serverEconomy.claims[api.sourceClaimKey(uid,'season_reward','s2')]);
  for(const [number,next] of [[4,5],[5,6]]){
    const result=await request('claimSeasonReward',{},'v219-repair-skipped-'+number);
    assert.equal(result.status,200,JSON.stringify(result.body));assert.equal(result.body.granted,true);
    const repaired=db.read('users/'+uid+'/'+PRODUCT_PROGRESS_FIELD);
    assert.equal(repaired.lastRewardSeason,number);assert.equal(repaired.rewardSeasonNumber,next);
    assert.equal(repaired.trophies,rank);assert.equal(repaired.ratingRevision,revision);
  }
  assert.deepEqual(db.read('users/'+uid+'/serverEconomy/claims/'+api.sourceClaimKey(uid,'season_reward','s2')),paidClaim);
  const before=structuredClone(db.read('users/'+uid));
  const replay=await request('claimSeasonReward',{},'v219-repair-skipped-replay');
  assert.equal(replay.status,200);assert.equal(replay.body.granted,false);assert.deepEqual(db.read('users/'+uid),before);
  assert.deepEqual(JSON.parse(db.read('battleV1Accounts/'+uid+'/accountJson')),account);
});

test('cursor repair can revisit an older unpaid season while preserving a later proven payment',async t=>{
  const {profile,account}=seasonFixture([2,4,5]),progress=profile[PRODUCT_PROGRESS_FIELD];
  for(const number of [2,5])api.applyRewardClaim(profile,{uid,sourceType:'season_reward',sourceId:'s'+number,reward:api.SEASON_REWARDS[0].reward,at});
  Object.assign(progress,{seasonNumber:6,rewardSeasonNumber:6,lastRewardSeason:5,lastRewardTier:api.SEASON_REWARDS[0].tier});
  progress.seasons.s6={number:6,seasonId:'s6',peakTrophies:0,startedAt:api.seasonBounds(6).startAt};
  const db=setup(t,profile,account),paidFive=structuredClone(profile.serverEconomy.claims[api.sourceClaimKey(uid,'season_reward','s5')]);
  const result=await request('claimSeasonReward',{},'v219-out-of-order-repair');
  assert.equal(result.status,200,JSON.stringify(result.body));assert.equal(result.body.granted,true);
  assert.equal(db.read('users/'+uid+'/'+PRODUCT_PROGRESS_FIELD+'/rewardSeasonNumber'),5);
  assert.ok(readBattleV1ProductProgress(db.read('users/'+uid),at));
  const gold=db.read('users/'+uid+'/gold'),gems=db.read('users/'+uid+'/gems');
  const repair=await request('claimSeasonReward',{},'v219-out-of-order-paid-replay');
  assert.equal(repair.status,200);assert.equal(repair.body.granted,false);
  assert.equal(db.read('users/'+uid+'/'+PRODUCT_PROGRESS_FIELD+'/rewardSeasonNumber'),6);
  assert.equal(db.read('users/'+uid+'/gold'),gold);assert.equal(db.read('users/'+uid+'/gems'),gems);
  assert.deepEqual(db.read('users/'+uid+'/serverEconomy/claims/'+api.sourceClaimKey(uid,'season_reward','s5')),paidFive);
});
