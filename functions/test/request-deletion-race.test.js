'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {idempotent,hash}=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');
const uid='request_player',id='request-race',operation='test-reward',path=`serverRequests/${uid}/${hash(id).slice(0,48)}`;
function deleting(db){db.write('accountDeletions/'+hash(uid),{status:'processing'});db.write(`serverRequests/${uid}`,null);}

test('an operation completed after deletion cannot recreate its cached success',async t=>{
  const db=memoryDatabase(t);
  await assert.rejects(idempotent(uid,id,operation,async()=>{deleting(db);return {ok:true,gold:99};}),{code:'account-deletion-in-progress'});
  assert.equal(db.read(path),null);
});

test('deletion during cached-result completion suppresses the response and clears only its own result',async t=>{
  const db=memoryDatabase(t,{}, {afterTransaction(currentPath,count,{write}){
    if(currentPath===path&&count===2)write('accountDeletions/'+hash(uid),{status:'processing'});
  }});
  await assert.rejects(idempotent(uid,id,operation,async()=>({ok:true})),{code:'account-deletion-in-progress'});
  assert.equal(db.read(path),null);
});

test('a removed processing claim is not resurrected by the result write',async t=>{
  const db=memoryDatabase(t);
  await assert.rejects(idempotent(uid,id,operation,async()=>{db.write(path,null);return {ok:true};}),{code:'request-state-changed'});
  assert.equal(db.read(path),null);
});

test('a late result cannot overwrite a replacement request owner',async t=>{
  const db=memoryDatabase(t),replacement={operation,status:'processing',ownerToken:'replacement',createdAt:5};
  await assert.rejects(idempotent(uid,id,operation,async()=>{db.write(path,replacement);return {ok:true};}),{code:'request-state-changed'});
  assert.deepEqual(db.read(path),replacement);
});

test('a failing old operation cannot remove a replacement processing claim',async t=>{
  const db=memoryDatabase(t),replacement={operation,status:'processing',ownerToken:'replacement',createdAt:5};
  await assert.rejects(idempotent(uid,id,operation,async()=>{db.write(path,replacement);throw new Error('work-failed');}),/work-failed/);
  assert.deepEqual(db.read(path),replacement);
});

test('a deleted account cannot replay an old completed result',async t=>{
  const db=memoryDatabase(t,{serverRequests:{[uid]:{[hash(id).slice(0,48)]:{operation,status:'complete',result:{gold:99}}}},deletedAccounts:{[hash(uid)]:{deletedAt:1}}});
  await assert.rejects(idempotent(uid,id,operation,async()=>assert.fail('must not run work')),{code:'account-deleted'});
  assert.ok(db.read(path));
});

test('healthy replay returns its existing result without running work or replacing the legacy claim',async t=>{
  const claim={operation,status:'complete',result:{gold:99}};
  const db=memoryDatabase(t,{serverRequests:{[uid]:{[hash(id).slice(0,48)]:claim}}},{cold:false});
  const result=await idempotent(uid,id,operation,async()=>assert.fail('must not run work'));
  assert.deepEqual(result,{gold:99,idempotent:true});assert.deepEqual(db.read(path),claim);
});

test('a healthy cold-cache request stores one owned result without speculative local writes',async t=>{
  const db=memoryDatabase(t),result=await idempotent(uid,id,operation,async()=>({gold:7}));
  assert.deepEqual(result,{gold:7});assert.equal(db.read(path).status,'complete');
  assert.match(db.read(path).ownerToken,/^[a-f0-9-]{36}$/);
  assert.deepEqual(db.read(path).result,{gold:7});
  assert.ok(db.transactions.filter(tx=>tx.path===path).every(tx=>tx.applyLocally===false));
  assert.ok(!db.writes.some(write=>write.path===path&&write.kind==='update'));
});

test('same-process duplicate requests share work and return one durable result',async t=>{
  const db=memoryDatabase(t);let runs=0;
  const results=await Promise.all(Array.from({length:12},()=>idempotent(uid,id,operation,async()=>{runs++;await new Promise(resolve=>setImmediate(resolve));return {gold:8};})));
  assert.equal(runs,1);assert.equal(results.filter(result=>result.idempotent===true).length,11);
  assert.equal(db.read(path).result.gold,8);
});

