import assert from 'node:assert/strict';
import test from 'node:test';
import {STARTER} from '../src/model.js';
import {migrateLegacy} from '../src/online/migration.js';

test('native V1 compatibility defaults do not silently unlock competitive cards',()=>{
  const profile={battleV1MigrationPolicy:'native-v1',
    unlockedCards:{card_block:true,angry_n:true,freeze:true,radar:true},
    battleV1UnlockedCards:{mine:true}};
  const account=migrateLegacy(profile);
  assert.deepEqual(new Set(account.entitlements),new Set([...STARTER,'mine']));
  assert.deepEqual(account.deck,STARTER);
});

test('legacy earned rights and already migrated rights are never revoked',()=>{
  const legacy=migrateLegacy({unlockedCards:{card_block:true,angry_n:true}});
  assert(legacy.entitlements.includes('card_block'));
  assert(legacy.entitlements.includes('angry_n'));
  const retained=migrateLegacy({battleV1MigrationPolicy:'native-v1'},legacy);
  assert.deepEqual(retained.entitlements,legacy.entitlements);
});
