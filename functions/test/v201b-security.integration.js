'use strict';
const {authHost,databaseHost}=require('./helpers/local-emulators').requireLocalEmulators();
const assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getDatabase}=require('firebase-admin/database');
const namespace='demo-luno-v201b-default-rtdb';
const app=initializeApp({projectId:'demo-luno-v201b',databaseURL:`http://${databaseHost}?ns=${namespace}`},'v201b-security');
const db=getDatabase(app);let allowed=0,denied=0;
async function user(){const r=await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-key`,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({returnSecureToken:true})});assert.equal(r.status,200);return r.json();}
async function check(path,u,allow,method='GET'){
 const r=await fetch(`http://${databaseHost}/${path}.json?ns=${namespace}&auth=${encodeURIComponent(u.idToken)}`,{method,headers:{'content-type':'application/json'},signal:AbortSignal.timeout(15000),...(method==='PUT'?{body:JSON.stringify({forged:true})}:{})});
 assert.equal(r.status,allow?200:401,`${method} ${path}: ${await r.text()}`);allow?allowed++:denied++;
}
async function main(){
 const [a,b,c]=await Promise.all([user(),user(),user()]),id='bv1_'+'1'.repeat(32);
 for(const u of [a,b,c])await db.ref('users/'+u.localId).set({uid:u.localId});
 await db.ref(`matchesV1/${id}`).set({public:{participants:{[a.localId]:true,[b.localId]:true},stateVersion:0},private:{[a.localId]:{handJson:'["radar"]',knowledgeJson:'{}',stateVersion:0},[b.localId]:{handJson:'["freeze"]',knowledgeJson:'{}',stateVersion:0}}});
 await db.ref(`matchSecretsV1/${id}`).set({recordJson:JSON.stringify({decks:{[a.localId]:['mine'],[b.localId]:['fog']}})});
 for(const u of [a,b]){await check(`matchesV1/${id}/public`,u,true);await check(`matchesV1/${id}/private/${u.localId}`,u,true);}
 await check(`matchesV1/${id}/private/${b.localId}`,a,false);await check(`matchesV1/${id}/private/${a.localId}`,b,false);
 await check(`matchesV1/${id}/public`,c,false);
 for(const u of [a,b,c])for(const p of [`matchSecretsV1/${id}`,`matchSecretsV1/${id}/recordJson`,`matchSecretsV1/${id}/decks/${u.localId}`,`matchesV1/${id}`,`matchesV1/${id}/private`])await check(p,u,false);
 for(const u of [a,b,c])for(const p of [`matchesV1/${id}/public`,`matchesV1/${id}/private/${u.localId}`,`matchSecretsV1/${id}`,'battleRollout/config','battleRollout/status','battleV1Control','battleV1Accounts/'+u.localId,'battleV1Ratings/'+u.localId])await check(p,u,false,'PUT');
 await db.ref(`matchesV1/${id}`).remove();await db.ref(`matchSecretsV1/${id}`).remove();
 const result={gate:1,namespace,allowed,denied,pass:true};
 require('node:fs').writeFileSync(require('node:path').join(__dirname,'../../luno_chess/qa/v201b-gate1-security.json'),JSON.stringify(result,null,2));
 console.log(JSON.stringify(result));
}
main().finally(()=>deleteApp(app)).catch(e=>{console.error(e);process.exitCode=1;});
