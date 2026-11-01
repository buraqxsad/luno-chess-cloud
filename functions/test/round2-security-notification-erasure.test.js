'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const {getDatabase}=require('firebase-admin/database');
const logger=require('firebase-functions/logger');
const {handler,starterProfile,LEGAL_TERMS_VERSION,LEGAL_PRIVACY_VERSION,LEGAL_COMMUNITY_VERSION}=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');
const owner='round2_erased_owner',recipient='round2_notice_peer',other='round2_notice_other';
function setup(t,options={}){
 const users={};
 for(const [i,uid] of [owner,recipient,other].entries()){
  users[uid]=starterProfile(uid,'notice_user_'+i);
  users[uid].legalConsent={uid,acceptedAt:1,termsVersion:LEGAL_TERMS_VERSION,privacyVersion:LEGAL_PRIVACY_VERSION,communityVersion:LEGAL_COMMUNITY_VERSION};
 }
 const unrelated={type:'friend_request',fromUid:other,fromUsername:'notice_user_2',read:false};
 const db=memoryDatabase(t,{users,notifications:{[recipient]:{unrelated}}},options);
 const pages=[];let authDeletes=0;
 t.mock.method(getAuth(),'verifyIdToken',async uid=>({uid,auth_time:Math.floor(Date.now()/1000),firebase:{sign_in_provider:'anonymous'}}));
 t.mock.method(getAuth(),'deleteUser',async()=>{authDeletes++;});
 t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
 for(const level of ['info','warn','error'])t.mock.method(logger,level,()=>{});
 // Real Admin push() is synchronous when allocating a key, unlike the generic
 // async test helper. Keep the production notification's actual push-ID shape.
 const original=getDatabase().ref.bind(getDatabase());let keys=0;
 t.mock.method(getDatabase(),'ref',(path='',...args)=>{
  const node=original(path,...args);
  function wrap(query,meta={}){return {...query,
   orderByKey(){return wrap(query.orderByKey(),{...meta,ordered:true});},
   startAfter(cursor){return wrap(query.startAfter(cursor),{...meta,cursor});},
   limitToFirst(limit){return wrap(query.limitToFirst(limit),{...meta,limit});},
   async get(){
    if(path==='notifications')assert.ok(meta.ordered&&meta.limit>=1&&meta.limit<=5,'Root notification reads must use small ordered recipient pages.');
    const value=await query.get();
    if(path==='notifications'){
     const recipientKeys=[];value.forEach(child=>{recipientKeys.push(child.key);return false;});
     pages.push({...meta,keys:recipientKeys});
    }
    return value;
   },
   push(value){
    if(arguments.length)return query.push(value);
    const key='-round2notice'+String(++keys).padStart(8,'0');
    return {...original([path,key].filter(Boolean).join('/')),key};
   },
  };}
  return wrap(node);
 });
 return {...db,unrelated,pages,get authDeletes(){return authDeletes;}};
}
async function request(uid,route,body,id){
 const headers={authorization:'Bearer '+uid,'x-firebase-appcheck':'local-app-check','x-luno-request-id':id};
 let status,value;
 await handler({method:'POST',path:'/'+route,body,get:name=>headers[name.toLowerCase()]||''},
  {set(){return this;},status(code){status=code;return this;},json(result){value=result;}});
 return {status,body:value};
}
for(const response of ['pending','rejected'])test(`account erasure removes its push-ID friend notifications after ${response}`,async t=>{
 const db=setup(t);
 const sent=await request(owner,'sendFriendRequest',{targetUid:recipient},'round2-notice-send-'+response);
 assert.equal(sent.status,200,JSON.stringify(sent.body));
 const owned=Object.values(db.read('notifications/'+recipient)||{}).filter(n=>n.fromUid===owner);
 assert.equal(owned.length,1,'Actual API emitted one real push-ID notification.');
 assert.equal(owned[0].fromUsername,'notice_user_0');
 if(response==='rejected'){
  const rejected=await request(recipient,'respondFriendRequest',{fromUid:owner,accept:false},'round2-notice-reject');
  assert.equal(rejected.status,200,JSON.stringify(rejected.body));
  assert.equal(db.read('outgoingFriendRequests/'+owner),null);
  assert.equal(db.read('friendRequests/'+recipient+'/'+owner),null);
 }
 const erased=await request(owner,'deleteAccount',{confirm:true},'round2-notice-delete-'+response);
 assert.equal(erased.status,200,JSON.stringify(erased.body));
 assert.equal(db.read('users/'+owner),null);
 const notices=Object.values(db.read('notifications/'+recipient)||{});
 assert.equal(notices.some(n=>n.fromUid===owner),false,'A completed account erasure must not leave the deleted sender UID/name in recipient notifications.');
 assert.deepEqual(db.read('notifications/'+recipient+'/unrelated'),db.unrelated);
});

