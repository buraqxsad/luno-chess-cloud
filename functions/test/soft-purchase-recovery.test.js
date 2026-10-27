'use strict';

const test=require('node:test'),assert=require('node:assert/strict');
const {purchaseSoftItem,SOFT_ITEM_CATALOG,softItemOwned,starterProfile,sourceClaimKey,hash,idempotent,PASS_CHEST_RECOVERY_MS}=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');
const uid='permanent_purchase_player',id='permanent-purchase',at=1900000000000,item='piece_set:roma';
const requestPath=`serverRequests/${uid}/${hash(id).slice(0,48)}`;
const receiptKey=itemId=>sourceClaimKey(uid,'soft_purchase',itemId);
function seed(){const profile=starterProfile(uid,'permanent_shop');profile.gold=100000;profile.gems=100000;return {users:{[uid]:profile}};}
function context(requestId=id,itemId=item){return {uid,requestId,body:{itemId}};}
function stale(data,operation='purchaseSoftItem:'+item,startedAt=at-PASS_CHEST_RECOVERY_MS-1){
  data.serverRequests={[uid]:{[hash(id).slice(0,48)]:{operation,status:'processing',ownerToken:'abandoned-owner',startedAt,createdAt:startedAt}}};return data;
}

for(const [itemId,definition] of Object.entries(SOFT_ITEM_CATALOG).filter(([,value])=>!value.seasonScoped)){
  test(`${itemId} keeps permanent ownership and spends at most once after cache loss`,async t=>{
    const data=seed(),alreadyOwned=softItemOwned(data.users[uid],definition),db=memoryDatabase(t,data);
    if(alreadyOwned){
      const before=structuredClone(db.read('users/'+uid));
      await assert.rejects(purchaseSoftItem(context(id,itemId)),{code:'already-owned'});
      assert.deepEqual(db.read('users/'+uid),before);return;
    }
    const first=await purchaseSoftItem(context(id,itemId)),profile=db.read('users/'+uid),receipt=profile.serverEconomy.purchases[receiptKey(itemId)];
    assert.equal(first.purchased,true);assert.equal(profile[definition.currency],100000-definition.price);
    assert.equal(softItemOwned(structuredClone(profile),definition),true);
    assert.deepEqual(first.grant,definition.grant);assert.equal(receipt.requestIdHash,hash(id));
    db.write(requestPath,null);const before=structuredClone(db.read('users/'+uid)),replay=await purchaseSoftItem(context(id,itemId));
    assert.equal(replay.purchased,false);assert.equal(replay.idempotent,true);assert.equal(replay.transactionId,first.transactionId);
    assert.deepEqual(replay.grant,first.grant);assert.deepEqual(db.read('users/'+uid),before);
  });
}

