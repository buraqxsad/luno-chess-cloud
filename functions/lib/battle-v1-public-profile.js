'use strict';

const {PROTOCOL}=require('../rules-v1/dist/src/online/protocol.js');
const {ARENAS,arenaIndexForProfile}=require('./ranked');
const isRecord=value=>!!value&&typeof value==='object'&&!Array.isArray(value);
const validUid=value=>typeof value==='string'&&/^[A-Za-z0-9_-]{6,128}$/.test(value);
const nonnegativeInt=value=>Number.isSafeInteger(value)&&value>=0;
const validTrophies=value=>nonnegativeInt(value)&&value<=1000000000;

function rankUnavailable(){
  const error=new Error('Battle V1 rank is unavailable.');
  error.code='battle-v1-rank-unavailable';error.status=503;return error;
}

function battleV1RankFromAccount(uid,record){
  if(!validUid(uid))throw rankUnavailable();
  if(record===null||record===undefined)return {protocolVersion:PROTOCOL,uid,trophies:0,arenaIdx:0};
  if(!isRecord(record)||typeof record.accountJson!=='string'||
    (Object.hasOwn(record,'uid')&&record.uid!==uid))throw rankUnavailable();
  let account;try{account=JSON.parse(record.accountJson);}catch(_){throw rankUnavailable();}
  if(!isRecord(account)||account.migrationVersion!==1||!validTrophies(account.rating)||
    (Object.hasOwn(account,'uid')&&account.uid!==uid)||
    (Object.hasOwn(account,'protocolVersion')&&account.protocolVersion!==PROTOCOL))throw rankUnavailable();
  const trophies=account.rating,expectedArena=arenaIndexForProfile({trophies});
  let arenaIdx=expectedArena;
  if(Object.hasOwn(account,'ratingProfile')){
    const profile=account.ratingProfile;
    if(!isRecord(profile)||profile.uid!==uid||profile.trophies!==trophies||
      !nonnegativeInt(profile.arenaIdx)||profile.arenaIdx>=ARENAS.length||
      profile.arenaIdx!==expectedArena)throw rankUnavailable();
    arenaIdx=profile.arenaIdx;
  }
  return {protocolVersion:PROTOCOL,uid,trophies,arenaIdx};
}

async function readBattleV1Rank(db,uid){
  if(!validUid(uid))throw rankUnavailable();
  return battleV1RankFromAccount(uid,(await db.ref('battleV1Accounts/'+uid).get()).val());
}

function validBattleV1Rating(uid,value){
  return validUid(uid)&&isRecord(value)&&value.uid===uid&&value.protocolVersion===PROTOCOL&&
    validTrophies(value.rating)&&nonnegativeInt(value.revision)&&nonnegativeInt(value.games);
}

module.exports={PROTOCOL,battleV1RankFromAccount,readBattleV1Rank,validBattleV1Rating};
