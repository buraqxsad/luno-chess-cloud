'use strict';

const test=require('node:test'),assert=require('node:assert/strict');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const logger=require('firebase-functions/logger');
const {handler,hash,starterProfile,LEGAL_TERMS_VERSION,LEGAL_PRIVACY_VERSION,LEGAL_COMMUNITY_VERSION}=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');
const uid='bootstrap_player',other='other_player';
const primary='luno_'+hash(uid).slice(0,8);
const alternate=attempt=>'luno_'+hash(uid+'|username-repair|'+attempt).slice(0,8);
function setup(t,seed={},options={}){
  const db=memoryDatabase(t,seed,options);
  t.mock.method(getAuth(),'verifyIdToken',async token=>({uid:token,firebase:{sign_in_provider:'anonymous'}}));
  t.mock.method(getAuth(),'updateUser',async()=>({}));
  t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
  for(const level of ['info','warn','error'])t.mock.method(logger,level,()=>{});
  return db;
}
async function api(path,body={},requestId='bootstrap-create'){
  const headers={authorization:'Bearer '+uid,'x-firebase-appcheck':'check','x-luno-request-id':requestId,origin:'https://localhost'};
  let status,result;
  await handler({method:'POST',path:'/'+path,body,get:name=>headers[name.toLowerCase()]||''},{set(){return this;},status(value){status=value;return this;},json(value){result=value;}});
  return {status,body:result};
}
function accept(db){
  db.write('users/'+uid+'/legalConsent',{uid,acceptedAt:1,termsVersion:LEGAL_TERMS_VERSION,privacyVersion:LEGAL_PRIVACY_VERSION,communityVersion:LEGAL_COMMUNITY_VERSION});
}

