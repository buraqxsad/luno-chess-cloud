'use strict';

const crypto=require('node:crypto');
const {MISSION_CATALOG}=require('./catalogs');
const {CARDS,STARTER}=require('../rules-v1/dist/src/model.js');

function missionOwned(profile,definition){
  const unlocked=profile&&profile.unlockedCards&&typeof profile.unlockedCards==='object'?profile.unlockedCards:{};
  const nativeV1=profile?.battleV1MigrationPolicy==='native-v1';
  if(nativeV1||profile?.serverProgress?.battleProtocol==='LUNO_BATTLE_V1'){
    const battleUnlocked=profile.battleV1UnlockedCards||{},owned=new Set(STARTER);
    for(const source of [nativeV1?{}:unlocked,battleUnlocked])for(const [id,value] of Object.entries(source))if(value===true&&Object.hasOwn(CARDS,id))owned.add(id);
    if(definition?.counter?.startsWith('cf_')&&definition.counter!=='cf_radar')return false;
    if(definition?.card)return Object.hasOwn(CARDS,definition.card)&&owned.has(definition.card);
    if(Array.isArray(definition?.anyOf))return definition.anyOf.some(id=>Object.hasOwn(CARDS,id)&&owned.has(id));
    return true;
  }
  if(definition&&definition.card)return unlocked[definition.card]===true;
  if(definition&&Array.isArray(definition.anyOf))return definition.anyOf.some(function(card){return unlocked[card]===true;});
  return true;
}
function deterministicMissionIds(profile,category,periodId){
  const catalog=MISSION_CATALOG[category]||{};
  const mandatory=category==='daily'?'d1':'w1';
  const candidates=Object.keys(catalog).filter(function(id){return id!==mandatory&&missionOwned(profile,catalog[id]);});
  candidates.sort(function(first,second){
    const firstHash=crypto.createHash('sha256').update([profile.uid,category,periodId,first].join('|')).digest('hex');
    const secondHash=crypto.createHash('sha256').update([profile.uid,category,periodId,second].join('|')).digest('hex');
    return firstHash.localeCompare(secondHash);
  });
  return [mandatory].concat(candidates).slice(0,5);
}

module.exports={deterministicMissionIds,missionOwned};
