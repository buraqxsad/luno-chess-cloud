'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {getDatabase}=require('firebase-admin/database');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const {assertAccountOperationAllowed,handler,hash}=require('../index')._test;
const uid='deletion-test-player';
function mockState(t,state,tombstone=null){
  const paths=[];
  t.mock.method(getDatabase(),'ref',path=>{
    paths.push(path);
    assert.ok([`accountDeletions/${hash(uid)}`,`deletedAccounts/${hash(uid)}`].includes(path),
      'blocked request must not reach operation data');
    const value=path.startsWith('accountDeletions/')?state:tombstone;
    return {async get(){return {val:()=>value,exists:()=>value!==null};}};
  });
  return paths;
}
test('normal account passes the deletion gate',async(t)=>{
  const paths=mockState(t,null);
  await assertAccountOperationAllowed(uid,'updateProfile');
  assert.equal(paths.length,2);
});
test('processing deletion blocks gameplay but permits deletion retry',async(t)=>{
  mockState(t,{status:'processing'});
  await assert.rejects(assertAccountOperationAllowed(uid,'enqueueRanked'),{code:'account-deletion-in-progress'});
  await assertAccountOperationAllowed(uid,'deleteAccount');
});
for(const state of [{status:'complete'},null])test(`deleted account blocked with ${state?'complete marker':'tombstone'}`,async(t)=>{
  mockState(t,state,state?null:{deletedAt:1});
  await assert.rejects(assertAccountOperationAllowed(uid,'updateProfile'),{code:'account-deleted'});
  await assert.rejects(assertAccountOperationAllowed(uid,'deleteAccount'),{code:'account-deleted'});
});
test('unknown deletion state is fail-closed for ordinary operations',async(t)=>{
  mockState(t,{status:'unexpected'});
  await assert.rejects(assertAccountOperationAllowed(uid,'updateProfile'),{code:'account-deletion-in-progress'});
});
test('deletion retry can finish Auth cleanup after data tombstone was written',async(t)=>{
  mockState(t,{status:'processing'},{deletedAt:1});
  await assertAccountOperationAllowed(uid,'deleteAccount');
  await assert.rejects(assertAccountOperationAllowed(uid,'updateProfile'),{code:'account-deleted'});
});
test('HTTP handler rejects before operation dispatch despite valid auth and App Check',async(t)=>{
  mockState(t,{status:'processing'});
  t.mock.method(getAuth(),'verifyIdToken',async()=>({uid}));
  t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
  t.mock.method(require('firebase-functions/logger'),'warn',()=>{});
  const req={method:'POST',path:'/updateProfile',body:{},get(name){
    return {authorization:'Bearer valid-test-token','x-firebase-appcheck':'valid-app-check'}[name.toLowerCase()]||'';
  }};
  let status,body;
  const res={status(value){status=value;return this;},json(value){body=value;}};
  await handler(req,res);
  assert.equal(status,409);
  assert.equal(body.error,'account-deletion-in-progress');
});
