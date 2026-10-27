'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const {starterProfile,deleteAccount,getPlayerState,handler,hash,writeAccountAudit,writeAccountLinkTicket,releaseAccountLinkTicket,rateLimit}=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');
const uid='metadata_player',other='metadata_other';

function seed(){return {users:{[uid]:starterProfile(uid,'metadata_name')}};}
function tombstone({read,write}){
  write('deletedAccounts/'+hash(uid),{deletedAt:1});
  for(const root of ['users','auditLogs','serverRateLimits','serverRequests'])write(root+'/'+uid,null);
  for(const [key,ticket] of Object.entries(read('accountLinkTickets')||{}))if(ticket.uid===uid)write('accountLinkTickets/'+key,null);
}
async function erase(t){
  t.mock.method(getAuth(),'deleteUser',async()=>{});
  return deleteAccount({uid,token:{firebase:{sign_in_provider:'anonymous'}},body:{confirm:true},requestId:'erase-metadata'});
}
async function api(t,route,body={},id='metadata-request'){
  t.mock.method(getAuth(),'verifyIdToken',async()=>({uid,firebase:{sign_in_provider:'google.com'},firebaseProvider:'google.com',auth_time:Math.floor(Date.now()/1000)}));
  t.mock.method(getAuth(),'getUser',async()=>({providerData:[{providerId:'google.com'}]}));
  t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
  for(const method of ['info','warn','error'])t.mock.method(require('firebase-functions/logger'),method,()=>{});
  const headers={authorization:'Bearer test-token','x-firebase-appcheck':'test-app-check','x-luno-request-id':id,origin:'https://localhost'};
  let status,result;
  await handler({method:'POST',path:'/'+route,body,get:name=>headers[name.toLowerCase()]||''},
    {set(){return this;},status(value){status=value;return this;},json(value){result=value;}});
  return {status,body:result};
}

test('account deletion erases username-bearing audit rows without touching another player',async t=>{
  const data=seed();data.auditLogs={[uid]:{old:{type:'username-changed',oldUsername:'old_name',newUsername:'metadata_name'}},[other]:{keep:{type:'guest-created',username:'other_name'}}};
  const db=memoryDatabase(t,data);
  assert.equal((await erase(t)).deleted,true);
  assert.equal(db.read('auditLogs/'+uid),null);
  assert.equal(db.read('auditLogs/'+other+'/keep/username'),'other_name');
});

test('account deletion erases its link tickets and preserves foreign tickets',async t=>{
  const data=seed();data.accountLinkTickets={owned:{uid,reason:'credential-already-in-use'},foreign:{uid:other,reason:'email-already-in-use'}};
  const db=memoryDatabase(t,data);
  await erase(t);
  assert.equal(db.read('accountLinkTickets/owned'),null);
  assert.equal(db.read('accountLinkTickets/foreign/uid'),other);
});

test('deletion retry erases orphan metadata even after the private profile is gone',async t=>{
  const db=memoryDatabase(t,{accountDeletions:{[hash(uid)]:{status:'processing'}},deletedAccounts:{[hash(uid)]:{deletedAt:1}},auditLogs:{[uid]:{old:{username:'orphan_name'}}},accountLinkTickets:{orphan:{uid}}});
  await erase(t);
  assert.equal(db.read('auditLogs/'+uid),null);assert.equal(db.read('accountLinkTickets/orphan'),null);
  assert.equal(db.read('accountDeletions/'+hash(uid)+'/status'),'complete');
});

test('ticket ownership is rechecked when it changes after the deletion query',async t=>{
  const data=seed();data.accountLinkTickets={moving:{uid,reason:'original'}};
  const db=memoryDatabase(t,data,{afterRead(currentPath,count,{write}){
    if(currentPath==='accountLinkTickets'&&count===1)write('accountLinkTickets/moving',{uid:other,reason:'new-owner'});
  }});
  await erase(t);
  assert.deepEqual(db.read('accountLinkTickets/moving'),{uid:other,reason:'new-owner'});
});