function seedOrphanNotice(db,uid,key='old'){
 db.write('notifications/'+uid,{[key]:{fromUid:owner,fromName:'notice_user_0',fromUsername:'notice_user_0',message:'Old user identity',ts:1},kept:{fromUid:other,message:'Keep this notice',ts:2}});
}
function assertNoAuthoredNotices(db){
 for(const rows of Object.values(db.read('notifications')||{}))assert.equal(Object.values(rows).some(row=>row.fromUid===owner),false);
}
test('historical orphan recipients span small pages in native numeric-key order without revisiting recipients',async t=>{
 const db=setup(t),uids=['100000','999999','1000000','1000001','2000000','2100000','2147483647','legacy_a','legacy_b','legacy_c','legacy_d','legacy_e','legacy_f'];
 for(const uid of uids)seedOrphanNotice(db,uid);
 const erased=await request(owner,'deleteAccount',{confirm:true},'round2-multi-page-delete');
 assert.equal(erased.status,200,JSON.stringify(erased.body));assertNoAuthoredNotices(db);
 const visited=db.pages.filter(p=>p.limit===5).flatMap(p=>p.keys);
 assert.ok(db.pages.length>=3);assert.equal(visited.length,new Set(visited).size,'The cursor must use SDK child order, not lexicographic sorting.');
 for(const uid of uids){assert.ok(visited.includes(uid));assert.equal(db.read('notifications/'+uid+'/kept/fromUid'),other);}
 assert.equal(db.authDeletes,1);
});
test('a stale notification page cannot remove a replacement owned by another sender',async t=>{
 let changed=false;
 const replacement={fromUid:other,fromName:'Surviving user',message:'Replacement',ts:9};
 const db=setup(t,{afterRead(path,count,ops){
  if(path==='notifications'&&!changed){changed=true;ops.write('notifications/'+recipient+'/old',replacement);}
 }});
 seedOrphanNotice(db,recipient);
 const erased=await request(owner,'deleteAccount',{confirm:true},'round2-replaced-notice-delete');
 assert.equal(erased.status,200,JSON.stringify(erased.body));assert.equal(changed,true);
 assert.deepEqual(db.read('notifications/'+recipient+'/old'),replacement);
});
test('a failed recipient page remains processing and resumes its durable checkpoint',async t=>{
 let fail=true;
 const db=setup(t,{afterRead(path,count){
  if(path==='notifications'&&count===2&&fail){fail=false;const error=new Error('local-notice-page-unavailable');error.status=503;error.code='notice-query-unavailable';throw error;}
 }});
 for(let i=0;i<12;i++)seedOrphanNotice(db,'legacy_recipient_'+String(i).padStart(3,'0'));
 const first=await request(owner,'deleteAccount',{confirm:true},'round2-page-failure');
 assert.equal(first.status,503);assert.notEqual(first.body.deleted,true);
 const state=db.read('accountDeletions/'+require('../index')._test.hash(owner));
 assert.equal(state.status,'processing');assert.equal(state.notificationsErased,undefined);
 assert.equal(typeof state.notificationCursor,'string');assert.equal(db.authDeletes,0);assert.ok(db.read('users/'+owner));
 const checkpoint=state.notificationCursor,previousPages=db.pages.length;
 const retry=await request(owner,'deleteAccount',{confirm:true},'round2-page-failure-retry');
 assert.equal(retry.status,200,JSON.stringify(retry.body));assertNoAuthoredNotices(db);
 assert.equal(db.pages[previousPages].cursor,checkpoint);assert.equal(db.authDeletes,1);
 assert.equal(db.read('accountDeletions/'+require('../index')._test.hash(owner)+'/notificationCursor'),null);
});
test('an invocation budget cannot silently skip the remaining legacy recipients',async t=>{
 const db=setup(t);
 for(let i=0;i<250;i++)seedOrphanNotice(db,'legacy_recipient_'+String(i).padStart(4,'0'));
 let erased=await request(owner,'deleteAccount',{confirm:true},'round2-budget-delete-0');
 assert.equal(erased.status,503);assert.notEqual(erased.body.deleted,true);assert.equal(db.authDeletes,0);
 assert.equal(db.read('accountDeletions/'+require('../index')._test.hash(owner)+'/status'),'processing');
 for(let i=1;i<=10&&erased.status!==200;i++)erased=await request(owner,'deleteAccount',{confirm:true},'round2-budget-delete-'+i);
 assert.equal(erased.status,200,JSON.stringify(erased.body));assertNoAuthoredNotices(db);assert.equal(db.authDeletes,1);
});
test('a social delivery held past completed notification cleanup is erased by its owner-deletion gate',async t=>{
 const db=setup(t),original=getDatabase().ref.bind(getDatabase());let enter,release,held=false;
 const entered=new Promise(resolve=>{enter=resolve;}),resume=new Promise(resolve=>{release=resolve;});
 t.mock.method(getDatabase(),'ref',(path='',...args)=>{
  const node=original(path,...args);
  return {...node,async update(values){
   if(!held&&path===''&&Object.keys(values).some(key=>key.startsWith('notifications/'+recipient+'/')&&values[key]?.fromUid===owner)){
    held=true;enter();await resume;
   }
   return node.update(values);
  }};
 });
 const sending=request(owner,'sendFriendRequest',{targetUid:recipient},'round2-late-notice-send');
 let erased;
 try{
  await entered;erased=await request(owner,'deleteAccount',{confirm:true},'round2-late-notice-delete');
  assert.equal(erased.status,200,JSON.stringify(erased.body));
  assert.equal(db.read('accountDeletions/'+require('../index')._test.hash(owner)+'/notificationsErased'),true);
 }finally{release();}
 const sent=await sending;assert.equal(sent.status,403,JSON.stringify(sent.body));assert.equal(sent.body.error,'account-deleted');
 assertNoAuthoredNotices(db);assert.equal(db.read('outgoingFriendRequests/'+owner),null);assert.equal(db.read('friendRequests/'+recipient+'/'+owner),null);
 assert.deepEqual(db.read('notifications/'+recipient+'/unrelated'),db.unrelated);
});
test('an empty notification tree completes without inventing notices or deleting another account',async t=>{
 const db=setup(t);db.write('notifications',null);
 const erased=await request(owner,'deleteAccount',{confirm:true},'round2-empty-notice-delete');
 assert.equal(erased.status,200,JSON.stringify(erased.body));assert.equal(db.read('notifications'),null);
 assert.ok(db.read('users/'+recipient));assert.ok(db.read('users/'+other));assert.equal(db.authDeletes,1);
});

