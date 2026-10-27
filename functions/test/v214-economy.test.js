'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {ARENAS,applyRankedSettlement}=require('../lib/ranked');
const {applyV1Rating}=require('../lib/battle-v1-rating');
const {UNLOCK_PATH,applyCompetitiveProgression,progressionSummary}=require('../lib/battle-v1-progression');
const {PASS_CURRENCY_REWARDS,PASS_CURRENCY_REWARDS_V2,SOFT_ITEM_CATALOG}=require('../lib/catalogs');
const {LAST_LEGACY_PASS_SEASON,syncPassState,passCurrencyReward}=require('../lib/pass');
const {periodSnapshot,seasonBounds}=require('../lib/economy');
const {STARTER,CARDS}=require('../rules-v1/dist/src/model');
const {migrateLegacy,validateOwnedDeck}=require('../rules-v1/dist/src/online/migration');
const {fixture}=require('./helpers/battle-v1-fixture');

test('rank client and authoritative catalog remain identical at every boundary',()=>{
  const source=fs.readFileSync(path.join(__dirname,'../../luno_chess/lib/data/rank_catalog.dart'),'utf8');
  const entries=[...source.matchAll(/ArenaDefinition\(\s*index: ([0-9]+),([\s\S]+?)\n  \)/g)];
  assert.equal(entries.length,ARENAS.length);
  entries.forEach((entry,index)=>{
    const n=key=>Number(new RegExp(key+': ([0-9]+)').exec(entry[2])?.[1]);
    assert.equal(Number(entry[1]),index);
    assert.equal(n('minTrophies'),ARENAS[index].min);
    assert.equal(n('winTrophies'),ARENAS[index].win);
    assert.equal(n('lossTrophies'),ARENAS[index].lose);
    if(index<ARENAS.length-1)assert.equal(n('maxTrophies')+1,ARENAS[index].max);
  });
});

test('upper-arena equal-rating break-even is between 50 and 55 percent',()=>{
  for(const arena of ARENAS.slice(5)){
    const rate=arena.lose/(arena.win+arena.lose);
    assert.ok(rate>=.5&&rate<=.55);
  }
});

test('rank floors, symmetric opponent adjustment, no streak trophy bonus, and retry safety hold',()=>{
  const at=Date.parse('2026-10-08T12:00:00Z');
  ARENAS.forEach((arena,index)=>{
    for(const outcome of ['win','loss','draw','cancelled']){
      const profile={trophies:arena.min+Math.min(100,Math.floor((arena.max-arena.min)/2)),arenaIdx:index,gold:777,gems:888,stats:{winStreak:6}};
      const options={uid:'alice',matchId:'rank-'+index+'-'+outcome,outcome,at,opponentTrophies:profile.trophies};
      const receipt=applyRankedSettlement(profile,options);
      const expected=outcome==='win'?arena.win:outcome==='loss'?-arena.lose:0;
      assert.equal(receipt.trophyDelta,expected);
      const snapshot=structuredClone(profile);
      for(let retry=0;retry<10;retry++)applyRankedSettlement(profile,{...options,outcome:'win'});
      assert.deepEqual(profile,snapshot);
    }
    const atFloor={trophies:arena.min,arenaIdx:index};
    const floor=applyRankedSettlement(atFloor,{uid:'alice',matchId:'floor-'+index,outcome:'loss',at});
    assert.equal(floor.newTrophies,arena.min);assert.equal(floor.trophyDelta,0);
    const position=arena.min+Math.min(100,Math.floor((arena.max-arena.min)/2));
    const down={trophies:position,arenaIdx:index},up=structuredClone(down);
    const lowerOpponent=Math.max(0,position-80);
    const lower=applyRankedSettlement(down,{uid:'alice',matchId:'lower-'+index,outcome:'win',opponentTrophies:lowerOpponent,at});
    const higher=applyRankedSettlement(up,{uid:'alice',matchId:'higher-'+index,outcome:'win',opponentTrophies:position+80,at});
    assert.equal(higher.trophyDelta-lower.trophyDelta,1-Math.round((lowerOpponent-position)/80));
  });
});

