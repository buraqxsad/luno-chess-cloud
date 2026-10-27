'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {fixture}=require('./helpers/battle-v1-fixture');
const {protocol,authority}=require('../lib/battle-v1');
const {STARTER}=require('../rules-v1/dist/src/model.js');
const {newBattle}=require('../rules-v1/dist/src/authoritative.js');
const {playerSettlementMetrics}=require('../lib/battle-v1-recovery');
const {periodSnapshot,sourceClaimKey,applySoftPurchase}=require('../lib/economy');
const {syncPassState}=require('../lib/pass');
const {applyRankedSettlement,ARENAS}=require('../lib/ranked');

const id='bv1_21421421421421421421421421421421';
const finishedAt=Date.UTC(2026,9,8,23,59);
async function ready(configure=()=>{},deck=STARTER){
 const f=fixture();f.setTime(finishedAt-20000);
 for(const uid of ['alice','bob']){
  const profile=structuredClone(f.read('users/'+uid));configure(profile,uid);
  f.write('users/'+uid,profile);await f.api.migrate(uid);
 }
 await f.api.create(id,{uid:'alice',name:'Alice',bot:false},{uid:'bob',name:'Bob',bot:false},deck,deck,true);
 return f;
}
async function finish(f,reason='resign',winner='w'){
 await f.api.transact(id,'alice',m=>({match:authority.finishMatch(m,{reason,winner,finishedAt})}));
}
function userReceipt(profile,uid){
 const receipts=Object.values(profile.serverProgress.rankedSettlements);
 assert.equal(receipts.length,1);assert.equal(receipts[0].matchId,id);
 assert(profile.serverEconomy.claims[sourceClaimKey(uid,'ranked_match',id)]);
 return receipts[0];
}
function ratingAccount(f,uid){return JSON.parse(f.read('battleV1Accounts/'+uid).accountJson);}

for(const invalidUid of ['attacker',undefined]){
 test(`existing users bridge rejects ${invalidUid===undefined?'missing':'foreign'} profile UID and safely retries`,async()=>{
  const f=await ready();await finish(f);
  const wrong=structuredClone(f.read('users/alice'));
  if(invalidUid===undefined)delete wrong.uid;else wrong.uid=invalidUid;
  f.write('users/alice',wrong);
  const attacker=structuredClone(f.read('users/attacker'));
  await assert.rejects(f.api.settle(id,'alice'),{code:'profile-owner-mismatch',status:403});
  assert.deepEqual(f.read('users/alice'),wrong);assert.deepEqual(f.read('users/attacker'),attacker);
  assert.equal((await f.api.load(id,'alice')).settlementStatus,'pending');
  const committedRating=ratingAccount(f,'alice');assert.equal(committedRating.games,1);
  f.write('users/alice',{...wrong,uid:'alice'});
  await f.api.settle(id,'alice');const credited=structuredClone(f.read('users/alice'));
  assert.equal(credited.stats.wins,1);userReceipt(credited,'alice');
  assert.deepEqual(ratingAccount(f,'alice'),committedRating);
  await f.api.settle(id,'bob');assert.deepEqual(f.read('users/alice'),credited);
 });
}

test('existing bridge adds spendable gold and XP to current users state without copying private balances or paid ownership',async()=>{
 const f=await ready(profile=>{
  profile.gold=2700;profile.gems=455;profile.lvl=3;profile.xp=17;
  profile.stats={wins:7,losses:2,draws:1,winStreak:3,bestStreak:4,chestsOpened:6};
  profile.unlockedCards={radar:true,freeze:true};profile.cardLevels={radar:2};
  profile.serverEconomy={claims:{paid:{receipt:'existing-paid-claim'}},purchases:{paid:{price:450}},ledger:{paid:{amount:-450}}};
 });
 const before=structuredClone(f.read('users/alice'));
 const record=f.read('battleV1Accounts/alice'),account=JSON.parse(record.accountJson);
 account.ratingProfile={uid:'alice',trophies:0,arenaIdx:0,gold:987654,gems:654321,lvl:1,xp:0,stats:{}};
 f.write('battleV1Accounts/alice',{...record,accountJson:JSON.stringify(account)});
 await finish(f);await f.api.settle(id,'alice');
 const profile=structuredClone(f.read('users/alice')),receipt=userReceipt(profile,'alice');
 assert.equal(profile.gold,before.gold+receipt.gold+receipt.levelGold);
 assert.equal(profile.xp,before.xp+receipt.xp);assert.equal(profile.lvl,before.lvl);
 assert.equal(profile.gems,before.gems);assert.equal(profile.stats.wins,before.stats.wins+1);
 assert.equal(profile.stats.chestsOpened,before.stats.chestsOpened);
 for(const key of ['trophies','arenaIdx','serverCompetition','serverSeason','unlockedCards','cardLevels'])assert.deepEqual(profile[key],before[key]);
 for(const key of ['claims','purchases','ledger'])assert.deepEqual(profile.serverEconomy[key].paid,before.serverEconomy[key].paid);
 assert.notEqual(profile.gold,ratingAccount(f,'alice').ratingProfile.gold);
 const spend=applySoftPurchase(profile,{uid:'alice',sourceType:'proof_purchase',sourceId:'after-v1-win',itemType:'proof',itemId:'bridge',currency:'gold',price:receipt.gold,at:finishedAt+1});
 assert.equal(spend.purchased,true);assert.equal(profile.gold,before.gold+receipt.levelGold);
});

