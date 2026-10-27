'use strict';
const {authHost,databaseHost}=require('./helpers/local-emulators').requireLocalEmulators();
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
process.env.LUNO_DB_EMULATOR_NAMESPACE='demo-luno-v201b-default-rtdb';
const namespace=process.env.LUNO_DB_EMULATOR_NAMESPACE;
const {getDatabase}=require('firebase-admin/database');
const {getApps,deleteApp}=require('firebase-admin/app');
const {handler,battleV1,starterProfile,applyRankedSettlement}=require('../index')._test;
const {protocol,authority}=require('../lib/battle-v1');
const {newBattle,applyAuthoritative,playerView}=require('../rules-v1/dist/src/authoritative');
const {publicFingerprint}=require('../rules-v1/dist/src/core');
const {CARDS,STARTER,clone}=require('../rules-v1/dist/src/model');
const {initial}=require('../rules-v1/dist/test/fixture_support');
const db=getDatabase(),client={platform:'android',build:17,protocolVersion:protocol.PROTOCOL};
const totals={allowed:0,denied:0,forgedRejected:0,fixtureActions:0,fixtureIllegal:0,reconnectChecks:0,sideChannelPairs:0,concurrentReplays:0,maintenanceBatches:0,authenticationRejected:0};let sequence=0,users;
async function user(){const r=await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-key`,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({returnSecureToken:true}),signal:AbortSignal.timeout(15000)});assert.equal(r.status,200);return r.json();}
async function call(route,u,body={},appCheck='luno-emulator-app-check'){
 const headers={authorization:'Bearer '+u.idToken,'x-firebase-appcheck':appCheck,'x-luno-request-id':'v201b-integration-'+(++sequence),origin:'https://localhost'};
 const req={method:'POST',path:'/'+route,body,get:k=>headers[k.toLowerCase()]||''};let status=200,result;
 const res={set(){return this;},status(s){status=s;return this;},json(r){result=r;return this;},send(r){result=r;return this;}};
 await handler(req,res);return {status,body:result};
}
async function read(path,u,allow,method='GET'){
 const r=await fetch(`http://${databaseHost}/${path}.json?ns=${namespace}&auth=${encodeURIComponent(u.idToken)}`,{method,headers:{'content-type':'application/json'},signal:AbortSignal.timeout(15000),...(method==='PUT'?{body:JSON.stringify({forged:true})}:{})});
 assert.equal(r.status,allow?200:401,`${method} ${path}: ${await r.text()}`);allow?totals.allowed++:totals.denied++;
}
function noSecrets(response){
 assert.deepEqual(Object.keys(response.view).sort(),['private','public']);
 const p=response.view.public,own=response.view.private,r=JSON.parse(p.rulesJson),k=JSON.parse(own.knowledgeJson);
 for(const forbidden of ['hidden','hands','decks','deckOrder','seed','shuffleSeed','analysisJson','settlementJson'])assert(!Object.hasOwn(p,forbidden)&&!Object.hasOwn(r,forbidden));
 assert.deepEqual(Object.keys(k).sort(),['knownUpcomingCards','pendingCards','radarObservations']);
 assert(!Object.hasOwn(own,'decks')&&!Object.hasOwn(own,'deckOrder'));
}
async function storeFixture(battle,id='bv1_'+crypto.randomBytes(16).toString('hex')){
 const m=authority.createServerMatch(id,{uid:users[0].localId,name:'A',bot:false},{uid:users[1].localId,name:'B',bot:false},STARTER,STARTER,Date.now(),false);
 m.battle=clone(battle);m.clock.activeSide=battle.rules.fen.split(' ')[1];m.audit=[];
 await db.ref('matchSecretsV1/'+id).set(battleV1.stored(m));await battleV1.publish(m);return m;
}
async function action(m,intent,u=users[m.battle.rules.fen.split(' ')[1]==='w'?0:1],extra={}){return call('submitBattleV1Action',u,{matchId:m.matchId,protocolVersion:protocol.PROTOCOL,expectedStateVersion:m.stateVersion,actionId:`a${m.stateVersion}_integration-action-${sequence}`,intent,...extra});}
async function reject(m,intent,extra={},u){const before=(await db.ref('matchSecretsV1/'+m.matchId).get()).val();const r=await action(m,intent,u,extra);assert(r.status>=400&&r.status<500,JSON.stringify(r));assert.deepEqual((await db.ref('matchSecretsV1/'+m.matchId).get()).val(),before);totals.forgedRejected++;}
async function main(){
 assert.equal(process.env.GCLOUD_PROJECT,'demo-luno-v201b');users=await Promise.all([user(),user(),user()]);
 for(const [i,u] of users.entries()){await db.ref('users/'+u.localId).set(starterProfile(u.localId,'v201b_player_'+i));await battleV1.migrate(u.localId);}
 await battleV1.updateConfig({...protocol.LEGACY_ONLY,configVersion:2,v1MatchmakingEnabled:true},1);
 const noAppCheck=await call('enqueueBattleV1',users[0],{client},'');assert.equal(noAppCheck.status,401);assert.equal(noAppCheck.body.error,'app-check-required');totals.authenticationRejected++;
 for(const token of ['','invalid-auth-token']){assert.equal((await call('enqueueBattleV1',{idToken:token},{client})).status,401);totals.authenticationRejected++;}
 assert.equal((await call('enqueueBattleV1',users[0],{client},'invalid-app-check-token')).status,401);totals.authenticationRejected++;
 assert.equal((await call('enqueueBattleV1',users[0],{client})).body.status,'queued');
 const paired=await call('enqueueBattleV1',users[1],{client});assert.equal(paired.status,200,JSON.stringify(paired));noSecrets(paired.body);const id=paired.body.matchId;
 for(const u of users.slice(0,2)){await read(`matchesV1/${id}/public`,u,true);await read(`matchesV1/${id}/private/${u.localId}`,u,true);}
 await read(`matchesV1/${id}/private/${users[1].localId}`,users[0],false);await read(`matchesV1/${id}/private/${users[0].localId}`,users[1],false);await read(`matchesV1/${id}/public`,users[2],false);
 for(const u of users)for(const p of [`matchesV1/${id}`,`matchesV1/${id}/private`,`matchSecretsV1/${id}`,`matchSecretsV1/${id}/recordJson`,`matchSecretsV1/${id}/battle/hidden/decks/${u.localId}`])await read(p,u,false);
 for(const u of users)for(const p of [`matchesV1/${id}/public`,`matchesV1/${id}/private/${u.localId}`,`matchSecretsV1/${id}`,'battleRollout/config','battleV1Control','battleV1Accounts/'+u.localId,'battleV1Ratings/'+u.localId])await read(p,u,false,'PUT');
 let m=await battleV1.load(id,users[0].localId);const moving=users.find(u=>u.localId===m.players.w.uid),other=users.find(u=>u.localId===m.players.b.uid);
 await reject(m,{type:'move',uci:'e2e5'},{},moving);await reject(m,{type:'move',uci:'e2e4'},{},other);await reject(m,{type:'move',uci:'e2e4'},{},users[2]);
 for(const field of ['mana','hand','decks','draw','seed','radarResult','state','board','activeEffect','mine','vow','rating','settlement'])await reject(m,{type:'move',uci:'e2e4'},{[field]:6},moving);
 const body={matchId:id,protocolVersion:protocol.PROTOCOL,expectedStateVersion:0,actionId:'a0_concurrent-replay-0001',intent:{type:'move',uci:'e2e4'}};
 const replays=await Promise.all(Array.from({length:6},()=>call('submitBattleV1Action',moving,body)));assert(replays.every(r=>r.status===200),JSON.stringify(replays));assert.equal(replays.filter(r=>!r.body.duplicate).length,1);totals.concurrentReplays=6;
 m=await battleV1.load(id,moving.localId);assert.equal(m.stateVersion,1);assert.equal(m.battle.rules.ply,1);await reject(m,{type:'move',uci:'e7e5'},{expectedStateVersion:0,actionId:'a0_stale-state-action'},other);
 await reject(m,{type:'move',uci:'d2d4'},{expectedStateVersion:0,actionId:body.actionId},moving);
 await reject(m,{type:'move',uci:'e7e5'},{expectedStateVersion:2,actionId:'a2_future-version-action'},other);
 await reject(m,{type:'move',uci:'e7e5'},{expectedStateVersion:-1,actionId:'a0_negative-version-action'},other);
 await reject(m,{type:'move',uci:'e7e5'},{protocolVersion:'UNKNOWN_FUTURE'},other);
 for(const u of users.slice(0,2)){const saved=(await db.ref('matchSecretsV1/'+id).get()).val();const r=await call('getBattleV1',u,{matchId:id,protocolVersion:protocol.PROTOCOL});assert.equal(r.status,200);noSecrets(r.body);assert.deepEqual((await db.ref('matchSecretsV1/'+id).get()).val(),saved);totals.reconnectChecks++;}
 for(const route of ['getRankedMatch','submitMatchAction'])assert((await call(route,moving,{matchId:id})).status>=400);
 assert.equal((await call('getBattleV1',users[2],{matchId:id,protocolVersion:protocol.PROTOCOL})).status,403);
 const fixtures=JSON.parse(fs.readFileSync(path.join(__dirname,'../../battle_contract/v1/rules.json'),'utf8')).fixtures;
 for(const f of fixtures){
  for(const u of users.slice(0,2))await db.ref('serverRateLimits/'+u.localId).remove();
  let expected=initial(f),match=await storeFixture(expected);
  for(const step of f.steps){if(!step.action)continue;const before=(await db.ref('matchSecretsV1/'+match.matchId).get()).val(),r=await action(match,step.action);
   if(step.legal===false){assert(r.status>=400&&r.status<500,f.fixtureId+JSON.stringify(r));assert.deepEqual((await db.ref('matchSecretsV1/'+match.matchId).get()).val(),before,f.fixtureId);totals.fixtureIllegal++;continue;}
   assert.equal(r.status,200,f.fixtureId+JSON.stringify(r));expected=applyAuthoritative(expected,step.action);match=await battleV1.load(match.matchId,users[0].localId);assert.deepEqual(match.battle,expected,f.fixtureId);noSecrets(r.body);totals.fixtureActions++;
   for(const u of users.slice(0,2)){const get=await call('getBattleV1',u,{matchId:match.matchId,protocolVersion:protocol.PROTOCOL});assert.equal(get.status,200,f.fixtureId);const own=JSON.parse(get.body.view.private.knowledgeJson),side=match.players.w.uid===u.localId?'w':'b';assert.deepEqual(own,expected.hidden.knowledge[side]);assert.deepEqual(JSON.parse(get.body.view.private.handJson),expected.hidden.hands[side]);totals.reconnectChecks++;}
  }
 }
 for(const fixtureId of ['shelter-window','fog-window']){const protectedMatch=await storeFixture(initial(fixtures.find(f=>f.fixtureId===fixtureId)));await reject(protectedMatch,{type:'play',card:'freeze',target:48});}
 const ready=initial(fixtures.find(f=>f.fixtureId==='card-freeze'));
 await reject(await storeFixture(ready),{type:'play',card:'shelter',target:8});
 await reject(await storeFixture(ready),{type:'play',card:'unknown_card',target:48});
 for(const field of ['used','discarded']){const retired=clone(ready);retired.hidden.hands.w=retired.hidden.hands.w.filter(c=>c!=='freeze');retired.rules.handCounts.w=retired.hidden.hands.w.length;retired.rules[field].w.push('freeze');await reject(await storeFixture(retired),{type:'play',card:'freeze',target:48});}
 const pinned=clone(newBattle(STARTER,STARTER));pinned.rules.fen='k3r3/8/8/8/8/8/4R3/4K3 w - - 0 1';pinned.rules.phase='chess';await reject(await storeFixture(pinned),{type:'move',uci:'e2a2'});
 for(const card of ['mana_sabotage','card_block','echo','radar']){
  const ownDeck=[card,...Object.keys(CARDS).filter(c=>c!==card)].slice(0,10),base=clone(newBattle(ownDeck,STARTER));base.rules.phase='card';base.rules.mana={w:6,b:6};base.rules.ownTurns={w:2,b:2};base.rules.repetitions={};
  const inHand=clone(base),inDeck=clone(base),index=inHand.hidden.decks.b.indexOf('freeze');[inHand.hidden.hands.b[0],inHand.hidden.decks.b[index]]=[inHand.hidden.decks.b[index],inHand.hidden.hands.b[0]];
  assert.deepEqual(inHand.rules,inDeck.rules);assert.equal(publicFingerprint(inHand.rules),publicFingerprint(inDeck.rules));
  const responses=[];for(const state of [inHand,inDeck]){const match=await storeFixture(state),r=await action(match,{type:'play',card,target:'freeze'});assert.equal(r.status,200,JSON.stringify(r));noSecrets(r.body);delete r.body.view.public.matchId;delete r.body.view.public.createdAt;delete r.body.view.public.clock;responses.push(r.body);}
  assert.deepEqual(responses[0].view.public,responses[1].view.public,card+' public side channel');assert.deepEqual(Object.keys(responses[0]).sort(),Object.keys(responses[1]).sort());if(card==='radar')assert.notDeepEqual(responses[0].view.private.knowledgeJson,responses[1].view.private.knowledgeJson);totals.sideChannelPairs++;
 }
 const legacyBefore=(await db.ref('users/'+moving.localId).get()).val(),accountBefore=(await db.ref('battleV1Accounts/'+moving.localId).get()).val();
 m=await battleV1.load(id,moving.localId);const resign={matchId:id,protocolVersion:protocol.PROTOCOL,expectedStateVersion:m.stateVersion,actionId:`a${m.stateVersion}_resign-integrated`};
 const end=await call('resignBattleV1',moving,resign);assert.equal(end.status,200,JSON.stringify(end));assert.equal(end.body.view.public.settlementStatus,'complete');assert(end.body.view.private.analysisJson);const profileAfter=(await db.ref('users/'+moving.localId).get()).val();assert.equal(profileAfter.trophies,legacyBefore.trophies);assert.equal(profileAfter.arenaIdx,legacyBefore.arenaIdx);
 const v1After=(await db.ref('battleV1Accounts/'+moving.localId).get()).val();assert.notDeepEqual(v1After,accountBefore);for(let i=0;i<3;i++)await battleV1.settle(id,moving.localId);assert.deepEqual((await db.ref('users/'+moving.localId).get()).val(),profileAfter);assert.deepEqual((await db.ref('battleV1Accounts/'+moving.localId).get()).val(),v1After);
 await read(`matchesV1/${id}/private/${moving.localId}/analysisJson`,users[2],false);await read(`matchesV1/${id}/public/analysisJson`,moving,true);
 const legacyClone=clone(profileAfter);applyRankedSettlement(legacyClone,{uid:moving.localId,matchId:'rm_'+'8'.repeat(32),outcome:'win',opponentTrophies:0,moveCount:20,at:Date.now()});assert.deepEqual((await db.ref('battleV1Accounts/'+moving.localId).get()).val(),v1After);
 assert.equal((await call('getBattleV1',moving,{matchId:'',protocolVersion:protocol.PROTOCOL})).body.matchId,id);
 assert.equal((await call('ackBattleV1Result',moving,{matchId:id,protocolVersion:protocol.PROTOCOL})).status,200);
 assert.equal((await call('getBattleV1',moving,{matchId:'',protocolVersion:protocol.PROTOCOL})).body.status,'idle');
 const botSearch=await call('enqueueBattleV1',moving,{client});assert.equal(botSearch.body.status,'queued');await db.ref('battleV1Control/queue/'+moving.localId+'/joinedAt').set(Date.now()-31000);
 const botGame=await call('getBattleV1',moving,{matchId:'',protocolVersion:protocol.PROTOCOL});assert.equal(botGame.status,200,JSON.stringify(botGame));assert.equal(botGame.body.view.public.rated,false);noSecrets(botGame.body);
 const bot=await battleV1.load(botGame.body.matchId,moving.localId),botSide=bot.players.w.bot?'w':'b',altered=clone(bot),enemy=botSide==='w'?'b':'w';altered.battle.hidden.hands[enemy].reverse();altered.battle.hidden.decks[enemy].reverse();
 assert.deepEqual(authority.botPlannerInput(bot,botSide),authority.botPlannerInput(altered,botSide));assert.deepEqual(authority.botIntent(bot,botSide),authority.botIntent(altered,botSide));
 const botUid=bot.players[botSide].uid;await read(`matchesV1/${bot.matchId}/private/${botUid}`,moving,false);
 const botRatingBefore=(await db.ref('battleV1Accounts/'+moving.localId).get()).val();await call('resignBattleV1',moving,{matchId:bot.matchId,protocolVersion:protocol.PROTOCOL,expectedStateVersion:bot.stateVersion,actionId:`a${bot.stateVersion}_bot-resign-action`});
 const botRatingAfter=(await db.ref('battleV1Accounts/'+moving.localId).get()).val();assert.equal(JSON.parse(botRatingAfter.accountJson).rating,JSON.parse(botRatingBefore.accountJson).rating);
 const pendingFixture=fixtures.find(f=>f.fixtureId==='card-prophecy'),pending=await storeFixture(initial(pendingFixture));const inspect=await action(pending,{type:'play',card:'prophecy'});assert.equal(inspect.status,200);const waiting=await battleV1.load(pending.matchId,users[0].localId);assert.equal(waiting.battle.rules.phase,'pending');waiting.clock.startedAt=Date.now()-waiting.clock.w-1;await db.ref('matchSecretsV1/'+waiting.matchId).set(battleV1.stored(waiting));
 const timeout=await action(waiting,{type:'resolve',order:waiting.battle.hidden.knowledge.w.pendingCards});assert.equal(timeout.body.error,'MATCH_TIMEOUT');const terminal=await battleV1.load(waiting.matchId,users[0].localId);assert.equal(terminal.result.reason,'timeout');assert.equal(terminal.settlementStatus,'complete');assert.equal(terminal.clock.w,0);await reject(terminal,{type:'resolve',order:[]});
 // More than one bounded maintenance page must advance past long-lived early IDs.
 const late=await storeFixture(newBattle(STARTER,STARTER),'bv1_'+'f'.repeat(32));late.clock.startedAt=Date.now()-late.clock.w-1;await db.ref('matchSecretsV1/'+late.matchId).set(battleV1.stored(late));
 assert(Object.keys((await db.ref('matchSecretsV1').orderByChild('status').equalTo('active').get()).val()||{}).length>80);
 await db.ref('battleV1Maintenance/cursor').set('');await battleV1.sweep();totals.maintenanceBatches++;
 assert.equal((await battleV1.load(late.matchId,users[0].localId)).result,null);
 await battleV1.sweep();totals.maintenanceBatches++;
 const swept=await battleV1.load(late.matchId,users[0].localId);assert.equal(swept.result.reason,'timeout');assert.equal(swept.settlementStatus,'complete');
 await battleV1.leaveAccount(moving.localId);await db.ref('users/'+moving.localId).remove();await read(`matchesV1/${id}/private/${moving.localId}`,moving,false);
 const report={gate:5,namespace,fixtureCount:fixtures.length,...totals,pass:true};fs.writeFileSync(path.join(__dirname,'../../luno_chess/qa/v201b-gate5-production.json'),JSON.stringify(report,null,2));console.log('V201B_RESULT '+JSON.stringify(report));
}
main().catch(e=>{console.error(e);process.exitCode=1;}).finally(async()=>{await Promise.all(getApps().map(a=>deleteApp(a)));});