test('metadata is erased before an Auth failure and deletion can resume safely',async t=>{
  const data=seed();data.auditLogs={[uid]:{row:{username:'metadata_name'}}};data.accountLinkTickets={owned:{uid}};
  const db=memoryDatabase(t,data);let attempts=0;
  t.mock.method(getAuth(),'deleteUser',async()=>{if(++attempts===1)throw new Error('auth-unavailable');});
  const context={uid,token:{firebase:{sign_in_provider:'anonymous'}},body:{confirm:true},requestId:'auth-retry'};
  await assert.rejects(deleteAccount(context),/auth-unavailable/);
  assert.equal(db.read('auditLogs/'+uid),null);assert.equal(db.read('accountLinkTickets/owned'),null);
  assert.equal((await deleteAccount(context)).deleted,true);assert.equal(attempts,2);
});

test('Google completion cannot recreate audit metadata after deletion starts',async t=>{
  let raced=false;
  const db=memoryDatabase(t,seed(),{beforeWrite(currentPath,kind,access){
    if(!raced&&currentPath.startsWith('auditLogs/'+uid+'/')){raced=true;tombstone(access);}
  }});
  const result=await api(t,'completeGoogleLink');
  assert.equal(raced,true);assert.equal(result.status,403);assert.equal(result.body.error,'account-deleted');
  assert.equal(db.read('auditLogs/'+uid),null);assert.equal(db.read('serverRequests/'+uid),null);
});

test('Google conflict cannot recreate a link ticket after deletion starts',async t=>{
  let raced=false;
  const db=memoryDatabase(t,seed(),{beforeWrite(currentPath,kind,access){
    if(!raced&&currentPath.startsWith('accountLinkTickets/')){raced=true;tombstone(access);}
  },beforeTransaction(currentPath,count,access){
    if(!raced&&currentPath.startsWith('accountLinkTickets/')){raced=true;tombstone(access);}
  }});
  const result=await api(t,'recordGoogleLinkConflict');
  assert.equal(raced,true);assert.equal(result.status,403);
  assert.ok(!Object.values(db.read('accountLinkTickets')||{}).some(ticket=>ticket.uid===uid));
  assert.equal(db.read('auditLogs/'+uid),null);
});

test('deletion between ticket and audit publication removes both owned records',async t=>{
  let raced=false;
  const db=memoryDatabase(t,seed(),{beforeWrite(currentPath,kind,access){
    if(!raced&&currentPath.startsWith('auditLogs/'+uid+'/')){raced=true;tombstone(access);}
  }});
  const result=await api(t,'recordGoogleLinkConflict');
  assert.equal(result.status,403);
  assert.equal(db.read('auditLogs/'+uid),null);
  assert.ok(!Object.values(db.read('accountLinkTickets')||{}).some(ticket=>ticket.uid===uid));
});

test('a committed audit write with a lost response is cleaned when deletion began',async t=>{
  let raced=false;
  const db=memoryDatabase(t,seed(),{afterWrite(currentPath,kind,access){
    if(!raced&&currentPath.startsWith('auditLogs/'+uid+'/')){
      raced=true;access.write('deletedAccounts/'+hash(uid),{deletedAt:1});throw new Error('write-response-lost');
    }
  }});
  const result=await api(t,'completeGoogleLink');
  assert.equal(raced,true);assert.equal(result.status,403);
  assert.equal(db.read('auditLogs/'+uid),null);
});

test('a rate-limit write racing deletion cannot recreate the deleted bucket',async t=>{
  let raced=false;
  const db=memoryDatabase(t,seed(),{beforeTransaction(currentPath,count,access){
    if(!raced&&currentPath.startsWith('serverRateLimits/'+uid+'/')){raced=true;tombstone(access);}
  }});
  const result=await api(t,'getPlayerState');
  assert.equal(raced,true);assert.equal(result.status,403);
  const buckets=db.read('serverRateLimits/'+uid+'/getPlayerState');
  assert.ok(!buckets||Object.keys(buckets).length===0);
});

