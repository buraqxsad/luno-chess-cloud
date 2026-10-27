'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {fixture}=require('./helpers/battle-v1-fixture');
const {protocol,authority}=require('../lib/battle-v1');
const {STARTER}=require('../rules-v1/dist/src/model.js');
const {newBattle}=require('../rules-v1/dist/src/authoritative.js');
const {playerSettlementMetrics}=require('../lib/battle-v1-recovery');
const {deterministicMissionIds,missionOwned}=require('../lib/missions');
const {MISSION_CATALOG}=require('../lib/catalogs');
const {selectedMissionIds,sourceClaimKey,periodSnapshot}=require('../index.js')._test;
const id='bv1_21212121212121212121212121212121';

function move(match,uci){
 const side=match.battle.rules.fen.split(' ')[1],uid=match.players[side].uid;
 const commit=intent=>{match=authority.commitAction(match,uid,{matchId:id,protocolVersion:protocol.PROTOCOL,expectedStateVersion:match.stateVersion,actionId:`a${match.stateVersion}_v213-action`,intent},1001+match.stateVersion).match;};
 if(match.battle.rules.phase==='card')commit({type:'pass'});
 commit({type:'move',uci});return match;
}
function fresh(){return authority.createServerMatch(id,{uid:'alice',name:'Alice',bot:false},{uid:'bob',name:'Bob',bot:false},STARTER,STARTER,1000);}

test('accepted moves record captures and checks for the correct player only',()=>{
 let m=fresh();for(const uci of ['e2e4','e7e5','f1c4','b8c6','d1h5','g8f6','h5f7'])m=move(m,uci);
 assert.equal(m.result.reason,'checkmate');
 assert.equal(m.metrics['player:w:captures'],1);assert.equal(m.metrics['player:w:checks'],1);
 assert.equal(m.metrics['player:b:captures'],0);assert.equal(m.metrics['player:b:checks'],undefined);
 assert.equal(playerSettlementMetrics(m,'w').moveCount,4);assert.equal(playerSettlementMetrics(m,'b').moveCount,3);
 const r={matchId:id,protocolVersion:protocol.PROTOCOL,expectedStateVersion:m.stateVersion,actionId:`a${m.stateVersion}_terminal-attempt`,intent:{type:'move',uci:'e8e7'}};
 assert.throws(()=>authority.commitAction(m,'bob',r,2000),{code:'MATCH_TERMINAL'});
});

test('duplicate action acknowledgement does not increment player statistics',()=>{
 const initial=fresh(),r={matchId:id,protocolVersion:protocol.PROTOCOL,expectedStateVersion:0,actionId:'a0_v213-duplicate',intent:{type:'move',uci:'e2e4'}};
 const once=authority.commitAction(initial,'alice',r,1001).match,twice=authority.commitAction(once,'alice',r,1002);
 assert(twice.duplicate);assert.deepEqual(twice.match.metrics,once.metrics);assert.equal(once.metrics['player:w:moveCount'],1);
});

test('rated settlement transfers only each player metrics and remains once-only',async()=>{
 const f=fixture();await f.api.migrate('alice');await f.api.migrate('bob');
 await f.api.create(id,{uid:'alice',name:'Alice',bot:false},{uid:'bob',name:'Bob',bot:false},STARTER,STARTER,true);
 await f.api.transact(id,'alice',m=>{
  m.battle.rules.used.w=['shelter','board_seal','radar'];m.battle.rules.used.b=['freeze'];m.battle.rules.ply=20;
  m.metrics={'player:w:captures':3,'player:w:checks':2,'player:w:promotions':1,'player:b:captures':1,'player:b:checks':0};
  return {match:authority.finishMatch(m,{reason:'resign',winner:'w',finishedAt:2000})};
 });
 await f.api.settle(id,'alice');
 const white=f.read('users/alice'),black=f.read('users/bob');
 assert.equal(white.stats.cardsPlayed,3);assert.equal(black.stats.cardsPlayed,1);
 assert.equal(white.stats.captures,3);assert.equal(black.stats.captures,1);assert.equal(white.stats.checks,2);assert.equal(white.stats.promotions,1);
 const day=Object.values(white.serverProgress.missions.daily)[0].counters;
 assert.equal(day.d3,3);assert.equal(day.d_legend,1);assert.equal(day.cu_board_seal,1);assert.equal(day.d_capture,3);assert.equal(day.cf_radar,1);
 assert.equal(white.serverProgress.battleProtocol,protocol.PROTOCOL);
 for(let i=0;i<3;i++)await f.api.settle(id,'bob');assert.deepEqual(f.read('users/alice'),white);assert.deepEqual(f.read('users/bob'),black);
});

