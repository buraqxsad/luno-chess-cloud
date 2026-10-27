'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {settleRankedMatch,sweepRankedMatchesJob,leaveRankedBeforeDeletion,starterProfile,canonicalDeckForProfile}=require('../index.js')._test;
const {createMatchState,applyRankedAction}=require('../lib/ranked');
const {getDatabase}=require('firebase-admin/database');
const {auditSettlements}=require('../lib/settlement-audit');

function memoryDatabase(root,fail,failRead=()=>false,coldStart=()=>false){
  const clone=value=>value===undefined?null:structuredClone(value);
  function read(path){return path.split('/').filter(Boolean).reduce((value,key)=>value&&value[key],root);}
  function write(path,value){
    const keys=path.split('/').filter(Boolean),last=keys.pop();let current=root;
    for(const key of keys)current=current[key]||(current[key]={});
    if(value===null)delete current[last];else current[last]=clone(value);
  }
  const snapshot=value=>({val:()=>clone(value),exists:()=>value!==null&&value!==undefined});
  return function ref(path=''){
    return {
      orderByChild(child){
        let expected,firstKey='';
        const query={
          equalTo(value){expected=value;return query;},
          startAt(value,key){expected=value;firstKey=key;return query;},
          endAt(value){assert.equal(value,expected);return query;},
          limitToFirst(limit){return {async get(){
            return snapshot(Object.fromEntries(Object.entries(read(path)||{})
              .sort(([a],[b])=>a<b?-1:a>b?1:0)
              .filter(([key,value])=>value[child]===expected&&key>=firstKey).slice(0,limit)));
          }};},
        };
        return query;
      },
      async get(){if(failRead(path))throw new Error('injected-read-failure');return snapshot(read(path));},
      async set(value){if(fail(path))throw new Error('injected-write-failure');write(path,value);},
      async remove(){if(fail(path))throw new Error('injected-write-failure');write(path,null);},
      async transaction(update){
        if(fail(path))throw new Error('injected-write-failure');
        if(coldStart(path)&&update(null)===undefined)return {committed:false,snapshot:snapshot(null)};
        const next=update(clone(read(path)));
        if(next!==undefined)write(path,next);
        return {committed:next!==undefined,snapshot:snapshot(read(path))};
      },
      async update(updates){
        if(fail(path,updates))throw new Error('injected-write-failure');
        for(const [key,value] of Object.entries(updates))write([path,key].filter(Boolean).join('/'),value);
      },
    };
  };
}

test('scheduled recovery rotates past a full failed batch and wraps for retry',async(t)=>{
  const white=starterProfile('white-player','whiteplayer'),black=starterProfile('black-player','blackplayer');
  const id='rm_'+(81).toString(16).padStart(32,'0');
  let match=createMatchState({matchId:id,at:Date.now(),white:{uid:white.uid,profile:white,deck:canonicalDeckForProfile(white)},black:{uid:black.uid,profile:black,deck:canonicalDeckForProfile(black)}});
  match=applyRankedAction(match,black.uid,{type:'resign',actionId:'rotation-resign-0001',expectedSequence:0},Date.now()).state;
  const matches={[id]:match};
  for(let i=1;i<=80;i++)matches['rm_'+i.toString(16).padStart(32,'0')]={status:'finished',settlementStatus:'pending'};
  const root={users:{[white.uid]:white,[black.uid]:black},rankedState:{matches}};
  t.mock.method(getDatabase(),'ref',memoryDatabase(root,()=>false,
    path=>path.startsWith('rankedState/matches/')&&path!==`rankedState/matches/${id}`));
  t.mock.method(require('firebase-functions/logger'),'error',()=>{});
  const first=await sweepRankedMatchesJob();
  assert.equal(first.recoveryFailed,80);
  assert.equal(first.recovered,0);
  const second=await sweepRankedMatchesJob();
  assert.equal(second.recovered,1);
  assert.equal(root.users[white.uid].stats.wins,1);
  assert.equal(root.rankedMaintenance.settlementCursor,id);
  await sweepRankedMatchesJob();
  assert.equal(root.rankedMaintenance.settlementCursor,undefined);
  const wrapped=await sweepRankedMatchesJob();
  assert.equal(wrapped.recoveryFailed,80);
  assert.equal(root.users[white.uid].stats.wins,1);
});

