'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {
  normalizeUsername,usernameValidationError,canonicalUsername,applyUsernameProfileChange,starterProfile,validateDeck,validUid,conversationId,PRODUCT_CATALOG,hash,assertBodyKeys,verifyAppAttestation,APP_CHECK_EMULATOR_TOKEN,friendlyDurationMinutes,
  tokenHasProvider,profileHasProtectedProgress,linkAttemptId,
  SERVER_SCHEMA_VERSION,applyDailyRewardClaim,applyRewardClaim,applySoftPurchase,economySnapshot,periodSnapshot,utcDayKey,utcDayOrdinal,
  achievementValue,achievementSchedule,rewardSchedule,selectedMissionIds,grantMissionPassXp,syncServerPass,MISSION_CATALOG,ACHIEVEMENT_CATALOG,
  PASS_CURRENCY_REWARDS,PASS_CONTENT_REWARDS,SOFT_ITEM_CATALOG,CARD_UPGRADE_CATALOG,CHEST_CATALOG,softItemOwned,grantSoftItem,grantPassContent,serverInventory,rollChest,applyChestInventoryRewards,knownSelection,
  LEADERBOARD_MAX_LIMIT,normalizeLeaderboardLimit,leaderboardRows,collectionScoreForProfile,AUTH_FALLBACK_ROUTES,applyRankedSettlement,
  seasonState,seasonBounds,normalizeSeasonRecord,SEASON_PATH_REWARDS,sourceClaimKey,canonicalDeckForProfile,canonicalPieceSetId,
  ONBOARDING_REWARD,SOCIAL_VISIT_REWARDS,USERNAME_CHANGE_COST,subscriptionExpiry,subscriptionLifecycle,applyVerifiedPurchaseGrant,applyVoidedPurchaseRevocation,decodeRtdnNotification,rtdnKind
}=require('../index.js')._test;

function appCheckRequest(token){
  return {get:function(name){return String(name).toLowerCase()==='x-firebase-appcheck'?(token||''):'';}};
}

test('App Check accepts current and legacy verified token shapes and rejects invalid tokens',async function(){
  const current=await verifyAppAttestation(appCheckRequest('current-valid-token'),{verifyToken:async function(){return {appId:'app-current',token:{sub:'app-current',aud:['projects/luno-chess']}};}});
  assert.equal(current.app_id,'app-current');
  assert.equal(current.appId,'app-current');
  assert.deepEqual(current.aud,['projects/luno-chess']);
  const legacy=await verifyAppAttestation(appCheckRequest('legacy-valid-token'),{verifyToken:async function(){return {app_id:'app-legacy'};}});
  assert.equal(legacy.app_id,'app-legacy');
  await assert.rejects(verifyAppAttestation(appCheckRequest('')),{code:'app-check-required'});
  await assert.rejects(verifyAppAttestation(appCheckRequest('fake-token'),{verifyToken:async function(){throw new Error('bad-signature');}}),{code:'invalid-app-check'});
  await assert.rejects(verifyAppAttestation(appCheckRequest('expired-token'),{verifyToken:async function(){throw new Error('expired');}}),{code:'invalid-app-check'});
  const previous=process.env.FIREBASE_AUTH_EMULATOR_HOST;
  delete process.env.FIREBASE_AUTH_EMULATOR_HOST;
  try{
    await assert.rejects(verifyAppAttestation(appCheckRequest(APP_CHECK_EMULATOR_TOKEN)),{code:'invalid-app-check'});
  }finally{
    if(previous===undefined)delete process.env.FIREBASE_AUTH_EMULATOR_HOST;
    else process.env.FIREBASE_AUTH_EMULATOR_HOST=previous;
  }
});

test('App Check permits an authenticated availability fallback only when the caller opts in',async function(){
  const fallback=await verifyAppAttestation(appCheckRequest(''),{allowAuthFallback:true});
  assert.equal(fallback.degraded,true);
  assert.equal(fallback.tokenType,'firebase-auth');
  assert.equal(fallback.app_id,'firebase-auth-fallback');
  await assert.rejects(
    verifyAppAttestation(appCheckRequest('invalid-present-token'),{allowAuthFallback:true,verifyToken:async function(){throw new Error('bad-signature');}}),
    {code:'invalid-app-check'}
  );
});

test('production routes do not downgrade to Firebase Auth without App Check',function(){
  assert.equal(AUTH_FALLBACK_ROUTES.size,0);
});

test('public profile exposes server-derived games played for social views',function(){
  const profile=starterProfile('uid-social','social_player');
  profile.stats={wins:4,losses:3,draws:2};
  const publicProfile=require('../index.js')._test.publicProfile;
  assert.equal(publicProfile(profile,Date.now()).gamesPlayed,9);
});

test('collection score is derived from unique unlocked cards for profiles and rankings',function(){
  const profile=starterProfile('uid-collection','collection_player');
  assert.equal(collectionScoreForProfile(profile),135);
  profile.unlockedCards.trap1=true;
  profile.unlockedCards.trap2=true;
  profile.unlockedCards.immunity=true;
  assert.equal(collectionScoreForProfile(profile),650);
  const publicView=require('../index.js')._test.publicProfile(profile,Date.now());
  assert.equal(publicView.collectionScore,650);
  const rows=leaderboardRows({[profile.uid]:profile},'collection',10,profile.uid);
  assert.equal(rows[0].collectionScore,650);
  const mirroredRows=leaderboardRows({[profile.uid]:publicView},'collection',10,profile.uid);
  assert.equal(mirroredRows[0].collectionScore,650);
});

