'use strict';

const test=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path');
const {getDatabase}=require('firebase-admin/database');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const logger=require('firebase-functions/logger');
const {battleV1RankFromAccount,readBattleV1Rank,PROTOCOL}=require('../lib/battle-v1-public-profile');
const {getPlayerState,getLeaderboard,getPublicPlayerProfile,getPublicPlayerProfiles,getFriends,searchPlayers,
  starterProfile,publicProfile,hash,syncServerPass,playerCode,handler}=require('../index')._test;
const {fixture}=require('./helpers/battle-v1-fixture');
const {authority}=require('../lib/battle-v1');
const self='player_self',other='player_other',third='player_third';
const clone=value=>value==null?null:structuredClone(value);
const account=(uid,rating=0,arenaIdx=0)=>({accountJson:JSON.stringify({migrationVersion:1,rating,
  ratingProfile:{uid,trophies:rating,arenaIdx},entitlements:['secret-card'],ratingSettlements:{secret:'receipt'}})});
const rating=(uid,value)=>({uid,rating:value,games:1,revision:1,protocolVersion:PROTOCOL,name:'stale_name'});
function profile(uid,trophies=1700){
  const p=starterProfile(uid,uid);p.trophies=trophies;p.arenaIdx=5;p.playerCode=playerCode(uid);
  p.collectionScore=0;syncServerPass(p,Date.now());return p;
}
function seed(){
  const users={[self]:profile(self),[other]:profile(other,5000),[third]:profile(third,6000)};
  return {users,publicProfiles:Object.fromEntries(Object.entries(users).map(([uid,p])=>[uid,publicProfile(p,Date.now())])),
    usernames:Object.fromEntries(Object.keys(users).map(uid=>[uid,uid])),
    playerCodes:Object.fromEntries(Object.keys(users).map(uid=>[playerCode(uid).toLowerCase(),uid])),
    battleV1Accounts:{[self]:account(self,32),[other]:account(other,1205,4),[third]:account(third,501,2)},
    battleV1Ratings:{[self]:rating(self,32),[other]:rating(other,1205),[third]:rating(third,501)}};
}

