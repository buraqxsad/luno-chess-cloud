'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const rules=JSON.parse(fs.readFileSync(path.resolve(__dirname,'../../database.rules.production.json'),'utf8')).rules;

test('DM profile/deletion defense keeps authenticated exact membership and write denial',()=>{
  const conversation=rules.dm.$conversationId;
  assert.equal(conversation['.read'],"auth != null && root.child('users').child(auth.uid).exists() && !root.child('deletedAccounts').child(auth.uid).exists() && data.child('members').child(auth.uid).val() === true");
  assert.equal(conversation['.write'],false);
  assert.equal(rules['.read'],false);assert.equal(rules['.write'],false);
  assert.equal(rules.messageThrottle['.read'],false);assert.equal(rules.purchaseClaims['.read'],false);
});
