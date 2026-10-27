'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const logger=require('firebase-functions/logger');
const {google}=require('googleapis');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const {memoryDatabase}=require('./helpers/memory-database');
const {writePurchaseClaim,writeModerationReport,fulfillPurchase,reconcilePlayNotification,recomputePremiumFromClaims,reportUser,reportMessage,applyVerifiedPurchaseGrant,applyVoidedPurchaseRevocation,starterProfile,PRODUCT_CATALOG,hash,conversationId,handler}=require('../index')._test;
const uid='billing_player',other='billing_other',productId='luno_gold_1000',token='private-purchase-token',key=hash(token),path='purchaseClaims/'+key,reportPath='moderationReports/rp_race';
function seed(){return {users:{[uid]:starterProfile(uid,'billing_name'),[other]:starterProfile(other,'billing_other')}};}
function claim(owner=uid){return {uid:owner,productId,status:'verified',verifiedAt:1};}
function receipt(){return {productId,kind:'inapp',active:true,entitlementStatus:'granted',grantGold:1000,grantGems:0};}
function report(){return {reportId:'rp_race',reporterUid:uid,targetUid:other,reason:'harassment',details:'private@example.com',messageText:'private-token',conversationId:conversationId(uid,other),createdAt:1,status:'open'};}
function deleted(database,owner=uid){database.write('deletedAccounts/'+hash(owner),{deletedAt:1});database.write('users/'+owner,null);}
function fakePlay(t,hooks={}){
  const calls={get:0,consume:0,ack:0,voided:0};
  const client={purchases:{
    productsv2:{async getproductpurchasev2(){calls.get++;if(hooks.get)await hooks.get();return {data:{productLineItem:[{productId}],purchaseStateContext:{purchaseState:'PURCHASED'},obfuscatedExternalAccountId:hash(uid),orderId:'GPA-private-order'}};}},
    products:{async consume(){calls.consume++;if(hooks.consume)await hooks.consume();}},
    subscriptionsv2:{async get(){calls.get++;if(hooks.get)await hooks.get();return {data:{lineItems:[{productId:'luno_premium_month',expiryTime:new Date(Date.now()+86400000).toISOString()}],externalAccountIdentifiers:{obfuscatedExternalAccountId:hash(uid)},subscriptionState:'SUBSCRIPTION_STATE_ACTIVE',acknowledgementState:'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED'}};}},
    subscriptions:{async acknowledge(){calls.ack++;if(hooks.ack)await hooks.ack();}},
    voidedpurchases:{async list(){calls.voided++;if(hooks.voided)await hooks.voided();return {data:{voidedPurchases:[{purchaseToken:token,orderId:'GPA-private-order',voidedTimeMillis:String(Date.now()),voidedReason:1}]}};}}
  }};
  t.mock.method(google,'androidpublisher',()=>client);t.mock.method(logger,'error',(...args)=>{if(hooks.log)hooks.log(args);});return calls;
}
function notification(kind='oneTimeProductNotification'){return {packageName:'com.luno.chess',eventTimeMillis:String(Date.now()),[kind]:{purchaseToken:token,sku:productId,notificationType:1}};}

