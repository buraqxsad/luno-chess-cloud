'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {openChest,hash,sourceClaimKey,starterProfile,CHEST_CATALOG,PASS_CHEST_RECOVERY_MS}=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');
const uid='shop_receipt_player',id='shop-recovery',at=1900000000000;
const requestPath=`serverRequests/${uid}/${hash(id).slice(0,48)}`;
function context(requestId=id,chestId='rare'){return {uid,body:{chestId},requestId};}
function sourceId(chestId='rare',requestId=id){return chestId+':'+hash(requestId).slice(0,32);}
function purchaseKey(chestId='rare',requestId=id){return sourceClaimKey(uid,'chest_purchase',sourceId(chestId,requestId));}
function seed(){const profile=starterProfile(uid,'shop_receipt');profile.gold=30000;profile.gems=3000;return {users:{[uid]:profile}};}
function stale(data,kind='rare'){
  data.serverRequests={[uid]:{[hash(id).slice(0,48)]:{operation:'openChest:'+kind,status:'processing',ownerToken:'abandoned-owner',createdAt:at-PASS_CHEST_RECOVERY_MS-1,startedAt:at-PASS_CHEST_RECOVERY_MS-1}}};
  return data;
}

for(const kind of Object.keys(CHEST_CATALOG)){
  test(`${kind} shop chest spends once and stores exact inventory drops`,async t=>{
    const db=memoryDatabase(t,seed()),result=await openChest(context(id,kind));
    const profile=db.read('users/'+uid),receipt=profile.serverEconomy.purchases[purchaseKey(kind)],definition=CHEST_CATALOG[kind];
    assert.equal(result.opened,true);assert.equal(profile.stats.chestsOpened,1);
    const gold=result.rewards.filter(reward=>reward.type==='gold').reduce((sum,reward)=>sum+reward.amount,0);
    assert.equal(profile.gold,30000-(definition.currency==='gold'?definition.price:0)+gold);
    assert.equal(profile.gems,3000-(definition.currency==='gems'?definition.price:0));
    assert.deepEqual(receipt.outcome.rewards,result.rewards);assert.equal(receipt.transactionId,result.transactionId);
    assert.deepEqual(receipt.outcome.rewardTransactionIds,result.rewardTransactionIds);
  });
  test(`${kind} shop chest survives cache loss with no second debit or reroll`,async t=>{
    const db=memoryDatabase(t,seed()),first=await openChest(context(id,kind));db.write(requestPath,null);
    const before=structuredClone(db.read('users/'+uid)),replay=await openChest(context(id,kind));
    assert.equal(replay.opened,false);assert.equal(replay.idempotent,true);
    assert.deepEqual(replay.rewards,first.rewards);assert.deepEqual(replay.rewardTransactionIds,first.rewardTransactionIds);
    assert.deepEqual(db.read('users/'+uid),before);
  });
}

test('stale processing before a shop purchase can recover safely',async t=>{
  t.mock.method(Date,'now',()=>at);
  const db=memoryDatabase(t,stale(seed())),result=await openChest(context());
  assert.equal(result.opened,true);assert.equal(db.read('users/'+uid+'/stats/chestsOpened'),1);
});
test('stale processing after a committed shop purchase replays without spending again',async t=>{
  t.mock.method(Date,'now',()=>at);
  const db=memoryDatabase(t,seed()),first=await openChest(context());
  db.write(requestPath,stale(seed()).serverRequests[uid][hash(id).slice(0,48)]);
  const before=structuredClone(db.read('users/'+uid)),replay=await openChest(context());
  assert.deepEqual(replay.rewards,first.rewards);assert.deepEqual(db.read('users/'+uid),before);
});
test('a lost cache completion response preserves the paid opening receipt',async t=>{
  const db=memoryDatabase(t,seed(),{beforeTransaction(path,count){if(path===requestPath&&count===2)throw new Error('cache-store-failed');}});
  await assert.rejects(openChest(context()),/cache-store-failed/);
  const before=structuredClone(db.read('users/'+uid)),replay=await openChest(context());
  assert.equal(replay.idempotent,true);assert.ok(replay.rewards.length>0);assert.deepEqual(db.read('users/'+uid),before);
});
test('cached shop replay returns current balances instead of the original snapshot',async t=>{
  const db=memoryDatabase(t,seed()),first=await openChest(context());
  db.write('users/'+uid+'/gold',27);db.write('users/'+uid+'/gems',8);
  const before=structuredClone(db.read('users/'+uid)),replay=await openChest(context());
  assert.equal(replay.state.gold,27);assert.equal(replay.state.gems,8);assert.deepEqual(replay.rewards,first.rewards);
  assert.deepEqual(db.read('users/'+uid),before);
});

