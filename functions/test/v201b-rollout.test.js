'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {createBattleV1Api,authority,protocol}=require('../lib/battle-v1');
const {installBattleV1Rollout}=require('../lib/battle-v1-rollout');
const {applyV1Rating}=require('../lib/battle-v1-rating');
const {applyChestInventoryRewards}=require('../lib/chests');
const {STARTER}=require('../rules-v1/dist/src/model.js');
function fixture(){
 const root={},copy=v=>v===undefined?null:structuredClone(v),read=p=>p.split('/').filter(Boolean).reduce((v,k)=>v?.[k],root);
 function write(p,v){const parts=p.split('/').filter(Boolean),key=parts.pop();let n=root;for(const part of parts)n=n[part]||(n[part]={});if(v===null)delete n[key];else n[key]=copy(v);}
 const snap=v=>({val:()=>copy(v),exists:()=>v!==undefined&&v!==null});
 const db={ref:(p='')=>({get:async()=>snap(read(p)),set:async v=>write(p,v),transaction:async f=>{const v=f(copy(read(p)));if(v!==undefined)write(p,v);return {committed:v!==undefined,snapshot:snap(read(p))};}})};
 let at=1000;const profiles={};
 const deps={db,now:()=>at,requirePlayer:async uid=>profiles[uid]||{uid,username:uid,deck:['freeze'],unlockedCards:{freeze:true},trophies:1500},rateLimit:async()=>{}};
 return {root,read,write,profiles,api:installBattleV1Rollout(createBattleV1Api(deps),deps),setTime:n=>at=n,client:{platform:'android',build:17,protocolVersion:protocol.PROTOCOL}};
}
test('rollout defaults legacy only; safe atomic coexistence, force update and rollback',async()=>{const f=fixture();await assert.rejects(f.api.enqueueBattleV1({uid:'alice',body:{client:f.client},requestId:'queue-1'}),{code:'TEMPORARILY_UNAVAILABLE'});await f.api.assertLegacyNewAllowed();const c={...protocol.LEGACY_ONLY,configVersion:2,v1MatchmakingEnabled:true};await f.api.updateConfig(c,1);await assert.rejects(f.api.updateConfig({...c,configVersion:3,legacyNewMatchesEnabled:false},2));assert.deepEqual(await f.api.config(),c);await f.api.updateConfig({...c,configVersion:3,legacyNewMatchesEnabled:false,legacyForceUpdateEnabled:true,forceUpdatePlatforms:['android','ios'],v1StoreReleaseReadyAndroid:true,v1StoreReleaseReadyIos:true},2);await assert.rejects(f.api.assertLegacyNewAllowed(),{code:'UPDATE_REQUIRED'});await f.api.updateConfig({...c,configVersion:4,v1MatchmakingEnabled:false},3);await f.api.assertLegacyNewAllowed();});
test('two V1 clients pair only in V1 control, migration retry is free and idempotent',async()=>{const f=fixture();await f.api.updateConfig({...protocol.LEGACY_ONLY,configVersion:2,v1MatchmakingEnabled:true},1);const a=await f.api.enqueueBattleV1({uid:'alice',body:{client:f.client},requestId:'queue-a'});assert.equal(a.status,'queued');const b=await f.api.enqueueBattleV1({uid:'bob',body:{client:f.client},requestId:'queue-b'});assert.equal(b.status,'active');assert.equal(b.view.public.protocolVersion,protocol.PROTOCOL);const again=await f.api.getBattleV1({uid:'alice',body:{matchId:'',protocolVersion:protocol.PROTOCOL},requestId:'poll-a'});assert.equal(again.matchId,b.matchId);const account=f.read('battleV1Accounts/alice');await f.api.migrate('alice');assert.deepEqual(f.read('battleV1Accounts/alice'),account);assert.equal(f.read('rankedState'),undefined);await assert.rejects(f.api.enqueueBattleV1({uid:'attacker',body:{client:{...f.client,protocolVersion:'legacy'}},requestId:'bad'}));});
test('V1 bot fill is unrated and has no human private projection',async()=>{const f=fixture();await f.api.updateConfig({...protocol.LEGACY_ONLY,configVersion:2,v1MatchmakingEnabled:true},1);await f.api.enqueueBattleV1({uid:'alice',body:{client:f.client},requestId:'bot-wait'});f.setTime(32000);const r=await f.api.getBattleV1({uid:'alice',body:{matchId:'',protocolVersion:protocol.PROTOCOL},requestId:'bot-poll'});assert.equal(r.view.public.rated,false);assert.equal(Object.values(r.view.public.players).filter(p=>p.bot).length,1);const projections=f.read('matchesV1/'+r.matchId);assert.deepEqual(Object.keys(projections.private),['alice']);});
test('V1 settlement cannot mutate legacy rating and duplicate rating is inert',()=>{const f=fixture(),legacy={trophies:1700,arenaIdx:5},before=structuredClone(legacy);let m=authority.createServerMatch('bv1_'+'9'.repeat(32),{uid:'alice',name:'A',bot:false},{uid:'bob',name:'B',bot:false},STARTER,STARTER,1000);m=authority.finishMatch(m,{reason:'checkmate',winner:'w',finishedAt:2000});const account={rating:0};const r=applyV1Rating(account,m,'alice');assert.equal(r.rated,true);assert(account.rating>0);assert.deepEqual(legacy,before);const saved=structuredClone(account);applyV1Rating(account,m,'alice');assert.deepEqual(account,saved);assert.throws(()=>applyV1Rating(account,{...m,protocolVersion:'legacy'},'alice'));});
test('owner deck read and post-migration chest unlock can be saved, never forged for another account',async()=>{
 const f=fixture();f.profiles.alice={uid:'alice',username:'Alice',deck:[],unlockedCards:{},trophies:0};
 const initial=await f.api.getBattleV1Deck({uid:'alice',body:{client:f.client}});
 assert.deepEqual(initial.deck,STARTER);assert.equal(initial.available,false);
 assert.equal(initial.entitlements.includes('fog'),false);
 f.profiles.alice.unlockedCards.fog=true;
 const earned=await f.api.getBattleV1Deck({uid:'alice',body:{client:f.client}});
 assert(earned.entitlements.includes('fog'));
 assert.equal((await f.api.getBattleV1Deck({uid:'bob',body:{client:f.client}})).entitlements.includes('fog'),false);
 await assert.rejects(f.api.getBattleV1Deck({uid:'bob',body:{client:f.client,uid:'alice'}}),{code:'INVALID_ACTION'});
 await f.api.updateConfig({...protocol.LEGACY_ONLY,configVersion:2,v1MatchmakingEnabled:true},1);
 const deck=[...STARTER.slice(0,9),'fog'];
 assert.deepEqual((await f.api.setBattleV1Deck({uid:'alice',body:{client:f.client,deck}})).deck,deck);
 assert.deepEqual((await f.api.getBattleV1Deck({uid:'alice',body:{client:f.client}})).deck,deck);
 await assert.rejects(f.api.setBattleV1Deck({uid:'bob',body:{client:f.client,deck}}),{code:'CARD_NOT_OWNED'});
 assert.deepEqual((await f.api.getBattleV1Deck({uid:'bob',body:{client:f.client}})).deck,STARTER);
});
test('historic chest card receipt reaches the server deck and actual matchmaking entry',async()=>{
 const f=fixture();
 const profile={uid:'alice',username:'Alice',deck:[],unlockedCards:{},trophies:0,stats:{}};
 f.profiles.alice=profile;
 await f.api.getBattleV1Deck({uid:'alice',body:{client:f.client}});
 const rewards=[{type:'battle_card',id:'mine',rarity:'rare',amount:1}];
 const granted=applyChestInventoryRewards(profile,rewards);
 const card=granted.find(reward=>reward.type==='battle_card');
 const account=await f.api.getBattleV1Deck({uid:'alice',body:{client:f.client}});
 assert(account.entitlements.includes(card.id));
 await f.api.updateConfig({...protocol.LEGACY_ONLY,configVersion:2,v1MatchmakingEnabled:true},1);
 const deck=[...STARTER.slice(0,9),card.id];
 await f.api.setBattleV1Deck({uid:'alice',body:{client:f.client,deck}});
 const queued=await f.api.enqueueBattleV1({uid:'alice',body:{client:f.client},requestId:'earned-card-queue'});
 assert.equal(queued.status,'queued');
 assert.deepEqual(f.read('battleV1Control/queue/alice').deck,deck);
 const matched=await f.api.enqueueBattleV1({uid:'bob',body:{client:f.client},requestId:'opponent-queue'});
 assert.equal(matched.status,'active');
 const match=await f.api.load(matched.matchId,'alice');
 const side=match.players.w.uid==='alice'?'w':'b';
 assert([...match.audit[0].hands[side],...match.audit[0].decks[side]].includes(card.id));
});
