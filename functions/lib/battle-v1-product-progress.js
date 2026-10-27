'use strict';

const {PROTOCOL}=require('../rules-v1/dist/src/online/protocol');
const {arenaIndexForProfile}=require('./ranked');
const {MAX_V1_TROPHIES}=require('./battle-v1-rating');
const {periodSnapshot,seasonBounds,sourceClaimKey}=require('./economy');
const {SEASON_REWARDS}=require('./catalogs');

const PRODUCT_PROGRESS_FIELD='serverV1ProductProgress';
const VERSION=1;
const record=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
const integer=value=>Number.isSafeInteger(value)&&value>=0;
const trophies=value=>integer(value)&&value<=MAX_V1_TROPHIES;
const timestamp=value=>integer(value)&&value>0&&value<=8640000000000000;
function unavailable(){
  const error=new Error('Battle V1 product progress is unavailable.');
  error.code='battle-v1-product-progress-unavailable';error.status=503;return error;
}
function seasonRecord(number,peakTrophies){
  return {number,seasonId:'s'+number,peakTrophies,startedAt:seasonBounds(number).startAt};
}
function validSeason(value,currentSeason){
  return record(value)&&integer(value.number)&&value.number>=1&&value.number<=currentSeason&&
    value.seasonId==='s'+value.number&&trophies(value.peakTrophies)&&
    value.startedAt===seasonBounds(value.number).startAt;
}
function receiptProgress(receipt,matchId,at){
  if(!record(receipt)||receipt.matchId!==matchId||receipt.protocolVersion!==PROTOCOL||receipt.rated!==true||
    !timestamp(receipt.settledAt)||receipt.settledAt>at+60000||
    !['win','loss','draw'].includes(receipt.outcome))return null;
  const previous=receipt.previousTrophies??receipt.newTrophies-receipt.trophyDelta;
  if(!trophies(previous)||!trophies(receipt.newTrophies)||!Number.isSafeInteger(receipt.trophyDelta)||
    receipt.newTrophies-previous!==receipt.trophyDelta)return null;
  const number=periodSnapshot(receipt.settledAt).seasonNumber;
  return number<=periodSnapshot(at).seasonNumber?seasonRecord(number,Math.max(previous,receipt.newTrophies)):null;
}

function readBattleV1ProductProgress(profile,at){
  if(!record(profile)||!timestamp(at))throw unavailable();
  const value=profile[PRODUCT_PROGRESS_FIELD];
  if(value===undefined||value===null)return null;
  if(typeof profile.uid!=='string'||!profile.uid)throw unavailable();
  const currentSeason=periodSnapshot(at).seasonNumber;
  if(!record(value)||value.version!==VERSION||value.protocolVersion!==PROTOCOL||value.uid!==profile.uid||
    !integer(value.ratingRevision)||value.ratingRevision<1||!trophies(value.trophies)||
    value.arenaIdx!==arenaIndexForProfile({trophies:value.trophies})||
    !trophies(value.peakTrophies)||value.peakTrophies<value.trophies||
    !integer(value.seasonNumber)||value.seasonNumber<1||value.seasonNumber>currentSeason||
    !integer(value.rewardSeasonNumber)||value.rewardSeasonNumber<1||value.rewardSeasonNumber>value.seasonNumber||
    !record(value.seasons))throw unavailable();
  for(const [key,season] of Object.entries(value.seasons)){
    if(!validSeason(season,value.seasonNumber)||key!==season.seasonId)throw unavailable();
  }
  if(!value.seasons['s'+value.rewardSeasonNumber]||!value.seasons['s'+value.seasonNumber])throw unavailable();
  if(value.lastRewardSeason!==undefined&&
    (!integer(value.lastRewardSeason)||value.lastRewardSeason<1||value.lastRewardSeason>=value.rewardSeasonNumber||
      !SEASON_REWARDS.some(tier=>tier.tier===value.lastRewardTier)))throw unavailable();
  return value;
}

