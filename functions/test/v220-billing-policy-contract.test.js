'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const root = path.resolve(__dirname, '../..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

test('B03: premium exposes a working static Play management action', () => {
  const premium = read('luno_chess/lib/screens/legacy_parity_screens.dart');
  assert.match(premium, /membership-manage-subscription/);
  assert.match(premium, /openPlaySubscriptions\(\)/);
  assert.match(read('luno_chess/lib/services/legal_link_service.dart'), /invokeMethod<bool>\('openPlaySubscriptions'\)/);
});

test('B03: Android uses a fixed subscription URL without broadening legal URLs', () => {
  const native = read('luno_chess/android/app/src/main/kotlin/com/luno/chess/MainActivity.kt');
  assert.match(native, /"openPlaySubscriptions"/);
  assert.match(native, /https:\/\/play\.google\.com\/store\/account\/subscriptions/);
  assert.match(native, /url !in setOf\(/);
  assert.doesNotMatch(native, /startsWith\("https:\/\/play/);
});

test('B04: odds confirmation is awaited before any chest debit', () => {
  const shop = read('luno_chess/lib/screens/shop_screen.dart');
  const flow = shop.slice(shop.indexOf('Future<void> _openServerChest'), shop.indexOf('Future<void> _buySoftItem'));
  assert.match(flow, /await _confirmChestOdds\(context, chestId, guard\)/);
  assert.ok(flow.indexOf('await _confirmChestOdds') < flow.indexOf('online.openChest('));
  assert.match(flow, /accepted != true/);
  assert.match(shop, /ChestOdds\.fromPlayerState/);
});

test('B04 recovery: existing paid receipt bypasses new-purchase odds and cannot stage a fresh debit', () => {
  const shop = read('luno_chess/lib/screens/shop_screen.dart');
  const flow = shop.slice(shop.indexOf('Future<void> _openServerChest'), shop.indexOf('Future<bool?> _confirmChestOdds'));
  assert.ok(flow.includes('pendingShopChestRequestKinds'), 'resolve durable journal before new-purchase odds');
  assert.ok(flow.includes('if (!recoverPending)'), 'exhausted collection must not block paid receipt recovery');
  assert.ok(flow.includes('recoverPendingOnly: recoverPending'), 'transport must use recovery-only staging');
  const store = read('luno_chess/lib/models/game_store.dart');
  assert.ok(store.includes('if (requireExisting)'), 'missing recovery journal must never create a purchase');
});

test('B05: delete confirmation warns and offers management, never auto-cancels', () => {
  const settings = read('luno_chess/lib/screens/native_hubs_screen.dart');
  const flow = settings.slice(settings.indexOf('Future<void> _deleteAccount()'), settings.indexOf('Future<void> _deleteAccount()') + 6500);
  assert.match(flow, /does not cancel your Google Play subscription/);
  assert.match(flow, /Google Play aboneliğini iptal etmez/);
  assert.match(flow, /delete-account-manage-subscription/);
  assert.match(flow, /openPlaySubscriptions\(\)/);
  assert.doesNotMatch(flow, /cancelSubscription|revokePurchase/);
});
