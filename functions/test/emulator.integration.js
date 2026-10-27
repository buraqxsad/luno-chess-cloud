'use strict';

const {authHost,databaseHost}=require('./helpers/local-emulators').requireLocalEmulators();
const assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getAuth}=require('firebase-admin/auth');
const {getDatabase}=require('firebase-admin/database');

const namespace='luno-chess-default-rtdb';
const adminApp=initializeApp({projectId:'luno-chess',databaseURL:`http://${databaseHost}?ns=${namespace}`},'integration-test');
const db=getDatabase(adminApp);
const {handler,ONBOARDING_REWARD,SOCIAL_VISIT_REWARDS}=require('../index.js')._test;

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
async function api(path,token,body,id,origin,timeoutMs,appCheckToken){
  const headers={
    authorization:'Bearer '+token,
    'content-type':'application/json',
    'x-firebase-appcheck':appCheckToken===undefined?'luno-emulator-app-check':appCheckToken,
    'x-luno-request-id':id||('it-'+Date.now()),
    origin:origin||'https://localhost'
  };
  const req={
    method:'POST',
    path,
    body:body||{},
    get:function(name){return headers[String(name||'').toLowerCase()]||'';}
  };
  let status=200,responseBody={};
  const res={
    set:function(){return this;},
    status:function(value){status=value;return this;},
    send:function(value){responseBody=value;return this;},
    json:function(value){responseBody=value;return this;}
  };
  let timer;
  await Promise.race([
    handler(req,res),
    new Promise(function(_,reject){timer=setTimeout(function(){reject(new Error('API timeout: '+path+' ['+(id||'no-id')+']'));},timeoutMs||45000);})
  ]).finally(function(){if(timer)clearTimeout(timer);});
  return {status,body:responseBody};
}
async function clientDb(path,token,method,value){
  const url=`http://${databaseHost}/${path}.json?ns=${namespace}`+(token?'&auth='+encodeURIComponent(token):'');
  const options={method:method||'GET',headers:{'Content-Type':'application/json'}};
  if(value!==undefined)options.body=JSON.stringify(value);
  options.signal=AbortSignal.timeout(15000);
  return json(await fetch(url,options));
}