// This bounded fake executes real endpoint/settlement code and records queries;
// no production Firebase or emulator is involved in these unit tests.
function setup(t,data=seed(),afterRead){
  const root=clone(data),writes=[],queries=[],reads=[];
  const read=path=>path.split('/').filter(Boolean).reduce((v,k)=>v&&v[k],root)??null;
  function write(path,value){
    const keys=path.split('/').filter(Boolean),leaf=keys.pop();let node=root;
    for(const key of keys)node=node[key]||(node[key]={});
    if(value==null)delete node[leaf];else node[leaf]=clone(value);
  }
  const keyCompare=(a,b)=>{
    const integer=key=>/^(?:0|[1-9][0-9]*)$/.test(key)&&Number(key)<=2147483647?Number(key):null;
    const first=integer(a),second=integer(b);
    if(first!==null&&second!==null)return first-second;
    if(first!==null)return -1;if(second!==null)return 1;return a<b?-1:a>b?1:0;
  };
  const snap=(value,orderedKeys)=>({val:()=>clone(value),exists:()=>value!=null,numChildren:()=>Object.keys(value||{}).length,
    forEach(visitor){for(const key of orderedKeys||Object.keys(value||{})){if(visitor({key,val:()=>clone(value[key])})===true)return true;}return false;}});
  function ref(path='',query={}){return {
    orderByValue(){return ref(path,{...query,byValue:true});},
    orderByChild(child){return ref(path,{...query,child});},
    orderByKey(){return ref(path,{...query,byKey:true});},
    equalTo(equal){return ref(path,{...query,equal});},
    startAt(start){return ref(path,{...query,start});},endAt(end){return ref(path,{...query,end});},
    startAfter(after){return ref(path,{...query,after});},
    limitToFirst(first){return ref(path,{...query,first});},limitToLast(last){return ref(path,{...query,last});},
    async get(){
      let value=clone(read(path)),orderedKeys;reads.push(path);queries.push({path,...query});
      if(query.byValue||query.child||query.byKey){
        const score=(key,row)=>query.byKey?key:query.byValue?row:row&&row[query.child];
        let rows=Object.entries(value||{}).filter(([key,row])=>
          (!Object.hasOwn(query,'equal')||score(key,row)===query.equal)&&
          (!Object.hasOwn(query,'start')||score(key,row)>=query.start)&&
          (!Object.hasOwn(query,'end')||score(key,row)<=query.end)&&
          (!Object.hasOwn(query,'after')||keyCompare(key,query.after)>0));
        rows.sort((a,b)=>query.byKey?keyCompare(a[0],b[0]):score(a[0],a[1])<score(b[0],b[1])?-1:score(a[0],a[1])>score(b[0],b[1])?1:a[0].localeCompare(b[0]));
        if(query.first)rows=rows.slice(0,query.first);if(query.last)rows=rows.slice(-query.last);
        value=rows.length?Object.fromEntries(rows):null;orderedKeys=rows.map(row=>row[0]);
      }
      if(afterRead)afterRead(path,{root,read,write,reads});return snap(value,orderedKeys);
    },
    async transaction(change){
      change(null);const next=change(clone(read(path)));
      if(next!==undefined){write(path,next);writes.push({path,value:clone(next)});}
      return {committed:next!==undefined,snapshot:snap(read(path))};
    },
    async set(value){write(path,value);writes.push({path,value:clone(value)});},
    async remove(){write(path,null);writes.push({path,value:null});},
    async update(values){for(const [key,value] of Object.entries(values))write([path,key].filter(Boolean).join('/'),value);writes.push({path,value:clone(values)});},
  };}
  t.mock.method(getDatabase(),'ref',ref);
  t.mock.method(getAuth(),'verifyIdToken',async uid=>({uid}));
  t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
  for(const level of ['info','warn','error'])t.mock.method(logger,level,()=>{});
  return {root,read,write,writes,queries,reads};
}
async function api(route,body,uid=self){
  let status,result;const headers={authorization:'Bearer '+uid,'x-firebase-appcheck':'checked',origin:'https://localhost'};
  await handler({method:'POST',path:'/'+route,body,get:name=>headers[name.toLowerCase()]||''},
    {set(){return this;},status(value){status=value;return this;},json(value){result=value;return this;}});
  return {status,body:result};
}
const context=body=>({uid:self,body});

