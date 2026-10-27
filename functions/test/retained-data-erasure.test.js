'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {getAuth}=require('firebase-admin/auth');
const {deleteAccount,starterProfile,hash}=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');
const uid='retained_player',other='retained_other',at=1900000000000;
function claim(owner=uid){return {uid:owner,productId:'gold_5000',status:'complete',kind:'inapp',active:true,grantGold:5000,grantGems:0,verifiedAt:at-3000,grantedAt:at-2000,completedAt:at-1000,orderIdHash:'a'.repeat(64),lastError:'email person@example.com token secret',email:'person@example.com',purchaseToken:'secret',orderId:'GPA-raw-order',nested:{username:'private-name'}};}
function report(reporter=uid,target=other){return {reportId:'owned-report',reporterUid:reporter,targetUid:target,reason:'harassment',status:'open',createdAt:at-1000,details:'private email person@example.com',messageText:'private message',conversationId:[reporter,target].sort().join('_'),messageId:'private-message',unexpected:{name:'private-name'}};}
function seed(){return {users:{[uid]:starterProfile(uid,'retained_name')},purchaseClaims:{owned:claim(),foreign:claim(other)},moderationReports:{owned:report(),foreign:report(other,'third_player')}};}
async function erase(t,id='retained-delete'){
  t.mock.method(getAuth(),'deleteUser',async()=>{});
  return deleteAccount({uid,token:{firebase:{sign_in_provider:'anonymous'}},body:{confirm:true},requestId:id});
}

