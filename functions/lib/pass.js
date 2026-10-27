'use strict';

const {periodSnapshot}=require('./economy');
const {PASS_CURRENCY_REWARDS,PASS_CURRENCY_REWARDS_V2}=require('./catalogs');
const {normalizeProductEntitlements}=require('./membership');
// s6 was live during this pass. Its full advertised rewards are retained;
// version 2 begins at s7 (2026-10-28 UTC), without changing season identifiers.
const LAST_LEGACY_PASS_SEASON=6;
const record=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
const safeInt=value=>{
  const number=typeof value==='number'?value:typeof value==='string'&&/^\d+$/.test(value.trim())?Number(value):0;
  return Number.isSafeInteger(number)&&number>=0?number:0;
};
function normalizedClaims(value){
  if(!record(value)&&!Array.isArray(value))return {};
  return Object.fromEntries(Object.entries(value).filter(([level,marker])=>
    /^(?:[1-9]|[12][0-9]|30)$/.test(level)&&
    (marker===true||Number.isSafeInteger(marker)&&marker>0)));
}
function passRewardVersion(pass,seasonId){
  if(pass?.rewardVersion===1||pass?.rewardVersion===2)return pass.rewardVersion;
  const match=/^s([1-9][0-9]*)$/.exec(String(seasonId||''));
  if(!match||Number(match[1])<=LAST_LEGACY_PASS_SEASON)return 1;
  // An unversioned earned/purchased live entitlement must not be downgraded.
  if(pass?.premium===true||safeInt(pass?.level)>0||safeInt(pass?.xp)>0||
    Object.keys(normalizedClaims(pass?.claimed?.premium)).length>0)return 1;
  return 2;
}
function syncPassState(profile,at){
  normalizeProductEntitlements(profile);
  const periods=periodSnapshot(at),season=periods.seasonNumber,seasonKey='ranked-'+periods.seasonId+'-v2';
  if(!record(profile.passState)||profile.passState.seasonKey!==seasonKey){
    profile.passState={seasonKey,seasonStartedAt:at,season,level:0,xp:0,premium:false,
      premiumSource:'',claimed:{free:{},premium:{}},
      rewardVersion:season<=LAST_LEGACY_PASS_SEASON?1:2};
  }
  const pass=profile.passState;
  pass.rewardVersion=passRewardVersion(pass,periods.seasonId);
  pass.seasonKey=seasonKey;pass.season=season;
  pass.level=Math.min(30,safeInt(pass.level));pass.xp=Math.min(249,safeInt(pass.xp));
  if(!record(pass.claimed))pass.claimed={free:{},premium:{}};
  for(const track of ['free','premium'])pass.claimed[track]=normalizedClaims(pass.claimed[track]);
  pass.unlocks=Array.isArray(pass.unlocks)?pass.unlocks.filter(value=>typeof value==='string'):[];
  return {pass,periods};
}
function passCurrencyReward(pass,track,level){
  if(!['free','premium'].includes(track)||!Number.isInteger(level)||level<1||level>30)return null;
  const version=passRewardVersion(pass,'s'+safeInt(pass?.season));
  const rewards=version===2?PASS_CURRENCY_REWARDS_V2:PASS_CURRENCY_REWARDS;
  return {...rewards[track][level]};
}
module.exports={LAST_LEGACY_PASS_SEASON,passRewardVersion,syncPassState,passCurrencyReward};