test('historical V1 receipts without previousTrophies still grant the correct upper-arena rewards',async()=>{
 const f=await ready(),before=structuredClone(f.read('users/alice'));
 const record=f.read('battleV1Accounts/alice'),account=JSON.parse(record.accountJson);
 account.rating=ARENAS.at(-1).min;
 f.write('battleV1Accounts/alice',{...record,accountJson:JSON.stringify(account)});
 await f.api.transact(id,'alice',m=>{m.ratingAtStart={w:account.rating,b:account.rating};return {match:authority.finishMatch(m,{reason:'resign',winner:'w',finishedAt})};});
 await f.api.settle(id,'alice');const profile=f.read('users/alice'),receipt=userReceipt(profile,'alice');
 const v1=ratingAccount(f,'alice').ratingSettlements[id];assert.equal(v1.previousTrophies,undefined);
 const expectedProfile={...before,trophies:account.rating,arenaIdx:0};
 const expected=applyRankedSettlement(expectedProfile,{uid:'alice',matchId:id,outcome:'win',opponentTrophies:account.rating,moveCount:0,at:finishedAt});
 assert.equal(receipt.gold,expected.gold);assert.equal(receipt.xp,expected.xp);assert.equal(profile.gold,before.gold+expected.gold+expected.levelGold);
 assert.equal(profile.trophies,before.trophies);assert.equal(profile.arenaIdx,before.arenaIdx);
});

for(const premium of [false,true]){
 test(`existing bridge uses current user ${premium?'purchased premium':'free'} Pass and server result timestamp`,async()=>{
  const f=await ready(profile=>{
   profile.xp=0;profile.lvl=1;
   const pass=syncPassState(profile,finishedAt).pass;
   Object.assign(pass,{premium,premiumSource:premium?'purchase':'',level:4,xp:240,rewardVersion:1,claimed:{free:{1:true},premium:{2:true}}});
  });
  const before=structuredClone(f.read('users/alice'));
  await finish(f);f.setTime(finishedAt+8*24*60*60*1000);
  await f.api.settle(id,'alice');const profile=structuredClone(f.read('users/alice')),receipt=userReceipt(profile,'alice');
  assert.equal(profile.passState.level*250+profile.passState.xp-(before.passState.level*250+before.passState.xp),receipt.xp*3*(premium?2:1));
  for(const key of ['premium','premiumSource','rewardVersion','claimed','seasonKey'])assert.deepEqual(profile.passState[key],before.passState[key]);
  const period=periodSnapshot(finishedAt),retryPeriod=periodSnapshot(finishedAt+8*24*60*60*1000);
  assert.equal(receipt.settledAt,finishedAt);
  assert.equal(profile.serverProgress.missions.daily[period.dayKey].counters.d1,1);
  assert.equal(profile.serverProgress.missions.weekly[period.weekKey].counters.w1,1);
  assert.equal(profile.serverProgress.missions.daily[retryPeriod.dayKey],undefined);
  assert.equal(profile.serverProgress.missions.weekly[retryPeriod.weekKey],undefined);
  assert.equal(profile.serverEconomy.claims[sourceClaimKey('alice','ranked_match',id)].claimedAt,finishedAt);
  await f.api.settle(id,'bob');assert.deepEqual(f.read('users/alice'),profile);
 });
}

test('real accepted cast, legendary sacrifice and discard keep correct per-player statistics and missions',async()=>{
 const deck=['shadow_contract','board_seal','radar',...STARTER.filter(card=>card!=='radar').slice(0,7)];
 const f=await ready(()=>{},deck);let match=await f.api.load(id,'alice');
 match.battle=newBattle(deck,deck);
 match.audit[0].hands=structuredClone(match.battle.hidden.hands);match.audit[0].decks=structuredClone(match.battle.hidden.decks);
 const action=intent=>{
  const side=match.battle.rules.fen.split(' ')[1];
  match=authority.commitAction(match,match.players[side].uid,{matchId:id,protocolVersion:protocol.PROTOCOL,expectedStateVersion:match.stateVersion,actionId:`a${match.stateVersion}_bridge-proof`,intent},finishedAt-10000+match.stateVersion).match;
 };
 action({type:'move',uci:'e2e4'});action({type:'move',uci:'e7e5'});
 action({type:'play',card:'shadow_contract',sacrifice:'board_seal'});action({type:'move',uci:'g1f3'});
 action({type:'discard',card:'board_seal'});
 assert.deepEqual(match.battle.rules.used.w,['shadow_contract']);assert.deepEqual(match.battle.rules.discarded.w,['board_seal']);
 assert.deepEqual(match.battle.rules.used.b,[]);assert.deepEqual(match.battle.rules.discarded.b,['board_seal']);
 assert.equal(playerSettlementMetrics(match,'w').cardsPlayed,1);assert.equal(playerSettlementMetrics(match,'w').legendaryCards,1);
 assert.equal(playerSettlementMetrics(match,'b').cardsPlayed,0);assert.equal(playerSettlementMetrics(match,'b').legendaryCards,0);
 await f.api.transact(id,'alice',()=>({match:authority.finishMatch(match,{reason:'resign',winner:'w',finishedAt})}));
 await f.api.settle(id,'alice');
 for(const [uid,casts,legendaries] of [['alice',1,1],['bob',0,0]]){
  const profile=f.read('users/'+uid),day=profile.serverProgress.missions.daily[periodSnapshot(finishedAt).dayKey].counters;
  assert.equal(profile.stats.cardsPlayed,casts);assert.equal(day.d3,casts);assert.equal(day.d_legend,legendaries);
  assert.equal(day.cu_board_seal,undefined);assert.equal(day.cu_shadow_contract,casts||undefined);
 }
});

