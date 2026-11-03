'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {fixture}=require('./helpers/battle-v1-fixture');
const {authority,protocol}=require('../lib/battle-v1');

async function terminal(){
 const f=fixture();await f.enable();
 await f.api.enqueueBattleV1(f.context('alice',{client:f.client},'round5-ack-alice'));
 const joined=await f.api.enqueueBattleV1(f.context('bob',{client:f.client},'round5-ack-bob'));
 f.id=joined.matchId;
 await f.api.transact(f.id,'alice',m=>({match:authority.finishMatch(m,{reason:'resign',winner:'b',finishedAt:1001})}));
 return f;
}
const resultBody=f=>({matchId:f.id,protocolVersion:protocol.PROTOCOL});
const pending=f=>f.api.getBattleV1(f.context('alice',{matchId:'',protocolVersion:protocol.PROTOCOL}));

test('a result acknowledged after ordinary settlement stays absent on reconnect',async()=>{
 const f=await terminal();await f.api.settle(f.id,'alice');
 const acknowledged=await f.api.ackBattleV1Result(f.context('alice',resultBody(f)));
 assert.equal(acknowledged.acknowledged,true);assert.equal((await pending(f)).status,'idle');
 assert.equal(f.read('battleV1Control/lastMatch/bob'),f.id,'The other player retains its own result.');
});

test('acknowledgement after the complete projection survives its delayed settlement cleanup',async()=>{
 const f=await terminal(),publish=f.api.publish;
 let entered,release,held=false;
 const reached=new Promise(resolve=>{entered=resolve;}),resume=new Promise(resolve=>{release=resolve;});
 f.api.publish=async match=>{
  await publish(match);
  if(!held&&match.settlementStatus==='complete'){held=true;entered();await resume;}
 };
 const settling=f.api.settle(f.id,'alice');
 try{
  await reached;
  assert.equal(f.read('matchesV1/'+f.id).public.settlementStatus,'complete','A subscribed client can now see the settled result.');
  const acknowledged=await f.api.ackBattleV1Result(f.context('alice',resultBody(f)));
  assert.equal(acknowledged.acknowledged,true);
 }finally{release();}
 await settling;
 assert.equal((await pending(f)).status,'idle','A successful acknowledgement must survive the cleanup that publishes the last-match pointer.');
 assert.equal(f.read('battleV1Control/lastMatch/alice'),undefined);
 assert.equal(f.read('battleV1Control/lastMatch/bob'),f.id,'The other player still owns an unacknowledged result.');
});

test('acknowledging an old result preserves a newer active match mapping',async()=>{
 const f=await terminal();await f.api.settle(f.id,'alice');
 const newer='bv1_'+'8f'.repeat(16);f.write('battleV1Control/active/alice',newer);
 await f.api.ackBattleV1Result(f.context('alice',resultBody(f)));
 assert.equal(f.read('battleV1Control/active/alice'),newer);
 assert.equal(f.read('battleV1Control/lastMatch/alice'),undefined);
});