test('stale permanent purchase can resume before its profile transaction',async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,stale(seed()));
  const result=await purchaseSoftItem(context());assert.equal(result.purchased,true);assert.equal(db.read('users/'+uid+'/gems'),99520);
});
test('stale permanent purchase after commit replays without a second debit',async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,seed()),first=await purchaseSoftItem(context());
  db.write(requestPath,stale(seed()).serverRequests[uid][hash(id).slice(0,48)]);const before=structuredClone(db.read('users/'+uid));
  const replay=await purchaseSoftItem(context());assert.equal(replay.purchased,false);assert.equal(replay.transactionId,first.transactionId);
  assert.deepEqual(db.read('users/'+uid),before);
});
test('lost cache completion leaves an independently recoverable permanent receipt',async t=>{
  const db=memoryDatabase(t,seed(),{beforeTransaction(path,count){if(path===requestPath&&count===2)throw new Error('cache-store-failed');}});
  await assert.rejects(purchaseSoftItem(context()),/cache-store-failed/);const before=structuredClone(db.read('users/'+uid));
  const replay=await purchaseSoftItem(context());assert.equal(replay.idempotent,true);assert.deepEqual(db.read('users/'+uid),before);
});
test('cached permanent replay reconstructs confirmation and reads fresh balance and selection',async t=>{
  const db=memoryDatabase(t,seed()),first=await purchaseSoftItem(context());
  db.write(requestPath+'/result',{ok:false,purchased:true,itemId:'piece_set:ice',state:{gems:100000}});
  db.write('users/'+uid+'/gems',7);db.write('users/'+uid+'/inventory/activePieceSet','std');const before=structuredClone(db.read('users/'+uid));
  const replay=await purchaseSoftItem(context());assert.equal(replay.ok,true);assert.equal(replay.itemId,item);assert.equal(replay.purchased,false);
  assert.equal(replay.state.gems,7);assert.equal(replay.state.inventory.activePieceSet,'std');assert.equal(replay.transactionId,first.transactionId);
  assert.deepEqual(db.read('users/'+uid),before);
});
test('read-only permanent replay remains available at zero balance during billing review',async t=>{
  const db=memoryDatabase(t,seed()),first=await purchaseSoftItem(context());db.write(requestPath,null);
  db.write('users/'+uid+'/gems',0);db.write('users/'+uid+'/serverEconomy/billingReviewRequired',true);const before=structuredClone(db.read('users/'+uid));
  const replay=await purchaseSoftItem(context());assert.equal(replay.transactionId,first.transactionId);assert.equal(replay.state.gems,0);
  assert.deepEqual(db.read('users/'+uid),before);await assert.rejects(purchaseSoftItem(context('new','piece_set:ice')),{code:'billing-review-required'});
});
test('a new request for an already purchased permanent item does not repurchase or reactivate it',async t=>{
  const db=memoryDatabase(t,seed()),first=await purchaseSoftItem(context());db.write('users/'+uid+'/inventory/activePieceSet','std');
  const before=structuredClone(db.read('users/'+uid)),replay=await purchaseSoftItem(context('new'));
  assert.equal(replay.transactionId,first.transactionId);assert.equal(replay.state.inventory.activePieceSet,'std');assert.deepEqual(db.read('users/'+uid),before);
});
test('a committed request cannot change its permanent product after cache loss',async t=>{
  const db=memoryDatabase(t,seed());await purchaseSoftItem(context());db.write(requestPath,null);const before=structuredClone(db.read('users/'+uid));
  await assert.rejects(purchaseSoftItem(context(id,'piece_set:ice')),{code:'request-id-conflict'});assert.deepEqual(db.read('users/'+uid),before);
});
test('profile owner mismatch cannot spend another player balance',async t=>{
  const data=seed();data.users[uid].uid='foreign';const db=memoryDatabase(t,data),before=structuredClone(db.read('users/'+uid));
  await assert.rejects(purchaseSoftItem(context()),{code:'profile-owner-mismatch'});assert.deepEqual(db.read('users/'+uid),before);
});
test('cached permanent replay does not return an absent profile',async t=>{
  const db=memoryDatabase(t,seed());await purchaseSoftItem(context());db.write('users/'+uid,null);
  await assert.rejects(purchaseSoftItem(context()),{code:'profile-not-found'});assert.equal(db.read('users/'+uid),null);
});
test('cached permanent replay cannot expose a replaced foreign profile',async t=>{
  const db=memoryDatabase(t,seed());await purchaseSoftItem(context());db.write('users/'+uid+'/uid','foreign');
  const before=structuredClone(db.read('users/'+uid));await assert.rejects(purchaseSoftItem(context()),{code:'profile-owner-mismatch'});
  assert.deepEqual(db.read('users/'+uid),before);
});
for(const state of ['processing','complete'])test(`cached permanent replay is gated during ${state} account deletion`,async t=>{
  const db=memoryDatabase(t,seed());await purchaseSoftItem(context());db.write('accountDeletions/'+hash(uid),{status:state});
  const before=structuredClone(db.read('users/'+uid));
  await assert.rejects(purchaseSoftItem(context()),{code:state==='processing'?'account-deletion-in-progress':'account-deleted'});
  assert.deepEqual(db.read('users/'+uid),before);
});
test('a validated legacy permanent receipt without request binding can replay without a charge',async t=>{
  const db=memoryDatabase(t,seed()),first=await purchaseSoftItem(context());db.write(requestPath,null);
  db.write('users/'+uid+'/serverEconomy/purchases/'+receiptKey(item)+'/requestIdHash',null);const before=structuredClone(db.read('users/'+uid));
  const replay=await purchaseSoftItem(context());assert.equal(replay.transactionId,first.transactionId);assert.deepEqual(db.read('users/'+uid),before);
});

