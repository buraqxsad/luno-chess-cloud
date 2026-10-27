'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {openPassChest,idempotent,hash,sourceClaimKey,applyRewardClaim,starterProfile}=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');
const uid='pass_receipt_player',id='pass-recovery',operation='openPassChest:rare',at=1900000000000,leaseMs=120000;
const requestPath=`serverRequests/${uid}/${hash(id).slice(0,48)}`;
function context(requestId=id,chestId='rare'){return {uid,body:{chestId},requestId};}
function seed(chests=['rare','rare']){
  const profile=starterProfile(uid,'pass_receipt');profile.inventory.pendingChests=chests;
  return {users:{[uid]:profile}};
}
function claimKey(chestId='rare',requestId=id){return sourceClaimKey(uid,'pass_chest_reward','pass:'+chestId+':'+hash(requestId).slice(0,32));}
function staleClaim(data,extra={}){
  data.serverRequests={[uid]:{[hash(id).slice(0,48)]:{operation,status:'processing',ownerToken:'abandoned-owner',createdAt:at-leaseMs-1,startedAt:at-leaseMs-1,...extra}}};
  return data;
}

test('Pass chest commits inventory, reward and replayable opening receipt atomically',async t=>{
  t.mock.method(Date,'now',()=>at);
  const db=memoryDatabase(t,seed()),result=await openPassChest(context());
  const profile=db.read('users/'+uid),claim=profile.serverEconomy.claims[claimKey()];
  assert.equal(result.opened,true);assert.equal(profile.inventory.pendingChests.length,1);assert.equal(profile.stats.chestsOpened,1);
  assert.equal(profile.gold,1250+result.rewards.filter(r=>r.type==='gold').reduce((sum,r)=>sum+r.amount,0));
  assert.deepEqual(claim.passChestOpening.rewards,result.rewards);
  assert.equal(claim.passChestOpening.chestId,'rare');assert.equal(claim.passChestOpening.requestIdHash,hash(id));
  assert.equal(claim.passChestOpening.version,1);assert.deepEqual(claim.transactionIds,result.rewardTransactionIds);
  assert.ok(db.transactions.filter(tx=>tx.path==='users/'+uid).every(tx=>tx.applyLocally===false));
});

test('missing response cache replays exact drops without consuming another same-rarity chest',async t=>{
  const db=memoryDatabase(t,seed()),first=await openPassChest(context()),before=structuredClone(db.read('users/'+uid));
  db.write(requestPath,null);
  const replay=await openPassChest(context());
  assert.equal(replay.opened,false);assert.equal(replay.idempotent,true);
  assert.deepEqual(replay.rewards,first.rewards);assert.deepEqual(replay.rewardTransactionIds,first.rewardTransactionIds);
  assert.deepEqual(db.read('users/'+uid),before);
});

test('a lost cache-store response cannot cause a second inventory consumption',async t=>{
  const db=memoryDatabase(t,seed(),{beforeTransaction(path,count){if(path===requestPath&&count===2)throw new Error('cache-store-failed');}});
  await assert.rejects(openPassChest(context()),/cache-store-failed/);
  const before=structuredClone(db.read('users/'+uid));
  const replay=await openPassChest(context());
  assert.equal(replay.idempotent,true);assert.equal(replay.opened,false);assert.ok(replay.rewards.length>0);
  assert.deepEqual(db.read('users/'+uid),before);
});

test('the last consumed Pass chest still has a recoverable opening outcome',async t=>{
  const db=memoryDatabase(t,seed(['rare'])),first=await openPassChest(context());db.write(requestPath,null);
  const replay=await openPassChest(context());
  assert.deepEqual(replay.rewards,first.rewards);assert.equal(replay.opened,false);assert.equal(db.read('users/'+uid+'/stats/chestsOpened'),1);
});

test('a stale processing claim can be taken over before any chest was consumed',async t=>{
  t.mock.method(Date,'now',()=>at);
  const db=memoryDatabase(t,staleClaim(seed())),result=await openPassChest(context());
  assert.equal(result.opened,true);assert.equal(db.read('users/'+uid+'/stats/chestsOpened'),1);
  assert.notEqual(db.read(requestPath+'/ownerToken'),'abandoned-owner');assert.equal(db.read(requestPath+'/status'),'complete');
});

