'use strict';
const crypto=require('node:crypto');
const {protocol,authority}=require('./battle-v1');
const {STARTER}=require('../rules-v1/dist/src/model.js');
const {migrateLegacy,validateOwnedDeck}=require('../rules-v1/dist/src/online/migration.js');
const {progressionSummary,reconcileCompetitiveProgression,syncEarlyProgress}=require('./battle-v1-progression');
const {PROTOCOL,BattleError,LEGACY_ONLY,validateRollout,requireClient,requireRecord,exactKeys,reconnectSnapshot}=protocol;
const digest=value=>crypto.createHash('sha256').update(value).digest('hex');
const matchId=(uid,id)=>'bv1_'+digest(uid+'|'+id).slice(0,32);
const QUEUE_TTL_MS=120000,MAX_QUEUE=128;
function installBattleV1Rollout(api,deps){
 const {db,now}=api;
 function decodeConfig(value){return value?validateRollout(value.configJson?JSON.parse(value.configJson):value):{...LEGACY_ONLY};}
 async function config(){return decodeConfig((await db.ref('battleRollout/config').get()).val());}
  async function updateConfig(value,expectedVersion){
  const next=validateRollout(value);let rejected=false;await db.ref('battleRollout/config').get();
  const tx=await db.ref('battleRollout/config').transaction(current=>{
   if(current===null&&expectedVersion!==LEGACY_ONLY.configVersion)return null;
   rejected=false;const previous=decodeConfig(current);
   if(previous.configVersion!==expectedVersion||next.configVersion!==previous.configVersion+1){rejected=true;return;}return {configVersion:next.configVersion,configJson:JSON.stringify(next)};
  },undefined,false);
  if(!tx.committed||rejected)throw new BattleError('STALE_CONFIG');return decodeConfig(tx.snapshot.val());
 }
 async function assertLegacyNewAllowed(platform='android'){
  const c=await config();if(c.maintenanceMode)throw new BattleError('TEMPORARILY_UNAVAILABLE',503);
  if(c.legacyForceUpdateEnabled&&c.forceUpdatePlatforms.includes(platform))throw new BattleError('UPDATE_REQUIRED',426);
  if(!c.legacyNewMatchesEnabled)throw new BattleError('TEMPORARILY_UNAVAILABLE',503);
 }
 async function admission(body){const c=await config();requireClient(body.client,c);if(c.maintenanceMode||!c.v1MatchmakingEnabled)throw new BattleError('TEMPORARILY_UNAVAILABLE',503);return c;}
 async function migrate(uid){
  const profile=await deps.requirePlayer(uid);let account;
  if(profile.uid!==uid)throw new BattleError('PROFILE_OWNER_MISMATCH',403);
  const tx=await db.ref('battleV1Accounts/'+uid).transaction(value=>{
   const old=value?.accountJson?JSON.parse(value.accountJson):null;
   account=migrateLegacy(profile,old);syncEarlyProgress(account,profile,uid,now());reconcileCompetitiveProgression(account);return {...value,accountJson:JSON.stringify(account)};
  },undefined,false);
  return {profile,account:JSON.parse(tx.snapshot.val().accountJson)};
 }
 async function setBattleV1Deck(context){const b=requireRecord(context.body);exactKeys(b,['client','deck']);await admission(b);await deps.rateLimit(context.uid,'setBattleV1Deck',20,60000);await migrate(context.uid);
  const tx=await db.ref('battleV1Accounts/'+context.uid).transaction(value=>{if(value===null)return null;const a=JSON.parse(value.accountJson);a.deck=validateOwnedDeck(b.deck,a);return {...value,accountJson:JSON.stringify(a)};},undefined,false);
  if(!tx.committed||!tx.snapshot.val())throw new BattleError('TEMPORARILY_UNAVAILABLE',503);return {ok:true,deck:JSON.parse(tx.snapshot.val().accountJson).deck};
 }
 async function getBattleV1Deck(context){const b=requireRecord(context.body);exactKeys(b,['client']);const c=await config();requireClient(b.client,c);await deps.rateLimit(context.uid,'getBattleV1Deck',60,60000);
  const {account}=await migrate(context.uid);return {ok:true,protocolVersion:PROTOCOL,deck:account.deck,entitlements:account.entitlements,progression:progressionSummary(account),available:c.v1MatchmakingEnabled&&!c.maintenanceMode};
 }
 async function getBattleV1Rollout(context){const b=requireRecord(context.body);exactKeys(b,['client']);const c=await config(),client=requireClient(b.client,c);return {ok:true,protocolVersion:PROTOCOL,configVersion:c.configVersion,available:c.v1MatchmakingEnabled&&!c.maintenanceMode,maintenanceMode:c.maintenanceMode,minClientBuild:client.platform==='android'?c.minV1ClientBuildAndroid:c.minV1ClientBuildIos};}
 async function completeReservation(id){
  const reservation=(await db.ref('battleV1Control/reservations/'+id).get()).val();
  if(!reservation){return null;}
  const m=await api.create(id,reservation.w.player,reservation.b.player,reservation.w.deck,reservation.b.deck,reservation.rated,{w:reservation.w.rating||0,b:reservation.b.rating||0});
  await db.ref('battleV1Control').transaction(v=>{if(v===null)return null;if(v.reservations?.[id])delete v.reservations[id];return v;},undefined,false);
  return m;
 }
 async function entry(uid,client){const {profile,account}=await migrate(uid);return {uid,player:{uid,name:String(profile.username||profile.name||'LunoPlayer').slice(0,32),bot:false},deck:account.deck,rating:account.rating,skill:account.games?account.rating:account.provisionalSkillSeed,client,joinedAt:now(),lastSeenAt:now(),protocolVersion:PROTOCOL};}
 async function enqueueBattleV1(context){
  const b=requireRecord(context.body);exactKeys(b,['client']);const c=await admission(b);await deps.rateLimit(context.uid,'enqueueBattleV1',30,60000);
  if(deps.resolveLegacyForV1)await deps.resolveLegacyForV1(context.uid);
  const queued=await entry(context.uid,b.client),id=matchId(context.uid,context.requestId),at=now(),ownWhite=crypto.randomInt(2)===0;let error=null;
  const tx=await db.ref('battleV1Control').transaction(value=>{
   error=null;const v=value||{};v.queue=v.queue||{};v.active=v.active||{};v.reservations=v.reservations||{};
   if(v.active[context.uid])return v;
   const room=v.rooms?.[v.roomByUser?.[context.uid]];if(room&&room.expiresAt>at&&!room.matchId){error=new BattleError('ROOM_ACTIVE');return;}
   if(v.lastMatch)delete v.lastMatch[context.uid];
   for(const [uid,q] of Object.entries(v.queue))if(!q||at-q.lastSeenAt>QUEUE_TTL_MS)delete v.queue[uid];
   const previous=v.queue[context.uid];const own={...queued,joinedAt:previous?.joinedAt||at,lastSeenAt:at};
   const candidates=Object.values(v.queue).filter(q=>q.uid!==context.uid&&q.protocolVersion===PROTOCOL).sort((a,b)=>Math.abs(a.skill-own.skill)-Math.abs(b.skill-own.skill)||a.joinedAt-b.joinedAt||a.uid.localeCompare(b.uid));
   let opponent=candidates[0];
   if(!opponent&&at-own.joinedAt>=c.v1BotFillTimeoutMs)opponent={uid:'bot_v1_'+id.slice(4),player:{uid:'bot_v1_'+id.slice(4),name:'Luno',bot:true},deck:[...STARTER]};
   if(!opponent){if(Object.keys(v.queue).length>=MAX_QUEUE&&!previous){error=new BattleError('TEMPORARILY_UNAVAILABLE',503);return;}v.queue[context.uid]=own;return v;}
   delete v.queue[context.uid];delete v.queue[opponent.uid];
   v.reservations[id]={w:ownWhite?own:opponent,b:ownWhite?opponent:own,rated:!opponent.player.bot,configVersion:c.configVersion};
   v.active[context.uid]=id;if(!opponent.player.bot)v.active[opponent.uid]=id;return v;
  },undefined,false);
  if(!tx.committed){if(error)throw error;throw new BattleError('TEMPORARILY_UNAVAILABLE',503);}
  const control=tx.snapshot.val(),active=control.active?.[context.uid];
  if(active){const m=await completeReservation(active)||await api.load(active,context.uid);return reconnectSnapshot(m,context.uid);}
  return {ok:true,status:'queued',protocolVersion:PROTOCOL,joinedAt:control.queue?.[context.uid]?.joinedAt};
 }
 async function cancelBattleV1Queue(context){const b=requireRecord(context.body);exactKeys(b,['protocolVersion']);if(b.protocolVersion!==PROTOCOL)throw new BattleError('INCOMPATIBLE_PROTOCOL',400);await deps.rateLimit(context.uid,'cancelBattleV1Queue',30,60000);
  const tx=await db.ref('battleV1Control').transaction(v=>{if(v===null)return null;if(v.queue)delete v.queue[context.uid];return v;},undefined,false);
  const id=tx.snapshot.val()?.active?.[context.uid];if(id){const m=await completeReservation(id)||await api.load(id,context.uid);return reconnectSnapshot(m,context.uid);}return {ok:true,status:'idle'};
 }
 const directGet=api.getBattleV1;
 api.getBattleV1=async context=>{
  if(context.body?.matchId===''){
   const b=requireRecord(context.body);exactKeys(b,['matchId','protocolVersion']);if(b.protocolVersion!==PROTOCOL)throw new BattleError('INCOMPATIBLE_PROTOCOL',400);
   await deps.requirePlayer(context.uid);await deps.rateLimit(context.uid,'getBattleV1Queue',90,60000);
   const [active,last,queued]=await Promise.all(['active','lastMatch','queue'].map(k=>db.ref('battleV1Control/'+k+'/'+context.uid).get()));
   const id=active.val()||last.val();
   if(id){await completeReservation(id);return directGet({...context,body:{matchId:id,protocolVersion:PROTOCOL}});}
   if(queued.val())return enqueueBattleV1({...context,body:{client:queued.val().client}});
   return {ok:true,status:'idle'};
  }
  return directGet(context);
 };
 Object.assign(api,{config,updateConfig,assertLegacyNewAllowed,admission,migrate,entry,setBattleV1Deck,getBattleV1Deck,getBattleV1Rollout,enqueueBattleV1,cancelBattleV1Queue,completeReservation,matchId});
 return api;
}
module.exports={installBattleV1Rollout};
