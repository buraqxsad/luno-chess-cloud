'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'../..');
const config=JSON.parse(fs.readFileSync(path.join(root,'firebase.json'),'utf8'));
const rules=JSON.parse(fs.readFileSync(path.join(root,config.database.rules),'utf8')).rules;

// Source contract only. Real security evaluation and onDisconnect regression:
// system-hunt-identity-presence.integration.js, against an isolated local RTDB.
test('selected presence rules require a provisioned owner profile',()=>{
  assert.equal(config.database.rules,'database.rules.production.json');
  const write=rules.presence.$uid['.write'];
  assert.match(write,/auth != null/);
  assert.match(write,/auth\.uid === \$uid/);
  assert.match(write,/root\.child\('users'\)\.child\(auth\.uid\)\.exists\(\)/,
    'A late client heartbeat/onDisconnect must not recreate presence after server account erasure.');
});

test('presence retains online and bounded server timestamp validation',()=>{
  const validation=rules.presence.$uid['.validate'];
  assert.match(validation,/newData\.hasChildren\(\['online','lastSeen'\]\)/);
  assert.match(validation,/newData\.child\('online'\)\.isBoolean\(\)/);
  assert.match(validation,/newData\.child\('lastSeen'\)\.isNumber\(\)/);
  assert.match(validation,/newData\.child\('lastSeen'\)\.val\(\) <= now \+ 10000/);
});

test('presence fix preserves server authority over profile and default write denial',()=>{
  assert.equal(rules.users.$uid['.write'],false);
  assert.equal(rules['.write'],false);
  assert.equal(rules['.read'],false);
});