test('stale processing after a committed opening recovers the receipt rather than consuming again',async t=>{
  t.mock.method(Date,'now',()=>at);
  const db=memoryDatabase(t,seed()),first=await openPassChest(context()),before=structuredClone(db.read('users/'+uid));
  db.write(requestPath,staleClaim(seed()).serverRequests[uid][hash(id).slice(0,48)]);
  const replay=await openPassChest(context());
  assert.equal(replay.idempotent,true);assert.equal(replay.opened,false);assert.deepEqual(replay.rewards,first.rewards);
  assert.deepEqual(db.read('users/'+uid),before);
});

test('a receipt for another chest binds the request identity after cache loss',async t=>{
  const db=memoryDatabase(t,seed(['rare','common']));await openPassChest(context());db.write(requestPath,null);
  const before=structuredClone(db.read('users/'+uid));
  await assert.rejects(openPassChest(context(id,'common')),{code:'request-id-conflict'});
  assert.deepEqual(db.read('users/'+uid),before);
});

test('legacy completed gold claim without an opening outcome fails closed after cache loss',async t=>{
  const data=seed(),profile=data.users[uid];
  applyRewardClaim(profile,{uid,sourceType:'pass_chest_reward',sourceId:'pass:rare:'+hash(id).slice(0,32),reward:{gold:234},at});
  profile.stats.chestsOpened=1;
  const before=structuredClone(profile),db=memoryDatabase(t,data);
  await assert.rejects(openPassChest(context()),{code:'pass-chest-recovery-unavailable'});
  assert.deepEqual(db.read('users/'+uid),before);
});

test('distinct request identities consume distinct earned Pass chests normally',async t=>{
  const db=memoryDatabase(t,seed());
  assert.equal((await openPassChest(context('first'))).opened,true);
  assert.equal((await openPassChest(context('second'))).opened,true);
  assert.equal(db.read('users/'+uid+'/stats/chestsOpened'),2);
});

for(const startedAt of [at-leaseMs+1,at+10000,0])test(`processing claim with timestamp ${startedAt} cannot be prematurely recovered`,async t=>{
  t.mock.method(Date,'now',()=>at);
  const db=memoryDatabase(t,staleClaim(seed(),{startedAt,createdAt:startedAt})),before=structuredClone(db.read('users/'+uid));
  await assert.rejects(openPassChest(context()),{code:'request-in-progress'});
  assert.deepEqual(db.read('users/'+uid),before);assert.equal(db.read(requestPath+'/ownerToken'),'abandoned-owner');
});

for(const op of ['purchaseSoftItem:item','openChest:unknown','openPassChest:unknown'])test(`abandoned ${op} is not blanket re-executed`,async t=>{
  t.mock.method(Date,'now',()=>at);
  const db=memoryDatabase(t,staleClaim(seed(),{operation:op}));
  await assert.rejects(idempotent(uid,id,op,async()=>assert.fail('unsafe work must not run')),{code:'request-in-progress'});
  assert.equal(db.read(requestPath+'/ownerToken'),'abandoned-owner');
});

for(const kind of ['common','rare','legendary','royal'])test(`${kind} Pass chest replays all drops from its durable receipt`,async t=>{
  const db=memoryDatabase(t,seed([kind,kind])),first=await openPassChest(context(id,kind));db.write(requestPath,null);
  const before=structuredClone(db.read('users/'+uid)),replay=await openPassChest(context(id,kind));
  assert.deepEqual(replay.rewards,first.rewards);assert.deepEqual(replay.rewardTransactionIds,first.rewardTransactionIds);
  assert.equal(replay.opened,false);assert.deepEqual(db.read('users/'+uid),before);
});

test('cached replay returns current account balances rather than its old response snapshot',async t=>{
  const db=memoryDatabase(t,seed()),first=await openPassChest(context());
  db.write('users/'+uid+'/gold',8888);db.write('users/'+uid+'/gems',222);
  const before=structuredClone(db.read('users/'+uid)),replay=await openPassChest(context());
  assert.equal(replay.state.gold,8888);assert.equal(replay.state.gems,222);
  assert.deepEqual(replay.rewards,first.rewards);assert.deepEqual(db.read('users/'+uid),before);
});

test('a legacy startedAt-less processing claim safely recovers from createdAt',async t=>{
  t.mock.method(Date,'now',()=>at);
  const data=staleClaim(seed());delete data.serverRequests[uid][hash(id).slice(0,48)].startedAt;
  const db=memoryDatabase(t,data),result=await openPassChest(context());
  assert.equal(result.opened,true);assert.equal(db.read(requestPath+'/attempts'),1);
});

