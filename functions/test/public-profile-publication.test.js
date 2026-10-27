'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {getDatabase}=require('firebase-admin/database');
const {starterProfile,publicProfile,publishPublicProfile}=require('../index.js')._test;

function profile(at,bio,revision=1){
  return Object.assign(starterProfile('publisher','publisher_name'),{
    updatedAt:at,bio,usernameRevision:revision,
  });
}

function database(t,initial=null){
  let current=initial;
  let failNext=false;
  let writes=0;
  t.mock.method(getDatabase(),'ref',path=>{
    if(path.startsWith('accountDeletions/')||path.startsWith('deletedAccounts/'))return {async get(){return {val:()=>null,exists:()=>false};}};
    assert.equal(path,'publicProfiles/publisher');
    return {async transaction(update){
      if(failNext){failNext=false;throw new Error('publication-unavailable');}
      const next=update(structuredClone(current));
      if(next!==undefined){current=structuredClone(next);writes++;}
      return {committed:next!==undefined,snapshot:{val:()=>structuredClone(current)}};
    }};
  });
  return {get value(){return current;},get writes(){return writes;},fail(){failNext=true;}};
}

test('late publication cannot replace a newer biography at the same username revision',async t=>{
  const db=database(t);
  await publishPublicProfile('publisher',profile(200,'new biography'),200);
  await publishPublicProfile('publisher',profile(100,'old biography'),300);
  assert.equal(db.value.bio,'new biography');
  assert.equal(db.value.profileUpdatedAt,200);
  assert.equal(db.writes,1);
});

test('cleared biography cannot be resurrected by an older publication',async t=>{
  const db=database(t);
  await publishPublicProfile('publisher',profile(200,''),200);
  await publishPublicProfile('publisher',profile(100,'removed biography'),300);
  assert.equal(db.value.bio,'');
});

test('new username revision still outranks an old revision with a later clock',async t=>{
  const db=database(t,publicProfile(profile(100,'new name',3),100));
  await publishPublicProfile('publisher',profile(500,'old name',2),500);
  assert.equal(db.value.usernameRevision,3);
  assert.equal(db.value.bio,'new name');
});

test('publication failure propagates and retry restores the public view',async t=>{
  const db=database(t);
  db.fail();
  await assert.rejects(publishPublicProfile('publisher',profile(100,'saved bio'),100),/publication-unavailable/);
  assert.equal(db.value,null);
  await publishPublicProfile('publisher',profile(100,'saved bio'),200);
  assert.equal(db.value.bio,'saved bio');
  assert.equal(db.writes,1);
});

test('retry of failed older publication cannot overwrite a later successful save',async t=>{
  const db=database(t);
  db.fail();
  await assert.rejects(publishPublicProfile('publisher',profile(100,'old bio'),100));
  await publishPublicProfile('publisher',profile(200,'new bio'),200);
  await publishPublicProfile('publisher',profile(100,'old bio'),300);
  assert.equal(db.value.bio,'new bio');
  assert.equal(db.writes,1);
});

test('legacy public mirrors without source timestamp can be migrated',async t=>{
  const legacy=publicProfile(profile(50,'legacy bio'),50);
  delete legacy.profileUpdatedAt;
  legacy.updatedAt=999999;
  const db=database(t,legacy);
  await publishPublicProfile('publisher',profile(100,'current bio'),100);
  assert.equal(db.value.bio,'current bio');
  assert.equal(db.value.profileUpdatedAt,100);
});

test('transaction retry rechecks the latest public state instead of cached null',async t=>{
  const newer=publicProfile(profile(200,'newer bio'),200);
  t.mock.method(getDatabase(),'ref',path=>path.startsWith('publicProfiles/')?({async transaction(update){
    assert.equal(update(null).bio,'older bio');
    assert.equal(update(newer),undefined);
    return {committed:false,snapshot:{val:()=>newer}};
  }}):({async get(){return {val:()=>null,exists:()=>false};}}));
  await publishPublicProfile('publisher',profile(100,'older bio'),300);
});

test('republication at the same source time can refresh expiring premium',async t=>{
  const source=profile(100,'same bio');
  source.premiumUntil=200;
  const db=database(t);
  await publishPublicProfile('publisher',source,150);
  assert.equal(db.value.isPremium,true);
  await publishPublicProfile('publisher',source,250);
  assert.equal(db.value.isPremium,false);
});

test('delayed projection cannot re-enable premium already expired in a newer projection',async t=>{
  const source=profile(100,'same bio');
  source.premiumUntil=200;
  const db=database(t);
  await publishPublicProfile('publisher',source,250);
  await publishPublicProfile('publisher',source,150);
  assert.equal(db.value.isPremium,false);
  assert.equal(db.value.profileProjectedAt,250);
  assert.equal(db.writes,1);
});
