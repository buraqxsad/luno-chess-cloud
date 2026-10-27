'use strict';

const test=require('node:test'),assert=require('node:assert/strict');
const {purchaseSoftItem,starterProfile,sourceClaimKey,hash,PASS_CHEST_RECOVERY_MS,requestClaimCanRecover}=require('../index')._test;
const {seasonBounds,periodSnapshot}=require('../lib/economy');
const {memoryDatabase}=require('./helpers/memory-database');
const uid='premium_purchase_player',id='premium-purchase',at=seasonBounds(6).startAt+3600000,season='s6',nextAt=seasonBounds(7).startAt+3600000;
const requestPath=`serverRequests/${uid}/${hash(id).slice(0,48)}`,receiptKey=sourceClaimKey(uid,'soft_purchase',season+':pass:premium');
function seed(){const profile=starterProfile(uid,'premium_player');profile.gems=30000;return {users:{[uid]:profile}};}
function context(requestId=id,seasonId=season){return {uid,requestId,body:{itemId:'pass:premium',seasonId}};}
function stale(data,startedAt=at-PASS_CHEST_RECOVERY_MS-1){
  data.serverRequests={[uid]:{[hash(id).slice(0,48)]:{operation:'purchaseSoftItem:pass:premium:'+season,status:'processing',ownerToken:'abandoned-owner',startedAt,createdAt:startedAt}}};return data;
}
test('fresh Premium purchase stores one season-bound receipt and intent atomically',async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,seed()),result=await purchaseSoftItem(context()),profile=db.read('users/'+uid);
  assert.equal(result.purchased,true);assert.equal(profile.gems,29550);assert.equal(result.seasonId,season);assert.equal(result.currentSeasonId,season);assert.equal(result.passActive,true);
  assert.deepEqual(result.grant,{kind:'pass_premium',id:'premium'});assert.equal(profile.serverEconomy.purchases[receiptKey].requestIdHash,hash(id));
  assert.equal(profile.serverEconomy.passPurchaseRequests[hash(id)],season);
});
test('same-season replay after cache loss uses the receipt without another charge',async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,seed()),first=await purchaseSoftItem(context());db.write(requestPath,null);
  const before=structuredClone(db.read('users/'+uid)),replay=await purchaseSoftItem(context());
  assert.equal(replay.purchased,false);assert.equal(replay.idempotent,true);assert.equal(replay.transactionId,first.transactionId);assert.equal(replay.passActive,true);
  assert.deepEqual(db.read('users/'+uid),before);
});
test('expired paid season replays as inactive and never purchases the new season',async t=>{
  let clock=at;t.mock.method(Date,'now',()=>clock);const db=memoryDatabase(t,seed()),first=await purchaseSoftItem(context());db.write(requestPath,null);clock=nextAt;
  const before=structuredClone(db.read('users/'+uid)),replay=await purchaseSoftItem(context());
  assert.equal(replay.transactionId,first.transactionId);assert.equal(replay.seasonId,season);assert.equal(replay.currentSeasonId,'s7');assert.equal(replay.passActive,false);
  assert.equal(replay.state.passState.seasonKey,'ranked-s7-v2');assert.equal(replay.state.passState.premium,false);assert.deepEqual(db.read('users/'+uid),before);
});
test('cached previous-season success cannot resurrect a Premium entitlement',async t=>{
  let clock=at;t.mock.method(Date,'now',()=>clock);const db=memoryDatabase(t,seed());await purchaseSoftItem(context());clock=nextAt;
  db.write('users/'+uid+'/gems',0);const replay=await purchaseSoftItem(context());
  assert.equal(replay.state.gems,0);assert.equal(replay.passActive,false);assert.equal(replay.state.passState.premium,false);
});
test('unpaid expired request is rejected without charging either season',async t=>{
  t.mock.method(Date,'now',()=>nextAt);const db=memoryDatabase(t,seed()),before=structuredClone(db.read('users/'+uid));
  await assert.rejects(purchaseSoftItem(context()),{code:'pass-season-changed'});assert.deepEqual(db.read('users/'+uid),before);
});
test('season is rechecked at the profile transaction, not only at request entry',async t=>{
  let clock=at;t.mock.method(Date,'now',()=>clock);const db=memoryDatabase(t,seed(),{beforeTransaction(path){if(path==='users/'+uid)clock=nextAt;}});
  const before=structuredClone(db.read('users/'+uid));await assert.rejects(purchaseSoftItem(context()),{code:'pass-season-changed'});assert.deepEqual(db.read('users/'+uid),before);
});
test('a season ending after the debit returns an expired confirmation, not new Premium',async t=>{
  let clock=at;t.mock.method(Date,'now',()=>clock);const db=memoryDatabase(t,seed(),{beforeTransaction(path,count){if(path===requestPath&&count===2)clock=nextAt;}});
  const result=await purchaseSoftItem(context());assert.equal(result.purchased,true);assert.equal(result.passActive,false);
  assert.equal(result.state.passState.premium,false);assert.equal(result.currentSeasonId,'s7');assert.equal(db.read('users/'+uid+'/gems'),29550);
  assert.equal(Object.keys(db.read('users/'+uid+'/serverEconomy/purchases')).length,1);
});
test('future season cannot be bought early',async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,seed()),before=structuredClone(db.read('users/'+uid));
  await assert.rejects(purchaseSoftItem(context(id,'s7')),{code:'pass-season-changed'});assert.deepEqual(db.read('users/'+uid),before);
});
test('new client must provide a season rather than leaving a charge ambiguous',async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,seed()),before=structuredClone(db.read('users/'+uid));
  await assert.rejects(purchaseSoftItem({uid,requestId:id,body:{itemId:'pass:premium'}}),{code:'pass-season-required'});assert.deepEqual(db.read('users/'+uid),before);
});
for(const invalid of [null,6,'s0','s06','s6/other','s1000000000'])test(`invalid season ${String(invalid)} cannot spend`,async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,seed()),before=structuredClone(db.read('users/'+uid));
  await assert.rejects(purchaseSoftItem(context(id,invalid)),{code:'invalid-pass-season'});assert.deepEqual(db.read('users/'+uid),before);
});
test('first committed Premium request cannot change season after cache loss',async t=>{
  let clock=at;t.mock.method(Date,'now',()=>clock);const db=memoryDatabase(t,seed());await purchaseSoftItem(context());db.write(requestPath,null);clock=nextAt;
  const before=structuredClone(db.read('users/'+uid));await assert.rejects(purchaseSoftItem(context(id,'s7')),{code:'request-id-conflict'});assert.deepEqual(db.read('users/'+uid),before);
});
test('Premium request cannot become a permanent item after cache loss',async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,seed());await purchaseSoftItem(context());db.write(requestPath,null);const before=structuredClone(db.read('users/'+uid));
  await assert.rejects(purchaseSoftItem({uid,requestId:id,body:{itemId:'piece_set:roma'}}),{code:'request-id-conflict'});assert.deepEqual(db.read('users/'+uid),before);
});
test('permanent purchase request cannot become Premium after cache loss',async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,seed());await purchaseSoftItem({uid,requestId:id,body:{itemId:'piece_set:roma'}});db.write(requestPath,null);
  const before=structuredClone(db.read('users/'+uid));await assert.rejects(purchaseSoftItem(context()),{code:'request-id-conflict'});assert.deepEqual(db.read('users/'+uid),before);
});
test('current receipt replays at zero balance during billing review',async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,seed()),first=await purchaseSoftItem(context());db.write(requestPath,null);
  db.write('users/'+uid+'/gems',0);db.write('users/'+uid+'/serverEconomy/billingReviewRequired',true);
  const replay=await purchaseSoftItem(context());assert.equal(replay.transactionId,first.transactionId);assert.equal(replay.state.gems,0);
});
test('known season-qualified processing operation can be reclaimed before debit',async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,stale(seed()));assert.equal((await purchaseSoftItem(context())).purchased,true);assert.equal(db.read('users/'+uid+'/gems'),29550);
});
test('stale processing operation after debit recovers its original receipt',async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,seed()),first=await purchaseSoftItem(context());
  db.write(requestPath,stale(seed()).serverRequests[uid][hash(id).slice(0,48)]);const before=structuredClone(db.read('users/'+uid));
  const replay=await purchaseSoftItem(context());assert.equal(replay.transactionId,first.transactionId);assert.deepEqual(db.read('users/'+uid),before);
});
test('cache completion failure cannot cause another season charge',async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,seed(),{beforeTransaction(path,count){if(path===requestPath&&count===2)throw new Error('cache-store-failed');}});
  await assert.rejects(purchaseSoftItem(context()),/cache-store-failed/);const before=structuredClone(db.read('users/'+uid));
  assert.equal((await purchaseSoftItem(context())).purchased,false);assert.deepEqual(db.read('users/'+uid),before);
});
for(const startedAt of [at-PASS_CHEST_RECOVERY_MS+1,at+1000,0])test(`invalid/premature lease ${startedAt} cannot recover`,async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,stale(seed(),startedAt));
  await assert.rejects(purchaseSoftItem(context()),{code:'request-in-progress'});assert.equal(db.read('users/'+uid+'/gems'),30000);
});
const corruptions={
  owner:(profile,receipt)=>receipt.uid='foreign',grant:(profile,receipt)=>receipt.outcome.id='other',
  price:(profile,receipt)=>receipt.price=0,currency:(profile,receipt)=>receipt.currency='cash',
  timestamp:(profile,receipt)=>receipt.purchasedAt=nextAt,key:(profile,receipt)=>receipt.idempotencyKey='wrong',
  transaction:(profile,receipt)=>receipt.transactionId='wrong',binding:(profile,receipt)=>receipt.requestIdHash=[hash(id)],
  missingIndex:profile=>delete profile.serverEconomy.passPurchaseRequests,
  wrongIndex:profile=>profile.serverEconomy.passPurchaseRequests[hash(id)]='s7',
  malformedIndex:profile=>profile.serverEconomy.passPurchaseRequests=[] ,
  missingLedger:(profile,receipt)=>delete profile.serverEconomy.ledger[receipt.transactionId],
  delta:(profile,receipt)=>profile.serverEconomy.ledger[receipt.transactionId].amount=-1,
  missingPremium:profile=>profile.passState.premium=false,
};
for(const [name,corrupt] of Object.entries(corruptions))test(`corrupt Premium receipt ${name} fails closed without another debit`,async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,seed());await purchaseSoftItem(context());db.write(requestPath,null);
  const profile=db.read('users/'+uid);corrupt(profile,profile.serverEconomy.purchases[receiptKey]);const before=structuredClone(profile);
  await assert.rejects(purchaseSoftItem(context()),{code:name==='wrongIndex'?'request-id-conflict':'pass-purchase-receipt-invalid'});assert.deepEqual(db.read('users/'+uid),before);
});
test('legacy valid receipt replays read-only without inventing original request binding',async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,seed()),first=await purchaseSoftItem(context());db.write(requestPath,null);
  db.write('users/'+uid+'/serverEconomy/purchases/'+receiptKey+'/requestIdHash',null);db.write('users/'+uid+'/serverEconomy/passPurchaseRequests',null);
  const before=structuredClone(db.read('users/'+uid)),replay=await purchaseSoftItem(context());assert.equal(replay.transactionId,first.transactionId);assert.deepEqual(db.read('users/'+uid),before);
});
test('orphaned Premium debit cannot be overwritten into another purchase',async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,seed());await purchaseSoftItem(context());db.write(requestPath,null);db.write('users/'+uid+'/serverEconomy/purchases/'+receiptKey,null);
  const before=structuredClone(db.read('users/'+uid));await assert.rejects(purchaseSoftItem(context()),{code:'pass-purchase-receipt-invalid'});assert.deepEqual(db.read('users/'+uid),before);
});
for(const state of ['processing','complete'])test(`${state} deletion blocks Premium replay`,async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,seed());await purchaseSoftItem(context());db.write('accountDeletions/'+hash(uid),{status:state});
  await assert.rejects(purchaseSoftItem(context()),{code:state==='processing'?'account-deletion-in-progress':'account-deleted'});
});