for(const startedAt of [at-PASS_CHEST_RECOVERY_MS+1,at+1000,0])test(`permanent processing timestamp ${startedAt} cannot be prematurely reclaimed`,async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,stale(seed(),'purchaseSoftItem:'+item,startedAt)),before=structuredClone(db.read('users/'+uid));
  await assert.rejects(purchaseSoftItem(context()),{code:'request-in-progress'});assert.deepEqual(db.read('users/'+uid),before);
});
for(const operation of ['purchaseSoftItem:pass:premium','purchaseSoftItem:unknown','purchaseSoftItem:toString','purchaseSoftItem:__proto__'])test(`abandoned ${operation} cannot be blindly re-executed`,async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,stale(seed(),operation));
  await assert.rejects(idempotent(uid,id,operation,async()=>assert.fail('unsafe work must not run')),{code:'request-in-progress'});
  assert.equal(db.read(requestPath+'/ownerToken'),'abandoned-owner');
});

const corruptions={
  owner:(profile,receipt)=>receipt.uid='foreign',
  key:(profile,receipt)=>receipt.idempotencyKey='wrong',
  source:(profile,receipt)=>receipt.sourceId='wrong',
  item:(profile,receipt)=>receipt.itemId='piece_set:ice',
  kind:(profile,receipt)=>receipt.itemType='skin',
  currency:(profile,receipt)=>receipt.currency='cash',
  price:(profile,receipt)=>receipt.price=-1,
  time:(profile,receipt)=>receipt.purchasedAt=0,
  transaction:(profile,receipt)=>receipt.transactionId='foreign',
  grant:(profile,receipt)=>receipt.outcome={kind:'piece_set',id:'ice'},
  requestBinding:(profile,receipt)=>receipt.requestIdHash='invalid',
  requestBindingArray:(profile,receipt)=>receipt.requestIdHash=[hash(id)],
  missingLedger:(profile,receipt)=>delete profile.serverEconomy.ledger[receipt.transactionId],
  ledgerOwner:(profile,receipt)=>profile.serverEconomy.ledger[receipt.transactionId].uid='foreign',
  ledgerDelta:(profile,receipt)=>profile.serverEconomy.ledger[receipt.transactionId].newBalance++,
  missingOwnership:profile=>profile.inventory.ownedSets=['std'],
};
for(const [name,corrupt] of Object.entries(corruptions))test(`malformed permanent receipt ${name} fails closed without spend or regrant`,async t=>{
  const db=memoryDatabase(t,seed());await purchaseSoftItem(context());db.write(requestPath,null);const profile=db.read('users/'+uid);
  corrupt(profile,profile.serverEconomy.purchases[receiptKey(item)]);const before=structuredClone(profile);
  await assert.rejects(purchaseSoftItem(context()),{code:'soft-purchase-receipt-invalid'});assert.deepEqual(db.read('users/'+uid),before);
});
for(const root of ['purchases','ledger','claims'])test(`malformed permanent ${root} root cannot be normalized into another purchase`,async t=>{
  const db=memoryDatabase(t,seed());await purchaseSoftItem(context());db.write(requestPath,null);db.write('users/'+uid+'/serverEconomy/'+root,'invalid');
  const before=structuredClone(db.read('users/'+uid));await assert.rejects(purchaseSoftItem(context()),{code:'soft-purchase-receipt-invalid'});
  assert.deepEqual(db.read('users/'+uid),before);
});

test('malformed economy root cannot be reset into another purchase',async t=>{
  const db=memoryDatabase(t,seed());await purchaseSoftItem(context());db.write(requestPath,null);db.write('users/'+uid+'/serverEconomy','invalid');
  const before=structuredClone(db.read('users/'+uid));await assert.rejects(purchaseSoftItem(context()),{code:'soft-purchase-receipt-invalid'});
  assert.deepEqual(db.read('users/'+uid),before);
});
for(const itemId of ['toString','__proto__'])test(`inherited catalog property ${itemId} is not a product`,async t=>{
  const db=memoryDatabase(t,seed()),before=structuredClone(db.read('users/'+uid));
  await assert.rejects(purchaseSoftItem(context(id,itemId)),{code:'unknown-item'});assert.deepEqual(db.read('users/'+uid),before);
});
test('an orphaned permanent debit cannot be overwritten into a second purchase',async t=>{
  const db=memoryDatabase(t,seed());await purchaseSoftItem(context());db.write(requestPath,null);
  db.write('users/'+uid+'/serverEconomy/purchases/'+receiptKey(item),null);db.write('users/'+uid+'/inventory/ownedSets',['std']);
  const before=structuredClone(db.read('users/'+uid));await assert.rejects(purchaseSoftItem(context()),{code:'soft-purchase-receipt-invalid'});
  assert.deepEqual(db.read('users/'+uid),before);
});
