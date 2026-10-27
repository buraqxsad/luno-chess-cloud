'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {getDatabase}=require('firebase-admin/database');
const {getPlayerState,createGuestPlayer,reconcileUsernameState,starterProfile,hash,
  withUsernameLock,withSocialPairLock,syncServerPass,publishPlayerCode,playerCode,
  isIncompleteGuestProfile,normalizeLoginActivity,utcDayOrdinal}=require('../index')._test;
const uid='freshness_player';
const copy=value=>value==null?null:structuredClone(value);

function memoryDatabase(t,profile,options={}){
  const data={users:profile?{[uid]:copy(profile)}:{},usernames:{}};
  if(profile&&profile.username)data.usernames[profile.username]=uid;
  const writes=[],transactions=[],reads=new Map();
  function read(path){return path.split('/').filter(Boolean).reduce((value,key)=>value&&value[key],data)??null;}
  function write(path,value){
    const keys=path.split('/').filter(Boolean),leaf=keys.pop();
    let target=data;
    for(const key of keys)target=target[key]||(target[key]={});
    if(value==null)delete target[leaf];else target[leaf]=copy(value);
  }
  function snapshot(value){return {val:()=>copy(value),exists:()=>value!=null,
    numChildren:()=>Object.keys(value||{}).length};}
  function reference(path='',query={}){
    return {
      orderByValue(){return reference(path,{...query,byValue:true});},
      equalTo(value){return reference(path,{...query,equal:value});},
      limitToFirst(limit){return reference(path,{...query,limit});},
      async get(){
        let value=copy(read(path));
        if(query.byValue)value=Object.fromEntries(Object.entries(value||{}).filter(([,owner])=>owner===query.equal).slice(0,query.limit||Infinity));
        const count=(reads.get(path)||0)+1;reads.set(path,count);
        if(options.afterRead)options.afterRead(path,count,{read,write});
        return snapshot(value);
      },
      async transaction(update,onComplete,applyLocally){
        transactions.push({path,applyLocally});
        if(options.beforeTransaction)options.beforeTransaction(path,{read,write,transactions});
        let next;
        if(options.cold!==false){
          next=update(null);
          if(next===undefined)return {committed:false,snapshot:snapshot(null)};
        }
        next=update(copy(read(path)));
        if(options.retry)next=options.retry(path,update,next,{read,write});
        if(next!==undefined){write(path,next);writes.push({path,kind:'transaction',value:copy(next)});}
        return {committed:next!==undefined,snapshot:snapshot(read(path))};
      },
      async set(value){write(path,value);writes.push({path,kind:'set'});},
      async remove(){write(path,null);writes.push({path,kind:'remove'});},
      async update(values){for(const [key,value] of Object.entries(values))write([path,key].filter(Boolean).join('/'),value);writes.push({path,kind:'update'});},
      async push(value){write(path+'/entry',value);},
    };
  }
  t.mock.method(getDatabase(),'ref',reference);
  return {data,read,write,writes,transactions};
}

function normalizedProfile(){
  const profile=starterProfile(uid,'fresh_player');
  syncServerPass(profile,Date.now());
  profile.collectionScore=0;
  return profile;
}
function context(username='fresh_player'){
  return {uid,token:{firebase:{sign_in_provider:'anonymous'}},body:{username},requestId:'guest-'+Math.random()};
}

test('state refresh never creates a partial missing profile through login activity',async t=>{
  const db=memoryDatabase(t,null);
  await assert.rejects(getPlayerState({uid}),{code:'profile-not-found'});
  assert.equal(db.read('users/'+uid),null);
});

test('state normalization preserves a concurrently purchased premium Pass and claimed reward',async t=>{
  const profile=normalizedProfile();profile.passState.seasonKey='old-season';
  const db=memoryDatabase(t,profile,{afterRead(path,count,{read,write}){
    if(path!==`users/${uid}`||count!==1)return;
    const latest=copy(read(path));syncServerPass(latest,Date.now());
    latest.passState.premium=true;latest.passState.level=12;latest.passState.claimed.premium={3:true};
    latest.gold=9876;write(path,latest);
  }});
  const result=await getPlayerState({uid});
  assert.equal(result.state.passState.premium,true);
  assert.equal(result.state.passState.level,12);
  assert.equal(db.read(`users/${uid}/passState/claimed/premium/3`),true);
  assert.equal(result.state.gold,9876);
});

