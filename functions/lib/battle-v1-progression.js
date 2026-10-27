'use strict';

const {CARDS,STARTER}=require('../rules-v1/dist/src/model.js');
const {PROTOCOL,sideForUid}=require('../rules-v1/dist/src/online/protocol.js');
const {sourceClaimKey,utcDayKey}=require('./economy');
const UNLOCK_PATH=Object.freeze([
  ['mine',1],['break_seal',2],['fog',3],['mana_sabotage',4],
  ['card_block',5],['rook_bend',6],['angry_n',8],['shadow_pass',9],
  ['hunt_vow',10],['watch_vow',12],['echo',13],['shadow_contract',15],
  ['fate_exchange',17],['board_seal',20]
].map(([card,matches])=>Object.freeze({card,matches})));
const safeCount=value=>Number.isSafeInteger(value)&&value>=0?value:0;
const record=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
const PLAYED_RESULT_REASONS=new Set(['checkmate','stalemate','seventy_five_moves','fivefold','resign']);
function verifiedEarlyProgress(profile,uid,at){
  const empty={welcomeClaimed:false,distinctDailyClaims:0};
  if(profile?.uid!==uid||!Number.isSafeInteger(at)||at<=0)return empty;
  const economy=profile.serverEconomy||{},days=new Set();let welcomeClaimed=false;
  for(const [key,claim] of Object.entries(record(economy.claims)?economy.claims:{})){
    if(!record(claim)||!['onboarding_reward','daily_reward'].includes(claim.sourceType))continue;
    const {sourceType,sourceId,claimedAt}=claim;
    if(!Number.isSafeInteger(claimedAt)||claimedAt<=0||claimedAt>at||
      key!==sourceClaimKey(uid,sourceType,sourceId)||claim.idempotencyKey!==key||
      !Number.isSafeInteger(claim.reward?.gold)||claim.reward.gold<=0||!Array.isArray(claim.transactionIds))continue;
    // A persisted claim and its owner-bound currency ledger must agree. Legacy
    // client streaks or onboarding booleans are deliberately not evidence.
    const credited=claim.transactionIds.some(id=>{
      const entry=economy.ledger?.[id];
      return record(entry)&&entry.transactionId===id&&entry.idempotencyKey===key&&entry.uid===uid&&
        entry.sourceType===sourceType&&entry.sourceId===sourceId&&entry.rewardType==='gold'&&
        entry.amount===claim.reward.gold&&entry.createdAt===claimedAt;
    });
    if(!credited)continue;
    if(sourceType==='onboarding_reward'&&sourceId==='v1')welcomeClaimed=true;
    if(sourceType==='daily_reward'&&sourceId===utcDayKey(claimedAt))days.add(sourceId);
  }
  return {welcomeClaimed,distinctDailyClaims:Math.min(3,days.size)};
}
function earlySummary(account){
  const early=account.competitiveProgression?.early;
  return {welcomeClaimed:early?.welcomeClaimed===true,distinctDailyClaims:Math.min(3,safeCount(early?.distinctDailyClaims))};
}
function tierRequirements(tier,matches,early){
  const anyOf=[{kind:'ranked_matches',current:matches,target:tier.matches}];
  if(tier.card==='mine')anyOf.push({kind:'welcome_claim',current:early.welcomeClaimed?1:0,target:1});
  if(tier.card==='break_seal'||tier.card==='fog')anyOf.push({kind:'daily_claim_days',current:early.distinctDailyClaims,target:tier.matches});
  return {anyOf};
}
function syncEarlyProgress(account,profile,uid,at){
  const early=verifiedEarlyProgress(profile,uid,at);
  account.competitiveProgression={...account.competitiveProgression,early};
  return early;
}
function reconcileEarlyCardOwnership(profile,uid,at){
  const early=verifiedEarlyProgress(profile,uid,at),unlocked=[];
  const due=[...(early.welcomeClaimed?['mine']:[]),...(early.distinctDailyClaims>=2?['break_seal']:[]),...(early.distinctDailyClaims>=3?['fog']:[])];
  if(due.length&&!record(profile.battleV1UnlockedCards))profile.battleV1UnlockedCards={};
  for(const card of due)if(profile.battleV1UnlockedCards[card]!==true){profile.battleV1UnlockedCards[card]=true;unlocked.push(card);}
  return {early,unlocked,changed:unlocked.length>0};
}
function progressionSummary(account){
  const matches=Math.min(20,safeCount(account.competitiveProgression?.meaningfulMatches));
  const early=earlySummary(account);
  const owned=new Set(Array.isArray(account.entitlements)?account.entitlements:STARTER);
  const path=UNLOCK_PATH.map(tier=>({...tier,owned:owned.has(tier.card),requirements:tierRequirements(tier,matches,early)}));
  const next=path.find(tier=>!tier.owned);
  return {version:2,meaningfulMatches:matches,targetMatches:20,early,nextUnlock:next?{...next}:null,path};
}
function reconcileCompetitiveProgression(account){
  const matches=Math.min(20,safeCount(account.competitiveProgression?.meaningfulMatches));
  const early=earlySummary(account);
  // Keep every valid earned/migrated entitlement; never replace the collection.
  const owned=new Set([...STARTER,...(Array.isArray(account.entitlements)?account.entitlements:[]).filter(id=>Object.hasOwn(CARDS,id))]);
  const unlocked=[];
  for(const tier of UNLOCK_PATH)if(tierRequirements(tier,matches,early).anyOf.some(condition=>condition.current>=condition.target)&&!owned.has(tier.card)){owned.add(tier.card);unlocked.push(tier.card);}
  account.entitlements=[...owned];
  account.competitiveProgression={version:2,meaningfulMatches:matches,early};
  return {...progressionSummary(account),unlocked};
}
function applyCompetitiveProgression(account,match,uid){
  const side=sideForUid(match,uid),result=match.result;
  // Clock-expired losses cannot farm unlocks; the participating opponent can.
  // Unknown/admin results fail closed. V1 has no separate connection/AFK reason.
  const playedResult=!!result&&(PLAYED_RESULT_REASONS.has(result.reason)||
    (result.reason==='timeout'&&result.winner===side));
  const eligible=match.protocolVersion===PROTOCOL&&match.rated===true&&playedResult&&
    !match.players.w.bot&&!match.players.b.bot&&
    safeCount(match.battle.rules.ply)>=12&&
    safeCount(match.metrics?.['player:'+side+':moveCount'])>=4;
  const current=Math.min(20,safeCount(account.competitiveProgression?.meaningfulMatches));
  account.competitiveProgression={...account.competitiveProgression,version:2,meaningfulMatches:eligible?Math.min(20,current+1):current};
  return {...reconcileCompetitiveProgression(account),qualified:eligible};
}
module.exports={UNLOCK_PATH,applyCompetitiveProgression,progressionSummary,reconcileCompetitiveProgression,
  verifiedEarlyProgress,syncEarlyProgress,reconcileEarlyCardOwnership};
