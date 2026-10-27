import test from 'node:test';
import assert from 'node:assert/strict';
import {newBattle} from '../src/authoritative.js';
import {STARTER} from '../src/model.js';
import {LEGACY_ONLY,PROTOCOL,parseActionRequest,requireClient,reconnectSnapshot,toPublicMatchState,toPlayerPrivateState,validateRollout,type ServerMatch} from '../src/online/protocol.js';
function match():ServerMatch{return {matchId:'bv1_'+'a'.repeat(32),protocolVersion:PROTOCOL,rulesetVersion:1,stateVersion:0,
  players:{w:{uid:'alice',name:'Alice',bot:false},b:{uid:'bob',name:'Bob',bot:false}},battle:newBattle(STARTER,STARTER),
  clock:{w:300000,b:300000,activeSide:'w',startedAt:1000,incrementMs:2000},result:null,settlementStatus:'none',rated:true,createdAt:1000,actions:{},lastEvent:null,audit:[],metrics:{},presence:{w:1000,b:1000}};}
test('intent envelope rejects authoritative fields and unknown protocols',()=>{
  const r={matchId:match().matchId,actionId:'intent-action-0001',expectedStateVersion:0,protocolVersion:PROTOCOL,intent:{type:'move',uci:'e2e4'}};
  assert.equal(parseActionRequest(r).intent.type,'move');
  for(const field of ['board','mana','hand','deck','draw','radarResult','seed','state'])assert.throws(()=>parseActionRequest({...r,[field]:1}));
  assert.throws(()=>parseActionRequest({...r,protocolVersion:'legacy'}));
  for(const intent of [{type:'move',uci:'e2e4',mana:6},{type:'resolve',order:['radar','radar']},{type:'pass',deck:STARTER},{type:'play',card:'radar',target:64}])assert.throws(()=>parseActionRequest({...r,intent}));
});
test('explicit serializers isolate both decks, opponent hand and private knowledge',()=>{
  const m=match();m.battle=structuredClone(m.battle);m.battle.hidden.knowledge.b.pendingCards=['freeze'];
  const p=toPublicMatchState(m),own=toPlayerPrivateState(m,'alice');
  assert.deepEqual(Object.keys(own).sort(),['handJson','knowledgeJson','stateVersion','viewer']);
  assert.equal(Object.hasOwn(JSON.parse(p.rulesJson),'hidden'),false);
  assert.equal(Object.hasOwn(JSON.parse(own.knowledgeJson),'decks'),false);
  assert.equal(JSON.parse(own.knowledgeJson).pendingCards.length,0);
  assert.equal(JSON.parse(own.handJson).length,3);
  assert.throws(()=>reconnectSnapshot(m,'attacker'));
  const snap=reconnectSnapshot(m,'alice');assert.deepEqual(Object.keys(snap.view).sort(),['private','public']);
});
test('rollout stages and rollback are atomic valid objects',()=>{
  assert.deepEqual(validateRollout(LEGACY_ONLY),LEGACY_ONLY);
  const coexist={...LEGACY_ONLY,v1MatchmakingEnabled:true};validateRollout(coexist);
  validateRollout({...coexist,legacyNewMatchesEnabled:false,legacyForceUpdateEnabled:true,forceUpdatePlatforms:['android','ios'],v1StoreReleaseReadyAndroid:true,v1StoreReleaseReadyIos:true});
  validateRollout({...coexist,v1MatchmakingEnabled:false,legacyNewMatchesEnabled:true,legacyForceUpdateEnabled:false});
  validateRollout({...LEGACY_ONLY,legacyNewMatchesEnabled:false,maintenanceMode:true});
});
for(const [name,change] of Object.entries({disabledForce:{legacyForceUpdateEnabled:true},notStoreReady:{v1MatchmakingEnabled:true,legacyForceUpdateEnabled:true,forceUpdatePlatforms:['android']},noPath:{legacyNewMatchesEnabled:false},unsafeShutdown:{v1MatchmakingEnabled:true,legacyNewMatchesEnabled:false},iosNotReady:{v1MatchmakingEnabled:true,legacyForceUpdateEnabled:true,forceUpdatePlatforms:['android','ios'],v1StoreReleaseReadyAndroid:true}}))test('reject unsafe rollout '+name,()=>assert.throws(()=>validateRollout({...LEGACY_ONLY,...change})));
test('platform-aware readiness and build gating',()=>{
  validateRollout({...LEGACY_ONLY,v1MatchmakingEnabled:true,legacyForceUpdateEnabled:true,forceUpdatePlatforms:['android'],v1StoreReleaseReadyAndroid:true});
  assert.deepEqual(requireClient({platform:'android',build:17,protocolVersion:PROTOCOL},{...LEGACY_ONLY}),{platform:'android',build:17});
  assert.throws(()=>requireClient({platform:'ios',build:16,protocolVersion:PROTOCOL},{...LEGACY_ONLY}));
  assert.throws(()=>requireClient({platform:'android',build:18,protocolVersion:'future'},{...LEGACY_ONLY}));
});
