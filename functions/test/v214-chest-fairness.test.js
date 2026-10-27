'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {rollChest,applyChestInventoryRewards,availableBattleCards}=require('../lib/chests');
const {CARD_UNLOCK_CATALOG,CHEST_CATALOG,SKIN_DROP_CATALOG,EMOJI_DROP_CATALOG,FRAME_SHARD_CATALOG,BIO_FRAME_SHARD_CATALOG}=require('../lib/catalogs');
const {CARDS,STARTER}=require('../rules-v1/dist/src/model');
const {migrateLegacy,mappedCard}=require('../rules-v1/dist/src/online/migration');
const {memoryDatabase}=require('./helpers/memory-database');
const {openChest,openPassChest,hash,sourceClaimKey,starterProfile}=require('../index')._test;

test('all fresh chest tiers and account stages are currency/cosmetic only across 12000 seeds',()=>{
  const profiles=[
    {trophies:0,unlockedCards:{}},
    {trophies:4000,arenaIdx:8,unlockedCards:{freeze:true,fog:true},battleV1UnlockedCards:{mine:true}},
    {trophies:99999,unlockedCards:Object.fromEntries(Object.keys(CARD_UNLOCK_CATALOG).map(id=>[id,true])),
      battleV1UnlockedCards:Object.fromEntries(Object.keys(CARDS).map(id=>[id,true])),inventory:{
        ownedSkins:Object.keys(SKIN_DROP_CATALOG),ownedEmojis:Object.keys(EMOJI_DROP_CATALOG),
        ownedFrames:Object.keys(FRAME_SHARD_CATALOG),ownedBioFrames:Object.keys(BIO_FRAME_SHARD_CATALOG)}}
  ];
  const allowed=new Set(['gold','gems','skin','emoji','frame_shard','bioframe_shard']);
  for(const [stage,profile] of profiles.entries()){
    const original=structuredClone(profile);
    for(const chest of Object.keys(CHEST_CATALOG)){
      assert.deepEqual(availableBattleCards(profile,chest),[]);
      for(let seed=0;seed<1000;seed++){
        const rewards=rollChest(profile,chest,`fairness-${stage}-${seed}`);
        assert(rewards.length>=1);assert(rewards.every(r=>allowed.has(r.type)));
        const gold=rewards.find(r=>r.type==='gold');
        assert(gold.amount>=CHEST_CATALOG[chest].drops.gold.min&&gold.amount<=CHEST_CATALOG[chest].drops.gold.max);
        assert(rewards.every(r=>Number.isSafeInteger(r.amount)&&r.amount>0));
        assert.deepEqual(rollChest(profile,chest,`fairness-${stage}-${seed}`),rewards);
      }
    }
    assert.deepEqual(profile,original);
  }
});

test('fresh openings never clear existing ownership, purchases, balances or premium claims',()=>{
  const profile={gold:1234,gems:456,trophies:4000,unlockedCards:{fog:true,barbarian:true},battleV1UnlockedCards:{board_seal:true},
    passState:{premium:true,claimed:{premium:{1:123}}},serverEconomy:{purchases:{historic:{receipt:true}}},
    inventory:{ownedSets:['ottoman'],pendingChests:['rare','rare']},stats:{chestsOpened:10}};
  const protectedState=()=>({gold:profile.gold,gems:profile.gems,unlockedCards:profile.unlockedCards,
    battleV1UnlockedCards:profile.battleV1UnlockedCards,passState:profile.passState,serverEconomy:profile.serverEconomy,
    ownedSets:profile.inventory.ownedSets,pendingChests:profile.inventory.pendingChests});
  const before=structuredClone(protectedState());
  for(const chest of Object.keys(CHEST_CATALOG))applyChestInventoryRewards(profile,rollChest(profile,chest,'preserve-'+chest));
  assert.deepEqual(protectedState(),before);assert.equal(profile.stats.chestsOpened,14);
});

