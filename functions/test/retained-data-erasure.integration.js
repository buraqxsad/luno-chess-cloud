'use strict';
const {authHost,databaseHost}=require('./helpers/local-emulators').requireLocalEmulators();
const assert=require('node:assert/strict');
const {getApps,deleteApp}=require('firebase-admin/app');
const {getDatabase}=require('firebase-admin/database');
const {getAuth}=require('firebase-admin/auth');
const {handler,hash,PRODUCT_CATALOG}=require('../index')._test;
const db=getDatabase();
async function guest(){
  const response=await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-key`,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({returnSecureToken:true}),signal:AbortSignal.timeout(15000)});
  const result=await response.json();assert.equal(response.status,200,JSON.stringify(result));return result;
}
async function api(user,route,body,id){
  const headers={authorization:'Bearer '+user.idToken,'x-firebase-appcheck':'luno-emulator-app-check','x-luno-request-id':id,origin:'https://localhost'};
  let status,result,timer;
  try{await Promise.race([handler({method:'POST',path:'/'+route,body,get:name=>headers[name.toLowerCase()]||''},{set(){return this;},status(value){status=value;return this;},json(value){result=value;}}),new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('Retained-data API timeout')),45000);})]);}
  finally{clearTimeout(timer);}
  return {status,body:result};
}
async function main(){
  const first=await guest(),other=await guest(),uid=first.localId,otherUid=other.localId,suffix=Date.now().toString(36),productId=Object.keys(PRODUCT_CATALOG).find(key=>PRODUCT_CATALOG[key].type==='inapp');
  for(const [user,name] of [[first,'ret_'+suffix],[other,'ret2_'+suffix]])assert.equal((await api(user,'createGuestPlayer',{username:name},'create-'+name)).status,200);
  const ownedKey=hash('owned-'+suffix),raceKey=hash('race-'+suffix),foreignKey=hash('foreign-'+suffix),reportKey='rp_'+hash(suffix).slice(0,30);
  const owned={uid,productId,status:'complete',kind:'inapp',active:true,grantGold:5000,grantGems:0,verifiedAt:Date.now(),email:'private@example.com',purchaseToken:'private-token',lastError:'private@example.com in provider error'};
  const foreign={...owned,uid:otherUid,privateOwnerNote:'must-stay'};
  await db.ref('purchaseClaims').update({[ownedKey]:owned,[raceKey]:owned,[foreignKey]:foreign});
  await db.ref('moderationReports/'+reportKey).set({reportId:reportKey,reporterUid:uid,targetUid:otherUid,reason:'harassment',status:'open',createdAt:Date.now(),conversationId:[uid,otherUid].sort().join('_'),messageText:'private@example.com',details:'private-token',messageId:'message-1'});
  const original=db.ref.bind(db);let ready,release,held=false;
  const entered=new Promise(resolve=>{ready=resolve;}),resume=new Promise(resolve=>{release=resolve;});
  db.ref=function(path){const ref=original(path);if(path==='purchaseClaims/'+raceKey){const tx=ref.transaction.bind(ref);ref.transaction=async function(...args){assert.equal(args[2],false);if(!held){held=true;ready();await resume;}return tx(...args);};}return ref;};
  let result;
  try{
    const pending=api(first,'deleteAccount',{confirm:true},'delete-'+suffix);await entered;
    await original('purchaseClaims/'+raceKey).set(foreign);release();result=await pending;
  }finally{release();db.ref=original;}
  assert.equal(result.status,200,JSON.stringify(result));assert.equal(result.body.deleted,true);
  const retained=(await db.ref('purchaseClaims/'+ownedKey).get()).val();
  assert.equal(retained.uid,hash(uid));assert.equal(retained.accountDeleted,true);assert.equal(retained.active,false);
  for(const field of ['email','purchaseToken','lastError'])assert.equal(retained[field],undefined);
  assert.deepEqual((await db.ref('purchaseClaims/'+raceKey).get()).val(),foreign);
  assert.deepEqual((await db.ref('purchaseClaims/'+foreignKey).get()).val(),foreign);
  const report=(await db.ref('moderationReports/'+reportKey).get()).val();
  assert.equal(report.reporterUid,hash(uid));assert.equal(report.targetUid,otherUid);assert.equal(report.reporterDeleted,true);
  for(const field of ['conversationId','messageText','details','messageId'])assert.equal(report[field],undefined);
  assert.equal((await db.ref('users/'+uid).get()).exists(),false);assert.equal((await db.ref('users/'+otherUid).get()).exists(),true);
  await assert.rejects(getAuth().getUser(uid),{code:'auth/user-not-found'});
  assert.equal((await db.ref('accountDeletions/'+hash(uid)+'/status').get()).val(),'complete');
  console.log('RETAINED_DATA_ERASURE_INTEGRATION_PASS '+JSON.stringify({authDeleted:true,pseudonymousReceipt:true,freeTextRemoved:true,rawConversationRemoved:true,ownerChangedAfterQueryPreserved:true,foreignAccountPreserved:true,databaseHost}));
}
main().catch(error=>{console.error(error);process.exitCode=1;}).finally(async()=>{await Promise.all(getApps().map(deleteApp));});
