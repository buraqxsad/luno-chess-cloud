'use strict';

const test=require('node:test'),assert=require('node:assert/strict');
const {PRODUCT_PROGRESS_FIELD,projectBattleV1ProductProgress,readBattleV1ProductProgress,
  productProgressProfile,completeBattleV1ProductSeason}=require('../lib/battle-v1-product-progress');
const {applyV1Rating}=require('../lib/battle-v1-rating');
const {authority,protocol}=require('../lib/battle-v1');
const {STARTER}=require('../rules-v1/dist/src/model');
const {arenaIndexForProfile}=require('../lib/ranked');
const {seasonBounds,applyRewardClaim,sourceClaimKey}=require('../lib/economy');
const {ACHIEVEMENT_CATALOG,SEASON_PATH_REWARDS,SEASON_REWARDS}=require('../lib/catalogs');
const {fixture}=require('./helpers/battle-v1-fixture');

const s6=seasonBounds(6).startAt,s7=seasonBounds(7).startAt;
function profile(){return {uid:'alice',trophies:9000,arenaIdx:8,gold:100,gems:10,
  serverSeason:{number:6,seasonId:'s6',peakTrophies:9000,startedAt:s6,claimed:{path_1:s6}},
  serverCompetition:{legacy:true},passState:{seasonKey:'ranked-s7-v2',premium:true,level:12,xp:41},
  serverProgress:{battleProtocol:protocol.PROTOCOL}};}
function account(rating=600){return {migrationVersion:1,rating,ratingRevision:0,games:0,entitlements:[...STARTER]};}
function settle(a,id,at,winner='w',reason='resign'){
  const m={protocolVersion:protocol.PROTOCOL,matchId:id,rated:true,
    players:{w:{uid:'alice',bot:false},b:{uid:'bob',bot:false}},result:{reason,winner,finishedAt:at},
    battle:{rules:{ply:12}},metrics:{'player:w:moveCount':6,'player:b:moveCount':6},
    ratingAtStart:{w:a.rating,b:a.rating}};
  applyV1Rating(a,m,'alice');a.ratingRevision++;return a;
}
function paidSeason(p,number,at,reward=SEASON_REWARDS[1].reward){
  return applyRewardClaim(p,{uid:p.uid,sourceType:'season_reward',sourceId:'s'+number,reward,at});
}
function withoutProjection(p){const copy=structuredClone(p);delete copy[PRODUCT_PROGRESS_FIELD];return copy;}

test('real V1 receipt projects rank, season path and arena achievement eligibility without changing legacy fields',()=>{
  const p=profile(),before=structuredClone(p),a=settle(account(),'first',s6+1000);
  assert.equal(projectBattleV1ProductProgress(p,a,'first',s6+2000),true);
  const view=productProgressProfile(p,s6+2000),progress=readBattleV1ProductProgress(p,s6+2000);
  assert.equal(view.trophies,a.rating);assert.equal(view.arenaIdx,arenaIndexForProfile({trophies:a.rating}));
  assert.equal(view.serverSeason.peakTrophies,a.rating);
  assert(SEASON_PATH_REWARDS.find(tier=>tier.id==='path_4').minTrophies<=view.serverSeason.peakTrophies);
  assert(SEASON_PATH_REWARDS.find(tier=>tier.id==='path_5').minTrophies>view.serverSeason.peakTrophies);
  assert(arenaIndexForProfile(view)+1>=ACHIEVEMENT_CATALOG.arena_3.target);
  assert(arenaIndexForProfile(view)+1<ACHIEVEMENT_CATALOG.arena_5.target);
  assert.equal(arenaIndexForProfile(view)>0,true); // special mission s1
  assert.equal(progress.ratingRevision,1);assert.equal(progress.uid,'alice');
  assert.deepEqual(withoutProjection(p),before);
});

test('missing legacy projection is unchanged; known old/cancelled V1 accounts use zero eligibility without 503 or legacy trophies',()=>{
  const legacy={uid:'alice',trophies:9000,arenaIdx:8};
  assert.equal(productProgressProfile(legacy,s6),legacy);
  const old=profile(),before=structuredClone(old),view=productProgressProfile(old,s6);
  assert.equal(view.trophies,0);assert.equal(view.arenaIdx,0);assert.equal(view.serverSeason.peakTrophies,0);
  assert.deepEqual(old,before);assert.equal(readBattleV1ProductProgress(old,s6),null);
});

test('newer loss may lower current rank but cannot lower earned peaks',()=>{
  const p=profile(),a=settle(account(650),'win',s6+1000);
  projectBattleV1ProductProgress(p,a,'win',s6+2000);
  const peak=p[PRODUCT_PROGRESS_FIELD].peakTrophies;
  settle(a,'loss',s6+3000,'b');projectBattleV1ProductProgress(p,a,'loss',s6+4000);
  assert.equal(p[PRODUCT_PROGRESS_FIELD].trophies,a.rating);assert(a.rating<peak);
  assert.equal(p[PRODUCT_PROGRESS_FIELD].peakTrophies,peak);
  assert.equal(p[PRODUCT_PROGRESS_FIELD].seasons.s6.peakTrophies,peak);
});