test('future Pass has no gem profit; legacy advertised rewards remain intact',()=>{
  const total=rewards=>Object.values(rewards).reduce((sum,r)=>sum+(r.gems||0),0);
  assert.equal(total(PASS_CURRENCY_REWARDS.free),120);
  assert.equal(total(PASS_CURRENCY_REWARDS.premium),540);
  assert.equal(total(PASS_CURRENCY_REWARDS_V2.premium),330);
  assert.equal(total(PASS_CURRENCY_REWARDS_V2.free)+total(PASS_CURRENCY_REWARDS_V2.premium),SOFT_ITEM_CATALOG['pass:premium'].price);
  for(let level=1;level<=30;level++){
    assert.equal(PASS_CURRENCY_REWARDS_V2.premium[level].gold,PASS_CURRENCY_REWARDS.premium[level].gold);
    assert.equal(passCurrencyReward({rewardVersion:1},'premium',level).gems,18);
    assert.equal(passCurrencyReward({rewardVersion:2},'premium',level).gems,11);
  }
});

test('season rollover is explicit, and active purchased/earned state is grandfathered without data loss',()=>{
  const before=seasonBounds(LAST_LEGACY_PASS_SEASON).endAt-1,after=before+1;
  assert.equal(periodSnapshot(after).seasonNumber,LAST_LEGACY_PASS_SEASON+1);
  const p={gold:1234,gems:5678,inventory:{ownedSets:['ottoman']},passState:{seasonKey:'ranked-s6-v2',season:6,level:12,xp:23,premium:true,premiumSource:'soft_purchase',claimed:{free:{5:7},premium:{2:8}},unlocks:['emoji:laugh']}};
  const old=syncPassState(p,before).pass;
  assert.equal(old.rewardVersion,1);assert.equal(old.level,12);assert.equal(old.xp,23);
  assert.deepEqual(old.claimed,{free:{5:7},premium:{2:8}});assert.deepEqual(old.unlocks,['emoji:laugh']);
  const next=syncPassState(p,after).pass;
  assert.equal(next.rewardVersion,2);assert.equal(next.premium,false);assert.equal(next.level,0);
  assert.equal(p.gold,1234);assert.equal(p.gems,5678);assert.deepEqual(p.inventory.ownedSets,['ottoman']);
  assert(p.inventory.ownedFrames.includes('premium')); // V215 preserves old shared cosmetic rights.
  for(const progress of [{premium:true},{level:1},{xp:1},{claimed:{premium:{1:123}}}]){
    const existing={passState:{seasonKey:'ranked-s7-v2',season:7,level:0,xp:0,premium:false,...progress}};
    assert.equal(syncPassState(existing,after).pass.rewardVersion,1);
  }
  const purchasedNew={passState:{seasonKey:'ranked-s7-v2',season:7,level:2,xp:5,premium:true,rewardVersion:2}};
  assert.equal(syncPassState(purchasedNew,after).pass.rewardVersion,2);
  const numericLegacy={passState:{seasonKey:'ranked-s7-v2',season:7,level:'12',xp:'23',premium:false}};
  const normalized=syncPassState(numericLegacy,after).pass;
  assert.equal(normalized.rewardVersion,1);assert.equal(normalized.level,12);assert.equal(normalized.xp,23);
});

test('new season membership does not activate Pass; invalid tier inputs cannot mint a reward',()=>{
  const at=seasonBounds(7).startAt;
  const profile={premiumUntil:at+100000};
  const pass=syncPassState(profile,at).pass;
  assert.equal(pass.rewardVersion,2);assert.equal(pass.premium,false);
  for(const [track,level] of [['bad',1],['free',0],['premium',31],['premium',1.5],['premium','1']])assert.equal(passCurrencyReward(pass,track,level),null);
});

function syntheticMatch(id,options={}){
  return {protocolVersion:'LUNO_BATTLE_V1',matchId:id,rated:true,players:{w:{uid:'alice',bot:false},b:{uid:'bob',bot:false}},
    result:{reason:'resign',winner:'b',finishedAt:Date.parse('2026-10-08T12:00:00Z')},
    battle:{rules:{ply:12}},metrics:{'player:w:moveCount':6,'player:b:moveCount':6},ratingAtStart:{w:0,b:0},...options};
}

test('every canonical card unlocks deterministically by 20 meaningful human ranked matches',()=>{
  const account={migrationVersion:1,deck:[...STARTER],entitlements:[...STARTER],fallback:true,rating:0,provisionalSkillSeed:0};
  assert.equal(UNLOCK_PATH.length,14);assert.equal(new Set(UNLOCK_PATH.map(t=>t.card)).size,14);
  for(let i=1;i<=20;i++){
    const match=syntheticMatch('unlock-'+i),receipt=applyV1Rating(account,match,'alice');
    assert.equal(receipt.progression.meaningfulMatches,i);
    const snapshot=structuredClone(account);
    for(let retry=0;retry<10;retry++)assert.deepEqual(applyV1Rating(account,match,'alice'),receipt);
    assert.deepEqual(account,snapshot);
    for(const tier of UNLOCK_PATH)assert.equal(account.entitlements.includes(tier.card),i>=tier.matches);
  }
  assert.deepEqual(new Set(account.entitlements),new Set(Object.keys(CARDS)));
  assert.equal(progressionSummary(account).nextUnlock,null);
  assert.equal(account.rating,0); // Losing never blocks learning progression.
});

