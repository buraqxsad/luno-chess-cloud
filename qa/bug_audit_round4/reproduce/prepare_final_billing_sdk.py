from pathlib import Path
import ast
old=Path('/workspace/luno-review/bug-audit-round3/runtime-billing');r=Path('/workspace/luno-review/bug-audit-round4/runtime-billing');r.mkdir(exist_ok=True)
s=(old/'run-proof.py').read_text().replace('bug-audit-round3/differential','bug-audit-round4/differential').replace('demo-luno-billing-fence-r3-final','demo-luno-billing-fence-r4-final')
s=s.replace("'tests':5,'pass':5", "'tests':7,'pass':7").replace("len(result['observations'])==5", "len(result['observations'])==7")
(r/'run-proof.py').write_text(s);ast.parse(s)
s=(old/'fences.cjs').read_text().replace('demo-luno-billing-fence-r3-final','demo-luno-billing-fence-r4-final')
s+='''

test('real SDK: interrupted refund lease stays retryable and an expired takeover reverses once',{timeout:12000},async t=>{
 const uid='sdk_r4_interrupted_refund',productId='luno_gold_1000',token='local-sdk-r4-interrupted-refund',key=api.hash(token);
 let clock=Date.now(),confirmations=0,consumes=0;
 t.mock.method(Date,'now',()=>clock);
 await seed(uid);const initialGold=(await checker.ref('users/'+uid+'/gold').get()).val();
 t.mock.method(logger,'error',()=>{});
 t.mock.method(google,'androidpublisher',()=>({purchases:{
  productsv2:{async getproductpurchasev2(){return {data:{productLineItem:[{productId,productOfferDetails:{consumptionState:'CONSUMPTION_STATE_YET_TO_BE_CONSUMED'}}],purchaseStateContext:{purchaseState:'PURCHASED'},obfuscatedExternalAccountId:api.hash(uid)}};}},
  products:{async consume(){consumes++;}},
  voidedpurchases:{async list(){confirmations++;return {data:{voidedPurchases:[{purchaseToken:token,voidedTimeMillis:String(clock),voidedReason:1}]}};}},
 }}));
 assert.equal((await api.fulfillPurchase(uid,{productId,purchaseToken:token})).entitlementGranted,true);
 const granted=(await checker.ref('users/'+uid+'/gold').get()).val();assert.equal(granted,initialGold+1000);
 const eventId='sdk-r4-interrupted-refund-event',eventKey=api.hash(eventId).slice(0,48),path='billingEvents/'+eventKey;
 const event={id:eventId,data:{message:{json:{packageName:'com.luno.chess',eventTimeMillis:String(clock),voidedPurchaseNotification:{purchaseToken:token}}}}};
 const originalRef=db.ref.bind(db);let interrupted=false;
 t.mock.method(db,'ref',(at='',...rest)=>{
  const ref=originalRef(at,...rest);if(at!==path)return ref;
  return proxied(ref,{async transaction(...args){
   const result=await ref.transaction(...args);
   if(!interrupted&&result.committed&&result.snapshot.val()?.status==='processing'){interrupted=true;throw new Error('sdk-worker-interrupted-after-durable-lease');}
   return result;
  }});
 });
 await assert.rejects(backend.exports.playBillingNotifications.run(event),/sdk-worker-interrupted-after-durable-lease/);
 const abandoned=(await checker.ref(path).get()).val();assert.equal(abandoned.status,'processing');assert.equal(confirmations,0);
 await assert.rejects(backend.exports.playBillingNotifications.run(event),{code:'billing-event-in-progress'});
 assert.equal((await checker.ref('users/'+uid+'/gold').get()).val(),granted);assert.equal(confirmations,0);
 clock+=300001;
 assert.equal((await backend.exports.playBillingNotifications.run(event)).revoked,true);
 const current=(await checker.ref(path).get()).val(),gold=(await checker.ref('users/'+uid+'/gold').get()).val();
 assert.equal(current.status,'complete');assert.equal(current.attempts,2);assert.notEqual(current.leaseId,abandoned.leaseId);assert.equal(gold,initialGold);
 const replay=await backend.exports.playBillingNotifications.run(event);assert.equal(replay.duplicate,true);assert.equal(confirmations,1);assert.equal(consumes,1);
 record({case:'interrupted-RTDN-lease-retry',initial_worker_interrupted:true,recent_lease_error:'billing-event-in-progress',provider_confirmations:confirmations,consume_calls:consumes,initial_gold:initialGold,granted_gold:granted,final_gold:gold,event_status:current.status,attempts:current.attempts,takeover_new_owner:current.leaseId!==abandoned.leaseId,complete_redelivery_duplicate:replay.duplicate});
});
'''
s+='\n'+"test('real SDK: an already stranded legacy friendly reservation is retired without changing the old result',{timeout:12000},async t=>{\n const owner='sdk_r4_legacy_host',peer='sdk_r4_legacy_first',other='sdk_r4_legacy_third',id='bv1_'+'4d'.repeat(16);\n const {STARTER}=req('./rules-v1/dist/src/model.js'),{authority}=req('./lib/battle-v1');\n const player=uid=>({uid,name:uid,bot:false});\n await checker.ref().set({users:{[owner]:api.starterProfile(owner,owner),[peer]:api.starterProfile(peer,peer),[other]:api.starterProfile(other,other)}});\n await api.battleV1.create(id,player(owner),player(peer),[...STARTER],[...STARTER],false);\n await api.battleV1.transact(id,peer,m=>({match:authority.finishMatch(m,{reason:'resign',winner:'w',finishedAt:Date.now()})}));\n await api.battleV1.settle(id,peer);\n const canonical=(await checker.ref('matchSecretsV1/'+id).get()).val();\n const entry=uid=>({uid,player:player(uid),deck:[...STARTER],rating:0,skill:0,joinedAt:Date.now(),lastSeenAt:Date.now(),protocolVersion:'LUNO_BATTLE_V1'});\n const w=entry(owner),b=entry(other);\n await checker.ref('battleV1Control').set({active:{[owner]:id,[other]:id},reservations:{[id]:{w,b,rated:false}},rooms:{ABCDEF:{code:'ABCDEF',host:w,guestUid:other,matchId:id,createdAt:Date.now(),expiresAt:Date.now()+120000,requestId:'old-legacy-request'}},roomByUser:{[owner]:'ABCDEF'}});\n const returned=await api.battleV1.completeReservation(id);\n const reservation=(await checker.ref('battleV1Control/reservations/'+id).get()).val(),active=(await checker.ref('battleV1Control/active/'+other).get()).val(),room=(await checker.ref('battleV1Control/rooms/ABCDEF').get()).val(),after=(await checker.ref('matchSecretsV1/'+id).get()).val();\n assert.equal(returned.matchId,id);assert.equal(reservation,null);assert.equal(active,null);assert.equal(room,null);assert.deepEqual(after,canonical);\n record({case:'legacy-friendly-reservation-recovery',reservation_absent:reservation===null,third_active_absent:active===null,bad_room_absent:room===null,canonical_result_unchanged:JSON.stringify(after)===JSON.stringify(canonical),returned_original_id:returned.matchId===id});\n});\n"
(r/'fences.cjs').write_text(s);print('Prepared final7 real RTDB cases (Billing6, legacy recovery1); execution deferred until Android/Gradle stop.')
