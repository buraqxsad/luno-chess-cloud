'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {verifiedEarlyProgress,syncEarlyProgress,reconcileCompetitiveProgression,reconcileEarlyCardOwnership,progressionSummary,UNLOCK_PATH}=require('../lib/battle-v1-progression');
const {applyDailyRewardClaim,applyRewardClaim,sourceClaimKey,seasonBounds}=require('../lib/economy');
const {membershipState,normalizeProductEntitlements,LEGACY_PASS_COSTUMES}=require('../lib/membership');
const {syncPassState}=require('../lib/pass');
const {chestAvailability,rollChest}=require('../lib/chests');
const {SKIN_DROP_CATALOG,EMOJI_DROP_CATALOG,FRAME_SHARD_CATALOG,BIO_FRAME_SHARD_CATALOG}=require('../lib/catalogs');
const {STARTER,CARDS}=require('../rules-v1/dist/src/model');
const {fixture}=require('./helpers/battle-v1-fixture');
const {memoryDatabase}=require('./helpers/memory-database');
const api=require('../index')._test;
const uid='v215_economy_alice',at=Date.UTC(2026,9,9,12),DAY=86400000;
const welcome=(profile,time=at)=>applyRewardClaim(profile,{uid,sourceType:'onboarding_reward',sourceId:'v1',reward:{gold:500},at:time});
const profile=()=>api.starterProfile(uid,'v215_alice');
const context=(requestId='welcome-1',body={})=>({uid,requestId,body});

test('24 canonical cards have 10 starter and 14 complete exact-condition entries',()=>{
  assert.equal(STARTER.length,10);assert.equal(UNLOCK_PATH.length,14);
  assert.deepEqual(new Set([...STARTER,...UNLOCK_PATH.map(t=>t.card)]),new Set(Object.keys(CARDS)));
  const summary=progressionSummary({entitlements:[...STARTER]});
  assert.equal(summary.version,2);assert.equal(summary.nextUnlock.card,'mine');
  assert.deepEqual(summary.early,{welcomeClaimed:false,distinctDailyClaims:0});
  for(const tier of summary.path){
    assert.deepEqual(tier.requirements.anyOf[0],{kind:'ranked_matches',current:0,target:tier.matches});
    assert.equal(tier.requirements.anyOf.length,['mine','break_seal','fog'].includes(tier.card)?2:1);
  }
});

test('welcome is unconditional account benefit, adds Mine once without claiming an AI win',()=>{
  const p=profile(),a={entitlements:[...STARTER]};
  const grant=welcome(p);assert.equal(grant.granted,true);
  const beforeGold=p.gold;
  assert.deepEqual(reconcileEarlyCardOwnership(p,uid,at).unlocked,['mine']);
  syncEarlyProgress(a,p,uid,at);const first=reconcileCompetitiveProgression(a);
  assert.deepEqual(first.unlocked,['mine']);assert.equal(first.meaningfulMatches,0);
  assert.equal(first.nextUnlock.card,'break_seal');
  for(let retry=0;retry<10;retry++){
    assert.equal(welcome(p).granted,false);
    assert.deepEqual(reconcileEarlyCardOwnership(p,uid,at).unlocked,[]);
    syncEarlyProgress(a,p,uid,at);assert.deepEqual(reconcileCompetitiveProgression(a).unlocked,[]);
  }
  assert.equal(p.gold,beforeGold);assert.equal(p.stats.wins,0);assert.equal(p.stats.losses,0);
});

test('two/three distinct committed UTC daily claims grant Break Seal/Fog without a population gate',()=>{
  const p=profile(),a={entitlements:[...STARTER]};
  welcome(p);
  for(let day=0;day<3;day++){
    const time=at+day*DAY;
    assert.equal(applyDailyRewardClaim(p,uid,time).granted,true);
    assert.equal(applyDailyRewardClaim(p,uid,time+1000).granted,false);
    assert.equal(reconcileEarlyCardOwnership(p,uid,time).early.distinctDailyClaims,day+1);
    syncEarlyProgress(a,p,uid,time);const result=reconcileCompetitiveProgression(a);
    assert.equal(result.meaningfulMatches,0);
    assert.equal(a.entitlements.includes('break_seal'),day>=1);
    assert.equal(a.entitlements.includes('fog'),day>=2);
  }
  assert.deepEqual(a.entitlements.slice(-3),['mine','break_seal','fog']);
  assert.equal(p.battleV1UnlockedCards.fog,true);
});