// Call only inside the users/{uid} transaction, after a committed V1 account settlement.
function projectBattleV1ProductProgress(profile,account,matchId,at){
  if(!record(profile)||!record(account)||!timestamp(at)||typeof matchId!=='string')throw unavailable();
  const uid=profile.uid,rank=account.ratingProfile,receipt=account.ratingSettlements?.[matchId];
  if(typeof uid!=='string'||!uid||account.migrationVersion!==1||
    (account.uid!==undefined&&account.uid!==uid)||
    (account.protocolVersion!==undefined&&account.protocolVersion!==PROTOCOL)||
    !integer(account.ratingRevision)||account.ratingRevision<1||!trophies(account.rating)||
    !record(rank)||rank.uid!==uid||rank.trophies!==account.rating||
    rank.arenaIdx!==arenaIndexForProfile({trophies:account.rating})||
    !record(receipt)||receipt.matchId!==matchId||receipt.protocolVersion!==PROTOCOL||receipt.rated!==true||
    !timestamp(receipt.settledAt)||receipt.settledAt>at+60000||
    !['win','loss','draw','cancelled'].includes(receipt.outcome))throw unavailable();
  if(receipt.outcome==='cancelled')return false;
  const settledSeason=receiptProgress(receipt,matchId,at);
  if(!settledSeason)throw unavailable();
  const currentSeason=periodSnapshot(at).seasonNumber;
  const stored=readBattleV1ProductProgress(profile,at);
  if(stored&&account.ratingRevision===stored.ratingRevision&&account.rating!==stored.trophies)throw unavailable();
  const sourceSeason=validSeason(rank.serverSeason,currentSeason)?rank.serverSeason:null;
  // A recovery may target an old match while reading a newer account revision.
  // Rebuild peaks from real committed receipts, never assign current rank to an old season.
  const earnedSeasons=Object.entries(account.ratingSettlements)
    .map(([id,value])=>receiptProgress(value,id,at)).filter(Boolean);
  if(sourceSeason)earnedSeasons.push(sourceSeason);
  const firstSeason=earnedSeasons.reduce((first,season)=>Math.min(first,season.number),settledSeason.number);
  const next=stored?structuredClone(stored):{
    version:VERSION,protocolVersion:PROTOCOL,uid,ratingRevision:account.ratingRevision,
    trophies:account.rating,arenaIdx:rank.arenaIdx,peakTrophies:account.rating,
    seasonNumber:settledSeason.number,rewardSeasonNumber:firstSeason,seasons:{}
  };
  if(account.ratingRevision>next.ratingRevision){
    next.ratingRevision=account.ratingRevision;next.trophies=account.rating;next.arenaIdx=rank.arenaIdx;
  }
  // Rank can fall after a newer loss. Peaks and season identity never regress.
  next.peakTrophies=Math.max(next.peakTrophies,account.rating);
  function mergeSeason(number,peak){
    const key='s'+number,old=next.seasons[key];
    next.seasons[key]=seasonRecord(number,Math.max(old?.peakTrophies||0,peak));
    next.seasonNumber=Math.max(next.seasonNumber,number);
  }
  for(const season of earnedSeasons){
    mergeSeason(season.number,season.peakTrophies);
    next.peakTrophies=Math.max(next.peakTrophies,season.peakTrophies);
  }
  if(JSON.stringify(stored)===JSON.stringify(next))return false;
  profile[PRODUCT_PROGRESS_FIELD]=next;
  return true;
}

function reconciledSeasonCursor(profile,progress,at){
  const earlier=Object.values(progress.seasons).filter(season=>season.number<progress.rewardSeasonNumber);
  const unpaid=earlier.filter(season=>profile.serverEconomy?.claims?.[
    sourceClaimKey(profile.uid,'season_reward','s'+season.number)]==null);
  if(!unpaid.length)return progress;
  const number=Math.min(...unpaid.map(season=>season.number));
  const next={...progress,rewardSeasonNumber:number};
  if(next.lastRewardSeason>=number){
    delete next.lastRewardSeason;delete next.lastRewardTier;
    const previous=earlier.filter(season=>season.number<number).sort((a,b)=>b.number-a.number)[0];
    if(previous){next.lastRewardSeason=previous.number;next.lastRewardTier=paidSeasonTier(profile,previous.number,at).tier;}
  }
  return next;
}
function repairBattleV1ProductSeasonCursor(profile,at){
  const progress=readBattleV1ProductProgress(profile,at);
  if(!progress)return false;
  const repaired=reconciledSeasonCursor(profile,progress,at);
  if(repaired===progress)return false;
  profile[PRODUCT_PROGRESS_FIELD]=repaired;
  return true;
}