test('missing V1 account starts at zero, never the legacy trophy seed',async t=>{
  const data=seed();delete data.battleV1Accounts[self];const db=setup(t,data);
  const result=await getPlayerState({uid:self});
  assert.deepEqual(result.state.battleV1Rank,{protocolVersion:PROTOCOL,uid:self,trophies:0,arenaIdx:0});
  assert.equal(result.state.trophies,1700);assert.equal(db.read('battleV1Accounts/'+self),null);
  assert.equal(db.read('users/'+self).trophies,1700);
  assert.ok(!db.writes.some(w=>/^battleV1(?:Accounts|Ratings)\//.test(w.path)));
});
test('rank projection is a strict four-field allowlist and uses V1 arena',()=>{
  const projected=battleV1RankFromAccount(other,account(other,1205,4));
  assert.deepEqual(projected,{protocolVersion:PROTOCOL,uid:other,trophies:1205,arenaIdx:4});
  assert.deepEqual(Object.keys(projected).sort(),['arenaIdx','protocolVersion','trophies','uid']);
  assert.deepEqual(battleV1RankFromAccount(self,{accountJson:JSON.stringify({migrationVersion:1,rating:600})}),
    {protocolVersion:PROTOCOL,uid:self,trophies:600,arenaIdx:3});
  assert.equal(battleV1RankFromAccount(self,account(self,1000000000,8)).trophies,1000000000);
});
for(const [label,record] of [
  ['broken JSON',{accountJson:'{' }],['missing JSON',{}],['array',{accountJson:'[]'}],
  ['missing migration',{accountJson:'{"rating":0}'}],
  ['negative',{accountJson:'{"migrationVersion":1,"rating":-1}'}],
  ['fraction',{accountJson:'{"migrationVersion":1,"rating":0.5}'}],
  ['string',{accountJson:'{"migrationVersion":1,"rating":"32"}'}],
  ['overflow',account(self,1000000001,8)],['outer owner',{...account(self),uid:other}],
  ['inner owner',{accountJson:JSON.stringify({migrationVersion:1,rating:0,uid:other})}],
  ['wrong protocol',{accountJson:JSON.stringify({migrationVersion:1,rating:0,protocolVersion:'legacy'})}],
  ['profile owner',account(other)],['inconsistent arena',account(self,300,0)],
  ['profile rating',{accountJson:JSON.stringify({migrationVersion:1,rating:32,ratingProfile:{uid:self,trophies:33,arenaIdx:0}})}],
])test('malformed V1 rank fails safely without invented gifts: '+label,()=>{
  assert.throws(()=>battleV1RankFromAccount(self,record),{code:'battle-v1-rank-unavailable',status:503});
});
test('invalid UID cannot form a rank read path',async()=>{
  let reads=0;await assert.rejects(readBattleV1Rank({ref(){reads++;}},'../foreign'),{code:'battle-v1-rank-unavailable'});
  assert.equal(reads,0);
});
test('V1 leaderboard queries its own rating index and uses current identity',async t=>{
  const data=seed();data.publicProfiles[other].username='old_identity';
  const db=setup(t,data),before=clone(db.root);
  const result=await getLeaderboard(context({mode:'trophies',limit:2,protocolVersion:PROTOCOL}));
  assert.deepEqual(result.results.map(p=>[p.uid,p.trophies,p.arenaIdx]),[[other,1205,4],[third,501,2]]);
  assert.equal(result.results[0].username,other);assert.equal(result.protocolVersion,PROTOCOL);
  assert.ok(db.queries.some(q=>q.path==='battleV1Ratings'&&q.child==='rating'&&q.last===2));
  for(const field of ['users','publicProfiles','battleV1Accounts','battleV1Ratings'])assert.deepEqual(db.root[field],before[field]);
  assert.ok(!JSON.stringify(result).includes('secret-card'));assert.ok(!JSON.stringify(result).includes('receipt'));
});
test('legacy trophy/season calls and optional V1 season call stay historical',async t=>{
  const data=seed();data.publicProfiles[self].seasonScore=900;const db=setup(t,data);
  const legacy=await getLeaderboard(context({mode:'trophies'}));assert.equal(legacy.results[0].uid,third);assert.equal(legacy.results[0].trophies,6000);
  const season=await getLeaderboard(context({mode:'season',protocolVersion:PROTOCOL}));
  assert.equal(season.results[0].uid,self);assert.equal(season.results[0].seasonScore,900);
  assert.equal(Object.hasOwn(season,'protocolVersion'),false);
  assert.equal(db.queries.filter(q=>q.path==='battleV1Ratings').length,0);
});
test('public endpoint and bounded roster batch are active, safe and read-only',async t=>{
  const db=setup(t),before=clone(db.root);
  const one=await getPublicPlayerProfile(context({targetUid:other}));
  assert.deepEqual(one.profile.battleV1Rank,{protocolVersion:PROTOCOL,uid:other,trophies:1205,arenaIdx:4});
  const batch=await getPublicPlayerProfiles(context({targetUids:[third,other],protocolVersion:PROTOCOL}));
  assert.deepEqual(batch.results.map(p=>[p.uid,p.trophies]),[[third,501],[other,1205]]);
  assert.ok(!JSON.stringify({one,batch}).includes('secret-card'));
  assert.deepEqual(db.root.users,before.users);assert.deepEqual(db.root.battleV1Accounts,before.battleV1Accounts);
  assert.ok(db.writes.every(w=>w.path.startsWith('serverRateLimits/')));
  assert.deepEqual((await getPublicPlayerProfiles(context({targetUids:[]}))).results,[]);
});
test('canonical RTDB rating index is present without weakening protected writes',()=>{
  const source=path.resolve(__dirname,'../..'),config=JSON.parse(fs.readFileSync(path.join(source,'firebase.json'),'utf8'));
  assert.equal(config.database.rules,'database.rules.production.json');
  const rules=JSON.parse(fs.readFileSync(path.join(source,config.database.rules),'utf8')).rules;
  assert.deepEqual(rules.battleV1Ratings['.indexOn'],['rating']);
  assert.equal(rules.battleV1Ratings['.write'],false);
  assert.equal(rules.battleV1Accounts.$uid['.write'],false);
  assert.equal(rules.battleV1Accounts.$uid['.read'],'auth != null && auth.uid === $uid');
});
test('runtime private profile fields are stripped from single and batch responses',async t=>{
  const data=seed();Object.assign(data.users[other],{email:'private-mail',password:'private-password',
    deviceId:'private-device',purchaseTokens:['private-token'],deck:['private-deck'],authProviders:['private-provider'],
    photoURL:{privateRuntimePayload:'private-nested-photo'}});
  setup(t,data);const single=await getPublicPlayerProfile(context({targetUid:other}));
  const fields=['uid','name','username','usernameRevision','playerCode','country','avatar','avatarEmoji','bio','photoURL',
    'trophies','collectionScore','seasonScore','wins','arenaIdx','lvl','gamesPlayed','isPremium','dmFriendsOnly','battleV1Rank'];
  assert.deepEqual(Object.keys(single.profile).sort(),fields.sort());
  const batch=await getPublicPlayerProfiles(context({targetUids:[other]}));
  assert.deepEqual(Object.keys(batch.results[0]).sort(),[...fields,'isMe'].sort());
  assert.equal(single.profile.photoURL,null);assert.equal(batch.results[0].photoURL,null);
  for(const marker of ['private-mail','private-password','private-device','private-token','private-deck','private-provider','private-nested-photo','secret-card','receipt']){
    assert.ok(!JSON.stringify({single,batch}).includes(marker),marker);
  }
});
test('friend roster and V1 search share the same active rank projection',async t=>{
  const data=seed();data.friends={[self]:{[other]:true,[third]:true},[other]:{[self]:true}};
  data.presence={[other]:{online:true,lastSeen:45}};setup(t,data);
  const friends=await getFriends(context({protocolVersion:PROTOCOL}));
  assert.deepEqual(friends.results.map(p=>[p.uid,p.trophies]),[[other,1205],[third,501]]);
  assert.equal(friends.results[0].online,true);assert.equal(friends.results[0].lastSeen,45);
  const search=await searchPlayers(context({query:'player_',protocolVersion:PROTOCOL}));
  assert.deepEqual(search.results.map(p=>[p.uid,p.trophies]),[[other,1205],[third,501]]);
  assert.equal(search.results[0].relationship,'friends');
});
test('friend pages expose the 101st accepted relationship without changing saved edges',async t=>{
  const data=seed();data.friends={[self]:{}};
  for(let i=0;i<101;i++){
    const uid='friend_'+String(i).padStart(3,'0');data.users[uid]=profile(uid);
    data.friends[self][uid]=true;
  }
  const db=setup(t,data),before=clone(db.root.friends);
  const result=await getFriends(context({protocolVersion:PROTOCOL}));
  assert.equal(result.results.length,100);assert.equal(result.results[0].uid,'friend_000');
  assert.equal(result.results.at(-1).uid,'friend_099');
  assert.ok(result.results.every(row=>row.trophies===0&&row.arenaIdx===0));
  assert.equal(typeof result.nextPageToken,'string');assert.ok(result.nextPageToken.length<=2048);
  const second=await getFriends(context({protocolVersion:PROTOCOL,pageToken:result.nextPageToken}));
  assert.deepEqual(second.results.map(row=>row.uid),['friend_100']);assert.equal(second.nextPageToken,null);
  assert.ok(db.queries.filter(q=>q.path==='friends/'+self&&q.byKey).every(q=>q.first===100||q.first===1));
  assert.deepEqual(db.root.friends,before);assert.equal(db.read('friends/'+self+'/friend_100'),true);
});
test('friend roster accepts true or record edges, rejects false/string/array/number',async t=>{
  const data=seed();data.friends={[self]:{[other]:true,[third]:{addedAt:1}}};
  for(const [i,value] of [false,'pending',[],1,null].entries()){
    const uid='invalid_friend_'+i;data.users[uid]=profile(uid);data.friends[self][uid]=value;
  }
  const db=setup(t,data),before=clone(db.root.friends),result=await getFriends(context({protocolVersion:PROTOCOL}));
  assert.deepEqual(result.results.map(row=>row.uid),[other,third]);assert.deepEqual(db.root.friends,before);
  assert.ok(!db.reads.some(read=>/^users\/invalid_friend_/.test(read)));
});
test('100 invalid friend edges yield an empty but advancing page',async t=>{
  const data=seed();data.friends={[self]:{[other]:true}};
  for(let i=0;i<100;i++)data.friends[self]['a_invalid_'+String(i).padStart(3,'0')]=false;
  const db=setup(t,data),result=await getFriends(context({protocolVersion:PROTOCOL}));
  assert.deepEqual(result.results,[]);assert.equal(typeof result.nextPageToken,'string');
  const next=await getFriends(context({protocolVersion:PROTOCOL,pageToken:result.nextPageToken}));
  assert.deepEqual(next.results.map(row=>row.uid),[other]);assert.equal(next.nextPageToken,null);
  assert.ok(!db.reads.some(read=>/^users\/a_invalid_/.test(read)));
});
test('blocked and deleted first-page rows do not strand the remaining friend',async t=>{
  const data=seed();data.friends={[self]:{[other]:true}};data.deletedAccounts={};data.blocks={[self]:{}};
  for(let i=0;i<100;i++){
    const uid='a_filtered_'+String(i).padStart(3,'0');data.users[uid]=profile(uid);data.friends[self][uid]=true;
    if(i%2)data.deletedAccounts[hash(uid)]={deletedAt:1};else data.blocks[self][uid]=true;
  }
  const db=setup(t,data),before=clone(db.root.friends);
  const first=await getFriends(context({protocolVersion:PROTOCOL}));
  assert.deepEqual(first.results,[]);assert.equal(typeof first.nextPageToken,'string');
  const second=await getFriends(context({protocolVersion:PROTOCOL,pageToken:first.nextPageToken}));
  assert.deepEqual(second.results.map(row=>row.uid),[other]);assert.equal(second.nextPageToken,null);
  assert.deepEqual(db.root.friends,before);
});
test('friend cursor survives removal of its last scanned edge',async t=>{
  const data=seed();data.friends={[self]:{}};
  for(let i=0;i<101;i++){
    const uid='friend_'+String(i).padStart(3,'0');data.users[uid]=profile(uid);data.friends[self][uid]=true;
  }
  const db=setup(t,data),first=await getFriends(context({protocolVersion:PROTOCOL}));
  db.write('friends/'+self+'/friend_099',null);
  const second=await getFriends(context({protocolVersion:PROTOCOL,pageToken:first.nextPageToken}));
  assert.deepEqual(second.results.map(row=>row.uid),['friend_100']);assert.equal(second.nextPageToken,null);
  assert.equal(db.read('friends/'+self+'/friend_099'),null);
});
test('empty roster and exactly-full final page stop with null token',async t=>{
  const data=seed();data.friends={[self]:{}};const db=setup(t,data);
  const empty=await getFriends(context({protocolVersion:PROTOCOL}));assert.deepEqual(empty.results,[]);assert.equal(empty.nextPageToken,null);
  for(let i=0;i<100;i++){
    const uid='friend_'+String(i).padStart(3,'0');db.write('users/'+uid,profile(uid));db.write('friends/'+self+'/'+uid,true);
  }
  const full=await getFriends(context({protocolVersion:PROTOCOL}));assert.equal(full.results.length,100);assert.equal(full.nextPageToken,null);
});
test('paged roster retains RTDB key order and contains no duplicate rows',async t=>{
  const data=seed();data.friends={[self]:{}};
  const uids=['123456','123457',...Array.from({length:203},(_,i)=>'friend_'+String(i).padStart(3,'0'))];
  for(const uid of [...uids].reverse()){data.users[uid]=profile(uid);data.friends[self][uid]=true;}
  setup(t,data);const collected=[],tokens=new Set();let pageToken;
  for(let i=0;i<4;i++){
    const result=await getFriends(context({protocolVersion:PROTOCOL,...(pageToken?{pageToken}:{})}));
    assert.ok(result.results.length<=100);collected.push(...result.results.map(row=>row.uid));
    if(result.nextPageToken===null)break;
    assert.ok(!tokens.has(result.nextPageToken));tokens.add(result.nextPageToken);pageToken=result.nextPageToken;
  }
  assert.deepEqual(collected,uids);assert.equal(new Set(collected).size,collected.length);assert.equal(tokens.size,2);
});
test('128-character account and friend UIDs generate a supported token beyond 256',async t=>{
  const owner='o'.repeat(128),data=seed();data.users[owner]=profile(owner);data.friends={[owner]:{}};
  const uids=Array.from({length:101},(_,i)=>'f'.repeat(124)+String(i).padStart(4,'0'));
  for(const uid of uids){data.users[uid]=profile(uid);data.friends[owner][uid]=true;}
  setup(t,data);const first=await getFriends({uid:owner,body:{protocolVersion:PROTOCOL}});
  assert.ok(first.nextPageToken.length>256);assert.ok(first.nextPageToken.length<=2048);
  const second=await getFriends({uid:owner,body:{protocolVersion:PROTOCOL,pageToken:first.nextPageToken}});
  assert.deepEqual(second.results.map(row=>row.uid),[uids[100]]);assert.equal(second.nextPageToken,null);
});
const cursorToken=value=>Buffer.from(JSON.stringify(value),'utf8').toString('base64url');
for(const badToken of [
  null,'','not-json','with/slash','=', 'a'.repeat(2049),
  cursorToken({v:1,uid:other,key:third}),cursorToken({v:2,uid:self,key:other}),
  cursorToken({v:1,uid:self,key:'../foreign'}),cursorToken({v:1,uid:self,key:''}),
  cursorToken({v:1,uid:self,key:'friend_\u0000unsafe'}),cursorToken({v:1,uid:self,key:'x'.repeat(769)}),
  cursorToken({v:1,uid:self,key:other,extra:true}),cursorToken({v:1,uid:self}),
])test('invalid or foreign-account friend cursor rejected: '+String(badToken).slice(0,32),async t=>{
  const db=setup(t),result=await api('getFriends',{protocolVersion:PROTOCOL,pageToken:badToken});
  assert.equal(result.status,400);assert.equal(result.body.error,'invalid-page-token');
  assert.deepEqual(db.reads,['accountDeletions/'+hash(self),'deletedAccounts/'+hash(self)]);assert.deepEqual(db.writes,[]);
});
test('well-formed absent cursor is a range position, not proof of a relationship',async t=>{
  const data=seed();data.friends={[self]:{[other]:true,[third]:true}};
  setup(t,data);const token=cursorToken({v:1,uid:self,key:'player_q_missing'});
  const result=await getFriends(context({protocolVersion:PROTOCOL,pageToken:token}));
  assert.deepEqual(result.results.map(row=>row.uid),[third]);assert.equal(result.nextPageToken,null);
});
for(const stage of ['after-rank','after-presence']){
  for(const edge of [false,'pending',null,[]]){
    test('friend race recheck excludes invalid or removed edge: '+stage+' '+JSON.stringify(edge),async t=>{
      const data=seed();data.friends={[self]:{[other]:true}};let mutated=false;
      const db=setup(t,data,(read,current)=>{
        const target=stage==='after-rank'?'battleV1Accounts/'+other:'presence/'+other;
        if(read===target&&!mutated){mutated=true;current.write('friends/'+self+'/'+other,edge);}
      });
      const result=await getFriends(context({protocolVersion:PROTOCOL}));
      assert.equal(mutated,true);assert.deepEqual(result.results,[]);
      assert.deepEqual(db.read('friends/'+self+'/'+other),edge);
      assert.ok(db.writes.every(write=>write.path.startsWith('serverRateLimits/')));
    });
  }
}
test('blocked, deleted, missing and mismatched identity rows do not leak',async t=>{
  const data=seed();data.blocks={[other]:{[self]:true}};data.deletedAccounts={[hash(third)]:{deletedAt:1}};
  const db=setup(t,data);
  assert.deepEqual((await getLeaderboard(context({protocolVersion:PROTOCOL}))).results.map(p=>p.uid),[self]);
  assert.deepEqual((await getPublicPlayerProfiles(context({targetUids:[other,third]}))).results,[]);
  await assert.rejects(getPublicPlayerProfile(context({targetUid:other})),{code:'target-not-found'});
  db.write('blocks/'+other+'/'+self,null);db.write('users/'+other+'/uid',third);
  assert.deepEqual((await getPublicPlayerProfiles(context({targetUids:[other]}))).results,[]);
  db.write('users/'+other+'/uid',other);db.write('publicProfiles/'+other+'/uid',third);
  assert.deepEqual((await getPublicPlayerProfiles(context({targetUids:[other]}))).results,[]);
  db.write('publicProfiles/'+other+'/uid',null);db.write('users/'+other,null);
  assert.deepEqual((await getPublicPlayerProfiles(context({targetUids:[other]}))).results,[]);
});
test('deletion or blocking during rank read is rechecked before publication',async t=>{
  setup(t,seed(),(path,db)=>{if(path==='battleV1Accounts/'+other)db.write('deletedAccounts/'+hash(other),{deletedAt:1});});
  const result=await getPublicPlayerProfiles(context({targetUids:[other,self]}));
  assert.deepEqual(result.results.map(p=>p.uid),[self]);
});
test('batch rechecks earlier rows after later row reads',async t=>{
  setup(t,seed(),(path,db)=>{if(path==='battleV1Accounts/'+third)db.write('blocks/'+self+'/'+other,{at:1});});
  assert.deepEqual((await getPublicPlayerProfiles(context({targetUids:[other,third]}))).results.map(p=>p.uid),[third]);
});
test('a malformed authoritative account never becomes a zero-rank success',async t=>{
  const data=seed();data.battleV1Accounts[other]={accountJson:'broken'};setup(t,data);
  const result=await api('getPublicPlayerProfiles',{targetUids:[other]});
  assert.equal(result.status,503);assert.equal(result.body.error,'battle-v1-rank-unavailable');
});
test('malformed rating-index owner or protocol is excluded',async t=>{
  const data=seed();data.battleV1Ratings[other].uid=third;data.battleV1Ratings[third].protocolVersion='legacy';setup(t,data);
  assert.deepEqual((await getLeaderboard(context({protocolVersion:PROTOCOL}))).results.map(p=>p.uid),[self]);
});
for(const value of ['legacy','LUNO_BATTLE_V1 ',null,1,{version:PROTOCOL}])test('forged protocol permits deletion gate only, no private reads or writes: '+JSON.stringify(value),async t=>{
  const db=setup(t);
  for(const [route,body] of [
    ['getLeaderboard',{mode:'trophies'}],['getPublicPlayerProfile',{targetUid:other}],
    ['getPublicPlayerProfiles',{targetUids:[other]}],['getFriends',{}],['searchPlayers',{query:'player_'}],
  ]){
    const result=await api(route,{...body,protocolVersion:value});
    assert.equal(result.status,400);assert.equal(result.body.error,'INCOMPATIBLE_PROTOCOL');
  }
  assert.deepEqual(db.reads,Array.from({length:5},()=>['accountDeletions/'+hash(self),'deletedAccounts/'+hash(self)]).flat());
  assert.deepEqual(db.writes,[]);
});
for(const targets of [null,'uid',[other,other],['../foreign'],[1],Array.from({length:51},(_,i)=>'player_'+i)])test('batch rejects invalid UID/size/duplicates: '+JSON.stringify(targets),async t=>{
  const db=setup(t),result=await api('getPublicPlayerProfiles',{targetUids:targets});
  assert.equal(result.status,400);assert.equal(result.body.error,'invalid-targets');
  assert.deepEqual(db.reads,['accountDeletions/'+hash(self),'deletedAccounts/'+hash(self)]);assert.deepEqual(db.writes,[]);
});
test('50 distinct roster UIDs use one batch quota and never create missing accounts',async t=>{
  const db=setup(t),targetUids=Array.from({length:50},(_,i)=>'absent_player_'+i);
  const result=await getPublicPlayerProfiles(context({targetUids,protocolVersion:PROTOCOL}));
  assert.deepEqual(result.results,[]);assert.equal(result.protocolVersion,PROTOCOL);
  assert.equal(db.writes.length,1);assert.ok(db.writes[0].path.startsWith('serverRateLimits/'+self+'/'));
  for(const uid of targetUids)assert.equal(db.read('users/'+uid),null);
});
test('real rated V1 settlement updates UI projections but not legacy trophies',async t=>{
  const f=fixture();f.setTime(Date.now());
  f.write('users/'+self,profile(self));f.write('users/'+other,profile(other));
  await f.enable();await f.api.enqueueBattleV1(f.context(self,{client:f.client},'public-rank-first'));
  const paired=await f.api.enqueueBattleV1(f.context(other,{client:f.client},'public-rank-second'));
  const m=await f.api.load(paired.matchId,self),winner=m.players.w.uid;
  const legacyBefore={self:f.read('users/'+self).trophies,other:f.read('users/'+other).trophies};
  await f.api.transact(m.matchId,self,current=>({match:authority.finishMatch(current,{reason:'resign',winner:'w',finishedAt:Date.now()})}));
  await f.api.settle(m.matchId,self);
  assert.equal(f.read('users/'+self).trophies,legacyBefore.self);assert.equal(f.read('users/'+other).trophies,legacyBefore.other);
  const active=JSON.parse(f.read('battleV1Accounts/'+winner).accountJson).rating;assert.ok(active>0);
  const db=setup(t,f.root),accountsBefore=clone(db.root.battleV1Accounts),ratingsBefore=clone(db.root.battleV1Ratings);
  const state=await getPlayerState({uid:winner});assert.equal(state.state.battleV1Rank.trophies,active);
  const list=await getLeaderboard({uid:winner,body:{protocolVersion:PROTOCOL}});
  assert.equal(list.results[0].uid,winner);assert.equal(list.results[0].trophies,active);
  const publicResult=await getPublicPlayerProfile({uid:self,body:{targetUid:winner}});
  assert.equal(publicResult.profile.battleV1Rank.trophies,active);
  assert.deepEqual(db.root.battleV1Accounts,accountsBefore);assert.deepEqual(db.root.battleV1Ratings,ratingsBefore);
  assert.equal(db.read('users/'+self).trophies,legacyBefore.self);assert.equal(db.read('users/'+other).trophies,legacyBefore.other);
});
