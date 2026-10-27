'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {memoryDatabase}=require('./helpers/memory-database');
const api=require('../index')._test;
const {applyChestInventoryRewards}=require('../lib/chests');
const {SKIN_DROP_CATALOG,SOFT_ITEM_CATALOG,EMOJI_DROP_CATALOG}=require('../lib/catalogs');

for(const [id,item] of Object.entries(SKIN_DROP_CATALOG)){
  test(`legacy ${id}: chest pieces unlock a preserved right and real server selection`,async t=>{
    const uid='finish_'+id,p=api.starterProfile(uid,'finish_owner');
    p.inventory.ownedSets=['std','ottoman'];
    p.inventory.skinPieces={[id]:item.target-1};
    const rewards=applyChestInventoryRewards(p,[{type:'skin',id,amount:1}]);
    assert(p.inventory.ownedSkins.includes(id));
    assert.equal(p.inventory.skinPieces[id],item.target);
    if(id!=='classic')assert.equal(rewards[0].unlocked,true);
    const db=memoryDatabase(t,{users:{[uid]:p}}),beforeGold=p.gold;
    for(let replay=0;replay<3;replay++){
      const result=await api.updateProfile({uid,body:{activeSkin:id}});
      assert.equal(result.state.inventory.activeSkin,id);
      assert(result.state.inventory.ownedSkins.includes(id));
      assert.deepEqual(result.state.inventory.ownedSets,['std','ottoman']);
      assert.equal(db.read(`users/${uid}/gold`),beforeGold);
      assert.equal(db.read(`users/${uid}/inventory/skinPieces/${id}`),item.target);
    }
  });
  if(id!=='classic')test(`legacy ${id}: incomplete pieces and other owner cannot equip`,async t=>{
    const uid='locked_'+id,p=api.starterProfile(uid,'locked_owner');
    p.inventory.skinPieces={[id]:item.target-1};
    const other=api.starterProfile('other','other_owner');other.inventory.ownedSkins.push(id);
    const db=memoryDatabase(t,{users:{[uid]:p,other}});
    await assert.rejects(api.updateProfile({uid,body:{activeSkin:id}}),{code:'locked-selection'});
    assert.equal(db.read(`users/${uid}/inventory/activeSkin`),'classic');
    assert.equal(db.read(`users/${uid}/inventory/skinPieces/${id}`),item.target-1);
  });
}
for(const id of Object.keys(EMOJI_DROP_CATALOG)){
  test(`existing emoji:${id} gold price remains catalog-backed`,()=>{
    const expected={common:500,rare:1500,legendary:4000,mythic:10000}[EMOJI_DROP_CATALOG[id].rarity];
    assert.deepEqual(SOFT_ITEM_CATALOG['emoji:'+id],
      {currency:'gold',price:expected,grant:{kind:'emoji',id}});
  });
}
