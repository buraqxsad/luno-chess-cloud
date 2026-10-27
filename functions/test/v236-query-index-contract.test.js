'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'../..');
const source=fs.readFileSync(path.join(root,'functions/index.js'),'utf8');
const config=JSON.parse(fs.readFileSync(path.join(root,'firebase.json'),'utf8'));
const rules=JSON.parse(fs.readFileSync(path.join(root,config.database.rules),'utf8')).rules;

test('configured production rules index the concrete notification sender cleanup query',()=>{
  assert.match(source,/db\.ref\(`notifications\/\$\{uid\}`\)\.orderByChild\('fromUid'\)/);
  assert.ok(rules.notifications.$uid['.indexOn']?.includes('fromUid'),
    'notifications/$uid needs fromUid for the existing Admin get query');
});

test('adding an index does not grant notification or DM writes or parent reads',()=>{
  assert.equal(rules['.read'],false);
  assert.equal(rules['.write'],false);
  assert.equal(rules.notifications['.read'],undefined);
  assert.equal(rules.notifications.$uid['.read'],'auth != null && auth.uid === $uid');
  assert.equal(rules.notifications.$uid['.write'],false);
  assert.equal(rules.dm['.read'],undefined);
  assert.equal(rules.dm.$conversationId['.write'],false);
  assert.match(rules.dm.$conversationId['.read'],/data\.child\('members'\)\.child\(auth\.uid\)\.val\(\) === true/);
  assert.match(rules.dm.$conversationId['.read'],/root\.child\('users'\)\.child\(auth\.uid\)\.exists\(\)/);
});
