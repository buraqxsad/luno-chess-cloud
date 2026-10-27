'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {fixture}=require('./helpers/battle-v1-fixture');
const {protocol,authority}=require('../lib/battle-v1');
async function paired(){const f=fixture();await f.enable();await f.api.enqueueBattleV1(f.context('alice',{client:f.client},'queue-a'));const r=await f.api.enqueueBattleV1(f.context('bob',{client:f.client},'queue-b'));return {...f,id:r.matchId};}
test('rated settlement is once-only, preserves legacy rating and restores a missing projection',async()=>{
 const f=await paired(),m=await f.api.load(f.id,'alice'),before=f.read('users/alice');
 await f.api.transact(f.id,'alice',m=>({match:authority.finishMatch(m,{reason:'resign',winner:'w',finishedAt:2000})}));
 const settled=await f.api.settle(f.id,'alice'),first=f.read('users/alice');
 assert.equal(settled.settlementStatus,'complete');for(const key of ['trophies','arenaIdx','serverCompetition','serverSeason'])assert.deepEqual(first[key],before[key]);
 assert.equal(JSON.parse(f.read('battleV1Accounts/'+m.players.w.uid).accountJson).games,1);
 for(let i=0;i<3;i++)await f.api.settle(f.id,'bob');assert.deepEqual(f.read('users/alice'),first);
 f.write('matchesV1/'+f.id,null);await f.api.settle(f.id,'alice');assert.equal(f.read('matchesV1/'+f.id).public.stateVersion,settled.stateVersion);
 const own=await f.api.getBattleV1(f.context('alice',{matchId:f.id,protocolVersion:protocol.PROTOCOL}));assert(own.view.private.analysisJson);assert(!Object.hasOwn(own.view.public,'analysisJson'));assert.equal(f.read('battleV1Control/active/alice'),undefined);
});
test('timeout is authoritative across pending/reconnect and late action cannot revive it',async()=>{
 const f=await paired(),m=await f.api.load(f.id,'alice'),uid=m.players.w.uid;f.setTime(301001);
 const r=await f.api.getBattleV1(f.context(uid,{matchId:f.id,protocolVersion:protocol.PROTOCOL}));assert.equal(r.view.public.result.reason,'timeout');assert.equal(r.view.public.clock.w,0);
 const stored=f.read('matchSecretsV1/'+f.id);await assert.rejects(f.api.submitBattleV1Action(f.context(uid,{matchId:f.id,protocolVersion:protocol.PROTOCOL,expectedStateVersion:0,actionId:'a0_late-move-action',intent:{type:'move',uci:'e2e4'}})),{code:'MATCH_TERMINAL'});assert.deepEqual(f.read('matchSecretsV1/'+f.id),stored);
});
test('resign retries retain their receipt after settlement, conflicting ID rejected',async()=>{
 const f=await paired(),m=await f.api.load(f.id,'alice'),body={matchId:f.id,protocolVersion:protocol.PROTOCOL,expectedStateVersion:0,actionId:'a0_resign-action-id'};
 const r=await f.api.resignBattleV1(f.context(m.players.w.uid,body));assert.equal(r.view.public.result.reason,'resign');const canonical=f.read('matchSecretsV1/'+f.id);
 await f.api.resignBattleV1(f.context(m.players.w.uid,body));assert.deepEqual(f.read('matchSecretsV1/'+f.id),canonical);
 await assert.rejects(f.api.resignBattleV1(f.context(m.players.b.uid,body)),{code:'ACTION_ID_CONFLICT'});
});
test('bot turn uses V1 phases, never rates humans and does not draw on reconnect',async()=>{
 const f=fixture();await f.enable();await f.api.enqueueBattleV1(f.context('alice',{client:f.client},'bot-a'));f.setTime(32000);
 const r=await f.api.getBattleV1(f.context('alice',{matchId:'',protocolVersion:protocol.PROTOCOL},'bot-poll'));const m=await f.api.load(r.matchId,'alice');assert(!m.players[m.battle.rules.fen.split(' ')[1]].bot);
 const saved=f.read('matchSecretsV1/'+r.matchId);await f.api.getBattleV1(f.context('alice',{matchId:r.matchId,protocolVersion:protocol.PROTOCOL}));assert.deepEqual(f.read('matchSecretsV1/'+r.matchId),saved);
});
test('account departure removes read membership even when projections are republished',async()=>{
 const f=await paired();await f.api.leaveAccount('alice');const m=await f.api.load(f.id,'bob');await f.api.publish(m);const p=f.read('matchesV1/'+f.id);assert.equal(p.public.participants.alice,undefined);assert.equal(p.private.alice,undefined);assert.equal(p.public.participants.bob,true);
});
test('unseen result survives process death until acknowledged, then new search advances',async()=>{
 const f=await paired();await assert.rejects(f.api.ackBattleV1Result(f.context('alice',{matchId:f.id,protocolVersion:protocol.PROTOCOL})),{code:'RESULT_NOT_READY'});
 await f.api.transact(f.id,'alice',m=>({match:authority.finishMatch(m,{reason:'resign',winner:'b',finishedAt:2000})}));await f.api.settle(f.id,'alice');
 const recovered=await f.api.getBattleV1(f.context('alice',{matchId:'',protocolVersion:protocol.PROTOCOL}));assert.equal(recovered.matchId,f.id);assert.equal(recovered.status,'finished');
 await f.api.ackBattleV1Result(f.context('alice',{matchId:f.id,protocolVersion:protocol.PROTOCOL}));assert.equal((await f.api.getBattleV1(f.context('alice',{matchId:'',protocolVersion:protocol.PROTOCOL}))).status,'idle');
 await f.api.enqueueBattleV1(f.context('bob',{client:f.client},'new-search'));assert.equal(f.read('battleV1Control/lastMatch/bob'),undefined);
});
