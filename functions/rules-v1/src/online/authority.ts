import {createHash,randomInt} from 'node:crypto';
import {newBattle,applyAuthoritative,playerView} from '../authoritative.js';
import {legalActions,legalRuleMoves,chooseBotAction} from '../core.js';
import {squares,sideOf,inCheck} from '../board.js';
import {actionKey,clone,validateDeck,type CardId,type Side} from '../model.js';
import {BattleError,PROTOCOL,RULESET_VERSION,INITIAL_CLOCK_MS,INCREMENT_MS,reconnectSnapshot,sideForUid,privateSideForUid,
  type ActionRequest,type MatchResult,type Participant,type ServerMatch} from './protocol.js';

export function secureShuffle(deck:readonly CardId[]):CardId[]{
  validateDeck(deck);const shuffled=[...deck];
  for(let i=shuffled.length-1;i>0;i--){const j=randomInt(i+1);[shuffled[i],shuffled[j]]=[shuffled[j]!,shuffled[i]!];}
  return shuffled;
}
export function createServerMatch(matchId:string,white:Participant,black:Participant,whiteDeck:readonly CardId[],blackDeck:readonly CardId[],at:number,rated=true):ServerMatch{
  if(white.uid===black.uid)throw new BattleError('INVALID_PARTICIPANTS',400);
  const battle=newBattle(secureShuffle(whiteDeck),secureShuffle(blackDeck));
  return {matchId,protocolVersion:PROTOCOL,rulesetVersion:RULESET_VERSION,stateVersion:0,players:{w:clone(white),b:clone(black)},battle,
    clock:{w:INITIAL_CLOCK_MS,b:INITIAL_CLOCK_MS,activeSide:'w',startedAt:at,incrementMs:INCREMENT_MS},result:null,settlementStatus:'none',
    rated:rated&&!white.bot&&!black.bot,createdAt:at,actions:{},lastEvent:null,audit:[{version:0,actor:'w',intent:{type:'pass'},hands:clone(battle.hidden.hands),decks:clone(battle.hidden.decks)}],metrics:{},presence:{w:at,b:at}};
}
export function chargeClock(m:ServerMatch,at:number):{w:number;b:number}{
  const result={w:m.clock.w,b:m.clock.b};if(!m.result)result[m.clock.activeSide]=Math.max(0,result[m.clock.activeSide]-Math.max(0,at-m.clock.startedAt));return result;
}
export function finishMatch(m:ServerMatch,result:MatchResult):ServerMatch{
  if(m.result)return clone(m);
  const finishedAt=Math.max(result.finishedAt,m.clock.startedAt);
  const next=clone(m);next.result={...clone(result),finishedAt};next.battle.rules.phase='terminal';next.battle.rules.pending=null;
  next.battle.hidden.knowledge.w.pendingCards=[];next.battle.hidden.knowledge.b.pendingCards=[];
  next.clock={...next.clock,...chargeClock(m,finishedAt),startedAt:finishedAt};
  next.settlementStatus='pending';next.stateVersion++;return next;
}
export function expireClock(m:ServerMatch,at:number):ServerMatch{
  if(m.result)return m;const charged=chargeClock(m,at);
  if(charged[m.clock.activeSide]>0)return m;
  const next=finishMatch(m,{reason:'timeout',winner:m.clock.activeSide==='w'?'b':'w',finishedAt:at});
  next.clock={...next.clock,...charged,startedAt:next.result!.finishedAt};return next;
}
export function intentDigest(r:ActionRequest):string{
  return createHash('sha256').update(JSON.stringify([r.protocolVersion,r.matchId,r.expectedStateVersion,actionKey(r.intent)])).digest('hex');
}
function metric(m:ServerMatch,key:string,amount=1):void{m.metrics[key]=(m.metrics[key]??0)+amount;}
export function commitAction(m:ServerMatch,uid:string,r:ActionRequest,at:number):{match:ServerMatch;duplicate:boolean;acceptedVersion:number}{
  const actor=sideForUid(m,uid);
  if(m.protocolVersion!==PROTOCOL||m.rulesetVersion!==RULESET_VERSION||r.protocolVersion!==PROTOCOL||r.matchId!==m.matchId)throw new BattleError('INCOMPATIBLE_PROTOCOL',400);
  const digest=intentDigest(r),previous=m.actions[r.actionId];
  if(previous){if(previous.uid!==uid||previous.digest!==digest)throw new BattleError('ACTION_ID_CONFLICT');return {match:m,duplicate:true,acceptedVersion:previous.stateVersion};}
  // The version anchor makes evicted IDs unreusable; retained acknowledgements are bounded.
  if(!r.actionId.startsWith(`a${r.expectedStateVersion}_`))throw new BattleError('INVALID_ACTION',400);
  if(m.result)throw new BattleError('MATCH_TERMINAL');
  if(r.expectedStateVersion!==m.stateVersion)throw new BattleError('STALE_STATE');
  const committedAt=Math.max(at,m.clock.startedAt);
  if(expireClock(m,committedAt)!==m)throw new BattleError('MATCH_TIMEOUT');
  const moving=m.battle.rules.fen.split(' ')[1] as Side;
  if(actor!==moving)throw new BattleError('NOT_YOUR_TURN');
  const view=playerView(m.battle,actor);
  if(!legalActions(view).some(a=>actionKey(a)===actionKey(r.intent)))throw new BattleError('INVALID_ACTION',400);
  let battle;try{battle=applyAuthoritative(m.battle,r.intent);}catch{throw new BattleError('INVALID_ACTION',400);}
  const next=clone(m),charged=chargeClock(m,committedAt),newSide=battle.rules.fen.split(' ')[1] as Side;
  next.battle=battle;next.stateVersion++;
  if(r.intent.type==='move'&&newSide!==moving)charged[actor]+=INCREMENT_MS;
  next.clock={...next.clock,...charged,activeSide:newSide,startedAt:committedAt};next.presence[actor]=committedAt;
  next.lastEvent={stateVersion:next.stateVersion,actor,type:r.intent.type};
  if(r.intent.type==='play'){
    next.lastEvent.card=r.intent.card;if(r.intent.target!==undefined)next.lastEvent.target=r.intent.target;
    metric(next,'play:'+r.intent.card);metric(next,'turn:'+m.battle.rules.ply);metric(next,'manaSpent',m.battle.rules.mana[actor]-battle.rules.mana[actor]);
    metric(next,'manaBefore:'+m.battle.rules.mana[actor]);metric(next,'manaAfter:'+battle.rules.mana[actor]);
    if(m.battle.rules.pieceEffects.some(e=>e.type==='freeze'&&e.owner!==actor)&&r.intent.card==='purify')metric(next,'freezePurify');
    if(m.battle.rules.modifiers.some(x=>x.type==='discount'&&x.responseSide===actor)&&r.intent.card==='freeze')metric(next,'contractFreeze');
    if(m.battle.rules.modifiers.some(x=>x.type==='discount'&&x.responseSide===actor)&&r.intent.card==='board_seal')metric(next,'contractBoardSeal');
  }
  if(r.intent.type==='discard'){next.lastEvent.card=r.intent.card;metric(next,'discard:'+r.intent.card);}
  if(r.intent.type==='move')next.lastEvent.uci=r.intent.uci;
  if(r.intent.type==='move'){
    const enemy=actor==='w'?'b':'w',prefix='player:'+actor+':';
    const count=(fen:string)=>squares(fen).filter(p=>p&&sideOf(p)===enemy).length;
    metric(next,prefix+'moveCount');
    metric(next,prefix+'captures',Math.max(0,count(m.battle.rules.fen)-count(battle.rules.fen)));
    if(inCheck(battle.rules.fen,enemy))metric(next,prefix+'checks');
    if(r.intent.uci.length===5)metric(next,prefix+'promotions');
  }
  const beforeMines=m.battle.rules.boardEffects.filter(e=>e.type==='mine'),afterMines=battle.rules.boardEffects.filter(e=>e.type==='mine');
  if(r.intent.type==='move'){
    metric(next,'persistentMinePly',beforeMines.length);
    const seals=m.battle.rules.boardEffects.filter(e=>e.type==='board_seal'&&e.owner!==actor);
    if(seals.length){const without=clone(m.battle.rules);without.boardEffects=without.boardEffects.filter(e=>!seals.some(s=>s.id===e.id));const allowed=new Set(legalRuleMoves(m.battle.rules,actor,m.battle.rules.special).map(a=>a.uci));const blocked=legalRuleMoves(without,actor,m.battle.rules.special).filter(a=>!allowed.has(a.uci));metric(next,'boardSealBlockedMoves',blocked.length);}
  }
  const removed=beforeMines.filter(e=>!afterMines.some(a=>a.id===e.id)).length;
  if(removed)metric(next,r.intent.type==='play'?'mineRemoved':'mineTrigger',removed);
  const beforeDebuffs=m.battle.rules.pieceEffects.filter(e=>e.type==='mine_debuff'),afterDebuffs=battle.rules.pieceEffects.filter(e=>e.type==='mine_debuff');
  if(beforeDebuffs.length)metric(next,'mineDebuffPly',r.intent.type==='move'?beforeDebuffs.length:0);
  metric(next,'mineDebuffConsumed',beforeDebuffs.filter(e=>!afterDebuffs.some(a=>a.id===e.id)).length);
  if(battle.rules.terminal){const terminal=battle.rules.terminal;next.result={reason:terminal.reason,winner:terminal.winner,finishedAt:committedAt};next.settlementStatus='pending';
    if(terminal.mateByRestriction)metric(next,'mate_by_restriction');if(terminal.mateBySpecialMove)metric(next,'mate_by_special_move');if(terminal.stalemateByRestriction)metric(next,'stalemate_by_restriction');}
  next.actions[r.actionId]={uid,digest,stateVersion:next.stateVersion};
  const keys=Object.keys(next.actions);for(const key of keys.slice(0,Math.max(0,keys.length-512)))delete next.actions[key];
  next.audit.push({version:next.stateVersion,actor,intent:clone(r.intent),hands:clone(battle.hidden.hands),decks:clone(battle.hidden.decks)});
  if(next.audit.length>256)next.audit.splice(0,next.audit.length-256);
  return {match:next,duplicate:false,acceptedVersion:next.stateVersion};
}
export function sanitizedActionResponse(m:ServerMatch,uid:string,duplicate:boolean,acceptedVersion:number){
  return {...reconnectSnapshot(m,uid),duplicate,acceptedVersion};
}
export function botPlannerInput(m:ServerMatch,side:Side){return playerView(m.battle,side);}
export function botIntent(m:ServerMatch,side:Side){return chooseBotAction(botPlannerInput(m,side));}
export function postMatchAnalysis(m:ServerMatch,uid:string):{protocolVersion:typeof PROTOCOL;stateVersion:number;truncated:boolean;history:ServerMatch['audit']}|null{
  privateSideForUid(m,uid);if(!m.result||m.settlementStatus!=='complete')return null;
  return {protocolVersion:PROTOCOL,stateVersion:m.stateVersion,truncated:(m.audit[0]?.version??0)!==0,history:clone(m.audit)};
}