for(const scenario of ['pending','active','active-cold','raced','failed','pointer-removed','pointer-removed-failed']){
  test(`account deletion preparation handles ${scenario} settlement`,async(t)=>{
    const id='rm_'+'b'.repeat(32);
    const white=starterProfile('white-player','whiteplayer'),black=starterProfile('black-player','blackplayer');
    const active=createMatchState({matchId:id,at:Date.now(),white:{uid:white.uid,profile:white,deck:canonicalDeckForProfile(white)},black:{uid:black.uid,profile:black,deck:canonicalDeckForProfile(black)}});
    const finished=applyRankedAction(active,black.uid,{type:'resign',actionId:'deletion-resign-0001',expectedSequence:0},Date.now()).state;
    const root={users:{[white.uid]:white,[black.uid]:black},rankedState:{
      matches:{[id]:scenario.startsWith('active')||scenario==='raced'?active:finished},
      activeByUser:{[white.uid]:id,[black.uid]:id},queue:{[black.uid]:{joinedAt:1}},
    }};
    if(scenario.startsWith('pointer-removed')){
      root.rankedState.activeByUser={};
      root.rankedState.pendingSettlementsByUser={[black.uid]:{[id]:true}};
    }
    const baseRef=memoryDatabase(root,path=>scenario.endsWith('failed')&&path===`users/${black.uid}`,
      ()=>false,path=>scenario==='active-cold'&&path===`rankedState/matches/${id}`);
    t.mock.method(getDatabase(),'ref',(path='')=>{
      const ref=baseRef(path);
      if(scenario==='raced'&&path===`rankedState/matches/${id}`){
        const transact=ref.transaction;
        ref.transaction=async update=>{root.rankedState.matches[id]=finished;return transact(update);};
      }
      return ref;
    });
    if(scenario.endsWith('failed')){
      await assert.rejects(leaveRankedBeforeDeletion(black.uid),/injected-write-failure/);
      assert.ok(root.users[black.uid]);
      assert.ok(root.rankedState.queue[black.uid]);
      assert.notEqual(root.rankedState.matches[id].settlementStatus,'complete');
    }else{
      await leaveRankedBeforeDeletion(black.uid);
      assert.equal(root.rankedState.matches[id].settlementStatus,'complete');
      assert.equal(root.users[white.uid].stats.wins,1);
      assert.equal(root.users[black.uid].stats.losses,1);
      assert.equal(root.rankedState.queue[black.uid],undefined);
      assert.ok(root.matchHistory[white.uid][id]);
      assert.equal(root.rankedState.pendingSettlementsByUser?.[black.uid]?.[id],undefined);
    }
  });
}

for(const deleted of [false,true]){
  test(`scheduled expiry handles a cold match cache${deleted?' and concurrent deletion':''}`,async t=>{
    const id='rm_'+'d'.repeat(32),at=Date.now();
    const white=starterProfile('white-player','whiteplayer'),black=starterProfile('black-player','blackplayer');
    const match=createMatchState({matchId:id,at,white:{uid:white.uid,profile:white,deck:canonicalDeckForProfile(white)},
      black:{uid:black.uid,profile:black,deck:canonicalDeckForProfile(black)}});
    match.clock.W=0;match.clock.deadlineAt=at-1000;
    const root={users:{[white.uid]:white,[black.uid]:black},rankedState:{matches:{[id]:match}}};
    t.mock.method(getDatabase(),'ref',memoryDatabase(root,()=>false,()=>false,path=>{
      if(path!==`rankedState/matches/${id}`)return false;
      if(deleted)delete root.rankedState.matches[id];
      return true;
    }));
    const result=await sweepRankedMatchesJob();
    assert.equal(result.scanned,1);
    assert.equal(result.settled,deleted?0:1);
    if(deleted){
      assert.equal(root.rankedState.matches[id],undefined);
      assert.equal(root.matchHistory,undefined);
    }else{
      assert.equal(root.rankedState.matches[id].settlementStatus,'complete');
      assert.ok(root.matchHistory[white.uid][id]);
      assert.ok(root.matchHistory[black.uid][id]);
    }
  });
}