async function main(){
  const first=await anonymousUser();
  const second=await anonymousUser();

  const missingGuestAppCheck=await api('/createGuestPlayer',first.idToken,{username:'  Ｌｕｎｏ＿１２  '},'guest-missing-app-check',undefined,undefined,'');
  assert.equal(missingGuestAppCheck.status,401,JSON.stringify(missingGuestAppCheck.body));
  assert.equal(missingGuestAppCheck.body.error,'app-check-required');
  const created=await api('/createGuestPlayer',first.idToken,{username:'  Ｌｕｎｏ＿１２  '},'guest-create-1');
  assert.equal(created.status,200,JSON.stringify(created.body));
  assert.equal(created.body.created,true);
  assert.match(created.body.username,/^luno_[a-f0-9]{8}$/);
  assert.notEqual(created.body.username,'luno_12');
  assert.equal(created.body.usernameGenerated,true);
  const firstConsent=await api('/acceptLegalTerms',first.idToken,{},'first-ugc-consent');
  assert.equal(firstConsent.status,200,JSON.stringify(firstConsent.body));
  const missingStrictAppCheck=await api('/purchaseSoftItem',first.idToken,{itemId:'skin:obsidian'},'app-check-missing-strict',undefined,undefined,'');
  assert.equal(missingStrictAppCheck.status,401,JSON.stringify(missingStrictAppCheck.body));
  assert.equal(missingStrictAppCheck.body.error,'app-check-required');
  const fakeAppCheck=await api('/getPlayerState',first.idToken,{},'app-check-fake',undefined,undefined,'fake-app-check');
  assert.equal(fakeAppCheck.status,401,JSON.stringify(fakeAppCheck.body));
  assert.equal(fakeAppCheck.body.error,'invalid-app-check');

  const replay=await api('/createGuestPlayer',first.idToken,{username:'luno_12'},'guest-create-1');
  assert.equal(replay.status,200,JSON.stringify(replay.body));
  assert.equal(replay.body.idempotent,true);

  const anotherRequest=await api('/createGuestPlayer',first.idToken,{username:'luno_12'},'guest-create-2');
  assert.equal(anotherRequest.status,200,JSON.stringify(anotherRequest.body));
  assert.equal(anotherRequest.body.created,false);

  const profileRead=await clientDb('users/'+first.localId,first.idToken);
  assert.equal(profileRead.status,200,JSON.stringify(profileRead.body));
  assert.equal(profileRead.body.gold,1250);
  assert.equal(profileRead.body.gems,50);
  assert.equal(profileRead.body.starterGrantVersion,2);

  const linkGuest=await anonymousUser();
  const linkGuestCreated=await api('/createGuestPlayer',linkGuest.idToken,{username:'google_guest'},'google-guest-create');
  assert.equal(linkGuestCreated.status,200,JSON.stringify(linkGuestCreated.body));
  const preparedLink=await api('/prepareGoogleLink',linkGuest.idToken,{},'google-link-prepare-1');
  assert.equal(preparedLink.status,200,JSON.stringify(preparedLink.body));
  assert.equal(preparedLink.body.switchAllowed,true);
  assert.match(preparedLink.body.attemptId,/^[a-f0-9]{32}$/);
  const preparedReplay=await api('/prepareGoogleLink',linkGuest.idToken,{},'google-link-prepare-1');
  assert.equal(preparedReplay.status,200,JSON.stringify(preparedReplay.body));
  assert.equal(preparedReplay.body.idempotent,true);
  const parallelLinkAttempt=await api('/prepareGoogleLink',linkGuest.idToken,{},'google-link-prepare-2');
  assert.equal(parallelLinkAttempt.status,409,JSON.stringify(parallelLinkAttempt.body));
  assert.equal(parallelLinkAttempt.body.error,'account-link-in-progress');
  const forgedLink=await api('/prepareGoogleLink',linkGuest.idToken,{idToken:'secret'},'google-link-forged');
  assert.equal(forgedLink.status,400,JSON.stringify(forgedLink.body));
  assert.equal(forgedLink.body.error,'unexpected-field');
  const conflictResults=await Promise.all(Array.from({length:5},function(){
    return api('/recordGoogleLinkConflict',linkGuest.idToken,{attemptId:preparedLink.body.attemptId,reason:'credential-already-in-use'},'google-link-conflict-1');
  }));
  conflictResults.forEach(function(result){assert.equal(result.status,200,JSON.stringify(result.body));});
  assert.equal(new Set(conflictResults.map(function(result){return result.body.ticketId;})).size,1);
  const supportTicketId=conflictResults[0].body.ticketId;
  const supportTicket=(await db.ref('accountLinkTickets/'+supportTicketId).get()).val();
  assert.equal(supportTicket.uid,linkGuest.localId);
  assert.equal(supportTicket.provider,'google.com');
  assert.equal(Object.prototype.hasOwnProperty.call(supportTicket,'email'),false);
  assert.equal(Object.prototype.hasOwnProperty.call(supportTicket,'credential'),false);
  const privateTicketRead=await clientDb('accountLinkTickets/'+supportTicketId,linkGuest.idToken);
  assert.equal(privateTicketRead.status,401,JSON.stringify(privateTicketRead.body));
  assert.equal((await db.ref('users/'+linkGuest.localId).get()).exists(),true);
  await getAuth(adminApp).updateUser(linkGuest.localId,{providerToLink:{providerId:'google.com',uid:'google-provider-link-1',email:'google-link@example.test'}});
  const completedLink=await api('/completeGoogleLink',linkGuest.idToken,{attemptId:preparedLink.body.attemptId},'google-link-complete-1');
  assert.equal(completedLink.status,200,JSON.stringify(completedLink.body));
  assert.equal(completedLink.body.linked,true);
  assert.equal(completedLink.body.uid,linkGuest.localId);
  assert.equal((await db.ref('users/'+linkGuest.localId+'/accountSecurity/google/status').get()).val(),'linked');
  const completedReplay=await api('/completeGoogleLink',linkGuest.idToken,{attemptId:preparedLink.body.attemptId},'google-link-complete-1');
  assert.equal(completedReplay.status,200,JSON.stringify(completedReplay.body));
  assert.equal(completedReplay.body.idempotent,true);
  const linkedPrepare=await api('/prepareGoogleLink',linkGuest.idToken,{},'google-link-prepare-linked');
  assert.equal(linkedPrepare.status,200,JSON.stringify(linkedPrepare.body));
  assert.equal(linkedPrepare.body.alreadyLinked,true);
  console.error('[stage] guest and Google-link safety complete');

  const parallelDaily=await Promise.all(Array.from({length:100},function(_,index){
    return api(
      '/claimDailyReward',
      first.idToken,
      {amount:999999999,clientTime:Date.now()+365*24*60*60*1000},
      'daily-parallel-'+index,
      'https://localhost',
      60000
    );
  }));
  parallelDaily.forEach(function(result){assert.equal(result.status,200,JSON.stringify(result.body));});
  assert.equal(parallelDaily.filter(function(result){return result.body.granted===true;}).length,1);
  const dailyProfile=(await db.ref('users/'+first.localId).get()).val();
  assert.equal(dailyProfile.gold,1450);
  assert.equal(Object.keys(dailyProfile.serverEconomy.claims||{}).length,1);
  assert.equal(Object.keys(dailyProfile.serverEconomy.ledger||{}).length,1);
  const ledgerEntry=Object.values(dailyProfile.serverEconomy.ledger)[0];
  assert.equal(ledgerEntry.amount,200);
  assert.equal(ledgerEntry.previousBalance,1250);
  assert.equal(ledgerEntry.newBalance,1450);
  assert.equal(ledgerEntry.uid,first.localId);

  const dailyRetry=await api('/claimDailyReward',first.idToken,{},'daily-parallel-0');
  assert.equal(dailyRetry.status,200,JSON.stringify(dailyRetry.body));
  assert.equal(dailyRetry.body.idempotent,true);
  const clockSpoof=await api('/claimDailyReward',first.idToken,{clientTime:0,dayKey:'2099-01-01'},'daily-clock-spoof-1');
  assert.equal(clockSpoof.status,200,JSON.stringify(clockSpoof.body));
  assert.equal(clockSpoof.body.granted,false);
  assert.equal((await db.ref('users/'+first.localId+'/gold').get()).val(),1450);
  const serverState=await api('/getPlayerState',first.idToken,{},'state-read-1');
  assert.equal(serverState.status,200,JSON.stringify(serverState.body));
  assert.equal(serverState.body.state.gold,1450);
  assert.equal(serverState.body.state.economy.daily.canClaim,false);

  const dayKey=serverState.body.state.economy.periods.dayKey;
  await db.ref('users/'+first.localId+'/serverProgress/missions/daily/'+dayKey+'/counters/d1').set(1);
  const forgedMission=await api('/claimMissionReward',first.idToken,{category:'daily',missionId:'d1',amount:999999},'mission-forged-1');
  assert.equal(forgedMission.status,400,JSON.stringify(forgedMission.body));
  assert.equal(forgedMission.body.error,'unexpected-field');
  const parallelMission=await Promise.all(Array.from({length:40},function(_,index){
    return api('/claimMissionReward',first.idToken,{category:'daily',missionId:'d1'},'mission-parallel-'+index);
  }));
  parallelMission.forEach(function(result){assert.equal(result.status,200,JSON.stringify(result.body));});
  assert.equal(parallelMission.filter(function(result){return result.body.granted===true;}).length,1);
  assert.equal((await db.ref('users/'+first.localId+'/gold').get()).val(),1600);

  const missionRetry=await api('/claimMissionReward',first.idToken,{category:'daily',missionId:'d1'},'mission-parallel-0');
  assert.equal(missionRetry.status,200,JSON.stringify(missionRetry.body));
  assert.equal(missionRetry.body.idempotent,true);
  const wrongMissionRetry=await api('/claimMissionReward',first.idToken,{category:'daily',missionId:'d2'},'mission-parallel-0');
  assert.equal(wrongMissionRetry.status,409,JSON.stringify(wrongMissionRetry.body));
  assert.equal(wrongMissionRetry.body.error,'request-id-conflict');
  assert.equal((await db.ref('users/'+first.localId+'/gold').get()).val(),1600);

  await db.ref('users/'+first.localId+'/stats/wins').set(1);
  const parallelAchievement=await Promise.all(Array.from({length:40},function(_,index){
    return api('/claimAchievementReward',first.idToken,{achievementId:'first_win'},'achievement-parallel-'+index);
  }));
  parallelAchievement.forEach(function(result){assert.equal(result.status,200,JSON.stringify(result.body));});
  assert.equal(parallelAchievement.filter(function(result){return result.body.granted===true;}).length,1);
  const wrongAchievementRetry=await api('/claimAchievementReward',first.idToken,{achievementId:'win_500'},'achievement-parallel-0');
  assert.equal(wrongAchievementRetry.status,409,JSON.stringify(wrongAchievementRetry.body));
  assert.equal(wrongAchievementRetry.body.error,'request-id-conflict');
  const lockedAchievement=await api('/claimAchievementReward',first.idToken,{achievementId:'win_500'},'achievement-locked-1');
  assert.equal(lockedAchievement.status,409,JSON.stringify(lockedAchievement.body));
  assert.equal(lockedAchievement.body.error,'achievement-not-complete');

  const seasonId=serverState.body.state.economy.periods.seasonId;
  const seasonNumber=Number(seasonId.slice(1));
  await db.ref('users/'+first.localId+'/passState').update({seasonKey:'ranked-'+seasonId+'-v2',season:seasonNumber,level:1,xp:0,premium:false,claimed:{free:{},premium:{}}});
  const parallelPass=await Promise.all(Array.from({length:30},function(_,index){
    return api('/claimPassReward',first.idToken,{level:1,track:'free'},'pass-parallel-'+index);
  }));
  parallelPass.forEach(function(result){assert.equal(result.status,200,JSON.stringify(result.body));});
  assert.equal(parallelPass.filter(function(result){return result.body.granted===true;}).length,1);
  const premiumPassDenied=await api('/claimPassReward',first.idToken,{level:1,track:'premium'},'pass-premium-denied-1');
  assert.equal(premiumPassDenied.status,409,JSON.stringify(premiumPassDenied.body));
  assert.equal(premiumPassDenied.body.error,'pass-premium-required');

  await db.ref('users/'+first.localId+'/serverSeason').set({number:seasonNumber-1,peakTrophies:700,startedAt:Date.now()-31*24*60*60*1000});
  const parallelSeason=await Promise.all(Array.from({length:30},function(_,index){
    return api('/claimSeasonReward',first.idToken,{},'season-parallel-'+index);
  }));
  parallelSeason.forEach(function(result){assert.equal(result.status,200,JSON.stringify(result.body));});
  assert.equal(parallelSeason.filter(function(result){return result.body.granted===true;}).length,1);
  const rewardProfile=(await db.ref('users/'+first.localId).get()).val();
  // Starter 1250 + daily 200 + mission 150 + achievement 100 + Pass 120 + season 1500.
  assert.equal(rewardProfile.gold,3320);
  assert.equal(rewardProfile.gems,72);
  assert.equal(Object.keys(rewardProfile.serverEconomy.claims||{}).length,5);
  assert.equal(Object.keys(rewardProfile.serverEconomy.ledger||{}).length,6);
  console.error('[stage] reward races complete');
  const pathUser=await anonymousUser();
  const pathCreated=await api('/createGuestPlayer',pathUser.idToken,{username:'season_path_race'},'path-player-create');
  assert.equal(pathCreated.status,200,JSON.stringify(pathCreated.body));
  const pathRef=db.ref('users/'+pathUser.localId);
  const pathBefore=(await pathRef.get()).val();
  const parallelPath=await Promise.all(Array.from({length:30},function(_,index){
    return api('/claimSeasonPathReward',pathUser.idToken,{tierId:'path_1'},'path-parallel-'+index);
  }));
  parallelPath.forEach(function(result){assert.equal(result.status,200,JSON.stringify(result.body));});
  assert.equal(parallelPath.filter(function(result){return result.body.granted===true;}).length,1);
  const pathAfter=(await pathRef.get()).val();
  assert.equal(pathAfter.gold,pathBefore.gold+100);
  assert.equal(pathAfter.gems,pathBefore.gems);
  assert.equal(Object.keys(pathAfter.serverEconomy.claims||{}).length,1);
  assert.equal(Object.keys(pathAfter.serverEconomy.ledger||{}).length,1);
  assert.equal(Object.prototype.hasOwnProperty.call(pathAfter.serverSeason.claimed,'path_1'),true);
  const duplicatePath=await api('/claimSeasonPathReward',pathUser.idToken,{tierId:'path_1'},'path-new-request');
  assert.equal(duplicatePath.status,200,JSON.stringify(duplicatePath.body));
  assert.equal(duplicatePath.body.granted,false);
  const replayPath=await api('/claimSeasonPathReward',pathUser.idToken,{tierId:'path_1'},'path-parallel-0');
  assert.equal(replayPath.status,200,JSON.stringify(replayPath.body));
  assert.equal(replayPath.body.idempotent,true);
  for(const attempt of [
    {body:{tierId:'path_10'},id:'path-locked',status:409,error:'season-tier-locked'},
    {body:{tierId:'path_1',amount:999999},id:'path-forged',status:400,error:'unexpected-field'},
    {body:{tierId:'path_2'},id:'path-parallel-0',status:409,error:'request-id-conflict'},
    {body:{tierId:'not-a-tier'},id:'path-unknown',status:400,error:'unknown-season-tier'}
  ]){
    const result=await api('/claimSeasonPathReward',pathUser.idToken,attempt.body,attempt.id);
    assert.equal(result.status,attempt.status,JSON.stringify(result.body));
    assert.equal(result.body.error,attempt.error);
  }
  const pathFinal=(await pathRef.get()).val();
  assert.equal(pathFinal.gold,pathAfter.gold);
  assert.equal(pathFinal.gems,pathAfter.gems);
  assert.deepEqual(pathFinal.serverEconomy.claims,pathAfter.serverEconomy.claims);
  assert.deepEqual(pathFinal.serverEconomy.ledger,pathAfter.serverEconomy.ledger);
  console.error('[stage] season path races complete');
  if(process.env.LUNO_TEST_REWARDS_ONLY==='1'){
    console.log(JSON.stringify({result:'pass',scope:'reward-races',parallelRewardRequests:270,rewardSources:6,requestIdentityConflictsVerified:true,seasonPathRaceVerified:true}));
    await deleteApp(adminApp);
    process.exit(0);
  }

  const secondCreated=await api('/createGuestPlayer',second.idToken,{username:'luno_12'},'guest-create-3');
  assert.equal(secondCreated.status,200,JSON.stringify(secondCreated.body));
  assert.equal(secondCreated.body.created,true);
  assert.equal(secondCreated.body.usernameGenerated,true);
  assert.notEqual(secondCreated.body.username,created.body.username);
  const secondConsent=await api('/acceptLegalTerms',second.idToken,{},'second-ugc-consent');
  assert.equal(secondConsent.status,200,JSON.stringify(secondConsent.body));
  const secondName=await api('/changeUsername',second.idToken,{username:'luno_13'},'second-name-choice');
  assert.equal(secondName.status,200,JSON.stringify(secondName.body));
  assert.equal(secondName.body.state.profile.usernameGenerated,false);
  await db.ref('usernames/luno_13').remove();
  const repairedExisting=await api('/createGuestPlayer',second.idToken,{username:'luno_13'},'guest-create-repair-1');
  assert.equal(repairedExisting.status,200,JSON.stringify(repairedExisting.body));
  assert.equal(repairedExisting.body.created,false);
  assert.equal((await db.ref('usernames/luno_13').get()).val(),second.localId);

  const usernameFirst=await anonymousUser(),usernameSecond=await anonymousUser();
  const usernameFirstCreated=await api('/createGuestPlayer',usernameFirst.idToken,{username:'name_owner_a'},'username-owner-a');
  const usernameSecondCreated=await api('/createGuestPlayer',usernameSecond.idToken,{username:'name_owner_b'},'username-owner-b');
  assert.equal(usernameFirstCreated.status,200,JSON.stringify(usernameFirstCreated.body));
  assert.equal(usernameSecondCreated.status,200,JSON.stringify(usernameSecondCreated.body));
  for(const [user,name] of [[usernameFirst,'name_owner_a'],[usernameSecond,'name_owner_b']]){
    const consent=await api('/acceptLegalTerms',user.idToken,{},'username-consent-'+name);
    assert.equal(consent.status,200,JSON.stringify(consent.body));
    const chosen=await api('/changeUsername',user.idToken,{username:name},'username-choice-'+name);
    assert.equal(chosen.status,200,JSON.stringify(chosen.body));
    assert.equal(chosen.body.state.profile.usernameGenerated,false);
  }
  const invalidUsernameChange=await api('/changeUsername',usernameFirst.idToken,{username:'ADMIN'},'username-invalid-1');
  assert.equal(invalidUsernameChange.status,400,JSON.stringify(invalidUsernameChange.body));
  assert.equal(invalidUsernameChange.body.error,'username-not-allowed');
  const forgedUsernameChange=await api('/changeUsername',usernameFirst.idToken,{username:'new_name',cost:0},'username-forged-1');
  assert.equal(forgedUsernameChange.status,400,JSON.stringify(forgedUsernameChange.body));
  assert.equal(forgedUsernameChange.body.error,'unexpected-field');

  const freeUsernameRace=await Promise.all(Array.from({length:20},function(_,index){
    return api('/changeUsername',usernameFirst.idToken,{username:'renamed_free'},'username-free-'+index);
  }));
  assert.equal(freeUsernameRace.every(function(result){return result.status===200||result.status===429;}),true,JSON.stringify(freeUsernameRace));
  assert.equal(freeUsernameRace.filter(function(result){return result.status===200&&result.body.changed===true;}).length,1);
  let usernameProfile=(await db.ref('users/'+usernameFirst.localId).get()).val();
  assert.equal(usernameProfile.username,'renamed_free');
  assert.equal(usernameProfile.usernameChanges,1);
  assert.equal(usernameProfile.gold,1250);
  assert.equal((await db.ref('usernames/name_owner_a').get()).exists(),false);
  assert.equal((await db.ref('usernames/renamed_free').get()).val(),usernameFirst.localId);
  assert.equal((await db.ref('publicProfiles/'+usernameFirst.localId+'/username').get()).val(),'renamed_free');

  await db.ref('serverRateLimits/'+usernameFirst.localId+'/changeUsername').remove();
  await db.ref('users/'+usernameFirst.localId+'/gold').set(6000);
  const paidUsernameRace=await Promise.all(Array.from({length:20},function(_,index){
    return api('/changeUsername',usernameFirst.idToken,{username:'renamed_paid'},'username-paid-'+index);
  }));
  assert.equal(paidUsernameRace.every(function(result){return result.status===200||result.status===429;}),true,JSON.stringify(paidUsernameRace));
  assert.equal(paidUsernameRace.filter(function(result){return result.status===200&&result.body.changed===true;}).length,1);
  usernameProfile=(await db.ref('users/'+usernameFirst.localId).get()).val();
  assert.equal(usernameProfile.username,'renamed_paid');
  assert.equal(usernameProfile.usernameChanges,2);
  assert.equal(usernameProfile.gold,1000);
  assert.equal(Object.values(usernameProfile.serverEconomy.ledger||{}).filter(function(entry){return entry.sourceType==='username_change'&&entry.amount===-5000;}).length,1);
  assert.equal((await db.ref('usernames/renamed_free').get()).exists(),false);
  assert.equal((await db.ref('usernames/renamed_paid').get()).val(),usernameFirst.localId);

  await db.ref('serverRateLimits/'+usernameFirst.localId+'/changeUsername').remove();
  await db.ref('users/'+usernameFirst.localId+'/gold').set(12000);
  const sameOwnerRace=await Promise.all([
    api('/changeUsername',usernameFirst.idToken,{username:'same_owner_a'},'username-same-owner-a'),
    api('/changeUsername',usernameFirst.idToken,{username:'same_owner_b'},'username-same-owner-b')
  ]);
  assert.equal(sameOwnerRace.every(function(result){return result.status===200;}),true,JSON.stringify(sameOwnerRace));
  usernameProfile=(await db.ref('users/'+usernameFirst.localId).get()).val();
  assert.equal(usernameProfile.username==='same_owner_a'||usernameProfile.username==='same_owner_b',true);
  assert.equal(usernameProfile.name,usernameProfile.username);
  assert.equal((await db.ref('publicProfiles/'+usernameFirst.localId+'/username').get()).val(),usernameProfile.username);
  const sameOwnerReservations=(await db.ref('usernames').orderByValue().equalTo(usernameFirst.localId).get()).val()||{};
  assert.deepEqual(Object.keys(sameOwnerReservations),[usernameProfile.username]);
  assert.equal(usernameProfile.usernameRevision,5);
  assert.equal(usernameProfile.gold,2000);

  const sharedUsernameRace=await Promise.all(Array.from({length:20},function(_,index){
    const contender=index%2===0?second:usernameSecond;
    return api('/changeUsername',contender.idToken,{username:'shared_final'},'username-shared-'+index);
  }));
  assert.equal(sharedUsernameRace.every(function(result){return result.status===200||result.status===409;}),true,JSON.stringify(sharedUsernameRace));
  const sharedOwner=(await db.ref('usernames/shared_final').get()).val();
  assert.equal(sharedOwner===second.localId||sharedOwner===usernameSecond.localId,true);
  const sharedProfiles=await Promise.all([db.ref('users/'+second.localId).get(),db.ref('users/'+usernameSecond.localId).get()]);
  assert.equal(sharedProfiles.filter(function(snapshot){return snapshot.val().username==='shared_final';}).length,1);
  const losingSnapshot=sharedProfiles.find(function(snapshot){return snapshot.val().username!=='shared_final';});
  assert.equal(losingSnapshot.val().usernameChanges||0,0);
  const winner=sharedOwner===second.localId?second:usernameSecond;
  const insufficientUsername=await api('/changeUsername',winner.idToken,{username:'needs_funds'},'username-insufficient-1');
  assert.equal(insufficientUsername.status,409,JSON.stringify(insufficientUsername.body));
  assert.equal(insufficientUsername.body.error,'insufficient-balance');
  assert.equal((await db.ref('users/'+winner.localId+'/username').get()).val(),'shared_final');
  console.error('[stage] username transaction races complete');

  const forgedOnboarding=await api('/claimOnboardingReward',usernameFirst.idToken,{gold:999999},'onboarding-forged-1');
  assert.equal(forgedOnboarding.status,400,JSON.stringify(forgedOnboarding.body));
  assert.equal(forgedOnboarding.body.error,'unexpected-field');
  const parallelOnboarding=await Promise.all(Array.from({length:20},function(_,index){
    return api('/claimOnboardingReward',usernameFirst.idToken,{},'onboarding-parallel-'+index);
  }));
  parallelOnboarding.forEach(function(result){assert.equal(result.status,200,JSON.stringify(result.body));});
  assert.equal(parallelOnboarding.filter(function(result){return result.body.granted===true;}).length,1);
  const unknownSocial=await api('/claimSocialVisitReward',usernameFirst.idToken,{missionId:'sp_fake'},'social-unknown-1');
  assert.equal(unknownSocial.status,400,JSON.stringify(unknownSocial.body));
  assert.equal(unknownSocial.body.error,'unknown-social-reward');
  const parallelSocial=await Promise.all(Array.from({length:20},function(_,index){
    return api('/claimSocialVisitReward',usernameFirst.idToken,{missionId:'sp_instagram'},'social-parallel-'+index);
  }));
  parallelSocial.forEach(function(result){assert.equal(result.status,200,JSON.stringify(result.body));});
  assert.equal(parallelSocial.filter(function(result){return result.body.granted===true;}).length,1);
  const fixedRewardProfile=(await db.ref('users/'+usernameFirst.localId).get()).val();
  assert.equal(fixedRewardProfile.gold,usernameProfile.gold+ONBOARDING_REWARD.gold);
  assert.equal(fixedRewardProfile.gems,usernameProfile.gems+SOCIAL_VISIT_REWARDS.sp_instagram.gems);
  assert.equal(fixedRewardProfile.passMissions.specialDone.sp_instagram,true);
  assert.equal(Object.values(fixedRewardProfile.serverEconomy.ledger||{}).filter(function(entry){return entry.sourceType==='onboarding_reward';}).length,1);
  assert.equal(Object.values(fixedRewardProfile.serverEconomy.ledger||{}).filter(function(entry){return entry.sourceType==='social_visit_reward';}).length,1);
  console.error('[stage] fixed one-time reward races complete');

  const privateRead=await clientDb('users/'+first.localId,second.idToken);
  assert.equal(privateRead.status,401,JSON.stringify(privateRead.body));
  const publicRead=await clientDb('publicProfiles/'+first.localId,second.idToken);
  assert.equal(publicRead.status,200,JSON.stringify(publicRead.body));
  assert.equal(publicRead.body.username,created.body.username);

  const economyTamper=await clientDb('users/'+first.localId+'/gold',first.idToken,'PUT',99999999);
  assert.equal(economyTamper.status,401,JSON.stringify(economyTamper.body));
  const usernameLeak=await clientDb('usernames/'+created.body.username,first.idToken);
  assert.equal(usernameLeak.status,401,JSON.stringify(usernameLeak.body));

  const profileUpdate=await api('/updateProfile',first.idToken,{country:'DE',bio:'Merhaba Luno',avatar:'#8844cc',activeSkin:'classic',activePieceSet:'std'},'profile-update-1');
  assert.equal(profileUpdate.status,200,JSON.stringify(profileUpdate.body));
  const updated=await db.ref('users/'+first.localId).get();
  assert.equal(updated.val().country,'DE');
  assert.equal(updated.val().bio,'Merhaba Luno');
  assert.equal(updated.val().gold,rewardProfile.gold);
  const updatedPublic=await db.ref('publicProfiles/'+first.localId).get();
  assert.equal(updatedPublic.val().bio,'Merhaba Luno');
  const lockedFrame=await api('/updateProfile',first.idToken,{frame:'royal'},'profile-locked-frame');
  assert.equal(lockedFrame.status,403,JSON.stringify(lockedFrame.body));
  assert.equal(lockedFrame.body.error,'locked-selection');
  const lockedSkin=await api('/updateProfile',first.idToken,{activeSkin:'celestial'},'profile-locked-skin');
  assert.equal(lockedSkin.status,403,JSON.stringify(lockedSkin.body));
  const lockedPieceSet=await api('/updateProfile',first.idToken,{activePieceSet:'neon'},'profile-locked-set');
  assert.equal(lockedPieceSet.status,403,JSON.stringify(lockedPieceSet.body));
  const unknownSelection=await api('/updateProfile',first.idToken,{frame:'not-a-frame'},'profile-unknown-frame');
  assert.equal(unknownSelection.status,400,JSON.stringify(unknownSelection.body));
  assert.equal(unknownSelection.body.error,'unknown-selection');
  const oversizedProfile=await api('/updateProfile',first.idToken,{bio:'x'.repeat(161)},'profile-oversized');
  assert.equal(oversizedProfile.status,400,JSON.stringify(oversizedProfile.body));
  assert.equal(oversizedProfile.body.error,'invalid-bio');
  const unexpectedProfile=await api('/updateProfile',first.idToken,{country:'TR',gold:999999},'profile-unexpected');
  assert.equal(unexpectedProfile.status,400,JSON.stringify(unexpectedProfile.body));
  assert.equal(unexpectedProfile.body.error,'unexpected-field');
  const lockedCostume=await api('/updateProfile',first.idToken,{activeCostumes:{K:'k_gold'}},'profile-locked-costume');
  assert.equal(lockedCostume.status,403,JSON.stringify(lockedCostume.body));
  const validFreeCostume=await api('/updateProfile',first.idToken,{activeCostumes:{K:'k_classic'}},'profile-free-costume');
  assert.equal(validFreeCostume.status,200,JSON.stringify(validFreeCostume.body));

  const validDeck=['barbarian','card_block','poison_q','angry_n','glue','freeze'];
  const deckUpdate=await api('/updatePreferences',first.idToken,{deck:validDeck},'deck-update-1');
  assert.equal(deckUpdate.status,200,JSON.stringify(deckUpdate.body));
  const badDeck=await api('/updatePreferences',first.idToken,{deck:['barbarian','barbarian','poison_q','angry_n','glue','freeze']},'deck-update-2');
  assert.equal(badDeck.status,400,JSON.stringify(badDeck.body));
  assert.equal(badDeck.body.error,'invalid-deck');
  const lockedEmoji=await api('/updatePreferences',first.idToken,{emojiLoadout:['rainbow']},'emoji-locked-1');
  assert.equal(lockedEmoji.status,403,JSON.stringify(lockedEmoji.body));
  assert.equal(lockedEmoji.body.error,'locked-selection');
  const unknownPreference=await api('/updatePreferences',first.idToken,{deck:validDeck,price:1},'preference-unknown-1');
  assert.equal(unknownPreference.status,400,JSON.stringify(unknownPreference.body));
  assert.equal(unknownPreference.body.error,'unexpected-field');

  await db.ref('users/'+first.localId).update({gold:100000,gems:10000});
  const forgedSoftPrice=await api('/purchaseSoftItem',first.idToken,{itemId:'frame:bronze',price:1,currency:'gold'},'soft-forged-1');
  assert.equal(forgedSoftPrice.status,400,JSON.stringify(forgedSoftPrice.body));
  assert.equal(forgedSoftPrice.body.error,'unexpected-field');
  const unknownSoftItem=await api('/purchaseSoftItem',first.idToken,{itemId:'frame:not-real'},'soft-unknown-1');
  assert.equal(unknownSoftItem.status,400,JSON.stringify(unknownSoftItem.body));
  assert.equal(unknownSoftItem.body.error,'unknown-item');
  const pollutedSoftBody=Object.create({price:1});pollutedSoftBody.itemId='frame:bronze';
  const pollutedSoftItem=await api('/purchaseSoftItem',first.idToken,pollutedSoftBody,'soft-polluted-1');
  assert.equal(pollutedSoftItem.status,400,JSON.stringify(pollutedSoftItem.body));
  assert.equal(pollutedSoftItem.body.error,'unexpected-field');
  const parallelSoftPurchase=await Promise.all(Array.from({length:20},function(_,index){
    return api('/purchaseSoftItem',first.idToken,{itemId:'frame:bronze'},'soft-parallel-'+index);
  }));
  parallelSoftPurchase.forEach(function(result){assert.equal(result.status,200,JSON.stringify(result.body));});
  assert.equal(parallelSoftPurchase.filter(function(result){return result.body.purchased===true;}).length,1);
  const softProfile=(await db.ref('users/'+first.localId).get()).val();
  assert.equal(softProfile.gold,99500);
  assert.equal(softProfile.frame,'bronze');
  assert.equal(softProfile.inventory.ownedFrames.filter(function(id){return id==='bronze';}).length,1);
  assert.equal(Object.keys(softProfile.serverEconomy.purchases||{}).length,1);
  const softReplay=await api('/purchaseSoftItem',first.idToken,{itemId:'frame:bronze'},'soft-replay-new-request');
  assert.equal(softReplay.status,200,JSON.stringify(softReplay.body));
  assert.equal(softReplay.body.idempotent,true);
  assert.equal((await db.ref('users/'+first.localId+'/gold').get()).val(),99500);
  const insufficientSoft=await api('/purchaseSoftItem',second.idToken,{itemId:'skin:celestial'},'soft-insufficient-1');
  assert.equal(insufficientSoft.status,409,JSON.stringify(insufficientSoft.body));
  assert.equal(insufficientSoft.body.error,'insufficient-balance');
  assert.equal((await db.ref('users/'+second.localId+'/gems').get()).val(),50);
  console.error('[stage] soft purchase race complete');

  await db.ref('users/'+first.localId).update({gold:10000,arenaIdx:2,trophies:300});
  await db.ref('users/'+first.localId+'/unlockedCards/trap1').set(true);
  await db.ref('users/'+first.localId+'/cardLevel/trap').set(1);
  const forgedUpgrade=await api('/upgradeCard',first.idToken,{family:'trap',targetLevel:2,price:1},'upgrade-forged-1');
  assert.equal(forgedUpgrade.status,400,JSON.stringify(forgedUpgrade.body));
  assert.equal(forgedUpgrade.body.error,'unexpected-field');
  const skippedUpgrade=await api('/upgradeCard',first.idToken,{family:'trap',targetLevel:3},'upgrade-skip-1');
  assert.equal(skippedUpgrade.status,409,JSON.stringify(skippedUpgrade.body));
  assert.equal(skippedUpgrade.body.error,'upgrade-sequence');
  const parallelUpgrade=await Promise.all(Array.from({length:20},function(_,index){
    return api('/upgradeCard',first.idToken,{family:'trap',targetLevel:2},'upgrade-parallel-'+index);
  }));
  parallelUpgrade.forEach(function(result){assert.equal(result.status,200,JSON.stringify(result.body));});
  assert.equal(parallelUpgrade.filter(function(result){return result.body.upgraded===true;}).length,1);
  const upgradedProfile=(await db.ref('users/'+first.localId).get()).val();
  assert.equal(upgradedProfile.cardLevel.trap,2);
  assert.equal(upgradedProfile.gold,7500);
  const arenaLockedUpgrade=await api('/upgradeCard',first.idToken,{family:'trap',targetLevel:3},'upgrade-arena-1');
  assert.equal(arenaLockedUpgrade.status,409,JSON.stringify(arenaLockedUpgrade.body));
  assert.equal(arenaLockedUpgrade.body.error,'arena-locked');
  const upgradeBucket=Math.floor(Date.now()/(60*1000));
  await db.ref('serverRateLimits/'+first.localId+'/upgradeCard/'+upgradeBucket).set(40);
  const upgradeRateLimited=await api('/upgradeCard',first.idToken,{family:'trap',targetLevel:3},'upgrade-rate-limit-1');
  assert.equal(upgradeRateLimited.status,429,JSON.stringify(upgradeRateLimited.body));
  assert.equal(upgradeRateLimited.body.error,'rate-limited');
  console.error('[stage] card upgrade race complete');

  await db.ref('users/'+first.localId+'/gold').set(10000);
  const parallelChest=await Promise.all(Array.from({length:20},function(){
    return api('/openChest',first.idToken,{chestId:'common'},'chest-same-request','https://localhost',90000);
  }));
  assert.equal(parallelChest.every(function(result){return result.status===200||result.status===409;}),true);
  const openedChest=parallelChest.find(function(result){return result.status===200&&result.body.opened===true&&result.body.idempotent!==true;});
  assert.equal(!!openedChest,true,JSON.stringify(parallelChest));
  assert.equal(parallelChest.filter(function(result){return result.body&&result.body.opened===true&&result.body.idempotent!==true;}).length,1);
  const chestGold=openedChest.body.rewards.filter(function(reward){return reward.type==='gold';}).reduce(function(sum,reward){return sum+reward.amount;},0);
  const chestProfile=(await db.ref('users/'+first.localId).get()).val();
  assert.equal(chestProfile.gold,10000-500+chestGold);
  assert.equal(chestProfile.stats.chestsOpened,1);
  assert.equal(Object.values(chestProfile.serverEconomy.purchases||{}).filter(function(purchase){return purchase.itemType==='chest';}).length,1);
  const chestReplay=await api('/openChest',first.idToken,{chestId:'common'},'chest-same-request');
  assert.equal(chestReplay.status,200,JSON.stringify(chestReplay.body));
  assert.equal(chestReplay.body.idempotent,true);
  assert.equal((await db.ref('users/'+first.localId+'/stats/chestsOpened').get()).val(),1);
  const chestRequestConflict=await api('/openChest',first.idToken,{chestId:'rare'},'chest-same-request');
  assert.equal(chestRequestConflict.status,409,JSON.stringify(chestRequestConflict.body));
  assert.equal(chestRequestConflict.body.error,'request-id-conflict');
  const forgedChest=await api('/openChest',first.idToken,{chestId:'common',amount:999999},'chest-forged-1');
  assert.equal(forgedChest.status,400,JSON.stringify(forgedChest.body));
  assert.equal(forgedChest.body.error,'unexpected-field');
  console.error('[stage] chest replay race complete');

  await db.ref('users/'+second.localId).update({trophies:300,arenaIdx:2});
  const firstBeforeRanked=(await db.ref('users/'+first.localId).get()).val();
  const secondBeforeRanked=(await db.ref('users/'+second.localId).get()).val();
  const queued=await api('/enqueueRanked',first.idToken,{},'ranked-queue-first');
  assert.equal(queued.status,200,JSON.stringify(queued.body));
  assert.equal(queued.body.status,'queued');
  const matched=await api('/enqueueRanked',second.idToken,{},'ranked-queue-second');
  assert.equal(matched.status,200,JSON.stringify(matched.body));
  assert.equal(matched.body.status,'matched');
  assert.match(matched.body.matchId,/^rm_[a-f0-9]{32}$/);
  const matchId=matched.body.matchId;
  const firstMatch=await api('/getRankedMatch',first.idToken,{matchId},'ranked-get-first');
  const secondMatch=await api('/getRankedMatch',second.idToken,{matchId},'ranked-get-second');
  assert.equal(firstMatch.status,200,JSON.stringify(firstMatch.body));
  assert.equal(secondMatch.status,200,JSON.stringify(secondMatch.body));
  assert.notEqual(firstMatch.body.view.viewerColor,secondMatch.body.view.viewerColor);
  const rankedUsers={};rankedUsers[firstMatch.body.view.viewerColor]=first;rankedUsers[secondMatch.body.view.viewerColor]=second;
  const rankedPreset=await api('/sendRankedMessage',first.idToken,{matchId,kind:'preset',id:'gl',tab:'greetings'},'ranked-chat-preset');
  assert.equal(rankedPreset.status,200,JSON.stringify(rankedPreset.body));
  assert.equal(rankedPreset.body.message.id,'gl');
  assert.equal(Object.prototype.hasOwnProperty.call(rankedPreset.body.message,'glyph'),false);
  const firstChatFeed=await clientDb('rankedMessages/'+first.localId+'/'+matchId,first.idToken);
  const secondChatFeed=await clientDb('rankedMessages/'+second.localId+'/'+matchId,second.idToken);
  assert.equal(firstChatFeed.status,200,JSON.stringify(firstChatFeed.body));
  assert.equal(secondChatFeed.status,200,JSON.stringify(secondChatFeed.body));
  assert.equal(firstChatFeed.body.messageId,rankedPreset.body.message.messageId);
  const crossChatRead=await clientDb('rankedMessages/'+second.localId+'/'+matchId,first.idToken);
  assert.equal(crossChatRead.status,401,JSON.stringify(crossChatRead.body));
  const forgedChatWrite=await clientDb('rankedMessages/'+first.localId+'/'+matchId,first.idToken,'PUT',{id:'fake',glyph:'<script>'});
  assert.equal(forgedChatWrite.status,401,JSON.stringify(forgedChatWrite.body));
  const lockedRankedEmoji=await api('/sendRankedMessage',second.idToken,{matchId,kind:'emoji',id:'rainbow',tab:'emojis'},'ranked-chat-locked-emoji');
  assert.equal(lockedRankedEmoji.status,403,JSON.stringify(lockedRankedEmoji.body));
  assert.equal(lockedRankedEmoji.body.error,'emoji-not-owned');
  const ownedRankedEmoji=await api('/sendRankedMessage',second.idToken,{matchId,kind:'emoji',id:'smile',tab:'emojis'},'ranked-chat-owned-emoji');
  assert.equal(ownedRankedEmoji.status,200,JSON.stringify(ownedRankedEmoji.body));
  console.error('[stage] authoritative ranked chat complete');
  let sequence=0,lastAction=null;
  const rankedMoves=[
    {color:'W',from:13,to:21,id:'ranked-white-f2-f3'},
    {color:'B',from:52,to:36,id:'ranked-black-e7-e5'},
    {color:'W',from:14,to:30,id:'ranked-white-g2-g4'},
    {color:'B',from:59,to:31,id:'ranked-black-mate'}
  ];
  for(let index=0;index<rankedMoves.length;index++){
    const move=rankedMoves[index];
    lastAction=await api('/submitMatchAction',rankedUsers[move.color].idToken,{matchId,type:'move',actionId:move.id,expectedSequence:sequence,from:move.from,to:move.to},'ranked-action-'+index);
    assert.equal(lastAction.status,200,JSON.stringify(lastAction.body));
    sequence=lastAction.body.view.sequence;
  }
  assert.equal(lastAction.body.view.status,'finished');
  assert.equal(lastAction.body.view.result.winner,'B');
  assert.equal(lastAction.body.view.result.reason,'checkmate');
  const finalMove=rankedMoves[rankedMoves.length-1];
  const finalReplay=await api('/submitMatchAction',rankedUsers.B.idToken,{matchId,type:'move',actionId:finalMove.id,expectedSequence:sequence-1,from:finalMove.from,to:finalMove.to},'ranked-final-replay');
  assert.equal(finalReplay.status,200,JSON.stringify(finalReplay.body));
  assert.equal(finalReplay.body.idempotent,true);
  assert.equal(finalReplay.body.view.sequence,sequence);
  assert.equal((await db.ref('rankedState/activeByUser/'+first.localId).get()).exists(),false);
  assert.equal((await db.ref('rankedState/activeByUser/'+second.localId).get()).exists(),false);
  assert.equal((await db.ref('matchHistory/'+first.localId+'/'+matchId).get()).exists(),true);
  assert.equal((await db.ref('rankedReplays/'+second.localId+'/'+matchId).get()).exists(),true);
  const firstAfterRanked=(await db.ref('users/'+first.localId).get()).val();
  const secondAfterRanked=(await db.ref('users/'+second.localId).get()).val();
  const winnerBefore=rankedUsers.B.localId===first.localId?firstBeforeRanked:secondBeforeRanked;
  const winnerAfter=rankedUsers.B.localId===first.localId?firstAfterRanked:secondAfterRanked;
  const loserBefore=rankedUsers.W.localId===first.localId?firstBeforeRanked:secondBeforeRanked;
  const loserAfter=rankedUsers.W.localId===first.localId?firstAfterRanked:secondAfterRanked;
  assert.equal(winnerAfter.stats.wins,winnerBefore.stats.wins+1);
  assert.equal(loserAfter.stats.losses,loserBefore.stats.losses+1);
  const canonicalRead=await clientDb('rankedState/matches/'+matchId,first.idToken);
  assert.equal(canonicalRead.status,401,JSON.stringify(canonicalRead.body));
  const ownerView=await clientDb('rankedMatchViews/'+first.localId+'/'+matchId,first.idToken);
  assert.equal(ownerView.status,200,JSON.stringify(ownerView.body));
  const otherView=await clientDb('rankedMatchViews/'+second.localId+'/'+matchId,first.idToken);
  assert.equal(otherView.status,401,JSON.stringify(otherView.body));
  const forgedRankedWrite=await clientDb('rankedMatchViews/'+first.localId+'/'+matchId,first.idToken,'PUT',{winner:'W',gold:999999});
  assert.equal(forgedRankedWrite.status,401,JSON.stringify(forgedRankedWrite.body));
  console.error('[stage] authoritative ranked match and settlement complete');

  const presence=await clientDb('presence/'+first.localId,first.idToken,'PUT',{online:true,lastSeen:Date.now()});
  assert.equal(presence.status,200,JSON.stringify(presence.body));
  const forgedPresence=await clientDb('presence/'+second.localId,first.idToken,'PUT',{online:true,lastSeen:Date.now()});
  assert.equal(forgedPresence.status,401,JSON.stringify(forgedPresence.body));

  const friendRequest=await api('/sendFriendRequest',first.idToken,{targetUid:second.localId},'friend-send-1');
  assert.equal(friendRequest.status,200,JSON.stringify(friendRequest.body));
  assert.equal(friendRequest.body.status,'sent');
  const duplicateFriendRequest=await api('/sendFriendRequest',first.idToken,{targetUid:second.localId},'friend-send-duplicate-1');
  assert.equal(duplicateFriendRequest.status,200,JSON.stringify(duplicateFriendRequest.body));
  assert.equal(duplicateFriendRequest.body.status,'pending');
  const friendNotifications=(await db.ref('notifications/'+second.localId).get()).val()||{};
  assert.equal(Object.values(friendNotifications).filter(value=>value.type==='friend_request').length,1);
  const invalidFriendResponse=await api('/respondFriendRequest',second.idToken,{fromUid:first.localId,accept:'true'},'friend-accept-invalid-type');
  assert.equal(invalidFriendResponse.status,400,JSON.stringify(invalidFriendResponse.body));
  assert.equal(invalidFriendResponse.body.error,'invalid-request-response');
  const incomingRequest=await clientDb('friendRequests/'+second.localId+'/'+first.localId,second.idToken);
  assert.equal(incomingRequest.status,200,JSON.stringify(incomingRequest.body));
  assert.equal(incomingRequest.body.fromUid,first.localId);
  const forgedFriendship=await clientDb('friends/'+first.localId+'/'+second.localId,first.idToken,'PUT',{addedAt:Date.now()});
  assert.equal(forgedFriendship.status,401,JSON.stringify(forgedFriendship.body));

  const accepted=await api('/respondFriendRequest',second.idToken,{fromUid:first.localId,accept:true},'friend-accept-1');
  assert.equal(accepted.status,200,JSON.stringify(accepted.body));
  assert.equal(accepted.body.accepted,true);
  assert.equal((await db.ref('friends/'+first.localId+'/'+second.localId).get()).exists(),true);
  assert.equal((await db.ref('friends/'+second.localId+'/'+first.localId).get()).exists(),true);
  const acceptedNotifications=(await db.ref('notifications/'+first.localId).get()).val()||{};
  assert.equal(Object.values(acceptedNotifications).filter(value=>value.type==='friend_accepted').length,1);

  const forgedInvite=await clientDb('matchInvites/'+second.localId+'/'+first.localId,first.idToken,'PUT',{fromUid:first.localId,sentAt:Date.now()});
  assert.equal(forgedInvite.status,401,JSON.stringify(forgedInvite.body));
  const beforeFriendlyFirst=(await db.ref('users/'+first.localId).get()).val();
  const beforeFriendlySecond=(await db.ref('users/'+second.localId).get()).val();
  const invalidFriendlyDuration=await api('/sendMatchInvite',first.idToken,{targetUid:second.localId,durationMinutes:2},'friendly-invite-invalid-duration');
  assert.equal(invalidFriendlyDuration.status,400,JSON.stringify(invalidFriendlyDuration.body));
  assert.equal(invalidFriendlyDuration.body.error,'invalid-time-control');
  const sentInvite=await api('/sendMatchInvite',first.idToken,{targetUid:second.localId,durationMinutes:3},'friendly-invite-send-1');
  assert.equal(sentInvite.status,200,JSON.stringify(sentInvite.body));
  assert.equal(sentInvite.body.sent,true);
  assert.equal(sentInvite.body.durationMinutes,3);
  const duplicateInvite=await api('/sendMatchInvite',first.idToken,{targetUid:second.localId,durationMinutes:3},'friendly-invite-send-duplicate-1');
  assert.equal(duplicateInvite.status,200,JSON.stringify(duplicateInvite.body));
  assert.equal(duplicateInvite.body.status,'pending');
  const incomingInvite=await clientDb('matchInvites/'+second.localId+'/'+first.localId,second.idToken);
  assert.equal(incomingInvite.status,200,JSON.stringify(incomingInvite.body));
  assert.equal(incomingInvite.body.status,'pending');
  assert.equal(incomingInvite.body.durationMinutes,3);
  const acceptedInviteAttempts=await Promise.all([
    api('/respondMatchInvite',second.idToken,{fromUid:first.localId,accept:true},'friendly-invite-accept-1'),
    api('/respondMatchInvite',second.idToken,{fromUid:first.localId,accept:true},'friendly-invite-accept-2')
  ]);
  const acceptedInvite=acceptedInviteAttempts.find(function(result){return result.status===200;});
  assert.ok(acceptedInvite,JSON.stringify(acceptedInviteAttempts));
  assert.equal(acceptedInvite.body.accepted,true);
  assert.match(acceptedInvite.body.matchId,/^fm_[a-f0-9]{32}$/);
  assert.equal(acceptedInvite.body.view.mode,'friendly');
  assert.equal(acceptedInvite.body.view.timeControlMinutes,3);
  assert.equal(acceptedInvite.body.view.clock.initialMs,3*60*1000);
  const friendlyMatchId=acceptedInvite.body.matchId;
  const friendlyFirst=await api('/getRankedMatch',first.idToken,{matchId:friendlyMatchId},'friendly-get-first');
  assert.equal(friendlyFirst.status,200,JSON.stringify(friendlyFirst.body));
  assert.equal(friendlyFirst.body.view.mode,'friendly');
  const friendlyResign=await api('/submitMatchAction',first.idToken,{matchId:friendlyMatchId,type:'resign',actionId:'friendly-resign-1',expectedSequence:0},'friendly-action-resign-1');
  assert.equal(friendlyResign.status,200,JSON.stringify(friendlyResign.body));
  assert.equal(friendlyResign.body.view.status,'finished');
  assert.equal(friendlyResign.body.view.settlement.trophyDelta,0);
  const afterFriendlyFirst=(await db.ref('users/'+first.localId).get()).val();
  const afterFriendlySecond=(await db.ref('users/'+second.localId).get()).val();
  for(const key of ['trophies','gold','gems','xp']){
    assert.equal(afterFriendlyFirst[key],beforeFriendlyFirst[key],key+' changed for friendly player one');
    assert.equal(afterFriendlySecond[key],beforeFriendlySecond[key],key+' changed for friendly player two');
  }
  assert.deepEqual(afterFriendlyFirst.stats,beforeFriendlyFirst.stats);
  assert.deepEqual(afterFriendlySecond.stats,beforeFriendlySecond.stats);
  assert.equal((await db.ref('matchHistory/'+first.localId+'/'+friendlyMatchId+'/mode').get()).val(),'friendly');

  const removedFriend=await api('/removeFriend',first.idToken,{targetUid:second.localId},'friend-remove-1');
  assert.equal(removedFriend.status,200,JSON.stringify(removedFriend.body));
  assert.equal(removedFriend.body.removed,true);
  assert.equal((await db.ref('friends/'+first.localId+'/'+second.localId).get()).exists(),false);
  assert.equal((await db.ref('friends/'+second.localId+'/'+first.localId).get()).exists(),false);

  const createdRoom=await api('/createFriendlyRoom',first.idToken,{durationMinutes:30},'friendly-room-create-1');
  assert.equal(createdRoom.status,200,JSON.stringify(createdRoom.body));
  assert.match(createdRoom.body.roomCode,/^[A-Z0-9]{6}$/);
  assert.equal(createdRoom.body.durationMinutes,30);
  const privateRoomRead=await clientDb('friendlyRooms/'+createdRoom.body.roomCode,first.idToken);
  assert.equal(privateRoomRead.status,401,JSON.stringify(privateRoomRead.body));
  const joinedRoom=await api('/joinFriendlyRoom',second.idToken,{roomCode:createdRoom.body.roomCode},'friendly-room-join-1');
  assert.equal(joinedRoom.status,200,JSON.stringify(joinedRoom.body));
  assert.equal(joinedRoom.body.view.mode,'friendly');
  assert.equal(joinedRoom.body.view.timeControlMinutes,30);
  assert.equal(joinedRoom.body.view.clock.initialMs,30*60*1000);
  assert.match(joinedRoom.body.matchId,/^fm_[a-f0-9]{32}$/);
  assert.equal((await db.ref('friendlyRooms/'+createdRoom.body.roomCode).get()).exists(),false);
  const roomResign=await api('/submitMatchAction',second.idToken,{matchId:joinedRoom.body.matchId,type:'resign',actionId:'friendly-room-resign-1',expectedSequence:0},'friendly-room-action-1');
  assert.equal(roomResign.status,200,JSON.stringify(roomResign.body));
  const cancellableRoom=await api('/createFriendlyRoom',first.idToken,{},'friendly-room-create-2');
  assert.equal(cancellableRoom.status,200,JSON.stringify(cancellableRoom.body));
  const cancelledRoom=await api('/cancelFriendlyRoom',first.idToken,{roomCode:cancellableRoom.body.roomCode},'friendly-room-cancel-1');
  assert.equal(cancelledRoom.status,200,JSON.stringify(cancelledRoom.body));
  assert.equal(cancelledRoom.body.cancelled,true);
  console.error('[stage] server-authoritative friendly invitations and rooms complete');

  const secondProfile=(await db.ref('users/'+second.localId).get()).val();
  const usernameQuery=String(secondProfile.username).toLowerCase();
  const usernameSearch=await api('/searchPlayers',first.idToken,{query:usernameQuery},'player-search-username-1');
  assert.equal(usernameSearch.status,200,JSON.stringify(usernameSearch.body));
  assert.equal(usernameSearch.body.results.some(function(player){return player.uid===second.localId;}),true);
  const codeSearch=await api('/searchPlayers',first.idToken,{query:String(secondProfile.playerCode).toLowerCase()},'player-search-code-1');
  assert.equal(codeSearch.status,200,JSON.stringify(codeSearch.body));
  assert.equal(codeSearch.body.results[0].uid,second.localId);

  const opened=await api('/openDirectMessage',first.idToken,{targetUid:second.localId},'dm-open-1');
  assert.equal(opened.status,200,JSON.stringify(opened.body));
  assert.equal(typeof opened.body.conversationId,'string');
  const forgedMessage=await clientDb('dm/'+opened.body.conversationId+'/msgs/forged',first.idToken,'PUT',{from:first.localId,text:'forged',ts:Date.now()});
  assert.equal(forgedMessage.status,401,JSON.stringify(forgedMessage.body));
  const acceptedLegal=await api('/acceptLegalTerms',first.idToken,{},'dm-legal-accept-1');
  assert.equal(acceptedLegal.status,200,JSON.stringify(acceptedLegal.body));
  assert.equal(acceptedLegal.body.legalConsent.accepted,true);
  const sentMessage=await api('/sendDirectMessage',first.idToken,{targetUid:second.localId,text:'Selam Luno'},'dm-send-1');
  assert.equal(sentMessage.status,200,JSON.stringify(sentMessage.body));
  assert.equal(typeof sentMessage.body.messageId,'string');
  assert.equal((await db.ref('dm/'+opened.body.conversationId+'/msgs/'+sentMessage.body.messageId).get()).val().text,'Selam Luno');
  assert.equal((await db.ref('dmInbox/'+second.localId+'/'+first.localId).get()).val().unread,true);
  const throttledMessage=await api('/sendDirectMessage',first.idToken,{targetUid:second.localId,text:'İkinci mesaj'},'dm-send-throttled-1');
  assert.equal(throttledMessage.status,429,JSON.stringify(throttledMessage.body));
  assert.equal(throttledMessage.body.error,'message-rate-limited');
  const unsafeMessage=await api('/sendDirectMessage',first.idToken,{targetUid:second.localId,text:'<script>alert(1)</script>'},'dm-send-unsafe-1');
  assert.equal(unsafeMessage.status,400,JSON.stringify(unsafeMessage.body));
  assert.equal(unsafeMessage.body.error,'invalid-message');
  const markedRead=await api('/markDirectMessageRead',second.idToken,{targetUid:first.localId,lastMessageId:sentMessage.body.messageId},'dm-read-1');
  assert.equal(markedRead.status,200,JSON.stringify(markedRead.body));
  assert.equal(markedRead.body.marked,true);
  assert.equal((await db.ref('dmInbox/'+second.localId+'/'+first.localId+'/unread').get()).val(),false);

  const muted=await api('/setConversationMuted',second.idToken,{targetUid:first.localId,muted:true},'dm-mute-1');
  assert.equal(muted.status,200,JSON.stringify(muted.body));
  assert.equal(muted.body.muted,true);
  const reopened=await api('/openDirectMessage',second.idToken,{targetUid:first.localId},'dm-open-muted-1');
  assert.equal(reopened.status,200,JSON.stringify(reopened.body));
  assert.equal(reopened.body.muted,true);
  const messageReport=await api('/reportMessage',second.idToken,{targetUid:first.localId,messageId:sentMessage.body.messageId,reason:'harassment'},'report-message-1');
  assert.equal(messageReport.status,200,JSON.stringify(messageReport.body));
  assert.equal((await db.ref('moderationReports/'+messageReport.body.reportId).get()).val().messageId,sentMessage.body.messageId);
  const invalidReport=await api('/reportUser',second.idToken,{targetUid:first.localId,reason:'anything-goes',details:''},'report-invalid-1');
  assert.equal(invalidReport.status,400,JSON.stringify(invalidReport.body));
  assert.equal(invalidReport.body.error,'invalid-report-reason');
  const userReport=await api('/reportUser',second.idToken,{targetUid:first.localId,reason:'spam',details:'Tekrarlanan istekler'},'report-user-1');
  assert.equal(userReport.status,200,JSON.stringify(userReport.body));

  const blocked=await api('/blockUser',second.idToken,{targetUid:first.localId},'block-user-1');
  assert.equal(blocked.status,200,JSON.stringify(blocked.body));
  assert.equal((await db.ref('blocks/'+second.localId+'/'+first.localId).get()).exists(),true);
  assert.equal((await db.ref('friends/'+second.localId+'/'+first.localId).get()).exists(),false);
  const blockedMessage=await api('/sendDirectMessage',first.idToken,{targetUid:second.localId,text:'Engeli aşamaz'},'dm-block-bypass-1');
  assert.equal(blockedMessage.status,403,JSON.stringify(blockedMessage.body));
  assert.equal(blockedMessage.body.error,'user-blocked');
  const blockedFriendRequest=await api('/sendFriendRequest',first.idToken,{targetUid:second.localId},'friend-block-bypass-1');
  assert.equal(blockedFriendRequest.status,403,JSON.stringify(blockedFriendRequest.body));
  const blockedMatchInvite=await api('/sendMatchInvite',first.idToken,{targetUid:second.localId},'friendly-block-bypass-1');
  assert.equal(blockedMatchInvite.status,403,JSON.stringify(blockedMatchInvite.body));
  const blockedSearch=await api('/searchPlayers',first.idToken,{query:usernameQuery},'player-search-blocked-1');
  assert.equal(blockedSearch.status,200,JSON.stringify(blockedSearch.body));
  assert.equal(blockedSearch.body.results.some(function(player){return player.uid===second.localId;}),false);
  const blockedList=await api('/listBlockedUsers',second.idToken,{},'blocked-list-1');
  assert.equal(blockedList.status,200,JSON.stringify(blockedList.body));
  assert.equal(blockedList.body.results.some(function(player){return player.uid===first.localId;}),true);
  const forgedBlock=await clientDb('blocks/'+second.localId+'/'+first.localId,second.idToken,'DELETE');
  assert.equal(forgedBlock.status,401,JSON.stringify(forgedBlock.body));

  const badOrigin=await api('/updateProfile',first.idToken,{country:'TR'},'origin-test-1','https://attacker.example');
  assert.equal(badOrigin.status,403,JSON.stringify(badOrigin.body));
  const unknown=await api('/notARealRoute',first.idToken,{},'unknown-route-1');
  assert.equal(unknown.status,404,JSON.stringify(unknown.body));

  const deletion=await api('/deleteAccount',first.idToken,{confirm:true},'delete-account-1');
  assert.equal(deletion.status,200,JSON.stringify(deletion.body));
  assert.equal((await db.ref('users/'+first.localId).get()).exists(),false);
  assert.equal((await db.ref('publicProfiles/'+first.localId).get()).exists(),false);
  assert.equal((await db.ref('friends/'+second.localId+'/'+first.localId).get()).exists(),false);
  assert.equal((await db.ref('dm/'+opened.body.conversationId).get()).exists(),false);
  await assert.rejects(getAuth(adminApp).getUser(first.localId),/no user record|user-not-found/i);

  console.log(JSON.stringify({result:'pass',baseChecks:240,parallelRewardRequests:240,parallelUsernameRequests:60,parallelFixedRewardRequests:40,parallelSoftPurchaseRequests:20,parallelCardUpgradeRequests:20,parallelChestRequests:20,parallelGoogleLinkRequests:5,rewardSources:7,uid:first.localId},null,2));
  await deleteApp(adminApp);
  process.exit(0);
}

main().catch(async function(error){
  console.error(error);
  await deleteApp(adminApp).catch(function(){});
  process.exit(1);
});
