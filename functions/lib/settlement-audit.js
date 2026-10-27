'use strict';
const {createHash}=require('node:crypto');
const record=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);

// Diagnostic only: missing ledger evidence must never authorize a second reward.
function auditSettlements(root){
  if(!record(root)||!record(root.rankedState)||!record(root.rankedState.matches)||!record(root.users)){
    throw new Error('A root snapshot containing rankedState.matches and users is required.');
  }
  const findings=[];
  for(const [id,match] of Object.entries(root.rankedState.matches)){
    if(!record(match)||!record(match.result))continue;
    const issues=[],blockers=[];
    if(!/^(rm|fm)_[a-f0-9]{32}$/.test(id)||match.matchId!==id)blockers.push('invalid-match-id');
    if(!['finished','cancelled'].includes(match.status))blockers.push('invalid-terminal-status');
    if(!['W','B','draw'].includes(match.result.winner))blockers.push('invalid-winner');
    if(!Number.isSafeInteger(match.result.finishedAt)||match.result.finishedAt<=0)blockers.push('invalid-finish-time');
    if(!['ranked','friendly'].includes(match.mode))blockers.push('unknown-mode');
    const uids=['W','B'].map(color=>match.players?.[color]?.uid);
    if(uids.some(uid=>typeof uid!=='string'||!uid)||uids[0]===uids[1])blockers.push('invalid-players');
    if(match.settlementStatus!=='complete')issues.push('completion-marker');
    for(const [index,uid] of uids.entries()){
      if(typeof uid!=='string'||!uid)continue;
      const color=index===0?'W':'B';
      if(match.participants?.[uid]!==true||match.colors?.[uid]!==color)blockers.push(`${color}:participant-mismatch`);
      const profile=root.users[uid];
      if(!record(profile))blockers.push(`${color}:missing-profile`);
      if(match.mode!=='friendly'){
        const key=createHash('sha256').update(uid+'|'+id).digest('hex').slice(0,48);
        const ledger=profile?.serverProgress?.rankedSettlements?.[key];
        const outcome=match.result.type==='cancelled'?'cancelled':match.result.winner==='draw'?'draw':match.result.winner===color?'win':'loss';
        if(!record(ledger))blockers.push(`${color}:missing-reward-ledger`);
        else if(ledger.matchId!==id||ledger.outcome!==outcome)blockers.push(`${color}:reward-ledger-mismatch`);
      }
      for(const [branch,label] of [['matchHistory','history'],['rankedReplays','replay'],['rankedMatchViews','view']]){
        const entry=root[branch]?.[uid]?.[id];
        if(!record(entry)||entry.matchId!==id||entry.result?.winner!==match.result.winner||entry.result?.finishedAt!==match.result.finishedAt||
          (branch==='rankedMatchViews'&&entry.status!==match.status)){
          issues.push(`${color}:${label}`);
        }
      }
      if(root.rankedState.activeByUser?.[uid]===id)issues.push(`${color}:active-pointer`);
      const presence=root.rankedPlayers?.[uid];
      if(presence?.matchId===id&&presence.status!==match.status)issues.push(`${color}:presence`);
    }
    findings.push({matchId:id,classification:blockers.length?'manual-review':issues.length?'publication-review':'consistent-in-snapshot',issues,blockers});
  }
  return {readOnly:true,automaticRepairAllowed:false,checked:findings.length,findings};
}
module.exports={auditSettlements};