test('deletion while a same-process duplicate waits suppresses every response',async t=>{
  const db=memoryDatabase(t);let runs=0;
  const results=await Promise.allSettled(Array.from({length:4},()=>idempotent(uid,id,operation,async()=>{runs++;await new Promise(resolve=>setImmediate(resolve));deleting(db);return {gold:8};})));
  assert.equal(runs,1);assert.ok(results.every(result=>result.status==='rejected'&&result.reason.code==='account-deletion-in-progress'));
  assert.equal(db.read(path),null);
});

test('deletion during cache lookup cannot let a completed legacy response escape',async t=>{
  const initial={serverRequests:{[uid]:{[hash(id).slice(0,48)]:{operation,status:'complete',result:{gold:99}}}}};
  const db=memoryDatabase(t,initial,{afterTransaction(currentPath,count,{write}){
    if(currentPath===path&&count===1)write('deletedAccounts/'+hash(uid),{deletedAt:1});
  }});
  await assert.rejects(idempotent(uid,id,operation,async()=>assert.fail('must not run work')),{code:'account-deleted'});
  assert.equal(db.read(path).status,'complete');
});

test('a request identity cannot be reused for a different operation',async t=>{
  const db=memoryDatabase(t,{serverRequests:{[uid]:{[hash(id).slice(0,48)]:{operation:'different-operation',status:'complete',result:{gold:99}}}}});
  await assert.rejects(idempotent(uid,id,operation,async()=>assert.fail('must not run work')),{code:'request-id-conflict'});
  assert.equal(db.read(path).operation,'different-operation');
});

test('idempotent work failure cleans only the owning claim and leaves other accounts intact',async t=>{
  const otherPath=`serverRequests/other_player/${hash(id).slice(0,48)}`;
  const db=memoryDatabase(t,{serverRequests:{other_player:{[hash(id).slice(0,48)]:{operation,status:'processing',ownerToken:'other-token'}}}});
  await assert.rejects(idempotent(uid,id,operation,async()=>{throw new Error('failed');}),/failed/);
  assert.equal(db.read(path),null);assert.equal(db.read(otherPath).ownerToken,'other-token');
});

test('HTTP response gate rejects a non-idempotent success after account deletion starts',async t=>{
  const {getAuth}=require('firebase-admin/auth'),{getAppCheck}=require('firebase-admin/app-check');
  const {handler,starterProfile}=require('../index')._test;
  const db=memoryDatabase(t,{users:{[uid]:starterProfile(uid,'request_name')}},{afterRead(currentPath,count,{write}){
    if(currentPath==='users')write('accountDeletions/'+hash(uid),{status:'processing'});
  }});
  t.mock.method(getAuth(),'verifyIdToken',async()=>({uid}));
  t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
  t.mock.method(require('firebase-functions/logger'),'warn',()=>{});
  let status,body;
  const req={method:'POST',path:'/getLeaderboard',body:{mode:'collection'},get(name){return {authorization:'Bearer test-token','x-firebase-appcheck':'test-app-check',origin:'https://localhost'}[name.toLowerCase()]||'';}};
  await handler(req,{set(){return this;},status(value){status=value;return this;},json(value){body=value;}});
  assert.equal(status,409);assert.equal(body.error,'account-deletion-in-progress');assert.equal(body.results,undefined);
  assert.ok(db.read('accountDeletions/'+hash(uid)));
});

test('HTTP deletion still returns success after creating its final tombstone',async t=>{
  const {getAuth}=require('firebase-admin/auth'),{getAppCheck}=require('firebase-admin/app-check');
  const {handler,starterProfile}=require('../index')._test;
  const db=memoryDatabase(t,{users:{[uid]:starterProfile(uid,'request_name')}});
  t.mock.method(getAuth(),'verifyIdToken',async()=>({uid,firebase:{sign_in_provider:'anonymous'}}));
  t.mock.method(getAuth(),'deleteUser',async()=>{});
  t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
  t.mock.method(require('firebase-functions/logger'),'info',()=>{});
  let status,body;
  const req={method:'POST',path:'/deleteAccount',body:{confirm:true},get(name){return {authorization:'Bearer test-token','x-firebase-appcheck':'test-app-check',origin:'https://localhost'}[name.toLowerCase()]||'';}};
  await handler(req,{set(){return this;},status(value){status=value;return this;},json(value){body=value;}});
  assert.equal(status,200);assert.equal(body.deleted,true);assert.equal(db.read('accountDeletions/'+hash(uid)).status,'complete');
});