test('cancelled, bots, friendly, immediate resignation, and low-input AFK matches cannot farm unlocks',()=>{
  for(const options of [
    {result:{reason:'protocol-upgrade',winner:null,finishedAt:1}},
    {players:{w:{uid:'alice',bot:false},b:{uid:'bob',bot:true}}},
    {rated:false},{battle:{rules:{ply:11}}},{metrics:{'player:w:moveCount':3}},
  ]){
    const account={entitlements:[...STARTER]};
    const receipt=applyCompetitiveProgression(account,syntheticMatch('not-earned',options),'alice');
    assert.equal(receipt.qualified,false);assert.equal(receipt.meaningfulMatches,0);assert.deepEqual(receipt.unlocked,[]);
  }
  const a={rating:0,games:0};
  applyV1Rating(a,syntheticMatch('cancel',{result:{reason:'protocol-upgrade',winner:null,finishedAt:1}}),'alice');
  assert.equal(a.games,0);
});

test('existing paid/migrated ownership survives progression and deck ownership checks',()=>{
  const a=migrateLegacy({battleV1UnlockedCards:{board_seal:true},gold:111,gems:222});
  assert.ok(a.entitlements.includes('board_seal'));
  applyCompetitiveProgression(a,syntheticMatch('preserve'),'alice');
  assert.ok(a.entitlements.includes('board_seal'));
  const migrated=migrateLegacy({unlockedCards:{radar3:true}},a);
  assert.equal(migrated.competitiveProgression.meaningfulMatches,1);
  assert.ok(migrated.entitlements.includes('mine'));assert.ok(migrated.entitlements.includes('board_seal'));
  assert.throws(()=>validateOwnedDeck([...STARTER.slice(0,9),'fate_exchange'],migrated),e=>e.code==='CARD_NOT_OWNED');
  assert.deepEqual(validateOwnedDeck([...STARTER.slice(0,9),'mine'],migrated),[...STARTER.slice(0,9),'mine']);
});

test('real V1 action/settlement/recovery path grants deterministic ownership once and keeps rating namespace isolated',async()=>{
  const f=fixture();await f.enable();await f.api.migrate('alice');await f.api.migrate('bob');
  const moves=['a2a3','a7a6','b2b3','b7b6','c2c3','c7c6','d2d3','d7d6','e2e3','e7e6','f2f3','f7f6'];
  for(let i=1;i<=20;i++){
    const id='bv1_'+String(i).padStart(32,'0');
    let m=await f.api.create(id,{uid:'alice',name:'alice',bot:false},{uid:'bob',name:'bob',bot:false},STARTER,STARTER,true,{w:0,b:0});
    for(let ply=0;ply<moves.length;ply++){
      const uid=ply%2?'bob':'alice';
      const intents=[...(m.battle.rules.phase==='card'?[{type:'pass'}]:[]),{type:'move',uci:moves[ply]}];
      for(const intent of intents){
        const r=await f.api.submitBattleV1Action(f.context(uid,{protocolVersion:'LUNO_BATTLE_V1',matchId:id,expectedStateVersion:m.stateVersion,actionId:`a${m.stateVersion}_progress-test`,intent}));
        m=await f.api.load(r.matchId,uid);
      }
    }
    await f.api.resignBattleV1(f.context('alice',{protocolVersion:'LUNO_BATTLE_V1',matchId:id,expectedStateVersion:m.stateVersion,actionId:`a${m.stateVersion}_resign-test`}));
    await f.api.settle(id,'alice');
    const deck=await f.api.getBattleV1Deck(f.context('alice',{client:f.client}));
    assert.equal(deck.progression.meaningfulMatches,i);
    assert.equal(f.read('users/alice').trophies,1200);assert.equal(f.read('users/alice').arenaIdx,4);
  }
  const result=await f.api.getBattleV1Deck(f.context('alice',{client:f.client}));
  assert.deepEqual(new Set(result.entitlements),new Set(Object.keys(CARDS)));
  assert.equal(result.progression.nextUnlock,null);
  const account=JSON.parse(f.read('battleV1Accounts/alice').accountJson);
  assert.equal(account.games,20);assert.equal(account.rating,0);
  assert.equal(f.read('battleV1Ratings/alice').rating,0);
});
