'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {applyV1Rating}=require('../lib/battle-v1-rating');
const {applyRankedSettlement,ARENAS}=require('../lib/ranked');
const {battleV1RankFromAccount,validBattleV1Rating}=require('../lib/battle-v1-public-profile');
const {authority,protocol}=require('../lib/battle-v1');
const {STARTER}=require('../rules-v1/dist/src/model.js');

const uid='playerA',opponent='playerB',id='bv1_21421421421421421421421421421422',at=Date.UTC(2026,9,8);
function match(rating,winner='w'){
 const m=authority.createServerMatch(id,{uid,name:'Player A',bot:false},{uid:opponent,name:'Player B',bot:false},STARTER,STARTER,at,true);
 m.ratingAtStart={w:rating,b:rating};
 return authority.finishMatch(m,{reason:'resign',winner,finishedAt:at+20000});
}
function account(rating){return {uid,migrationVersion:1,protocolVersion:protocol.PROTOCOL,rating,games:0,entitlements:[...STARTER]};}

for(const rating of [1000000000,999999999]){
 test(`new V1 win at ${rating} stays readable at the canonical public bound with exact receipts`,()=>{
  const value=account(rating),m=match(rating),receipt=applyV1Rating(value,m,uid);
  assert.equal(value.rating,1000000000);assert.equal(value.ratingProfile.trophies,1000000000);
  assert.equal(receipt.newTrophies,1000000000);assert.equal(receipt.trophyDelta,1000000000-rating);
  assert.equal(battleV1RankFromAccount(uid,{accountJson:JSON.stringify(value)}).trophies,1000000000);
  assert(validBattleV1Rating(uid,{uid,rating:value.rating,games:value.games,revision:1,protocolVersion:protocol.PROTOCOL}));
  const inner=Object.values(value.ratingProfile.serverProgress.rankedSettlements)[0],ledger=Object.values(value.ratingProfile.serverCompetition.ledger)[0];
  assert.equal(inner.newTrophies,receipt.newTrophies);assert.equal(inner.trophyDelta,receipt.trophyDelta);
  assert.equal(ledger.newTrophies,receipt.newTrophies);assert.equal(ledger.trophyDelta,receipt.trophyDelta);
  assert.equal(ledger.previousTrophies,rating);
  const snapshot=structuredClone(value);assert.deepEqual(applyV1Rating(value,m,uid),receipt);assert.deepEqual(value,snapshot);
 });
}

for(const winner of ['w','b',null]){
 test(`ordinary V1 rating remains identical to the prior formula: winner=${winner}`,()=>{
  const rating=1200,value=account(rating),m=match(rating,winner),outcome=winner==='w'?'win':winner==='b'?'loss':'draw';
  const priorProfile={uid,trophies:rating,arenaIdx:0,gold:0,gems:0,lvl:1,xp:0,stats:{}};
  const expected=applyRankedSettlement(priorProfile,{uid,matchId:id,outcome,opponentTrophies:rating,moveCount:0,at:m.result.finishedAt});
  const receipt=applyV1Rating(value,m,uid);
  for(const key of ['trophyDelta','previousTrophies','newTrophies','newArenaIdx','gold','xp','levelGold','newLevel','settledAt'])assert.deepEqual(receipt[key],expected[key]);
  assert.equal(value.rating,priorProfile.trophies);assert.deepEqual(value.ratingProfile,priorProfile);
  assert.doesNotThrow(()=>battleV1RankFromAccount(uid,{accountJson:JSON.stringify(value)}));
 });
}

test('legacy settlement calls retain their existing uncapped formula',()=>{
 const profile={uid,trophies:1000000000,arenaIdx:ARENAS.length-1,gold:0,lvl:1,xp:0,stats:{}};
 const receipt=applyRankedSettlement(profile,{uid,matchId:id,outcome:'win',opponentTrophies:1000000000,at});
 assert.equal(receipt.newTrophies,1000000000+ARENAS.at(-1).win);assert.equal(receipt.trophyDelta,ARENAS.at(-1).win);
});

test('previously committed V1 receipts are returned byte-for-byte without reapplying the new boundary policy',()=>{
 const value=account(900),receipt={matchId:id,outcome:'win',rated:true,trophyDelta:18,previousTrophies:882,newTrophies:900,settledAt:at,protocolVersion:protocol.PROTOCOL};
 value.ratingSettlements={[id]:receipt};const snapshot=structuredClone(value);
 assert.deepEqual(applyV1Rating(value,match(900),uid),receipt);assert.deepEqual(value,snapshot);
});
