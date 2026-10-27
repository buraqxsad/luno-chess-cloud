'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {isDeepStrictEqual}=require('node:util');
const {getDatabase}=require('firebase-admin/database');
const {acknowledgeDirectMessage,markDirectMessageRead,hash}=require('../index.js')._test;
const uid='reader1',targetUid='sender1';
const snap=value=>({val:()=>structuredClone(value),exists:()=>value!==null});
const inbox=(id='message1',extra={})=>Object.assign({messageId:id,last:'Hello',ts:100,unread:true,name:'sender_name'},extra);

function fixture(t,initial,options={}){
  let current=structuredClone(initial),writes=0,transactions=0;
  const reads=[];
  t.mock.method(getDatabase(),'ref',path=>{
    if(path===`accountDeletions/${hash(uid)}`||path===`deletedAccounts/${hash(uid)}`)return {async get(){return snap(null);}};
    if(path.startsWith('serverRateLimits/'))return {async transaction(update){const next=update(0);return {committed:next!==undefined,snapshot:snap(next)};}};
    if(path===`users/${targetUid}`)return {async get(){return snap({username:'sender_name'});}};
    if(path.startsWith('blocks/'))return {async get(){return snap(options.blocked?true:null);}};
    if(path===`dm/${uid}_${targetUid}/members/${uid}`)return {async get(){return snap(options.member===false?null:true);}};
    if(path.startsWith(`dm/${uid}_${targetUid}/msgs/`))return {async get(){reads.push(path);return snap(options.seen||null);}};
    assert.equal(path,`dmInbox/${uid}/${targetUid}`);
    return {
      async get(){reads.push(path);if(options.readFailure)throw new Error('read-unavailable');return snap(initial);},
      async transaction(update){
        transactions++;
        if(options.transactionFailure)throw new Error('transaction-unavailable');
        if(Object.prototype.hasOwnProperty.call(options,'beforeTransaction'))current=structuredClone(options.beforeTransaction);
        if(options.coldStart&&update(null)===undefined)return {committed:false,snapshot:snap(null)};
        let next=update(structuredClone(current));
        if(Object.prototype.hasOwnProperty.call(options,'retryValue')){
          current=structuredClone(options.retryValue);next=update(structuredClone(current));
        }
        if(next!==undefined){if(!isDeepStrictEqual(current,next))writes++;current=structuredClone(next);}
        return {committed:next!==undefined,snapshot:snap(current)};
      },
    };
  });
  return {get value(){return current;},get writes(){return writes;},get transactions(){return transactions;},reads};
}

