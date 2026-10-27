'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {getDatabase}=require('firebase-admin/database');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const api=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');
const {profiles,syntheticConversation,request}=require('../tools/v220-support.cjs');
const sender='v220_sender',recipient='v220_recipient';

function setup(t,conversations={}){
  const store=memoryDatabase(t,{users:profiles(api,[sender,recipient]),dm:conversations});
  const db=getDatabase(),original=db.ref.bind(db),calls={once:0,get:0};let pushed=0;
  t.mock.method(getAuth(),'verifyIdToken',async uid=>({uid,auth_time:Math.floor(Date.now()/1000),firebase:{sign_in_provider:'anonymous'}}));
  t.mock.method(getAuth(),'deleteUser',async()=>{});
  t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
  t.mock.method(db,'ref',(location='')=>{
    const node=original(location);
    return {...node,orderByChild(child){
      if(location!=='dm')return node.orderByChild(child);
      assert.equal(child,'members/'+sender);
      return {equalTo(expected){
        assert.equal(expected,true);
        return {
          async get(){calls.get++;throw new Error('Regression: indexed get cannot read dynamic membership.');},
          async once(event){
            calls.once++;assert.equal(event,'value');await Promise.resolve();
            const rows=Object.fromEntries(Object.entries(store.read('dm')||{}).filter(([,value])=>value.members?.[sender]===true));
            return {val:()=>Object.keys(rows).length?structuredClone(rows):null};
          }
        };
      }};
    },push(value){
      if(arguments.length)return node.push(value);
      const key='-v220_'+String(++pushed).padStart(14,'0');return {...original(location+'/'+key),key};
    }};
  });
  return {store,calls};
}

test('runtime fresh DM uses one-time membership query, never failing indexed get',async t=>{
  const {store,calls}=setup(t);
  const result=await request(api,sender,'sendDirectMessage',{targetUid:recipient,text:'Runtime once regression'},'v220-once-unit');
  assert.equal(result.status,200,JSON.stringify(result));assert.equal(calls.once,1);assert.equal(calls.get,0);
  assert.equal(Object.keys(store.read('dm/'+api.conversationId(sender,recipient)+'/msgs')).length,1);
});

test('runtime account deletion discovers and erases orphan membership with once',async t=>{
  const key=api.conversationId(sender,recipient);
  const {store,calls}=setup(t,{[key]:syntheticConversation(api,sender,recipient,1)});
  const result=await request(api,sender,'deleteAccount',{confirm:true},'v220-once-delete-unit');
  assert.equal(result.status,200,JSON.stringify(result));assert.equal(calls.once,1);assert.equal(calls.get,0);
  assert.equal(store.read('dm/'+key),null);assert.equal(store.read('users/'+sender),null);
  assert.ok(store.read('users/'+recipient));
});

test('runtime membership read change does not bypass deleted-account gating',async t=>{
  const {store,calls}=setup(t);store.write('deletedAccounts/'+api.hash(sender),{deletedAt:Date.now()});
  const result=await request(api,sender,'sendDirectMessage',{targetUid:recipient,text:'must not send'},'v220-deleted-unit');
  assert.equal(result.status,403);assert.equal(result.body.error,'account-deleted');
  assert.equal(calls.once,0);assert.equal(calls.get,0);assert.equal(store.read('dm/'+api.conversationId(sender,recipient)),null);
});