test('state normalization preserves a newly saved deck instead of rewriting an old invalid deck',async t=>{
  const profile=normalizedProfile(),latestDeck=[...profile.deck].reverse();profile.deck=['invalid'];
  const db=memoryDatabase(t,profile,{afterRead(path,count,{read,write}){
    if(path!==`users/${uid}`||count!==1)return;
    const latest=copy(read(path));latest.deck=latestDeck;write(path,latest);
  }});
  const result=await getPlayerState({uid});
  assert.deepEqual(result.state.deck,latestDeck);
  assert.deepEqual(db.read(`users/${uid}/deck`),latestDeck);
});

test('deletion during state refresh cannot recreate the profile with normalizer child writes',async t=>{
  const db=memoryDatabase(t,normalizedProfile(),{afterRead(path,count,{write}){
    if(path===`users/${uid}`&&count===1)write(path,null);
  }});
  await assert.rejects(getPlayerState({uid}),{code:'profile-not-found'});
  assert.equal(db.read(`users/${uid}`),null);
});

test('state refresh writes player normalization only through a non-speculative profile transaction',async t=>{
  const profile=normalizedProfile();delete profile.serverSeason;
  const db=memoryDatabase(t,profile);
  const result=await getPlayerState({uid});
  assert.equal(result.state.uid,uid);
  const playerWrites=db.writes.filter(write=>write.path===`users/${uid}`||write.path.startsWith(`users/${uid}/`));
  assert.ok(playerWrites.length>0);
  assert.ok(playerWrites.every(write=>write.path===`users/${uid}`&&write.kind==='transaction'));
  assert.ok(db.transactions.filter(tx=>tx.path===`users/${uid}`).every(tx=>tx.applyLocally===false));
});

test('username repair reaches the real profile after an initial cold-cache null',async t=>{
  const profile=normalizedProfile();profile.name='Old Display';
  const db=memoryDatabase(t,profile);
  const result=await reconcileUsernameState(uid);
  assert.equal(result.name,'fresh_player');
  assert.equal(db.read(`users/${uid}/name`),'fresh_player');
});

test('username repair cannot return a stale private profile after deletion',async t=>{
  const profile=normalizedProfile();profile.name='Old Display';
  const db=memoryDatabase(t,profile,{beforeTransaction(path,{write}){
    if(path===`users/${uid}`)write(path,null);
  }});
  await assert.rejects(reconcileUsernameState(uid),{code:'profile-not-found'});
  assert.equal(db.read(`users/${uid}`),null);
  assert.equal(db.read('usernames/fresh_player'),null);
  assert.equal(db.read(`publicProfiles/${uid}`),null);
});

test('changed canonical identity cannot be published or have its reservation removed by a stale repair',async t=>{
  const profile=normalizedProfile();profile.name='Old Display';
  const db=memoryDatabase(t,profile,{beforeTransaction(path,{read,write}){
    if(path!==`users/${uid}`)return;
    const latest=copy(read(path));latest.username=latest.name='latest_player';latest.usernameRevision=4;
    write(path,latest);write('usernames/latest_player',uid);
  }});
  await assert.rejects(reconcileUsernameState(uid),{code:'username-state-changed'});
  assert.equal(db.read('usernames/latest_player'),uid);
  assert.equal(db.read('usernames/fresh_player'),null);
  assert.equal(db.read(`users/${uid}/username`),'latest_player');
});

test('existing guest profile repair commits its corrected display name on a cold cache',async t=>{
  const profile=normalizedProfile();profile.name='Old Display';
  const db=memoryDatabase(t,profile);
  const result=await createGuestPlayer(context());
  assert.equal(result.created,false);
  assert.equal(db.read(`users/${uid}/name`),'fresh_player');
});

test('existing guest creation cannot report success for a profile deleted during its repair',async t=>{
  const profile=normalizedProfile();profile.name='Old Display';
  const db=memoryDatabase(t,profile,{beforeTransaction(path,{write}){
    if(path===`users/${uid}`)write(path,null);
  }});
  await assert.rejects(createGuestPlayer(context()),{code:'profile-not-found'});
  assert.equal(db.read('usernames/fresh_player'),null);
});

