'use strict';

const crypto=require('node:crypto');

const DAY_MS=24*60*60*1000;
const SERVER_SCHEMA_VERSION=3;
const SEASON_EPOCH_MS=Date.UTC(2026,4,1);
const SEASON_LENGTH_MS=30*DAY_MS;
const DAILY_REWARDS=Object.freeze([200,300,450,600,800,1000,1500]);
const BALANCE_FIELDS=new Set(['gold','gems']);

function digest(value){
  return crypto.createHash('sha256').update(String(value)).digest('hex');
}
function isRecord(value){
  return value!==null&&typeof value==='object'&&!Array.isArray(value);
}
function safeInteger(value,fallback){
  const number=Number(value);
  return Number.isSafeInteger(number)&&number>=0?number:Number(fallback||0);
}
function utcDayOrdinal(timestamp){
  return Math.floor(Number(timestamp)/DAY_MS);
}
function utcDayKey(timestamp){
  return new Date(utcDayOrdinal(timestamp)*DAY_MS).toISOString().slice(0,10);
}
function utcWeekKey(timestamp){
  return 'w'+Math.floor((utcDayOrdinal(timestamp)+3)/7);
}
function seasonNumber(timestamp){
  return Math.max(1,Math.floor((Number(timestamp)-SEASON_EPOCH_MS)/SEASON_LENGTH_MS)+1);
}
function seasonBounds(season){
  const number=Math.max(1,Math.floor(Number(season)||1)),start=SEASON_EPOCH_MS+(number-1)*SEASON_LENGTH_MS;
  return {seasonNumber:number,startAt:start,endAt:start+SEASON_LENGTH_MS};
}
function periodSnapshot(timestamp){
  const at=Number(timestamp);
  const season=seasonBounds(seasonNumber(at));
  return {
    serverTime:at,
    dayKey:utcDayKey(at),
    weekKey:utcWeekKey(at),
    seasonId:'s'+season.seasonNumber,
    seasonNumber:season.seasonNumber,
    seasonStartAt:season.startAt,
    seasonEndAt:season.endAt
  };
}
function normalizeSeasonRecord(profile,timestamp){
  if(!isRecord(profile))return false;
  const at=Number(timestamp),periods=periodSnapshot(at),currentSeason=periods.seasonNumber,raw=isRecord(profile.serverSeason)?profile.serverSeason:{},rawNumber=Number(raw.number),hasValidNumber=Number.isSafeInteger(rawNumber)&&rawNumber>0;
  let normalized;
  if(!hasValidNumber){
    const bounds=seasonBounds(currentSeason);
    normalized=Object.assign({},raw,{number:currentSeason,seasonId:periods.seasonId,peakTrophies:Math.max(safeInteger(raw.peakTrophies,0),safeInteger(profile.trophies,0)),startedAt:bounds.startAt,claimed:isRecord(raw.claimed)?raw.claimed:{}});
  }else if(rawNumber>currentSeason){
    // A future season can only come from stale or tampered client data. Do not
    // let its claims or peak score become spendable in the current season.
    normalized={number:currentSeason,seasonId:periods.seasonId,peakTrophies:0,startedAt:periods.seasonStartAt,claimed:{}};
  }else{
    const bounds=seasonBounds(rawNumber);
    normalized=Object.assign({},raw,{number:rawNumber,seasonId:'s'+rawNumber,peakTrophies:safeInteger(raw.peakTrophies,0),startedAt:Number.isSafeInteger(Number(raw.startedAt))&&Number(raw.startedAt)>0?Number(raw.startedAt):bounds.startAt,claimed:isRecord(raw.claimed)?raw.claimed:{}});
  }
  const changed=JSON.stringify(profile.serverSeason||null)!==JSON.stringify(normalized);
  profile.serverSeason=normalized;
  return changed;
}
function economyEvidence(profile){
  const economy=profile.serverEconomy;
  if(economy==null)return {};
  if(!isRecord(economy))throw new TypeError('Economy receipt evidence is invalid.');
  for(const field of ['claims','ledger','purchases']){
    if(economy[field]!=null&&!isRecord(economy[field]))throw new TypeError('Economy receipt evidence is invalid.');
  }
  return economy;
}
function ensureEconomy(profile){
  const economy=economyEvidence(profile);
  profile.serverEconomy=economy;
  economy.schemaVersion=SERVER_SCHEMA_VERSION;
  if(!isRecord(economy.claims))economy.claims={};
  if(!isRecord(economy.ledger))economy.ledger={};
  if(!isRecord(economy.purchases))economy.purchases={};
  if(!isRecord(economy.daily))economy.daily={};
  return economy;
}
function purchaseTransactionId(uid,sourceType,sourceId,currency){
  return 'sp_'+digest([uid,sourceType,sourceId,currency].join('|')).slice(0,40);
}
function applySoftPurchase(profile,options){
  if(!isRecord(profile))throw new TypeError('Profile is required.');
  const uid=String(options.uid||''),sourceType=String(options.sourceType||'soft_purchase'),sourceId=String(options.sourceId||'');
  const itemType=String(options.itemType||''),itemId=String(options.itemId||''),currency=String(options.currency||''),price=Number(options.price),at=Number(options.at);
  if(!uid||!sourceId||!itemType||!itemId||!BALANCE_FIELDS.has(currency)||!Number.isSafeInteger(price)||price<=0||price>1000000||!Number.isSafeInteger(at)||at<=0)throw new TypeError('Purchase source is invalid.');
  const evidence=economyEvidence(profile),idempotencyKey=sourceClaimKey(uid,sourceType,sourceId),existing=evidence.purchases?.[idempotencyKey];
  if(existing!=null&&!isRecord(existing))throw new TypeError('Purchase receipt evidence is invalid.');
  const transactionId=purchaseTransactionId(uid,sourceType,sourceId,currency);
  // A surviving debit is not permission to charge again after partial receipt loss.
  if(existing==null&&Object.hasOwn(evidence.ledger||{},transactionId))throw new TypeError('Purchase receipt evidence is incomplete.');
  const economy=ensureEconomy(profile);
  if(isRecord(existing)){
    return {purchased:false,idempotent:true,idempotencyKey,transactionId:existing.transactionId,outcome:isRecord(existing.outcome)?existing.outcome:{},balances:{gold:safeInteger(profile.gold,0),gems:safeInteger(profile.gems,0)}};
  }
  if(typeof options.isOwned==='function'&&options.isOwned(profile)===true){
    return {purchased:false,idempotent:false,error:'already-owned',balances:{gold:safeInteger(profile.gold,0),gems:safeInteger(profile.gems,0)}};
  }
  const previousBalance=safeInteger(profile[currency],0);
  if(previousBalance<price)return {purchased:false,idempotent:false,error:'insufficient-balance',currency,price,balances:{gold:safeInteger(profile.gold,0),gems:safeInteger(profile.gems,0)}};
  const newBalance=previousBalance-price;
  profile[currency]=newBalance;
  const outcome=typeof options.grant==='function'?(options.grant(profile)||{}):{};
  economy.ledger[transactionId]={
    transactionId,idempotencyKey,uid,sourceType,sourceId,rewardType:currency,amount:-price,
    previousBalance,newBalance,createdAt:at,serverVersion:SERVER_SCHEMA_VERSION,itemType,itemId
  };
  economy.purchases[idempotencyKey]={
    idempotencyKey,transactionId,uid,sourceType,sourceId,itemType,itemId,currency,price,
    outcome,purchasedAt:at,serverVersion:SERVER_SCHEMA_VERSION
  };
  profile.serverSchemaVersion=SERVER_SCHEMA_VERSION;
  profile.updatedAt=at;
  return {purchased:true,idempotent:false,idempotencyKey,transactionId,outcome,balances:{gold:safeInteger(profile.gold,0),gems:safeInteger(profile.gems,0)}};
}
function rewardEntries(reward){
  if(!isRecord(reward))throw new TypeError('Reward must be an object.');
  const entries=[];
  Object.keys(reward).forEach(function(type){
    if(!BALANCE_FIELDS.has(type))throw new TypeError('Unsupported reward type: '+type);
    const amount=Number(reward[type]);
    if(!Number.isSafeInteger(amount)||amount<=0||amount>1000000)throw new TypeError('Invalid reward amount.');
    entries.push([type,amount]);
  });
  if(!entries.length)throw new TypeError('Reward cannot be empty.');
  return entries;
}
function sourceClaimKey(uid,sourceType,sourceId){
  return digest([uid,sourceType,sourceId].join('|')).slice(0,48);
}
function rewardTransactionId(uid,sourceType,sourceId,rewardType){
  return 'rw_'+digest([uid,sourceType,sourceId,rewardType].join('|')).slice(0,40);
}
function applyRewardClaim(profile,options){
  if(!isRecord(profile))throw new TypeError('Profile is required.');
  const uid=String(options.uid||'');
  const sourceType=String(options.sourceType||'');
  const sourceId=String(options.sourceId||'');
  const at=Number(options.at);
  if(!uid||!sourceType||!sourceId||!Number.isSafeInteger(at)||at<=0)throw new TypeError('Reward source is invalid.');
  const entries=rewardEntries(options.reward);
  const evidence=economyEvidence(profile);
  const idempotencyKey=sourceClaimKey(uid,sourceType,sourceId);
  const existing=evidence.claims?.[idempotencyKey];
  if(existing!=null&&!isRecord(existing))throw new TypeError('Reward receipt evidence is invalid.');
  // Preserve orphaned credits for reconciliation; never mint the same source again.
  if(existing==null&&entries.some(([type])=>Object.hasOwn(evidence.ledger||{},rewardTransactionId(uid,sourceType,sourceId,type))))throw new TypeError('Reward receipt evidence is incomplete.');
  const economy=ensureEconomy(profile);
  if(isRecord(existing)){
    return {
      granted:false,
      idempotent:true,
      idempotencyKey,
      transactionIds:Array.isArray(existing.transactionIds)?existing.transactionIds.slice():[],
      reward:isRecord(existing.reward)?Object.assign({},existing.reward):{},
      balances:{gold:safeInteger(profile.gold,0),gems:safeInteger(profile.gems,0)}
    };
  }

  const transactionIds=[];
  const reward={};
  entries.forEach(function(entry){
    const rewardType=entry[0],amount=entry[1];
    const previousBalance=safeInteger(profile[rewardType],0);
    const newBalance=previousBalance+amount;
    if(!Number.isSafeInteger(newBalance))throw new TypeError('Balance overflow.');
    const transactionId=rewardTransactionId(uid,sourceType,sourceId,rewardType);
    profile[rewardType]=newBalance;
    economy.ledger[transactionId]={
      transactionId,
      idempotencyKey,
      uid,
      sourceType,
      sourceId,
      rewardType,
      amount,
      previousBalance,
      newBalance,
      createdAt:at,
      serverVersion:SERVER_SCHEMA_VERSION
    };
    if(options.matchId)economy.ledger[transactionId].matchId=String(options.matchId);
    transactionIds.push(transactionId);
    reward[rewardType]=amount;
  });
  economy.claims[idempotencyKey]={
    idempotencyKey,
    sourceType,
    sourceId,
    matchId:options.matchId?String(options.matchId):null,
    reward,
    transactionIds,
    claimedAt:at,
    serverVersion:SERVER_SCHEMA_VERSION
  };
  profile.serverSchemaVersion=SERVER_SCHEMA_VERSION;
  profile.updatedAt=at;
  return {
    granted:true,
    idempotent:false,
    idempotencyKey,
    transactionIds,
    reward,
    balances:{gold:safeInteger(profile.gold,0),gems:safeInteger(profile.gems,0)}
  };
}
function dailyState(profile,timestamp){
  const economy=ensureEconomy(profile);
  const daily=economy.daily;
  if(!Number.isSafeInteger(daily.lastClaimDay)){
    const inventory=isRecord(profile.inventory)?profile.inventory:{};
    const legacyLast=safeInteger(inventory.lastDailyReward,0);
    if(legacyLast>0)daily.lastClaimDay=utcDayOrdinal(legacyLast);
    daily.streak=safeInteger(inventory.dailyStreak,0);
  }
  daily.streak=safeInteger(daily.streak,0);
  const today=utcDayOrdinal(timestamp);
  const nextStreak=(daily.lastClaimDay===today||daily.lastClaimDay===today-1)?daily.streak:0;
  return {
    serverTime:Number(timestamp),
    canClaim:daily.lastClaimDay!==today,
    streak:daily.streak,
    lastClaimDay:Number.isSafeInteger(daily.lastClaimDay)?daily.lastClaimDay:null,
    lastClaimAt:safeInteger(daily.lastClaimAt,0),
    nextClaimAt:(today+1)*DAY_MS,
    nextReward:{gold:DAILY_REWARDS[nextStreak%DAILY_REWARDS.length],gems:0}
  };
}
function applyDailyRewardClaim(profile,uid,timestamp){
  const at=Number(timestamp),today=utcDayOrdinal(at),economy=ensureEconomy(profile);
  const before=dailyState(profile,at);
  const sourceId=utcDayKey(at);
  if(!before.canClaim){
    return {
      granted:false,
      idempotent:true,
      reward:{},
      balances:{gold:safeInteger(profile.gold,0),gems:safeInteger(profile.gems,0)},
      daily:before,
      periods:periodSnapshot(at)
    };
  }
  const continuing=before.lastClaimDay===today-1;
  const streakBefore=continuing?before.streak:0;
  const amount=DAILY_REWARDS[streakBefore%DAILY_REWARDS.length];
  const result=applyRewardClaim(profile,{uid,sourceType:'daily_reward',sourceId,reward:{gold:amount},at});
  if(!result.granted){
    result.daily=dailyState(profile,at);
    result.periods=periodSnapshot(at);
    return result;
  }
  economy.daily.lastClaimDay=today;
  economy.daily.lastClaimAt=at;
  economy.daily.streak=streakBefore+1;
  if(!isRecord(profile.inventory))profile.inventory={};
  profile.inventory.lastDailyReward=at;
  profile.inventory.dailyStreak=economy.daily.streak;
  result.daily={
    serverTime:at,canClaim:false,streak:economy.daily.streak,lastClaimDay:today,lastClaimAt:at,
    nextClaimAt:(today+1)*DAY_MS,
    nextReward:{gold:DAILY_REWARDS[economy.daily.streak%DAILY_REWARDS.length],gems:0}
  };
  result.periods=periodSnapshot(at);
  return result;
}
function economySnapshot(profile,timestamp){
  return {
    gold:safeInteger(profile&&profile.gold,0),
    gems:safeInteger(profile&&profile.gems,0),
    trophies:safeInteger(profile&&profile.trophies,0),
    xp:safeInteger(profile&&profile.xp,0),
    lvl:Math.max(1,safeInteger(profile&&profile.lvl,1)),
    daily:dailyState(profile,timestamp),
    periods:periodSnapshot(timestamp),
    serverSchemaVersion:safeInteger(profile&&profile.serverSchemaVersion,SERVER_SCHEMA_VERSION)
  };
}

module.exports={
  DAILY_REWARDS,
  SERVER_SCHEMA_VERSION,
  applyDailyRewardClaim,
  applyRewardClaim,
  applySoftPurchase,
  economySnapshot,
  normalizeSeasonRecord,
  periodSnapshot,
  seasonNumber,
  seasonBounds,
  sourceClaimKey,
  utcDayKey,
  utcDayOrdinal,
  utcWeekKey
};
