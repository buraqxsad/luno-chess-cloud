'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {applyRewardClaim,applySoftPurchase}=require('../lib/economy');

const at=Date.UTC(2026,9,22,12),uid='v236-evidence-owner';
const profile=()=>({uid,gold:2000,gems:500});
const reward=p=>applyRewardClaim(p,{uid,sourceType:'onboarding_reward',sourceId:'v1',reward:{gold:500},at});
const purchase=(p,grant=()=>({kind:'piece_set',id:'ottoman'}))=>applySoftPurchase(p,{
  uid,sourceType:'soft_purchase',sourceId:'piece_set:ottoman',itemType:'piece_set',
  itemId:'ottoman',currency:'gold',price:1000,at,grant,
});

test('valid durable reward and purchase receipts replay without another balance mutation',()=>{
  const p=profile();
  const earned=reward(p),bought=purchase(p),before=structuredClone(p);
  assert.equal(p.gold,1500);
  assert.deepEqual(reward(p).transactionIds,earned.transactionIds);
  assert.equal(purchase(p).transactionId,bought.transactionId);
  assert.deepEqual(p,before);
});

test('retained reward ledger blocks a second credit when its claim marker is missing',()=>{
  const p=profile(),first=reward(p);
  delete p.serverEconomy.claims[first.idempotencyKey];
  const before=structuredClone(p);
  assert.throws(()=>reward(p),/receipt|evidence/i);
  assert.deepEqual(p,before);
  assert.equal(p.gold,2500);
});

test('retained spend ledger blocks a second debit and delivery when its purchase marker is missing',()=>{
  const p=profile(),first=purchase(p);
  delete p.serverEconomy.purchases[first.idempotencyKey];
  const before=structuredClone(p);
  let deliveries=0;
  assert.throws(()=>purchase(p,()=>{deliveries++;return {};}),/receipt|evidence/i);
  assert.equal(deliveries,0);
  assert.deepEqual(p,before);
  assert.equal(p.gold,1000);
});

for(const kind of ['reward','purchase']){
  test(`${kind} does not treat a malformed existing marker as a fresh operation`,()=>{
    const p=profile(),run=kind==='reward'?reward:purchase,first=run(p);
    p.serverEconomy[kind==='reward'?'claims':'purchases'][first.idempotencyKey]=false;
    const before=structuredClone(p);
    assert.throws(()=>run(p),/receipt|evidence/i);
    assert.deepEqual(p,before);
  });
}

for(const field of ['claims','purchases','ledger']){
  test(`normalization preserves malformed ${field} evidence instead of replacing it`,()=>{
    const p=profile();reward(p);purchase(p);
    p.serverEconomy[field]=['retained-evidence'];
    const before=structuredClone(p);
    assert.throws(()=>reward(p),/receipt|evidence/i);
    assert.deepEqual(p,before);
  });
}

test('a malformed economy container is not reset to authorize another reward',()=>{
  const p={...profile(),serverEconomy:'retained-evidence'},before=structuredClone(p);
  assert.throws(()=>reward(p),/receipt|evidence/i);
  assert.deepEqual(p,before);
});

test('legacy profiles with absent proof containers still receive their first reward',()=>{
  const p=profile();
  assert.equal(reward(p).granted,true);
  assert.equal(p.gold,2500);
  assert.equal(Object.keys(p.serverEconomy.ledger).length,1);
});