test('friendly time controls accept the published choices and reject forged durations',function(){
  for(const minutes of [1,3,5,10,30])assert.equal(friendlyDurationMinutes(minutes),minutes);
  assert.equal(friendlyDurationMinutes(undefined),5);
  for(const minutes of [0,2,4,60,'five'])assert.throws(function(){friendlyDurationMinutes(minutes);},/1, 3, 5, 10 or 30 minutes/);
});

test('username normalization applies NFKC before lowercase validation',function(){
  assert.equal(normalizeUsername('  Ｌｕｎｏ＿１２  '),'luno_12');
});

test('username policy rejects reserved, abusive and malformed names',function(){
  assert.equal(usernameValidationError('normal_player'),'');
  assert.equal(usernameValidationError('ADMIN'),'username-not-allowed');
  assert.equal(usernameValidationError('luno_support'),'username-not-allowed');
  assert.equal(usernameValidationError('a'),'invalid-username');
});

test('username input is type-safe and canonical display never trusts a stale name field',function(){
  assert.equal(normalizeUsername(123),'');
  assert.equal(usernameValidationError(123),'invalid-username');
  const profile={uid:'uid-canonical',username:'Current_Name',name:'Old Name'};
  assert.equal(canonicalUsername(profile,profile.uid),'current_name');
  const publicProfile=require('../index.js')._test.publicProfile(profile,Date.now());
  assert.equal(publicProfile.name,'current_name');
  assert.equal(publicProfile.username,'current_name');
});

test('username change is free once, then debits exactly 5000 gold with a ledger record',function(){
  const profile=starterProfile('uid-name','first_name');
  const first=applyUsernameProfileChange(profile,'uid-name','second_name',Date.parse('2026-08-09T12:00:00Z'));
  assert.equal(first.changed,true);
  assert.equal(first.cost,0);
  assert.equal(profile.gold,1250);
  assert.equal(profile.usernameChanges,1);
  profile.gold=6000;
  const second=applyUsernameProfileChange(profile,'uid-name','third_name',Date.parse('2026-08-09T12:01:00Z'));
  assert.equal(second.changed,true);
  assert.equal(second.cost,USERNAME_CHANGE_COST);
  assert.equal(profile.gold,1000);
  assert.equal(Object.values(profile.serverEconomy.ledger).filter(function(entry){return entry.sourceType==='username_change'&&entry.amount===-5000;}).length,1);
  const replay=applyUsernameProfileChange(profile,'uid-name','third_name',Date.parse('2026-08-09T12:02:00Z'));
  assert.equal(replay.changed,false);
  assert.equal(profile.gold,1000);
});

test('paid username change leaves the profile untouched when server balance is insufficient',function(){
  const profile=starterProfile('uid-name-low','first_name');
  profile.usernameChanges=1;
  const before=JSON.parse(JSON.stringify(profile));
  const result=applyUsernameProfileChange(profile,'uid-name-low','next_name',Date.parse('2026-08-09T12:00:00Z'));
  assert.equal(result.error,'insufficient-balance');
  assert.deepEqual(profile,before);
});

test('starter profile grants the launch economy once in one object',function(){
  const profile=starterProfile('uid-1','luno_12');
  assert.equal(profile.uid,'uid-1');
  assert.equal(profile.username,'luno_12');
  assert.equal(profile.starterGrantVersion,2);
  assert.equal(profile.gold,1250);
  assert.equal(profile.gems,50);
  assert.equal(profile.deck.length,6);
  assert.deepEqual(profile.inventory.ownedEmojis,['smile']);
  assert.equal(profile.passState.premium,false);
});

test('Google-link provider and guest-progress checks fail closed',function(){
  assert.equal(tokenHasProvider({firebase:{sign_in_provider:'google.com'}},'google.com'),true);
  assert.equal(tokenHasProvider({firebase:{sign_in_provider:'anonymous',identities:{'google.com':['provider-1']}}},'google.com'),true);
  assert.equal(tokenHasProvider({firebase:{sign_in_provider:'anonymous'}},'google.com'),false);
  const pristine=starterProfile('uid-google','google_guest');
  assert.equal(profileHasProtectedProgress(pristine),false);
  pristine.stats.wins=1;
  assert.equal(profileHasProtectedProgress(pristine),true);
  assert.equal(linkAttemptId('uid-google','request-1'),linkAttemptId('uid-google','request-1'));
  assert.notEqual(linkAttemptId('uid-google','request-1'),linkAttemptId('uid-google','request-2'));
});

test('fixed one-time rewards are explicit server constants',function(){
  assert.deepEqual(ONBOARDING_REWARD,{gold:500});
  assert.deepEqual(SOCIAL_VISIT_REWARDS.sp_instagram,{gems:5});
  assert.deepEqual(SOCIAL_VISIT_REWARDS.sp_tiktok,{gems:5});
  assert.deepEqual(SOCIAL_VISIT_REWARDS.sp_youtube,{gems:5});
  assert.equal(SOCIAL_VISIT_REWARDS.unknown,undefined);
});

test('deck validation accepts six unique unlocked cards',function(){
  const profile=starterProfile('uid-deck','deck_user');
  assert.deepEqual(validateDeck(profile.deck,profile),profile.deck);
});