test('partial two-player bridge failure keeps earlier committed rewards exact-once on recovery',async()=>{
 const f=await ready();await finish(f);
 const ref=f.api.db.ref.bind(f.api.db);let fail=true;
 f.api.db.ref=path=>{
  const node=ref(path);if(path!=='users/bob')return node;
  return {...node,transaction:async(...args)=>{if(fail){fail=false;throw new Error('simulated-users-transaction-failure');}return node.transaction(...args);}};
 };
 await assert.rejects(f.api.settle(id,'alice'),/simulated-users-transaction-failure/);
 const alice=structuredClone(f.read('users/alice')),account=ratingAccount(f,'alice');
 assert.equal(alice.stats.wins,1);assert.equal(f.read('users/bob').stats,undefined);
 assert.equal((await f.api.load(id,'alice')).settlementStatus,'pending');
 await f.api.settle(id,'bob');assert.deepEqual(f.read('users/alice'),alice);assert.deepEqual(ratingAccount(f,'alice'),account);
 const bob=structuredClone(f.read('users/bob'));assert.equal(bob.stats.losses,1);userReceipt(bob,'bob');
 assert.equal((await f.api.load(id,'alice')).settlementStatus,'complete');
 await f.api.settle(id,'alice');assert.deepEqual(f.read('users/alice'),alice);assert.deepEqual(f.read('users/bob'),bob);
});

test('Firebase-style transaction callback retry discards speculative reward mutations',async()=>{
 const f=await ready();await finish(f);
 const before=structuredClone(f.read('users/alice')),ref=f.api.db.ref.bind(f.api.db);let probes=0;
 f.api.db.ref=path=>{
  const node=ref(path);if(path!=='users/alice')return node;
  return {...node,transaction:async(fn,...args)=>{for(let i=0;i<3;i++){fn(structuredClone(f.read(path)));probes++;}return node.transaction(fn,...args);}};
 };
 await f.api.settle(id,'alice');const profile=f.read('users/alice'),receipt=userReceipt(profile,'alice');
 assert.equal(probes,3);assert.equal(profile.stats.wins,1);
 assert.equal(profile.gold,before.gold+receipt.gold+receipt.levelGold);
});

test('concurrent settlement entry points remain exact-once in the in-memory transaction fixture',async()=>{
 const f=await ready();await finish(f);
 await Promise.all([f.api.settle(id,'alice'),f.api.settle(id,'bob'),f.api.settle(id,'alice')]);
 const first=structuredClone(f.read('users/alice')),second=structuredClone(f.read('users/bob'));
 assert.equal(first.stats.wins,1);assert.equal(second.stats.losses,1);
 assert.equal(ratingAccount(f,'alice').games,1);assert.equal(ratingAccount(f,'bob').games,1);
 userReceipt(first,'alice');userReceipt(second,'bob');
 await f.api.settle(id,'bob');assert.deepEqual(f.read('users/alice'),first);assert.deepEqual(f.read('users/bob'),second);
});

test('protocol upgrade cancellation preserves balances, paid Pass and mission state',async()=>{
 const f=await ready(profile=>{
  const pass=syncPassState(profile,finishedAt).pass;Object.assign(pass,{premium:true,premiumSource:'purchase',level:7,xp:123,claimed:{free:{1:true},premium:{2:true}}});
 });
 const before=structuredClone(f.read('users/alice'));await finish(f,'protocol-upgrade',null);await f.api.settle(id,'alice');
 const profile=f.read('users/alice');
 for(const key of ['gold','gems','xp','lvl','passState','trophies','arenaIdx','serverCompetition','serverSeason'])assert.deepEqual(profile[key],before[key]);
 assert.equal(profile.serverProgress.missions,undefined);assert.equal(profile.serverEconomy,undefined);
 assert.equal(profile.stats.wins,0);assert.equal(profile.stats.losses,0);assert.equal(profile.stats.draws,0);
 assert.equal(ratingAccount(f,'alice').games,0);
});
