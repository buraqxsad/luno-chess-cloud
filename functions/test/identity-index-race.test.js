'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {getAuth}=require('firebase-admin/auth');
const {starterProfile,playerCode,getPlayerState,createGuestPlayer,deleteAccount,hash,repairPlayerCodeIndex,releaseOwnedIndex}=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');
const uid='identity_player',other='different_player';
function seed(profile=starterProfile(uid,'identity_name')){
  return {users:{[uid]:profile},usernames:{identity_name:uid},playerCodes:{[profile.playerCode.toLowerCase()]:uid}};
}
function context(username='identity_name'){
  return {uid,token:{firebase:{sign_in_provider:'anonymous'}},body:{username},requestId:'identity-'+Math.random()};
}
async function erase(t,db){
  const deleted=[];
  t.mock.method(getAuth(),'deleteUser',async value=>{deleted.push(value);});
  const result=await deleteAccount({...context(),body:{confirm:true}});
  assert.equal(result.deleted,true);assert.deepEqual(deleted,[uid]);
  assert.equal(db.read(`users/${uid}`),null);
}

test('guest creation recovers a colliding player code without overwriting its owner',async t=>{
  const primary=playerCode(uid),db=memoryDatabase(t,{playerCodes:{[primary.toLowerCase()]:other}});
  const result=await createGuestPlayer(context());
  assert.equal(result.created,true);
  const profile=db.read(`users/${uid}`);
  assert.match(profile.playerCode,/^LUNO-[A-F0-9]{8}$/);
  assert.notEqual(profile.playerCode,primary);
  assert.equal(db.read('playerCodes/'+primary.toLowerCase()),other);
  assert.equal(db.read('playerCodes/'+profile.playerCode.toLowerCase()),uid);
  assert.equal(profile.gold,1250);assert.equal(profile.gems,50);
});

test('refresh repairs an existing code collision and keeps earned progress intact',async t=>{
  const profile=starterProfile(uid,'identity_name');profile.gold=8901;profile.stats.wins=17;
  const initial=seed(profile);initial.playerCodes[profile.playerCode.toLowerCase()]=other;
  const db=memoryDatabase(t,initial),result=await getPlayerState({uid});
  assert.notEqual(result.state.profile.playerCode,profile.playerCode);
  assert.equal(result.state.gold,8901);assert.equal(result.state.stats.wins,17);
  assert.equal(db.read('playerCodes/'+profile.playerCode.toLowerCase()),other);
  assert.equal(db.read('playerCodes/'+result.state.profile.playerCode.toLowerCase()),uid);
  assert.equal(db.read(`publicProfiles/${uid}/playerCode`),result.state.profile.playerCode);
});

test('refresh restores a missing code index even when the profile already stores a code',async t=>{
  const initial=seed();initial.playerCodes={};
  const db=memoryDatabase(t,initial),result=await getPlayerState({uid});
  assert.equal(db.read('playerCodes/'+result.state.profile.playerCode.toLowerCase()),uid);
});

test('deleting a malformed legacy profile cannot remove another player identity',async t=>{
  const initial=seed();initial.usernames.identity_name=other;initial.playerCodes[playerCode(uid).toLowerCase()]=other;
  const db=memoryDatabase(t,initial);
  await erase(t,db);
  assert.equal(db.read('usernames/identity_name'),other);
  assert.equal(db.read('playerCodes/'+playerCode(uid).toLowerCase()),other);
});

test('deletion rechecks username ownership after its reservation query',async t=>{
  const db=memoryDatabase(t,seed(),{afterRead(path,count,{write}){
    if(path==='usernames'&&count===1)write('usernames/identity_name',other);
  }});
  await erase(t,db);
  assert.equal(db.read('usernames/identity_name'),other);
});

test('deletion removes all owned code aliases but preserves aliases transferred during cleanup',async t=>{
  const initial=seed();initial.playerCodes['luno-11111111']=uid;initial.playerCodes['luno-22222222']=uid;
  const db=memoryDatabase(t,initial,{afterRead(path,count,{write}){
    if(path==='playerCodes'&&count===1)write('playerCodes/luno-22222222',other);
  }});
  await erase(t,db);
  assert.equal(db.read('playerCodes/luno-11111111'),null);
  assert.equal(db.read('playerCodes/luno-22222222'),other);
  assert.equal(db.read('playerCodes/'+playerCode(uid).toLowerCase()),null);
});

test('deletion retry completes owned-index cleanup after the private profile is already gone',async t=>{
  const initial={usernames:{orphan_name:uid},playerCodes:{'luno-33333333':uid},accountDeletions:{[hash(uid)]:{status:'processing'}},deletedAccounts:{[hash(uid)]:{deletedAt:1}}};
  const db=memoryDatabase(t,initial);
  await erase(t,db);
  assert.equal(db.read('usernames/orphan_name'),null);
  assert.equal(db.read('playerCodes/luno-33333333'),null);
});

test('allocator skips multiple occupied candidates while preserving every existing owner',async t=>{
  const initial=seed(),primary=playerCode(uid),firstFallback=playerCode(uid,1);
  initial.playerCodes[primary.toLowerCase()]=other;initial.playerCodes[firstFallback.toLowerCase()]='third_player';
  const db=memoryDatabase(t,initial),profile=await repairPlayerCodeIndex(uid);
  assert.equal(profile.playerCode,playerCode(uid,2));
  assert.equal(db.read('playerCodes/'+primary.toLowerCase()),other);
  assert.equal(db.read('playerCodes/'+firstFallback.toLowerCase()),'third_player');
});