for(const status of ['processing','complete'])test(`purchase claim writes reject ${status} deletion before writing`,async t=>{
  const data=seed();data.accountDeletions={[hash(uid)]:{status}};const db=memoryDatabase(t,data);
  await assert.rejects(writePurchaseClaim(uid,key,productId,{status:'verified'},true),error=>error.code.startsWith('account-delet'));
  assert.equal(db.read(path),null);assert.equal(db.transactions.length,0);
});
for(const create of [false,true])test(`late ${create?'created':'updated'} purchase claim is retired after deletion`,async t=>{
  const data=seed();if(!create)data.purchaseClaims={[key]:claim()};
  const db=memoryDatabase(t,data,{afterTransaction(current,count,ops){if(current===path&&count===1)deleted(ops);}});
  await assert.rejects(writePurchaseClaim(uid,key,productId,{status:'granted',active:true,lastError:'private@example.com'},create),{code:'account-deleted'});
  assert.equal(db.read(path+'/uid'),hash(uid));assert.equal(db.read(path+'/accountDeleted'),true);assert.equal(db.read(path+'/active'),false);assert.equal(db.read(path+'/lastError'),null);
});
test('lost purchase write response still retires a committed late record',async t=>{
  const db=memoryDatabase(t,seed(),{afterTransaction(current,count,ops){if(current===path&&count===1){deleted(ops);throw new Error('lost-write-response');}}});
  await assert.rejects(writePurchaseClaim(uid,key,productId,{status:'verified'},true),{code:'account-deleted'});assert.equal(db.read(path+'/uid'),hash(uid));
});
test('claim completion cannot recreate a removed record',async t=>{
  const db=memoryDatabase(t,seed());await assert.rejects(writePurchaseClaim(uid,key,productId,{status:'complete'}),{code:'purchase-claim-changed'});assert.equal(db.read(path),null);
});
test('claim retry preserves changed ownership',async t=>{
  const data=seed();data.purchaseClaims={[key]:claim()};const replacement=claim(other);
  const db=memoryDatabase(t,data,{retry(current,count,update,next,ops){if(current===path){ops.write(path,replacement);return update(replacement);}return next;}});
  await assert.rejects(writePurchaseClaim(uid,key,productId,{status:'complete'}),{code:'purchase-claim-changed'});assert.deepEqual(db.read(path),replacement);
});
test('late cleanup cannot retire the replacement claim owner',async t=>{
  const replacement=claim(other),db=memoryDatabase(t,seed(),{afterTransaction(current,count,ops){if(current===path&&count===1){deleted(ops);ops.write(path,replacement);}}});
  await assert.rejects(writePurchaseClaim(uid,key,productId,{status:'verified'},true),{code:'account-deleted'});assert.deepEqual(db.read(path),replacement);
});
for(const retired of [{accountDeleted:true},{anonymizedAt:1}])test(`retired claim is never updated (${Object.keys(retired)[0]})`,async t=>{
  const data=seed();data.purchaseClaims={[key]:{...claim(),...retired}};const db=memoryDatabase(t,data);
  await assert.rejects(writePurchaseClaim(uid,key,productId,{active:true}),{code:'purchase-claim-changed'});assert.deepEqual(db.read(path),data.purchaseClaims[key]);
});
test('late failure or grant cannot downgrade an already complete claim',async t=>{
  const data=seed();data.purchaseClaims={[key]:{...claim(),status:'complete'}};const db=memoryDatabase(t,data);
  await writePurchaseClaim(uid,key,productId,{status:'reconcile-required'});await writePurchaseClaim(uid,key,productId,{status:'granted'});assert.equal(db.read(path+'/status'),'complete');
});
test('a voided claim cannot be reactivated by late fulfillment',async t=>{
  const data=seed();data.purchaseClaims={[key]:{...claim(),voided:true,active:false}};const db=memoryDatabase(t,data);
  await assert.rejects(writePurchaseClaim(uid,key,productId,{status:'complete',active:true}),{code:'purchase-claim-changed'});assert.equal(db.read(path+'/active'),false);
});

