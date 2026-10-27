'use strict';
const {authHost,databaseHost}=require('./helpers/local-emulators').requireLocalEmulators();
const assert=require('node:assert/strict');
if(process.env.GCLOUD_PROJECT!=='demo-luno-v201b')throw new Error('Demo project required.');
process.env.LUNO_DB_EMULATOR_NAMESPACE='demo-luno-v201b-default-rtdb';
const namespace=process.env.LUNO_DB_EMULATOR_NAMESPACE;
const {getDatabase}=require('firebase-admin/database');
const {getApps,deleteApp}=require('firebase-admin/app');
const {handler,battleV1,starterProfile,LEGAL_TERMS_VERSION,LEGAL_PRIVACY_VERSION,LEGAL_COMMUNITY_VERSION}=require('../index')._test;
const {protocol}=require('../lib/battle-v1');
const db=getDatabase();let sequence=0;
const counts={allowed:0,denied:0,privateQueueReadsDenied:0,forgedWritesDenied:0};
async function user(){
 const response=await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-key`,{
  method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({returnSecureToken:true}),signal:AbortSignal.timeout(15000),
 });assert.equal(response.status,200);return response.json();
}
async function call(route,u,body={},id){
 const headers={authorization:'Bearer '+u.idToken,'x-firebase-appcheck':'luno-emulator-app-check','x-luno-request-id':id||'v214-social-'+(++sequence),origin:'https://localhost'};
 let status,result;
 await handler({method:'POST',path:'/'+route,body,get:name=>headers[name.toLowerCase()]||''},
  {set(){return this;},status(value){status=value;return this;},json(value){result=value;return this;}});
 return {status,body:result};
}
async function allowed(route,u,body={},id){const r=await call(route,u,body,id);assert.equal(r.status,200,JSON.stringify(r));counts.allowed++;return r.body;}
async function denied(route,u,body,code){const r=await call(route,u,body);assert.equal(r.status,403,JSON.stringify(r));assert.equal(r.body.error,code);counts.denied++;}
async function denyRead(path,u,method='GET'){
 const response=await fetch(`http://${databaseHost}/${path}.json?ns=${namespace}&auth=${encodeURIComponent(u.idToken)}`,{
  method,headers:{'content-type':'application/json'},...(method==='PUT'?{body:'{"forged":true}'}:{}),signal:AbortSignal.timeout(15000),
 });assert.equal(response.status,401,`${method} ${path}: ${await response.text()}`);
 if(method==='GET')counts.privateQueueReadsDenied++;else counts.forgedWritesDenied++;
}
async function main(){
 const users=await Promise.all([user(),user(),user()]),[a,b,c]=users;
 for(const [i,u] of users.entries()){
  const p=starterProfile(u.localId,'qa_safety_'+i);
  p.legalConsent={uid:u.localId,acceptedAt:Date.now(),termsVersion:LEGAL_TERMS_VERSION,privacyVersion:LEGAL_PRIVACY_VERSION,communityVersion:LEGAL_COMMUNITY_VERSION};
  await db.ref('users/'+u.localId).set(p);await battleV1.migrate(u.localId);
 }
 const previousConfig=await battleV1.config();
 const nextVersion=previousConfig.configVersion+1;
 const configured=await battleV1.updateConfig({...protocol.LEGACY_ONLY,configVersion:nextVersion,v1MatchmakingEnabled:true},previousConfig.configVersion);
 assert.equal(configured.configVersion,nextVersion);
 await db.ref('friends/'+a.localId+'/'+b.localId).set(true);
 await db.ref('friends/'+b.localId+'/'+a.localId).set(true);
 const message=await allowed('sendDirectMessage',a,{targetUid:b.localId,text:'Local safety test'});
 const report=await allowed('reportMessage',b,{targetUid:a.localId,messageId:message.messageId,reason:'harassment'},'v214-report-replay');
 const replay=await allowed('reportMessage',b,{targetUid:a.localId,messageId:message.messageId,reason:'harassment'},'v214-report-replay');
 assert.equal(replay.reportId,report.reportId);assert.equal(replay.idempotent,true);
 assert.equal((await db.ref('moderationReports/'+report.reportId).get()).val().messageText,'Local safety test');
 for(const u of users){await denyRead('moderationReports',u);await denyRead('moderationReports/'+report.reportId,u);await denyRead('moderationReports/'+report.reportId,u,'PUT');}
 const client={platform:'android',build:17,protocolVersion:protocol.PROTOCOL};
 await allowed('sendBattleV1Invite',a,{targetUid:b.localId,client});
 const room=await allowed('createBattleV1Room',c,{client});
 await allowed('blockUser',b,{targetUid:a.localId});
 assert.equal((await db.ref('battleV1Control/invites/'+a.localId+'|'+b.localId).get()).exists(),false);
 assert.equal((await db.ref('matchInvites/'+b.localId+'/'+a.localId).get()).exists(),false);
 await denied('sendDirectMessage',a,{targetUid:b.localId,text:'Must be rejected'},'user-blocked');
 await denied('openDirectMessage',a,{targetUid:b.localId},'user-blocked');
 await denied('sendFriendRequest',a,{targetUid:b.localId},'user-blocked');
 await denied('sendBattleV1Invite',a,{targetUid:b.localId,client},'user-blocked');
 await denied('respondBattleV1Invite',b,{fromUid:a.localId,accept:true,client},'user-blocked');
 await allowed('blockUser',a,{targetUid:c.localId});
 await denied('joinBattleV1Room',a,{roomCode:room.roomCode,client},'user-blocked');
 const list=await allowed('listBlockedUsers',b);assert.ok(list.results.some(row=>row.uid===a.localId));
 await denyRead('blocks/'+b.localId+'/'+a.localId,b,'PUT');
 await allowed('unblockUser',b,{targetUid:a.localId});
 assert.equal((await db.ref('friends/'+a.localId+'/'+b.localId).get()).exists(),false);
 await db.ref('users/'+c.localId).remove();
 const deletedList=await allowed('listBlockedUsers',a);assert.equal(deletedList.results.find(row=>row.uid===c.localId).name,'Silinmiş oyuncu');
 await allowed('unblockUser',a,{targetUid:c.localId});
 assert.equal((await db.ref('blocks/'+a.localId+'/'+c.localId).get()).exists(),false);
 assert.equal((await db.ref('users/'+c.localId).get()).exists(),false);
 console.log(JSON.stringify({result:'PASS',project:'demo-luno-v201b',...counts,liveFirebaseTouched:false}));
}
main().then(async()=>{await Promise.all(getApps().map(deleteApp));process.exit(0);}).catch(async error=>{console.error(error);await Promise.all(getApps().map(deleteApp));process.exit(1);});