test('allocator has a bounded retry budget and cannot erase progress on exhaustion',async t=>{
  const initial=seed();initial.users[uid].gold=6789;
  for(let index=0;index<16;index++)initial.playerCodes[playerCode(uid,index).toLowerCase()]=other;
  const db=memoryDatabase(t,initial);
  await assert.rejects(repairPlayerCodeIndex(uid),error=>error.code==='player-code-unavailable'&&error.status===503);
  assert.equal(db.read(`users/${uid}/gold`),6789);
  assert.equal(db.transactions.filter(tx=>tx.path.startsWith('playerCodes/')).length,16);
  assert.ok(Object.values(db.read('playerCodes')).every(owner=>owner===other));
});

test('deletion between code reservation and profile commit removes the orphan reservation',async t=>{
  const initial=seed();initial.playerCodes={};
  const db=memoryDatabase(t,initial,{beforeTransaction(path,count,{write}){
    if(path===`users/${uid}`){write(path,null);write('accountDeletions/'+hash(uid),{status:'processing'});}
  }});
  await assert.rejects(repairPlayerCodeIndex(uid),{code:'profile-not-found'});
  assert.equal(db.read(`users/${uid}`),null);
  assert.equal(db.read('playerCodes/'+playerCode(uid).toLowerCase()),null);
});

test('code repair cannot overwrite a changed profile code or remove its replacement reservation',async t=>{
  const initial=seed();initial.playerCodes[playerCode(uid).toLowerCase()]=other;
  const replacement='LUNO-1234ABCD';
  const db=memoryDatabase(t,initial,{beforeTransaction(path,count,{read,write}){
    if(path!==`users/${uid}`)return;
    const profile=read(path);profile.playerCode=replacement;write(path,profile);write('playerCodes/'+replacement.toLowerCase(),uid);
  }});
  await assert.rejects(repairPlayerCodeIndex(uid),{code:'player-code-state-changed'});
  assert.equal(db.read(`users/${uid}/playerCode`),replacement);
  assert.equal(db.read('playerCodes/'+replacement.toLowerCase()),uid);
  assert.equal(db.read('playerCodes/'+playerCode(uid,1).toLowerCase()),null);
  assert.equal(db.read('playerCodes/'+playerCode(uid).toLowerCase()),other);
});

test('code repair canonicalizes lowercase legacy codes without changing the identity',async t=>{
  const initial=seed(),expected=playerCode(uid);initial.users[uid].playerCode=expected.toLowerCase();
  const db=memoryDatabase(t,initial),profile=await repairPlayerCodeIndex(uid);
  assert.equal(profile.playerCode,expected);assert.equal(db.read('playerCodes/'+expected.toLowerCase()),uid);
});

test('healthy refresh preserves an already owned code without index transactions',async t=>{
  const db=memoryDatabase(t,seed());
  assert.equal((await getPlayerState({uid})).state.profile.playerCode,playerCode(uid));
  assert.ok(!db.transactions.some(tx=>tx.path.startsWith('playerCodes/')));
});

test('code repair fails closed for a mismatched private profile owner',async t=>{
  const initial=seed();initial.users[uid].uid=other;
  const db=memoryDatabase(t,initial);
  await assert.rejects(repairPlayerCodeIndex(uid),{code:'profile-owner-mismatch'});
  assert.equal(db.read(`users/${uid}/uid`),other);
  assert.ok(!db.transactions.some(tx=>tx.path.startsWith('playerCodes/')));
});

test('owned-index cleanup re-evaluates ownership on retry instead of carrying a stale removal decision',async t=>{
  const db=memoryDatabase(t,{usernames:{retry_name:uid}},{retry(path,count,update,next,{write}){
    if(path!=='usernames/retry_name')return next;
    write(path,other);return update(other);
  }});
  const removed=await releaseOwnedIndex(require('firebase-admin/database').getDatabase().ref('usernames/retry_name'),uid);
  assert.equal(removed,false);assert.equal(db.read('usernames/retry_name'),other);
});

test('deletion releases exact owned legacy aliases including uppercase and reserved names',async t=>{
  const initial=seed();Object.assign(initial.usernames,{OLD_ALIAS:uid,admin:uid,'legacy alias':uid});
  const db=memoryDatabase(t,initial);
  await erase(t,db);
  for(const name of ['OLD_ALIAS','admin','legacy alias'])assert.equal(db.read('usernames/'+name),null,name);
});

test('malformed legacy profile code cannot redirect deletion into an unrelated path',async t=>{
  const initial=seed();initial.users[uid].playerCode='../../different-player';initial.playerCodes['legacy_code']=uid;
  const db=memoryDatabase(t,initial);db.write('different-player/protected',other);
  await erase(t,db);
  assert.equal(db.read('different-player/protected'),other);
  assert.equal(db.read('playerCodes/legacy_code'),null);
  assert.equal(db.read('playerCodes/'+playerCode(uid).toLowerCase()),null);
});

test('player-code ownership queries are indexed without granting client writes',()=>{
  const rules=JSON.parse(require('node:fs').readFileSync(require('node:path').join(__dirname,'../../database.rules.production.json'),'utf8')).rules.playerCodes;
  assert.deepEqual(rules['.indexOn'],['.value']);assert.equal(rules['.read'],false);assert.equal(rules['.write'],false);
});

test('invalid legacy code objects are repaired without treating separately read copies as an identity change',async t=>{
  const initial=seed();initial.users[uid].playerCode={legacy:true};initial.users[uid].gold=756;
  const db=memoryDatabase(t,initial),profile=await repairPlayerCodeIndex(uid);
  assert.equal(profile.playerCode,playerCode(uid));assert.equal(profile.gold,756);
  assert.equal(db.read('playerCodes/'+playerCode(uid).toLowerCase()),uid);
});
