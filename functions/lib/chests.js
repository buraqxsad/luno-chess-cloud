'use strict';

const crypto=require('node:crypto');
const {
  BIO_FRAME_SHARD_CATALOG,
  CARD_UNLOCK_CATALOG,
  CHEST_CATALOG,
  EMOJI_DROP_CATALOG,
  FRAME_SHARD_CATALOG,
  SKIN_DROP_CATALOG
}=require('./catalogs');
const {arenaIndexForProfile}=require('./ranked');
const {CARDS,STARTER}=require('../rules-v1/dist/src/model.js');
const starterBattleCards=new Set(STARTER);

function record(value){return value!==null&&typeof value==='object'&&!Array.isArray(value);}
function int(value,fallback){const number=Number(value);return Number.isSafeInteger(number)&&number>=0?number:Number(fallback||0);}
function stringList(value,defaults){
  const result=[],seen=new Set();
  const add=function(item){item=String(item||'').slice(0,64);if(item&&!seen.has(item)){seen.add(item);result.push(item);}};
  if(Array.isArray(value))value.forEach(add);
  else if(record(value))Object.keys(value).forEach(function(key){if(value[key]===true)add(key);else add(value[key]);});
  (defaults||[]).forEach(add);
  return result;
}
// Pending Pass chests are inventory units, not owned cosmetic IDs. Preserve
// duplicate rarities so two earned rare chests cannot collapse into one.
function stringMultisetList(value,defaults){
  const result=[];
  const add=function(item){item=String(item||'').slice(0,64);if(item)result.push(item);};
  if(Array.isArray(value))value.forEach(add);
  else if(record(value))Object.keys(value).forEach(function(key){
    const count=Number(value[key]);
    if(Number.isSafeInteger(count)&&count>0&&count<=100)for(let index=0;index<count;index++)add(key);
    else if(value[key]===true)add(key);
  });
  (defaults||[]).forEach(add);
  return result;
}
function seededRandom(seed){
  let counter=0;
  return function(){
    const digest=crypto.createHash('sha256').update(String(seed)+'|'+counter++).digest();
    return digest.readUInt32BE(0)/0x100000000;
  };
}
function randomInt(random,min,max){return min+Math.floor(random()*(max-min+1));}
function pick(random,list){return list.length?list[Math.floor(random()*list.length)]:null;}
function missingCollectibles(profile,catalog,ownedField,piecesField,rarity){
  const inventory=record(profile.inventory)?profile.inventory:{},owned=new Set(stringList(inventory[ownedField],[])),pieces=record(inventory[piecesField])?inventory[piecesField]:{};
  return Object.keys(catalog).filter(function(id){
    const item=catalog[id];
    return item.rarity===rarity&&!owned.has(id)&&int(pieces[id],0)<item.target;
  });
}
function availableCards(profile){
  const unlocked=record(profile.unlockedCards)?profile.unlockedCards:{},arenaIdx=arenaIndexForProfile(profile);
  return Object.keys(CARD_UNLOCK_CATALOG).filter(function(id){
    return unlocked[id]!==true&&CARD_UNLOCK_CATALOG[id].arenaIdx<=arenaIdx;
  });
}
// Retain the exported query for older callers, but competitive access is now
// earned through verified match progression, never a new random chest roll.
function availableBattleCards(){return [];}
function collectibleDrop(random,profile,kind,rarity,min,max){
  const skin=kind==='skin',catalog=skin?SKIN_DROP_CATALOG:EMOJI_DROP_CATALOG;
  const ids=missingCollectibles(profile,catalog,skin?'ownedSkins':'ownedEmojis',skin?'skinPieces':'emojiPieces',rarity);
  const id=pick(random,ids);if(!id)return null;
  return {type:kind,id,name:catalog[id].name,rarity,amount:randomInt(random,min,max)};
}
function shardDrop(random,profile,catalog,ownedField,piecesField,rarities,amount){
  const inventory=record(profile.inventory)?profile.inventory:{},owned=new Set(stringList(inventory[ownedField],[])),pieces=record(inventory[piecesField])?inventory[piecesField]:{};
  const ids=Object.keys(catalog).filter(function(id){
    return rarities.includes(catalog[id].rarity)&&!owned.has(id)&&int(pieces[id],0)<catalog[id].target;
  });
  const id=pick(random,ids);if(!id)return null;
  return {id,name:catalog[id].name,rarity:catalog[id].rarity,amount};
}
function chestCosmeticTargets(profile,chestId){
  const chest=CHEST_CATALOG[chestId];if(!chest)throw new TypeError('Unknown chest.');
  const targets=[];
  for(const [key,drop] of Object.entries(chest.drops)){
    if(key==='gold'||drop.chance<=0)continue;
    const [type,rarity]=key.split('_'),skin=type==='skin',catalog=skin?SKIN_DROP_CATALOG:EMOJI_DROP_CATALOG;
    for(const id of missingCollectibles(profile,catalog,skin?'ownedSkins':'ownedEmojis',skin?'skinPieces':'emojiPieces',rarity)){
      targets.push({type,id,name:catalog[id].name,rarity,min:drop.min,max:drop.max});
    }
  }
  const rarities=['legendary',...(chestId==='legendary'||chestId==='royal'?['mythic']:[])];
  for(const [type,catalog,ownedField,piecesField] of [
    ['frame_shard',FRAME_SHARD_CATALOG,'ownedFrames','frameShards'],
    ['bioframe_shard',BIO_FRAME_SHARD_CATALOG,'ownedBioFrames','bioFrameShards'],
  ])for(const rarity of rarities){
    for(const id of missingCollectibles(profile,catalog,ownedField,piecesField,rarity))targets.push({type,id,name:catalog[id].name,rarity,min:1,max:1});
  }
  return targets;
}
function chestAvailability(profile,chestId){
  const definition=CHEST_CATALOG[chestId],canPurchase=chestCosmeticTargets(profile,chestId).length>0;
  return {canPurchase,reason:canPurchase?null:'chest-collection-complete',currency:definition.currency,price:definition.price,
    guaranteedGold:{min:definition.drops.gold.min,max:definition.drops.gold.max},guaranteedCosmetic:canPurchase,competitiveCards:false};
}
function rollChest(profile,chestId,seed){
  const chest=CHEST_CATALOG[chestId];if(!chest)throw new TypeError('Unknown chest.');
  const random=seededRandom(seed),results=[];
  const gold=chest.drops.gold;
  results.push({type:'gold',amount:randomInt(random,gold.min,gold.max)});
  const priorities=['mythic','legendary','rare','common'];
  priorities.forEach(function(rarity){
    Object.keys(chest.drops).forEach(function(key){
      if(key==='gold'||!key.endsWith('_'+rarity))return;
      const drop=chest.drops[key];if(random()>=drop.chance)return;
      const kind=key.startsWith('skin_')?'skin':'emoji';
      const result=collectibleDrop(random,profile,kind,rarity,drop.min,drop.max);
      if(result)results.push(result);
    });
  });
  const frameChance={common:.05,rare:.15,legendary:.35,royal:.55}[chestId]||0;
  if(random()<frameChance){
    const rarities=chestId==='legendary'||chestId==='royal'?['legendary','mythic']:['legendary'];
    const result=shardDrop(random,profile,FRAME_SHARD_CATALOG,'ownedFrames','frameShards',rarities,random()<.3?2:1);
    if(result)results.push(Object.assign({type:'frame_shard'},result));
  }
  const bioChance={common:.04,rare:.12,legendary:.25,royal:.4}[chestId]||0;
  if(random()<bioChance){
    const rarities=chestId==='legendary'||chestId==='royal'?['legendary','mythic']:['legendary'];
    const result=shardDrop(random,profile,BIO_FRAME_SHARD_CATALOG,'ownedBioFrames','bioFrameShards',rarities,1);
    if(result)results.push(Object.assign({type:'bioframe_shard'},result));
  }
  if(results.length===1){
    // A paid chest must progress the remaining cosmetic collection, not become
    // an expensive gold-only roll when its higher rarity pools are exhausted.
    const target=pick(random,chestCosmeticTargets(profile,chestId));
    if(target){const {min,max,...item}=target;results.push({...item,amount:randomInt(random,min,max)});}
  }
  // Do not roll legacy cards either: some migrate into canonical V1 abilities.
  // Historic card rewards are still accepted by the receipt delivery below.
  return results;
}