for(const failure of ['second-player','publication','white-pointer','white-status','black-pointer','black-status','views','views-new-match','completion']){
  test(`settlement recovers after ${failure} failure without double reward`,async(t)=>{
    const id='rm_0123456789abcdef0123456789abcdef';
    const white=starterProfile('white-player','whiteplayer'),black=starterProfile('black-player','blackplayer');
    let match=createMatchState({matchId:id,at:Date.now(),white:{uid:white.uid,profile:white,deck:canonicalDeckForProfile(white)},black:{uid:black.uid,profile:black,deck:canonicalDeckForProfile(black)}});
    match=applyRankedAction(match,black.uid,{type:'resign',actionId:'recovery-resign-0001',expectedSequence:0},Date.now()).state;
    assert.equal(match.settlementStatus,'pending');
    const root={users:{[white.uid]:white,[black.uid]:black},rankedState:{matches:{[id]:match},activeByUser:{[white.uid]:id,[black.uid]:id}},rankedPlayers:{[white.uid]:{matchId:id,status:'active'},[black.uid]:{matchId:id,status:'active'}}};
    let failed=false;
    const failurePaths={
      'second-player':`users/${black.uid}`,
      'publication':'',
      'white-pointer':`rankedState/activeByUser/${white.uid}`,
      'white-status':`rankedPlayers/${white.uid}`,
      'black-pointer':`rankedState/activeByUser/${black.uid}`,
      'black-status':`rankedPlayers/${black.uid}`,
    };
    const ref=memoryDatabase(root,(path,updates)=>{
      const isViewFailure=failure.startsWith('views');
      const target=failure==='completion'
        ?path===''&&updates?.[`rankedState/matches/${id}/settlementStatus`]==='complete'
        :isViewFailure
        ?path===''&&Object.keys(updates||{}).some(key=>key.startsWith('rankedMatchViews/'))
        :path===failurePaths[failure];
      if(!failed&&target){failed=true;return true;}
      return false;
    });
    t.mock.method(getDatabase(),'ref',ref);
    const blackBefore=JSON.stringify(root.users[black.uid]);
    await assert.rejects(settleRankedMatch(id),/injected-write-failure/);
    const interruptedAudit=auditSettlements(root);
    assert.notEqual(interruptedAudit.findings[0].classification,'consistent-in-snapshot');
    assert.ok(interruptedAudit.findings[0].issues.includes('completion-marker'));
    assert.notEqual(root.rankedState.matches[id].settlementStatus,'complete',
      'failed settlement must remain eligible for reader retry');
    if(failure==='views'||failure==='completion'){
      assert.equal(root.rankedState.activeByUser[black.uid],undefined);
      assert.equal(root.rankedState.pendingSettlementsByUser[black.uid][id],true);
    }
    const whiteAfter=JSON.stringify(root.users[white.uid]);
    assert.equal(root.users[white.uid].stats.wins,1);
    if(failure==='second-player')assert.equal(JSON.stringify(root.users[black.uid]),blackBefore);
    const nextId='rm_abcdef0123456789abcdef0123456789';
    if(failure==='views-new-match'){
      for(const uid of [white.uid,black.uid]){
        root.rankedState.activeByUser[uid]=nextId;
        root.rankedPlayers[uid]={matchId:nextId,status:'active'};
      }
    }
    const sweep=await sweepRankedMatchesJob();
    assert.equal(sweep.recovered,1);
    assert.equal(sweep.recoveryFailed,0);
    const recovered=root.rankedState.matches[id];
    assert.equal(recovered.settlementStatus,'complete');
    assert.equal(root.rankedState.matches[id].settlementStatus,'complete');
    assert.equal(JSON.stringify(root.users[white.uid]),whiteAfter);
    assert.equal(root.users[black.uid].stats.losses,1);
    const finalUsers=JSON.stringify(root.users);
    await settleRankedMatch(id);
    assert.equal(JSON.stringify(root.users),finalUsers);
    for(const uid of [white.uid,black.uid]){
      assert.equal(root.rankedState.activeByUser[uid],failure==='views-new-match'?nextId:undefined);
      assert.equal(root.rankedPlayers[uid].matchId,failure==='views-new-match'?nextId:id);
      assert.equal(root.rankedPlayers[uid].status,failure==='views-new-match'?'active':'finished');
      assert.equal(root.rankedMatchViews[uid][id].status,'finished');
      assert.ok(root.rankedReplays[uid][id]);
      assert.equal(root.rankedState.pendingSettlementsByUser?.[uid]?.[id],undefined);
    }
    assert.ok(root.matchHistory[white.uid][id]);
    assert.ok(root.matchHistory[black.uid][id]);
    const recoveredAudit=auditSettlements(root);
    assert.equal(recoveredAudit.checked,1);
    assert.deepEqual(recoveredAudit.findings[0],{
      matchId:id,classification:'consistent-in-snapshot',issues:[],blockers:[],
    });
  });
}
