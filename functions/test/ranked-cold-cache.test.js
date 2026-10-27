'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {getDatabase}=require('firebase-admin/database');
const {getRankedMatch,submitMatchAction,heartbeatRankedMatch,sendRankedMessage,
  starterProfile,canonicalDeckForProfile}=require('../index.js')._test;
const {createMatchState}=require('../lib/ranked');

function fixture(t,{deleted=false,expired=false,queue=false}={}){
  const white=starterProfile('white-player','whiteplayer');
  const black=starterProfile('black-player','blackplayer');
  const matchId='fm_'+'c'.repeat(32),at=Date.now();
  const match=createMatchState({matchId,at,mode:'friendly',
    white:{uid:white.uid,profile:white,deck:canonicalDeckForProfile(white)},
    black:{uid:black.uid,profile:black,deck:canonicalDeckForProfile(black)}});
  if(expired){match.clock.W=0;match.clock.deadlineAt=at-1000;}
  const root={users:{[white.uid]:white,[black.uid]:black},rankedState:{
    matches:{[matchId]:match},queue:queue?{[white.uid]:{joinedAt:at,lastSeenAt:at}}:{}}};
  const matchPath=`rankedState/matches/${matchId}`;
  const coldPath=queue?`rankedState/queue/${white.uid}`:matchPath;
  let probes=0;
  const clone=value=>value===undefined?null:structuredClone(value);
  const read=path=>path.split('/').filter(Boolean).reduce((value,key)=>value?.[key],root);
  function write(path,value){
    const keys=path.split('/').filter(Boolean),last=keys.pop();let current=root;
    for(const key of keys)current=current[key]||(current[key]={});
    if(value===null)delete current[last];else current[last]=clone(value);
  }
  const snapshot=value=>({val:()=>clone(value),exists:()=>value!==null&&value!==undefined});
  t.mock.method(getDatabase(),'ref',(path='')=>({
    async get(){return snapshot(read(path));},
    async set(value){write(path,value);},
    async remove(){write(path,null);},
    async update(values){for(const [key,value] of Object.entries(values))write([path,key].filter(Boolean).join('/'),value);},
    async transaction(update,onComplete,applyLocally){
      if(path===coldPath){
        assert.equal(onComplete,undefined);
        assert.equal(applyLocally,false,'server reads must not observe a speculative null match/queue');
        probes++;
        const speculative=update(null);
        if(speculative===undefined)return {committed:false,snapshot:snapshot(null)};
        assert.equal(speculative,null,'cold-cache probe must not resurrect cached data');
        if(deleted)write(path,null);
      }
      const next=update(clone(read(path)));
      if(next!==undefined)write(path,next);
      return {committed:next!==undefined,snapshot:snapshot(read(path))};
    },
  }));
  const context=(body,uid=white.uid)=>({uid,body,requestId:'cold-cache-request-'+t.name});
  return {root,matchId,white,black,context,probes:()=>probes};
}

test('legal move retries against the server after a cold transaction cache',async t=>{
  const f=fixture(t);
  const result=await submitMatchAction(f.context({matchId:f.matchId,type:'move',
    from:12,to:28,actionId:'cold-cache-move-0001',expectedSequence:0}));
  assert.equal(result.view.sequence,1);
  assert.equal(f.root.rankedState.matches[f.matchId].moveCount,1);
  assert.equal(f.probes(),1);
});

test('cold cache does not bypass stale action sequence validation',async t=>{
  const f=fixture(t);
  await assert.rejects(submitMatchAction(f.context({matchId:f.matchId,type:'resign',
    actionId:'cold-cache-stale-0001',expectedSequence:8})),error=>error.code==='stale-sequence');
  assert.equal(f.root.rankedState.matches[f.matchId].sequence,0);
});

test('cold cache does not accept a nonparticipant action',async t=>{
  const f=fixture(t);
  await assert.rejects(submitMatchAction(f.context({matchId:f.matchId,type:'resign',
    actionId:'cold-cache-foreign-0001',expectedSequence:0},'other-player')),
    error=>error.code==='not-a-participant');
  assert.equal(f.root.rankedState.matches[f.matchId].status,'active');
});

test('heartbeat updates server presence after a cold cache',async t=>{
  const f=fixture(t);
  const result=await heartbeatRankedMatch(f.context({matchId:f.matchId}));
  assert.equal(result.status,'active');
  assert.ok(f.root.rankedMatchViews[f.white.uid][f.matchId]);
  assert.equal(f.probes(),1);
});

test('cold heartbeat still rejects a nonparticipant',async t=>{
  const f=fixture(t);
  await assert.rejects(heartbeatRankedMatch(f.context({matchId:f.matchId},'other-player')),
    error=>error.code==='not-a-participant');
  assert.equal(f.root.rankedMatchViews,undefined);
});

test('match chat retries the server heartbeat on cold cache',async t=>{
  const f=fixture(t);
  const result=await sendRankedMessage(f.context({matchId:f.matchId,kind:'preset',tab:'greetings',id:'good_luck'}));
  assert.equal(result.message.id,'good_luck');
  assert.equal(f.root.rankedMessages[f.black.uid][f.matchId].messageId,result.message.messageId);
  assert.equal(f.probes(),1);
});

for(const route of ['action','heartbeat','chat']){
  test(`${route} handles concurrent server deletion without resurrecting the match`,async t=>{
    const f=fixture(t,{deleted:true});
    const request=route==='action'
      ?submitMatchAction(f.context({matchId:f.matchId,type:'resign',actionId:'deleted-match-action',expectedSequence:0}))
      :route==='heartbeat'?heartbeatRankedMatch(f.context({matchId:f.matchId}))
      :sendRankedMessage(f.context({matchId:f.matchId,kind:'preset',tab:'greetings',id:'good_luck'}));
    await assert.rejects(request,error=>error.code==='match-not-found');
    assert.equal(f.root.rankedState.matches[f.matchId],undefined);
    assert.equal(f.root.rankedMatchViews,undefined);
    assert.equal(f.root.rankedMessages,undefined);
  });
}

test('queue polling discovers and refreshes a cold server queue',async t=>{
  const f=fixture(t,{queue:true});
  const result=await getRankedMatch(f.context({matchId:''}));
  assert.equal(result.status,'queued');
  assert.equal(f.probes(),1);
});

test('deleted queue is not recreated by a cold poll',async t=>{
  const f=fixture(t,{queue:true,deleted:true});
  assert.equal((await getRankedMatch(f.context({matchId:''}))).status,'idle');
  assert.equal(f.root.rankedState.queue[f.white.uid],undefined);
});

test('match read reports concurrent deletion during expiry sweep',async t=>{
  const f=fixture(t,{deleted:true,expired:true});
  await assert.rejects(getRankedMatch(f.context({matchId:f.matchId})),error=>error.code==='match-not-found');
  assert.equal(f.root.rankedState.matches[f.matchId],undefined);
  assert.equal(f.root.rankedMatchViews,undefined);
});
