'use strict';
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const root = path.resolve(__dirname, '../..');
const oracle = require('../../luno_chess/qa/v220/billing/chest-odds-oracle.cjs');
const parseDartJson = file => JSON.parse(fs.readFileSync(path.join(root, file), 'utf8').match(/r'''([\s\S]*?)'''/)[1]);
const contract = parseDartJson('luno_chess/lib/services/chest_odds_contract.dart');

test('B04 disclosure contract exactly matches all authoritative chest and cosmetic catalogs', () => {
  assert.deepEqual(contract.chests, oracle.catalogs.CHEST_CATALOG);
  assert.deepEqual(contract.pools, oracle.pools);
});
test('B04 roll algorithm, shard gates, and quantity gate cannot silently drift', () => {
  assert.equal(contract.algorithmSha256, crypto.createHash('sha256').update(oracle.source).digest('hex'));
  assert.deepEqual(contract.frameChance, JSON.parse(JSON.stringify(oracle.chance('frameChance'))));
  assert.deepEqual(contract.bioChance, JSON.parse(JSON.stringify(oracle.chance('bioChance'))));
  assert.equal(contract.frameTwoPieceChance, Number(oracle.source.match(/random\(\)<(\.\d+)\?2:1/)[1]));
});
test('B04 Dart expected outcomes are produced from the backend oracle, including fallback and caps', () => {
  assert.deepEqual(parseDartJson('luno_chess/test/v220_billing_odds_fixture.dart'), oracle.fixtures());
});
test('B04 oracle agrees with actual backend availability for all controlled inventories', () => {
  const {chestAvailability} = require('../lib/chests');
  for (const fixture of oracle.fixtures()) {
    const actual = chestAvailability({inventory: fixture.inventory}, fixture.expected.chestId);
    assert.equal(actual.canPurchase, fixture.expected.items.length > 0);
    assert.equal(actual.price, fixture.expected.price);
    assert.equal(actual.currency, fixture.expected.currency);
    for (const item of fixture.expected.items) {
      const total = Object.values(item.amountOdds).reduce((a, b) => a + b, 0);
      assert.ok(total > 0 && total <= 1 + 1e-12);
    }
  }
  const single = oracle.fixtures().find(f => f.name === 'one-target').expected;
  assert.equal(single.items.length, 1);
  assert.ok(Math.abs(Object.values(single.items[0].amountOdds).reduce((a,b) => a+b) - 1) < 1e-12);
  const capped = oracle.fixtures().find(f => f.name === 'one-frame-capped').expected;
  assert.deepEqual(capped.items[0].amountOdds, {'1': 1});
});