test('nonconsecutive days work, UTC rollover counts exactly once, future receipts do not count',()=>{
  const p=profile(),midnight=Date.UTC(2026,9,10);
  for(const time of [midnight-1,midnight,midnight+10*DAY])applyDailyRewardClaim(p,uid,time);
  assert.equal(verifiedEarlyProgress(p,uid,midnight).distinctDailyClaims,2);
  assert.equal(verifiedEarlyProgress(p,uid,midnight+10*DAY).distinctDailyClaims,3);
});

for(const kind of ['local_flags','other_owner','missing_ledger','wrong_uid','wrong_day','future','wrong_amount']){
  test(`early evidence rejects ${kind} rather than trusting client-like state`,()=>{
    const p=profile();welcome(p);applyDailyRewardClaim(p,uid,at);
    const key=sourceClaimKey(uid,'daily_reward','2026-10-09'),claim=p.serverEconomy.claims[key];
    if(kind==='local_flags'){
      p.serverEconomy.claims={};p.inventory.dailyStreak=999;p.onboardingRewardClaimedAt=at;p.wonOffline=true;
    }else if(kind==='other_owner')p.uid='bob';
    else if(kind==='missing_ledger')p.serverEconomy.ledger={};
    else if(kind==='wrong_uid')for(const entry of Object.values(p.serverEconomy.ledger))entry.uid='bob';
    else if(kind==='wrong_day')claim.sourceId='2026-10-10';
    else if(kind==='future')for(const entry of Object.values(p.serverEconomy.claims))entry.claimedAt=at+1;
    else if(kind==='wrong_amount')claim.reward.gold++;
    const early=verifiedEarlyProgress(p,uid,at);
    assert.equal(early.distinctDailyClaims,0);
    if(['local_flags','other_owner','missing_ledger','wrong_uid','future'].includes(kind))assert.equal(early.welcomeClaimed,false);
  });
}

test('getDeck reconciles committed receipts after an interrupted client response and preserves historic ownership',async()=>{
  const f=fixture();f.setTime(at);
  const p={...profile(),uid:'alice'};
  applyRewardClaim(p,{uid:'alice',sourceType:'onboarding_reward',sourceId:'v1',reward:{gold:500},at});
  p.battleV1UnlockedCards={board_seal:true};
  f.write('users/alice',p);
  const first=await f.api.getBattleV1Deck(f.context('alice',{client:f.client}));
  assert(first.entitlements.includes('mine'));assert(first.entitlements.includes('board_seal'));
  assert.equal(first.progression.early.welcomeClaimed,true);assert.equal(first.deck.length,10);
  const snapshot=structuredClone(f.read('battleV1Accounts/alice'));
  await f.api.getBattleV1Deck(f.context('alice',{client:f.client}));
  assert.deepEqual(f.read('battleV1Accounts/alice'),snapshot);
  assert.equal(f.read('users/alice').gold,p.gold);
  const bob=await f.api.getBattleV1Deck(f.context('bob',{client:f.client}));
  assert.equal(bob.entitlements.includes('mine'),false);
});

test('migration rejects a profile belonging to a different UID before writing account data',async()=>{
  const f=fixture();f.write('users/alice',{uid:'bob'});
  await assert.rejects(f.api.migrate('alice'),{code:'PROFILE_OWNER_MISMATCH',status:403});
  assert.equal(f.read('battleV1Accounts/alice'),undefined);
});

