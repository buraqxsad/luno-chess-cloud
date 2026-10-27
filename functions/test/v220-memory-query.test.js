'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
require('../index');
const {getDatabase}=require('firebase-admin/database');
const {memoryDatabase}=require('./helpers/memory-database');

test('one-time mock query applies nested exact membership like RTDB',async t=>{
  const owned={members:{alice:true}},other={members:{bob:true}};
  memoryDatabase(t,{dm:{owned,other}});
  const result=await getDatabase().ref('dm').orderByChild('members/alice').equalTo(true).once('value');
  assert.deepEqual(result.val(),{owned});
});

test('one-time mock query observes later membership removal',async t=>{
  const db=memoryDatabase(t,{dm:{owned:{members:{alice:true}}}});
  const query=getDatabase().ref('dm').orderByChild('members/alice').equalTo(true);
  assert.deepEqual((await query.once('value')).val(),{owned:{members:{alice:true}}});
  db.write('dm/owned/members/alice',null);
  assert.deepEqual((await query.once('value')).val(),{});
});

test('one-time mock query rejects events it does not model',async t=>{
  memoryDatabase(t,{});
  await assert.rejects(getDatabase().ref('dm').once('child_added'),/Only one-time value/);
});
