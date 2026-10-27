'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const logger=require('firebase-functions/logger');
const {handler,starterProfile,publicProfile,usernameValidationError,LEGAL_TERMS_VERSION,LEGAL_PRIVACY_VERSION,LEGAL_COMMUNITY_VERSION}=require('../index')._test;
const {BIO_MAX_LENGTH,MESSAGE_MAX_LENGTH,normalizeUgcText,safePublicBio}=require('../lib/ugc-safety');
const {memoryDatabase}=require('./helpers/memory-database');
const uid='ugc_player',target='ugc_target';
function consent(owner=uid){return {uid:owner,acceptedAt:1,termsVersion:LEGAL_TERMS_VERSION,privacyVersion:LEGAL_PRIVACY_VERSION,communityVersion:LEGAL_COMMUNITY_VERSION};}
function setup(t,{accepted=true,options={}}={}){
 const first=starterProfile(uid,'ugc_player'),second=starterProfile(target,'ugc_target');
 if(accepted)first.legalConsent=consent();
 const db=memoryDatabase(t,{users:{[uid]:first,[target]:second},usernames:{ugc_player:uid,ugc_target:target}},options);
 t.mock.method(getAuth(),'verifyIdToken',async token=>({uid:token}));
 t.mock.method(getAuth(),'updateUser',async()=>({}));
 t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
 for(const level of ['info','warn','error'])t.mock.method(logger,level,()=>{});
 return db;
}
async function api(path,body={},requestId='ugc-request'){
 const headers={authorization:'Bearer '+uid,'x-firebase-appcheck':'check','x-luno-request-id':requestId,origin:'https://localhost'};
 let status,result;
 await handler({method:'POST',path:'/'+path,body,get:name=>headers[name.toLowerCase()]||''},{set(){return this;},status(value){status=value;return this;},json(value){result=value;}});
 return {status,body:result};
}