test('deck validation rejects duplicates and locked cards',function(){
  const profile=starterProfile('uid-deck-bad','deck_bad');
  assert.throws(function(){validateDeck(['barbarian','barbarian','poison_q','angry_n','glue','freeze'],profile);},/duplicate or locked/i);
  assert.throws(function(){validateDeck(['barbarian','archer','poison_q','angry_n','glue','freeze'],profile);},/duplicate or locked/i);
});

test('deck validation accepts only the server-owned card-family level',function(){
  const profile=starterProfile('uid-deck-level','deck_level');
  profile.unlockedCards.trap1=true;profile.cardLevel.trap=2;
  assert.deepEqual(validateDeck(['trap2','barbarian','card_block','poison_q','angry_n','glue'],profile),['trap2','barbarian','card_block','poison_q','angry_n','glue']);
  assert.throws(function(){validateDeck(['trap3','barbarian','card_block','poison_q','angry_n','glue'],profile);},/duplicate or locked/i);
});

test('deck validation canonicalizes family ownership keys without allowing a downgrade',function(){
  const profile=starterProfile('uid-deck-family','deck_family');
  profile.unlockedCards.trap1=true;profile.cardLevel.trap=2;
  assert.deepEqual(
    validateDeck(['trap','barbarian','card_block','poison_q','angry_n','glue'],profile),
    ['trap2','barbarian','card_block','poison_q','angry_n','glue']
  );
  assert.deepEqual(
    validateDeck(['trap1','barbarian','card_block','poison_q','angry_n','glue'],profile),
    ['trap2','barbarian','card_block','poison_q','angry_n','glue']
  );
});

test('malformed profile decks are repaired only from owned cards',function(){
  const profile=starterProfile('uid-deck-repair','deck_repair');
  profile.deck=['barbarian','barbarian','locked','freeze'];
  assert.deepEqual(canonicalDeckForProfile(profile),['barbarian','freeze','card_block','poison_q','angry_n','glue']);
  profile.unlockedCards.glue=false;
  assert.deepEqual(canonicalDeckForProfile(profile),[]);
});

test('legacy owned family decks can be repaired without granting starter cards',function(){
  const profile=starterProfile('uid-deck-legacy','deck_legacy');
  profile.unlockedCards={trap1:true,resist1:true,radar1:true,shield1:true,freeze:true,barbarian:true};
  profile.cardLevel={trap:1,resist:1,radar:1,shield:1,deploy:1};
  profile.deck=['trap1','trap1','broken','freeze'];
  assert.deepEqual(canonicalDeckForProfile(profile),['trap1','freeze','resist1','radar1','shield1','barbarian']);
});

test('piece-set aliases are explicit and inventory sanitization drops forged ownership',function(){
  assert.equal(canonicalPieceSetId('luno'),'std');
  assert.equal(knownSelection('piece_set','luno'),true);
  const profile=starterProfile('uid-inventory-sanitize','inventory_sanitize');
  profile.inventory.ownedSets=['std','ottoman','forged'];
  profile.inventory.activePieceSet='forged';
  profile.inventory.ownedCostumes=['k_forced','q_classic'];
  profile.inventory.activeCostumes={K:'k_forced',Q:'q_classic'};
  const inventory=serverInventory(profile);
  assert.deepEqual(inventory.ownedSets,['std','ottoman']);
  assert.equal(inventory.activePieceSet,'std');
  assert.deepEqual(inventory.activeCostumes,{Q:'q_classic'});
});

test('billing catalog contains only explicit package products',function(){
  assert.equal(Object.keys(PRODUCT_CATALOG).length,10);
  assert.deepEqual(PRODUCT_CATALOG.luno_gold_1000.grant,{gold:1000});
  assert.equal(PRODUCT_CATALOG.luno_premium_year.type,'subs');
  assert.equal(PRODUCT_CATALOG.unknown,undefined);
});

test('billing grants are token-idempotent and subscriptions use Google expiry',function(){
  const profile=starterProfile('uid-billing','billing_user');
  const purchase={kind:'inapp',productId:'luno_gold_1000',data:{}};
  const first=applyVerifiedPurchaseGrant(profile,'uid-billing',PRODUCT_CATALOG.luno_gold_1000,purchase,'token-hash-1');
  const second=applyVerifiedPurchaseGrant(profile,'uid-billing',PRODUCT_CATALOG.luno_gold_1000,purchase,'token-hash-1');
  assert.equal(first.granted,true);
  assert.equal(second.idempotent,true);
  assert.equal(profile.gold,2250);
  const expiry=Date.now()+14*86400000;
  const subscription={kind:'subs',productId:'luno_premium_month',data:{subscriptionState:'SUBSCRIPTION_STATE_ACTIVE',lineItems:[{expiryTime:new Date(expiry).toISOString()}]}};
  assert.equal(subscriptionExpiry(subscription),expiry);
  const premium=applyVerifiedPurchaseGrant(profile,'uid-billing',PRODUCT_CATALOG.luno_premium_month,subscription,'token-hash-2');
  assert.equal(premium.granted,true);
  assert.equal(profile.premiumUntil,expiry);
});

