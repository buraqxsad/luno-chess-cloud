'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {STARTER,CARDS}=require('../rules-v1/dist/src/model');
const {UNLOCK_PATH,applyCompetitiveProgression,progressionSummary,reconcileCompetitiveProgression}=require('../lib/battle-v1-progression');
const {applyV1Rating}=require('../lib/battle-v1-rating');
const {fixture}=require('./helpers/battle-v1-fixture');

function match(reason,winner='b',overrides={}){
  return {protocolVersion:'LUNO_BATTLE_V1',matchId:'bv1_'+('c'.repeat(32)),rated:true,
    players:{w:{uid:'alice',bot:false},b:{uid:'bob',bot:false}},
    result:{reason,winner,finishedAt:1000},battle:{rules:{ply:12}},
    metrics:{'player:w:moveCount':6,'player:b:moveCount':6},ratingAtStart:{w:0,b:0},...overrides};
}

for(const reason of ['checkmate','resign'])test(`${reason}: meaningful winner and loser both progress`,()=>{
  for(const uid of ['alice','bob']){
    const account={entitlements:[...STARTER]};
    const result=applyCompetitiveProgression(account,match(reason),uid);
    assert.equal(result.qualified,true);assert.equal(result.meaningfulMatches,1);
    assert.deepEqual(result.unlocked,['mine']);
  }
});

for(const reason of ['stalemate','seventy_five_moves','fivefold'])test(`${reason}: meaningful draw progresses both players`,()=>{
  for(const uid of ['alice','bob'])assert.equal(applyCompetitiveProgression({entitlements:[...STARTER]},match(reason,null),uid).qualified,true);
});

test('timeout: only the sufficiently participating winner progresses, never the clock-expired loser',()=>{
  for(const winner of ['w','b']){
    const m=match('timeout',winner);
    for(const [uid,side] of [['alice','w'],['bob','b']]){
      const account={entitlements:[...STARTER]},r=applyCompetitiveProgression(account,m,uid);
      assert.equal(r.qualified,side===winner);
      assert.equal(r.meaningfulMatches,side===winner?1:0);
    }
    const uid=winner==='w'?'alice':'bob';
    assert.equal(applyCompetitiveProgression({entitlements:[...STARTER]},match('timeout',winner,{metrics:{['player:'+winner+':moveCount']:3}}),uid).qualified,false);
    assert.equal(applyCompetitiveProgression({entitlements:[...STARTER]},match('timeout',winner,{metrics:{['player:'+winner+':moveCount']:4}}),uid).qualified,true);
    assert.equal(applyCompetitiveProgression({entitlements:[...STARTER]},match('timeout',winner,{battle:{rules:{ply:11}}}),uid).qualified,false);
  }
  for(const uid of ['alice','bob'])assert.equal(applyCompetitiveProgression({entitlements:[...STARTER]},match('timeout',null),uid).qualified,false);
});

for(const reason of ['protocol-upgrade','account-deleted','afk','disconnect','connection-lost','abandoned','cancelled','unknown'])
  test(`${reason}: administrative or unrecognized result cannot grant match progress`,()=>{
    for(const uid of ['alice','bob']){
      const r=applyCompetitiveProgression({entitlements:[...STARTER]},match(reason),uid);
      assert.equal(r.qualified,false);assert.equal(r.meaningfulMatches,0);assert.deepEqual(r.unlocked,[]);
    }
  });

test('timeout rating receipt retries cannot award extra progress; rated outcome remains unchanged',()=>{
  const account={rating:0,entitlements:[...STARTER]},m=match('timeout','b');
  const first=applyV1Rating(account,m,'bob');
  assert.equal(first.outcome,'win');assert.equal(first.progression.qualified,true);
  const snapshot=structuredClone(account);
  for(let retry=0;retry<10;retry++)assert.deepEqual(applyV1Rating(account,m,'bob'),first);
  assert.deepEqual(account,snapshot);
  const loser={rating:0,entitlements:[...STARTER]},lost=applyV1Rating(loser,m,'alice');
  assert.equal(lost.outcome,'loss');assert.equal(lost.progression.qualified,false);
});

test('surviving inner rating receipt cannot increment progression when the outer receipt is missing',()=>{
  for(const winner of ['w','b',null]){
    const account={rating:0,entitlements:[...STARTER]},m=match(winner===null?'stalemate':'resign',winner);
    const first=applyV1Rating(account,m,'alice');
    assert.equal(first.progression.meaningfulMatches,1);
    delete account.ratingSettlements[m.matchId];
    const protectedState=()=>({rating:account.rating,games:account.games,ratingProfile:account.ratingProfile,
      competitiveProgression:account.competitiveProgression,entitlements:account.entitlements});
    const before=structuredClone(protectedState());
    const recovered=applyV1Rating(account,m,'alice');
    assert.equal(recovered.applied,false);assert.equal(recovered.idempotent,true);
    assert.equal(recovered.progression.meaningfulMatches,1);
    assert.deepEqual(recovered.progression.unlocked,[]);
    assert.deepEqual(protectedState(),before);
    for(let retry=0;retry<10;retry++)assert.deepEqual(applyV1Rating(account,m,'alice'),recovered);
    assert.deepEqual(protectedState(),before);
  }
});

