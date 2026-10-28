'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const logger=require('firebase-functions/logger');
const api=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');

const uid='v238_migration_owner',otherUid='v238_other_owner';
const profilePath='users/'+uid,accountPath='battleV1Accounts/'+uid;
const client={platform:'android',build:17,protocolVersion:'LUNO_BATTLE_V1'};
const tombstone={status:'complete',completedAt:12345};
const otherAccount={accountJson:JSON.stringify({migrationVersion:1,rating:733,deck:['retained']})};

function erase(store){
  store.write('accountDeletions/'+api.hash(uid),tombstone);
  store.write('deletedAccounts/'+api.hash(uid),{deletedAt:12345});
  store.write(profilePath,null);
  store.write(accountPath,null);
}
function setup(t,options={}){
  const db=memoryDatabase(t,{
    users:{[uid]:api.starterProfile(uid,'v238_migration_owner')},
    battleV1Accounts:{[otherUid]:otherAccount},
  },options);
  t.mock.method(getAuth(),'verifyIdToken',async()=>({uid}));
  t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
  for(const level of ['info','warn','error'])t.mock.method(logger,level,()=>{});
  return db;
}
async function request(){
  const headers={authorization:'Bearer local-test-identity','x-firebase-appcheck':'local-test-attestation','x-luno-request-id':'v238-migration-request'};
  let status,body;
  await api.handler({method:'POST',path:'/getBattleV1Deck',body:{client},get:name=>headers[name.toLowerCase()]||''},
    {set(){return this;},status(value){status=value;return this;},json(value){body=value;}});
  return {status,body};
}
function assertErased(db,result){
  assert.equal(result.status,403,JSON.stringify(result.body));
  assert.equal(result.body.error,'account-deleted');
  assert.equal(result.body.deck,undefined);
  assert.equal(db.read(profilePath),null);
  assert.equal(db.read(accountPath),null,'A late migration must not restore erased V1 account data.');
  assert.deepEqual(db.read('battleV1Accounts/'+otherUid),otherAccount);
  assert.deepEqual(db.read('accountDeletions/'+api.hash(uid)),tombstone);
}

for(const point of ['after-profile-read','before-account-write','after-account-write']){
  test('V1 deck migration does not restore erased account data '+point,async t=>{
    let erased=false;
    const db=setup(t,{
      afterRead(path,count,store){
        if(!erased&&point==='after-profile-read'&&path===profilePath){erased=true;erase(store);}
      },
      beforeTransaction(path,count,store){
        if(!erased&&point==='before-account-write'&&path===accountPath){erased=true;erase(store);}
      },
      afterTransaction(path,count,store){
        if(!erased&&point==='after-account-write'&&path===accountPath){erased=true;erase(store);}
      },
    });
    const result=await request();
    assert.equal(erased,true,'The requested deletion race must be reached.');
    assertErased(db,result);
  });
}

test('healthy V1 deck migration still creates a stable owner account',async t=>{
  const db=setup(t),first=await request();
  assert.equal(first.status,200,JSON.stringify(first.body));
  assert.equal(first.body.protocolVersion,client.protocolVersion);
  assert.equal(first.body.deck.length,10);
  const saved=structuredClone(db.read(accountPath));
  assert.equal(JSON.parse(saved.accountJson).migrationVersion,1);
  const replay=await request();
  assert.equal(replay.status,200);
  assert.deepEqual(replay.body.deck,first.body.deck);
  assert.deepEqual(db.read(accountPath),saved);
  assert.deepEqual(db.read('battleV1Accounts/'+otherUid),otherAccount);
  assert.ok(db.transactions.filter(tx=>tx.path===accountPath).every(tx=>tx.applyLocally===false));
});
