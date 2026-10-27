'use strict';
const {applyRankedSettlement}=require('./ranked');
const {BattleError,sideForUid}=require('../rules-v1/dist/src/online/protocol.js');
const {applyCompetitiveProgression,reconcileCompetitiveProgression}=require('./battle-v1-progression');
const MAX_V1_TROPHIES=1000000000;
function applyV1Rating(account,match,uid){
 if(match.protocolVersion!=='LUNO_BATTLE_V1'||!match.result)throw new BattleError('INVALID_SETTLEMENT');
 const side=sideForUid(match,uid),opponent=side==='w'?'b':'w';
 const outcome=match.result.reason==='protocol-upgrade'?'cancelled':match.result.winner===null?'draw':match.result.winner===side?'win':'loss';
 account.ratingSettlements=account.ratingSettlements||{};
 if(account.ratingSettlements[match.matchId])return account.ratingSettlements[match.matchId];
 const at=match.result.finishedAt;
 if(!match.rated){const result={protocolVersion:'LUNO_BATTLE_V1',matchId:match.matchId,outcome,rated:false,trophyDelta:0,newTrophies:account.rating,settledAt:at};account.ratingSettlements[match.matchId]=result;return result;}
 // Reuse the proven project rating formula on a SEPARATE V1 profile, never users/{uid}.
 const p=account.ratingProfile||{uid,trophies:account.rating,arenaIdx:0,gold:0,gems:0,lvl:1,xp:0,stats:{}};
 const settlement=applyRankedSettlement(p,{uid,matchId:match.matchId,outcome,opponentTrophies:match.ratingAtStart?.[opponent]??0,moveCount:match.battle.rules.ply,at,trophyCap:MAX_V1_TROPHIES});
 const games=Number.isSafeInteger(account.games)&&account.games>=0?account.games:0;
 account.ratingProfile=p;account.rating=p.trophies;account.games=games+(settlement.applied&&outcome!=='cancelled'?1:0);
 // A surviving inner receipt also proves this match was already committed.
 // Repair due ownership, but never count it twice if the outer receipt was lost.
 const progression=settlement.applied?applyCompetitiveProgression(account,match,uid):{...reconcileCompetitiveProgression(account),qualified:false};
 const result={...settlement,protocolVersion:'LUNO_BATTLE_V1',rated:true,progression};account.ratingSettlements[match.matchId]=result;return result;
}
module.exports={applyV1Rating,MAX_V1_TROPHIES};
