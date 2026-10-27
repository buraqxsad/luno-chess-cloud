'use strict';
const {applyRankedSettlement}=require('./ranked');
const {applyV1Rating,MAX_V1_TROPHIES}=require('./battle-v1-rating');
const {projectBattleV1ProductProgress}=require('./battle-v1-product-progress');
const {finalizePlayerStateRevision}=require('./player-state-revision');
const {protocol,authority}=require('./battle-v1');
const {CARDS}=require('../rules-v1/dist/src/model.js');
const {PROTOCOL,BattleError,requireRecord,exactKeys,validMatchId,validActionId,sideForUid,reconnectSnapshot}=protocol;
function playerSettlementMetrics(match,side){
 const used=[...new Set(match.battle.rules.used[side])],prefix='player:'+side+':';
 const counter=key=>{const value=match.metrics?.[prefix+key];return Number.isSafeInteger(value)&&value>=0?value:0;};
 return {cardsPlayed:used.length,legendaryCards:used.filter(id=>CARDS[id]?.rarity==='legendary').length,
  captures:counter('captures'),checks:counter('checks'),promotions:counter('promotions'),
  cardUsage:Object.fromEntries(used.map(id=>[id,1])),moveCount:Math.ceil((match.battle.rules.ply-(side==='b'?1:0))/2)};
}
function installBattleV1Recovery(api,deps){
 const {db,now}=api;
 async function cleanup(match){
  await db.ref('battleV1Control').transaction(v=>{if(v===null)return null;for(const p of Object.values(match.players))if(v.active?.[p.uid]===match.matchId){delete v.active[p.uid];if(!p.bot&&!match.deletedParticipants?.[p.uid]){v.lastMatch=v.lastMatch||{};v.lastMatch[p.uid]=match.matchId;}}return v;},undefined,false);
 }
 async function settle(id,uid){
  let match=await api.load(id,uid);if(!match.result)return match;
  if(match.settlementStatus==='complete'){await api.publish(match);await cleanup(match);return match;}
  const receipts={};
  for(const side of ['w','b']){
   const p=match.players[side];if(p.bot)continue;
   const tx=await db.ref('battleV1Accounts/'+p.uid).transaction(value=>{
    if(value===null)return null;const account=JSON.parse(value.accountJson),before=account.ratingSettlements?.[id];
    applyV1Rating(account,match,p.uid);if(!before)account.ratingRevision=(account.ratingRevision||0)+1;
    return {...value,accountJson:JSON.stringify(account)};
   },undefined,false);
   if(!tx.snapshot.val()){receipts[side]={skipped:true,reason:'account-unavailable'};continue;}
   const account=JSON.parse(tx.snapshot.val().accountJson),receipt=account.ratingSettlements[id];receipts[side]=receipt;
   if(match.rated){
    const projectedAt=now();
    await db.ref('users/'+p.uid).transaction(profile=>{
     if(profile===null)return null;
     if(profile.uid!==p.uid)throw new BattleError('profile-owner-mismatch',403);
     const previousProfile=structuredClone(profile);
     const preserved={};for(const key of ['trophies','arenaIdx','serverCompetition','serverSeason'])preserved[key]={has:Object.hasOwn(profile,key),value:structuredClone(profile[key])};
     profile.serverProgress=profile.serverProgress||{};profile.serverProgress.battleProtocol=PROTOCOL;
     // Historical receipts omit previousTrophies; their committed delta still identifies it.
     profile.trophies=receipt.previousTrophies??Math.max(0,(receipt.newTrophies??0)-(receipt.trophyDelta??0));profile.arenaIdx=0;
     applyRankedSettlement(profile,{uid:p.uid,matchId:id,outcome:receipt.outcome,opponentTrophies:match.ratingAtStart?.[side==='w'?'b':'w']??0,moveCount:match.battle.rules.ply,metrics:playerSettlementMetrics(match,side),at:match.result.finishedAt,trophyCap:MAX_V1_TROPHIES});
     for(const [key,saved] of Object.entries(preserved)){if(saved.has)profile[key]=saved.value;else delete profile[key];}
     projectBattleV1ProductProgress(profile,account,id,projectedAt);
     finalizePlayerStateRevision(profile,previousProfile);
     return profile;
    },undefined,false);
   }
   await db.ref('battleV1Ratings/'+p.uid).transaction(value=>value?.revision>=account.ratingRevision?value:{uid:p.uid,name:p.name,rating:account.rating,games:account.games||0,revision:account.ratingRevision||0,protocolVersion:PROTOCOL},undefined,false);
  }
  const tx=await api.transact(id,uid,m=>{if(m.settlementStatus==='complete')return {match:m};m.settlementStatus='complete';m.settlements=receipts;m.stateVersion++;return {match:m};});
  match=tx.match;await api.publish(match);await cleanup(match);return match;
 }
 async function driveBot(match,uid){
  for(let i=0;i<4&&!match.result;i++){
   const side=match.battle.rules.fen.split(' ')[1];if(!match.players[side].bot)break;
   const intent=authority.botIntent(match,side);if(!intent)break;
   const request={matchId:match.matchId,protocolVersion:PROTOCOL,expectedStateVersion:match.stateVersion,actionId:`a${match.stateVersion}_server-bot-action`,intent};
   const tx=await api.transact(match.matchId,uid,m=>{const expired=authority.expireClock(m,now());if(expired!==m)return {match:expired};if(m.stateVersion!==request.expectedStateVersion)return {match:m};return authority.commitAction(m,m.players[side].uid,request,now());});
   match=tx.match;await api.publish(match);
  }
  return match.result?settle(match.matchId,uid):match;
 }
 const originalGet=api.getBattleV1,originalSubmit=api.submitBattleV1Action;
 api.getBattleV1=async context=>{const r=await originalGet(context);if(!r.matchId)return r;let m=await api.load(r.matchId,context.uid);m=await driveBot(m,context.uid);if(m.result)m=await settle(m.matchId,context.uid);return api.snapshot(m,context.uid);};
 api.submitBattleV1Action=async context=>{let r;try{r=await originalSubmit(context);}catch(e){if(e.code==='MATCH_TIMEOUT')await settle(context.body.matchId,context.uid);throw e;}let m=await api.load(r.matchId,context.uid);m=await driveBot(m,context.uid);if(m.result)m=await settle(m.matchId,context.uid);return {...api.snapshot(m,context.uid),duplicate:r.duplicate,acceptedVersion:r.acceptedVersion};};
 async function resignBattleV1(context){
  const b=requireRecord(context.body);exactKeys(b,['matchId','actionId','expectedStateVersion','protocolVersion']);
  if(b.protocolVersion!==PROTOCOL||!validMatchId(b.matchId)||!validActionId(b.actionId)||!Number.isSafeInteger(b.expectedStateVersion)||!b.actionId.startsWith(`a${b.expectedStateVersion}_`))throw new BattleError('INVALID_ACTION',400);
  await deps.requirePlayer(context.uid);await deps.rateLimit(context.uid,'resignBattleV1',20,60000);
  const at=now(),tx=await api.transact(b.matchId,context.uid,m=>{
   const previous=m.actions[b.actionId],digest='resign|'+b.expectedStateVersion;
   if(previous){if(previous.uid!==context.uid||previous.digest!==digest)throw new BattleError('ACTION_ID_CONFLICT');return {match:m};}
   if(m.result)throw new BattleError('MATCH_TERMINAL');if(m.stateVersion!==b.expectedStateVersion)throw new BattleError('STALE_STATE');
   const expired=authority.expireClock(m,at);if(expired!==m)return {match:expired};
   const side=sideForUid(m,context.uid),next=authority.finishMatch(m,{reason:'resign',winner:side==='w'?'b':'w',finishedAt:at});
   next.actions[b.actionId]={uid:context.uid,digest,stateVersion:next.stateVersion};return {match:next};
  });return api.snapshot(await settle(tx.match.matchId,context.uid),context.uid);
 }
 async function sweep(){
  // A rotating key cursor prevents long-lived early IDs starving later matches.
  const cursor=(await db.ref('battleV1Maintenance/cursor').get()).val()||'';
  const activeQuery=db.ref('matchSecretsV1').orderByChild('status');
  let active=await (cursor?activeQuery.startAt('active',cursor+'\uf8ff'):activeQuery.startAt('active')).endAt('active').limitToFirst(80).get();
  if(!active.exists()){active=await db.ref('matchSecretsV1').orderByChild('status').equalTo('active').limitToFirst(80).get();}
  const activeIds=Object.keys(active.val()||{}).sort();await db.ref('battleV1Maintenance/cursor').set(activeIds.at(-1)||'');
  for(const [id,value] of Object.entries(active.val()||{})){try{const m=api.hydrate(value),human=Object.values(m.players).find(p=>!p.bot);if(!human)continue;const tx=await api.transact(id,human.uid,current=>({match:authority.expireClock(current,now())}));await driveBot(tx.match,human.uid);if(tx.match.result)await settle(id,human.uid);}catch(e){deps.logger?.warn('Battle V1 maintenance deferred',{matchId:id,code:e.code||'TEMPORARILY_UNAVAILABLE'});}}
  const pending=await db.ref('matchSecretsV1').orderByChild('settlementStatus').equalTo('pending').limitToFirst(80).get();
  for(const [id,value] of Object.entries(pending.val()||{})){try{const m=api.hydrate(value),human=Object.values(m.players).find(p=>!p.bot);if(human)await settle(id,human.uid);}catch(e){deps.logger?.warn('Battle V1 settlement deferred',{matchId:id,code:e.code||'TEMPORARILY_UNAVAILABLE'});}}
 }
 async function ackBattleV1Result(context){
  const b=requireRecord(context.body);exactKeys(b,['matchId','protocolVersion']);if(b.protocolVersion!==PROTOCOL)throw new BattleError('INCOMPATIBLE_PROTOCOL',400);
  await deps.requirePlayer(context.uid);await deps.rateLimit(context.uid,'ackBattleV1Result',20,60000);const m=await api.load(b.matchId,context.uid);if(!m.result||m.settlementStatus!=='complete')throw new BattleError('RESULT_NOT_READY');
  await db.ref('battleV1Control').transaction(v=>{if(v===null)return null;if(v.lastMatch?.[context.uid]===m.matchId)delete v.lastMatch[context.uid];return v;},undefined,false);return {ok:true,acknowledged:true};
 }
 Object.assign(api,{settle,driveBot,resignBattleV1,ackBattleV1Result,sweep,cleanup});return api;
}
module.exports={installBattleV1Recovery,playerSettlementMetrics};