test('observed inbox message is marked atomically without losing summary fields',async t=>{
  const db=fixture(t,inbox());
  assert.equal((await acknowledgeDirectMessage(uid,targetUid,'message1',true)).marked,true);
  assert.equal(db.value.unread,false);assert.equal(db.value.name,'sender_name');
  assert.equal(db.value.lastReadMessageId,'message1');assert.deepEqual(db.value.lastReadAt,{'.sv':'timestamp'});
});
test('cold transaction cache fetches server row before acknowledging it',async t=>{
  const db=fixture(t,inbox(),{coldStart:true});
  assert.equal((await acknowledgeDirectMessage(uid,targetUid,'message1',true)).marked,true);
  assert.equal(db.value.unread,false);assert.equal(db.writes,1);
});
test('cold transaction cache does not clear a newer server message',async t=>{
  const newer=inbox('message2'),db=fixture(t,inbox(),{coldStart:true,beforeTransaction:newer});
  assert.equal((await acknowledgeDirectMessage(uid,targetUid,'message1',true)).marked,false);
  assert.deepEqual(db.value,newer);assert.equal(db.writes,0);
});
test('cold transaction cache does not recreate deleted server inbox',async t=>{
  const db=fixture(t,inbox(),{coldStart:true,beforeTransaction:null});
  assert.equal((await acknowledgeDirectMessage(uid,targetUid,'message1',true)).marked,false);
  assert.equal(db.value,null);assert.equal(db.writes,0);
});
for(const phase of ['beforeTransaction','retryValue']){
  test(`new message at ${phase} remains unread, including identical text/time`,async t=>{
    const newer=inbox('message2'),db=fixture(t,inbox(),{[phase]:newer});
    assert.equal((await acknowledgeDirectMessage(uid,targetUid,'message1',true)).marked,false);
    assert.deepEqual(db.value,newer);assert.equal(db.writes,0);
  });
  test(`deleted inbox at ${phase} is not recreated by receipt`,async t=>{
    const db=fixture(t,inbox(),{[phase]:null});
    assert.equal((await acknowledgeDirectMessage(uid,targetUid,'message1',true)).marked,false);
    assert.equal(db.value,null);assert.equal(db.writes,0);
  });
}
test('older observed ID does not clear an already newer inbox',async t=>{
  const db=fixture(t,inbox('message2'));
  assert.equal((await acknowledgeDirectMessage(uid,targetUid,'message1',true)).marked,false);
  assert.equal(db.transactions,0);assert.equal(db.value.unread,true);
});
test('new-client opening with no observed message performs no inbox read or write',async t=>{
  const db=fixture(t,inbox());
  assert.equal((await acknowledgeDirectMessage(uid,targetUid,null,true)).marked,false);
  assert.deepEqual(db.reads,[]);assert.equal(db.writes,0);
});
test('old client without a cursor still uses captured version, not blind unread=false',async t=>{
  const db=fixture(t,inbox(),{beforeTransaction:inbox('message2')});
  assert.equal((await acknowledgeDirectMessage(uid,targetUid,null,false)).marked,false);assert.equal(db.value.unread,true);
});
test('old client can acknowledge a stable legacy summary',async t=>{
  const legacy=inbox();delete legacy.messageId;const db=fixture(t,legacy);
  assert.equal((await acknowledgeDirectMessage(uid,targetUid,null,false)).marked,true);assert.equal(db.value.unread,false);
});
test('observed legacy message requires exact content/time and participant',async t=>{
  const legacy=inbox();delete legacy.messageId;
  const db=fixture(t,legacy,{seen:{from:targetUid,text:'Hello',ts:100}});
  assert.equal((await acknowledgeDirectMessage(uid,targetUid,'message1',true)).marked,true);assert.equal(db.value.lastReadMessageId,'message1');
});
for(const seen of [null,{from:'intruder',text:'Hello',ts:100},{from:targetUid,text:'Other',ts:100},{from:targetUid,text:'Hello',ts:101}]){
  test(`mismatched legacy cursor preserves unread ${JSON.stringify(seen)}`,async t=>{
    const legacy=inbox();delete legacy.messageId;const db=fixture(t,legacy,{seen});
    assert.equal((await acknowledgeDirectMessage(uid,targetUid,'message1',true)).marked,false);
    assert.equal(db.transactions,0);assert.equal(db.value.unread,true);
  });
}
test('missing inbox is not recreated',async t=>{
  const db=fixture(t,null);assert.equal((await acknowledgeDirectMessage(uid,targetUid,'message1',true)).marked,false);assert.equal(db.transactions,0);
});
for(const failure of ['readFailure','transactionFailure']){
  test(`receipt ${failure} propagates without writing success`,async t=>{
    const db=fixture(t,inbox(),{[failure]:true});
    await assert.rejects(acknowledgeDirectMessage(uid,targetUid,'message1',true),/unavailable/);assert.equal(db.value.unread,true);assert.equal(db.writes,0);
  });
}
test('route accepts observed cursor after membership and block checks',async t=>{
  const db=fixture(t,inbox());const result=await markDirectMessageRead({uid,body:{targetUid,lastMessageId:'message1'}});
  assert.equal(result.marked,true);assert.equal(db.value.unread,false);
});
for(const denied of ['blocked','member']){
  test(`route rejects ${denied} before receipt mutation`,async t=>{
    const db=fixture(t,inbox(),denied==='blocked'?{blocked:true}:{member:false});
    await assert.rejects(markDirectMessageRead({uid,body:{targetUid,lastMessageId:'message1'}}),e=>e.code===(denied==='blocked'?'user-blocked':'conversation-denied'));
    assert.equal(db.transactions,0);assert.equal(db.writes,0);
  });
}
for(const invalid of ['','../message',{},10]){
  test(`route rejects malformed cursor ${JSON.stringify(invalid)}`,async t=>{
    const db=fixture(t,inbox());await assert.rejects(markDirectMessageRead({uid,body:{targetUid,lastMessageId:invalid}}),e=>e.code==='invalid-message-id');
    assert.deepEqual(db.reads,[]);assert.equal(db.transactions,0);
  });
}
