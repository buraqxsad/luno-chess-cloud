from pathlib import Path
import ast
old=Path('/workspace/luno-review/bug-audit-round2/runtime/sdk-proof-final');r=Path('/workspace/luno-review/bug-audit-round3/runtime-billing');r.mkdir(exist_ok=True)
s=(old/'run-proof.py').read_text().replace('bug-audit-round2/differential','bug-audit-round3/differential').replace('demo-luno-billing-fence-r2-final','demo-luno-billing-fence-r3-final')
s=s.replace("'tests':4,'pass':4", "'tests':5,'pass':5").replace("len(result['observations'])==4", "len(result['observations'])==5")
s=s.replace("result['earlier_successful_baseline']='../sdk-proof/results.json'", "result['earlier_successful_baseline']='/workspace/luno-review/bug-audit-round2/runtime/sdk-proof-final/results.json'")
(r/'run-proof.py').write_text(s);ast.parse(s)
s=(old/'fences.cjs').read_text().replace('demo-luno-billing-fence-r2-final','demo-luno-billing-fence-r3-final')
s+='''

test('real SDK: first consumable registration cannot miss its ACKed unmatched refund',{timeout:12000},async t=>{
 const uid='sdk_r3_unmatched_refund',productId='luno_gold_1000',token='local-sdk-r3-unmatched-refund-token',key=api.hash(token);
 await seed(uid);const before=(await checker.ref('users/'+uid+'/gold').get()).val();
 let purchased=true,lookups=0,consumes=0,enter,release;
 const entered=new Promise(resolve=>{enter=resolve;}),resume=new Promise(resolve=>{release=resolve;});
 t.mock.method(logger,'error',()=>{});
 t.mock.method(google,'androidpublisher',()=>({purchases:{
  productsv2:{async getproductpurchasev2(){
   const data={productLineItem:[{productId,productOfferDetails:{consumptionState:'CONSUMPTION_STATE_YET_TO_BE_CONSUMED'}}],purchaseStateContext:{purchaseState:purchased?'PURCHASED':'CANCELED'},obfuscatedExternalAccountId:api.hash(uid)};
   if(++lookups===1){enter();await resume;}
   return {data};
  }},
  products:{async consume(){consumes++;throw new Error('A refunded purchase cannot be consumed.');}},
  voidedpurchases:{async list(){return {data:{voidedPurchases:purchased?[]:[{purchaseToken:token,voidedTimeMillis:String(Date.now()),voidedReason:1}]}};}},
 }}));
 const eventId='sdk-r3-preclaim-refund',eventKey=api.hash(eventId).slice(0,48);
 const event={id:eventId,data:{message:{json:{packageName:'com.luno.chess',eventTimeMillis:String(Date.now()),voidedPurchaseNotification:{purchaseToken:token}}}}};
 const pending=api.fulfillPurchase(uid,{productId,purchaseToken:token}),settled=pending.then(value=>({value}),error=>({error}));
 try{
  await entered;assert.equal((await checker.ref('purchaseClaims/'+key).get()).val(),null);
  purchased=false;const notified=await backend.exports.playBillingNotifications.run(event);
  assert.equal(notified.deferred,true);
  assert.equal((await checker.ref('billingSignals/unmatched/'+eventKey+'/status').get()).val(),'awaiting-client-claim');
  assert.equal((await checker.ref('billingEvents/'+eventKey+'/status').get()).val(),'complete');
 }finally{release();}
 const outcome=await settled;
 assert.equal(outcome.error?.code,'purchase-not-complete');
 const replay=await backend.exports.playBillingNotifications.run(event);assert.equal(replay.duplicate,true);
 const gold=(await checker.ref('users/'+uid+'/gold').get()).val(),receipt=(await checker.ref('users/'+uid+'/serverEconomy/purchaseTokens/'+key).get()).val();
 record({case:'first-inapp-ACKed-unmatched-refund',provider_lookups:lookups,event_status:'complete',unmatched_status:'awaiting-client-claim',redelivery_duplicate:replay.duplicate,error_code:outcome.error?.code,expected_gold:before,actual_gold:gold,receipt_absent:receipt===null,consume_calls:consumes});
 assert.equal(gold,before);assert.equal(receipt,null);assert.equal(consumes,0);
});
'''
(r/'fences.cjs').write_text(s);print('Prepared existing4 + new actual SDK unmatched-refund case. No repository changes.')