test('subscription lifecycle distinguishes grace, cancellation, hold, revoke and expiry',function(){
  const at=Date.parse('2026-08-11T12:00:00Z'),future=new Date(at+24*60*60*1000).toISOString(),past=new Date(at-1000).toISOString();
  function state(subscriptionState,expiry){return subscriptionLifecycle({data:{subscriptionState,lineItems:[{expiryTime:expiry}]}},at);}
  assert.equal(state('SUBSCRIPTION_STATE_ACTIVE',future).active,true);
  assert.equal(state('SUBSCRIPTION_STATE_IN_GRACE_PERIOD',future).grace,true);
  assert.equal(state('SUBSCRIPTION_STATE_CANCELED',future).active,true);
  assert.equal(state('SUBSCRIPTION_STATE_CANCELED',past).active,false);
  assert.equal(state('SUBSCRIPTION_STATE_ON_HOLD',future).onHold,true);
  assert.equal(state('SUBSCRIPTION_STATE_ON_HOLD',future).active,false);
  assert.equal(state('SUBSCRIPTION_STATE_REVOKED',future).revoked,true);
  assert.equal(state('SUBSCRIPTION_STATE_REVOKED',future).active,false);
  assert.equal(state('SUBSCRIPTION_STATE_EXPIRED',past).expired,true);
});

test('voided consumable reversal is idempotent and later purchases repay billing debt first',function(){
  const profile=starterProfile('uid-refund','refund_user'),at=Date.parse('2026-08-11T12:00:00Z');
  const claim={uid:'uid-refund',productId:'luno_bundle_starter',grantGold:2500,grantGems:100};
  profile.serverEconomy.purchaseTokens={'void-token':{productId:claim.productId,kind:'inapp',grantGold:2500,grantGems:100,active:true,entitlementStatus:'granted'}};
  const first=applyVoidedPurchaseRevocation(profile,claim,'void-token',at);
  assert.equal(first.revoked,true);
  assert.equal(profile.gold,0);
  assert.equal(profile.gems,0);
  assert.deepEqual(profile.serverEconomy.billingDebt,{gold:1250,gems:50});
  assert.equal(profile.serverEconomy.billingReviewRequired,true);
  const snapshot=JSON.stringify(profile);
  assert.equal(applyVoidedPurchaseRevocation(profile,claim,'void-token',at+1).idempotent,true);
  assert.equal(JSON.stringify(profile),snapshot);
  const grant=applyVerifiedPurchaseGrant(profile,'uid-refund',{grant:{gold:2500,gems:100}},{kind:'inapp',productId:'luno_bundle_starter',data:{}},'replacement-token');
  assert.equal(grant.granted,true);
  assert.equal(profile.gold,1250);
  assert.equal(profile.gems,50);
  assert.equal(profile.serverEconomy.billingReviewRequired,false);
});

test('RTDN decoder accepts Pub/Sub base64 and rejects ambiguous notifications',function(){
  const payload={version:'1.0',packageName:'com.luno.chess',eventTimeMillis:'1',subscriptionNotification:{version:'1.0',notificationType:2,purchaseToken:'token'}};
  const event={data:{message:{data:Buffer.from(JSON.stringify(payload)).toString('base64')}}};
  assert.deepEqual(decodeRtdnNotification(event),payload);
  assert.equal(rtdnKind(payload),'subscriptionNotification');
  assert.throws(function(){rtdnKind(Object.assign({},payload,{testNotification:{version:'1.0'}}));},/exactly one notification/i);
});

test('purchase and account identifiers are stored as deterministic hashes',function(){
  assert.equal(hash('same-token'),hash('same-token'));
  assert.notEqual(hash('same-token'),hash('other-token'));
  assert.match(hash('same-token'),/^[a-f0-9]{64}$/);
});

test('social identifiers reject malformed database paths',function(){
  assert.equal(validUid('Abcdef_123-xyz'),true);
  assert.equal(validUid('short'),false);
  assert.equal(validUid('user/other'),false);
  assert.equal(validUid('user.other'),false);
});

test('conversation identifiers are deterministic for either participant order',function(){
  assert.equal(conversationId('z-user-123','a_user_456'),'a_user_456_z-user-123');
  assert.equal(conversationId('a_user_456','z-user-123'),'a_user_456_z-user-123');
});

test('leaderboard output stays bounded when the profile database grows',function(){
  function profiles(count){
    const result={};
    for(let index=0;index<count;index+=1){
      const uid='uid_'+String(index).padStart(5,'0');
      result[uid]={name:'Player '+String(index).padStart(5,'0'),username:'player_'+String(index).padStart(5,'0'),trophies:index%100,collectionScore:index%250,seasonScore:index%75,wins:index%40};
    }
    return result;
  }
  assert.equal(normalizeLeaderboardLimit(0),LEADERBOARD_MAX_LIMIT);
  assert.equal(normalizeLeaderboardLimit(10000),LEADERBOARD_MAX_LIMIT);
  const ten=leaderboardRows(profiles(10),'trophies',100,'uid_00000');
  const hundred=leaderboardRows(profiles(100),'trophies',100,'uid_00000');
  const tenThousand=leaderboardRows(profiles(10000),'trophies',100,'uid_00000');
  assert.equal(ten.length,10);
  assert.equal(hundred.length,100);
  assert.equal(tenThousand.length,100);
  assert.equal(tenThousand.every(function(row,index){return index===0||tenThousand[index-1].trophies>=row.trophies;}),true);
  assert.ok(JSON.stringify(tenThousand).length<=JSON.stringify(hundred).length*1.2,'leaderboard response grows with the full profile database');
});

