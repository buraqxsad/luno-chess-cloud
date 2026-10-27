'use strict';

const test=require('node:test'),assert=require('node:assert/strict');
const {getDatabase}=require('firebase-admin/database');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const logger=require('firebase-functions/logger');
const {handler,starterProfile,hash}=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');
const self='blocked_self',other='blocked_other';
const copy=value=>value==null?null:structuredClone(value);
const target=index=>'target_'+String(index).padStart(3,'0');
const token=(uid,after,extra={})=>Buffer.from(JSON.stringify({v:1,scope:'blocked-users',uid,after,...extra})).toString('base64url');
function keyCompare(a,b){
  const integer=value=>/^(?:0|[1-9][0-9]*)$/.test(value)&&Number(value)<=2147483647?Number(value):null;
  const left=integer(a),right=integer(b);
  if(left!==null&&right!==null)return left-right;
  if(left!==null)return -1;if(right!==null)return 1;return a<b?-1:a>b?1:0;
}
function setup(t,seed,options={}){
  const queries=[],db=memoryDatabase(t,seed,options),original=getDatabase().ref.bind(getDatabase());
  function ref(path='',query={}){
    const base=original(path);
    return {...base,child:key=>ref([path,key].filter(Boolean).join('/')),
      orderByKey:()=>ref(path,{...query,byKey:true}),startAfter:after=>ref(path,{...query,after}),
      limitToFirst:limit=>query.byKey?ref(path,{...query,limit}):base.limitToFirst(limit),
      async get(){
        const snapshot=await base.get();let value=snapshot.val();
        if(query.byKey){
          queries.push({path,...query});
          let rows=Object.entries(value||{}).sort(([a],[b])=>keyCompare(a,b));
          if(query.after!==undefined)rows=rows.filter(([key])=>keyCompare(key,query.after)>0);
          if(query.limit)rows=rows.slice(0,query.limit);
          value=rows.length?Object.fromEntries(rows):null;
        }
        return {val:()=>copy(value),exists:()=>value!=null,
          forEach(visit){for(const key of Object.keys(value||{}).sort(keyCompare))if(visit({key,val:()=>copy(value[key])})===true)return true;return false;}};
      },
    };
  }
  t.mock.method(getDatabase(),'ref',ref);
  t.mock.method(getAuth(),'verifyIdToken',async uid=>({uid,firebase:{sign_in_provider:'anonymous'}}));
  t.mock.method(getAuth(),'deleteUser',async()=>{});
  t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
  for(const level of ['info','warn','error'])t.mock.method(logger,level,()=>{});
  return {...db,queries};
}
function blockedSeed(count=101){
  const users={[self]:starterProfile(self,'blocked_self'),[other]:starterProfile(other,'blocked_other')},blocks={},publicProfiles={};
  // Deliberately insert backwards; endpoint ordering must come from the query.
  for(let index=count;index>=1;index--){
    const uid=target(index);users[uid]=starterProfile(uid,uid);blocks[uid]={createdAt:index};
    publicProfiles[uid]={username:uid,bio:'PRIVATE_BIO',email:'private@example.com',deck:['PRIVATE_CARD']};
  }
  return {users,publicProfiles,blocks:{[self]:blocks}};
}
async function api(route,body={},uid=self){
  const headers={authorization:'Bearer '+uid,'x-firebase-appcheck':'check','x-luno-request-id':'v215-bounded-'+route,origin:'https://localhost'};
  let status,result;
  await handler({method:'POST',path:'/'+route,body,get:name=>headers[name.toLowerCase()]||''},
    {set(){return this;},status(value){status=value;return this;},json(value){result=value;}});
  return {status,body:result};
}
test('101st existing block is reachable in bounded deterministic pages without mutation',async t=>{
  const data=blockedSeed(),initial=copy(data.blocks),db=setup(t,data),rows=[];let pageToken;
  do{
    const result=await api('listBlockedUsers',pageToken?{pageToken}:{});
    assert.equal(result.status,200,JSON.stringify(result.body));assert.ok(result.body.results.length<=25);
    rows.push(...result.body.results);pageToken=result.body.nextPageToken;
    if(pageToken)assert.ok(pageToken.length<=512);
  }while(pageToken);
  assert.deepEqual(rows.map(row=>row.uid),Array.from({length:101},(_,i)=>target(i+1)));
  assert.deepEqual(db.read('blocks'),initial);
  assert.ok(db.queries.every(query=>query.limit===25||query.limit===1));
  for(const secret of ['PRIVATE_BIO','private@example.com','PRIVATE_CARD'])assert.ok(!JSON.stringify(rows).includes(secret));
});
test('foreign and malformed cursors are rejected before list/rate metadata writes',async t=>{
  const db=setup(t,blockedSeed(1));
  for(const pageToken of [null,123,'','='.repeat(10),'a'.repeat(513),token(other,target(1)),token(self,target(1),{scope:'friends'}),
    token(self,target(1),{extra:true}),token(self,'../private'),Buffer.from('not-json').toString('base64url')]){
    const result=await api('listBlockedUsers',{pageToken});
    assert.equal(result.status,400,JSON.stringify(result.body));assert.equal(result.body.error,'invalid-page-token');
  }
  assert.equal(db.read('serverRateLimits'),null);assert.equal(db.queries.length,0);
});
test('removed cursor edge remains a valid continuation and cannot hide later relationships',async t=>{
  const db=setup(t,blockedSeed(27)),first=await api('listBlockedUsers');
  db.write('blocks/'+self+'/'+target(25),null);
  const next=await api('listBlockedUsers',{pageToken:first.body.nextPageToken});
  assert.equal(next.status,200);assert.deepEqual(next.body.results.map(row=>row.uid),[target(26),target(27)]);
});
test('a fully filtered raw page still advances to live later blocks',async t=>{
  const data=blockedSeed(27);for(let i=1;i<=25;i++)data.blocks[self][target(i)]=i%2===0?false:'invalid-edge';
  setup(t,data);const first=await api('listBlockedUsers');
  assert.equal(first.status,200);assert.deepEqual(first.body.results,[]);assert.ok(first.body.nextPageToken);
  const next=await api('listBlockedUsers',{pageToken:first.body.nextPageToken});
  assert.deepEqual(next.body.results.map(row=>row.uid),[target(26),target(27)]);
});
test('deleted or forged target profile produces removable tombstone, never stale identity',async t=>{
  const data=blockedSeed(3);delete data.users[target(1)];data.users[target(2)].uid=other;
  data.deletedAccounts={[hash(target(3))]:{deletedAt:1}};
  const db=setup(t,data),result=await api('listBlockedUsers');
  assert.equal(result.status,200);assert.equal(result.body.results.length,3);
  for(const row of result.body.results){assert.equal(row.unavailable,true);assert.equal(row.username,'');assert.equal(row.name,'Silinmiş oyuncu');}
  const removed=await api('unblockUser',{targetUid:target(1)});
  assert.equal(removed.status,200);assert.equal(db.read('blocks/'+self+'/'+target(1)),null);
  assert.ok(db.read('blocks/'+self+'/'+target(2)));assert.equal(db.read('users/'+target(1)),null);
});
test('unblock race removes stale row before page response',async t=>{
  const db=setup(t,blockedSeed(2),{afterRead(path,count,{write}){
    if(path==='publicProfiles/'+target(1))write('blocks/'+self+'/'+target(1),null);
  }});
  const result=await api('listBlockedUsers');assert.equal(result.status,200);
  assert.deepEqual(result.body.results.map(row=>row.uid),[target(2)]);assert.ok(db.read('blocks/'+self+'/'+target(2)));
});
test('target deletion during projection is replaced with tombstone at final privacy check',async t=>{
  setup(t,blockedSeed(1),{afterRead(path,count,{write}){
    if(path==='accountDeletions/'+hash(target(1))&&count===2)write('deletedAccounts/'+hash(target(1)),{deletedAt:1});
  }});
  const result=await api('listBlockedUsers');assert.equal(result.status,200);
  assert.equal(result.body.results[0].unavailable,true);assert.equal(result.body.results[0].username,'');
});
test('owner deletion during list read suppresses all page data',async t=>{
  setup(t,blockedSeed(1),{afterRead(path,count,{write}){
    if(path==='publicProfiles/'+target(1))write('accountDeletions/'+hash(self),{status:'processing'});
  }});
  const result=await api('listBlockedUsers');assert.equal(result.status,409);assert.equal(result.body.results,undefined);
});
function telemetrySeed(){
  const day='2026-10-09',owned='a'.repeat(64),foreign='b'.repeat(64);
  return {users:{[self]:starterProfile(self,'blocked_self'),[other]:starterProfile(other,'blocked_other')},
    productTelemetryOwners:{[self]:{[owned]:{day}},[other]:{[foreign]:{day}}},
    productTelemetryDaily:{[day]:{[owned]:{kind:'diagnostics',counts:{safe:1}},[foreign]:{kind:'analytics',counts:{safe:1}}}}};
}
test('actual deleteAccount route purges only owned telemetry under processing marker before user erase',async t=>{
  let purged=0,userErased=0;
  const db=setup(t,telemetrySeed(),{beforeWrite(path,kind,{read,values}){
    if(path===''&&Object.hasOwn(values,'productTelemetryOwners/'+self)){
      assert.equal(read('accountDeletions/'+hash(self)+'/status'),'processing');assert.ok(read('users/'+self));purged++;
    }
    if(path===''&&Object.hasOwn(values,'users/'+self)){
      assert.equal(read('productTelemetryOwners/'+self),null);
      assert.equal(read('productTelemetryDaily/2026-10-09/'+'a'.repeat(64)),null);userErased++;
    }
  }});
  const result=await api('deleteAccount',{confirm:true});assert.equal(result.status,200,JSON.stringify(result.body));
  assert.equal(result.body.deleted,true);assert.equal(purged,1);assert.equal(userErased,1);
  assert.equal(db.read('users/'+self),null);assert.ok(db.read('users/'+other));
  assert.ok(db.read('productTelemetryOwners/'+other));assert.ok(db.read('productTelemetryDaily/2026-10-09/'+'b'.repeat(64)));
});
test('actual deletion purge failure preserves profile and processing marker; retry succeeds',async t=>{
  let fail=true,authDeletes=0;
  const db=setup(t,telemetrySeed(),{beforeWrite(path,kind,{values}){
    if(fail&&path===''&&Object.hasOwn(values,'productTelemetryOwners/'+self))throw new Error('purge-unavailable');
  }});
  t.mock.method(getAuth(),'deleteUser',async()=>{authDeletes++;});
  const first=await api('deleteAccount',{confirm:true});assert.equal(first.status,500);
  assert.ok(db.read('users/'+self));assert.ok(db.read('productTelemetryOwners/'+self));assert.equal(authDeletes,0);
  assert.equal(db.read('accountDeletions/'+hash(self)+'/status'),'processing');
  fail=false;const retry=await api('deleteAccount',{confirm:true});assert.equal(retry.status,200,JSON.stringify(retry.body));
  assert.equal(authDeletes,1);assert.equal(db.read('productTelemetryOwners/'+self),null);assert.equal(db.read('users/'+self),null);
});
test('actual deletion retry after Auth failure safely repeats an already-completed telemetry purge',async t=>{
  const db=setup(t,telemetrySeed());let attempts=0;
  t.mock.method(getAuth(),'deleteUser',async()=>{if(++attempts===1)throw new Error('auth-unavailable');});
  const first=await api('deleteAccount',{confirm:true});assert.equal(first.status,500);
  assert.equal(db.read('users/'+self),null);assert.equal(db.read('productTelemetryOwners/'+self),null);
  const retry=await api('deleteAccount',{confirm:true});assert.equal(retry.status,200,JSON.stringify(retry.body));
  assert.equal(attempts,2);assert.ok(db.read('productTelemetryOwners/'+other));
  assert.equal(db.read('accountDeletions/'+hash(self)+'/status'),'complete');
});