for(const owner of [uid,other])test(`late moderation report retires only deleted owner ${owner}`,async t=>{
  const db=memoryDatabase(t,seed(),{afterTransaction(current,count,ops){if(current===reportPath&&count===1)deleted(ops,owner);}});
  await assert.rejects(writeModerationReport(report()),{code:'account-deleted'});
  assert.equal(db.read(reportPath+(owner===uid?'/reporterUid':'/targetUid')),hash(owner));
  assert.equal(db.read(reportPath+(owner===uid?'/targetUid':'/reporterUid')),owner===uid?other:uid);
  for(const field of ['details','messageText','conversationId'])assert.equal(db.read(reportPath+'/'+field),null);
});
test('deleting both report owners retains both retired markers',async t=>{
  const db=memoryDatabase(t,seed(),{afterTransaction(current,count,ops){if(current===reportPath&&count===1){deleted(ops);deleted(ops,other);}}});
  await assert.rejects(writeModerationReport(report()),{code:'account-deleted'});assert.equal(db.read(reportPath+'/reporterDeleted'),true);assert.equal(db.read(reportPath+'/targetDeleted'),true);
});
test('lost report write response is cleaned after target deletion',async t=>{
  const db=memoryDatabase(t,seed(),{afterTransaction(current,count,ops){if(current===reportPath&&count===1){deleted(ops,other);throw new Error('lost-report-response');}}});
  await assert.rejects(writeModerationReport(report()),{code:'account-deleted'});assert.equal(db.read(reportPath+'/targetDeleted'),true);assert.equal(db.read(reportPath+'/reporterDeleted'),null);
});
test('report retry preserves the first content instead of replacing it',async t=>{
  const db=memoryDatabase(t,seed());await writeModerationReport(report());await writeModerationReport({...report(),details:'replacement'});assert.equal(db.read(reportPath+'/details'),'private@example.com');
});
test('changed report ownership is preserved even during deletion cleanup',async t=>{
  const replacement={...report(),reporterUid:'third_player',targetUid:'fourth_player'};
  const db=memoryDatabase(t,seed(),{afterTransaction(current,count,ops){if(current===reportPath&&count===1){ops.write(reportPath,replacement);deleted(ops);}}});
  await assert.rejects(writeModerationReport(report()),{code:'account-deleted'});assert.deepEqual(db.read(reportPath),replacement);
});
for(const endpoint of [reportUser,reportMessage])test(`${endpoint.name} uses guarded report writes`,async t=>{
  const data=seed(),messageId='message-1';data.dm={[conversationId(uid,other)]:{msgs:{[messageId]:{from:other,text:'private@example.com'}}}};
  const db=memoryDatabase(t,data,{afterTransaction(current,count,ops){if(current.startsWith('moderationReports/')&&count===1)deleted(ops,other);}});
  const body={targetUid:other,reason:'harassment'};if(endpoint===reportMessage)body.messageId=messageId;else body.details='private-token';
  await assert.rejects(endpoint({uid,body,requestId:'report-endpoint-'+endpoint.name}),{code:'account-deleted'});
  const stored=Object.values(db.read('moderationReports'))[0];assert.equal(stored.targetDeleted,true);assert.equal(stored.details,undefined);assert.equal(stored.messageText,undefined);
});