test('stale account revision cannot regress rank; equal-revision rank conflict fails closed',()=>{
  const p=profile(),a=settle(account(),'old',s6+1000),old=structuredClone(a);
  settle(a,'new',s6+2000);projectBattleV1ProductProgress(p,a,'new',s6+3000);
  const before=structuredClone(p);
  assert.equal(projectBattleV1ProductProgress(p,old,'old',s6+3000),false);
  assert.deepEqual(p,before);
  const conflict=structuredClone(a);conflict.rating++;conflict.ratingProfile.trophies++;
  assert.throws(()=>projectBattleV1ProductProgress(p,conflict,'new',s6+3000),{code:'battle-v1-product-progress-unavailable'});
  assert.deepEqual(p,before);
});

test('old-match recovery with latest account rebuilds newer season records and can backfill a historical V1 user',()=>{
  const a=settle(account(),'old',s6+1000);settle(a,'new',s7+1000);
  assert.equal(a.ratingProfile.serverSeason.number,6); // source season does not auto-roll
  const p=profile();projectBattleV1ProductProgress(p,a,'old',s7+2000);
  const progress=readBattleV1ProductProgress(p,s7+2000);
  assert.equal(progress.ratingRevision,2);assert.equal(progress.trophies,a.rating);
  assert.equal(progress.seasonNumber,7);assert(progress.seasons.s7.peakTrophies>progress.seasons.s6.peakTrophies);
  assert.equal(progress.rewardSeasonNumber,6);assert.equal(productProgressProfile(p,s7+2000).serverSeason.number,6);
});

test('shared ledger advances only the reward cursor, preserves current peaks, and old recovery cannot undo it',()=>{
  const p=profile(),a=settle(account(),'old',s6+1000),old=structuredClone(a);
  settle(a,'new',s7+1000);projectBattleV1ProductProgress(p,a,'new',s7+2000);
  const rank=a.rating,peak=p[PRODUCT_PROGRESS_FIELD].seasons.s7.peakTrophies,legacy=withoutProjection(p);
  const grant=paidSeason(p,6,s7+2000);assert.equal(grant.granted,true);
  completeBattleV1ProductSeason(p,6,s7+2000);
  const view=productProgressProfile(p,s7+2000);
  assert.equal(view.serverSeason.number,7);assert.equal(view.serverSeason.peakTrophies,peak);
  assert.equal(view.serverSeason.lastRewardSeason,6);assert.equal(view.serverSeason.lastRewardTier,'Silver');
  assert.equal(view.trophies,rank);assert.equal(p.trophies,legacy.trophies);assert.deepEqual(p.passState,legacy.passState);
  const after=structuredClone(p);assert.equal(projectBattleV1ProductProgress(p,old,'old',s7+3000),false);
  assert.deepEqual(p,after);assert.equal(paidSeason(p,6,s7+3000).granted,false);assert.deepEqual(p,after);
});

test('cursor advancement without a current-season match creates no unearned peak and keeps a valid latest record',()=>{
  const p=profile(),a=settle(account(),'old',s6+1000);projectBattleV1ProductProgress(p,a,'old',s6+2000);
  paidSeason(p,6,s7);completeBattleV1ProductSeason(p,6,s7);
  const progress=readBattleV1ProductProgress(p,s7);
  assert.equal(progress.seasonNumber,7);assert.equal(progress.rewardSeasonNumber,7);
  assert.equal(progress.seasons.s7.peakTrophies,0);assert.equal(progress.trophies,a.rating);
});

test('end reward requires owner-bound ledger proof; a prior legacy tier is not paid twice',()=>{
  const p=profile(),a=settle(account(),'old',s6+1000);projectBattleV1ProductProgress(p,a,'old',s6+2000);
  const before=structuredClone(p);
  assert.throws(()=>completeBattleV1ProductSeason(p,6,s7),{code:'battle-v1-product-progress-unavailable'});
  assert.deepEqual(p,before);
  paidSeason(p,6,s7,SEASON_REWARDS[0].reward);
  const broken=structuredClone(p),claim=broken.serverEconomy.claims[sourceClaimKey('alice','season_reward','s6')];
  broken.serverEconomy.ledger[claim.transactionIds[0]].uid='bob';
  assert.throws(()=>completeBattleV1ProductSeason(broken,6,s7),{code:'battle-v1-product-progress-unavailable'});
  completeBattleV1ProductSeason(p,6,s7);
  assert.equal(productProgressProfile(p,s7).serverSeason.lastRewardTier,'Bronze');
  assert.equal(paidSeason(p,6,s7).granted,false);
});

