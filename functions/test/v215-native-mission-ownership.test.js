'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {missionOwned,deterministicMissionIds}=require('../lib/missions');
const {MISSION_CATALOG}=require('../lib/catalogs');
const fresh={uid:'native_player',battleV1MigrationPolicy:'native-v1',unlockedCards:{radar:true,card_block:true,angry_n:true,trap:true}};

test('native mission eligibility never mistakes compatibility defaults for earned V1 cards',()=>{
  for(const profile of [fresh,{...fresh,serverProgress:{battleProtocol:'LUNO_BATTLE_V1'}}]){
    assert.equal(missionOwned(profile,{card:'radar'}),true);
    assert.equal(missionOwned(profile,{card:'card_block'}),false);
    assert.equal(missionOwned(profile,{anyOf:['angry_n','angry_b']}),false);
    assert.equal(missionOwned(profile,{card:'trap'}),false);
    assert.equal(missionOwned(profile,{counter:'cf_trap'}),false);
    const earned={...profile,battleV1UnlockedCards:{card_block:true,angry_n:true}};
    assert.equal(missionOwned(earned,{card:'card_block'}),true);
    assert.equal(missionOwned(earned,{anyOf:['angry_n','angry_b']}),true);
  }
});

test('native daily/weekly pool only selects actually available card objectives',()=>{
  for(let day=0;day<100;day++)for(const category of ['daily','weekly']){
    const ids=deterministicMissionIds(fresh,category,'period_'+day);
    assert.equal(ids.length,5);assert.equal(new Set(ids).size,5);
    for(const id of ids){
      const definition=MISSION_CATALOG[category][id];
      if(definition.card||definition.anyOf)assert.equal(missionOwned({...fresh,unlockedCards:{}},definition),true);
      assert.ok(!['dc_block','dc_angry'].includes(id));
    }
  }
});

test('unmarked historic V1 and legacy mission rights remain intact',()=>{
  const historic={...fresh,serverProgress:{battleProtocol:'LUNO_BATTLE_V1'}};
  delete historic.battleV1MigrationPolicy;
  assert.equal(missionOwned(historic,{card:'card_block'}),true);
  assert.equal(missionOwned(historic,{anyOf:['angry_n','angry_b']}),true);
  const legacy={...historic};delete legacy.serverProgress;
  assert.equal(missionOwned(legacy,{card:'trap'}),true);
  assert.equal(missionOwned(legacy,{counter:'cf_trap'}),true);
});