test('cached paid replay reconstructs canonical confirmation from its durable receipt',async t=>{
  const db=memoryDatabase(t,seed()),first=await openChest(context());
  db.write(requestPath+'/result',{ok:false,opened:true,chestId:'common',state:{gold:999999},rewards:[]});
  const before=structuredClone(db.read('users/'+uid)),replay=await openChest(context());
  assert.equal(replay.ok,true);assert.equal(replay.chestId,'rare');assert.equal(replay.opened,false);
  assert.deepEqual(replay.rewards,first.rewards);assert.equal(replay.transactionId,first.transactionId);
  assert.deepEqual(replay.rewardTransactionIds,first.rewardTransactionIds);assert.deepEqual(db.read('users/'+uid),before);
});
test('receipt replay works even when the player can no longer afford a new chest',async t=>{
  const db=memoryDatabase(t,seed()),first=await openChest(context());db.write(requestPath,null);db.write('users/'+uid+'/gold',0);
  const replay=await openChest(context());assert.equal(replay.state.gold,0);assert.deepEqual(replay.rewards,first.rewards);
});
test('cache loss cannot change an old request into a different chest purchase',async t=>{
  const db=memoryDatabase(t,seed());await openChest(context());db.write(requestPath,null);
  const before=structuredClone(db.read('users/'+uid));
  await assert.rejects(openChest(context(id,'common')),{code:'request-id-conflict'});
  assert.deepEqual(db.read('users/'+uid),before);
});
test('profile owner mismatch cannot spend another account balance',async t=>{
  const data=seed();data.users[uid].uid='foreign';const db=memoryDatabase(t,data),before=structuredClone(db.read('users/'+uid));
  await assert.rejects(openChest(context()),{code:'profile-owner-mismatch'});assert.deepEqual(db.read('users/'+uid),before);
});
test('billing review blocks fresh spending but not read-only recovery of an already committed chest',async t=>{
  const db=memoryDatabase(t,seed()),first=await openChest(context());db.write(requestPath,null);
  db.write('users/'+uid+'/serverEconomy/billingReviewRequired',true);
  const before=structuredClone(db.read('users/'+uid)),replay=await openChest(context());
  assert.deepEqual(replay.rewards,first.rewards);assert.deepEqual(db.read('users/'+uid),before);
  await assert.rejects(openChest(context('fresh')),{code:'billing-review-required'});
});
test('distinct identities are distinct intended shop purchases',async t=>{
  const db=memoryDatabase(t,seed());await openChest(context('first'));await openChest(context('second'));
  assert.equal(db.read('users/'+uid+'/stats/chestsOpened'),2);
});

for(const startedAt of [at-PASS_CHEST_RECOVERY_MS+1,at+10000,0])test(`paid processing timestamp ${startedAt} cannot be prematurely recovered`,async t=>{
  t.mock.method(Date,'now',()=>at);
  const data=stale(seed()),claim=data.serverRequests[uid][hash(id).slice(0,48)];claim.startedAt=startedAt;claim.createdAt=startedAt;
  const db=memoryDatabase(t,data),before=structuredClone(db.read('users/'+uid));
  await assert.rejects(openChest(context()),{code:'request-in-progress'});
  assert.deepEqual(db.read('users/'+uid),before);assert.equal(db.read(requestPath+'/ownerToken'),'abandoned-owner');
});

test('cached paid replay does not return a deleted profile snapshot',async t=>{
  const db=memoryDatabase(t,seed());await openChest(context());db.write('users/'+uid,null);
  await assert.rejects(openChest(context()),{code:'profile-not-found'});assert.equal(db.read('users/'+uid),null);
});

test('cached paid replay checks current profile ownership',async t=>{
  const db=memoryDatabase(t,seed());await openChest(context());db.write('users/'+uid+'/uid','foreign');
  const before=structuredClone(db.read('users/'+uid));
  await assert.rejects(openChest(context()),{code:'profile-owner-mismatch'});assert.deepEqual(db.read('users/'+uid),before);
});

test('an orphaned gold reward claim cannot become another chest purchase',async t=>{
  const db=memoryDatabase(t,seed());await openChest(context());db.write(requestPath,null);
  db.write('users/'+uid+'/serverEconomy/purchases/'+purchaseKey(),null);const before=structuredClone(db.read('users/'+uid));
  await assert.rejects(openChest(context()),{code:'chest-purchase-receipt-invalid'});assert.deepEqual(db.read('users/'+uid),before);
});