test('welcome endpoint grants currency once, repairs historic Mine without re-crediting gold, and cache loss is safe',async t=>{
  t.mock.method(Date,'now',()=>at);const p=profile();welcome(p,at-1000);
  const db=memoryDatabase(t,{users:{[uid]:p}}),gold=p.gold;
  const response=await api.claimOnboardingReward(context());
  assert.equal(response.granted,false);assert.equal(response.welcome.claimed,true);
  assert.equal(response.welcome.eligibility,'account_welcome');
  assert.equal(db.read('users/'+uid+'/battleV1UnlockedCards/mine'),true);
  assert.equal(db.read('users/'+uid+'/gold'),gold);
  db.write('serverRequests/'+uid,null);
  await api.claimOnboardingReward(context());assert.equal(db.read('users/'+uid+'/gold'),gold);
  assert.equal(Object.values(db.read('users/'+uid+'/serverEconomy/ledger')).filter(e=>e.sourceType==='onboarding_reward').length,1);
});

test('fresh welcome and server daily endpoints return actual currency outcomes and deterministic cards',async t=>{
  let clock=at;t.mock.method(Date,'now',()=>clock);
  const p=profile(),db=memoryDatabase(t,{users:{[uid]:p}});
  assert.equal((await api.claimOnboardingReward(context())).granted,true);
  assert.equal(db.read('users/'+uid+'/gold'),p.gold+500);
  for(let day=0;day<3;day++){
    clock=at+day*DAY;
    assert.equal((await api.claimDailyReward(context('daily-'+day))).granted,true);
    assert.equal((await api.claimDailyReward(context('daily-repeat-'+day))).granted,false);
  }
  assert.deepEqual(db.read('users/'+uid+'/battleV1UnlockedCards'),{mine:true,break_seal:true,fog:true});
});

for(const method of ['claimOnboardingReward','claimDailyReward']){
  test(`${method} rejects spoofed win/time/UID body and foreign stored profile`,async t=>{
    t.mock.method(Date,'now',()=>at);const p={...profile(),uid:'bob'},db=memoryDatabase(t,{users:{[uid]:p}});
    for(const body of [{wonOffline:true},{completed:true},{uid:'bob'},{at:at+DAY}])await assert.rejects(api[method](context('bad-body',body)),{status:400});
    await assert.rejects(api[method](context('wrong-owner')),{code:'profile-owner-mismatch',status:403});
    assert.deepEqual(db.read('users/'+uid),p);
  });
}

test('membership and Pass are independent in public state, achievements and cosmetic access',()=>{
  const p=profile();p.passState.premium=true;p.premiumUntil=at-1;
  assert.deepEqual(membershipState(p,at),{active:false,expiresAt:at-1});
  assert.equal(api.publicProfile(p,at).isPremium,false);assert.equal(api.achievementValue(p,'isPremium',at,{}),0);
  assert.equal(api.ownsSelection(p,'frame','premium',at),false);
  p.premiumUntil=at+DAY;
  assert.equal(api.publicProfile(p,at).isPremium,true);assert.equal(api.achievementValue(p,'isPremium',at,{}),1);
  assert.equal(api.ownsSelection(p,'frame','premium',at),true);
});

test('legacy current subscription Pass and shared cosmetics are grandfathered without balance/receipt changes',()=>{
  const p=profile();delete p.productEntitlementVersion;
  p.passState={seasonKey:'ranked-s6-v2',season:6,level:12,xp:45,premium:true,premiumSource:'subscription',rewardVersion:1,claimed:{free:{3:at},premium:{2:at}},unlocks:['emoji:laugh']};
  p.serverEconomy.purchases={historical:{price:450}};p.premiumUntil=at-1;
  const before=structuredClone(p);
  assert.equal(normalizeProductEntitlements(p),true);assert.equal(normalizeProductEntitlements(p),false);
  for(const key of ['gold','gems','serverEconomy'])assert.deepEqual(p[key],before[key]);
  assert.equal(p.passState.premiumSource,'grandfathered_subscription');
  for(const key of ['level','xp','claimed','unlocks','rewardVersion'])assert.deepEqual(p.passState[key],before.passState[key]);
  for(const id of LEGACY_PASS_COSTUMES)assert(p.inventory.ownedCostumes.includes(id));
  assert.equal(api.ownsSelection(p,'frame','premium',at),true);
  assert.equal(api.ownsSelection(p,'bio_frame','premium',at),true);
  assert.equal(membershipState(p,at).active,false);
  const next=syncPassState(p,seasonBounds(7).startAt).pass;
  assert.equal(next.premium,false);assert.equal(next.rewardVersion,2);
  assert(p.inventory.ownedFrames.includes('premium'));
});