test('leaderboard tie ordering is stable and invalid public scores are zeroed',function(){
  const profiles={
    uid_z:{username:'zulu',trophies:50},
    uid_a:{username:'alpha',trophies:50},
    uid_bad:{username:'broken',trophies:-10,collectionScore:'not-a-number'}
  };
  const rows=leaderboardRows(profiles,'trophies',10,'uid_a');
  assert.deepEqual(rows.map(function(row){return row.uid;}),['uid_a','uid_z','uid_bad']);
  assert.equal(rows[2].trophies,0);
});

test('request bodies reject unknown fields and prototype pollution shapes',function(){
  assert.doesNotThrow(function(){assertBodyKeys({missionId:'d1'},['missionId']);});
  assert.throws(function(){assertBodyKeys({missionId:'d1',amount:999999},['missionId']);},/unexpected field/i);
  assert.throws(function(){assertBodyKeys(JSON.parse('{"__proto__":{"polluted":true}}'),[]);},/unexpected field/i);
  const inherited=Object.create({polluted:true});
  inherited.missionId='d1';
  assert.throws(function(){assertBodyKeys(inherited,['missionId']);},/unexpected field/i);
});

test('server periods are based on one UTC instant instead of device timezone',function(){
  const instantA=Date.parse('2026-08-09T21:30:00+03:00');
  const instantB=Date.parse('2026-08-09T18:30:00Z');
  assert.equal(instantA,instantB);
  assert.deepEqual(periodSnapshot(instantA),periodSnapshot(instantB));
  assert.equal(utcDayKey(instantA),'2026-08-09');
});

test('daily reward is server-priced, streaked and written to a complete ledger',function(){
  const profile=starterProfile('uid-daily','daily_user');
  const at=Date.parse('2026-08-09T12:00:00Z');
  const result=applyDailyRewardClaim(profile,'uid-daily',at);
  assert.equal(result.granted,true);
  assert.deepEqual(result.reward,{gold:200});
  assert.equal(profile.gold,1450);
  assert.equal(profile.inventory.dailyStreak,1);
  assert.equal(profile.serverSchemaVersion,SERVER_SCHEMA_VERSION);
  const ledger=profile.serverEconomy.ledger[result.transactionIds[0]];
  assert.deepEqual(
    Object.keys(ledger).sort(),
    ['amount','createdAt','idempotencyKey','newBalance','previousBalance','rewardType','serverVersion','sourceId','sourceType','transactionId','uid'].sort()
  );
  assert.equal(ledger.previousBalance,1250);
  assert.equal(ledger.newBalance,1450);
  assert.equal(ledger.amount,200);
  assert.equal(ledger.rewardType,'gold');
  assert.deepEqual(result.daily.nextReward,{gold:300,gems:0});
  assert.deepEqual(economySnapshot(profile,at).daily.nextReward,{gold:300,gems:0});
});

test('one daily reward is granted across one hundred retries',function(){
  const profile=starterProfile('uid-retry','retry_user');
  const at=Date.parse('2026-08-09T12:00:00Z');
  const results=[];
  for(let index=0;index<100;index++)results.push(applyDailyRewardClaim(profile,'uid-retry',at));
  assert.equal(results.filter(function(result){return result.granted;}).length,1);
  assert.equal(profile.gold,1450);
  assert.equal(Object.keys(profile.serverEconomy.claims).length,1);
  assert.equal(Object.keys(profile.serverEconomy.ledger).length,1);
});

test('daily streak continues on the next UTC day and resets after a missed day',function(){
  const profile=starterProfile('uid-streak','streak_user');
  const dayOne=Date.parse('2026-08-09T23:59:59Z');
  const dayTwo=Date.parse('2026-08-10T00:00:01Z');
  const dayFour=Date.parse('2026-08-12T00:00:01Z');
  assert.deepEqual(applyDailyRewardClaim(profile,'uid-streak',dayOne).reward,{gold:200});
  assert.deepEqual(applyDailyRewardClaim(profile,'uid-streak',dayTwo).reward,{gold:300});
  assert.deepEqual(applyDailyRewardClaim(profile,'uid-streak',dayFour).reward,{gold:200});
  assert.equal(profile.inventory.dailyStreak,1);
  assert.equal(profile.gold,1950);
});

test('generic reward service rejects client-shaped invalid amounts and deduplicates its source',function(){
  const profile=starterProfile('uid-reward','reward_user');
  const at=Date.parse('2026-08-09T12:00:00Z');
  assert.throws(function(){
    applyRewardClaim(profile,{uid:'uid-reward',sourceType:'mission',sourceId:'fake',reward:{gold:999999999},at});
  },/invalid reward amount/i);
  const first=applyRewardClaim(profile,{uid:'uid-reward',sourceType:'mission',sourceId:'daily:d1:2026-08-09',reward:{gold:150},at});
  const replay=applyRewardClaim(profile,{uid:'uid-reward',sourceType:'mission',sourceId:'daily:d1:2026-08-09',reward:{gold:150},at:at+1000});
  assert.equal(first.granted,true);
  assert.equal(replay.granted,false);
  assert.equal(replay.idempotent,true);
  assert.equal(profile.gold,1400);
});

test('server mission rotation is deterministic and excludes locked card missions',function(){
  const profile=starterProfile('uid-missions','mission_user');
  const at=Date.parse('2026-08-09T12:00:00Z');
  const first=selectedMissionIds(profile,'daily',at);
  const second=selectedMissionIds(profile,'daily',at);
  assert.deepEqual(first,second);
  assert.equal(first.length,5);
  assert.equal(first[0],'d1');
  assert.equal(first.includes('dc_arch'),false);
  assert.equal(first.every(function(id){return !!MISSION_CATALOG.daily[id];}),true);
  const schedule=rewardSchedule(profile,at);
  assert.equal(schedule.missions.daily.length,5);
  assert.equal(schedule.missions.weekly[0].id,'w1');
  assert.equal(first.every(function(id){return typeof (schedule.missions.daily.find(function(row){return row.id===id})||{}).title==='string';}),true);
});