for(const [name,mutate] of [
  ['foreign owner',a=>{a.ratingProfile.uid='bob';}],
  ['wrong protocol',a=>{a.protocolVersion='legacy';}],
  ['fractional revision',a=>{a.ratingRevision=1.5;}],
  ['string rating',a=>{a.rating=String(a.rating);}],
  ['invalid arena',a=>{a.ratingProfile.arenaIdx=99;}],
  ['future receipt',a=>{a.ratingSettlements.first.settledAt=s7;}],
  ['mismatched delta',a=>{const r=a.ratingSettlements.first;r.previousTrophies=r.newTrophies-r.trophyDelta;r.trophyDelta++;}],
  ['missing receipt',a=>{delete a.ratingSettlements.first;}],
])test('untrusted projection source rejected: '+name,()=>{
  const p=profile(),before=structuredClone(p),a=settle(account(),'first',s6+1000);mutate(a);
  assert.throws(()=>projectBattleV1ProductProgress(p,a,'first',s6+2000),{code:'battle-v1-product-progress-unavailable'});
  assert.deepEqual(p,before);
});

test('invalid source season is not promoted; corrupt stored latest/cursor records fail closed',()=>{
  const p=profile(),a=settle(account(),'first',s6+1000);
  a.ratingProfile.serverSeason={number:7,seasonId:'s7',peakTrophies:999999,startedAt:s7};
  projectBattleV1ProductProgress(p,a,'first',s6+2000);
  assert.equal(p[PRODUCT_PROGRESS_FIELD].seasonNumber,6);assert.equal(p[PRODUCT_PROGRESS_FIELD].peakTrophies,a.rating);
  for(const mutate of [x=>{x.seasonNumber=7;},x=>{delete x.seasons.s6;},x=>{x.uid='bob';},x=>{x.seasons.s6.peakTrophies=Infinity;}]){
    const broken=structuredClone(p);mutate(broken[PRODUCT_PROGRESS_FIELD]);
    assert.throws(()=>productProgressProfile(broken,s7),{code:'battle-v1-product-progress-unavailable'});
  }
});

async function paired(){
  const f=fixture();f.setTime(s6+2000);await f.enable();
  await f.api.enqueueBattleV1(f.context('alice',{client:f.client},'v218-a'));
  const q=await f.api.enqueueBattleV1(f.context('bob',{client:f.client},'v218-b'));
  return {...f,id:q.matchId};
}
test('real recovery persists trusted product progress exactly once and preserves legacy fields and current paid Pass',async()=>{
  const f=await paired(),before=structuredClone(f.read('users/alice'));
  before.passState={seasonKey:'ranked-s7-v2',season:7,premium:true,level:12,xp:41};
  before.productEntitlementVersion=2;f.write('users/alice',before);
  const m=await f.api.load(f.id,'alice'),side=protocol.sideForUid(m,'alice');
  await f.api.transact(f.id,'alice',current=>({match:authority.finishMatch(current,{reason:'resign',winner:side,finishedAt:s6+1000})}));
  await f.api.settle(f.id,'alice');
  const after=f.read('users/alice'),a=JSON.parse(f.read('battleV1Accounts/alice').accountJson);
  assert.equal(after[PRODUCT_PROGRESS_FIELD].trophies,a.rating);assert.equal(after[PRODUCT_PROGRESS_FIELD].ratingRevision,a.ratingRevision);
  for(const key of ['trophies','arenaIdx','serverSeason','serverCompetition','passState'])assert.deepEqual(after[key],before[key]);
  assert.equal(after.stats.wins,1);const saved=structuredClone(after);
  await f.api.settle(f.id,'bob');assert.deepEqual(f.read('users/alice'),saved);
});

test('cancelled first rated recovery remains readable and cannot create product rewards from legacy rank',async()=>{
  const f=await paired();
  await f.api.transact(f.id,'alice',m=>({match:authority.finishMatch(m,{reason:'protocol-upgrade',winner:null,finishedAt:s6+1000})}));
  await f.api.settle(f.id,'alice');
  const p=f.read('users/alice');assert.equal(p[PRODUCT_PROGRESS_FIELD],undefined);
  const view=productProgressProfile(p,s6+2000);assert.equal(view.trophies,0);assert.equal(view.serverSeason.peakTrophies,0);
});

test('overlapping account/profile writes cannot let an older recovery replace a newer committed revision',async()=>{
  const p=profile(),a=settle(account(),'old',s6+1000),old=structuredClone(a);
  let release;const blocked=new Promise(resolve=>{release=resolve;});
  const lateWrite=(async()=>{await blocked;projectBattleV1ProductProgress(p,old,'old',s7+3000);})();
  settle(a,'new',s7+1000);projectBattleV1ProductProgress(p,a,'new',s7+2000);
  const expected=structuredClone(p);release();await lateWrite;assert.deepEqual(p,expected);
});