test('verified new membership neither grants competitive cards nor a Pass and uses Google expiry',t=>{
  t.mock.method(Date,'now',()=>at);const p=profile(),pass=structuredClone(p.passState),gold=p.gold,gems=p.gems;
  const verified={kind:'subs',productId:'luno_premium_month',data:{subscriptionState:'SUBSCRIPTION_STATE_ACTIVE',lineItems:[{expiryTime:new Date(at+31*DAY).toISOString()}]}};
  assert.equal(api.applyVerifiedPurchaseGrant(p,uid,api.PRODUCT_CATALOG.luno_premium_month,verified,'subscription-token').granted,true);
  assert.deepEqual(p.passState,pass);assert.equal(p.gold,gold);assert.equal(p.gems,gems);
  assert.equal(p.premiumUntil,at+31*DAY);assert.equal(p.premiumSince,at);
  assert.equal(p.battleV1UnlockedCards,undefined);
  assert.equal(syncPassState(p,seasonBounds(7).startAt).pass.premium,false);
});

test('buying a season Pass never activates membership or membership achievements',async t=>{
  t.mock.method(Date,'now',()=>at);const p=profile();p.gems=1000;
  const db=memoryDatabase(t,{users:{[uid]:p}});
  const response=await api.purchaseSoftItem(context('pass-buy',{itemId:'pass:premium',seasonId:'s6'}));
  assert.equal(response.purchased,true);assert.equal(response.state.passState.premium,true);
  assert.deepEqual(response.state.membership,{active:false,expiresAt:0});
  assert.equal(db.read('users/'+uid+'/gems'),550);
  assert.equal(api.achievementValue(db.read('users/'+uid),'isPremium',at,{}),0);
  assert.equal(db.read('users/'+uid+'/battleV1UnlockedCards'),null);
});

test('subscription revocation changes membership only and retains already-owned current Pass',async t=>{
  t.mock.method(Date,'now',()=>at);const p=profile();p.premiumUntil=at+DAY;p.passState.premium=true;p.passState.premiumSource='soft_purchase';
  p.passState.claimed.premium={1:at};const before=structuredClone(p.passState);
  const db=memoryDatabase(t,{users:{[uid]:p}});
  assert.deepEqual(await api.recomputePremiumFromClaims(uid,at),{premiumUntil:0,active:false});
  assert.deepEqual(db.read('users/'+uid+'/passState'),before);
});

function exhaustedProfile(){
  const p=profile();p.gold=50000;p.gems=5000;
  Object.assign(p.inventory,{ownedSkins:Object.keys(SKIN_DROP_CATALOG),ownedEmojis:Object.keys(EMOJI_DROP_CATALOG),
    ownedFrames:Object.keys(FRAME_SHARD_CATALOG),ownedBioFrames:Object.keys(BIO_FRAME_SHARD_CATALOG)});
  return p;
}
for(const chestId of ['common','rare','legendary','royal']){
  test(`${chestId} cannot sell gold-only exhausted collection and never rolls competitive cards`,async t=>{
    t.mock.method(Date,'now',()=>at);const p=exhaustedProfile(),db=memoryDatabase(t,{users:{[uid]:p}});
    assert.equal(chestAvailability(p,chestId).canPurchase,false);
    assert.equal(chestAvailability(p,chestId).competitiveCards,false);
    await assert.rejects(api.openChest(context('complete-'+chestId,{chestId})),{code:'chest-collection-complete',status:409});
    assert.deepEqual(db.read('users/'+uid),p);
    // Earned chest delivery remains available, even for a complete collector.
    const earned=rollChest(p,chestId,'earned-complete');assert.equal(earned.length,1);assert.equal(earned[0].type,'gold');
  });
}