test('every stored historic legacy card reward is still deliverable and mapped ownership is preserved',()=>{
  const profile={unlockedCards:{historic:true},battleV1UnlockedCards:{board_seal:true},stats:{}};
  const results=Object.keys(CARD_UNLOCK_CATALOG).map(id=>({type:'card',id,amount:1}));
  const untouched=structuredClone(results),grants=applyChestInventoryRewards(profile,results);
  assert(grants.every(reward=>reward.unlocked===true));assert.equal(profile.unlockedCards.historic,true);
  const migrated=migrateLegacy(profile);
  for(const reward of results){assert.equal(profile.unlockedCards[reward.id],true);const mapped=mappedCard(reward.id);if(mapped)assert(migrated.entitlements.includes(mapped));}
  assert(migrated.entitlements.includes('board_seal'));
  assert.deepEqual(results,untouched);
  const ownership=structuredClone(profile.unlockedCards);
  const repeat=applyChestInventoryRewards(profile,results);
  assert(repeat.every(reward=>reward.unlocked===undefined));assert.deepEqual(profile.unlockedCards,ownership);
});

test('catalog prototype names cannot become historic card or cosmetic ownership',()=>{
  const profile={stats:{}};
  const rewards=['card','battle_card','skin','emoji','frame_shard','bioframe_shard'].flatMap(type=>
    ['__proto__','constructor','toString','unknown'].map(id=>({type,id,amount:999})));
  const grants=applyChestInventoryRewards(profile,rewards);
  assert(grants.every(reward=>reward.unlocked===undefined));
  assert.equal(profile.unlockedCards,undefined);assert.equal(profile.battleV1UnlockedCards,undefined);
  for(const field of ['skinPieces','emojiPieces','frameShards','bioFrameShards'])assert.deepEqual(profile.inventory[field],{});
});

for(const mode of ['shop','pass'])test(`${mode} historic committed card receipt replays exactly without spending or reroll`,async t=>{
  const uid='v214_chest_player',requestId='historic-'+mode,profile=starterProfile(uid,'v214_chest');
  assert.equal(profile.battleV1MigrationPolicy,'native-v1');
  assert.deepEqual(new Set(migrateLegacy(profile).entitlements),new Set(STARTER));
  // Historical receipts belong to accounts predating the native-V1 policy;
  // compatibility defaults on a genuinely new account are not earned cards.
  delete profile.battleV1MigrationPolicy;
  profile.gold=10000;profile.gems=1000;profile.inventory.pendingChests=['rare','rare'];
  const db=memoryDatabase(t,{users:{[uid]:profile}}),context={uid,requestId,body:{chestId:'rare'}},open=mode==='shop'?openChest:openPassChest;
  const first=await open(context);assert.equal(first.opened,true);
  assert(!first.rewards.some(r=>r.type==='card'||r.type==='battle_card'));
  const stored=db.read('users/'+uid),historical=[...first.rewards,
    {type:'card',id:'fog',rarity:'rare',amount:1,unlocked:true},
    {type:'battle_card',id:'board_seal',rarity:'legendary',amount:1,unlocked:true}];
  stored.unlockedCards.fog=true;stored.battleV1UnlockedCards={board_seal:true};
  if(mode==='shop'){
    const source='rare:'+hash(requestId).slice(0,32),key=sourceClaimKey(uid,'chest_purchase',source);
    stored.serverEconomy.purchases[key].outcome.rewards=historical;
  }else{
    const source='pass:rare:'+hash(requestId).slice(0,32),key=sourceClaimKey(uid,'pass_chest_reward',source);
    stored.serverEconomy.claims[key].passChestOpening.rewards=historical;
  }
  db.write('users/'+uid,stored);db.write(`serverRequests/${uid}/${hash(requestId).slice(0,48)}`,null);
  const before=structuredClone(stored),replay=await open(context);
  assert.equal(replay.opened,false);assert.equal(replay.idempotent,true);assert.deepEqual(replay.rewards,historical);
  assert.deepEqual(db.read('users/'+uid),before);
  assert(migrateLegacy(before).entitlements.includes('board_seal'));assert(migrateLegacy(before).entitlements.includes('fog'));
  const fresh=await open({...context,requestId:'new-'+mode});
  assert.equal(fresh.opened,true);assert(!fresh.rewards.some(r=>r.type==='card'||r.type==='battle_card'));
  assert.equal(db.read('users/'+uid+'/battleV1UnlockedCards/board_seal'),true);
  assert.equal(db.read('users/'+uid+'/unlockedCards/fog'),true);
});