for(const category of ['daily','weekly']){
 test(`V1 mission rotation never selects an unavailable legacy ability: ${category}`,()=>{
  const profile={uid:'alice',unlockedCards:{barbarian:true,glue:true,ghosts:true,poison_q:true},serverProgress:{battleProtocol:protocol.PROTOCOL}};
  for(let period=0;period<100;period++){
   const ids=deterministicMissionIds(profile,category,String(period));assert.equal(ids.length,5);assert.equal(new Set(ids).size,5);
   for(const task of ids)assert(missionOwned(profile,MISSION_CATALOG[category][task]));
   assert(!ids.some(id=>['dc_barb','dc_pois','dc_glue','dc_trapf','dc_shf','dc_resf','wc_barb','wc_deployf','wc_ghost','wc_plague','wc_imm','wc_med'].includes(id)));
  }
 });
}

test('V1 rotation keeps claimed legacy tasks and fills incompatible unclaimed slots without duplicate rewards',()=>{
 const at=Date.UTC(2026,9,7),day=periodSnapshot(at).dayKey;
 const profile={uid:'alice',unlockedCards:{barbarian:true,glue:true,ghosts:true},serverProgress:{battleProtocol:protocol.PROTOCOL,missions:{daily:{[day]:{selected:['d1','dc_barb','dc_glue','dc_trapf','dc_shf'],counters:{dc_barb:2}}}}},serverEconomy:{claims:{}}};
 profile.serverEconomy.claims[sourceClaimKey('alice','mission_reward',`daily:${day}:dc_barb`)]={claimed:true};
 const ids=selectedMissionIds(profile,'daily',at);
 assert.equal(ids.length,5);assert.equal(new Set(ids).size,5);assert(ids.includes('dc_barb'));assert(!ids.includes('dc_glue'));assert(!ids.includes('dc_trapf'));assert(!ids.includes('dc_shf'));
 assert.deepEqual(selectedMissionIds(profile,'daily',at),ids);
});

test('legacy mission selection and namespaces remain untouched without a V1 settlement',()=>{
 const at=Date.UTC(2026,9,7),day=periodSnapshot(at).dayKey,profile={uid:'alice',unlockedCards:{barbarian:true},serverProgress:{missions:{daily:{[day]:{selected:['d1','dc_barb']}}}}};
 assert(missionOwned(profile,MISSION_CATALOG.daily.dc_barb));assert.deepEqual(selectedMissionIds(profile,'daily',at),['d1','dc_barb']);
});

test('old matches do not invent unknown capture/check/promotion statistics',()=>{
 const m=structuredClone(fresh());m.battle.rules.used.w=['freeze','freeze','prophecy'];
 assert.deepEqual(playerSettlementMetrics(m,'w'),{cardsPlayed:2,legendaryCards:0,captures:0,checks:0,promotions:0,cardUsage:{freeze:1,prophecy:1},moveCount:0});
 m.metrics={'player:w:captures':-10,'player:w:checks':NaN,'player:w:promotions':Infinity};
 assert.equal(playerSettlementMetrics(m,'w').captures,0);assert.equal(playerSettlementMetrics(m,'w').checks,0);assert.equal(playerSettlementMetrics(m,'w').promotions,0);
});

test('en passant and normal captures both increment only the mover',()=>{
 let m=fresh();for(const uci of ['e2e4','a7a6','e4e5','d7d5','e5d6'])m=move(m,uci);
 assert.equal(m.metrics['player:w:captures'],1);assert.equal(m.metrics['player:b:captures'],0);
 assert.equal(playerSettlementMetrics(m,'w').captures,1);assert.equal(playerSettlementMetrics(m,'b').captures,0);
});

for(const promotion of ['q','r','b','n'])for(const capture of [false,true]){
 test(`promotion metrics are based on an accepted legal move: ${promotion}, capture=${capture}`,()=>{
  const m=fresh();m.battle=newBattle(STARTER,STARTER,'1r5k/P7/8/8/8/8/8/4K3 w - - 0 1');
  const next=move(m,`a7${capture?'b8':'a8'}${promotion}`);
  assert.equal(next.metrics['player:w:promotions'],1);assert.equal(next.metrics['player:b:promotions'],undefined);
  assert.equal(next.metrics['player:w:captures'],capture?1:0);
 });
}

test('unrated games do not issue rated profile rewards or mission progress',async()=>{
 const f=fixture();await f.api.migrate('alice');await f.api.migrate('bob');
 await f.api.create(id,{uid:'alice',name:'Alice',bot:false},{uid:'bob',name:'Bob',bot:false},STARTER,STARTER,false);
 const before=structuredClone(f.read('users/alice'));
 await f.api.transact(id,'alice',m=>{m.battle.rules.used.w=['shelter'];return {match:authority.finishMatch(m,{reason:'resign',winner:'w',finishedAt:2000})};});
 await f.api.settle(id,'alice');assert.deepEqual(f.read('users/alice'),before);
});