test('mission and achievement catalogs expose useful copy and new progress tracks',function(){
  const profile=starterProfile('uid-catalog','catalog_user');
  const at=Date.parse('2026-08-09T12:00:00Z');
  profile.stats={wins:0,losses:0,draws:10,captures:100,checks:50,promotions:5};
  profile.serverActivity={loginStreak:7,lastLoginDay:utcDayOrdinal(at)};
  const achievements=achievementSchedule(profile,at,{});
  const byId=function(id){return achievements.find(function(row){return row.id===id;});};
  assert.equal(byId('draw_10').canClaim,true);
  assert.equal(byId('captures_100').canClaim,true);
  assert.equal(byId('checks_50').canClaim,true);
  assert.equal(byId('promotions_5').canClaim,true);
  assert.equal(byId('login_7').progress,7);
  assert.equal(typeof byId('draw_10').title,'string');
  const passProfile=starterProfile('uid-pass-mission','pass_mission_user');
  const passGrant=grantMissionPassXp(passProfile,'daily',at);
  assert.equal(passGrant.passXp,25);
  assert.equal(passProfile.passState.xp,25);
});

test('mission rotation stays fixed for the whole period after the first settlement',function(){
  const profile=starterProfile('uid-fixed-missions','fixed_mission_user');
  const at=Date.parse('2026-08-01T12:00:00Z');
  const first=selectedMissionIds(profile,'daily',at);
  applyRankedSettlement(profile,{uid:profile.uid,matchId:'fixed-mission-0001',outcome:'win',opponentTrophies:0,metrics:{},at});
  profile.unlockedCards.trap1=true;
  assert.deepEqual(selectedMissionIds(profile,'daily',at),first);
  assert.deepEqual(profile.serverProgress.missions.daily[periodSnapshot(at).dayKey].selected,first);
});

test('mission period storage stays bounded while periods renew from server time',function(){
  const profile=starterProfile('uid-periods','period_user');
  const start=Date.parse('2026-08-01T12:00:00Z');
  for(let index=0;index<20;index++){
    applyRankedSettlement(profile,{uid:profile.uid,matchId:'period-'+index,outcome:'draw',opponentTrophies:0,metrics:{},at:start+index*24*60*60*1000});
  }
  assert.equal(Object.keys(profile.serverProgress.missions.daily).length<=14,true);
  assert.equal(Object.keys(profile.serverProgress.missions.weekly).length<=8,true);
  const current=periodSnapshot(start+19*24*60*60*1000);
  assert.equal(Object.prototype.hasOwnProperty.call(profile.serverProgress.missions.daily,current.dayKey),true);
});

test('season path exposes deterministic active, current, claimable and claimed states',function(){
  const profile=starterProfile('uid-season-path','season_path_user');
  const at=Date.parse('2026-08-09T12:00:00Z');
  profile.serverSeason={number:4,seasonId:'s4',peakTrophies:0,startedAt:seasonBounds(4).startAt,claimed:{}};
  const initial=seasonState(profile,at);
  assert.equal(initial.status,'active');
  assert.equal(initial.seasonNumber,4);
  assert.equal(initial.path.length,SEASON_PATH_REWARDS.length);
  assert.equal(initial.path[0].state,'claimable');
  assert.equal(initial.path[0].canClaim,true);
  assert.equal(initial.path[1].state,'current');
  assert.equal(initial.path[1].canClaim,false);
  assert.equal(initial.claimableCount,1);
  assert.equal(initial.progress,0);

  profile.serverSeason.peakTrophies=1000;
  profile.serverSeason.claimed={path_1:at};
  const reached=seasonState(profile,at);
  assert.equal(reached.path[0].state,'claimed');
  assert.equal(reached.path[1].state,'claimable');
  assert.equal(reached.path[4].state,'claimable');
  assert.equal(reached.path[5].state,'current');
  assert.equal(reached.currentTierId,'path_6');
  assert.equal(reached.nextTierId,'path_6');
  assert.equal(reached.nextTrophies,1500);
  assert.equal(reached.claimableCount,4);

  const ledgerKey=sourceClaimKey(profile.uid,'season_path_reward','s4:path_2');
  profile.serverEconomy.claims[ledgerKey]={claimedAt:at};
  assert.equal(seasonState(profile,at).path[1].state,'claimed');
  assert.equal(seasonState(profile,at).claimableCount,3);
});

test('season path freezes the finished season and rejects future-season records',function(){
  const profile=starterProfile('uid-season-boundary','season_boundary_user');
  const seasonFour=seasonBounds(4);
  profile.serverSeason={number:4,seasonId:'s4',peakTrophies:0,startedAt:seasonFour.startAt,claimed:{}};
  profile.serverSeason.peakTrophies=2500;
  const ended=seasonState(profile,seasonFour.endAt+1);
  assert.equal(ended.status,'ended');
  assert.equal(ended.seasonNumber,4);
  assert.equal(ended.currentSeasonNumber,5);
  assert.equal(ended.score,2500);
  assert.equal(ended.canClaimEndReward,true);
  assert.equal(ended.path.every(function(row){return row.canClaim===false;}),true);

  profile.serverSeason.number=99;
  const future=seasonState(profile,Date.parse('2026-08-09T12:00:00Z'));
  assert.equal(future.status,'syncing');
  assert.equal(future.score,0);
  assert.equal(future.claimableCount,0);
  assert.equal(future.path.some(function(row){return row.canClaim;}),false);
});

