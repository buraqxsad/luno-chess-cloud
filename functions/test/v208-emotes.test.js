'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {fixture}=require('./helpers/battle-v1-fixture');
const {installBattleV1Emotes}=require('../lib/battle-v1-emotes');
const {protocol}=require('../lib/battle-v1');
const {STARTER}=require('../rules-v1/dist/src/model');
async function setup(){
  const f=fixture();installBattleV1Emotes(f.api,{requirePlayer:async uid=>{
    const p=f.read('users/'+uid);if(!p)throw Error('missing');return p;
  },rateLimit:async()=>{}});
  const id='bv1_'+ 'a'.repeat(32);
  await f.api.create(id,{uid:'alice',name:'Alice',bot:false},
    {uid:'bob',name:'Bob',bot:false},STARTER,STARTER,false);
  const body={matchId:id,protocolVersion:protocol.PROTOCOL};
  return {...f,id,body,send:(uid,emojiId='smile',request='one')=>
    f.api.sendBattleV1Emote(f.context(uid,{...body,emojiId},request)),
    get:(uid,after=0)=>f.api.getBattleV1Emotes(f.context(uid,{...body,after}))};
}
test('participants exchange emotes without touching gameplay or private projections',async()=>{
  const f=await setup(),before=JSON.stringify(f.read('matchSecretsV1/'+f.id));
  const event=(await f.send('alice')).event;
  assert.equal(event.side,'w');assert.equal(event.sequence,1);
  assert.equal((await f.get('bob')).events.length,1);
  assert.equal((await f.get('bob',1)).events.length,0);
  assert.equal(JSON.stringify(f.read('matchSecretsV1/'+f.id)),before);
  assert.deepEqual(Object.keys(event).sort(),['at','emojiId','sequence','side']);
});
test('outsiders, unowned and unknown emotes, body injection are rejected',async()=>{
  const f=await setup();
  await assert.rejects(f.send('attacker'));
  await assert.rejects(f.send('alice','crown'));
  await assert.rejects(f.send('alice','nope'));
  await assert.rejects(f.api.sendBattleV1Emote(f.context('alice',{
    ...f.body,emojiId:'smile',side:'b'})));
  await assert.rejects(f.get('alice',-1));
  assert.equal(f.read('matchEmotesV1/'+f.id),undefined);
});
test('cooldown and duplicate requests are atomic and ownership comes from server',async()=>{
  const f=await setup();f.write('users/alice/inventory',{ownedEmojis:['heart']});
  await f.send('alice','heart','first');
  await f.send('alice','heart','first');
  assert.equal((await f.get('bob')).sequence,1);
  await assert.rejects(f.send('alice','smile','first'));
  await assert.rejects(f.send('alice','smile','second'));
  await f.send('bob','smile','bob');
  f.setTime(4000);await f.send('alice','smile','second');
  await f.send('alice','heart','first');
  assert.equal((await f.get('alice')).sequence,3);
});
test('bounded feed expires, finished and deleted players cannot send',async()=>{
  const f=await setup();
  for(let i=0;i<25;i++){f.setTime(1000+i*3000);await f.send('alice','smile','r'+i);}
  assert.ok((await f.get('bob')).events.length<=16);
  f.setTime(200000);assert.equal((await f.get('bob')).events.length,0);
  assert.deepEqual(f.read('matchEmotesV1/'+f.id).receipts,[]);
  assert.deepEqual(f.read('matchEmotesV1/'+f.id).last,{});
  await f.api.transact(f.id,'alice',m=>{m.result={reason:'resign',winner:'b'};return {match:m};});
  await assert.rejects(f.send('alice','smile','ended'));
});
test('deleted participants cannot send or read the emote feed',async()=>{
  const f=await setup();await f.send('bob');
  await f.api.transact(f.id,'bob',m=>{m.deletedParticipants={alice:true};return {match:m};});
  await assert.rejects(f.send('alice'),e=>e.code==='NOT_PARTICIPANT');
  await assert.rejects(f.get('alice'),e=>e.code==='NOT_PARTICIPANT');
  assert.equal((await f.get('bob')).events.length,1);
});
test('result acknowledgement cleans optional emotes but survives cleanup failure',async()=>{
  const f=await setup();await f.send('alice');
  await f.api.resignBattleV1(f.context('alice',{...f.body,expectedStateVersion:0,actionId:'a0_resign-action-id'},'resign'));
  assert.equal((await f.api.ackBattleV1Result(f.context('alice',f.body))).acknowledged,true);
  assert.equal(f.read('matchEmotesV1/'+f.id),undefined);
  const originalRef=f.api.db.ref;
  f.api.db.ref=p=>p==='matchEmotesV1/'+f.id?{remove:async()=>{throw Error('offline');}}:originalRef(p);
  assert.equal((await f.api.ackBattleV1Result(f.context('alice',f.body))).acknowledged,true);
});
