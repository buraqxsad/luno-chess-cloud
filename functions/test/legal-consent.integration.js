'use strict';

const {authHost,databaseHost}=require('./helpers/local-emulators').requireLocalEmulators();
const assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getDatabase}=require('firebase-admin/database');

const namespace='luno-chess-default-rtdb';
const adminApp=initializeApp({projectId:'luno-chess',databaseURL:`http://${databaseHost}?ns=${namespace}`},'legal-consent-integration');
const db=getDatabase(adminApp);
const apiModule=require('../index.js')._test;
const handler=apiModule.handler;

async function json(response){
  const body=await response.json().catch(function(){return {};});
  return {status:response.status,body};
}
async function anonymousUser(){
  const response=await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-key`,{
    method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({returnSecureToken:true}),signal:AbortSignal.timeout(15000)
  });
  const result=await json(response);assert.equal(result.status,200,JSON.stringify(result.body));return result.body;
}
async function api(path,token,body,id){
  const headers={authorization:'Bearer '+token,'content-type':'application/json','x-firebase-appcheck':'luno-emulator-app-check','x-luno-request-id':id,origin:'https://localhost'};
  const req={method:'POST',path,body:body||{},get:function(name){return headers[String(name||'').toLowerCase()]||'';}};
  let status=200,responseBody={};
  const res={set:function(){return this;},status:function(value){status=value;return this;},send:function(value){responseBody=value;return this;},json:function(value){responseBody=value;return this;}};
  let timer;
  await Promise.race([
    handler(req,res),
    new Promise(function(_,reject){timer=setTimeout(function(){reject(new Error('API timeout: '+path));},30000);})
  ]).finally(function(){if(timer)clearTimeout(timer);});
  return {status,body:responseBody};
}

async function main(){
  const first=await anonymousUser(),second=await anonymousUser();
  assert.equal((await api('/createGuestPlayer',first.idToken,{username:'legal_first'},'legal-create-1')).status,200);
  assert.equal((await api('/createGuestPlayer',second.idToken,{username:'legal_second'},'legal-create-2')).status,200);

  const safetyReport=await api('/reportUser',first.idToken,{targetUid:second.localId,reason:'spam',details:'consent safety test'},'legal-report-1');
  assert.equal(safetyReport.status,200,JSON.stringify(safetyReport.body));
  const safetyBlock=await api('/blockUser',first.idToken,{targetUid:second.localId},'legal-block-1');
  assert.equal(safetyBlock.status,200,JSON.stringify(safetyBlock.body));
  assert.equal((await api('/unblockUser',first.idToken,{targetUid:second.localId},'legal-unblock-1')).status,200);

  const withoutConsent=await api('/sendDirectMessage',first.idToken,{targetUid:second.localId,text:'blocked before consent'},'legal-dm-1');
  assert.equal(withoutConsent.status,403,JSON.stringify(withoutConsent.body));
  assert.equal(withoutConsent.body.error,'legal-consent-required');
  const localFake=await api('/sendDirectMessage',first.idToken,{targetUid:second.localId,text:'fake',legalConsent:true},'legal-local-fake-1');
  assert.equal(localFake.status,400,JSON.stringify(localFake.body));
  assert.equal(localFake.body.error,'unexpected-field');
  const clientVersions=await api('/acceptLegalTerms',first.idToken,{termsVersion:'client-value',privacyVersion:'client-value'},'legal-forged-version-1');
  assert.equal(clientVersions.status,400,JSON.stringify(clientVersions.body));
  assert.equal(clientVersions.body.error,'unexpected-field');

  const accepted=await api('/acceptLegalTerms',first.idToken,{},'legal-accept-1');
  assert.equal(accepted.status,200,JSON.stringify(accepted.body));
  assert.equal(accepted.body.legalConsent.accepted,true);
  const record=(await db.ref('users/'+first.localId+'/legalConsent').get()).val();
  assert.equal(record.uid,first.localId);
  assert.equal(record.termsVersion,apiModule.LEGAL_TERMS_VERSION);
  assert.equal(record.privacyVersion,apiModule.LEGAL_PRIVACY_VERSION);
  assert.equal(Number.isSafeInteger(record.acceptedAt),true);

  const duplicate=await api('/acceptLegalTerms',first.idToken,{},'legal-accept-2');
  assert.equal(duplicate.status,200,JSON.stringify(duplicate.body));
  assert.equal(duplicate.body.alreadyAccepted,true);
  assert.equal((await db.ref('users/'+first.localId+'/legalConsent/acceptedAt').get()).val(),record.acceptedAt);
  const sent=await api('/sendDirectMessage',first.idToken,{targetUid:second.localId,text:'accepted message'},'legal-dm-2');
  assert.equal(sent.status,200,JSON.stringify(sent.body));

  await db.ref('users/'+first.localId+'/legalConsent').set(Object.assign({},record,{termsVersion:'terms-old'}));
  const oldVersion=await api('/sendDirectMessage',first.idToken,{targetUid:second.localId,text:'old version blocked'},'legal-dm-3');
  assert.equal(oldVersion.status,403,JSON.stringify(oldVersion.body));
  assert.equal(oldVersion.body.error,'legal-consent-required');
  const reaccepted=await api('/acceptLegalTerms',first.idToken,{},'legal-accept-3');
  assert.equal(reaccepted.status,200,JSON.stringify(reaccepted.body));
  assert.equal(reaccepted.body.alreadyAccepted,false);

  const current=(await db.ref('users/'+first.localId+'/legalConsent').get()).val();
  await db.ref('users/'+first.localId+'/legalConsent').set(Object.assign({},current,{uid:second.localId}));
  const anotherUid=await api('/sendDirectMessage',first.idToken,{targetUid:second.localId,text:'copied consent blocked'},'legal-dm-4');
  assert.equal(anotherUid.status,403,JSON.stringify(anotherUid.body));
  assert.equal(anotherUid.body.error,'legal-consent-required');

  console.log('LEGAL CONSENT INTEGRATION PASS');
  await deleteApp(adminApp);
  process.exit(0);
}

main().catch(async function(error){
  console.error(error&&error.stack||error);
  await deleteApp(adminApp).catch(function(){});
  process.exit(1);
});