test('takeover retries cannot replace a new active request owner',async t=>{
  t.mock.method(Date,'now',()=>at);
  const replacement={operation,status:'processing',ownerToken:'new-owner',startedAt:at,createdAt:at};
  const db=memoryDatabase(t,staleClaim(seed()),{retry(path,count,update,next,{write}){
    if(path===requestPath&&count===1){write(path,replacement);return update(structuredClone(replacement));}return next;
  }});
  const before=structuredClone(db.read('users/'+uid));
  await assert.rejects(openPassChest(context()),{code:'request-in-progress'});
  assert.deepEqual(db.read(requestPath),replacement);assert.deepEqual(db.read('users/'+uid),before);
});

test('profile owner mismatch is rejected without consuming inventory',async t=>{
  const data=seed();data.users[uid].uid='another-player';const db=memoryDatabase(t,data),before=structuredClone(db.read('users/'+uid));
  await assert.rejects(openPassChest(context()),{code:'profile-owner-mismatch'});
  assert.deepEqual(db.read('users/'+uid),before);
});

test('deletion while taking over a stale claim suppresses work and cleans only its claim',async t=>{
  t.mock.method(Date,'now',()=>at);
  const db=memoryDatabase(t,staleClaim(seed()),{afterTransaction(path,count,{write}){
    if(path===requestPath&&count===1)write('accountDeletions/'+hash(uid),{status:'processing'});
  }});
  const before=structuredClone(db.read('users/'+uid));
  await assert.rejects(openPassChest(context()),{code:'account-deletion-in-progress'});
  assert.equal(db.read(requestPath),null);assert.deepEqual(db.read('users/'+uid),before);
});

test('cached Pass opening cannot be replayed for a deleted account',async t=>{
  const db=memoryDatabase(t,seed());await openPassChest(context());
  db.write('deletedAccounts/'+hash(uid),{deletedAt:at});
  await assert.rejects(openPassChest(context()),{code:'account-deleted'});
});

test('a replay whose profile disappeared fails instead of returning stale account state',async t=>{
  const db=memoryDatabase(t,seed());await openPassChest(context());db.write('users/'+uid,null);
  await assert.rejects(openPassChest(context()),{code:'profile-not-found'});
  assert.equal(db.read('users/'+uid),null);
});

const corruptions={
  version:claim=>claim.passChestOpening.version=2,
  requestHash:claim=>claim.passChestOpening.requestIdHash='wrong',
  ownerHash:claim=>claim.passChestOpening.uidHash=hash('another'),
  chestKind:claim=>claim.passChestOpening.chestId='royal',
  emptyDrops:claim=>claim.passChestOpening.rewards=[],
  negativeDrop:claim=>claim.passChestOpening.rewards[0].amount=-1,
  unknownDrop:claim=>claim.passChestOpening.rewards[0].type='cash',
  missingCollectibleId:claim=>claim.passChestOpening.rewards=[{type:'card',amount:1}],
  goldMismatch:claim=>claim.reward.gold++,
  sourceMismatch:claim=>claim.sourceId='wrong',
  receiptKey:claim=>claim.idempotencyKey='wrong',
  timestamp:claim=>claim.claimedAt=0,
  transactionIds:claim=>claim.transactionIds=[],
  malformedOpening:claim=>claim.passChestOpening='not-a-record',
};
for(const [name,corrupt] of Object.entries(corruptions))test(`malformed receipt ${name} cannot consume another chest or grant any reward`,async t=>{
  const db=memoryDatabase(t,seed());await openPassChest(context());db.write(requestPath,null);
  const profile=db.read('users/'+uid);corrupt(profile.serverEconomy.claims[claimKey()]);
  const before=structuredClone(profile);
  await assert.rejects(openPassChest(context()),{code:'pass-chest-receipt-invalid'});
  assert.deepEqual(db.read('users/'+uid),before);
});

for(const [name,corrupt] of [['economy',profile=>profile.serverEconomy=[]],['claims',profile=>profile.serverEconomy.claims='invalid']]){
  test(`malformed ${name} root fails closed before a fresh opening`,async t=>{
    const data=seed();data.users[uid].serverEconomy={claims:{}};corrupt(data.users[uid]);
    const db=memoryDatabase(t,data),before=structuredClone(db.read('users/'+uid));
    await assert.rejects(openPassChest(context()),{code:'pass-chest-receipt-invalid'});
    assert.deepEqual(db.read('users/'+uid),before);
  });
}
