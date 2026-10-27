import {clone,type Action,type AuthoritativeBattleState,type PlayerKnowledgeState,type RuleState,type Side} from '../model.js';

export const PROTOCOL='LUNO_BATTLE_V1' as const;
export const RULESET_VERSION=1;
export const INITIAL_CLOCK_MS=300_000;
export const INCREMENT_MS=2_000;
export type Platform='android'|'ios';
export class BattleError extends Error {
  constructor(public readonly code:string,public readonly status=409){super(code);}
}
export function requireRecord(value:unknown):Record<string,unknown>{
  if(!value||typeof value!=='object'||Array.isArray(value))throw new BattleError('INVALID_ACTION',400);
  return value as Record<string,unknown>;
}
export function exactKeys(value:Record<string,unknown>,required:readonly string[],optional:readonly string[]=[]):void{
  if(required.some(key=>!Object.hasOwn(value,key))||Object.keys(value).some(key=>!required.includes(key)&&!optional.includes(key)))throw new BattleError('INVALID_ACTION',400);
}
export function validUid(value:unknown):value is string{return typeof value==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(value);}
export function validMatchId(value:unknown):value is string{return typeof value==='string'&&/^bv1_[a-f0-9]{32}$/.test(value);}
export function validActionId(value:unknown):value is string{return typeof value==='string'&&/^[A-Za-z0-9_-]{12,80}$/.test(value);}
export function parseIntent(value:unknown):Action{
  const a=requireRecord(value);
  switch(a.type){
    case 'pass':exactKeys(a,['type']);break;
    case 'move':exactKeys(a,['type','uci']);if(typeof a.uci!=='string'||!/^[a-h][1-8][a-h][1-8][qrbn]?$/.test(a.uci))throw new BattleError('INVALID_ACTION',400);break;
    case 'discard':exactKeys(a,['type','card']);break;
    case 'play':exactKeys(a,['type','card'],['target','sacrifice']);
      if(a.target!==undefined&&!(Number.isInteger(a.target)&&Number(a.target)>=0&&Number(a.target)<64)&&!(typeof a.target==='string'&&a.target.length<=80))throw new BattleError('INVALID_ACTION',400);
      if(a.sacrifice!==undefined&&typeof a.sacrifice!=='string')throw new BattleError('INVALID_ACTION',400);break;
    case 'resolve':exactKeys(a,['type','order'],['selected']);
      if(!Array.isArray(a.order)||a.order.length>3||a.order.some(v=>typeof v!=='string')||new Set(a.order).size!==a.order.length||a.selected!==undefined&&typeof a.selected!=='string')throw new BattleError('INVALID_ACTION',400);break;
    default:throw new BattleError('INVALID_ACTION',400);
  }
  if(('card' in a)&&(typeof a.card!=='string'||a.card.length>32))throw new BattleError('INVALID_ACTION',400);
  return clone(a) as Action;
}
export interface ActionRequest {matchId:string;actionId:string;expectedStateVersion:number;protocolVersion:typeof PROTOCOL;intent:Action}
export function parseActionRequest(value:unknown):ActionRequest{
  const r=requireRecord(value);exactKeys(r,['matchId','actionId','expectedStateVersion','protocolVersion','intent']);
  if(r.protocolVersion!==PROTOCOL)throw new BattleError('INCOMPATIBLE_PROTOCOL',400);
  if(!validMatchId(r.matchId)||!validActionId(r.actionId)||!Number.isSafeInteger(r.expectedStateVersion)||Number(r.expectedStateVersion)<0)throw new BattleError('INVALID_ACTION',400);
  return {matchId:r.matchId,actionId:r.actionId,expectedStateVersion:Number(r.expectedStateVersion),protocolVersion:PROTOCOL,intent:parseIntent(r.intent)};
}
export interface Participant {uid:string;name:string;bot:boolean}
export interface MatchResult {reason:string;winner:Side|null;finishedAt:number}
export interface Clock {w:number;b:number;activeSide:Side;startedAt:number;incrementMs:number}
export interface PublicEvent {stateVersion:number;actor:Side;type:Action['type'];card?:string;target?:number|string;uci?:string}
export interface MatchProjection {
  matchId:string;protocolVersion:typeof PROTOCOL;rulesetVersion:number;stateVersion:number;
  participants:Record<string,true>;players:{w:Participant;b:Participant};
  rulesJson:string;clock:Clock;result:MatchResult|null;settlementStatus:'none'|'pending'|'complete';
  rated:boolean;createdAt:number;lastEvent:PublicEvent|null;
}
export interface PrivateProjection {stateVersion:number;viewer:Side;handJson:string;knowledgeJson:string}
export interface ServerMatch {
  matchId:string;protocolVersion:typeof PROTOCOL;rulesetVersion:number;stateVersion:number;
  players:{w:Participant;b:Participant};battle:AuthoritativeBattleState;clock:Clock;
  result:MatchResult|null;settlementStatus:'none'|'pending'|'complete';rated:boolean;createdAt:number;
  actions:Record<string,{uid:string;digest:string;stateVersion:number}>;lastEvent:PublicEvent|null;
  audit:{version:number;actor:Side;intent:Action;hands:{w:string[];b:string[]};decks:{w:string[];b:string[]}}[];
  metrics:Record<string,number>;presence:{w:number;b:number};
  deletedParticipants?:Record<string,true>;
}
export function sideForUid(match:ServerMatch,uid:string):Side{
  if(match.players.w.uid===uid)return 'w';if(match.players.b.uid===uid)return 'b';throw new BattleError('NOT_PARTICIPANT',403);
}
// Internal settlement/deletion still needs sideForUid after access is revoked.
export function privateSideForUid(match:ServerMatch,uid:string):Side{
  const side=sideForUid(match,uid);
  if(match.players[side].bot||match.deletedParticipants?.[uid]===true)throw new BattleError('NOT_PARTICIPANT',403);
  return side;
}
// This allowlist is deliberate: authoritative objects are never encoded then redacted.
export function publicRules(s:RuleState):RuleState{
  return {fen:s.fen,pieceIds:[...s.pieceIds],movedPawns:[...s.movedPawns],phase:s.phase,
    mana:clone(s.mana),ownTurns:clone(s.ownTurns),handCounts:clone(s.handCounts),deckCounts:clone(s.deckCounts),drawCounts:clone(s.drawCounts),
    arsenals:clone(s.arsenals),used:clone(s.used),discarded:clone(s.discarded),pieceEffects:clone(s.pieceEffects),boardEffects:clone(s.boardEffects),
    modifiers:clone(s.modifiers),vows:clone(s.vows),special:clone(s.special),pending:clone(s.pending),terminal:clone(s.terminal),
    effectSequence:s.effectSequence,ply:s.ply,repetitions:clone(s.repetitions)};
}
export function privateKnowledge(s:PlayerKnowledgeState):PlayerKnowledgeState{
  return {knownUpcomingCards:[...s.knownUpcomingCards],radarObservations:s.radarObservations.map(o=>({queriedCardId:o.queriedCardId,result:o.result,
    observedTurn:o.observedTurn,opponentCumulativeDrawCountAtObservation:o.opponentCumulativeDrawCountAtObservation,stale:o.stale})),pendingCards:[...s.pendingCards]};
}
export function toPublicMatchState(m:ServerMatch):MatchProjection{
  const participants:Record<string,true>=Object.fromEntries(Object.values(m.players).filter(p=>!p.bot&&m.deletedParticipants?.[p.uid]!==true).map(p=>[p.uid,true as const]));
  return {matchId:m.matchId,protocolVersion:PROTOCOL,rulesetVersion:RULESET_VERSION,stateVersion:m.stateVersion,participants,players:clone(m.players),
    rulesJson:JSON.stringify(publicRules(m.battle.rules)),clock:clone(m.clock),result:clone(m.result),settlementStatus:m.settlementStatus,
    rated:m.rated,createdAt:m.createdAt,lastEvent:clone(m.lastEvent)};
}
export function toPlayerPrivateState(m:ServerMatch,uid:string):PrivateProjection{
  const side=privateSideForUid(m,uid);
  return {stateVersion:m.stateVersion,viewer:side,handJson:JSON.stringify([...m.battle.hidden.hands[side]]),knowledgeJson:JSON.stringify(privateKnowledge(m.battle.hidden.knowledge[side]))};
}
export function reconnectSnapshot(m:ServerMatch,uid:string){
  sideForUid(m,uid);return {ok:true,matchId:m.matchId,status:m.result?'finished':'active',view:{public:toPublicMatchState(m),private:toPlayerPrivateState(m,uid)}};
}
export interface BattleRolloutConfig {
  configVersion:number;v1MatchmakingEnabled:boolean;legacyNewMatchesEnabled:boolean;legacyForceUpdateEnabled:boolean;
  forceUpdatePlatforms:Platform[];v1StoreReleaseReadyAndroid:boolean;v1StoreReleaseReadyIos:boolean;
  minV1ClientBuildAndroid:number;minV1ClientBuildIos:number;maintenanceMode:boolean;v1BotFillTimeoutMs:number;
}
export const LEGACY_ONLY:Readonly<BattleRolloutConfig>=Object.freeze({configVersion:1,v1MatchmakingEnabled:false,legacyNewMatchesEnabled:true,
  legacyForceUpdateEnabled:false,forceUpdatePlatforms:[],v1StoreReleaseReadyAndroid:false,v1StoreReleaseReadyIos:false,
  minV1ClientBuildAndroid:17,minV1ClientBuildIos:17,maintenanceMode:false,v1BotFillTimeoutMs:30_000});