test('more than three bounded erasure attempts use an owner-only resume budget and finish every recipient',async t=>{
 const db=setup(t);
 for(let i=0;i<610;i++)seedOrphanNotice(db,'legacy_recipient_'+String(i).padStart(4,'0'));
 let attempts=0,result;
 do{
  result=await request(owner,'deleteAccount',{confirm:true},'round2-large-retry-'+attempts++);
  if(result.status!==200){assert.equal(result.status,503,JSON.stringify(result.body));assert.notEqual(result.body.deleted,true);assert.equal(db.authDeletes,0);}
 }while(result.status!==200&&attempts<10);
 assert.equal(result.status,200,JSON.stringify(result.body));assert.ok(attempts>=4);assertNoAuthoredNotices(db);
 const initialRateTransactions=db.transactions.filter(t=>t.path.startsWith('serverRateLimits/'+owner+'/deleteAccount/'));
 const resumePrefix='accountDeletions/'+require('../index')._test.hash(owner)+'/resumeRate/';
 assert.equal(initialRateTransactions.length,1,'Initial-entry3/hour is charged only once.');
 assert.equal(db.transactions.filter(t=>t.path.startsWith(resumePrefix)).length,attempts-1);
 assert.equal(db.read('accountDeletions/'+require('../index')._test.hash(owner)+'/resumeRate'),null,'Completed deletion must remove temporary retry buckets.');
 assert.equal(db.authDeletes,1);
});