test('fresh fulfillment grants once and completed replay never calls Play again',async t=>{
  const db=memoryDatabase(t,seed()),calls=fakePlay(t),before=db.read('users/'+uid+'/gold');
  const first=await fulfillPurchase(uid,{productId,purchaseToken:token});assert.equal(first.entitlementGranted,true);assert.equal(db.read('users/'+uid+'/gold'),before+1000);
  const second=await fulfillPurchase(uid,{productId,purchaseToken:token});assert.equal(second.idempotent,true);assert.equal(calls.get,1);assert.equal(calls.consume,1);assert.equal(db.read('users/'+uid+'/gold'),before+1000);assert.equal(db.read(path+'/status'),'complete');
});
for(const invalid of ['missing','revoked','wrong-product','wrong-kind','unproven'])test(`completed consumable replay rejects ${invalid} receipt`,async t=>{
  const data=seed();data.purchaseClaims={[key]:{...claim(),status:'complete',active:true}};
  const value=receipt();if(invalid==='revoked')value.active=false;if(invalid==='wrong-product')value.productId='other';if(invalid==='wrong-kind')value.kind='subs';if(invalid==='unproven')delete value.active;
  if(invalid!=='missing')data.users[uid].serverEconomy.purchaseTokens={[key]:value};const db=memoryDatabase(t,data),calls=fakePlay(t),before=db.read('users/'+uid);
  await assert.rejects(fulfillPurchase(uid,{productId,purchaseToken:token}),{code:invalid==='revoked'?'purchase-revoked':'purchase-receipt-invalid'});assert.equal(calls.get,0);assert.deepEqual(db.read('users/'+uid),before);
});
test('verification finishing after deletion grants nothing and creates no claim',async t=>{
  const db=memoryDatabase(t,seed()),calls=fakePlay(t,{get(){deleted(db);}});
  await assert.rejects(fulfillPurchase(uid,{productId,purchaseToken:token}),{code:'account-deleted'});assert.equal(db.read(path),null);assert.equal(db.read('users/'+uid),null);assert.equal(calls.consume,0);
});
test('deletion during Play consumption does not restore raw claim ownership',async t=>{
  const db=memoryDatabase(t,seed());fakePlay(t,{consume(){deleted(db);}});
  await assert.rejects(fulfillPurchase(uid,{productId,purchaseToken:token}),{code:'account-deleted'});
  assert.equal(db.read(path+'/uid'),hash(uid));assert.equal(db.read(path+'/active'),false);assert.equal(db.read('users/'+uid),null);
});
test('provider errors persist no raw token, UID or error message',async t=>{
  const db=memoryDatabase(t,seed()),logs=[];fakePlay(t,{consume(){throw new Error(uid+' private@example.com '+token);},log(args){logs.push(args);}});
  await assert.rejects(fulfillPurchase(uid,{productId,purchaseToken:token}),{code:'play-billing-unavailable',status:503});
  assert.equal(db.read(path+'/status'),'reconcile-required');assert.equal(db.read(path+'/lastError'),null);const text=JSON.stringify(logs);for(const value of [uid,'private@example.com',token])assert.equal(text.includes(value),false);
});
test('failed consume retry does not grant currency twice',async t=>{
  const db=memoryDatabase(t,seed());let fail=true;const calls=fakePlay(t,{consume(){if(fail){fail=false;throw new Error('consume-unavailable');}}});const before=db.read('users/'+uid+'/gold');
  await assert.rejects(fulfillPurchase(uid,{productId,purchaseToken:token}),{code:'play-billing-unavailable'});await fulfillPurchase(uid,{productId,purchaseToken:token});assert.equal(db.read('users/'+uid+'/gold'),before+1000);assert.equal(calls.consume,2);assert.equal(db.read(path+'/status'),'complete');
});
test('profile owner changing during fulfillment is never granted currency',async t=>{
  const replacement=starterProfile(other,'replacement_name'),db=memoryDatabase(t,seed(),{beforeTransaction(current,count,ops){if(current==='users/'+uid)ops.write(current,replacement);}});const calls=fakePlay(t);
  await assert.rejects(fulfillPurchase(uid,{productId,purchaseToken:token}),{code:'profile-owner-mismatch'});assert.deepEqual(db.read('users/'+uid),replacement);assert.equal(calls.consume,0);
});
test('inherited catalog keys are not purchasable',async t=>{memoryDatabase(t,seed());const calls=fakePlay(t);await assert.rejects(fulfillPurchase(uid,{productId:'constructor',purchaseToken:token}),{code:'invalid-product'});assert.equal(calls.get,0);});
test('purchase grant and refund helpers reject a foreign profile before mutation',()=>{
  const profile=starterProfile(other,'foreign_name'),before=structuredClone(profile);
  assert.equal(applyVerifiedPurchaseGrant(profile,uid,PRODUCT_CATALOG[productId],{kind:'inapp',productId},key).error,'profile-owner-mismatch');
  assert.equal(applyVoidedPurchaseRevocation(profile,claim(),key,Date.now()).error,'profile-owner-mismatch');assert.deepEqual(profile,before);
});