function ensureInventory(profile){
  if(!record(profile.inventory))profile.inventory={};
  const inventory=profile.inventory;
  inventory.ownedSkins=stringList(inventory.ownedSkins,['classic']);
  inventory.ownedEmojis=stringList(inventory.ownedEmojis,[]);
  inventory.ownedFrames=stringList(inventory.ownedFrames,['none']);
  inventory.ownedBioFrames=stringList(inventory.ownedBioFrames,['default']);
  if(!record(inventory.skinPieces))inventory.skinPieces={};
  if(!record(inventory.emojiPieces))inventory.emojiPieces={};
  if(!record(inventory.frameShards))inventory.frameShards={};
  if(!record(inventory.bioFrameShards))inventory.bioFrameShards={};
  return inventory;
}
function addCollectiblePieces(inventory,result,catalog,ownedField,piecesField){
  if(!Object.hasOwn(catalog,result.id))return;const item=catalog[result.id];
  const before=int(inventory[piecesField][result.id],0),after=Math.min(item.target,before+int(result.amount,0));
  inventory[piecesField][result.id]=after;
  if(after>=item.target&&!inventory[ownedField].includes(result.id)){inventory[ownedField].push(result.id);result.unlocked=true;}
}
function addShardPieces(inventory,result,catalog,ownedField,piecesField){
  if(!Object.hasOwn(catalog,result.id))return;const item=catalog[result.id];
  const before=int(inventory[piecesField][result.id],0),after=Math.min(item.target,before+int(result.amount,0));
  inventory[piecesField][result.id]=after;
  if(after>=item.target&&!inventory[ownedField].includes(result.id)){inventory[ownedField].push(result.id);result.unlocked=true;}
}
function applyChestInventoryRewards(profile,results){
  const inventory=ensureInventory(profile),output=results.map(function(item){return Object.assign({},item);});
  output.forEach(function(result){
    if(result.type==='skin')addCollectiblePieces(inventory,result,SKIN_DROP_CATALOG,'ownedSkins','skinPieces');
    else if(result.type==='emoji')addCollectiblePieces(inventory,result,EMOJI_DROP_CATALOG,'ownedEmojis','emojiPieces');
    else if(result.type==='frame_shard')addShardPieces(inventory,result,FRAME_SHARD_CATALOG,'ownedFrames','frameShards');
    else if(result.type==='bioframe_shard')addShardPieces(inventory,result,BIO_FRAME_SHARD_CATALOG,'ownedBioFrames','bioFrameShards');
    else if(result.type==='card'&&Object.hasOwn(CARD_UNLOCK_CATALOG,result.id)){
      if(!record(profile.unlockedCards))profile.unlockedCards={};
      if(profile.unlockedCards[result.id]!==true){profile.unlockedCards[result.id]=true;result.unlocked=true;}
    }else if(result.type==='battle_card'&&Object.hasOwn(CARDS,result.id)&&!starterBattleCards.has(result.id)){
      if(!record(profile.battleV1UnlockedCards))profile.battleV1UnlockedCards={};
      if(profile.battleV1UnlockedCards[result.id]!==true){profile.battleV1UnlockedCards[result.id]=true;result.unlocked=true;}
    }
  });
  if(!record(profile.stats))profile.stats={};
  profile.stats.chestsOpened=int(profile.stats.chestsOpened,0)+1;
  return output;
}

module.exports={applyChestInventoryRewards,availableCards,availableBattleCards,chestAvailability,rollChest,seededRandom,stringList,stringMultisetList};