for(const committed of [false,true])test(`a cursor-checkpoint failure retries safely without skipping unfinished recipients (committed=${committed})`,async t=>{
 let lost=false;
 const db=setup(t,{beforeWrite(path,kind,ops){
  if(!lost&&path==='accountDeletions/'+require('../index')._test.hash(owner)&&kind==='update'&&typeof ops.values.notificationCursor==='string'){
   lost=true;if(committed)ops.write(path+'/notificationCursor',ops.values.notificationCursor);
   const error=new Error('checkpoint-response-lost');error.status=503;error.code='checkpoint-unavailable';throw error;
  }
 }});
 for(let i=0;i<12;i++)seedOrphanNotice(db,'checkpoint_recipient_'+String(i).padStart(3,'0'));
 const first=await request(owner,'deleteAccount',{confirm:true},'round2-checkpoint-lost');
 assert.equal(lost,true);assert.equal(first.status,503);assert.equal(db.authDeletes,0);
 assert.equal(db.read('accountDeletions/'+require('../index')._test.hash(owner)+'/status'),'processing');
 const retry=await request(owner,'deleteAccount',{confirm:true},'round2-checkpoint-retry');
 assert.equal(retry.status,200,JSON.stringify(retry.body));assertNoAuthoredNotices(db);assert.equal(db.authDeletes,1);
});

test('the initial deletion-entry3/hour limit remains enforced',async t=>{
 const at=Date.UTC(2026,10,1,12);t.mock.method(Date,'now',()=>at);
 const db=setup(t);db.write('serverRateLimits/'+owner+'/deleteAccount/'+Math.floor(at/3600000),3);
 const result=await request(owner,'deleteAccount',{confirm:true},'round2-initial-limit');
 assert.equal(result.status,429);assert.equal(result.body.error,'rate-limited');assert.ok(db.read('users/'+owner));assert.equal(db.authDeletes,0);
});
test('the processing owner resume budget is still bounded at30/minute',async t=>{
 const at=Date.UTC(2026,10,1,12);t.mock.method(Date,'now',()=>at);
 const db=setup(t);db.write('accountDeletions/'+require('../index')._test.hash(owner),{status:'processing'});
 db.write('accountDeletions/'+require('../index')._test.hash(owner)+'/resumeRate/'+Math.floor(at/60000),30);
 const result=await request(owner,'deleteAccount',{confirm:true},'round2-resume-limit');
 assert.equal(result.status,429);assert.equal(result.body.error,'rate-limited');assert.ok(db.read('users/'+owner));assert.equal(db.authDeletes,0);
});

test('Auth cleanup failures cannot reset the durable30/minute resume limit',async t=>{
 const at=Date.UTC(2026,10,1,12);t.mock.method(Date,'now',()=>at);
 const db=setup(t);let authCalls=0;
 t.mock.method(getAuth(),'deleteUser',async()=>{authCalls++;const error=new Error('local-auth-cleanup-unavailable');error.code='auth/internal-error';throw error;});
 for(let i=0;i<=30;i++){
  const failed=await request(owner,'deleteAccount',{confirm:true},'round2-auth-unavailable-'+i);
  assert.equal(failed.status,500,JSON.stringify(failed.body));assert.equal(failed.body.error,'auth/internal-error');assert.notEqual(failed.body.deleted,true);
 }
 assert.equal(authCalls,31,'One entry plus30 permitted resumes reached Auth cleanup.');
 assert.equal(db.read('users/'+owner),null,'The ordinary data-erasure root update already ran, so its rate-limit cleanup cannot undo the resume budget.');
 const limited=await request(owner,'deleteAccount',{confirm:true},'round2-auth-unavailable-limited');
 assert.equal(limited.status,429);assert.equal(limited.body.error,'rate-limited');assert.equal(authCalls,31);
 const state=db.read('accountDeletions/'+require('../index')._test.hash(owner));
 assert.equal(state.status,'processing');assert.equal(state.notificationsErased,true);
 assert.equal(state.resumeRate[Math.floor(at/60000)],30);assertNoAuthoredNotices(db);
});