test('legacy season records are migrated without opening a future-season claim path',function(){
  const at=Date.parse('2026-08-09T12:00:00Z');
  const legacy=starterProfile('uid-season-legacy','season_legacy_user');
  delete legacy.serverSeason;
  legacy.trophies=420;
  assert.equal(normalizeSeasonRecord(legacy,at),true);
  assert.equal(legacy.serverSeason.number,4);
  assert.equal(legacy.serverSeason.seasonId,'s4');
  assert.equal(legacy.serverSeason.peakTrophies,420);
  assert.equal(legacy.serverSeason.startedAt,seasonBounds(4).startAt);

  const future=starterProfile('uid-season-future','season_future_user');
  future.serverSeason={number:99,seasonId:'s99',peakTrophies:99999,startedAt:at,claimed:{path_10:at}};
  assert.equal(normalizeSeasonRecord(future,at),true);
  assert.equal(future.serverSeason.number,4);
  assert.equal(future.serverSeason.peakTrophies,0);
  assert.deepEqual(future.serverSeason.claimed,{});
});

test('ranked settlement cannot inflate a finished season after rollover',function(){
  const profile=starterProfile('uid-season-frozen','season_frozen_user');
  const seasonFour=seasonBounds(4),at=seasonFour.endAt+60*1000;
  profile.serverSeason={number:4,seasonId:'s4',peakTrophies:2500,startedAt:seasonFour.startAt,claimed:{}};
  profile.trophies=1500;
  applyRankedSettlement(profile,{uid:profile.uid,matchId:'season-frozen-match',outcome:'win',opponentTrophies:1500,metrics:{},at});
  assert.equal(profile.serverSeason.number,4);
  assert.equal(profile.serverSeason.peakTrophies,2500);
});

test('achievement eligibility reads authoritative profile fields',function(){
  const profile=starterProfile('uid-achievement','achievement_user');
  const at=Date.parse('2026-08-09T12:00:00Z');
  profile.stats.wins=1;
  assert.equal(achievementValue(profile,'wins',at,{}),1);
  assert.equal(achievementValue(profile,'arenaIdx',at,{}),1);
  assert.equal(achievementValue(profile,'friendsCount',at,{friendsCount:5}),5);
  assert.deepEqual(ACHIEVEMENT_CATALOG.first_win.reward,{gold:100});
});

test('Pass state uses the server season and discards a stale client season',function(){
  const profile=starterProfile('uid-pass','pass_user');
  profile.passState={seasonKey:'client-fake-s999',season:999,level:30,xp:249,premium:true,claimed:{free:{1:true},premium:{1:true}}};
  const synced=syncServerPass(profile,Date.parse('2026-08-09T12:00:00Z'));
  assert.equal(synced.pass.seasonKey,'ranked-s4-v2');
  assert.equal(synced.pass.level,0);
  assert.equal(synced.pass.xp,0);
  assert.equal(synced.pass.premium,false);
});

test('Pass content rewards become usable server inventory instead of a display-only unlock',function(){
  const profile=starterProfile('uid-pass-content','pass_content_user');
  const emoji=grantPassContent(profile,{kind:'emoji',id:'smile'});
  const set=grantPassContent(profile,{kind:'piece_set',id:'ottoman'});
  const chest=grantPassContent(profile,{kind:'chest',id:'rare'});
  grantPassContent(profile,{kind:'chest',id:'rare'});
  const inventory=serverInventory(profile);
  assert.equal(emoji.kind,'emoji');
  assert.equal(set.kind,'piece_set');
  assert.equal(chest.kind,'chest');
  assert.equal(inventory.ownedEmojis.includes('smile'),true);
  assert.equal(inventory.ownedSets.includes('ottoman'),true);
  assert.deepEqual(inventory.pendingChests,['rare','rare']);
  assert.equal(emoji.duplicate,true);
  assert.deepEqual(emoji.compensation,{gold:250});
});

test('Pass catalog is complete, priced consistently and has no duplicate cosmetic content',function(){
  ['free','premium'].forEach(function(track){
    const rewards=PASS_CURRENCY_REWARDS[track];
    assert.equal(Object.keys(rewards).length,30,track+' must have 30 currency tiers');
    for(let level=1;level<=30;level++){
      const reward=rewards[level];
      assert.ok(reward,track+' level '+level+' is missing');
      assert.ok(Object.values(reward).every(function(amount){return Number.isSafeInteger(amount)&&amount>0;}),track+' level '+level+' has an invalid amount');
    }
  });
  const total=function(track){return Object.values(PASS_CURRENCY_REWARDS[track]).reduce(function(sum,reward){return {gold:sum.gold+(reward.gold||0),gems:sum.gems+(reward.gems||0)};},{gold:0,gems:0});};
  assert.deepEqual(total('free'),{gold:12300,gems:120});
  assert.deepEqual(total('premium'),{gold:13950,gems:540});
  const cosmeticKeys=new Set();
  Object.keys(PASS_CONTENT_REWARDS).forEach(function(track){
    Object.keys(PASS_CONTENT_REWARDS[track]).forEach(function(level){
      const content=PASS_CONTENT_REWARDS[track][level];
      assert.ok(['emoji','piece_set','chest'].includes(content.kind));
      assert.ok(content.kind==='chest'?CHEST_CATALOG[content.id]:content.kind==='emoji'?knownSelection('emoji',content.id):knownSelection('piece_set',content.id));
      if(content.kind!=='chest'){
        const key=content.kind+':'+content.id;
        assert.equal(cosmeticKeys.has(key),false,'duplicate cosmetic '+key);
        cosmeticKeys.add(key);
      }
    });
  });
  assert.equal(PASS_CONTENT_REWARDS.free[16].id,'legendary');
});

