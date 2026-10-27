'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {root,projectId,namespace,databaseHost,guardEmulator,bytes,syntheticConversation,profiles,
  request,recordReferences,saveJson}=require('../tools/v220-support.cjs');

const enabled=process.env.V220_DB_INTEGRATION==='1';
const sender='v220_sender',recipient='v220_recipient',outsider='v220_outsider';
const observations=[];

function rulesToken(uid){
  const timestamp=Math.floor(Date.now()/1000);
  const encode=value=>Buffer.from(JSON.stringify(value)).toString('base64url');
  return encode({alg:'none',typ:'JWT'})+'.'+encode({iss:'https://securetoken.google.com/'+projectId,
    aud:projectId,auth_time:timestamp-1,user_id:uid,sub:uid,iat:timestamp-1,exp:timestamp+3600,
    firebase:{sign_in_provider:'custom',identities:{}}})+'.';
}

async function rest(location,options={},uid=null){
  const url=new URL(`http://${databaseHost}/${location}.json`);url.searchParams.set('ns',namespace);
  if(uid)url.searchParams.set('auth',rulesToken(uid));
  const response=await fetch(url,{...options,signal:AbortSignal.timeout(10000)});
  return {status:response.status,body:await response.json()};
}

test('V220 actual isolated RTDB integration (Auth, App Check and Play remain mocked)',
  {skip:!enabled,timeout:150000},async t=>{
    guardEmulator();
    const {initializeApp,deleteApp,getApps}=require('firebase-admin/app');
    const {getDatabase}=require('firebase-admin/database');
    const {getAuth}=require('firebase-admin/auth');
    const {getAppCheck}=require('firebase-admin/app-check');
    const logger=require('firebase-functions/logger');
    const api=require('../index')._test;
    const db=getDatabase();
    const writerApp=initializeApp({projectId,databaseURL:`http://${databaseHost}?ns=${namespace}`},'v220-independent-writer');
    const writer=getDatabase(writerApp);
    const key=api.conversationId(sender,recipient);
    const rules=fs.readFileSync(path.join(root,'database.rules.production.json'),'utf8');
    const loaded=await rest('.settings/rules',{method:'PUT',headers:{Authorization:'Bearer owner','Content-Type':'application/json'},body:rules});
    assert.equal(loaded.status,200,JSON.stringify(loaded));
    async function setup(st,data={},options={}){
      await writer.ref().set({users:profiles(api,[sender,recipient,outsider]),...data});
      st.mock.method(getAuth(),'verifyIdToken',async(token,checkRevoked)=>{
        assert.equal(checkRevoked,true);
        return {uid:token,auth_time:Math.floor(Date.now()/1000),firebase:{sign_in_provider:'anonymous'}};
      });
      st.mock.method(getAuth(),'deleteUser',async()=>{});
      st.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
      for(const level of ['info','warn','error'])st.mock.method(logger,level,()=>{});
      return recordReferences(st,db,options);
    }
    try{
      await t.test('real SDK removes empty objects and resolves server timestamps',async st=>{
        await setup(st);
        await db.ref('v220Probe').set({empty:{},createdAt:{'.sv':'timestamp'}});
        const value=(await writer.ref('v220Probe').get()).val();
        assert.equal(Object.hasOwn(value,'empty'),false);assert.equal(Number.isSafeInteger(value.createdAt),true);
        await assert.rejects(async()=>db.ref().update({'v220Probe':{a:1},'v220Probe/a':2}),/ancestor|contains.*path|same location/i);
      });

      await t.test('cold null transaction can abort immediately; null return probes existing server data',async st=>{
        await setup(st);await writer.ref('v220Cold/existing').set({count:7});
        let abortedCalls=0,probeCalls=0;
        const aborted=await db.ref('v220Cold/existing').transaction(value=>{abortedCalls++;return value===null?undefined:value;},undefined,false);
        assert.equal(aborted.committed,false);assert.equal(abortedCalls,1);
        const probe=await db.ref('v220Cold/existing').transaction(value=>{
          probeCalls++;return value===null?null:{count:value.count+1};
        },undefined,false);
        assert.equal(probe.committed,true);assert.equal(probe.snapshot.val().count,8);assert.ok(probeCalls>=2);
        observations.push({case:'cold-cache',abortedCalls,probeCalls});
      });

      await t.test('SDK get rejects dynamic unindexed membership; runtime once returns only current members',async st=>{
        await setup(st,{dm:{[key]:syntheticConversation(api,sender,recipient,2),foreign:{members:{[outsider]:true}}}});
        const query=db.ref('dm').orderByChild('members/'+sender).equalTo(true);
        await assert.rejects(query.get(),/Index not defined/);
        assert.deepEqual(Object.keys((await query.once('value')).val()),[key]);
        const absent=await db.ref('dm').orderByChild('members/v220_absent').equalTo(true).once('value');
        assert.equal(absent.val(),null);assert.equal(absent.exists(),false);
      });

      await t.test('once compatibility control fetches cold membership and rechecks after independent committed changes',async st=>{
        await setup(st,{dm:{[key]:syntheticConversation(api,sender,recipient,2),foreign:{members:{[outsider]:true}}}});
        const query=db.ref('dm').orderByChild('members/'+sender).equalTo(true);
        assert.deepEqual(Object.keys((await query.once('value')).val()),[key]);
        for(let attempt=0;attempt<3;attempt++){
          await writer.ref('dm/'+key+'/members/'+sender).remove();
          assert.equal((await query.once('value')).val(),null,'A removed membership must not be served from a prior once snapshot.');
          await writer.ref('dm/'+key+'/members/'+sender).set(true);
          assert.deepEqual(Object.keys((await query.once('value')).val()),[key]);
        }
        observations.push({case:'once-compatibility-freshness-control',coldRead:true,independentRemoveAndRestoreCycles:3,
          caveat:'No persistent root listener in current backend. This does not establish offline-cache freshness or bounded transfer.'});
      });

      await t.test('actual rules preserve participant, private-hand, secret and economy boundaries',async st=>{
        await setup(st,{dm:{[key]:syntheticConversation(api,sender,recipient,1)},
          messageThrottle:{[sender]:{'!sendRequests':{proof:{private:true}}}},
          purchaseClaims:{token:{uid:sender}},
          matchesV1:{fixture:{public:{participants:{[sender]:true,[recipient]:true}},
            private:{[sender]:{hand:['secret-a']},[recipient]:{hand:['secret-b']}}}},
          matchSecretsV1:{fixture:{deckOrder:['secret']}}});
        assert.equal((await rest('dm/'+key,{},sender)).status,200);
        for(const [location,uid] of [['dm/'+key,outsider],['messageThrottle/'+sender,sender],
          ['purchaseClaims/token',sender],['matchSecretsV1/fixture',sender],
          ['matchesV1/fixture/private/'+recipient,sender]])assert.equal((await rest(location,{},uid)).status,401,location);
        assert.equal((await rest('matchesV1/fixture/private/'+sender,{},sender)).status,200);
        assert.equal((await rest('users/'+sender+'/gold',{method:'PUT',headers:{'Content-Type':'application/json'},body:'999999'},sender)).status,401);
        assert.equal((await rest('dm/'+key+'/msgs/forged',{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify({from:sender,text:'forged',ts:1})},sender)).status,401);
      });

      await t.test('DM fanout persists message, proof, sender binding and both inbox summaries atomically',async st=>{
        const records=await setup(st);
        const result=await request(api,sender,'sendDirectMessage',{targetUid:recipient,text:'Firebase fanout'},'v220-fanout');
        assert.equal(result.status,200,JSON.stringify(result));
        const state=(await writer.ref().get()).val(),id=result.body.messageId,requestHash=api.hash('v220-fanout');
        assert.match(id,/^[-A-Za-z0-9_]{20}$/);
        const proof=state.dm[key].sendRequests[api.hash(sender)][requestHash];
        assert.deepEqual(state.messageThrottle[sender]['!sendRequests'][requestHash],proof);
        assert.equal(proof.messageId,id);assert.equal(state.dm[key].msgs[id].ts,proof.createdAt);
        assert.equal(state.dmInbox[sender][recipient].messageId,id);assert.equal(state.dmInbox[recipient][sender].messageId,id);
        const fanout=records.find(record=>record.kind==='update'&&record.keys.some(p=>p.includes('/msgs/')));
        assert.equal(fanout.keys.length,5);
        observations.push({case:'fresh-DM',records});
      });

      await t.test('lost cache completion replays real Firebase proof without rewinding a newer receipt',async st=>{
        let fail=true;
        const records=await setup(st,{}, {beforeTransaction(location){
          if(fail&&location.startsWith('serverRequests/')){
            const record=records.filter(item=>item.kind==='transaction'&&item.path===location);
            if(record.length===1){fail=false;throw new Error('v220 injected completion outage');}
          }
        }});
        const body={targetUid:recipient,text:'Durable delivery'},id='v220-lost-cache';
        const first=await request(api,sender,'sendDirectMessage',body,id);
        assert.equal(first.status,500,JSON.stringify(first));
        const messages=(await writer.ref('dm/'+key+'/msgs').get()).val();
        assert.equal(Object.keys(messages).length,1);
        const messageId=Object.keys(messages)[0];
        await writer.ref('dmInbox/'+recipient+'/'+sender).set({messageId:'newer-message',last:'newer',ts:Date.now()+1,unread:false,lastReadAt:Date.now()});
        const before=(await writer.ref('dmInbox/'+recipient+'/'+sender).get()).val();
        const replay=await request(api,sender,'sendDirectMessage',body,id);
        assert.equal(replay.status,200,JSON.stringify(replay));assert.equal(replay.body.messageId,messageId);
        assert.equal(replay.body.idempotent,true);
        assert.deepEqual((await writer.ref('dmInbox/'+recipient+'/'+sender).get()).val(),before);
        await writer.ref('serverRequests/'+sender+'/'+api.hash(id).slice(0,48)).remove();
        const conflict=await request(api,sender,'sendDirectMessage',{targetUid:outsider,text:body.text},id);
        assert.equal(conflict.status,409,JSON.stringify(conflict));assert.equal(conflict.body.error,'request-id-conflict');
      });

      await t.test('a competing SDK writer cannot have its new inbox row marked read',async st=>{
        const original={messageId:'observed',last:'same',ts:123,unread:true},newer={...original,messageId:'newer'};
        let injected=false;
        const records=await setup(st,{dmInbox:{[recipient]:{[sender]:original}}},{async beforeTransaction(location){
          if(!injected&&location==='dmInbox/'+recipient+'/'+sender){injected=true;await writer.ref(location).set(newer);}
        }});
        const result=await api.acknowledgeDirectMessage(recipient,sender,'observed',true);
        assert.equal(injected,true);assert.equal(result.marked,false);
        assert.deepEqual((await writer.ref('dmInbox/'+recipient+'/'+sender).get()).val(),newer);
        observations.push({case:'receipt-race',records});
      });

      await t.test('concurrent fulfillments replay one receipt and grant real DB currency once (Play mocked)',async st=>{
        await setup(st);
        const {google}=require('googleapis');const token='v220-synthetic-play-token',productId='luno_gold_1000';
        let consumed=false,consumeCalls=0;
        st.mock.method(google,'androidpublisher',()=>({purchases:{
          productsv2:{async getproductpurchasev2(){return {data:{productLineItem:[{productId,productOfferDetails:{
            consumptionState:consumed?'CONSUMPTION_STATE_CONSUMED':'CONSUMPTION_STATE_YET_TO_BE_CONSUMED'}}],
            purchaseStateContext:{purchaseState:'PURCHASED'},obfuscatedExternalAccountId:api.hash(sender)}};}},
          products:{async consume(){consumeCalls++;consumed=true;}}
        }}));
        const before=(await writer.ref('users/'+sender+'/gold').get()).val();
        const results=await Promise.all([api.fulfillPurchase(sender,{productId,purchaseToken:token}),
          api.fulfillPurchase(sender,{productId,purchaseToken:token})]);
        assert.ok(results.every(result=>result.verified));
        assert.equal((await writer.ref('users/'+sender+'/gold').get()).val(),before+1000);
        assert.equal((await writer.ref('purchaseClaims/'+api.hash(token)+'/status').get()).val(),'complete');
        await assert.rejects(api.fulfillPurchase(recipient,{productId,purchaseToken:token}),{code:'purchase-token-used'});
        observations.push({case:'purchase-concurrency',grants:1,consumeCalls,play:'mocked; consume call multiplicity is not proof of Play acceptance'});
      });

      await t.test('real Firebase account deletion erases orphaned membership after block-index loss',async st=>{
        await setup(st,{dm:{[key]:syntheticConversation(api,sender,recipient,3)}});
        const result=await request(api,sender,'deleteAccount',{confirm:true},'v220-delete-orphan');
        assert.equal(result.status,200,JSON.stringify(result));
        assert.equal((await writer.ref('dm/'+key).get()).exists(),false);
        assert.equal((await writer.ref('users/'+sender).get()).exists(),false);
        assert.equal((await rest('dm/'+key,{},sender)).status,401);
      });

      await t.test('capacity observation: opening a conversation transacts retained history',async st=>{
        const history=syntheticConversation(api,sender,recipient,1000);
        const records=await setup(st,{dm:{[key]:history}});
        const result=await request(api,sender,'openDirectMessage',{targetUid:recipient},'v220-open-capacity');
        assert.equal(result.status,200,JSON.stringify(result));
        const transaction=records.find(record=>record.kind==='transaction'&&record.path==='dm/'+key);
        assert.ok(transaction.maxInputBytes>700000);
        assert.equal((await writer.ref('dm/'+key+'/msgs').get()).numChildren(),1000);
        observations.push({case:'whole-conversation-transaction',serializedHistoryBytes:bytes(history),transaction});
      });

      await t.test('capacity observation: fresh DM queries unrelated owned conversation histories',async st=>{
        const otherKey=api.conversationId(sender,outsider);
        const records=await setup(st,{dm:{[otherKey]:syntheticConversation(api,sender,outsider,1000)}});
        const result=await request(api,sender,'sendDirectMessage',{targetUid:recipient,text:'new bounded request'},'v220-fresh-scan-red');
        assert.equal(result.status,200,JSON.stringify(result));
        const scans=records.filter(record=>['get','once'].includes(record.kind)&&record.path==='dm'&&record.query?.orderByChild==='members/'+sender);
        observations.push({case:'fresh-send-history-scan',classification:'Known capacity risk; not a functional Firebase failure',scans});
        assert.equal(scans.length,1);assert.ok(scans[0].bytes>700000);
      });

      await t.test('removed profile loses DM read access even if conversation cleanup fails',async st=>{
        await setup(st,{dm:{[key]:syntheticConversation(api,sender,recipient,1)}});
        assert.equal((await rest('dm/'+key,{},sender)).status,200,'Control: the emulator-only member identity must work.');
        await writer.ref().update({['users/'+sender]:null,['deletedAccounts/'+api.hash(sender)]:{deletedAt:Date.now()}});
        const matchRead=await rest('matchesV1/nonexistent/public',{},sender);
        assert.equal(matchRead.status,401,'Existing match rules already include a profile-existence guard.');
        const result=await rest('dm/'+key,{},sender);
        observations.push({case:'RED-deleted-member-read',status:result.status,returnedMessageCount:Object.keys(result.body?.msgs||{}).length});
        assert.equal(result.status,401,'Current DM rules still authorize deleted member credentials while retained/late conversation data exists.');
      });

      await t.test('raw-UID legacy deletion marker denies a remaining member even if its profile still exists',async st=>{
        await setup(st,{dm:{[key]:syntheticConversation(api,sender,recipient,1)},deletedAccounts:{[sender]:{deletedAt:Date.now()}}});
        assert.equal((await rest('dm/'+key,{},sender)).status,401);
        assert.equal((await rest('dm/'+key,{},recipient)).status,200);
      });
    }finally{
      saveJson('firebase-observations.json',{environment:'actual Firebase Realtime Database emulator and installed Admin SDK',
        queryCompatibilityCandidate:process.env.V220_QUERY_COMPAT_CANDIDATE==='1',
        exclusions:['Firebase Auth token verification mocked','Rules identities are unsigned emulator-only fixtures','App Check verification mocked',
          'Google Android Publisher mocked','No Functions HTTP server/deployment','No production or device verification'],observations});
      await writer.ref().remove();
      for(const app of getApps())await deleteApp(app);
    }
  });
