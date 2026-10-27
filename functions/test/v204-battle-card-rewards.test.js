'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {CARDS,STARTER}=require('../rules-v1/dist/src/model.js');
const {migrateLegacy,validateOwnedDeck}=require('../rules-v1/dist/src/online/migration.js');
const {rollChest,applyChestInventoryRewards,availableBattleCards}=require('../lib/chests');

test('new gold and gem chests never offer canonical or mapped legacy battle cards',()=>{
 const profile={unlockedCards:{},trophies:0};
 for(const chest of ['common','rare','legendary','royal']){
  assert.deepEqual(availableBattleCards(profile,chest),[]);
  for(let seed=0;seed<500;seed++)assert(!rollChest(profile,chest,'v214-no-rng-'+seed).some(r=>r.type==='card'||r.type==='battle_card'));
 }
});

for(const id of Object.keys(CARDS).filter(card=>!STARTER.includes(card)))test(`historic ${id} chest receipt preserves ownership and remains selectable`,()=>{
 const profile={unlockedCards:{},trophies:0,stats:{}};
 const before=migrateLegacy(profile);
 const rewards=[{type:'battle_card',id,rarity:CARDS[id].rarity,amount:1}];
 const unchanged=structuredClone(rewards);
 const granted=applyChestInventoryRewards(profile,rewards);
 const card=granted.find(reward=>reward.type==='battle_card');
 assert.equal(card.unlocked,true);
 assert.equal(profile.battleV1UnlockedCards[card.id],true);
 const migrated=migrateLegacy(profile,before);
 assert(migrated.entitlements.includes(card.id));
 assert.deepEqual(validateOwnedDeck([...STARTER.slice(0,9),card.id],migrated),[...STARTER.slice(0,9),card.id]);
 const replay=applyChestInventoryRewards(profile,rewards);
 assert.equal(replay.find(reward=>reward.type==='battle_card').unlocked,undefined);
 assert.deepEqual(rewards,unchanged);
 assert(!availableBattleCards(profile,'legendary').includes(card.id));
});