export function validateRollout(value:unknown):BattleRolloutConfig{
  const c=requireRecord(value);exactKeys(c,Object.keys(LEGACY_ONLY));
  for(const key of ['v1MatchmakingEnabled','legacyNewMatchesEnabled','legacyForceUpdateEnabled','v1StoreReleaseReadyAndroid','v1StoreReleaseReadyIos','maintenanceMode'])if(typeof c[key]!=='boolean')throw new BattleError('INVALID_ROLLOUT_CONFIG',400);
  for(const key of ['configVersion','minV1ClientBuildAndroid','minV1ClientBuildIos','v1BotFillTimeoutMs'])if(!Number.isSafeInteger(c[key])||Number(c[key])<1)throw new BattleError('INVALID_ROLLOUT_CONFIG',400);
  if(Number(c.v1BotFillTimeoutMs)<10_000||Number(c.v1BotFillTimeoutMs)>300_000||!Array.isArray(c.forceUpdatePlatforms)||new Set(c.forceUpdatePlatforms).size!==c.forceUpdatePlatforms.length||c.forceUpdatePlatforms.some(v=>v!=='android'&&v!=='ios'))throw new BattleError('INVALID_ROLLOUT_CONFIG',400);
  if(c.legacyForceUpdateEnabled&&(!c.v1MatchmakingEnabled||c.forceUpdatePlatforms.length===0||c.forceUpdatePlatforms.some(p=>p==='android'?!c.v1StoreReleaseReadyAndroid:!c.v1StoreReleaseReadyIos)))throw new BattleError('UNSAFE_ROLLOUT_CONFIG',400);
  if(!c.v1MatchmakingEnabled&&!c.legacyNewMatchesEnabled&&!c.maintenanceMode)throw new BattleError('UNSAFE_ROLLOUT_CONFIG',400);
  if(!c.legacyNewMatchesEnabled&&!c.maintenanceMode&&(!c.legacyForceUpdateEnabled||c.forceUpdatePlatforms.length!==2))throw new BattleError('UNSAFE_ROLLOUT_CONFIG',400);
  return clone(c) as unknown as BattleRolloutConfig;
}
export function requireClient(value:unknown,c:BattleRolloutConfig,protocol:typeof PROTOCOL=PROTOCOL):{platform:Platform;build:number}{
  const r=requireRecord(value);exactKeys(r,['platform','build','protocolVersion']);
  if(r.protocolVersion!==protocol)throw new BattleError('INCOMPATIBLE_PROTOCOL',400);
  if((r.platform!=='android'&&r.platform!=='ios')||!Number.isSafeInteger(r.build))throw new BattleError('INVALID_CLIENT',400);
  const min=r.platform==='android'?c.minV1ClientBuildAndroid:c.minV1ClientBuildIos;
  if(Number(r.build)<min)throw new BattleError('UPDATE_REQUIRED',426);
  return {platform:r.platform,build:Number(r.build)};
}
