'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {getDatabase,ServerValue}=require('firebase-admin/database');
const api=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');

test('shared mock selects owned conversations and excludes foreign nested membership',async t=>{
  const owned={members:{v220_owner:true}};
  memoryDatabase(t,{dm:{owned,foreign:{members:{v220_other:true}}}});
  const snapshot=await getDatabase().ref('dm').orderByChild('members/v220_owner').equalTo(true).get();
  assert.deepEqual(snapshot.val(),{owned});
  assert.equal(Object.hasOwn(snapshot.val(),'foreign'),false);
  assert.equal(snapshot.exists(),true);
});

test('V219 shared mock retains empty objects and unresolved server timestamps',async t=>{
  const store=memoryDatabase(t);
  await getDatabase().ref('probe').set({empty:{},createdAt:ServerValue.TIMESTAMP});
  assert.deepEqual(store.read('probe'),{empty:{},createdAt:{'.sv':'timestamp'}});
});

test('V219 shared mock accepts overlapping updates forbidden by the real SDK',async t=>{
  const store=memoryDatabase(t);
  await getDatabase().ref().update({'probe':{a:1},'probe/a':2});
  assert.deepEqual(store.read('probe'),{a:2});
});

test('V219 shared mock retries a cold absent transaction twice rather than once',async t=>{
  memoryDatabase(t);let callbacks=0;
  await getDatabase().ref('absent').transaction(value=>{callbacks++;return value;});
  assert.equal(callbacks,2);
});