test('Royal always gives progress for the final remaining cosmetic instead of an expensive gold-only roll',()=>{
  for(const remaining of ['skin','frame','bio']){
    const p=exhaustedProfile();
    const type=remaining==='skin'?'skin':remaining==='frame'?'frame_shard':'bioframe_shard';
    if(remaining==='skin')p.inventory.ownedSkins=p.inventory.ownedSkins.filter(id=>id!=='celestial');
    if(remaining==='frame')p.inventory.ownedFrames=p.inventory.ownedFrames.filter(id=>id!=='rainbow');
    if(remaining==='bio')p.inventory.ownedBioFrames=p.inventory.ownedBioFrames.filter(id=>id!=='galaxy');
    assert.equal(chestAvailability(p,'royal').canPurchase,true);
    for(let seed=0;seed<500;seed++){
      const rewards=rollChest(p,'royal','last-cosmetic-'+seed);
      assert(rewards.some(r=>r.type===type));assert(!rewards.some(r=>r.type==='card'||r.type==='battle_card'));
    }
  }
});

test('paid chest receipt replays even if its successful opening completed the collection',async t=>{
  t.mock.method(Date,'now',()=>at);const p=exhaustedProfile();
  p.inventory.ownedSkins=p.inventory.ownedSkins.filter(id=>id!=='celestial');p.inventory.skinPieces={celestial:4};
  const db=memoryDatabase(t,{users:{[uid]:p}}),first=await api.openChest(context('last-chest',{chestId:'royal'}));
  assert.equal(first.opened,true);assert.equal(first.state.shopChests.royal.canPurchase,false);
  const after=structuredClone(db.read('users/'+uid));db.write('serverRequests/'+uid,null);
  const replay=await api.openChest(context('last-chest',{chestId:'royal'}));
  assert.equal(replay.opened,false);assert.equal(replay.idempotent,true);
  assert.equal(replay.transactionId,first.transactionId);assert.deepEqual(replay.rewards,first.rewards);
  assert.deepEqual(db.read('users/'+uid),after);
});

test('new launch grant is intentional 50 gems, while an existing 42-gem profile is unchanged by product migration',()=>{
  const fresh=profile();assert.equal(fresh.gems,50);assert.equal(fresh.starterGrantVersion,2);
  const existing=profile();existing.gems=42;existing.starterGrantVersion=1;delete existing.productEntitlementVersion;
  normalizeProductEntitlements(existing);syncPassState(existing,at);
  assert.equal(existing.gems,42);assert.equal(existing.starterGrantVersion,1);
});

test('player refresh persists legacy cosmetic migration and clears a stale Pass-derived public membership badge',async t=>{
  t.mock.method(Date,'now',()=>at);const p=profile();delete p.productEntitlementVersion;
  p.passState.premium=true;p.passState.premiumSource='subscription';p.premiumUntil=at-1;
  const db=memoryDatabase(t,{users:{[uid]:p},publicProfiles:{[uid]:{...api.publicProfile(p,at),isPremium:true}}});
  const response=await api.getPlayerState(context('membership-refresh'));
  assert.deepEqual(response.state.membership,{active:false,expiresAt:at-1});
  assert.equal(response.state.passState.premium,true);
  assert.equal(db.read('users/'+uid+'/productEntitlementVersion'),2);
  assert(db.read('users/'+uid+'/inventory/ownedFrames').includes('premium'));
  assert.equal(db.read('publicProfiles/'+uid+'/isPremium'),false);
});

test('membership expiry updates the public badge on state refresh without revoking a paid season Pass',async t=>{
  let clock=at;t.mock.method(Date,'now',()=>clock);const p=profile();p.premiumUntil=at+1000;p.passState.premium=true;p.passState.premiumSource='soft_purchase';
  const db=memoryDatabase(t,{users:{[uid]:p}});
  assert.equal((await api.getPlayerState(context('active-state'))).state.membership.active,true);
  assert.equal(db.read('publicProfiles/'+uid+'/isPremium'),true);
  clock=at+1001;
  assert.equal((await api.getPlayerState(context('expired-state'))).state.membership.active,false);
  assert.equal(db.read('publicProfiles/'+uid+'/isPremium'),false);
  assert.equal(db.read('users/'+uid+'/passState/premium'),true);
});