for(const retirement of [{uid:hash(uid),accountDeleted:true},{uid:hash(uid),anonymizedAt:1}])test(`RTDN skips retired claim (${Object.keys(retirement)[1]}) without calling Play`,async t=>{
  const data=seed();data.purchaseClaims={[key]:{...claim(),...retirement}};const db=memoryDatabase(t,data),calls=fakePlay(t),before=db.read('users');
  const result=await reconcilePlayNotification(notification(),'event-retired');assert.equal(result.handled,true);assert.equal(result.status,'account-deleted');assert.equal(calls.get,0);assert.deepEqual(db.read('users'),before);assert.deepEqual(db.read(path),data.purchaseClaims[key]);
});
test('RTDN retires an orphan raw claim when its owner is already deleted',async t=>{
  const data=seed();data.purchaseClaims={[key]:{...claim(),lastError:'private@example.com'}};const db=memoryDatabase(t,data);deleted(db);const calls=fakePlay(t);
  const result=await reconcilePlayNotification(notification(),'event-orphan');assert.equal(result.status,'account-deleted');assert.equal(calls.get,0);assert.equal(db.read(path+'/uid'),hash(uid));assert.equal(db.read(path+'/lastError'),null);
});
for(const kind of ['oneTimeProductNotification','subscriptionNotification','voidedPurchaseNotification'])test(`RTDN ${kind} handles deletion during provider lookup`,async t=>{
  const data=seed();data.purchaseClaims={[key]:{...claim(),productId:kind==='subscriptionNotification'?'luno_premium_month':productId}};const db=memoryDatabase(t,data);fakePlay(t,{get(){deleted(db);},voided(){deleted(db);}});
  const result=await reconcilePlayNotification(notification(kind),'event-deletion');assert.equal(result.status,'account-deleted');assert.equal(db.read(path+'/uid'),hash(uid));assert.equal(db.read(path+'/active'),false);assert.equal(db.read('users/'+uid),null);
});
test('pending refund update cannot restore a deleted claim owner',async t=>{
  const data=seed();data.purchaseClaims={[key]:claim()};const db=memoryDatabase(t,data,{afterTransaction(current,count,ops){if(current===path&&count===1)deleted(ops);}});fakePlay(t);
  assert.equal((await reconcilePlayNotification(notification('pendingRefundReviewNotification'),'event-pending')).status,'account-deleted');assert.equal(db.read(path+'/uid'),hash(uid));
});
test('premium recomputation ignores retired claims and preserves a replaced profile',async t=>{
  const data=seed(),replacement=starterProfile(other,'replacement_name');data.purchaseClaims={[key]:{uid,productId:'luno_premium_month',kind:'subs',active:true,expiry:Date.now()+86400000,accountDeleted:true}};
  const db=memoryDatabase(t,data);assert.equal((await recomputePremiumFromClaims(uid,Date.now())).premiumUntil,0);
  db.write('users/'+uid,replacement);await assert.rejects(recomputePremiumFromClaims(uid,Date.now()),{code:'profile-owner-mismatch'});assert.deepEqual(db.read('users/'+uid),replacement);
});
for(const status of ['processing','complete'])test(`fulfillment rejects ${status} deletion without Play calls`,async t=>{
  const data=seed();data.accountDeletions={[hash(uid)]:{status}};const db=memoryDatabase(t,data),calls=fakePlay(t);
  await assert.rejects(fulfillPurchase(uid,{productId,purchaseToken:token}),error=>error.code.startsWith('account-delet'));assert.equal(calls.get,0);assert.equal(db.read(path),null);
});
test('completed replay rechecks the claim after reading the current profile',async t=>{
  const data=seed();data.purchaseClaims={[key]:{...claim(),status:'complete'}};data.users[uid].serverEconomy.purchaseTokens={[key]:receipt()};
  const db=memoryDatabase(t,data,{afterRead(current,count,ops){if(current==='users/'+uid&&count===2)ops.write(path,claim(other));}});fakePlay(t);
  await assert.rejects(fulfillPurchase(uid,{productId,purchaseToken:token}),{code:'purchase-claim-changed'});assert.equal(db.read(path+'/uid'),other);
});
for(const [field,value] of [['grantGold',-1],['grantGems',1.5],['grantGold',1000000001]])test(`completed receipt rejects invalid ${field}=${value}`,async t=>{
  const data=seed();data.purchaseClaims={[key]:{...claim(),status:'complete'}};data.users[uid].serverEconomy.purchaseTokens={[key]:{...receipt(),[field]:value}};memoryDatabase(t,data);fakePlay(t);
  await assert.rejects(fulfillPurchase(uid,{productId,purchaseToken:token}),{code:'purchase-receipt-invalid'});
});
test('completed receipt cannot disagree with historical claim amounts',async t=>{
  const data=seed();data.purchaseClaims={[key]:{...claim(),status:'complete',grantGold:2000}};data.users[uid].serverEconomy.purchaseTokens={[key]:receipt()};memoryDatabase(t,data);fakePlay(t);
  await assert.rejects(fulfillPurchase(uid,{productId,purchaseToken:token}),{code:'purchase-receipt-invalid'});
});
test('refund of a verified but ungranted purchase cannot debit unrelated gold',()=>{
  const profile=starterProfile(uid,'ungranted_name'),before=structuredClone(profile);
  assert.deepEqual(applyVoidedPurchaseRevocation(profile,claim(),key,Date.now()),{revoked:false,ungranted:true});assert.deepEqual(profile,before);
});
for(const invalid of ['missing','mismatched-product','negative-amount','claim-disagrees'])test(`refund fails closed for ${invalid} grant evidence`,()=>{
  const profile=starterProfile(uid,'refund_name'),value=receipt(),entry={...claim(),status:'complete'};
  if(invalid==='mismatched-product')value.productId='other';if(invalid==='negative-amount')value.grantGold=-1000;if(invalid==='claim-disagrees')entry.grantGold=2000;
  if(invalid!=='missing')profile.serverEconomy.purchaseTokens={[key]:value};const before=structuredClone(profile);
  assert.equal(applyVoidedPurchaseRevocation(profile,entry,key,Date.now()).error,'purchase-receipt-invalid');assert.deepEqual(profile,before);
});
test('refunded token cannot be granted again after its marker is revoked',()=>{
  const profile=starterProfile(uid,'revoked_name');profile.serverEconomy.purchaseTokens={[key]:{...receipt(),active:false,entitlementStatus:'voided'}};
  const before=structuredClone(profile);assert.equal(applyVerifiedPurchaseGrant(profile,uid,PRODUCT_CATALOG[productId],{kind:'inapp',productId},key).error,'purchase-revoked');assert.deepEqual(profile,before);
});
test('provider failure is redacted through the actual HTTP handler and logs',async t=>{
  const db=memoryDatabase(t,seed()),logs=[];fakePlay(t,{consume(){throw new Error(uid+' private@example.com '+token);},log(args){logs.push(args);}});
  t.mock.method(getAuth(),'verifyIdToken',async()=>({uid}));t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
  for(const method of ['info','warn'])t.mock.method(logger,method,(...args)=>logs.push(args));
  const headers={authorization:'Bearer fake-token','x-firebase-appcheck':'fake-check','x-luno-request-id':'provider-error-request',origin:'https://localhost'};let status,body;
  await handler({method:'POST',path:'/verifyPurchase',body:{productId,purchaseToken:token},get:name=>headers[name.toLowerCase()]||''},{set(){return this;},status(value){status=value;return this;},json(value){body=value;}});
  assert.equal(status,503);assert.equal(body.error,'play-billing-unavailable');assert.equal(db.read(path+'/lastError'),null);
  const text=JSON.stringify({logs,body});for(const privateValue of [uid,'private@example.com',token])assert.equal(text.includes(privateValue),false);
});
for(const operation of ['get','consume'])test(`${operation} provider failure exposes only a safe service error`,async t=>{
  memoryDatabase(t,seed());fakePlay(t,{[operation](){throw new Error('private@example.com '+token);}});
  await assert.rejects(fulfillPurchase(uid,{productId,purchaseToken:token}),error=>error.code==='play-billing-unavailable'&&!error.message.includes(token)&&!error.message.includes('private@example.com'));
});
test('late one-time notification for a confirmed voided token is handled without reactivation',async t=>{
  const data=seed();data.purchaseClaims={[key]:{...claim(),status:'complete',voided:true,active:false,entitlementStatus:'voided'}};const db=memoryDatabase(t,data),calls=fakePlay(t);
  const result=await reconcilePlayNotification(notification(),'event-voided-replay');assert.equal(result.handled,true);assert.equal(result.status,'voided');assert.equal(result.active,false);assert.equal(calls.get,0);assert.deepEqual(db.read(path),data.purchaseClaims[key]);
});
test('subscription fulfillment still grants expiry and revalidates on replay',async t=>{
  const db=memoryDatabase(t,seed()),calls=fakePlay(t),subscriptionId='luno_premium_month',before=db.read('users/'+uid+'/gold');
  assert.equal((await fulfillPurchase(uid,{productId:subscriptionId,purchaseToken:token})).entitlementGranted,true);
  assert.equal(db.read(path+'/status'),'complete');assert.equal(db.read(path+'/kind'),'subs');assert.ok(db.read('users/'+uid+'/premiumUntil')>Date.now());
  await fulfillPurchase(uid,{productId:subscriptionId,purchaseToken:token});assert.equal(calls.get,2);assert.equal(calls.consume,0);assert.equal(db.read('users/'+uid+'/gold'),before);
});
test('live subscription notification recomputes Premium through cold profile transactions',async t=>{
  const data=seed();data.purchaseClaims={[key]:{...claim(),productId:'luno_premium_month',status:'complete',kind:'subs'}};const db=memoryDatabase(t,data);fakePlay(t);
  const result=await reconcilePlayNotification(notification('subscriptionNotification'),'event-sub-live');assert.equal(result.active,true);assert.ok(result.premiumUntil>Date.now());assert.equal(db.read(path+'/active'),true);assert.equal(db.read('users/'+uid+'/premiumUntil'),result.premiumUntil);
});
test('confirmed refund reverses a proved grant once across duplicate notifications',async t=>{
  const data=seed();data.purchaseClaims={[key]:{...claim(),status:'complete',kind:'inapp',active:true,grantGold:1000,grantGems:0}};data.users[uid].serverEconomy.purchaseTokens={[key]:receipt()};data.users[uid].gold+=1000;
  const db=memoryDatabase(t,data);fakePlay(t);const first=await reconcilePlayNotification(notification('voidedPurchaseNotification'),'event-refund');assert.equal(first.revoked,true);assert.equal(first.recoveredGold,1000);
  const gold=db.read('users/'+uid+'/gold'),second=await reconcilePlayNotification(notification('voidedPurchaseNotification'),'event-refund-repeat');assert.equal(second.idempotent,true);assert.equal(db.read('users/'+uid+'/gold'),gold);assert.equal(db.read(path+'/voided'),true);assert.equal(db.read(path+'/active'),false);
});
test('confirmed refund of an ungranted claim changes no player currency',async t=>{
  const data=seed();data.purchaseClaims={[key]:claim()};const db=memoryDatabase(t,data),before=db.read('users/'+uid+'/gold');fakePlay(t);
  const result=await reconcilePlayNotification(notification('voidedPurchaseNotification'),'event-ungranted-refund');assert.equal(result.ungranted,true);assert.equal(result.revoked,false);assert.equal(db.read('users/'+uid+'/gold'),before);assert.equal(db.read(path+'/voided'),true);
});
test('historical subscription refund metadata cannot override current verified Google access',async t=>{
  const data=seed();data.purchaseClaims={[key]:{...claim(),productId:'luno_premium_month',status:'complete',kind:'subs',voided:true,active:false}};const db=memoryDatabase(t,data),calls=fakePlay(t);
  const result=await fulfillPurchase(uid,{productId:'luno_premium_month',purchaseToken:token});assert.equal(result.entitlementGranted,true);assert.equal(db.read(path+'/voided'),true);assert.equal(db.read(path+'/active'),true);assert.ok(db.read('users/'+uid+'/premiumUntil')>Date.now());assert.equal(calls.get,1);
});
test('retry after catalog changes retains the actual historical grant amount',async t=>{
  const data=seed();data.purchaseClaims={[key]:claim()};data.users[uid].serverEconomy.purchaseTokens={[key]:receipt()};const db=memoryDatabase(t,data),before=db.read('users/'+uid+'/gold');fakePlay(t);
  const original=PRODUCT_CATALOG[productId].grant;PRODUCT_CATALOG[productId].grant={gold:2000};t.after(()=>{PRODUCT_CATALOG[productId].grant=original;});
  await fulfillPurchase(uid,{productId,purchaseToken:token});assert.equal(db.read(path+'/grantGold'),1000);assert.equal(db.read('users/'+uid+'/gold'),before);
  assert.equal((await fulfillPurchase(uid,{productId,purchaseToken:token})).idempotent,true);
});
test('malformed existing grant cannot be consumed and reported as complete',async t=>{
  const data=seed();data.purchaseClaims={[key]:claim()};data.users[uid].serverEconomy.purchaseTokens={[key]:{...receipt(),grantGold:-1}};const db=memoryDatabase(t,data),calls=fakePlay(t),before=db.read('users/'+uid+'/gold');
  await assert.rejects(fulfillPurchase(uid,{productId,purchaseToken:token}),{code:'purchase-receipt-invalid'});assert.equal(calls.consume,0);assert.notEqual(db.read(path+'/status'),'complete');assert.equal(db.read('users/'+uid+'/gold'),before);
});
test('durable reversal prevents regrant even when its token marker is missing',()=>{
  const profile=starterProfile(uid,'reversal_name');profile.serverEconomy.billingReversals={[key]:{productId,createdAt:1}};const before=structuredClone(profile);
  assert.equal(applyVerifiedPurchaseGrant(profile,uid,PRODUCT_CATALOG[productId],{kind:'inapp',productId},key).error,'purchase-revoked');assert.deepEqual(profile,before);
});