test('deletion retains only pseudonymous purchase metadata, never raw private fields',async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,seed());await erase(t);const retained=db.read('purchaseClaims/owned');
  assert.equal(retained.uid,hash(uid));assert.equal(retained.accountDeleted,true);assert.equal(retained.active,false);
  assert.equal(retained.productId,'gold_5000');assert.equal(retained.grantGold,5000);assert.equal(retained.status,'complete');assert.equal(retained.orderIdHash,'a'.repeat(64));
  assert.equal(retained.anonymizedAt,at);for(const key of ['lastError','email','purchaseToken','orderId','nested'])assert.equal(retained[key],undefined,key);
  assert.deepEqual(db.read('purchaseClaims/foreign'),claim(other));assert.equal(db.read('users/'+uid),null);
});
test('report retirement removes free text, raw conversation identifiers and unknown fields',async t=>{
  t.mock.method(Date,'now',()=>at);const db=memoryDatabase(t,seed());await erase(t);const retained=db.read('moderationReports/owned');
  assert.equal(retained.reporterUid,hash(uid));assert.equal(retained.reporterDeleted,true);assert.equal(retained.targetUid,other);
  assert.equal(retained.reason,'harassment');assert.equal(retained.status,'open');assert.equal(retained.createdAt,at-1000);
  for(const key of ['details','messageText','conversationId','messageId','unexpected'])assert.equal(retained[key],undefined,key);
  assert.deepEqual(db.read('moderationReports/foreign'),report(other,'third_player'));
});
test('deleting the report target preserves the live reporter and retires only the target',async t=>{
  const data=seed();data.moderationReports.owned=report(other,uid);const db=memoryDatabase(t,data);await erase(t);
  const retained=db.read('moderationReports/owned');assert.equal(retained.reporterUid,other);assert.equal(retained.targetUid,hash(uid));assert.equal(retained.targetDeleted,true);assert.notEqual(retained.reporterDeleted,true);
});
test('report appearing in both owner queries is retired once without losing either marker',async t=>{
  const data=seed();data.moderationReports.owned=report(uid,uid);const db=memoryDatabase(t,data);await erase(t);
  const retained=db.read('moderationReports/owned');assert.equal(retained.reporterUid,hash(uid));assert.equal(retained.targetUid,hash(uid));assert.equal(retained.reporterDeleted,true);assert.equal(retained.targetDeleted,true);
  assert.equal(db.transactions.filter(tx=>tx.path==='moderationReports/owned').length,1);
});
for(const root of ['purchaseClaims','moderationReports'])test(`${root} owner changes after query are preserved`,async t=>{
  const db=memoryDatabase(t,seed(),{afterRead(path,count,{write}){if(path===root&&count===1)write(root+'/owned',root==='purchaseClaims'?claim(other):report(other,'third_player'));}});
  await erase(t);assert.deepEqual(db.read(root+'/owned'),root==='purchaseClaims'?claim(other):report(other,'third_player'));
});
for(const root of ['purchaseClaims','moderationReports'])test(`${root} deletion during cleanup cannot recreate the record`,async t=>{
  const db=memoryDatabase(t,seed(),{beforeTransaction(path,count,{write}){if(path===root+'/owned')write(path,null);}});
  await erase(t);assert.equal(db.read(root+'/owned'),null);
});
for(const root of ['purchaseClaims','moderationReports'])test(`${root} transaction retry cannot overwrite a new owner`,async t=>{
  const replacement=root==='purchaseClaims'?claim(other):report(other,'third_player');
  const db=memoryDatabase(t,seed(),{retry(path,count,update,next,{write}){if(path===root+'/owned'){write(path,replacement);return update(structuredClone(replacement));}return next;}});
  await erase(t);assert.deepEqual(db.read(root+'/owned'),replacement);
});
test('legacy previously hashed records are scrubbed during a resumed deletion',async t=>{
  t.mock.method(Date,'now',()=>at);const data=seed();data.purchaseClaims.owned={...claim(hash(uid)),anonymizedAt:at-100};
  data.moderationReports.owned={...report(hash(uid),other),anonymizedAt:at-100};
  data.accountDeletions={[hash(uid)]:{status:'processing'}};data.deletedAccounts={[hash(uid)]:{deletedAt:at-100}};delete data.users;
  const db=memoryDatabase(t,data);await erase(t);assert.equal(db.read('purchaseClaims/owned/email'),null);assert.equal(db.read('purchaseClaims/owned/anonymizedAt'),at-100);
  assert.equal(db.read('moderationReports/owned/conversationId'),null);assert.equal(db.read('moderationReports/owned/reporterDeleted'),true);
});
test('already hashed live UID without retirement proof is not treated as this account',async t=>{
  const data=seed();data.purchaseClaims.hashed=claim(hash(uid));data.moderationReports.hashed=report(hash(uid),other);const db=memoryDatabase(t,data);await erase(t);
  assert.deepEqual(db.read('purchaseClaims/hashed'),data.purchaseClaims.hashed);assert.deepEqual(db.read('moderationReports/hashed'),data.moderationReports.hashed);
});
test('cleanup failure leaves deletion resumable and does not delete Auth prematurely',async t=>{
  let fail=true,authCalls=0;const db=memoryDatabase(t,seed(),{beforeTransaction(path){if(fail&&path==='purchaseClaims/owned')throw new Error('retention-write-failed');}});
  t.mock.method(getAuth(),'deleteUser',async()=>{authCalls++;});
  const context={uid,token:{firebase:{sign_in_provider:'anonymous'}},body:{confirm:true},requestId:'retry-cleanup'};
  await assert.rejects(deleteAccount(context),/retention-write-failed/);assert.equal(authCalls,0);assert.equal(db.read('accountDeletions/'+hash(uid)+'/status'),'processing');
  fail=false;assert.equal((await deleteAccount(context)).deleted,true);assert.equal(authCalls,1);assert.equal(db.read('purchaseClaims/owned/accountDeleted'),true);
});
test('Auth failure can resume without changing the original anonymization timestamp',async t=>{
  let clock=at,calls=0;t.mock.method(Date,'now',()=>clock);const db=memoryDatabase(t,seed());t.mock.method(getAuth(),'deleteUser',async()=>{if(++calls===1)throw new Error('auth-unavailable');});
  const context={uid,token:{firebase:{sign_in_provider:'anonymous'}},body:{confirm:true},requestId:'auth-retry-retained'};
  await assert.rejects(deleteAccount(context),/auth-unavailable/);clock+=1000;await deleteAccount(context);
  assert.equal(db.read('purchaseClaims/owned/anonymizedAt'),at);assert.equal(db.read('moderationReports/owned/anonymizedAt'),at);
});
for(const [field,value] of [['grantGold',-1],['grantGems',1.2],['orderIdHash',['a'.repeat(64)]],['expiry','not-time'],['productId','private@example.com'],['status','private email']])test(`invalid retained purchase field ${field} is discarded`,async t=>{
  const data=seed();data.purchaseClaims.owned[field]=value;const db=memoryDatabase(t,data);await erase(t);assert.equal(db.read('purchaseClaims/owned/'+field),null);
});
test('private retention roots remain closed to clients and owner queries are indexed',()=>{
  const rules=require('../../database.rules.production.json').rules;
  for(const root of ['purchaseClaims','moderationReports']){assert.equal(rules[root]['.read'],false);assert.equal(rules[root]['.write'],false);}
  assert.ok(rules.purchaseClaims['.indexOn'].includes('uid'));assert.ok(rules.moderationReports['.indexOn'].includes('reporterUid'));assert.ok(rules.moderationReports['.indexOn'].includes('targetUid'));
});