for(const operation of ['purchaseSoftItem:pass:premium','purchaseSoftItem:pass:premium:s06','purchaseSoftItem:pass:premium:s0','purchaseSoftItem:pass:premium:s6:other'])test(`ambiguous operation ${operation} is never lease-recovered`,()=>{
  assert.equal(requestClaimCanRecover(operation,{operation,status:'processing',startedAt:at-PASS_CHEST_RECOVERY_MS-1},at),false);
});
test('read-only replay aliases do not grow the charged-request index',async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,seed());await purchaseSoftItem(context());
  for(let i=0;i<5;i++)assert.equal((await purchaseSoftItem(context('alias-'+i))).purchased,false);
  assert.deepEqual(db.read('users/'+uid+'/serverEconomy/passPurchaseRequests'),{[hash(id)]:season});assert.equal(db.read('users/'+uid+'/gems'),29550);
});
test('cached success cannot bypass a subsequently corrupt receipt',async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,seed());await purchaseSoftItem(context());
  db.write('users/'+uid+'/serverEconomy/purchases/'+receiptKey+'/uid','foreign');
  const before=structuredClone(db.read('users/'+uid));await assert.rejects(purchaseSoftItem(context()),{code:'pass-purchase-receipt-invalid'});assert.deepEqual(db.read('users/'+uid),before);
});
test('cached success cannot resurrect a removed profile',async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,seed());await purchaseSoftItem(context());db.write('users/'+uid,null);
  await assert.rejects(purchaseSoftItem(context()),{code:'profile-not-found'});assert.equal(db.read('users/'+uid),null);
});
test('cached success cannot expose a replaced profile owner',async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,seed());await purchaseSoftItem(context());db.write('users/'+uid+'/uid','foreign');
  await assert.rejects(purchaseSoftItem(context()),{code:'profile-owner-mismatch'});
});
for(const root of ['purchases','ledger','claims'])test(`malformed Premium ${root} root cannot be normalized into a debit`,async t=>{
  t.mock.method(Date,'now',()=>at);const data=seed();data.users[uid].serverEconomy={[root]:[]};const db=memoryDatabase(t,data),before=structuredClone(db.read('users/'+uid));
  await assert.rejects(purchaseSoftItem(context()),{code:'pass-purchase-receipt-invalid'});assert.deepEqual(db.read('users/'+uid),before);
});
test('bound request with no receipt cannot buy a replacement',async t=>{
  t.mock.method(Date,'now',()=>at);const data=seed();data.users[uid].serverEconomy={passPurchaseRequests:{[hash(id)]:season}};const db=memoryDatabase(t,data),before=structuredClone(db.read('users/'+uid));
  await assert.rejects(purchaseSoftItem(context()),{code:'pass-purchase-receipt-invalid'});assert.deepEqual(db.read('users/'+uid),before);
});
