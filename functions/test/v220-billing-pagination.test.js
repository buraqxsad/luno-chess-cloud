'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {google} = require('googleapis');
const {memoryDatabase} = require('./helpers/memory-database');
const {reconcilePlayNotification, starterProfile, hash} = require('../index')._test;
const uid = 'v220_billing_owner';
const productId = 'luno_gold_1000';
const token = 'synthetic-v220-billing-token';
const tokenHash = hash(token);
const orderId = 'synthetic-v220-order';

function fixture(t, provider) {
  const profile = starterProfile(uid, 'v220_billing');
  profile.gold = 1000;
  profile.serverEconomy = {purchaseTokens: {[tokenHash]: {
    productId, kind: 'inapp', active: true, entitlementStatus: 'granted',
    grantGold: 1000, grantGems: 0,
  }}};
  const db = memoryDatabase(t, {users: {[uid]: profile}, purchaseClaims: {
    [tokenHash]: {uid, productId, status: 'complete', kind: 'inapp', active: true,
      entitlementStatus: 'granted', grantGold: 1000, grantGems: 0},
  }});
  const calls = [];
  t.mock.method(google, 'androidpublisher', () => ({purchases: {voidedpurchases: {
    async list(request) {calls.push(request); return provider(request, calls.length);},
  }}}));
  const notification = {packageName: 'com.luno.chess', eventTimeMillis: String(Date.now()),
    voidedPurchaseNotification: {purchaseToken: token, orderId, productType: 2, refundType: 1}};
  return {db, calls, run: () => reconcilePlayNotification(notification, 'v220-pagination')};
}

const proof = () => ({purchaseToken: token, orderId, voidedTimeMillis: String(Date.now())});

test('refund proof on a later provider page revokes exactly once', async t => {
  const {db, calls, run} = fixture(t, request => request.token === 'page-two'
    ? {data: {voidedPurchases: [proof()]}}
    : {data: {voidedPurchases: [], tokenPagination: {nextPageToken: 'page-two'}}});
  assert.equal((await run()).revoked, true);
  assert.equal(db.read('users/' + uid + '/gold'), 0);
  assert.deepEqual(calls.map(call => call.token || null), [null, 'page-two']);
  assert.equal((await run()).idempotent, true);
  assert.equal(db.read('users/' + uid + '/gold'), 0);
});

test('first-page proof needs no further provider calls', async t => {
  const {calls, run} = fixture(t, () => ({data: {voidedPurchases: [proof()],
    tokenPagination: {nextPageToken: 'unused'}}}));
  assert.equal((await run()).revoked, true);
  assert.equal(calls.length, 1);
});

for (const [name, provider, code, count] of [
  ['cycle', () => ({data: {voidedPurchases: [], tokenPagination: {nextPageToken: 'same-page'}}}),
    'void-pagination-cycle', 2],
  ['page budget', (_, count) => ({data: {voidedPurchases: [], tokenPagination: {nextPageToken: 'page-' + count}}}),
    'void-pagination-limit', 20],
  ['invalid page token', () => ({data: {voidedPurchases: [], tokenPagination: {nextPageToken: {invalid: true}}}}),
    'void-pagination-invalid', 1],
  ['no proof', () => ({data: {voidedPurchases: []}}), 'void-not-confirmed', 1],
  ['wrong order', () => ({data: {voidedPurchases: [{...proof(), orderId: 'other-order'}]}}),
    'void-not-confirmed', 1],
  ['later provider failure', request => {
    if (request.token) throw new Error('synthetic-provider-unavailable');
    return {data: {voidedPurchases: [], tokenPagination: {nextPageToken: 'page-two'}}};
  }, 'play-billing-unavailable', 2],
]) test(`refund pagination ${name} fails closed with no reversal`, async t => {
  const {db, calls, run} = fixture(t, provider);
  const before = structuredClone(db.data);
  await assert.rejects(run(), {code});
  assert.deepEqual(db.data, before);
  assert.equal(calls.length, count);
});