test('legacy profiles normalize Pass chest inventory before access',function(){
  const profile=starterProfile('uid-pass-legacy','pass_legacy');
  delete profile.inventory.pendingChests;
  const inventory=serverInventory(profile);
  assert.deepEqual(inventory.pendingChests,[]);
});

test('pending Pass chests count as protected guest progress',function(){
  const profile=starterProfile('uid-pass-pending','pass_pending');
  profile.inventory.pendingChests=['rare'];
  assert.equal(profileHasProtectedProgress(profile),true);
});

test('soft-currency catalog is explicit and excludes free or shard-only inventory',function(){
  assert.equal(Object.keys(SOFT_ITEM_CATALOG).length,68);
  assert.deepEqual(SOFT_ITEM_CATALOG['piece_set:ottoman'].grant,{kind:'piece_set',id:'ottoman'});
  assert.equal(SOFT_ITEM_CATALOG['skin:classic'],undefined);
  assert.equal(SOFT_ITEM_CATALOG['frame:galaxy'],undefined);
  assert.equal(SOFT_ITEM_CATALOG['bio_frame:premium'],undefined);
  assert.equal(SOFT_ITEM_CATALOG['pass:premium'].price,450);
});

test('one-time soft purchases debit and grant exactly once across one hundred retries',function(){
  const profile=starterProfile('uid-soft','soft_user'),definition=SOFT_ITEM_CATALOG['frame:bronze'];
  const at=Date.parse('2026-08-09T12:00:00Z'),results=[];
  for(let index=0;index<100;index++){
    results.push(applySoftPurchase(profile,{
      uid:profile.uid,sourceType:'soft_purchase',sourceId:'frame:bronze',itemType:'frame',itemId:'frame:bronze',
      currency:definition.currency,price:definition.price,at:at+index,
      isOwned:function(current){return softItemOwned(current,definition);},
      grant:function(current){return grantSoftItem(current,definition,at);}
    }));
  }
  assert.equal(results.filter(function(result){return result.purchased;}).length,1);
  assert.equal(results.filter(function(result){return result.idempotent;}).length,99);
  assert.equal(profile.gold,750);
  assert.equal(profile.frame,'bronze');
  assert.equal(profile.inventory.ownedFrames.filter(function(id){return id==='bronze';}).length,1);
  assert.equal(Object.keys(profile.serverEconomy.purchases).length,1);
  const debit=Object.values(profile.serverEconomy.ledger).find(function(entry){return entry.sourceType==='soft_purchase';});
  assert.equal(debit.amount,-500);
  assert.equal(debit.previousBalance,1250);
  assert.equal(debit.newBalance,750);
});

test('insufficient soft-currency balance leaves the complete profile unchanged',function(){
  const profile=starterProfile('uid-poor','poor_user');profile.gems=0;
  const before=JSON.stringify(profile),definition=SOFT_ITEM_CATALOG['skin:celestial'];
  const result=applySoftPurchase(profile,{
    uid:profile.uid,sourceId:'skin:celestial',itemType:'skin',itemId:'skin:celestial',currency:definition.currency,
    price:definition.price,at:Date.parse('2026-08-09T12:00:00Z'),
    isOwned:function(current){return softItemOwned(current,definition);},
    grant:function(current){return grantSoftItem(current,definition,Date.parse('2026-08-09T12:00:00Z'));}
  });
  assert.equal(result.error,'insufficient-balance');
  assert.equal(JSON.stringify(profile),before);
});

test('card upgrade and chest catalogs keep prices and arena gates server-side',function(){
  assert.deepEqual(CARD_UPGRADE_CATALOG.trap[2],{price:2500,minArenaIdx:2});
  assert.deepEqual(CARD_UPGRADE_CATALOG.deploy[3],{price:5000,minArenaIdx:7});
  assert.equal(CHEST_CATALOG.common.price,500);
  assert.equal(CHEST_CATALOG.royal.currency,'gems');
  assert.equal(CHEST_CATALOG.royal.price,380);
});

test('chest rolls are deterministic per server seed and inventory grants are bounded',function(){
  const profile=starterProfile('uid-chest','chest_user');profile.arenaIdx=7;
  const first=rollChest(profile,'royal','server-only-seed');
  const second=rollChest(profile,'royal','server-only-seed');
  assert.deepEqual(first,second);
  assert.equal(first[0].type,'gold');
  assert.equal(first[0].amount>=1000&&first[0].amount<=2500,true);
  const applied=applyChestInventoryRewards(profile,first);
  assert.equal(profile.stats.chestsOpened,1);
  assert.equal(applied.every(function(reward){return Number.isSafeInteger(reward.amount)&&reward.amount>0;}),true);
});
