'use strict';
const {rollChest}=require('../lib/chests');
const {CHEST_CATALOG,SKIN_DROP_CATALOG,EMOJI_DROP_CATALOG,FRAME_SHARD_CATALOG,BIO_FRAME_SHARD_CATALOG,
  SOFT_ITEM_CATALOG,PASS_CURRENCY_REWARDS,PASS_CURRENCY_REWARDS_V2,PASS_CONTENT_REWARDS}=require('../lib/catalogs');
const samples=10000;
const fresh={inventory:{ownedSkins:['classic'],ownedEmojis:['smile'],ownedFrames:['none'],ownedBioFrames:['default']}};
const exhausted={inventory:{ownedSkins:Object.keys(SKIN_DROP_CATALOG),ownedEmojis:Object.keys(EMOJI_DROP_CATALOG),ownedFrames:Object.keys(FRAME_SHARD_CATALOG),ownedBioFrames:Object.keys(BIO_FRAME_SHARD_CATALOG)}};
function model(profile,chestId){
  const totals={},slots={},rarities={};let noCosmetic=0;
  for(let seed=0;seed<samples;seed++){
    const rewards=rollChest(profile,chestId,'v215-ev-'+seed);
    if(rewards.every(r=>r.type==='gold'))noCosmetic++;
    slots[rewards.length]=(slots[rewards.length]||0)+1;
    for(const r of rewards){totals[r.type]=(totals[r.type]||0)+r.amount;if(r.rarity)rarities[r.rarity]=(rarities[r.rarity]||0)+r.amount;}
  }
  const mean=values=>Object.fromEntries(Object.entries(values).map(([key,total])=>[key,Number((total/samples).toFixed(4))]));
  return {price:CHEST_CATALOG[chestId].price,currency:CHEST_CATALOG[chestId].currency,
    expectedUnits:mean(totals),expectedRarityUnits:mean(rarities),slotCounts:slots,goldOnlyProbability:noCosmetic/samples};
}
const passTotal=rewards=>Object.values(rewards).reduce((sum,r)=>({gold:sum.gold+(r.gold||0),gems:sum.gems+(r.gems||0)}),{gold:0,gems:0});
console.log(JSON.stringify({samples,seedPrefix:'v215-ev-',method:'Independent fixed inventory per roll; no gem conversion assigned to partial cosmetic pieces; not a completion-time simulation.',
  chests:Object.fromEntries(Object.keys(CHEST_CATALOG).map(id=>[id,{fresh:model(fresh,id),exhausted:model(exhausted,id)}])),
  pass:{priceGems:SOFT_ITEM_CATALOG['pass:premium'].price,legacy:{free:passTotal(PASS_CURRENCY_REWARDS.free),premium:passTotal(PASS_CURRENCY_REWARDS.premium)},future:{free:passTotal(PASS_CURRENCY_REWARDS_V2.free),premium:passTotal(PASS_CURRENCY_REWARDS_V2.premium)},content:PASS_CONTENT_REWARDS},
  goldSinks:Object.fromEntries(Object.entries(SOFT_ITEM_CATALOG).filter(([,v])=>v.currency==='gold').map(([id,v])=>[id,v.price])),
  startingGems:{existing:42,proposedNew:50,delta:8,additionalPassCostShare:8/SOFT_ITEM_CATALOG['pass:premium'].price,existingBalancesMigrated:false},
  premium:'Subscription-only cosmetics/profile identity; no competitive cards, no automatic Pass. Cash prices are Play-localized and not assumed here.'},null,2));
