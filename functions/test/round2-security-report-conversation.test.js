'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const logger=require('firebase-functions/logger');
const {handler,starterProfile,conversationId,LEGAL_TERMS_VERSION,LEGAL_PRIVACY_VERSION,LEGAL_COMMUNITY_VERSION}=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');

// Both are valid Firebase UIDs. The legacy underscore key is not injective,
// including pairs that share one target: AB_A == A_BA, after lexicographic sort.
const reporter='aaaaaa_bbbbbb';
const target='aaaaaa_bbbbbb_aaaaaa';
const actualRecipient='bbbbbb_aaaaaa';
const key=conversationId(reporter,target),messageId='private-message';
function setup(t,members,{from=target,legacy=false}={}){
 const users={};
 for(const [i,uid] of [reporter,target,actualRecipient].entries()){
  users[uid]=starterProfile(uid,'audit_user_'+i);
  users[uid].legalConsent={uid,acceptedAt:1,termsVersion:LEGAL_TERMS_VERSION,privacyVersion:LEGAL_PRIVACY_VERSION,communityVersion:LEGAL_COMMUNITY_VERSION};
 }
 const conversation={msgs:{[messageId]:{from,text:'PRIVATE_OTHER_PAIR_CONTENT',ts:1}}};
 if(!legacy)conversation.members=members;
 const readPaths=[];
 const db=memoryDatabase(t,{users,dm:{[key]:conversation}},{afterRead(path){readPaths.push(path);}});
 db.readPaths=readPaths;
 t.mock.method(getAuth(),'verifyIdToken',async(uid,checkRevoked)=>{
  assert.equal(checkRevoked,true);return {uid};
 });
 t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
 for(const level of ['info','warn','error'])t.mock.method(logger,level,()=>{});
 return db;
}
async function report(id){
 const headers={authorization:'Bearer '+reporter,'x-firebase-appcheck':'local-app-check','x-luno-request-id':id};
 let status,body;
 await handler({method:'POST',path:'/reportMessage',body:{targetUid:target,messageId,reason:'harassment'},get:name=>headers[name.toLowerCase()]||''},
  {set(){return this;},status(code){status=code;return this;},json(value){body=value;}});
 return {status,body};
}
test('reportMessage does not copy another pair private text through a shared-target legacy key collision',async t=>{
 assert.equal(key,conversationId(target,actualRecipient),'The supplied real UID pairs really collide.');
 const db=setup(t,{[target]:true,[actualRecipient]:true});
 const result=await report('round2-collision-report');
 assert.equal(result.status,404,'A caller outside the declared conversation cannot report its private messages.');
 assert.equal(result.body.error,'message-not-found');
 assert.equal(db.read('moderationReports'),null,'Foreign private content must not be retained as this caller\'s moderation report.');
 assert.equal(db.read('dm/'+key+'/msgs/'+messageId+'/text'),'PRIVATE_OTHER_PAIR_CONTENT');
});
test('reportMessage rejects a declared conversation without its target membership',async t=>{
 const db=setup(t,{[reporter]:true,[target]:false});
 const result=await report('round2-false-target-report');
 assert.equal(result.status,404);assert.equal(result.body.error,'message-not-found');
 assert.equal(db.read('moderationReports'),null);
});
test('reportMessage still snapshots an actual received member message',async t=>{
 const db=setup(t,{[reporter]:true,[target]:true});const result=await report('round2-owned-report');
 assert.equal(result.status,200);assert.equal(result.body.reported,true);
 const reports=Object.values(db.read('moderationReports')||{});assert.equal(reports.length,1);
 assert.equal(reports[0].reporterUid,reporter);assert.equal(reports[0].targetUid,target);
 assert.equal(reports[0].messageText,'PRIVATE_OTHER_PAIR_CONTENT');assert.equal(result.body.messageText,undefined);
});
test('reportMessage still rejects an own outgoing message in an owned conversation',async t=>{
 const db=setup(t,{[reporter]:true,[target]:true},{from:reporter});const result=await report('round2-outgoing-report');
 assert.equal(result.status,404);assert.equal(db.read('moderationReports'),null);
});
test('legacy records without a declared member map retain the existing received-message report contract',async t=>{
 const db=setup(t,undefined,{legacy:true});const result=await report('round2-legacy-report');
 assert.equal(result.status,200);assert.equal(Object.values(db.read('moderationReports')||{}).length,1);
});

test('reportMessage reads only members and the selected message, not thread history',async t=>{
 const db=setup(t,{[reporter]:true,[target]:true});const result=await report('round2-bounded-report');
 assert.equal(result.status,200);assert.ok(db.readPaths.includes('dm/'+key+'/members'));
 assert.ok(db.readPaths.includes('dm/'+key+'/msgs/'+messageId));
 assert.equal(db.readPaths.includes('dm/'+key),false,'Reporting one message must never download the entire conversation.');
});
