'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const path=require('node:path');
const api=require('../index');
const {loadStack}=require('../node_modules/firebase-functions/lib/runtime/loader.js');
const required=['lunoApi','playBillingNotifications','sweepBattleV1','sweepProductTelemetry','sweepRankedMatches'];

test('test helpers remain accessible to tests but are not deployment exports',()=>{
  assert.equal(typeof api._test.handler,'function');
  assert.equal(typeof api._test.battleV1.enqueueBattleV1,'function');
  assert.equal(Object.getOwnPropertyDescriptor(api,'_test').enumerable,false);
  assert.deepEqual(Object.keys(api).sort(),required);
});

test('the actual Firebase SDK discovers exactly the five production endpoints',async()=>{
  const stack=await loadStack(path.resolve(__dirname,'..'));
  assert.deepEqual(Object.keys(stack.endpoints).sort(),required);
  for(const id of required)assert.equal(stack.endpoints[id].entryPoint,id);
  assert.ok(stack.endpoints.lunoApi.httpsTrigger);
  assert.ok(stack.endpoints.sweepBattleV1.scheduleTrigger);
  assert.ok(stack.endpoints.sweepProductTelemetry.scheduleTrigger);
  assert.ok(stack.endpoints.playBillingNotifications.eventTrigger);
});
