'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getDatabase,ServerValue}=require('firebase-admin/database');
const {createHash}=require('node:crypto');
// Intentionally opt-in and isolated. No Auth/Functions or cloud credentials.
const host=process.env.FIREBASE_DATABASE_EMULATOR_HOST;
assert.equal(host,'127.0.0.1:19000');
assert.equal(process.env.GCLOUD_PROJECT,'demo-luno-presence-erasure');
assert.equal(process.env.GOOGLE_APPLICATION_CREDENTIALS,undefined);
const namespace='demo-luno-presence-erasure-default-rtdb';
const databaseURL=`http://${host}?ns=${namespace}`;
let serial=0;const apps=[];const observations=[];
function connection(override){
 const app=initializeApp({projectId:process.env.GCLOUD_PROJECT,databaseURL,...(override===undefined?{}:{databaseAuthVariableOverride:override})},'presence-'+(++serial));
 apps.push(app);return getDatabase(app);
}
const admin=connection();
const owner='presence_owner',other='presence_other';
const uidHash=uid=>createHash('sha256').update(uid).digest('hex');
const valid=()=>({online:true,lastSeen:ServerValue.TIMESTAMP});
async function seed(){
 await admin.ref().set({users:{[owner]:{uid:owner,username:'luno_owner'},[other]:{uid:other,username:'luno_other'}}});
}
const client=connection({uid:owner,token:{sub:owner}}),wrong=connection({uid:other,token:{sub:other}}),guest=connection(null);
async function observe(key){const value=(await admin.ref('presence/'+owner).get()).val();observations.push({case:key,persisted_presence:value});return value;}
async function rejected(work){await assert.rejects(work,e=>/PERMISSION_DENIED|permission.denied/i.test(e.code+' '+e.message));}
async function erased(){await admin.ref().update({['users/'+owner]:null,['presence/'+owner]:null,['deletedAccounts/'+uidHash(owner)]:{deletedAt:Date.now()},['accountDeletions/'+uidHash(owner)]:{status:'complete'}});}
async function waitFor(read,predicate){const deadline=Date.now()+4500;let value;do{value=await read();if(predicate(value))return value;await new Promise(r=>setTimeout(r,80));}while(Date.now()<deadline);return value;}

test('live provisioned owner can write online presence',async()=>{await seed();await client.ref('presence/'+owner).set(valid());const value=await observe('live-owner-write');assert.equal(value.online,true);assert.equal(typeof value.lastSeen,'number');});
test('wrong UID is denied despite having its own live profile (no Admin bypass)',async()=>{await seed();await rejected(wrong.ref('presence/'+owner).set(valid()));assert.equal(await observe('wrong-uid'),null);});
test('unauthenticated SDK connection is denied (no Admin bypass)',async()=>{await seed();await rejected(guest.ref('presence/'+owner).set(valid()));assert.equal(await observe('unauthenticated'),null);});
test('UID without a provisioned profile cannot create presence',async()=>{await seed();await admin.ref('users/'+owner).remove();await rejected(client.ref('presence/'+owner).set(valid()));assert.equal(await observe('unprovisioned'),null);});
test('deleted owner cannot recreate presence through a late set',async()=>{await seed();await client.ref('presence/'+owner).set(valid());await erased();await rejected(client.ref('presence/'+owner).set(valid()));assert.equal(await observe('late-deleted-set'),null);});
test('live owner heartbeat and explicit presence removal keep working',async()=>{await seed();await client.ref('presence/'+owner).set(valid());await client.ref('presence/'+owner).update({lastSeen:ServerValue.TIMESTAMP});await client.ref('presence/'+owner).remove();assert.equal(await observe('live-heartbeat-remove'),null);});
test('future device timestamp remains denied',async()=>{await seed();await rejected(client.ref('presence/'+owner).set({online:true,lastSeen:Date.now()+60000}));assert.equal(await observe('future-timestamp'),null);});
test('malformed online flag remains denied',async()=>{await seed();await rejected(client.ref('presence/'+owner).set({online:'true',lastSeen:ServerValue.TIMESTAMP}));assert.equal(await observe('malformed-online'),null);});
test('missing required presence fields remain denied',async()=>{await seed();await rejected(client.ref('presence/'+owner).set({online:true}));assert.equal(await observe('missing-lastSeen'),null);});
test('new Google/account UID cannot write the old UID presence',async()=>{await seed();await rejected(wrong.ref('presence/'+owner).update({online:false,lastSeen:ServerValue.TIMESTAMP}));assert.equal(await observe('account-switch'),null);});
test('live profile onDisconnect still records offline status',async()=>{
 await seed();const db=connection({uid:owner,token:{sub:owner}}),ref=db.ref('presence/'+owner);
 await ref.set(valid());await ref.onDisconnect().set({online:false,lastSeen:ServerValue.TIMESTAMP});
 db.goOffline();const value=await waitFor(async()=>(await admin.ref('presence/'+owner).get()).val(),v=>v?.online===false);
 observations.push({case:'live-onDisconnect',persisted_presence:value});assert.equal(value?.online,false);
});
test('onDisconnect registered before deletion cannot restore erased presence',async()=>{
 await seed();const db=connection({uid:owner,token:{sub:owner}}),ref=db.ref('presence/'+owner);
 await ref.set(valid());await ref.onDisconnect().set({online:false,lastSeen:ServerValue.TIMESTAMP});await erased();
 db.goOffline();await new Promise(r=>setTimeout(r,800));assert.equal(await observe('deleted-onDisconnect'),null);
});
test.after(async()=>{
 if(process.argv[2])fs.writeFileSync(process.argv[2],JSON.stringify(observations,null,2)+'\n');
 await Promise.all(apps.map(deleteApp));
});