test('malformed economy root cannot be reset into a fresh paid opening',async t=>{
  const data=seed();data.users[uid].serverEconomy=[];const db=memoryDatabase(t,data),before=structuredClone(db.read('users/'+uid));
  await assert.rejects(openChest(context()),{code:'chest-purchase-receipt-invalid'});assert.deepEqual(db.read('users/'+uid),before);
});

const corruptions={
  receiptOwner:(profile,receipt)=>receipt.uid='foreign',
  receiptSource:(profile,receipt)=>receipt.sourceId='wrong',
  receiptKey:(profile,receipt)=>receipt.idempotencyKey='wrong',
  receiptItem:(profile,receipt)=>receipt.itemId='common',
  receiptType:(profile,receipt)=>receipt.itemType='skin',
  receiptPrice:(profile,receipt)=>receipt.price=-1,
  receiptCurrency:(profile,receipt)=>receipt.currency='cash',
  receiptTime:(profile,receipt)=>receipt.purchasedAt=0,
  receiptTransaction:(profile,receipt)=>receipt.transactionId='foreign',
  receiptOutcome:(profile,receipt)=>receipt.outcome=null,
  emptyDrops:(profile,receipt)=>receipt.outcome.rewards=[],
  invalidDrop:(profile,receipt)=>receipt.outcome.rewards[0].amount=-1,
  unknownDrop:(profile,receipt)=>receipt.outcome.rewards[0].type='cash',
  missingCollectibleId:(profile,receipt)=>receipt.outcome.rewards=[{type:'card',amount:1}],
  missingRewardIds:(profile,receipt)=>receipt.outcome.rewardTransactionIds=[],
  missingSpendLedger:(profile,receipt)=>delete profile.serverEconomy.ledger[receipt.transactionId],
  spendAmount:(profile,receipt)=>profile.serverEconomy.ledger[receipt.transactionId].amount=1,
  spendOwner:(profile,receipt)=>profile.serverEconomy.ledger[receipt.transactionId].uid='foreign',
  missingRewardClaim:profile=>delete profile.serverEconomy.claims[sourceClaimKey(uid,'chest_reward',sourceId())],
  rewardMismatch:profile=>profile.serverEconomy.claims[sourceClaimKey(uid,'chest_reward',sourceId())].reward.gold++,
  duplicateRewardIds:(profile,receipt)=>{
    receipt.outcome.rewardTransactionIds.push(receipt.outcome.rewardTransactionIds[0]);
    profile.serverEconomy.claims[sourceClaimKey(uid,'chest_reward',sourceId())].transactionIds=receipt.outcome.rewardTransactionIds.slice();
  },
  missingRewardLedger:(profile,receipt)=>delete profile.serverEconomy.ledger[receipt.outcome.rewardTransactionIds[0]],
  rewardLedgerOwner:(profile,receipt)=>profile.serverEconomy.ledger[receipt.outcome.rewardTransactionIds[0]].uid='foreign',
  rewardLedgerDelta:(profile,receipt)=>profile.serverEconomy.ledger[receipt.outcome.rewardTransactionIds[0]].newBalance++,
  rewardLedgerTime:(profile,receipt)=>profile.serverEconomy.ledger[receipt.outcome.rewardTransactionIds[0]].createdAt++,
};
for(const [name,corrupt] of Object.entries(corruptions))test(`malformed shop receipt ${name} fails closed without spending or granting`,async t=>{
  const db=memoryDatabase(t,seed());await openChest(context());db.write(requestPath,null);
  const profile=db.read('users/'+uid);corrupt(profile,profile.serverEconomy.purchases[purchaseKey()]);
  const before=structuredClone(profile);
  await assert.rejects(openChest(context()),{code:'chest-purchase-receipt-invalid'});
  assert.deepEqual(db.read('users/'+uid),before);
});
for(const root of ['purchases','ledger','claims'])test(`malformed economy ${root} root is not reset into a second purchase`,async t=>{
  const db=memoryDatabase(t,seed());await openChest(context());db.write(requestPath,null);
  db.write('users/'+uid+'/serverEconomy/'+root,'invalid');const before=structuredClone(db.read('users/'+uid));
  await assert.rejects(openChest(context()),{code:'chest-purchase-receipt-invalid'});assert.deepEqual(db.read('users/'+uid),before);
});