test('existing guest retry preserves a concurrently changed username',async t=>{
  const db=memoryDatabase(t,normalizedProfile(),{beforeTransaction(path,{read,write}){
    if(path!==`users/${uid}`)return;
    const current=copy(read(path));current.username=current.name='new_owner_name';
    write(path,current);write('usernames/new_owner_name',uid);
  }});
  await assert.rejects(createGuestPlayer(context()),{code:'profile-exists'});
  assert.equal(db.read('usernames/new_owner_name'),uid);
  assert.equal(db.read('usernames/fresh_player'),null);
});

test('legacy normalization-only guest remnants are not treated as a complete account',async t=>{
  const partial={serverActivity:{lastLoginDay:utcDayOrdinal(Date.now()),loginStreak:1},username:'legacy_remnant',name:'legacy_remnant',passState:{level:0}};
  const db=memoryDatabase(t,partial);
  await assert.rejects(getPlayerState({uid}),{code:'profile-not-found'});
  const created=await createGuestPlayer(context());
  assert.equal(created.created,true);
  assert.equal(db.read(`users/${uid}/uid`),uid);
  assert.equal(db.read(`users/${uid}/gold`),starterProfile(uid,'fresh_player').gold);
  assert.equal(db.read(`users/${uid}/serverActivity/loginStreak`),1);
  assert.equal(db.read('usernames/legacy_remnant'),null);
  assert.equal((await getPlayerState({uid})).state.profile.username,'luno_'+hash(uid).slice(0,8));
  assert.equal(db.read(`users/${uid}/usernameGenerated`),true);
});

test('incomplete-profile recovery cannot replace any profile carrying real account or progress data',()=>{
  assert.equal(isIncompleteGuestProfile({serverActivity:{}}),true);
  for(const [key,value] of Object.entries({uid,createdAt:1,gold:1,gems:0,xp:0,trophies:0,stats:{},inventory:{},serverEconomy:{},unlockedCards:{}})){
    assert.equal(isIncompleteGuestProfile({serverActivity:{},[key]:value}),false,key);
  }
  assert.equal(isIncompleteGuestProfile(null),false);
  assert.equal(isIncompleteGuestProfile([]),false);
});

test('a normalization remnant created during refresh is rejected rather than returned as an authenticated player',async t=>{
  const db=memoryDatabase(t,normalizedProfile(),{afterRead(path,count,{write}){
    if(path===`users/${uid}`&&count===1)write(path,{serverActivity:{}});
  }});
  await assert.rejects(getPlayerState({uid}),{code:'profile-not-found'});
  assert.equal(db.read(`users/${uid}/uid`),null);
});

test('login normalization increments once per UTC day and never rolls back a newer request',()=>{
  const at=Date.UTC(2026,9,3,23,59),profile={};
  assert.equal(normalizeLoginActivity(profile,at),true);
  assert.equal(normalizeLoginActivity(profile,at+1000),false);
  assert.equal(profile.serverActivity.loginStreak,1);
  assert.equal(normalizeLoginActivity(profile,at+60000),true);
  assert.equal(profile.serverActivity.loginStreak,2);
  assert.equal(normalizeLoginActivity(profile,at),false);
  assert.equal(profile.serverActivity.lastLoginDay,utcDayOrdinal(at+60000));
  assert.equal(normalizeLoginActivity(profile,at+3*86400000),true);
  assert.equal(profile.serverActivity.loginStreak,1);
});

test('normalizer retry does not publish stale player-code decisions from an uncommitted attempt',async t=>{
  const profile=normalizedProfile();delete profile.playerCode;
  const code='LUNO-1234ABCD';let retried=false;
  const db=memoryDatabase(t,profile,{retry(path,update,next,{write}){
    if(path!==`users/${uid}`||retried)return next;
    retried=true;next.playerCode=code;write(path,next);
    return update(copy(next));
  }});
  const result=await getPlayerState({uid});
  assert.equal(result.state.profile.playerCode,code);
  assert.ok(!db.transactions.some(tx=>tx.path==='playerCodes/'+playerCode(uid).toLowerCase()));
  assert.equal(db.read('playerCodes/'+code.toLowerCase()),uid);
});