test('a completed-deletion account cannot create a rate-limit bucket via a direct operation',async t=>{
  const data=seed();data.deletedAccounts={[hash(uid)]:{deletedAt:1}};
  const db=memoryDatabase(t,data);
  await assert.rejects(getPlayerState({uid}),{code:'account-deleted'});
  assert.equal(db.read('serverRateLimits/'+uid),null);
});

test('Google conflict ticket creation does not replace an unrelated owner',async t=>{
  const id='foreign-ticket',ticketId=hash(`google-conflict:${uid}:${id}`).slice(0,20).toUpperCase();
  const data=seed();data.accountLinkTickets={[ticketId]:{uid:other,status:'open',reason:'keep'}};
  const db=memoryDatabase(t,data),result=await api(t,'recordGoogleLinkConflict',{},id);
  assert.equal(result.status,409);assert.equal(result.body.error,'account-link-ticket-conflict');
  assert.deepEqual(db.read('accountLinkTickets/'+ticketId),{uid:other,status:'open',reason:'keep'});
});

test('healthy Google link completion keeps its audit and durable response',async t=>{
  const db=memoryDatabase(t,seed()),result=await api(t,'completeGoogleLink');
  assert.equal(result.status,200);assert.equal(result.body.linked,true);
  const rows=Object.values(db.read('auditLogs/'+uid)||{});
  assert.equal(rows.length,1);assert.equal(rows[0].type,'google-link-completed');
  assert.equal(db.read('serverRequests/'+uid+'/'+hash('metadata-request').slice(0,48)+'/status'),'complete');
});

test('healthy Google conflict stores a private owned support ticket',async t=>{
  const db=memoryDatabase(t,seed()),result=await api(t,'recordGoogleLinkConflict');
  assert.equal(result.status,200);
  assert.equal(db.read('accountLinkTickets/'+result.body.ticketId+'/uid'),uid);
  assert.equal(Object.values(db.read('auditLogs/'+uid)||{})[0].type,'google-link-conflict');
});

test('link-ticket cleanup has an owner query index without opening client access',()=>{
  const rules=JSON.parse(fs.readFileSync(path.join(__dirname,'../../database.rules.production.json'),'utf8')).rules;
  assert.ok(rules.accountLinkTickets&&rules.accountLinkTickets['.indexOn'].includes('uid'));
  assert.equal(rules.accountLinkTickets['.read'],false);assert.equal(rules.accountLinkTickets['.write'],false);
});

for(const state of ['processing','complete'])test(`audit write is rejected before touching metadata during ${state} deletion`,async t=>{
  const db=memoryDatabase(t,{accountDeletions:{[hash(uid)]:{status:state}}});
  await assert.rejects(writeAccountAudit(uid,{type:'late'},'late-row'),{code:state==='processing'?'account-deletion-in-progress':'account-deleted'});
  assert.equal(db.read('auditLogs/'+uid),null);assert.equal(db.writes.length,0);
});

test('an unrelated audit write failure does not erase an existing account record',async t=>{
  const row={type:'existing'},data=seed();data.auditLogs={[uid]:{fixed:row}};
  const db=memoryDatabase(t,data,{beforeWrite(currentPath){if(currentPath===`auditLogs/${uid}/fixed`)throw new Error('network-failed');}});
  await assert.rejects(writeAccountAudit(uid,{type:'new'},'fixed'),/network-failed/);
  assert.deepEqual(db.read(`auditLogs/${uid}/fixed`),row);
});

