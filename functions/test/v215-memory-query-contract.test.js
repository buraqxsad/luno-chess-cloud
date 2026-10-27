'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {initializeApp,getApps}=require('firebase-admin/app');
const {getDatabase}=require('firebase-admin/database');
const {memoryDatabase}=require('./helpers/memory-database');
if(!getApps().length)initializeApp({projectId:'demo-luno-v215-unit',databaseURL:'https://demo-luno-v215-unit-default-rtdb.firebaseio.com'});

test('memory query traverses Firebase key order and strict continuation bounds',async t=>{
  memoryDatabase(t,{rows:{b:true,'10':true,a:true,'2':true}});
  const root=getDatabase().ref('rows');
  const first=await root.orderByKey().limitToFirst(3).get(),keys=[];
  first.forEach(child=>{keys.push(child.key);assert.equal(child.val(),true);return false;});
  assert.deepEqual(keys,['2','10','a']);
  const remaining=await root.orderByKey().startAfter('10').limitToFirst(1).get(),later=[];
  remaining.forEach(child=>{later.push(child.key);});
  assert.deepEqual(later,['a']);
  assert.equal((await root.child('b').get()).key,'b');
  assert.equal((await root.child('absent').get()).exists(),false);
  let visited=0;assert.equal(first.forEach(()=>{visited++;return true;}),true);assert.equal(visited,1);
});

test('existing equality filters retain their selection and obey limits',async t=>{
  memoryDatabase(t,{rows:{a:{owner:'x'},b:{owner:'y'},c:{owner:'x'}},values:{a:'x',b:'y',c:'x'}});
  assert.deepEqual((await getDatabase().ref('rows').orderByChild('owner').equalTo('x').get()).val(),{a:{owner:'x'},c:{owner:'x'}});
  assert.deepEqual((await getDatabase().ref('values').orderByValue().equalTo('x').limitToFirst(1).get()).val(),{a:'x'});
});