test('summary cannot call a due-but-missing card complete at 20 matches',()=>{
  const account={entitlements:[...STARTER],competitiveProgression:{version:1,meaningfulMatches:20}};
  const before=structuredClone(account),summary=progressionSummary(account);
  assert.equal(summary.nextUnlock.card,'mine');assert.equal(summary.nextUnlock.matches,1);
  assert.equal(summary.nextUnlock.owned,false);
  assert.deepEqual(summary.nextUnlock.requirements.anyOf,[
    {kind:'ranked_matches',current:20,target:1},{kind:'welcome_claim',current:0,target:1},
  ]);
  assert(summary.path.some(t=>!t.owned));assert.deepEqual(account,before);
  const repair=reconcileCompetitiveProgression(account);
  assert.equal(repair.meaningfulMatches,20);assert.equal(repair.nextUnlock,null);
  assert.deepEqual(new Set(account.entitlements),new Set(Object.keys(CARDS)));
  assert.deepEqual(repair.unlocked,UNLOCK_PATH.map(t=>t.card));
  assert.deepEqual(reconcileCompetitiveProgression(account).unlocked,[]);
});

test('repair uses only stored integer server progress and preserves earned entitlements and unrelated state',()=>{
  for(const count of [undefined,-1,1.5,'20',NaN,Infinity]){
    const account={entitlements:[...STARTER,'board_seal'],competitiveProgression:{version:1,meaningfulMatches:count},
      rating:123,games:99,paidClaims:{historic:true},gold:456,gems:789};
    const repair=reconcileCompetitiveProgression(account);
    assert.equal(repair.meaningfulMatches,0);assert.deepEqual(repair.unlocked,[]);
    assert(account.entitlements.includes('board_seal'));assert.equal(account.rating,123);
    assert.equal(account.games,99);assert.equal(account.gold,456);assert.equal(account.gems,789);
    assert.deepEqual(account.paidClaims,{historic:true});
  }
});

for(const count of [0,1,6,19,20,99])test(`getDeck atomically repairs missing earned entitlements at stored count ${count}`,async()=>{
  const f=fixture();await f.enable();await f.api.migrate('alice');
  const record=structuredClone(f.read('battleV1Accounts/alice')),account=JSON.parse(record.accountJson);
  account.entitlements=[...STARTER,'board_seal'];account.competitiveProgression={version:1,meaningfulMatches:count};
  account.rating=345;account.games=42;account.paidClaims={historic:true};
  f.write('battleV1Accounts/alice',{...record,accountJson:JSON.stringify(account)});
  const profileBefore=structuredClone(f.read('users/alice'));
  const first=await f.api.getBattleV1Deck(f.context('alice',{client:f.client}));
  const total=Math.min(20,count);
  assert.equal(first.progression.meaningfulMatches,total);
  for(const t of first.progression.path)assert.equal(t.owned,t.matches<=total||t.card==='board_seal');
  const next=UNLOCK_PATH.find(t=>!first.entitlements.includes(t.card));
  assert.deepEqual(first.progression.nextUnlock,next?first.progression.path.find(t=>t.card===next.card):null);
  if(next)assert(next.matches>total);
  const persisted=JSON.parse(f.read('battleV1Accounts/alice').accountJson);
  assert.deepEqual(persisted.entitlements,first.entitlements);assert.equal(persisted.games,42);assert.equal(persisted.rating,345);
  assert.deepEqual(persisted.paidClaims,{historic:true});assert.deepEqual(f.read('users/alice'),profileBefore);
  assert.deepEqual(await f.api.getBattleV1Deck(f.context('alice',{client:f.client})),first);
  assert.deepEqual(JSON.parse(f.read('battleV1Accounts/alice').accountJson),persisted);
});

test('actual authoritative clock expiry after 12 legal plies settles progress only for the participating winner',async()=>{
  const f=fixture();await f.enable();await f.api.migrate('alice');await f.api.migrate('bob');
  const id='bv1_'+('e'.repeat(32));
  let m=await f.api.create(id,{uid:'alice',name:'alice',bot:false},{uid:'bob',name:'bob',bot:false},STARTER,STARTER,true,{w:0,b:0});
  const moves=['a2a3','a7a6','b2b3','b7b6','c2c3','c7c6','d2d3','d7d6','e2e3','e7e6','f2f3','f7f6'];
  for(let ply=0;ply<moves.length;ply++){
    const uid=ply%2?'bob':'alice';
    for(const intent of [...(m.battle.rules.phase==='card'?[{type:'pass'}]:[]),{type:'move',uci:moves[ply]}]){
      await f.api.submitBattleV1Action(f.context(uid,{protocolVersion:'LUNO_BATTLE_V1',matchId:id,expectedStateVersion:m.stateVersion,
        actionId:`a${m.stateVersion}_timeout-test`,intent}));
      m=await f.api.load(id,uid);
    }
  }
  assert.equal(m.clock.activeSide,'w');assert.equal(m.metrics['player:w:moveCount'],6);assert.equal(m.metrics['player:b:moveCount'],6);
  f.setTime(m.clock.startedAt+m.clock.w+1);
  await f.api.getBattleV1(f.context('bob',{matchId:id,protocolVersion:'LUNO_BATTLE_V1'}));
  m=await f.api.load(id,'bob');assert.equal(m.result.reason,'timeout');assert.equal(m.result.winner,'b');assert.equal(m.settlementStatus,'complete');
  const alice=await f.api.getBattleV1Deck(f.context('alice',{client:f.client}));
  const bob=await f.api.getBattleV1Deck(f.context('bob',{client:f.client}));
  assert.equal(alice.progression.meaningfulMatches,0);assert.equal(bob.progression.meaningfulMatches,1);
  assert(!alice.entitlements.includes('mine'));assert(bob.entitlements.includes('mine'));
  const before=structuredClone(f.read('battleV1Accounts'));
  await f.api.settle(id,'bob');assert.deepEqual(f.read('battleV1Accounts'),before);
});