test('failed late-audit cleanup surfaces an error rather than reporting success',async t=>{
  let raced=false;
  const db=memoryDatabase(t,seed(),{beforeWrite(currentPath,kind,access){
    if(currentPath===`auditLogs/${uid}/late`&&kind==='set'&&!raced){raced=true;tombstone(access);}
    if(currentPath===`auditLogs/${uid}/late`&&kind==='remove')throw new Error('cleanup-unavailable');
  }});
  await assert.rejects(writeAccountAudit(uid,{type:'late'},'late'),/cleanup-unavailable/);
  assert.ok(db.read(`auditLogs/${uid}/late`));
});

test('ticket cleanup handles cold cache and preserves a changed owner on retry',async t=>{
  const db=memoryDatabase(t,{accountLinkTickets:{changing:{uid}}},{retry(currentPath,count,update,next,{write}){
    if(currentPath==='accountLinkTickets/changing'){write(currentPath,{uid:other,status:'open'});return update({uid:other,status:'open'});}
    return next;
  }});
  assert.equal(await releaseAccountLinkTicket(uid,'changing'),false);
  assert.deepEqual(db.read('accountLinkTickets/changing'),{uid:other,status:'open'});
  assert.equal(db.transactions[0].applyLocally,false);
});

test('late ticket cleanup cannot remove a ticket reassigned to another player',async t=>{
  let raced=false;
  const db=memoryDatabase(t,seed(),{afterTransaction(currentPath,count,{write}){
    if(currentPath==='accountLinkTickets/changed'&&!raced){
      raced=true;write(currentPath,{uid:other,status:'new-owner'});write('deletedAccounts/'+hash(uid),{deletedAt:1});
    }
  }});
  await assert.rejects(writeAccountLinkTicket(uid,'changed',{status:'open'}),{code:'account-deleted'});
  assert.deepEqual(db.read('accountLinkTickets/changed'),{uid:other,status:'new-owner'});
});

test('a ticket committed before a lost response is cleaned after deletion',async t=>{
  let raced=false;
  const db=memoryDatabase(t,seed(),{afterTransaction(currentPath,count,{write}){
    if(currentPath==='accountLinkTickets/lost'&&!raced){raced=true;write('deletedAccounts/'+hash(uid),{deletedAt:1});throw new Error('response-lost');}
  }});
  await assert.rejects(writeAccountLinkTicket(uid,'lost',{status:'open'}),{code:'account-deleted'});
  assert.equal(db.read('accountLinkTickets/lost'),null);
});

test('healthy rate limiting preserves the cap and disables speculative writes',async t=>{
  const db=memoryDatabase(t,seed());
  await rateLimit(uid,'limited-operation',2,60000);await rateLimit(uid,'limited-operation',2,60000);
  await assert.rejects(rateLimit(uid,'limited-operation',2,60000),{code:'rate-limited'});
  const rows=Object.values(db.read(`serverRateLimits/${uid}/limited-operation`));
  assert.deepEqual(rows,[2]);assert.ok(db.transactions.every(tx=>tx.applyLocally===false));
});

for(const value of [-8,'broken'])test(`malformed rate counter ${value} does not bypass normalization`,async t=>{
  t.mock.method(Date,'now',()=>1900000000000);
  const bucket=Math.floor(Date.now()/60000),data=seed();
  data.serverRateLimits={[uid]:{malformed:{[bucket]:value}}};
  const db=memoryDatabase(t,data);await rateLimit(uid,'malformed',2,60000);
  assert.equal(db.read(`serverRateLimits/${uid}/malformed/${bucket}`),1);
});

test('rate-limit completion removes its late bucket even if account deletion was already processing',async t=>{
  let raced=false;
  const db=memoryDatabase(t,seed(),{afterTransaction(currentPath,count,{write}){
    if(currentPath.startsWith(`serverRateLimits/${uid}/`)&&!raced){raced=true;write('accountDeletions/'+hash(uid),{status:'processing'});}
  }});
  await assert.rejects(rateLimit(uid,'ordinary-operation',2,60000),{code:'account-deletion-in-progress'});
  assert.equal(db.read('serverRateLimits/'+uid),null);
});
