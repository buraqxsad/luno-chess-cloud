'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {getDatabase}=require('firebase-admin/database');
const {starterProfile,publishPublicProfile,nextProfileUpdateTime,updateProfile,LEGAL_TERMS_VERSION,LEGAL_PRIVACY_VERSION,LEGAL_COMMUNITY_VERSION}=require('../index.js')._test;

test('profile preference updates are ordered even at equal or regressed wall time',()=>{
  const profile={updatedAt:100};
  profile.updatedAt=nextProfileUpdateTime(profile,100);
  assert.equal(profile.updatedAt,101);
  profile.updatedAt=nextProfileUpdateTime(profile,100);
  assert.equal(profile.updatedAt,102);
  assert.equal(nextProfileUpdateTime(profile,50),103);
  assert.equal(nextProfileUpdateTime(profile,200),200);
});

test('legacy profile time normalizes but unsafe ordering fails closed',()=>{
  for(const updatedAt of [undefined,-1,NaN,Infinity,{'sv':'timestamp'}]){
    assert.equal(nextProfileUpdateTime({updatedAt},100),100);
  }
  for(const at of [-1,NaN,Infinity,1.5]){
    assert.throws(()=>nextProfileUpdateTime({},at),{code:'profile-clock-invalid'});
  }
  assert.throws(()=>nextProfileUpdateTime({updatedAt:Number.MAX_SAFE_INTEGER},100),{code:'profile-clock-invalid'});
});

for(const scenario of ['processing-before','deleted-before','complete-before','deletion-during-write','tombstone-during-write','gate-read-failure']){
  test(`public profile does not survive ${scenario}`,async t=>{
    let value=null,writes=0,removed=0,afterWrite=false;
    t.mock.method(getDatabase(),'ref',path=>{
      if(path.startsWith('publicProfiles/'))return {
        async transaction(update){value=update(value);writes++;afterWrite=true;return {committed:true,snapshot:{val:()=>value}};},
        async remove(){value=null;removed++;},
      };
      return {async get(){
        if(scenario==='gate-read-failure'&&afterWrite)throw new Error('gate-unavailable');
        const deletion=path.startsWith('accountDeletions/');
        const state=deletion&&((scenario==='processing-before')||scenario==='deletion-during-write'&&afterWrite)
          ?{status:'processing'}:deletion&&scenario==='complete-before'?{status:'complete'}:
          !deletion&&(scenario==='deleted-before'||scenario==='tombstone-during-write'&&afterWrite)?{deletedAt:1}:null;
        return {val:()=>state,exists:()=>state!==null};
      }};
    });
    const operation=publishPublicProfile('deleted-player',starterProfile('deleted-player','deleted_name'),Date.now());
    if(scenario==='gate-read-failure')await assert.rejects(operation,/gate-unavailable/);
    else await operation;
    assert.equal(value,null);
    assert.equal(writes,scenario.endsWith('before')?0:1);
    assert.equal(removed,scenario.endsWith('before')?0:1);
  });
}

test('deletion-gate failure before publication prevents any public write',async t=>{
  t.mock.method(getDatabase(),'ref',path=>{
    assert.ok(!path.startsWith('publicProfiles/'));
    return {async get(){throw new Error('gate-unavailable');}};
  });
  await assert.rejects(publishPublicProfile('player',starterProfile('player','playername')),/gate-unavailable/);
});

test('real profile update transaction increments ordering and publishes cleared biography',async t=>{
  const uid='ordered-player',initialTime=Date.now()+60000;
  const initial=starterProfile(uid,'ordered_name');
  initial.legalConsent={uid,acceptedAt:1,termsVersion:LEGAL_TERMS_VERSION,privacyVersion:LEGAL_PRIVACY_VERSION,communityVersion:LEGAL_COMMUNITY_VERSION};
  initial.updatedAt=initialTime;
  const values=new Map([[`users/${uid}`,initial]]);
  const clone=value=>value===undefined?null:structuredClone(value);
  t.mock.method(getDatabase(),'ref',path=>({
    async get(){const value=clone(values.get(path));return {val:()=>value,exists:()=>value!==null};},
    async transaction(update){
      const next=update(clone(values.get(path)));
      if(next!==undefined)values.set(path,clone(next));
      return {committed:next!==undefined,snapshot:{val:()=>clone(values.get(path))}};
    },
    async remove(){values.delete(path);},
  }));
  const first=await updateProfile({uid,body:{bio:'First biography',country:'GB'}});
  assert.equal(first.ok,true);
  assert.equal(first.state.profile.bio,'First biography');
  assert.equal(values.get(`users/${uid}`).updatedAt,initialTime+1);
  assert.equal(values.get(`publicProfiles/${uid}`).bio,'First biography');
  const second=await updateProfile({uid,body:{bio:''}});
  assert.equal(second.ok,true);
  assert.equal(second.state.profile.bio,'');
  assert.equal(values.get(`users/${uid}`).updatedAt,initialTime+2);
  assert.equal(values.get(`publicProfiles/${uid}`).bio,'');
  assert.equal(values.get(`publicProfiles/${uid}`).country,'GB');
});

test('failed cleanup is not reported as a successful publication',async t=>{
  let written=false;
  t.mock.method(getDatabase(),'ref',path=>{
    if(path.startsWith('publicProfiles/'))return {
      async transaction(update){written=true;return {committed:true,snapshot:{val:()=>update(null)}};},
      async remove(){throw new Error('cleanup-unavailable');},
    };
    return {async get(){const state=written?{status:'processing'}:null;return {val:()=>state,exists:()=>state!==null};}};
  });
  await assert.rejects(publishPublicProfile('player',starterProfile('player','playername')),/cleanup-unavailable/);
});