for(const body of [{},{username:'client_chosen'},{username:'admin'},{username:'<script>\u202E'}]){
  test('fresh guest bootstrap uses only a server alias: '+JSON.stringify(body),async t=>{
    const db=setup(t),result=await api('createGuestPlayer',body);
    assert.equal(result.status,200,JSON.stringify(result.body));
    assert.equal(result.body.created,true);assert.equal(result.body.username,primary);
    assert.equal(result.body.usernameGenerated,true);
    assert.equal(db.read('users/'+uid+'/username'),primary);
    assert.equal(db.read('users/'+uid+'/name'),primary);
    assert.equal(db.read('users/'+uid+'/usernameGenerated'),true);
    assert.equal(db.read('users/'+uid+'/legalConsent'),null);
    assert.deepEqual(db.read('usernames'),{[primary]:uid});
    assert.equal(db.read('publicProfiles/'+uid+'/username'),primary);
    assert.equal(db.read('users/'+uid+'/gold'),1250);assert.equal(db.read('users/'+uid+'/gems'),50);
    const state=await api('getPlayerState',{},'bootstrap-state');
    assert.equal(state.status,200);assert.equal(state.body.state.profile.usernameGenerated,true);
  });
}
test('server alias collision uses a deterministic alternate and preserves another owner',async t=>{
  const db=setup(t,{usernames:{[primary]:other}}),result=await api('createGuestPlayer',{});
  assert.equal(result.status,200,JSON.stringify(result.body));
  assert.equal(result.body.username,alternate(0));
  assert.equal(db.read('usernames/'+primary),other);
  assert.equal(db.read('usernames/'+alternate(0)),uid);
});
test('bounded alias exhaustion does not create a partial account or steal a reservation',async t=>{
  const names=[primary,...Array.from({length:15},(_,index)=>alternate(index))];
  const db=setup(t,{usernames:Object.fromEntries(names.map(name=>[name,other]))});
  const result=await api('createGuestPlayer',{});
  assert.equal(result.status,503);assert.equal(result.body.error,'guest-username-unavailable');
  assert.equal(db.read('users/'+uid),null);assert.equal(db.read('publicProfiles/'+uid),null);
  assert.deepEqual(db.read('usernames'),Object.fromEntries(names.map(name=>[name,other])));
});
for(const body of [{},{username:'overwrite_attempt'}]){
  test('existing chosen guest survives bootstrap retry: '+JSON.stringify(body),async t=>{
    const profile=starterProfile(uid,'chosen_player');
    profile.gold=9876;profile.gems=456;profile.stats.wins=21;profile.bio='Existing safe biography';
    const db=setup(t,{users:{[uid]:profile},usernames:{chosen_player:uid},playerCodes:{[profile.playerCode.toLowerCase()]:uid}});
    const result=await api('createGuestPlayer',body);
    assert.equal(result.status,200,JSON.stringify(result.body));assert.equal(result.body.created,false);
    assert.equal(result.body.username,'chosen_player');assert.equal(result.body.usernameGenerated,false);
    assert.deepEqual(db.read('users/'+uid),profile);assert.equal(db.read('usernames/'+primary),null);
  });
}
test('cached bootstrap replay returns a subsequently chosen name without replacing earned data',async t=>{
  const db=setup(t);
  assert.equal((await api('createGuestPlayer',{},'same-create')).status,200);
  accept(db);
  const chosen=await api('changeUsername',{username:'chosen_player'},'chosen-name');
  assert.equal(chosen.status,200,JSON.stringify(chosen.body));assert.equal(chosen.body.cost,0);
  assert.equal(chosen.body.state.profile.usernameGenerated,false);
  assert.equal(db.read('users/'+uid+'/usernameChanges'),0);
  db.write('users/'+uid+'/gold',9988);db.write('users/'+uid+'/stats/wins',24);
  const before=structuredClone(db.read('users/'+uid));
  const replay=await api('createGuestPlayer',{username:'overwrite'},'same-create');
  assert.equal(replay.status,200,JSON.stringify(replay.body));assert.equal(replay.body.idempotent,true);
  assert.equal(replay.body.username,'chosen_player');assert.equal(replay.body.usernameGenerated,false);
  assert.deepEqual(db.read('users/'+uid),before);
  assert.equal(db.read('usernames/'+primary),null);assert.equal(db.read('usernames/chosen_player'),uid);
  const rename=await api('changeUsername',{username:'first_rename'},'first-rename');
  assert.equal(rename.status,200);assert.equal(rename.body.cost,0);
  assert.equal(db.read('users/'+uid+'/usernameChanges'),1);
});
test('explicitly choosing the generated alias still requires consent and then clears generated state',async t=>{
  const db=setup(t);assert.equal((await api('createGuestPlayer')).status,200);
  const refused=await api('changeUsername',{username:primary},'refused-choice');
  assert.equal(refused.status,403);assert.equal(db.read('users/'+uid+'/usernameGenerated'),true);
  accept(db);
  const confirmed=await api('changeUsername',{username:primary},'confirmed-choice');
  assert.equal(confirmed.status,200,JSON.stringify(confirmed.body));
  assert.equal(confirmed.body.state.profile.usernameGenerated,false);
  assert.equal(db.read('users/'+uid+'/usernameGenerated'),false);
  assert.equal(db.read('users/'+uid+'/usernameChanges'),0);
});
test('concurrently inserted complete profile is returned, not replaced by the alias starter profile',async t=>{
  const profile=starterProfile(uid,'race_chosen');profile.gold=7711;profile.stats.wins=33;
  let inserted=false;
  const db=setup(t,{}, {beforeTransaction(path,count,{write}){
    if(path!=='users/'+uid||inserted)return;
    inserted=true;write(path,profile);write('usernames/race_chosen',uid);write('playerCodes/'+profile.playerCode.toLowerCase(),uid);
  }});
  const result=await api('createGuestPlayer');
  assert.equal(result.status,200,JSON.stringify(result.body));assert.equal(result.body.created,false);
  assert.equal(result.body.username,'race_chosen');assert.equal(result.body.usernameGenerated,false);
  assert.deepEqual(db.read('users/'+uid),profile);assert.equal(db.read('usernames/'+primary),null);
});
test('bootstrap never replaces a malformed profile containing earned progress',async t=>{
  const profile={gold:9000,stats:{wins:8},name:'legacy_progress'};
  const db=setup(t,{users:{[uid]:profile}}),result=await api('createGuestPlayer');
  assert.equal(result.status,403);assert.equal(result.body.error,'profile-owner-mismatch');
  assert.deepEqual(db.read('users/'+uid),profile);assert.equal(db.read('usernames'),null);
});
test('rapid duplicated bootstrap requests publish one alias and one starter grant',async t=>{
  const db=setup(t);
  const results=await Promise.all([api('createGuestPlayer',{},'rapid-create'),api('createGuestPlayer',{username:'ignored'},'rapid-create')]);
  assert.ok(results.every(result=>result.status===200),JSON.stringify(results));
  assert.ok(results.some(result=>result.body.idempotent===true));
  assert.deepEqual(db.read('usernames'),{[primary]:uid});assert.equal(db.read('users/'+uid+'/gold'),1250);
  assert.equal(Object.values(db.read('auditLogs/'+uid)||{}).filter(entry=>entry.type==='guest-created').length,1);
});