// Read-only eligibility view. Never persist it or pass it to a currency grant.
// Known V1 accounts without a projection get no eligibility from legacy rank.
function productProgressProfile(profile,at){
  const stored=readBattleV1ProductProgress(profile,at);
  const progress=stored&&reconciledSeasonCursor(profile,stored,at);
  if(!progress){
    if(profile.serverProgress?.battleProtocol!==PROTOCOL)return profile;
    const number=periodSnapshot(at).seasonNumber;
    return {...profile,trophies:0,arenaIdx:0,serverSeason:{...seasonRecord(number,0),claimed:{}}};
  }
  const season=progress.seasons['s'+progress.rewardSeasonNumber];
  return {...profile,trophies:progress.trophies,arenaIdx:progress.arenaIdx,
    serverSeason:{...season,claimed:{},
      ...(progress.lastRewardSeason===undefined?{}:{lastRewardSeason:progress.lastRewardSeason,lastRewardTier:progress.lastRewardTier})}};
}

function paidSeasonTier(profile,seasonNumber,at){
  const sourceId='s'+seasonNumber,key=sourceClaimKey(profile.uid,'season_reward',sourceId);
  const economy=profile.serverEconomy,claim=economy?.claims?.[key];
  if(!record(claim)||claim.idempotencyKey!==key||claim.sourceType!=='season_reward'||claim.sourceId!==sourceId||
    !timestamp(claim.claimedAt)||claim.claimedAt>at||!record(claim.reward)||!Array.isArray(claim.transactionIds))throw unavailable();
  // A prior legacy claim may have a different tier; it is still already paid.
  for(const [currency,amount] of Object.entries(claim.reward)){
    if(!['gold','gems'].includes(currency)||!integer(amount)||amount<=0||
      !claim.transactionIds.some(id=>{
        const entry=economy.ledger?.[id];
        return record(entry)&&entry.transactionId===id&&entry.idempotencyKey===key&&entry.uid===profile.uid&&
          entry.sourceType==='season_reward'&&entry.sourceId===sourceId&&entry.rewardType===currency&&
          entry.amount===amount&&entry.createdAt===claim.claimedAt;
      }))throw unavailable();
  }
  if(!Object.keys(claim.reward).length)throw unavailable();
  const paidTier=SEASON_REWARDS.find(tier=>
    Object.keys(tier.reward).length===Object.keys(claim.reward).length&&
    Object.entries(tier.reward).every(([currency,amount])=>claim.reward[currency]===amount));
  if(!paidTier)throw unavailable();
  return paidTier;
}
// After applyRewardClaim, advance the legacy-compatible reward cursor, not rating.
// The shared season_reward ledger prevents separate legacy/V1 double claims.
function completeBattleV1ProductSeason(profile,seasonNumber,at){
  const progress=readBattleV1ProductProgress(profile,at),currentSeason=periodSnapshot(at).seasonNumber;
  if(!progress||seasonNumber!==progress.rewardSeasonNumber||seasonNumber>=currentSeason)throw unavailable();
  const paidTier=paidSeasonTier(profile,seasonNumber,at);
  const next=structuredClone(progress);
  next.rewardSeasonNumber=Object.values(next.seasons).reduce((number,season)=>
    season.number>seasonNumber?Math.min(number,season.number):number,currentSeason);
  next.seasonNumber=Math.max(next.seasonNumber,currentSeason);
  next.seasons['s'+currentSeason]??=seasonRecord(currentSeason,0);
  next.lastRewardSeason=seasonNumber;next.lastRewardTier=paidTier.tier;
  profile[PRODUCT_PROGRESS_FIELD]=next;
  return next;
}

module.exports={PRODUCT_PROGRESS_FIELD,projectBattleV1ProductProgress,readBattleV1ProductProgress,
  productProgressProfile,completeBattleV1ProductSeason,repairBattleV1ProductSeasonCursor};