for(const [label,value] of [
 ['bidi override','hello\u202Eworld'],['bidi isolate','hello\u2066world'],
 ['zero-width','hello\u200Bworld'],['C1','hello\u0085world'],
 ['control','hello\u0000world'],['markup','<script>x</script>'],
 ['compatibility markup','\uFF1Cscript\uFF1E'],
]){
 test(`UGC refuses ${label} without publishing any biography`,async t=>{
  assert.equal(normalizeUgcText(value,BIO_MAX_LENGTH,{allowEmpty:true}),null);
  const db=setup(t),result=await api('updateProfile',{bio:value});
  assert.equal(result.status,400,JSON.stringify(result.body));
  assert.equal(result.body.error,'invalid-bio');assert.equal(db.read('users/'+uid+'/bio'),'');
  assert.equal(db.read('publicProfiles/'+uid),null);
 });
}
test('biography and DM boundaries use the same bounded whitespace policy',()=>{
 assert.equal(normalizeUgcText('  Merhaba\t\n dünya  ',BIO_MAX_LENGTH,{allowEmpty:true}),'Merhaba dünya');
 assert.equal(normalizeUgcText('👩‍💻 şah ♟',BIO_MAX_LENGTH,{allowEmpty:true}),'👩‍💻 şah ♟');
 assert.equal(normalizeUgcText('x'.repeat(160),BIO_MAX_LENGTH),'x'.repeat(160));
 assert.equal(normalizeUgcText('x'.repeat(161),BIO_MAX_LENGTH),null);
 assert.equal(normalizeUgcText('x'.repeat(500),MESSAGE_MAX_LENGTH),'x'.repeat(500));
 assert.equal(normalizeUgcText('x'.repeat(501),MESSAGE_MAX_LENGTH),null);
 assert.equal(normalizeUgcText(' '.repeat(4097),BIO_MAX_LENGTH,{allowEmpty:true}),null);
});
for(const [path,body] of [['updateProfile',{bio:'New public bio'}],['changeUsername',{username:'new_ugc_name'}],['openDirectMessage',{targetUid:target}],['sendDirectMessage',{targetUid:target,text:'Hello'}]]){
 test(`${path} requires current consent before any UGC mutation`,async t=>{
  const db=setup(t,{accepted:false}),original=structuredClone(db.read('users/'+uid));
  const result=await api(path,body);
  assert.equal(result.status,403,JSON.stringify(result.body));assert.equal(result.body.error,'legal-consent-required');
  assert.deepEqual(db.read('users/'+uid),original);assert.equal(db.read('dm'),null);assert.equal(db.read('dmInbox'),null);
  assert.equal(db.read('usernames/new_ugc_name'),null);
 });
}
test('old terms/privacy acknowledgement without Community Guidelines does not authorize UGC',async t=>{
 const db=setup(t);db.write('users/'+uid+'/legalConsent/communityVersion',null);
 const result=await api('updateProfile',{bio:'No implicit migration'});
 assert.equal(result.status,403);assert.equal(db.read('users/'+uid+'/bio'),'');
});
test('another user acknowledgement cannot authorize profile or conversation creation',async t=>{
 const db=setup(t);db.write('users/'+uid+'/legalConsent',consent(target));
 const result=await api('openDirectMessage',{targetUid:target});
 assert.equal(result.status,403);assert.equal(db.read('dm'),null);
});
test('clearing a bio and choosing non-UGC cosmetics do not require consent',async t=>{
 const db=setup(t,{accepted:false});db.write('users/'+uid+'/bio','Old biography');
 const result=await api('updateProfile',{bio:' ',country:'JP',avatarEmoji:'av_knight'});
 assert.equal(result.status,200,JSON.stringify(result.body));assert.equal(result.body.state.profile.bio,'');
 assert.equal(db.read('users/'+uid+'/bio'),'');
});
test('accepted biography normalization is confirmed and the public mirror matches',async t=>{
 const db=setup(t),result=await api('updateProfile',{bio:'  Tahtada\n\t görüşürüz  '});
 assert.equal(result.status,200,JSON.stringify(result.body));
 assert.equal(result.body.state.profile.bio,'Tahtada görüşürüz');
 assert.equal(db.read('publicProfiles/'+uid+'/bio'),'Tahtada görüşürüz');
});
test('legacy unsafe bio is hidden without destroying the stored source',()=>{
 const profile=starterProfile(uid,'ugc_player');profile.bio='Hello\u202Eworld';
 assert.equal(safePublicBio(profile.bio),'');assert.equal(publicProfile(profile,1).bio,'');
 assert.equal(profile.bio,'Hello\u202Eworld');
});
test('username controls remain invalid even when trim could hide them',()=>{
 for(const value of ['\nplayer','player\t','p\u202Elayer','p\u200Blayer'])assert.equal(usernameValidationError(value),'invalid-username');
 assert.equal(usernameValidationError('  Player_1  '),'');
 assert.equal(usernameValidationError('admin'),'username-not-allowed');
});
test('consent acceptance writes server-owned versions once, with UID-bound evidence',async t=>{
 const db=setup(t,{accepted:false,options:{afterTransaction(path,count,{read,write}){
  if(path==='users/'+uid){const profile=read(path);if(profile?.legalConsent?.acceptedAt?.['.sv']==='timestamp')write(path+'/legalConsent/acceptedAt',Date.now());}
 }}});
 const first=await api('acceptLegalTerms',{},'ugc-accept-1');
 assert.equal(first.status,200,JSON.stringify(first.body));assert.equal(first.body.accepted,true);
 assert.equal(first.body.legalConsent.uid,uid);assert.equal(first.body.legalConsent.communityVersion,LEGAL_COMMUNITY_VERSION);
 const acceptedAt=first.body.legalConsent.acceptedAt;
 const replay=await api('acceptLegalTerms',{},'ugc-accept-2');
 assert.equal(replay.status,200);assert.equal(replay.body.alreadyAccepted,true);assert.equal(replay.body.legalConsent.acceptedAt,acceptedAt);
 assert.equal(db.read('users/'+uid+'/legalConsent/uid'),uid);
 const forged=await api('acceptLegalTerms',{communityVersion:'fake'},'ugc-forge');
 assert.equal(forged.status,400);assert.equal(forged.body.error,'unexpected-field');
});
test('profile transaction rechecks consent after a concurrent change',async t=>{
 const db=setup(t,{options:{beforeTransaction(path,count,{write}){
  if(path==='users/'+uid)write(path+'/legalConsent/communityVersion','community-old');
 }}});
 const result=await api('updateProfile',{bio:'Must not publish'});
 assert.equal(result.status,403);assert.equal(db.read('users/'+uid+'/bio'),'');
});
