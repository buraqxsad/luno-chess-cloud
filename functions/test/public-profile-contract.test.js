'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {starterProfile,publicProfile,leaderboardRows}=require('../index.js')._test;

function row(profile,mode='trophies'){
  return leaderboardRows({'uid-contract':profile},mode,10,'viewer')[0];
}

test('public mirror retains match totals, biography and canonical identity in API rows',function(){
  const profile=starterProfile('uid-contract','contract_player');
  profile.stats={wins:4,losses:3,draws:2};
  profile.bio='A real biography';
  profile.country='GB';
  const mirror=publicProfile(profile,Date.now());
  const result=row(mirror);
  assert.equal(result.gamesPlayed,9);
  assert.equal(result.wins,4);
  assert.equal(result.bio,'A real biography');
  assert.equal(result.username,'contract_player');
  assert.equal(result.country,'GB');
});

test('private collection rows and public mirror use the same public fields',function(){
  const profile=starterProfile('uid-contract','contract_player');
  profile.stats={wins:8,losses:2,draws:1};
  profile.bio='Collection player';
  profile.serverSeason={peakTrophies:500};
  profile.email='private@example.invalid';
  profile.deviceId='private-device';
  const privateRow=row(profile,'collection');
  const mirrorRow=row(publicProfile(profile,Date.now()),'collection');
  assert.deepEqual(privateRow,mirrorRow);
  assert.equal(privateRow.gamesPlayed,11);
  assert.equal(privateRow.wins,8);
  assert.equal(privateRow.seasonScore,500);
  for(const field of ['email','deviceId','stats','serverSeason','unlockedCards','ledger','gold','gems']){
    assert.equal(Object.hasOwn(privateRow,field),false,field);
  }
});

test('public profile totals cannot be negative, non-finite or lower than wins',function(){
  for(const gamesPlayed of [-5,NaN,Infinity,0,3]){
    const result=row({username:'contract_player',wins:7,gamesPlayed,trophies:10});
    assert.equal(result.gamesPlayed,7);
  }
});

test('public result preserves premium boolean and rejects truthy strings',function(){
  assert.equal(row({username:'contract_player',isPremium:true}).isPremium,true);
  assert.equal(row({username:'contract_player',isPremium:'true'}).isPremium,false);
});

test('collection rows derive active and expired premium from authoritative access',function(){
  const profile=starterProfile('uid-contract','contract_player');
  profile.premiumUntil=Date.now()+60000;
  assert.equal(row(profile,'collection').isPremium,true);
  profile.premiumUntil=Date.now()-60000;
  profile.passState={premium:false};
  assert.equal(row(profile,'collection').isPremium,false);
  profile.passState.premium=true;
  assert.equal(row(profile,'collection').isPremium,false);
});

test('clearing biography and changing username do not resurrect stale public text',function(){
  const profile=starterProfile('uid-contract','current_player');
  profile.name='stale_player';
  profile.usernameRevision=3;
  profile.bio='';
  const result=row(publicProfile(profile,Date.now()));
  assert.equal(result.name,'current_player');
  assert.equal(result.username,'current_player');
  assert.equal(result.usernameRevision,3);
  assert.equal(result.bio,'');
});

test('public output has only the explicit public field allowlist',function(){
  const profile=starterProfile('uid-contract','contract_player');
  profile.password='never-public';
  profile.purchaseTokens=['secret'];
  profile.authProviders=['private'];
  assert.deepEqual(Object.keys(row(profile)).sort(),[
    'uid','name','username','usernameRevision','playerCode','country','avatar',
    'avatarEmoji','bio','photoURL','trophies','collectionScore','seasonScore',
    'wins','arenaIdx','lvl','gamesPlayed','isPremium','dmFriendsOnly','isMe',
  ].sort());
});