test('player-code publication cannot overwrite a different owner',async t=>{
  const db=memoryDatabase(t,null),code=playerCode(uid),path='playerCodes/'+code.toLowerCase();
  db.write(path,'other_player');
  await assert.rejects(publishPlayerCode(uid,code),{code:'player-code-conflict'});
  assert.equal(db.read(path),'other_player');
});

test('player-code publication during deletion removes only its own late index entry',async t=>{
  const db=memoryDatabase(t,null,{beforeTransaction(path,{write}){
    if(path.startsWith('playerCodes/'))write('accountDeletions/'+hash(uid),{status:'processing'});
  }});
  await assert.rejects(publishPlayerCode(uid,playerCode(uid)),{code:'account-deletion-in-progress'});
  assert.equal(db.read('playerCodes/'+playerCode(uid).toLowerCase()),null);
});

test('player-code deletion cleanup preserves a replacement owner',async t=>{
  let gates=0;
  const code=playerCode(uid),path='playerCodes/'+code.toLowerCase();
  const db=memoryDatabase(t,null,{afterRead(readPath,count,{write}){
    if(readPath!=='accountDeletions/'+hash(uid))return;
    if(++gates===2){write(path,'other_player');write('deletedAccounts/'+hash(uid),{deletedAt:1});}
  }});
  await assert.rejects(publishPlayerCode(uid,code),{code:'account-deleted'});
  assert.equal(db.read(path),'other_player');
});

test('guest creation rechecks account deletion after waiting for the username lock',async t=>{
  const db=memoryDatabase(t,null);
  let release,entered;
  const ready=new Promise(resolve=>{entered=resolve;});
  const holding=withUsernameLock(uid,async()=>{entered();await new Promise(resolve=>{release=resolve;});});
  await ready;
  const waiting=createGuestPlayer(context());
  await new Promise(resolve=>setImmediate(resolve));
  db.write('accountDeletions/'+hash(uid),{status:'complete'});
  release();await holding;
  await assert.rejects(waiting,{code:'account-deleted'});
  assert.equal(db.read(`users/${uid}`),null);
  assert.equal(db.read('usernames/fresh_player'),null);
});

for(const [name,run,path] of [
  ['username',operation=>withUsernameLock(uid,operation),`usernameLocks/${uid}`],
  ['social',operation=>withSocialPairLock(uid,'other_player',operation),`socialLocks/${hash([uid,'other_player'].sort().join('|')).slice(0,48)}`],
]){
  for(const emulator of [false,true])test(`${name} lease release is atomic and handles cold cache (${emulator?'emulator':'production'} path)`,async t=>{
    const previous=process.env.FIREBASE_AUTH_EMULATOR_HOST;
    process.env.FIREBASE_AUTH_EMULATOR_HOST=emulator?'127.0.0.1:9099':'';
    t.after(()=>{if(previous===undefined)delete process.env.FIREBASE_AUTH_EMULATOR_HOST;else process.env.FIREBASE_AUTH_EMULATOR_HOST=previous;});
    const db=memoryDatabase(t,null);
    const value=await run(async()=>{assert.ok(db.read(path));return 'done';});
    assert.equal(value,'done');assert.equal(db.read(path),null);
    assert.ok(db.transactions.filter(tx=>tx.path===path).every(tx=>tx.applyLocally===false));
    assert.ok(!db.writes.some(write=>write.path===path&&write.kind==='remove'));
  });
  test(`${name} expired holder cannot release a replacement holder's lease`,async t=>{
    const db=memoryDatabase(t,null);
    await run(async()=>db.write(path,{token:'replacement',expiresAt:Date.now()+60000}));
    assert.equal(db.read(path).token,'replacement');
  });
  test(`${name} operation failure releases its lease without swallowing the failure`,async t=>{
    const db=memoryDatabase(t,null);
    await assert.rejects(run(async()=>{throw new Error('operation-failed');}),/operation-failed/);
    assert.equal(db.read(path),null);
  });
}
