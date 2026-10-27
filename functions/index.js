'use strict';

const crypto=require('node:crypto');
const {setGlobalOptions}=require('firebase-functions/v2');
const {onRequest}=require('firebase-functions/v2/https');
const {onMessagePublished}=require('firebase-functions/v2/pubsub');
const {onSchedule}=require('firebase-functions/v2/scheduler');
const {logger}=require('firebase-functions');
const {initializeApp}=require('firebase-admin/app');
const {getAppCheck}=require('firebase-admin/app-check');
const {getAuth}=require('firebase-admin/auth');
const {getDatabase,ServerValue}=require('firebase-admin/database');
const {
  SERVER_SCHEMA_VERSION,
  applyDailyRewardClaim,
  applyRewardClaim,
  applySoftPurchase,
  economySnapshot,
  normalizeSeasonRecord,
  periodSnapshot,
  sourceClaimKey,
  seasonBounds,
  utcDayKey,
  utcDayOrdinal,
  utcWeekKey
}=require('./lib/economy');
const {
  ACHIEVEMENT_CATALOG,CARD_UNLOCK_CATALOG,CARD_UPGRADE_CATALOG,CHEST_CATALOG,COSTUME_PRICES,MISSION_CATALOG,
  ACHIEVEMENT_COPY,MISSION_COPY,PASS_CONTENT_REWARDS,PASS_CURRENCY_REWARDS,SEASON_PATH_REWARDS,SEASON_REWARDS,SOFT_ITEM_CATALOG
}=require('./lib/catalogs');
const {applyChestInventoryRewards,chestAvailability,rollChest,stringList,stringMultisetList}=require('./lib/chests');
const {deterministicMissionIds,missionOwned}=require('./lib/missions');
const {syncPassState,passCurrencyReward}=require('./lib/pass');
const {ENTITLEMENT_VERSION,membershipState,normalizeProductEntitlements}=require('./lib/membership');
const {reconcileEarlyCardOwnership}=require('./lib/battle-v1-progression');
const {settlePlayerPresence}=require('./lib/settlement-presence');
const {playerStateRevision,finalizePlayerStateRevision}=require('./lib/player-state-revision');
const {retainPurchaseClaim,retainModerationReport,purchaseClaimRetired}=require('./lib/retained-data');
const {createBattleV1Api}=require('./lib/battle-v1');
const {installBattleV1Rollout}=require('./lib/battle-v1-rollout');
const {installBattleV1Recovery}=require('./lib/battle-v1-recovery');
const {PROTOCOL:BATTLE_V1_PROTOCOL,readBattleV1Rank,validBattleV1Rating}=require('./lib/battle-v1-public-profile');
const {PRODUCT_PROGRESS_FIELD,projectBattleV1ProductProgress,readBattleV1ProductProgress,
  productProgressProfile,completeBattleV1ProductSeason,repairBattleV1ProductSeasonCursor}=require('./lib/battle-v1-product-progress');
const {
  ARENAS,HEARTBEAT_STALE_MS,applyRankedAction,applyRankedSettlement,arenaIndexForProfile,createMatchState,heartbeatRankedState,hydrateMatch,profileSummary,
  sanitizeMatchReplay,sanitizeMatchView,sweepRankedState
}=require('./lib/ranked');

const emulatorNamespace=process.env.LUNO_DB_EMULATOR_NAMESPACE||'luno-chess-default-rtdb';
const databaseUrl=process.env.FIREBASE_DATABASE_EMULATOR_HOST
  ?'http://'+process.env.FIREBASE_DATABASE_EMULATOR_HOST+'?ns='+emulatorNamespace
  :'https://luno-chess-default-rtdb.firebaseio.com';
initializeApp({databaseURL:databaseUrl});
setGlobalOptions({region:'europe-west1',maxInstances:20,memory:'512MiB',timeoutSeconds:60});

const db=getDatabase();
const IN_FLIGHT_REQUESTS=new Map();
const PACKAGE_NAME='com.luno.chess';
const USERNAME_RE=/^[a-z0-9][a-z0-9_]{2,15}$/;
const USERNAME_CHANGE_COST=5000;
const ONBOARDING_REWARD=Object.freeze({gold:500});
const SOCIAL_VISIT_REWARDS=Object.freeze({sp_instagram:Object.freeze({gems:5}),sp_tiktok:Object.freeze({gems:5}),sp_youtube:Object.freeze({gems:5})});
const GOOGLE_PROVIDER_ID='google.com';
const ACCOUNT_LINK_TTL_MS=15*60*1000;
const PASS_CHEST_RECOVERY_MS=2*60*1000;
const RANKED_QUEUE_TTL_MS=2*60*1000;
const RANKED_SWEEP_LIMIT=80;
const RANKED_CHAT_COOLDOWN_MS=1500;
const FRIENDLY_INVITE_TTL_MS=5*60*1000;
const FRIENDLY_ROOM_TTL_MS=10*60*1000;
const FRIENDLY_DURATION_MINUTES=new Set([1,3,5,10,30]);
const DM_COOLDOWN_MS=1200;
const LEGAL_TERMS_VERSION='terms-2026-08-09';
const LEGAL_PRIVACY_VERSION='privacy-2026-08-09';
const LEGAL_COMMUNITY_VERSION='community-2026-08-13';
const {BIO_MAX_LENGTH,MESSAGE_MAX_LENGTH,normalizeUgcText,safePublicBio}=require('./lib/ugc-safety');
const APP_CHECK_EMULATOR_TOKEN='luno-emulator-app-check';
// Production is fail-closed: Firebase Auth proves the user, while App Check /
// Play Integrity proves that the request came from an attested app instance.
// Server-side eligibility, idempotency and rate limits remain defense in depth;
// they are not a replacement for attestation on online or economy routes.
const AUTH_FALLBACK_ROUTES=new Set();
const BILLING_RTDN_TOPIC=process.env.LUNO_BILLING_RTDN_TOPIC||'luno-play-billing-events';
const RANKED_CHAT_PRESETS=Object.freeze({
  greetings:new Set(['hello','good_luck','well_played','thanks','gl','hi','gg','wp']),
  reactions:new Set(['wow','haha','oops','think']),
  game:new Set(['nice','almost','tough','respect','oh_no'])
});
const RESERVED_USERNAMES=new Set(['admin','administrator','moderator','support','official','system','owner','lunochess','luno_official','luno_support']);
const USERNAME_ABUSE_RE=/(?:fuck|shit|siktir|orospu|nazi)/;
const ALLOWED_ORIGINS=new Set([
  'https://localhost',
  'capacitor://localhost',
  'https://luno-chess.web.app',
  'https://luno-chess.firebaseapp.com',
  'https://lunochessgame.web.app',
  'https://lunochessgame.firebaseapp.com'
]);
const STARTER_CARDS=['barbarian','card_block','poison_q','angry_n','glue','freeze'];
const STARTER_LEVELS={trap:1,radar:1,resist:1,deploy:1,shield:1};
const CARD_FAMILY_RE=/^(trap|radar|resist|shield|deploy)([123])?$/;
const PIECE_SET_IDS=new Set(['std','ottoman','roma','brit','viking','tasdevri','samuray','ice','dragon','neon']);
const COUNTRY_CODES=new Set(['TR','US','GB','DE','FR','IT','ES','NL','RU','JP','CN','KR','BR','AR','MX','IN','AU','CA','PL','SE','NO','FI','DK','GR','PT','BE','CH','AT','IE','UA','AZ','SA','AE','EG','ZA']);
const LEADERBOARD_FIELDS=Object.freeze({trophies:'trophies',collection:'collectionScore',season:'seasonScore',wins:'wins'});
const LEADERBOARD_MAX_LIMIT=100;
const COLLECTION_POINTS=Object.freeze({common:15,rare:60,legendary:200,mythic:500});
const AVATAR_IDS=new Set(['&#9818;','av_pawn','av_knight','av_bishop','av_rook','av_queen','av_king','av_robot','av_robotcrown','av_crown','av_lightning','av_fire']);
const FREE_COSTUMES=new Set(['k_classic','q_classic','r_classic','b_classic','n_classic','p_classic']);
const FREE_EMOJIS=new Set(['smile']);
const REPORT_REASONS=new Set(['harassment','threats','sexual_content','hate','spam','scam','cheating','abuse','other']);
const PASS_COSTUMES=new Set(['k_crystal','q_crystal','r_ice','b_wizard','n_armor','p_soldier']);
const COSTUME_TYPES={K:'k_',Q:'q_',R:'r_',B:'b_',N:'n_',P:'p_'};
const PAID_BY_KIND={};
Object.keys(SOFT_ITEM_CATALOG).forEach(function(itemId){
  const grant=SOFT_ITEM_CATALOG[itemId].grant||{};
  if(!PAID_BY_KIND[grant.kind])PAID_BY_KIND[grant.kind]=new Set();
  PAID_BY_KIND[grant.kind].add(grant.id);
});
const PRODUCT_CATALOG={
  luno_gold_1000:{type:'inapp',grant:{gold:1000}},
  luno_gold_5500:{type:'inapp',grant:{gold:5500}},
  luno_gold_15000:{type:'inapp',grant:{gold:15000}},
  luno_gem_80:{type:'inapp',grant:{gems:80}},
  luno_gem_500:{type:'inapp',grant:{gems:500}},
  luno_gem_1500:{type:'inapp',grant:{gems:1500}},
  luno_premium_month:{type:'subs',grant:{premiumDays:31}},
  luno_premium_year:{type:'subs',grant:{premiumDays:366}},
  luno_bundle_starter:{type:'inapp',grant:{gold:2500,gems:100}},
  luno_bundle_pro:{type:'inapp',grant:{gold:12000,gems:500}}
};

function normalizeUsername(value){
  return typeof value==='string'?value.normalize('NFKC').trim().toLowerCase():'';
}
function usernameValidationError(value){
  if(typeof value!=='string')return 'invalid-username';
  if(/[\u0000-\u001F\u007F-\u009F\u200B-\u200F\u202A-\u202E\u2060-\u206F\uFEFF]/u.test(value))return 'invalid-username';
  const username=normalizeUsername(value);
  if(!USERNAME_RE.test(username))return 'invalid-username';
  if(RESERVED_USERNAMES.has(username)||USERNAME_ABUSE_RE.test(username))return 'username-not-allowed';
  return '';
}
function cleanString(value,max){return String(value||'').trim().slice(0,max);}
function safeInt(value,fallback){const number=Number(value);return Number.isSafeInteger(number)&&number>=0?number:Number(fallback||0);}
function usernameRevision(profile){return Math.max(safeInt(profile&&profile.usernameRevision,0),safeInt(profile&&profile.usernameChanges,0));}
function canonicalUsername(profile,uid){
  const candidates=[profile&&profile.username,profile&&profile.name];
  for(const candidate of candidates){
    const normalized=normalizeUsername(candidate);
    if(!usernameValidationError(normalized))return normalized;
  }
  return 'luno_'+hash(String(uid||profile&&profile.uid||profile&&profile.playerCode||'unknown')).slice(0,8);
}
function usernameRepairCandidate(uid,attempt){
  return 'luno_'+hash(String(uid)+'|username-repair|'+String(attempt)).slice(0,8);
}
function delay(milliseconds){return new Promise(function(resolve){setTimeout(resolve,milliseconds);});}
const LOCAL_LOCKS=new Map();
async function withLocalLock(key,operation){
  const previous=LOCAL_LOCKS.get(key)||Promise.resolve();
  let release;
  const current=new Promise(function(resolve){release=resolve;});
  LOCAL_LOCKS.set(key,current);
  await previous;
  try{return await operation();}
  finally{
    release();
    if(LOCAL_LOCKS.get(key)===current)LOCAL_LOCKS.delete(key);
  }
}
function friendlyDurationMinutes(value){
  const minutes=Number(value===undefined?5:value);
  if(!Number.isInteger(minutes)||!FRIENDLY_DURATION_MINUTES.has(minutes))throw httpError(400,'invalid-time-control','Friendly matches support 1, 3, 5, 10 or 30 minutes.');
  return minutes;
}
function assertBodyKeys(body,allowed){
  if(!body||typeof body!=='object'||Array.isArray(body))throw httpError(400,'invalid-body','A JSON object is required.');
  const prototype=Object.getPrototypeOf(body);
  if(prototype!==Object.prototype&&prototype!==null)throw httpError(400,'unexpected-field','Request contains an unexpected field.');
  const allow=new Set(allowed||[]);
  for(const key of Object.keys(body)){
    if(key==='__proto__'||key==='prototype'||key==='constructor'||!allow.has(key))throw httpError(400,'unexpected-field','Request contains an unexpected field.');
  }
}
function assertPlainRecord(value,code){
  if(!value||typeof value!=='object'||Array.isArray(value))throw httpError(400,code||'invalid-object','A JSON object is required.');
  const prototype=Object.getPrototypeOf(value);
  if(prototype!==Object.prototype&&prototype!==null)throw httpError(400,'unexpected-field','Request contains an unexpected field.');
  for(const key of Object.keys(value))if(key==='__proto__'||key==='prototype'||key==='constructor')throw httpError(400,'unexpected-field','Request contains an unexpected field.');
  return value;
}
function strictString(value,max,code){
  if(typeof value!=='string')throw httpError(400,code||'invalid-string','A string value is required.');
  const normalized=value.normalize('NFKC').trim();
  if(normalized.length>max||/[\u0000-\u001F<>]/.test(normalized))throw httpError(400,code||'invalid-string','String value is invalid.');
  return normalized;
}
function requestId(req){
  const raw=cleanString(req.get('X-Luno-Request-Id')||'',128);
  return raw&&/^[a-zA-Z0-9._:-]+$/.test(raw)?raw:crypto.randomUUID();
}
function hash(value){return crypto.createHash('sha256').update(String(value)).digest('hex');}
function playerCode(uid,attempt=0){return 'LUNO-'+hash(attempt?String(uid)+'|player-code|'+attempt:uid).slice(0,8).toUpperCase();}
function now(){return Date.now();}
function httpError(status,code,message){const error=new Error(message||code);error.status=status;error.code=code;return error;}

function isIncompleteGuestProfile(profile){
  if(!profile||typeof profile!=='object'||Array.isArray(profile)||profile.uid)return false;
  // Recover only normalizer remnants, never a record containing earned progress.
  const normalizerFields=new Set(['serverActivity','serverSeason','deck','passState','collectionScore','playerCode','updatedAt','username','name','usernameRevision']);
  return Object.keys(profile).every(function(key){return normalizerFields.has(key);});
}

function normalizeLoginActivity(profile,at){
  const value=profile.serverActivity,current=value&&typeof value==='object'&&!Array.isArray(value)?value:{};
  const today=utcDayOrdinal(at),last=Number.isSafeInteger(Number(current.lastLoginDay))?Number(current.lastLoginDay):-1;
  if(last>=today)return false;
  const previousStreak=last===today-1?safeInt(current.loginStreak,0):0;
  profile.serverActivity={lastLoginDay:today,lastLoginAt:at,loginStreak:previousStreak+1};
  return true;
}

function tokenHasProvider(token,providerId){
  const firebaseIdentity=token&&token.firebase||{},identities=firebaseIdentity.identities||{};
  return firebaseIdentity.sign_in_provider===providerId||Object.prototype.hasOwnProperty.call(identities,providerId);
}
function hasRecordValues(value){return !!(value&&typeof value==='object'&&Object.keys(value).length);}
function profileHasProtectedProgress(profile){
  if(!profile||typeof profile!=='object')return true;
  if(safeInt(profile.trophies,0)>0||safeInt(profile.xp,0)>0||safeInt(profile.lvl,1)>1)return true;
  if(safeInt(profile.usernameChanges,0)>0||safeInt(profile.premiumUntil,0)>now())return true;
  if(profile.onboardingRewardClaimedAt||hasRecordValues(profile.achievementsClaimed))return true;
  const stats=profile.stats||{};
  if(['wins','losses','draws','bestStreak','winStreak','cardsPlayed','chestsOpened','captures','checks','promotions'].some(function(key){return safeInt(stats[key],0)>0;}))return true;
  const pass=profile.passState||{};
  if(safeInt(pass.level,0)>0||safeInt(pass.xp,0)>0||pass.premium===true||hasRecordValues(pass.claimed&&pass.claimed.free)||hasRecordValues(pass.claimed&&pass.claimed.premium))return true;
  const inventory=profile.inventory||{};
  if(stringMultisetList(inventory.pendingChests,[]).length)return true;
  if((stringList(inventory.ownedSkins).filter(function(id){return id!=='classic';}).length)||
     stringList(inventory.ownedEmojis).filter(function(id){return !FREE_EMOJIS.has(id);}).length||stringList(inventory.ownedCostumes).length||
     stringList(inventory.ownedFrames).filter(function(id){return id!=='none';}).length||
     stringList(inventory.ownedBioFrames).filter(function(id){return id!=='default';}).length||
     stringList(inventory.ownedSets).filter(function(id){return id!=='std';}).length)return true;
  const economy=profile.serverEconomy||{};
  return hasRecordValues(economy.claims)||hasRecordValues(economy.purchases)||hasRecordValues(economy.ledger);
}

function applyCors(req,res){
  const origin=req.get('origin');
  if(origin&&ALLOWED_ORIGINS.has(origin)){
    res.set('Access-Control-Allow-Origin',origin);
    res.set('Vary','Origin');
    res.set('Access-Control-Allow-Headers','Authorization, Content-Type, X-Firebase-AppCheck, X-Luno-Request-Id');
    res.set('Access-Control-Allow-Methods','POST, OPTIONS');
  }
  if(req.method==='OPTIONS'){
    if(origin&&!ALLOWED_ORIGINS.has(origin))throw httpError(403,'origin-denied','Origin is not allowed.');
    res.status(204).send('');return true;
  }
  if(origin&&!ALLOWED_ORIGINS.has(origin))throw httpError(403,'origin-denied','Origin is not allowed.');
  return false;
}
async function authenticate(req){
  const header=req.get('authorization')||'';
  const match=/^Bearer\s+(.+)$/i.exec(header);
  if(!match)throw httpError(401,'auth-required','A Firebase ID token is required.');
  try{return await getAuth().verifyIdToken(match[1],true);}
  catch(error){throw httpError(401,'invalid-token','The Firebase ID token is invalid or revoked.');}
}
async function assertAccountOperationAllowed(uid,route){
  const key=hash(uid);
  const [deletion,deleted]=await Promise.all([
    db.ref(`accountDeletions/${key}`).get(),
    db.ref(`deletedAccounts/${key}`).get(),
  ]);
  const state=deletion.val();
  // Data cleanup can succeed before Auth deletion; allow that workflow to resume.
  if(route==='deleteAccount'&&state&&state.status==='processing')return;
  if(deleted.exists()||state&&state.status==='complete'){
    throw httpError(403,'account-deleted','This account has been deleted.');
  }
  if(state&&route!=='deleteAccount'){
    throw httpError(409,'account-deletion-in-progress','Finish account deletion before making other requests.');
  }
}
function isAccountDeletionError(error){return !!(error&&['account-deleted','account-deletion-in-progress'].includes(error.code));}
async function writeAccountMetadata(uid,route,write,cleanup){
  await assertAccountOperationAllowed(uid,route);
  try{
    const result=await write();
    await assertAccountOperationAllowed(uid,route);
    return result;
  }catch(error){
    let deletionError=isAccountDeletionError(error)?error:null;
    if(!deletionError){
      try{await assertAccountOperationAllowed(uid,route);}
      catch(gateError){if(isAccountDeletionError(gateError))deletionError=gateError;}
    }
    // A write may commit after cleanup, even if its response was lost.
    if(deletionError){await cleanup();throw deletionError;}
    throw error;
  }
}
async function writeAccountAudit(uid,entry,key){
  const ref=db.ref(`auditLogs/${uid}/${key||crypto.randomUUID()}`);
  return writeAccountMetadata(uid,'writeAccountAudit',()=>ref.set(entry),()=>ref.remove());
}
async function releaseAccountLinkTicket(uid,ticketId){
  const result=await db.ref(`accountLinkTickets/${ticketId}`).transaction(function(value){
    if(value===null)return null;
    return value.uid===uid?null:undefined;
  },undefined,false);
  return result.committed;
}
async function writeAccountLinkTicket(uid,ticketId,entry){
  const ref=db.ref(`accountLinkTickets/${ticketId}`);
  return writeAccountMetadata(uid,'writeAccountLinkTicket',async function(){
    const result=await ref.transaction(function(value){
      if(value&&value.uid!==uid)return;
      return Object.assign({},entry,{uid});
    },undefined,false);
    if(!result.committed)throw httpError(409,'account-link-ticket-conflict','Support ticket ownership changed.');
  },()=>releaseAccountLinkTicket(uid,ticketId));
}
async function verifyAppAttestation(req,options){
  const raw=cleanString(req.get('X-Firebase-AppCheck')||'',8192);
  const allowAuthFallback=!!(options&&options.allowAuthFallback);
  if(!raw){
    if(allowAuthFallback)return {app_id:'firebase-auth-fallback',appId:'firebase-auth-fallback',tokenType:'firebase-auth',degraded:true};
    throw httpError(401,'app-check-required','A Firebase App Check token is required.');
  }
  const emulator=!!process.env.FIREBASE_AUTH_EMULATOR_HOST;
  if(raw===APP_CHECK_EMULATOR_TOKEN){
    if(!emulator)throw httpError(401,'invalid-app-check','Debug App Check tokens are not accepted in production.');
    return {app_id:PACKAGE_NAME,tokenType:'emulator'};
  }
  try{
    const verifier=options&&options.verifyToken?options.verifyToken:function(token){return getAppCheck().verifyToken(token);};
    const verified=await verifier(raw);
    const decoded=verified&&verified.token&&typeof verified.token==='object'?verified.token:verified;
    const appId=cleanString(verified&&verified.appId||decoded&&decoded.app_id||decoded&&decoded.sub||'',256);
    if(!decoded||!appId)throw new Error('missing-app-id');
    return Object.assign({},decoded,{app_id:appId,appId});
  }catch(error){
    throw httpError(401,'invalid-app-check','The Firebase App Check token is invalid or expired.');
  }
}
async function rateLimit(uid,operation,limit,windowMs){
  const bucket=Math.floor(now()/windowMs);
  const ref=db.ref(`serverRateLimits/${uid}/${operation}/${bucket}`);
  const result=await writeAccountMetadata(uid,operation,()=>ref.transaction(function(value){
    const count=safeInt(value,0);
    return count>=limit?undefined:count+1;
  },undefined,false),()=>ref.remove());
  if(!result.committed)throw httpError(429,'rate-limited','Too many requests.');
}
function requestClaimCanRecover(operation,value,at){
  const prefix=['openPassChest:','openChest:'].find(prefix=>operation.startsWith(prefix));
  const itemId=operation.startsWith('purchaseSoftItem:')?operation.slice('purchaseSoftItem:'.length):null;
  const permanentItem=itemId&&Object.hasOwn(SOFT_ITEM_CATALOG,itemId)&&!SOFT_ITEM_CATALOG[itemId].seasonScoped;
  const passSeason=operation.startsWith('purchaseSoftItem:pass:premium:')?operation.slice('purchaseSoftItem:pass:premium:'.length):null;
  if(!permanentItem&&!validPassPurchaseSeason(passSeason)&&(!prefix||!Object.hasOwn(CHEST_CATALOG,operation.slice(prefix.length))))return false;
  if(!value||value.operation!==operation||value.status!=='processing')return false;
  const startedAt=value.startedAt==null?value.createdAt:value.startedAt;
  return Number.isSafeInteger(startedAt)&&startedAt>0&&at-startedAt>=PASS_CHEST_RECOVERY_MS;
}
async function idempotent(uid,id,operation,work){
  await assertAccountOperationAllowed(uid,operation);
  const key=hash(id).slice(0,48);
  const inFlightKey=uid+':'+key,existingFlight=IN_FLIGHT_REQUESTS.get(inFlightKey);
  if(existingFlight){
    if(existingFlight.operation!==operation)throw httpError(409,'request-id-conflict','Request id belongs to another operation.');
    const shared=await existingFlight.promise;
    await assertAccountOperationAllowed(uid,operation);
    return Object.assign({},shared||{},{idempotent:true});
  }
  const promise=(async function(){
    const ref=db.ref(`serverRequests/${uid}/${key}`),ownerToken=crypto.randomUUID(),startedAt=now();
    const claim=await ref.transaction(function(value){
      if(value&&!requestClaimCanRecover(operation,value,startedAt))return;
      return {operation,status:'processing',ownerToken,startedAt,attempts:safeInt(value&&value.attempts,0)+1,createdAt:value&&value.createdAt||ServerValue.TIMESTAMP};
    },undefined,false);
    if(!claim.committed){
      const existing=claim.snapshot.val()||{};
      if(existing.operation!==operation)throw httpError(409,'request-id-conflict','Request id belongs to another operation.');
      if(existing.status==='complete'){
        await assertAccountOperationAllowed(uid,operation);
        return Object.assign({},existing.result||{},{idempotent:true});
      }
      throw httpError(409,'request-in-progress','The same request is already being processed.');
    }
    try{
      await assertAccountOperationAllowed(uid,operation);
      const result=await work();
      await assertAccountOperationAllowed(uid,operation);
      const completed=await ref.transaction(function(value){
        if(value===null)return null;
        if(value.ownerToken!==ownerToken||value.operation!==operation||value.status!=='processing')return;
        return Object.assign({},value,{status:'complete',completedAt:ServerValue.TIMESTAMP,result:result||{ok:true}});
      },undefined,false);
      if(!completed.committed||!completed.snapshot.val())throw httpError(503,'request-state-changed','Request ownership changed. Retry the same request.');
      await assertAccountOperationAllowed(uid,operation);
      return result;
    }catch(error){
      await ref.transaction(function(value){
        if(value===null)return null;
        return value.ownerToken===ownerToken?null:undefined;
      },undefined,false).catch(function(){});
      throw error;
    }
  })();
  IN_FLIGHT_REQUESTS.set(inFlightKey,{operation,promise});
  try{
    return await promise;
  }finally{
    const current=IN_FLIGHT_REQUESTS.get(inFlightKey);
    if(current&&current.promise===promise)IN_FLIGHT_REQUESTS.delete(inFlightKey);
  }
}
async function transactExistingPlayer(uid,mutate){
  const userRef=db.ref(`users/${uid}`),initialSnapshot=await userRef.get();
  if(!initialSnapshot.exists())throw httpError(404,'profile-not-found','Player profile does not exist.');
  let decision=null,transaction;
  for(let attempt=0;attempt<3;attempt++){
    decision=null;
    try{
      transaction=await userRef.transaction(function(profile){
        if(!profile){
          // Probe server data without restoring a deleted account from a snapshot.
          decision=null;return null;
        }
        const previousProfile=structuredClone(profile);
        decision=mutate(profile)||{commit:false};
        if(decision.commit===true){
          profile.collectionScore=collectionScoreForProfile(profile);
          finalizePlayerStateRevision(profile,previousProfile);
        }
        return decision.commit===true?profile:undefined;
      },undefined,false);
      break;
    }catch(error){
      if(error.code!=='MAXRETRY'&&error.message!=='maxretry')throw error;
      if(attempt===2)throw httpError(503,'profile-busy','Player data is busy. Retry the request.');
      // Only an uncommitted contention failure is safe to re-evaluate.
      await new Promise(resolve=>setTimeout(resolve,25*(attempt+1)));
    }
  }
  let profile=transaction.snapshot.val();
  if(!transaction.committed&&!profile)profile=(await userRef.get()).val();
  if(!profile)throw httpError(404,'profile-not-found','Player profile does not exist.');
  if(!decision)throw httpError(409,'profile-changed','Player profile changed during the transaction. Retry the request.');
  return {committed:transaction.committed,decision:decision||{commit:false},profile};
}
function collectionScoreForProfile(profile){
  const unlocked=profile&&profile.unlockedCards&&typeof profile.unlockedCards==='object'?profile.unlockedCards:{};
  const counted=new Set();
  let score=0;
  Object.keys(unlocked).forEach(function(rawKey){
    if(unlocked[rawKey]!==true)return;
    const key=String(rawKey),familyMatch=key.match(CARD_FAMILY_RE),catalogKey=familyMatch?familyMatch[1]+'1':key;
    if(counted.has(catalogKey))return;
    const definition=CARD_UNLOCK_CATALOG[catalogKey];
    if(!definition)return;
    counted.add(catalogKey);score+=COLLECTION_POINTS[definition.rarity]||0;
  });
  return score;
}
async function releaseOwnedIndex(ref,uid){
  let removed=false;
  const transaction=await ref.transaction(function(value){
    removed=false;
    if(value===null)return null;
    if(value!==uid)return;
    removed=true;return null;
  },undefined,false);
  return transaction.committed&&removed;
}
async function releaseUsernameIfOwned(username,uid){
  const normalized=normalizeUsername(username);
  if(!normalized)return false;
  return releaseOwnedIndex(db.ref(`usernames/${normalized}`),uid);
}
function starterProfile(uid,username){
  const periods=periodSnapshot(now()),season=Number(periods.seasonId.slice(1));
  const unlocked={};STARTER_CARDS.forEach(function(card){unlocked[card]=true;});
  return {
    uid,
    playerCode:playerCode(uid),
    name:username,
    username,
    usernameChanges:0,
    usernameRevision:0,
    usernameChangedAt:0,
    country:'TR',
    avatar:'#e8b840',
    avatarEmoji:'av_pawn',
    bio:'',
    photoURL:null,
    photoAnimated:false,
    trophies:0,
    arenaIdx:0,
    gold:1250,
    gems:50,
    xp:0,
    lvl:1,
    createdAt:ServerValue.TIMESTAMP,
    starterGrantVersion:2,
    battleV1MigrationPolicy:'native-v1',
    productEntitlementVersion:ENTITLEMENT_VERSION,
    deck:STARTER_CARDS,
    emojiLoadout:[],
    collectionScore:collectionScoreForProfile({unlockedCards:unlocked}),
    deckSlots:6,
    unlockedCards:unlocked,
    cardLevel:STARTER_LEVELS,
    inventory:{
      ownedSkins:['classic'],ownedEmojis:['smile'],ownedFrames:['none'],ownedBioFrames:['default'],
      bioFrameShards:{},frameShards:{},skinPieces:{},emojiPieces:{},ownedCostumes:[],
      activeCostumes:{},activeSkin:'classic',activePieceSet:'std',ownedSets:['std'],pendingChests:[],
      lastDailyReward:0,dailyStreak:0
    },
    missions:{daily:{},weekly:{},special:{}},
    achievementsClaimed:{},
    passState:{seasonKey:'ranked-'+periods.seasonId+'-v2',seasonStartedAt:periods.serverTime,season,level:0,xp:0,premium:false,claimed:{free:{},premium:{}}},
    serverSeason:{number:season,seasonId:periods.seasonId,peakTrophies:0,startedAt:periods.serverTime,claimed:{}},
    stats:{wins:0,losses:0,draws:0,bestStreak:0,winStreak:0,cardsPlayed:0,chestsOpened:0,captures:0,checks:0,promotions:0},
    serverActivity:{},
    serverProgress:{missions:{daily:{},weekly:{},special:{}},passMissions:{daily:{},weekly:{},special:{}}},
    serverEconomy:{schemaVersion:SERVER_SCHEMA_VERSION,claims:{},purchases:{},ledger:{},daily:{streak:0}},
    serverSchemaVersion:SERVER_SCHEMA_VERSION,
    serverVersion:SERVER_SCHEMA_VERSION,
    updatedAt:ServerValue.TIMESTAMP
  };
}
function publicProfile(profile,at){
  const timestamp=Number.isSafeInteger(at)?at:now();
  const username=canonicalUsername(profile,profile&&profile.uid);
  return {
    name:username,
    username,
    usernameRevision:usernameRevision(profile),
    playerCode:cleanString(profile.playerCode||playerCode(profile.uid),13),
    country:cleanString(profile.country||'TR',2),
    avatar:cleanString(profile.avatar||'#e8b840',16),
    avatarEmoji:cleanString(profile.avatarEmoji||'&#9818;',32),
    bio:safePublicBio(profile.bio),
    frame:cleanString(profile.frame||'none',64),
    bioFrame:cleanString(profile.bioFrame||'default',64),
    dmFriendsOnly:profile.dmFriendsOnly===true,
    photoURL:profile.photoURL||null,
    trophies:safeInt(profile.trophies,0),
    arenaIdx:arenaIndexForProfile(profile),
    collectionScore:collectionScoreForProfile(profile),
    seasonScore:safeInt(profile.serverSeason&&profile.serverSeason.peakTrophies,0),
    wins:safeInt(profile.stats&&profile.stats.wins,0),
    gamesPlayed:safeInt(profile.stats&&profile.stats.wins,0)+safeInt(profile.stats&&profile.stats.losses,0)+safeInt(profile.stats&&profile.stats.draws,0),
    lvl:safeInt(profile.lvl,1),
    xp:safeInt(profile.xp,0),
    isPremium:premiumAccess(profile,timestamp),
    profileUpdatedAt:safeInt(profile.updatedAt,0),
    profileProjectedAt:timestamp,
    updatedAt:ServerValue.TIMESTAMP
  };
}

async function reserveUsernameForUid(username,uid){
  const normalized=normalizeUsername(username),validationError=usernameValidationError(normalized);
  if(validationError)throw httpError(409,'username-conflict','The player profile has an invalid username and needs reconciliation.');
  const ref=db.ref(`usernames/${normalized}`);
  const reservation=await ref.transaction(function(value){return value===null||value===uid?uid:undefined;},undefined,false);
  if(!reservation.committed&&reservation.snapshot.val()!==uid)throw httpError(409,'username-taken','This username is already in use.');
  return normalized;
}

async function releaseOtherUsernameReservations(uid,keepUsername){
  const keep=normalizeUsername(keepUsername),snapshot=await db.ref('usernames').orderByValue().equalTo(uid).get();
  const owned=Object.keys(snapshot.val()||{}).filter(function(username){return username!==keep;});
  await Promise.all(owned.map(function(username){return releaseOwnedIndex(db.ref(`usernames/${username}`),uid);}));
  return owned.length;
}

async function withUsernameLock(uid,operation){
  return withLocalLock('username:'+uid,async function(){
    const ref=db.ref(`usernameLocks/${uid}`),token=crypto.randomUUID(),deadline=now()+8000;
    let acquired=false;
    while(!acquired&&now()<deadline){
      const transaction=await ref.transaction(function(value){
        const holder=value&&typeof value==='object'?value:null,expiresAt=Number(holder&&holder.expiresAt)||0;
        if(!holder||expiresAt<=now()||holder.token===token)return {token,expiresAt:now()+60000};
        return undefined;
      },undefined,false);
      acquired=transaction.committed&&transaction.snapshot.val()&&transaction.snapshot.val().token===token;
      if(!acquired)await delay(50+Math.floor(Math.random()*75));
    }
    if(!acquired)throw httpError(409,'username-change-busy','Username is being updated. Please try again.');
    try{return await operation();}
    finally{
      try{
        await ref.transaction(function(value){
          if(value===null)return null;
          return value&&value.token===token?null:undefined;
        },undefined,false);
      }catch(error){logger.warn('Username lock release failed',{uidHash:hash(uid).slice(0,16),error:String(error&&error.code||error)});}
    }
  });
}

// All writes that describe a relationship between two players share one
// short-lived RTDB lock. This keeps opposite-direction requests, accepts,
// removals and friendly invitations from interleaving across function
// instances.
async function withSocialPairLock(firstUid,secondUid,operation,identity=null){
  const pairKey=hash(identity||[String(firstUid),String(secondUid)].sort().join('|')).slice(0,48);
  return withLocalLock('social:'+pairKey,async function(){
    const ref=db.ref(`socialLocks/${pairKey}`),token=crypto.randomUUID(),deadline=now()+8000;
    let acquired=false;
    while(!acquired&&now()<deadline){
      const transaction=await ref.transaction(function(value){
        const holder=value&&typeof value==='object'?value:null,expiresAt=Number(holder&&holder.expiresAt)||0;
        if(!holder||expiresAt<=now()||holder.token===token)return {token,expiresAt:now()+60000};
        return undefined;
      },undefined,false);
      acquired=transaction.committed&&transaction.snapshot.val()&&transaction.snapshot.val().token===token;
      if(!acquired)await delay(50+Math.floor(Math.random()*75));
    }
    if(!acquired)throw httpError(409,'social-operation-busy','This social action is already being processed.');
    try{return await operation();}
    finally{
      try{
        await ref.transaction(function(value){
          if(value===null)return null;
          return value&&value.token===token?null:undefined;
        },undefined,false);
      }catch(error){logger.warn('Social lock release failed',{pairHash:pairKey.slice(0,16),error:String(error&&error.code||error)});}
    }
  });
}

async function ownedDirectMessageConversations(uid){
  // RTDB get rejects this dynamic unindexed query; a one-time listen retains its membership filter.
  return (await db.ref('dm').orderByChild('members/'+uid).equalTo(true).once('value')).val()||{};
}
function sameDirectMessageProof(value,proof){
  return value&&typeof value==='object'&&!Array.isArray(value)&&
    Object.keys(value).length===Object.keys(proof).length&&
    Object.entries(proof).every(([field,item])=>value[field]===item);
}
function directMessageBindingRef(uid,requestHash){
  // Reserved private metadata, separate from cooldown rows and disposable request cache.
  return db.ref(`messageThrottle/${uid}/!sendRequests/${requestHash}`);
}
async function eraseDirectMessagePair(firstUid,secondUid,delivery=null,key=conversationId(firstUid,secondUid)){
  await db.ref(`dm/${key}`).transaction(function(value){
    if(value===null)return null;
    const members=Object.keys(value.members||{}),pair=new Set([firstUid,secondUid]);
    const foreign=members.some(uid=>!pair.has(uid))||
      !members.length&&Object.values(value.msgs||{}).some(message=>!pair.has(message?.from));
    if(!foreign)return null;
    if(!delivery?.messageId)return;
    let changed=false;
    const message=value.msgs?.[delivery.messageId],proofs=value.sendRequests?.[hash(firstUid)],proof=proofs?.[delivery.requestHash];
    if(message&&message.from===firstUid&&message.text===delivery.text&&message.ts===delivery.createdAt){
      delete value.msgs[delivery.messageId];changed=true;
      if(!Object.keys(value.msgs).length)delete value.msgs;
    }
    if(sameDirectMessageProof(proof,delivery.proof)){
      delete proofs[delivery.requestHash];changed=true;
      if(!Object.keys(proofs).length)delete value.sendRequests[hash(firstUid)];
      if(!Object.keys(value.sendRequests).length)delete value.sendRequests;
    }
    return changed?value:undefined;
  },undefined,false);
}
async function cleanupDeletedSocialPair(firstUid,secondUid,delivery=null){
  const updates={};
  for(const [uid,targetUid] of [[firstUid,secondUid],[secondUid,firstUid]]){
    for(const root of ['friends','friendRequests','outgoingFriendRequests','matchInvites','matchInviteThrottle',
      'dmInbox','blocks','blockedBy','mutes','messageThrottle'])updates[`${root}/${uid}/${targetUid}`]=null;
  }
  await db.ref().update(updates);
  if(delivery?.proof){
    try{await assertAccountOperationAllowed(firstUid,'socialInteraction');}
    catch(error){
      if(!isAccountDeletionError(error))throw error;
      await directMessageBindingRef(firstUid,delivery.requestHash).transaction(value=>
        value===null||sameDirectMessageProof(value,delivery.proof)?null:undefined,undefined,false);
    }
  }
  await removeBattleV1Invites(firstUid,secondUid);
  await eraseDirectMessagePair(firstUid,secondUid,delivery);
  for(const [uid,targetUid] of [[firstUid,secondUid],[secondUid,firstUid]]){
    const notices=(await db.ref(`notifications/${uid}`).orderByChild('fromUid').equalTo(targetUid).get()).val()||{};
    for(const key of Object.keys(notices))await db.ref(`notifications/${uid}/${key}`).transaction(function(value){
      if(value===null)return null;
      return value.fromUid===targetUid?null:undefined;
    },undefined,false);
  }
}
async function withSocialPairMetadata(uid,targetUid,operation,delivery=null){
  return withSocialPairLock(uid,targetUid,async function(){
    let cleanup;
    const erase=()=>cleanup||(cleanup=cleanupDeletedSocialPair(uid,targetUid,delivery));
    try{
      return await writeAccountMetadata(uid,'socialInteraction',()=>
        writeAccountMetadata(targetUid,'socialInteraction',async function(){
          await requirePlayer(uid);
          await targetPlayer(targetUid,uid);
          return operation();
        },erase),erase);
    }catch(error){
      if(isAccountDeletionError(error)){
        // A deleted recipient must not invalidate the surviving sender's session.
        await assertAccountOperationAllowed(uid,'socialInteraction');
        throw httpError(404,'target-not-found','Target player does not exist.');
      }
      throw error;
    }
  });
}
async function withDirectMessageMetadata(uid,targetUid,operation,delivery=null){
  // Distinct UID pairs can share a legacy conversation key; serialize its ownership too.
  return withSocialPairLock(uid,targetUid,()=>withSocialPairMetadata(uid,targetUid,operation,delivery),
    JSON.stringify(['dm-conversation',conversationId(uid,targetUid)]));
}

async function reconcileUsernameState(uid){
  const userRef=db.ref(`users/${uid}`),snapshot=await userRef.get();
  if(!snapshot.exists()||isIncompleteGuestProfile(snapshot.val()))throw httpError(404,'profile-not-found','Player profile does not exist.');
  const initial=snapshot.val(),desired=canonicalUsername(initial,uid),ownedSnapshot=await db.ref('usernames').orderByValue().equalTo(uid).limitToFirst(2).get(),owned=ownedSnapshot.val()||{};
  const needsRepair=initial.username!==desired||initial.name!==desired||owned[desired]!==uid||Object.keys(owned).some(function(username){return username!==desired;});
  if(!needsRepair)return initial;
  return withUsernameLock(uid,async function(){
    await assertAccountOperationAllowed(uid,'getPlayerState');
    const latestSnapshot=await userRef.get();
    if(!latestSnapshot.exists())throw httpError(404,'profile-not-found','Player profile does not exist.');
    const latest=latestSnapshot.val(),sourceUsername=canonicalUsername(latest,uid),at=now();
    let username=sourceUsername;
    try{
      await reserveUsernameForUid(username,uid);
    }catch(error){
      if(!error||error.code!=='username-taken')throw error;
      let repairedReservation=false;
      for(let attempt=0;attempt<8&&!repairedReservation;attempt++){
        username=usernameRepairCandidate(uid,attempt);
        try{
          await reserveUsernameForUid(username,uid);
          repairedReservation=true;
        }catch(candidateError){
          if(!candidateError||candidateError.code!=='username-taken')throw candidateError;
        }
      }
      if(!repairedReservation)throw httpError(503,'username-repair-unavailable','A safe username could not be reserved.');
    }
    try{
      const result=await transactExistingPlayer(uid,function(profile){
        const current=canonicalUsername(profile,uid),revision=usernameRevision(profile);
        if(current!==sourceUsername)return {commit:false,error:'username-state-changed'};
        const repaired=profile.username!==username||profile.name!==username||safeInt(profile.usernameRevision,0)!==revision;
        if(repaired){
          profile.username=username;profile.name=username;profile.usernameRevision=revision;
          profile.updatedAt=nextProfileUpdateTime(profile,at);
        }
        return {commit:repaired};
      });
      if(result.decision.error)throw httpError(409,result.decision.error,'Player username changed during repair. Retry the request.');
      await releaseOtherUsernameReservations(uid,username);
      await publishPublicProfile(uid,result.profile,at);
      return result.profile;
    }catch(error){
      const current=(await userRef.get()).val();
      if(!current||canonicalUsername(current,uid)!==username)await releaseUsernameIfOwned(username,uid).catch(function(){});
      throw error;
    }
  });
}

function nextProfileUpdateTime(profile,at){
  const previous=safeInt(profile&&profile.updatedAt,0);
  if(!Number.isSafeInteger(at)||at<0||previous>=Number.MAX_SAFE_INTEGER)throw httpError(409,'profile-clock-invalid','Profile update ordering is unavailable.');
  return Math.max(at,previous+1);
}

async function publishPublicProfile(uid,profile,at){
  const deletionError=error=>error&&['account-deleted','account-deletion-in-progress'].includes(error.code);
  try{await assertAccountOperationAllowed(uid,'publishPublicProfile');}
  catch(error){if(deletionError(error))return;throw error;}
  const ref=db.ref(`publicProfiles/${uid}`),candidate=publicProfile(profile,at),candidateRevision=safeInt(candidate.usernameRevision,0);
  await ref.transaction(function(current){
    const currentRevision=safeInt(current&&current.usernameRevision,0);
    // Publication completion order must not roll back newer profile contents.
    const currentSourceAt=safeInt(current&&current.profileUpdatedAt,0);
    const staleContents=currentRevision===candidateRevision&&(currentSourceAt>candidate.profileUpdatedAt||
      currentSourceAt===candidate.profileUpdatedAt&&safeInt(current&&current.profileProjectedAt,0)>candidate.profileProjectedAt);
    return current&&(currentRevision>candidateRevision||staleContents)?undefined:candidate;
  });
  // A cleanup can finish between the first gate and the publication write.
  try{await assertAccountOperationAllowed(uid,'publishPublicProfile');}
  catch(error){
    await ref.remove();
    if(!deletionError(error))throw error;
  }
}

async function publishPlayerCode(uid,code){
  const key=cleanString(code,13).toLowerCase();
  if(!/^luno-[a-f0-9]{8}$/.test(key))throw httpError(409,'player-code-invalid','Player code is invalid.');
  await assertAccountOperationAllowed(uid,'publishPlayerCode');
  const ref=db.ref(`playerCodes/${key}`);
  const transaction=await ref.transaction(function(value){return value===null||value===uid?uid:undefined;},undefined,false);
  if(!transaction.committed&&transaction.snapshot.val()!==uid)throw httpError(409,'player-code-conflict','Player code is already reserved.');
  try{await assertAccountOperationAllowed(uid,'publishPlayerCode');}
  catch(error){
    await releaseOwnedIndex(ref,uid);
    throw error;
  }
}

function normalizedPlayerCode(value){
  return typeof value==='string'&&/^LUNO-[A-F0-9]{8}$/i.test(value)?value.toUpperCase():'';
}
async function repairPlayerCodeIndex(uid){
  await assertAccountOperationAllowed(uid,'getPlayerState');
  const userRef=db.ref(`users/${uid}`),initial=(await userRef.get()).val();
  if(!initial)throw httpError(404,'profile-not-found','Player profile does not exist.');
  if(initial.uid!==uid)throw httpError(403,'profile-owner-mismatch','Player profile ownership does not match.');
  const primary=normalizedPlayerCode(initial.playerCode)||playerCode(uid);
  for(let attempt=0;attempt<16;attempt++){
    const candidate=attempt?playerCode(uid,attempt):primary;
    try{await publishPlayerCode(uid,candidate);}
    catch(error){if(error.code==='player-code-conflict')continue;throw error;}
    try{
      const at=now(),result=await transactExistingPlayer(uid,function(profile){
        if(profile.uid!==uid)return {commit:false,error:'profile-owner-mismatch'};
        if(normalizedPlayerCode(profile.playerCode)!==normalizedPlayerCode(initial.playerCode))return {commit:false,error:'player-code-state-changed'};
        if(profile.playerCode===candidate)return {commit:false};
        profile.playerCode=candidate;profile.updatedAt=nextProfileUpdateTime(profile,at);
        return {commit:true};
      });
      if(result.decision.error)throw httpError(result.decision.error==='profile-owner-mismatch'?403:409,result.decision.error,'Player code changed during repair. Retry the request.');
      const owned=(await db.ref('playerCodes').orderByValue().equalTo(uid).get()).val()||{};
      await Promise.all(Object.keys(owned).filter(function(key){return key!==candidate.toLowerCase();}).map(function(key){return releaseOwnedIndex(db.ref(`playerCodes/${key}`),uid);}));
      await publishPublicProfile(uid,result.profile,at);
      await assertAccountOperationAllowed(uid,'getPlayerState');
      return result.profile;
    }catch(error){
      const current=(await userRef.get()).val();
      if(!current||normalizedPlayerCode(current.playerCode)!==candidate)await releaseOwnedIndex(db.ref(`playerCodes/${candidate.toLowerCase()}`),uid).catch(function(){});
      throw error;
    }
  }
  throw httpError(503,'player-code-unavailable','A unique player code could not be reserved. Retry later.');
}
async function reconcilePlayerCodeState(uid,profile){
  if(profile.uid!==uid)throw httpError(403,'profile-owner-mismatch','Player profile ownership does not match.');
  const code=normalizedPlayerCode(profile.playerCode);
  if(code&&profile.playerCode===code&&(await db.ref(`playerCodes/${code.toLowerCase()}`).get()).val()===uid)return profile;
  // Guest creation/deletion already holds this lock; refresh enters it here.
  return withUsernameLock(uid,async function(){return repairPlayerCodeIndex(uid);});
}

async function createGuestPlayer(context){
  const {uid,token,body}=context;
  assertBodyKeys(body,['username']);
  if(token.firebase&&token.firebase.sign_in_provider!=='anonymous')throw httpError(409,'not-anonymous','This endpoint only creates anonymous guest profiles.');
  // Old clients may send username, but guest bootstrap never publishes client UGC.
  await rateLimit(uid,'createGuestPlayer',8,60*1000);
  const result=await idempotent(uid,context.requestId,'createGuestPlayer',async function(){
    return withUsernameLock(uid,async function(){
      await assertAccountOperationAllowed(uid,'createGuestPlayer');
      const userRef=db.ref(`users/${uid}`),existing=(await userRef.get()).val();
      if(existing&&!isIncompleteGuestProfile(existing)){
        if(existing.uid!==uid)throw httpError(403,'profile-owner-mismatch','Player profile ownership does not match.');
        const existingUsername=canonicalUsername(existing,uid);
        await reserveUsernameForUid(existingUsername,uid);
        try{
          const at=now(),result=await transactExistingPlayer(uid,function(current){
            if(canonicalUsername(current,uid)!==existingUsername)return {commit:false,error:'profile-exists'};
            const revision=usernameRevision(current),repaired=current.username!==existingUsername||current.name!==existingUsername||safeInt(current.usernameRevision,0)!==revision;
            if(repaired){
              current.username=existingUsername;current.name=existingUsername;current.usernameRevision=revision;
              current.updatedAt=nextProfileUpdateTime(current,at);
            }
            return {commit:repaired};
          });
          if(result.decision.error)throw httpError(409,result.decision.error,'This guest already has another player username.');
          await releaseOtherUsernameReservations(uid,existingUsername);
          await repairPlayerCodeIndex(uid);
          return {ok:true,created:false,uid,username:existingUsername,usernameGenerated:result.profile.usernameGenerated===true};
        }catch(error){
          const current=(await userRef.get()).val();
          if(!current||canonicalUsername(current,uid)!==existingUsername)await releaseUsernameIfOwned(existingUsername,uid).catch(function(){});
          throw error;
        }
      }
      let username=canonicalUsername(null,uid),reserved=false;
      for(let attempt=0;attempt<16&&!reserved;attempt++){
        if(attempt)username=usernameRepairCandidate(uid,attempt-1);
        try{await reserveUsernameForUid(username,uid);reserved=true;}
        catch(error){if(!error||error.code!=='username-taken')throw error;}
      }
      if(!reserved)throw httpError(503,'guest-username-unavailable','A guest identity could not be reserved. Retry later.');
      try{
        const created=await userRef.transaction(function(value){
          if(value!==null&&!isIncompleteGuestProfile(value))return;
          const profile=starterProfile(uid,username);
          profile.usernameGenerated=true;
          if(value&&value.serverActivity)profile.serverActivity=value.serverActivity;
          return profile;
        },undefined,false);
        if(!created.committed){
          const raced=created.snapshot.val(),racedUsername=canonicalUsername(raced,uid);
          if(raced&&raced.uid===uid&&!isIncompleteGuestProfile(raced)){
            if(racedUsername!==username)await releaseUsernameIfOwned(username,uid);
            await reserveUsernameForUid(racedUsername,uid);
            await releaseOtherUsernameReservations(uid,racedUsername);
            await repairPlayerCodeIndex(uid);
            return {ok:true,created:false,uid,username:racedUsername,usernameGenerated:raced.usernameGenerated===true};
          }
          throw httpError(409,'profile-race','Profile creation conflicted with another request.');
        }
        await releaseOtherUsernameReservations(uid,username);
        await repairPlayerCodeIndex(uid);
        await writeAccountAudit(uid,{type:'guest-created',username,at:ServerValue.TIMESTAMP});
        return {ok:true,created:true,uid,username,usernameGenerated:true};
      }catch(error){
        const latest=(await userRef.get()).val();
        if(!latest||canonicalUsername(latest,uid)!==username)await releaseUsernameIfOwned(username,uid).catch(function(){});
        throw error;
      }
    });
  });
  // A replay can outlive the first chosen name. Return current identity, not the
  // old cached alias, without granting starter items or replacing the profile.
  const current=await requirePlayer(uid);
  if(current.uid!==uid)throw httpError(403,'profile-owner-mismatch','Player profile ownership does not match.');
  await assertAccountOperationAllowed(uid,'createGuestPlayer');
  return Object.assign({},result,{username:canonicalUsername(current,uid),usernameGenerated:current.usernameGenerated===true});
}

async function authUserHasProvider(uid,token,providerId){
  if(tokenHasProvider(token,providerId))return true;
  const record=await getAuth().getUser(uid);
  return (record.providerData||[]).some(function(provider){return provider&&provider.providerId===providerId;});
}
async function accountSwitchAssessment(uid,profile){
  const snapshots=await Promise.all([
    db.ref('purchaseClaims').orderByChild('uid').equalTo(uid).limitToFirst(1).get(),
    db.ref(`rankedState/activeByUser/${uid}`).get(),
    db.ref(`rankedState/queue/${uid}`).get(),
    db.ref(`friendlyRoomByUser/${uid}`).get()
  ]);
  const at=now(),hasPurchaseEntitlement=snapshots[0].exists();
  const activeMatchId=cleanString(snapshots[1].val(),40);
  let hasActiveRankedMatch=false;
  if(validServerMatchId(activeMatchId)){
    const activeMatch=hydrateMatch((await db.ref(`rankedState/matches/${activeMatchId}`).get()).val());
    hasActiveRankedMatch=!!(activeMatch&&activeMatch.participants&&activeMatch.participants[uid]===true&&activeMatch.status==='active'&&!activeMatch.result);
  }
  const queue=snapshots[2].val()||{},queueSeen=safeInt(queue.lastSeenAt||queue.joinedAt,0);
  const hasLiveQueue=!!(queue.uid===uid&&queueSeen>0&&at-queueSeen<=RANKED_QUEUE_TTL_MS);
  const roomCode=cleanString(snapshots[3].val(),6);
  let hasOpenFriendlyRoom=false;
  if(/^[A-Z0-9]{6}$/.test(roomCode)){
    const room=(await db.ref(`friendlyRooms/${roomCode}`).get()).val();
    hasOpenFriendlyRoom=!!(room&&room.hostUid===uid&&['waiting','matching'].includes(room.status)&&safeInt(room.expiresAt,0)>at);
  }
  hasActiveRankedMatch=hasActiveRankedMatch||hasLiveQueue||hasOpenFriendlyRoom;
  const hasProtectedProgress=profileHasProtectedProgress(profile);
  return {
    hasProtectedProgress,
    hasPurchaseEntitlement,
    hasActiveRankedMatch,
    switchAllowed:!hasProtectedProgress&&!hasPurchaseEntitlement&&!hasActiveRankedMatch
  };
}
function linkAttemptId(uid,requestId){return hash(`google-link:${uid}:${requestId}`).slice(0,32);}

async function prepareGoogleLink(context){
  const {uid,token,body}=context;
  assertBodyKeys(body,[]);
  await rateLimit(uid,'prepareGoogleLink',8,60*1000);
  return idempotent(uid,context.requestId,'prepareGoogleLink',async function(){
    const profile=(await db.ref(`users/${uid}`).get()).val();
    if(!profile)throw httpError(404,'profile-not-found','Player profile does not exist.');
    const at=now(),attemptId=linkAttemptId(uid,context.requestId);
    const linked=await authUserHasProvider(uid,token,GOOGLE_PROVIDER_ID);
    const assessment=await accountSwitchAssessment(uid,profile);
    const transaction=await transactExistingPlayer(uid,function(current){
      const security=current.accountSecurity||{},google=security.google||{};
      if(linked){
        security.google={provider:GOOGLE_PROVIDER_ID,status:'linked',linkedAt:safeInt(google.linkedAt,at)||at,lastVerifiedAt:at};
        current.accountSecurity=security;current.updatedAt=at;
        return {commit:true,alreadyLinked:true};
      }
      if(google.status==='pending'&&safeInt(google.expiresAt,0)>at&&google.attemptId!==attemptId){
        return {commit:false,error:'account-link-in-progress'};
      }
      security.google={provider:GOOGLE_PROVIDER_ID,status:'pending',attemptId,startedAt:at,expiresAt:at+ACCOUNT_LINK_TTL_MS};
      current.accountSecurity=security;current.updatedAt=at;
      return {commit:true,alreadyLinked:false};
    });
    if(!transaction.committed&&transaction.decision.error)throw httpError(409,transaction.decision.error,'Another account-link attempt is already active.');
    if(!transaction.committed)throw httpError(409,'account-link-conflict','Account-link state changed.');
    await writeAccountAudit(uid,{type:linked?'google-link-verified':'google-link-started',attemptIdHash:hash(attemptId),at:ServerValue.TIMESTAMP});
    return Object.assign({ok:true,attemptId,alreadyLinked:linked,expiresAt:at+ACCOUNT_LINK_TTL_MS},assessment);
  });
}

async function completeGoogleLink(context){
  const {uid,token,body}=context;
  assertBodyKeys(body,['attemptId']);
  const attemptId=body.attemptId==null?'':strictString(body.attemptId,64,'invalid-link-attempt');
  if(attemptId&&!/^[a-f0-9]{32}$/.test(attemptId))throw httpError(400,'invalid-link-attempt','Account-link attempt is invalid.');
  await rateLimit(uid,'completeGoogleLink',12,60*1000);
  return idempotent(uid,context.requestId,'completeGoogleLink',async function(){
    if(!(await authUserHasProvider(uid,token,GOOGLE_PROVIDER_ID)))throw httpError(403,'google-provider-required','Google is not linked to this Firebase UID.');
    const at=now();
    const transaction=await transactExistingPlayer(uid,function(profile){
      const security=profile.accountSecurity||{},google=security.google||{};
      if(attemptId&&google.status==='pending'&&google.attemptId&&google.attemptId!==attemptId){
        return {commit:false,error:'account-link-attempt-mismatch'};
      }
      security.google={
        provider:GOOGLE_PROVIDER_ID,status:'linked',linkedAt:safeInt(google.linkedAt,at)||at,
        lastVerifiedAt:at,attemptIdHash:attemptId?hash(attemptId):google.attemptIdHash||null
      };
      profile.accountSecurity=security;profile.updatedAt=at;
      return {commit:true};
    });
    if(!transaction.committed&&transaction.decision.error)throw httpError(409,transaction.decision.error,'Account-link attempt does not match.');
    if(!transaction.committed)throw httpError(409,'account-link-conflict','Account-link state changed.');
    await writeAccountAudit(uid,{type:'google-link-completed',attemptIdHash:attemptId?hash(attemptId):null,at:ServerValue.TIMESTAMP});
    return {ok:true,linked:true,uid,state:authoritativeState(transaction.profile,at)};
  });
}

async function recordGoogleLinkConflict(context){
  const {uid,body}=context;
  assertBodyKeys(body,['attemptId','reason']);
  const attemptId=body.attemptId==null?'':strictString(body.attemptId,64,'invalid-link-attempt');
  if(attemptId&&!/^[a-f0-9]{32}$/.test(attemptId))throw httpError(400,'invalid-link-attempt','Account-link attempt is invalid.');
  const reason=body.reason==null?'credential-already-in-use':strictString(body.reason,80,'invalid-link-reason');
  if(!['credential-already-in-use','email-already-in-use','account-exists-with-different-credential'].includes(reason))throw httpError(400,'invalid-link-reason','Unsupported account-link conflict reason.');
  await rateLimit(uid,'recordGoogleLinkConflict',6,60*60*1000);
  return idempotent(uid,context.requestId,'recordGoogleLinkConflict',async function(){
    const profile=(await db.ref(`users/${uid}`).get()).val();
    if(!profile)throw httpError(404,'profile-not-found','Player profile does not exist.');
    const assessment=await accountSwitchAssessment(uid,profile),at=now();
    const ticketId=hash(`google-conflict:${uid}:${context.requestId}`).slice(0,20).toUpperCase();
    const supportCode='GL-'+ticketId.slice(0,10);
    const transaction=await transactExistingPlayer(uid,function(current){
      const security=current.accountSecurity||{},google=security.google||{};
      if(attemptId&&google.status==='pending'&&google.attemptId&&google.attemptId!==attemptId){
        return {commit:false,error:'account-link-attempt-mismatch'};
      }
      security.google={
        provider:GOOGLE_PROVIDER_ID,status:'conflict',attemptIdHash:attemptId?hash(attemptId):null,
        supportCode,conflictAt:at
      };
      current.accountSecurity=security;current.updatedAt=at;
      return {commit:true};
    });
    if(!transaction.committed&&transaction.decision.error)throw httpError(409,transaction.decision.error,'Account-link attempt does not match.');
    if(!transaction.committed)throw httpError(409,'account-link-conflict','Account-link state changed.');
    await writeAccountLinkTicket(uid,ticketId,{
      uid,provider:GOOGLE_PROVIDER_ID,status:'open',reason,
      hasProtectedProgress:assessment.hasProtectedProgress,
      hasPurchaseEntitlement:assessment.hasPurchaseEntitlement,
      hasActiveRankedMatch:assessment.hasActiveRankedMatch,
      createdAt:ServerValue.TIMESTAMP
    });
    await writeAccountAudit(uid,{type:'google-link-conflict',ticketIdHash:hash(ticketId),at:ServerValue.TIMESTAMP});
    return Object.assign({ok:true,ticketId,supportCode},assessment);
  });
}

function applyUsernameProfileChange(profile,uid,newUsername,at){
  const oldUsername=canonicalUsername(profile,uid),revision=usernameRevision(profile);
  if(oldUsername===newUsername){
    const repaired=profile.username!==newUsername||profile.name!==newUsername||safeInt(profile.usernameRevision,0)!==revision||profile.usernameGenerated===true;
    if(repaired){
      profile.username=newUsername;profile.name=newUsername;profile.usernameRevision=revision;profile.updatedAt=at;
      profile.usernameGenerated=false;
    }
    return {changed:false,repaired,idempotent:!repaired,oldUsername,newUsername,cost:0,previousBalance:safeInt(profile.gold,0),newBalance:safeInt(profile.gold,0)};
  }
  const previousChanges=safeInt(profile.usernameChanges,0);
  const initialChoice=profile.usernameGenerated===true;
  const cost=initialChoice||previousChanges===0?0:USERNAME_CHANGE_COST;
  const previousBalance=safeInt(profile.gold,0);
  if(previousBalance<cost)return {changed:false,idempotent:false,error:'insufficient-balance',oldUsername,newUsername,cost,previousBalance,newBalance:previousBalance};
  let transactionId=null;
  if(cost>0){
    const purchase=applySoftPurchase(profile,{
      uid,sourceType:'username_change',sourceId:String(previousChanges+1)+':'+newUsername,
      itemType:'username_change',itemId:newUsername,currency:'gold',price:cost,at,
      isOwned:function(){return false;},
      grant:function(){return {oldUsername,newUsername};}
    });
    if(purchase.error)return Object.assign({changed:false,oldUsername,newUsername,cost},purchase);
    transactionId=purchase.transactionId||null;
  }
  profile.username=newUsername;
  profile.name=newUsername;
  profile.usernameChanges=initialChoice?previousChanges:previousChanges+1;
  profile.usernameGenerated=false;
  profile.usernameRevision=revision+1;
  profile.usernameChangedAt=at;
  profile.updatedAt=at;
  return {
    changed:true,idempotent:false,oldUsername,newUsername,cost,transactionId,
    previousBalance,newBalance:safeInt(profile.gold,0),changeCount:profile.usernameChanges
  };
}

async function changeUsername(context){
  const {uid,body}=context;
  assertBodyKeys(body,['username']);
  const newUsername=normalizeUsername(body.username),validationError=usernameValidationError(body.username);
  if(validationError)throw httpError(400,validationError,validationError==='username-not-allowed'?'This username is reserved or not allowed.':'Username must contain 3-16 ASCII letters, digits or underscore.');
  await rateLimit(uid,'changeUsername',12,60*1000);
  assertCurrentLegalConsent(await requirePlayer(uid),uid);
  return idempotent(uid,context.requestId,'changeUsername:'+newUsername,async function(){
    return withUsernameLock(uid,async function(){
      await assertAccountOperationAllowed(uid,'changeUsername');
      const at=now();
      await reserveUsernameForUid(newUsername,uid);
      let result;
      try{
        result=await transactExistingPlayer(uid,function(profile){
          assertCurrentLegalConsent(profile,uid);
          const decision=applyUsernameProfileChange(profile,uid,newUsername,at);
          if(decision.error)return Object.assign({commit:false},decision);
          if(decision.changed){
            decision.transitionId='un_'+hash([uid,decision.oldUsername,newUsername,decision.changeCount,at].join('|')).slice(0,40);
            profile.usernameTransition={
              id:decision.transitionId,oldUsername:decision.oldUsername||'',newUsername,cost:decision.cost,
              transactionId:decision.transactionId||'',changeCount:decision.changeCount,at
            };
          }
          return Object.assign({commit:decision.changed||decision.repaired},decision);
        });
      }catch(error){
        const latest=(await db.ref(`users/${uid}`).get()).val();
        if(!latest||canonicalUsername(latest,uid)!==newUsername)await releaseUsernameIfOwned(newUsername,uid).catch(function(){});
        throw error;
      }
      if(result.decision.error){
        if(canonicalUsername(result.profile,uid)!==newUsername)await releaseUsernameIfOwned(newUsername,uid).catch(function(){});
        throw httpError(409,result.decision.error,result.decision.error==='insufficient-balance'?'Server balance is insufficient.':'Username could not be changed.');
      }
      const profile=result.profile;
      const transition=profile.usernameTransition&&profile.usernameTransition.newUsername===newUsername?profile.usernameTransition:null;
      await releaseOtherUsernameReservations(uid,newUsername);
      await publishPublicProfile(uid,profile,at);
      if(transition){
        await writeAccountAudit(uid,{
          type:'username-changed',oldUsername:transition.oldUsername||null,newUsername,cost:safeInt(transition.cost,0),
          transactionId:transition.transactionId||null,changeCount:safeInt(transition.changeCount,0),at:transition.at||ServerValue.TIMESTAMP
        },transition.id);
        await db.ref(`users/${uid}/usernameTransition`).transaction(function(value){return value&&value.id===transition.id?null:undefined;});
        delete profile.usernameTransition;
      }
      if(result.decision.changed)await getAuth().updateUser(uid,{displayName:newUsername}).catch(function(error){logger.warn('Auth display name sync failed',{uidHash:hash(uid).slice(0,16),error:String(error&&error.code||error)});});
      return {
        ok:true,changed:result.decision.changed===true,username:newUsername,cost:result.decision.cost||0,
        transactionId:result.decision.transactionId||null,state:authoritativeState(profile,at)
      };
    });
  });
}

function premiumAccess(profile,at){return membershipState(profile,at).active;}
function knownSelection(kind,id){
  if(kind==='skin')return id==='classic'||PAID_BY_KIND.skin&&PAID_BY_KIND.skin.has(id);
  if(kind==='piece_set'){
    const canonical=canonicalPieceSetId(id);
    return PIECE_SET_IDS.has(canonical);
  }
  if(kind==='frame')return id==='none'||['galaxy','phoenix','rainbow','premium','crown_elite'].includes(id)||PAID_BY_KIND.frame&&PAID_BY_KIND.frame.has(id);
  if(kind==='bio_frame')return id==='default'||['aurora','galaxy','premium'].includes(id)||PAID_BY_KIND.bio_frame&&PAID_BY_KIND.bio_frame.has(id);
  if(kind==='costume')return FREE_COSTUMES.has(id)||Object.prototype.hasOwnProperty.call(COSTUME_PRICES,id);
  if(kind==='emoji')return FREE_EMOJIS.has(id)||PAID_BY_KIND.emoji&&PAID_BY_KIND.emoji.has(id);
  return false;
}
function canonicalPieceSetId(id){return id==='luno'?'std':id;}
function ownsSelection(profile,kind,id,at){
  if(!knownSelection(kind,id))throw httpError(400,'unknown-selection','Cosmetic selection is unknown.');
  const inventory=serverInventory(profile);
  if(kind==='skin')return inventory.ownedSkins.includes(id);
  if(kind==='piece_set')return inventory.ownedSets.includes(canonicalPieceSetId(id));
  if(kind==='frame')return inventory.ownedFrames.includes(id)||['premium','crown_elite'].includes(id)&&premiumAccess(profile,at);
  if(kind==='bio_frame')return inventory.ownedBioFrames.includes(id)||id==='premium'&&premiumAccess(profile,at);
  if(kind==='costume')return FREE_COSTUMES.has(id)||inventory.ownedCostumes.includes(id)||PASS_COSTUMES.has(id)&&premiumAccess(profile,at);
  if(kind==='emoji')return FREE_EMOJIS.has(id)||inventory.ownedEmojis.includes(id);
  return false;
}
async function updateProfile(context){
  const {uid,body}=context;
  assertBodyKeys(body,['country','avatar','avatarEmoji','bio','dmFriendsOnly','frame','bioFrame','activeSkin','activePieceSet','activeCostumes']);
  const parsed={};
  if(Object.prototype.hasOwnProperty.call(body,'country')){
    parsed.country=strictString(body.country,2,'invalid-country');if(!COUNTRY_CODES.has(parsed.country))throw httpError(400,'invalid-country','Country is invalid.');
  }
  if(Object.prototype.hasOwnProperty.call(body,'avatar')){
    parsed.avatar=strictString(body.avatar,16,'invalid-avatar');if(!/^#[0-9a-f]{6}$/i.test(parsed.avatar))throw httpError(400,'invalid-avatar','Avatar color is invalid.');
  }
  if(Object.prototype.hasOwnProperty.call(body,'avatarEmoji')){
    parsed.avatarEmoji=strictString(body.avatarEmoji,32,'invalid-avatar');if(!AVATAR_IDS.has(parsed.avatarEmoji))throw httpError(400,'invalid-avatar','Avatar icon is invalid.');
  }
  if(Object.prototype.hasOwnProperty.call(body,'bio')){
    parsed.bio=normalizeUgcText(body.bio,BIO_MAX_LENGTH,{allowEmpty:true});
    if(parsed.bio===null)throw httpError(400,'invalid-bio','Biography contains invalid content.');
  }
  if(Object.prototype.hasOwnProperty.call(body,'dmFriendsOnly')){
    if(typeof body.dmFriendsOnly!=='boolean')throw httpError(400,'invalid-profile','Profile value is invalid.');parsed.dmFriendsOnly=body.dmFriendsOnly;
  }
  [['frame','frame'],['bioFrame','bio_frame'],['activeSkin','skin'],['activePieceSet','piece_set']].forEach(function(entry){
    if(!Object.prototype.hasOwnProperty.call(body,entry[0]))return;
    const id=strictString(body[entry[0]],64,'invalid-selection');
    const canonical=entry[1]==='piece_set'?canonicalPieceSetId(id):id;
    if(!knownSelection(entry[1],canonical))throw httpError(400,'unknown-selection','Cosmetic selection is unknown.');
    parsed[entry[0]]=canonical;
  });
  if(Object.prototype.hasOwnProperty.call(body,'activeCostumes')){
    const selections=assertPlainRecord(body.activeCostumes,'invalid-costumes'),active={};
    for(const pieceType of Object.keys(selections)){
      if(!Object.prototype.hasOwnProperty.call(COSTUME_TYPES,pieceType))throw httpError(400,'invalid-costumes','Costume selection is invalid.');
      const costume=strictString(selections[pieceType],64,'invalid-costumes');
      if(!knownSelection('costume',costume)||!costume.startsWith(COSTUME_TYPES[pieceType]))throw httpError(400,'invalid-costumes','Costume selection is invalid.');
      active[pieceType]=costume;
    }
    parsed.activeCostumes=active;
  }
  await rateLimit(uid,'updateProfile',20,60*1000);
  const at=now();
  const result=await transactExistingPlayer(uid,function(profile){
    if(parsed.bio)assertCurrentLegalConsent(profile,uid);
    if(Object.prototype.hasOwnProperty.call(parsed,'country'))profile.country=parsed.country;
    if(Object.prototype.hasOwnProperty.call(parsed,'avatar'))profile.avatar=parsed.avatar;
    if(Object.prototype.hasOwnProperty.call(parsed,'avatarEmoji'))profile.avatarEmoji=parsed.avatarEmoji;
    if(Object.prototype.hasOwnProperty.call(parsed,'bio'))profile.bio=parsed.bio;
    if(Object.prototype.hasOwnProperty.call(parsed,'dmFriendsOnly'))profile.dmFriendsOnly=parsed.dmFriendsOnly;
    if(parsed.frame&&!ownsSelection(profile,'frame',parsed.frame,at))return {commit:false,error:'locked-selection'};
    if(parsed.bioFrame&&!ownsSelection(profile,'bio_frame',parsed.bioFrame,at))return {commit:false,error:'locked-selection'};
    if(parsed.frame)profile.frame=parsed.frame;
    if(parsed.bioFrame)profile.bioFrame=parsed.bioFrame;
    const inventory=serverInventory(profile);
    if(parsed.activeSkin&&!ownsSelection(profile,'skin',parsed.activeSkin,at))return {commit:false,error:'locked-selection'};
    if(parsed.activePieceSet&&!ownsSelection(profile,'piece_set',parsed.activePieceSet,at))return {commit:false,error:'locked-selection'};
    if(parsed.activeSkin)inventory.activeSkin=parsed.activeSkin;
    if(parsed.activePieceSet)inventory.activePieceSet=parsed.activePieceSet;
    if(parsed.activeCostumes){
      for(const pieceType of Object.keys(parsed.activeCostumes))if(!ownsSelection(profile,'costume',parsed.activeCostumes[pieceType],at))return {commit:false,error:'locked-selection'};
      inventory.activeCostumes=parsed.activeCostumes;
    }
    profile.updatedAt=nextProfileUpdateTime(profile,at);
    return {commit:true};
  });
  if(result.decision.error)throw httpError(result.decision.error==='locked-selection'?403:400,result.decision.error,'Profile preference is invalid.');
  await publishPublicProfile(uid,result.profile,at);
  return {ok:true,state:authoritativeState(result.profile,at)};
}

function validateDeck(deck,current){
  if(!Array.isArray(deck)||deck.length!==6)throw httpError(400,'invalid-deck','Deck must contain exactly six cards.');
  const unlocked=current.unlockedCards||{};
  const result=[],seen=new Set();
  deck.forEach(function(value){
    const card=cleanString(value,64);
    const match=CARD_FAMILY_RE.exec(card),family=match&&match[1];
    const unlockedFamily=family&&(unlocked[family+'1']===true||unlocked[family]===true);
    const currentLevel=family?Math.max(1,Math.min(3,safeInt(current.cardLevel&&current.cardLevel[family],1))):0;
    const requestedLevel=family&&match[2]?Number(match[2]):currentLevel;
    const owned=family?unlockedFamily&&currentLevel>=requestedLevel:CARD_UNLOCK_CATALOG[card]&&unlocked[card]===true;
    const identity=family||card;
    if(!card||seen.has(identity)||!owned||family&&currentLevel<1)throw httpError(400,'invalid-deck','Deck contains a duplicate or locked card.');
    seen.add(identity);result.push(card);
  });
  // The server always plays the currently upgraded family level. A client may
  // submit either `trap` or a legacy `trap1`/`trap2` key, but it cannot force a
  // downgraded variant into a ranked or friendly match.
  return result.map(function(card){
    const match=CARD_FAMILY_RE.exec(card);
    return match?match[1]+Math.max(1,Math.min(3,safeInt(current.cardLevel&&current.cardLevel[match[1]],1))):card;
  });
}
function canonicalDeckForProfile(profile){
  try{return validateDeck(profile&&profile.deck,profile||{});}catch(_){/* repair below */}
  const unlocked=profile&&profile.unlockedCards&&typeof profile.unlockedCards==='object'?profile.unlockedCards:{};
  // Keep valid entries from the player's previous deck first, then fill the
  // remaining slots from the authoritative unlocked-card map. This repairs a
  // duplicate or truncated deck without silently reshuffling a healthy part
  // of the player's loadout.
  const previousDeck=profile&&Array.isArray(profile.deck)?profile.deck:[];
  const candidates=[...previousDeck,...Object.keys(unlocked).filter(function(key){return unlocked[key]===true;}),...STARTER_CARDS],result=[],seen=new Set();
  for(const raw of candidates){
    const rawKey=String(raw),match=CARD_FAMILY_RE.exec(rawKey),identity=match?match[1]:rawKey;
    const owned=match?unlocked[identity+'1']===true||unlocked[identity]===true:unlocked[rawKey]===true;
    if(!owned)continue;
    if(seen.has(identity))continue;
    const playable=match?identity+Math.max(1,Math.min(3,safeInt(profile&&profile.cardLevel&&profile.cardLevel[identity],1))):String(raw);
    if(!match&&!CARD_UNLOCK_CATALOG[playable])continue;
    seen.add(identity);result.push(playable);
    if(result.length===6)break;
  }
  if(result.length!==6)return [];
  try{return validateDeck(result,profile||{});}catch(_){return [];}
}
function validRankedMatchId(value){return /^rm_[a-f0-9]{32}$/.test(String(value||''));}
function validServerMatchId(value){return /^(?:rm|fm)_[a-f0-9]{32}$/.test(String(value||''));}
function rankedMatchId(uid,id){return 'rm_'+hash(['ranked',uid,id].join('|')).slice(0,32);}
function friendlyMatchId(uid,targetUid,id){return 'fm_'+hash('friendly|'+[uid,targetUid].sort().join('|')+'|'+id).slice(0,32);}
function rankedOutcome(match,color){
  if(match.result&&match.result.type==='cancelled')return 'cancelled';
  if(!match.result||match.result.winner==='draw')return 'draw';
  return match.result.winner===color?'win':'loss';
}
function queueRange(entry,at){return Math.min(2000,200+Math.floor(Math.max(0,at-safeInt(entry&&entry.joinedAt,at))/(15*1000))*200);}
async function publishRankedMatch(match,publishPlayerStatus=true){
  match=hydrateMatch(match);const updates={};
  for(const uid of Object.keys(match.participants||{})){
    const view=sanitizeMatchView(match,uid);
    updates[`rankedMatchViews/${uid}/${match.matchId}`]=view;
    if(publishPlayerStatus)updates[`rankedPlayers/${uid}`]={
      status:match.status==='active'?'active':match.status,matchId:match.matchId,mode:match.mode||'ranked',color:match.colors[uid],
      opponentUid:match.players[match.colors[uid]==='W'?'B':'W'].uid,updatedAt:ServerValue.TIMESTAMP
    };
  }
  await db.ref().update(updates);
}
async function settleRankedMatch(matchId){
  if(!validServerMatchId(matchId))throw httpError(400,'invalid-match-id','Server match id is invalid.');
  let match=hydrateMatch((await db.ref(`rankedState/matches/${matchId}`).get()).val());
  if(!match||!match.result)return match;
  const mode=match.mode==='friendly'?'friendly':'ranked',settlements={};
  for(const color of ['W','B']){
    const player=match.players[color],opponent=match.players[color==='W'?'B':'W'],uid=player.uid,outcome=rankedOutcome(match,color);
    if(mode==='friendly'){
      settlements[color]={applied:false,idempotent:true,mode:'friendly',outcome,trophyDelta:0,gold:0,levelGold:0,xp:0};
      continue;
    }
    const transaction=await transactExistingPlayer(uid,function(profile){
      const settlement=applyRankedSettlement(profile,{
        uid,matchId,outcome,opponentTrophies:opponent.trophies,moveCount:match.moveCount,
        metrics:Object.assign({moveCount:match.moveCount},match.metrics[color]||{}),at:safeInt(match.result.finishedAt,now())
      });
      return {commit:settlement.applied===true,settlement};
    });
    settlements[color]=transaction.decision.settlement||match.settlement&&match.settlement[color]||null;
  }
  match.settlement=Object.assign({},match.settlement||{},settlements);
  const updates={};
  updates[`rankedState/matches/${matchId}/settlement`]=match.settlement;
  for(const color of ['W','B']){
    const uid=match.players[color].uid,outcome=rankedOutcome(match,color),opponent=match.players[color==='W'?'B':'W'];
    updates[`matchHistory/${uid}/${matchId}`]={
      matchId,mode,outcome,opponent:{uid:opponent.uid,name:opponent.name,trophies:opponent.trophies},
      result:match.result,moveCount:match.moveCount,createdAt:match.createdAt,finishedAt:match.result.finishedAt,settlement:settlements[color]
    };
    updates[`rankedReplays/${uid}/${matchId}`]=sanitizeMatchReplay(match,uid);
    updates[`rankedState/pendingSettlementsByUser/${uid}/${matchId}`]=true;
  }
  await db.ref().update(updates);
  for(const color of ['W','B']){
    const uid=match.players[color].uid,opponent=match.players[color==='W'?'B':'W'];
    await settlePlayerPresence(db,uid,matchId,{status:match.status,matchId,mode,color,opponentUid:opponent.uid,updatedAt:ServerValue.TIMESTAMP});
  }
  await publishRankedMatch(match,false);
  // Readers must retry until presence cleanup and result publication succeed.
  match.settlementStatus='complete';match.settledAt=now();
  const completion={
    [`rankedState/matches/${matchId}/settlementStatus`]:'complete',
    [`rankedState/matches/${matchId}/settledAt`]:match.settledAt,
  };
  for(const color of ['W','B'])completion[`rankedState/pendingSettlementsByUser/${match.players[color].uid}/${matchId}`]=null;
  await db.ref().update(completion);
  return match;
}
async function enqueueRanked(context){
  await battleV1.assertLegacyNewAllowed(context.req?.get('X-Luno-Platform')==='ios'?'ios':'android');
  const {uid,body}=context;assertBodyKeys(body,[]);await rateLimit(uid,'enqueueRanked',30,60*1000);
  const profile=await requirePlayer(uid),deck=canonicalDeckForProfile(profile),at=now(),newMatchId=rankedMatchId(uid,context.requestId);
  if(deck.length!==6)throw httpError(409,'invalid-deck','A valid six-card deck is required before matchmaking.');
  if(await hasOpenFriendlyRoom(uid,at))throw httpError(409,'friendly-room-active','Cancel the open friendly room before ranked matchmaking.');
  const stateRef=db.ref('rankedState');let activeConflict=false;
  const transaction=await stateRef.transaction(function(value){
    value=value&&typeof value==='object'?value:{};value.queue=value.queue&&typeof value.queue==='object'?value.queue:{};
    value.matches=value.matches&&typeof value.matches==='object'?value.matches:{};value.activeByUser=value.activeByUser&&typeof value.activeByUser==='object'?value.activeByUser:{};
    const existingId=value.activeByUser[uid],existing=existingId&&value.matches[existingId];
    if(existing&&existing.status==='active'&&!existing.result){
      if(existingId===newMatchId)return value;
      activeConflict=true;return;
    }
    if(existingId)delete value.activeByUser[uid];
    Object.keys(value.queue).forEach(function(queuedUid){
      const item=value.queue[queuedUid];if(!item||at-safeInt(item.lastSeenAt||item.joinedAt,0)>RANKED_QUEUE_TTL_MS)delete value.queue[queuedUid];
    });
    const current=value.queue[uid],entry={uid,joinedAt:current?safeInt(current.joinedAt,at):at,lastSeenAt:at,player:profileSummary(profile,uid),deck};
    const candidates=Object.keys(value.queue).filter(function(candidateUid){
      if(candidateUid===uid)return false;const candidate=value.queue[candidateUid];if(!candidate||!candidate.player||!Array.isArray(candidate.deck)||candidate.deck.length!==6)return false;
      const difference=Math.abs(safeInt(candidate.player.trophies,0)-safeInt(entry.player.trophies,0));return difference<=Math.max(queueRange(entry,at),queueRange(candidate,at));
    }).sort(function(first,second){
      const a=value.queue[first],b=value.queue[second],diffA=Math.abs(safeInt(a.player.trophies,0)-safeInt(entry.player.trophies,0)),diffB=Math.abs(safeInt(b.player.trophies,0)-safeInt(entry.player.trophies,0));
      return diffA-diffB||safeInt(a.joinedAt,0)-safeInt(b.joinedAt,0)||first.localeCompare(second);
    });
    if(!candidates.length){value.queue[uid]=entry;return value;}
    const opponentUid=candidates[0],opponent=value.queue[opponentUid];delete value.queue[uid];delete value.queue[opponentUid];
    const uidIsWhite=parseInt(hash(newMatchId+'|color').slice(0,2),16)%2===0;
    const white=uidIsWhite?entry:opponent,black=uidIsWhite?opponent:entry;
    value.matches[newMatchId]=createMatchState({
      matchId:newMatchId,at,
      white:{uid:white.uid,profile:white.player,deck:white.deck},
      black:{uid:black.uid,profile:black.player,deck:black.deck}
    });
    value.activeByUser[uid]=newMatchId;value.activeByUser[opponentUid]=newMatchId;
    return value;
  });
  if(activeConflict)throw httpError(409,'match-already-active','A ranked match is already active for this player.');
  if(!transaction.committed)throw httpError(409,'matchmaking-conflict','Ranked queue changed before it could be saved.');
  const rankedState=transaction.snapshot.val()||{},matchId=rankedState.activeByUser&&rankedState.activeByUser[uid],match=matchId&&rankedState.matches&&rankedState.matches[matchId];
  if(match){await publishRankedMatch(match);return {ok:true,status:'matched',matchId,view:sanitizeMatchView(match,uid)};}
  await db.ref(`rankedPlayers/${uid}`).set({status:'queued',queuedAt:at,updatedAt:ServerValue.TIMESTAMP});
  return {ok:true,status:'queued',queuedAt:at};
}
async function cancelRankedQueue(context){
  const {uid,body}=context;assertBodyKeys(body,[]);await rateLimit(uid,'cancelRankedQueue',20,60*1000);
  const stateRef=db.ref('rankedState');let activeMatch=false;
  const transaction=await stateRef.transaction(function(value){
    value=value&&typeof value==='object'?value:{};value.queue=value.queue&&typeof value.queue==='object'?value.queue:{};
    value.matches=value.matches&&typeof value.matches==='object'?value.matches:{};value.activeByUser=value.activeByUser&&typeof value.activeByUser==='object'?value.activeByUser:{};
    const activeId=cleanString(value.activeByUser[uid],80),match=activeId&&value.matches[activeId];
    if(match&&match.status==='active'&&!match.result){activeMatch=true;return;}
    if(activeId)delete value.activeByUser[uid];
    delete value.queue[uid];
    return value;
  });
  if(activeMatch)throw httpError(409,'match-already-active','A ranked match is already active.');
  if(!transaction.committed)throw httpError(409,'matchmaking-conflict','Ranked queue changed before it could be cancelled.');
  await db.ref(`rankedPlayers/${uid}`).set({status:'idle',updatedAt:ServerValue.TIMESTAMP});
  return {ok:true,status:'idle'};
}
async function getRankedMatch(context){
  if(String(context.body?.matchId||'').startsWith('bv1_'))throw httpError(400,'INCOMPATIBLE_PROTOCOL','Use the V1 match endpoint.');
  const {uid,body}=context;assertBodyKeys(body,['matchId']);await rateLimit(uid,'getRankedMatch',120,60*1000);
  let matchId=cleanString(body.matchId,40);
  if(!matchId){
    const activeId=cleanString((await db.ref(`rankedState/activeByUser/${uid}`).get()).val(),40);
    if(activeId){
      matchId=activeId;
    }
  }
  if(!matchId){
    const queueRef=db.ref(`rankedState/queue/${uid}`),at=now();let queueDecision='idle';
    const queueTransaction=await queueRef.transaction(function(value){
      if(!value){queueDecision='idle';return value===null?null:undefined;}
      const seen=safeInt(value.lastSeenAt||value.joinedAt,0);
      if(!seen||at-seen>RANKED_QUEUE_TTL_MS){queueDecision='expired';return null;}
      // Polling is the queue heartbeat. Keep a live search alive while the
      // player is still on the matchmaking screen, but let an abandoned queue
      // expire when the app stops polling.
      value.lastSeenAt=at;queueDecision='queued';return value;
    },undefined,false);
    if(queueDecision==='queued'&&queueTransaction.snapshot.exists())return {ok:true,status:'queued',matchId:null};
    if(queueDecision==='expired'&&queueTransaction.committed)await db.ref(`rankedPlayers/${uid}`).set({status:'idle',updatedAt:ServerValue.TIMESTAMP});
  }
  if(!validServerMatchId(matchId))return {ok:true,status:'idle',matchId:null};
  const matchRef=db.ref(`rankedState/matches/${matchId}`),initialMatch=(await matchRef.get()).val();
  let match=hydrateMatch(initialMatch);
  if(!match||!match.participants||match.participants[uid]!==true)throw httpError(404,'match-not-found','Ranked match was not found for this player.');
  // Reads also close an expired clock or reconnect window. The scheduled
  // sweeper remains the backstop, while a resumed client gets a current result
  // immediately instead of rendering a stale active board.
  const at=now(),presence=match.presence||{},needsSweep=match.status==='active'&&!match.result&&(
    safeInt(match.clock&&match.clock.deadlineAt,0)<=at||
    Object.keys(match.participants||{}).some(function(playerUid){return at-safeInt(presence[playerUid]&&presence[playerUid].lastSeenAt,match.createdAt)>HEARTBEAT_STALE_MS;})
  );
  if(needsSweep){
    const transaction=await matchRef.transaction(function(value){
      if(!value||value.status!=='active'||value.result)return value;
      return sweepRankedState(value,now());
    },undefined,false);
    match=hydrateMatch(transaction.committed?transaction.snapshot.val():(await matchRef.get()).val());
  }
  if(!match||match.participants?.[uid]!==true)throw httpError(404,'match-not-found','Ranked match was not found for this player.');
  if(match.result&&match.settlementStatus!=='complete')match=await settleRankedMatch(matchId);
  const result={ok:true,status:match.status,matchId,view:sanitizeMatchView(match,uid)};
  if(match.result)result.state=authoritativeState(await requirePlayer(uid),now());
  return result;
}
async function submitMatchAction(context){
  if(String(context.body?.matchId||'').startsWith('bv1_'))throw httpError(400,'INCOMPATIBLE_PROTOCOL','Use the V1 action endpoint.');
  const {uid,body}=context;
  assertBodyKeys(body,['matchId','type','actionId','expectedSequence','from','to','promotion','cardKey','target','secondaryTarget']);
  const matchId=cleanString(body.matchId,40);if(!validServerMatchId(matchId))throw httpError(400,'invalid-match-id','Server match id is invalid.');
  await rateLimit(uid,'submitMatchAction',180,60*1000);
  const action={};for(const key of ['type','actionId','expectedSequence','from','to','promotion','cardKey','target','secondaryTarget'])if(Object.prototype.hasOwnProperty.call(body,key))action[key]=body[key];
  const ref=db.ref(`rankedState/matches/${matchId}`),initial=(await ref.get()).val();if(!initial)throw httpError(404,'match-not-found','Ranked match does not exist.');
  let decision=null,actionError=null;
  const transaction=await ref.transaction(function(value){
    decision=null;actionError=null;
    // A null cache must probe the server, never restore the pre-read match.
    if(value===null)return null;
    if(!value)return;
    try{decision=applyRankedAction(value,uid,action,now());actionError=null;return decision.state;}
    catch(error){actionError=error;return;}
  },undefined,false);
  if(!transaction.committed){
    if(actionError)throw httpError(['stale-sequence','match-finished'].includes(actionError.code)?409:400,actionError.code||'invalid-action',actionError.message);
    throw httpError(409,'match-action-conflict','Ranked action conflicted with another action.');
  }
  let match=hydrateMatch(transaction.snapshot.val());
  if(!match)throw httpError(404,'match-not-found','Ranked match does not exist.');
  if(match.result)match=await settleRankedMatch(matchId);else await publishRankedMatch(match);
  const response={ok:true,idempotent:decision&&decision.idempotent===true,matchId,view:sanitizeMatchView(match,uid)};
  if(match.result)response.state=authoritativeState(await requirePlayer(uid),now());
  return response;
}
async function heartbeatRankedMatch(context){
  if(String(context.body?.matchId||'').startsWith('bv1_'))throw httpError(400,'INCOMPATIBLE_PROTOCOL','Use the V1 match endpoint.');
  const {uid,body}=context;assertBodyKeys(body,['matchId']);const matchId=cleanString(body.matchId,40);
  if(!validServerMatchId(matchId))throw httpError(400,'invalid-match-id','Server match id is invalid.');
  await rateLimit(uid,'heartbeatRankedMatch',12,60*1000);
  const ref=db.ref(`rankedState/matches/${matchId}`),initial=(await ref.get()).val();if(!initial)throw httpError(404,'match-not-found','Ranked match does not exist.');
  let heartbeatError=null;
  const transaction=await ref.transaction(function(value){
    heartbeatError=null;
    if(value===null)return null;
    if(!value)return;
    try{heartbeatError=null;return heartbeatRankedState(value,uid,now());}catch(error){heartbeatError=error;return;}
  },undefined,false);
  if(!transaction.committed){if(heartbeatError)throw httpError(403,heartbeatError.code||'heartbeat-rejected',heartbeatError.message);throw httpError(409,'heartbeat-conflict','Heartbeat conflicted with another update.');}
  let match=hydrateMatch(transaction.snapshot.val());
  if(!match)throw httpError(404,'match-not-found','Ranked match does not exist.');
  if(match.result)match=await settleRankedMatch(matchId);else await publishRankedMatch(match);
  return {ok:true,status:match.status,matchId,view:sanitizeMatchView(match,uid)};
}
async function enforceRankedChatCooldown(matchId,uid,at){
  const ref=db.ref(`rankedState/chatThrottle/${matchId}/${uid}`);
  const result=await ref.transaction(function(value){
    const last=safeInt(value,0);
    return last&&at-last<RANKED_CHAT_COOLDOWN_MS?undefined:at;
  });
  if(!result.committed)throw httpError(429,'chat-rate-limited','Ranked chat is being used too quickly.');
}
async function sendRankedMessage(context){
  if(String(context.body?.matchId||'').startsWith('bv1_'))throw httpError(400,'INCOMPATIBLE_PROTOCOL','Use the V1 protocol.');
  const {uid,body}=context;
  assertBodyKeys(body,['matchId','kind','id','tab']);
  const matchId=cleanString(body.matchId,40),kind=strictString(body.kind,16,'invalid-chat-kind'),id=strictString(body.id,64,'invalid-chat-id');
  if(!validServerMatchId(matchId))throw httpError(400,'invalid-match-id','Server match id is invalid.');
  if(kind!=='preset'&&kind!=='emoji')throw httpError(400,'invalid-chat-kind','Ranked chat kind is invalid.');
  let tab=kind==='emoji'?'emojis':strictString(body.tab,16,'invalid-chat-tab');
  if(kind==='preset'&&(!RANKED_CHAT_PRESETS[tab]||!RANKED_CHAT_PRESETS[tab].has(id)))throw httpError(400,'invalid-chat-preset','Ranked chat preset is invalid.');
  await rateLimit(uid,'sendRankedMessage',24,60*1000);
  const operation=['sendRankedMessage',matchId,kind,tab,id].join(':');
  return idempotent(uid,context.requestId,operation,async function(){
    const at=now();
    const initial=(await db.ref(`rankedState/matches/${matchId}`).get()).val();
    const initialMatch=hydrateMatch(initial);
    if(!initialMatch||!initialMatch.participants||initialMatch.participants[uid]!==true)throw httpError(404,'match-not-found','Ranked match was not found for this player.');
    if(kind==='emoji'){
      const profile=await requirePlayer(uid);
      if(!ownsSelection(profile,'emoji',id,at))throw httpError(403,'emoji-not-owned','Ranked emoji is not owned by this player.');
    }
    await enforceRankedChatCooldown(matchId,uid,at);
    // Chat must observe the same clock and reconnect lease as gameplay. A
    // stale message must never keep a timed-out or abandoned match alive.
    const ref=db.ref(`rankedState/matches/${matchId}`);let heartbeatError=null;
    const transaction=await ref.transaction(function(value){
      heartbeatError=null;
      if(value===null)return null;
      if(!value)return;
      try{return heartbeatRankedState(value,uid,now());}
      catch(error){heartbeatError=error;return;}
    },undefined,false);
    if(!transaction.committed){
      if(heartbeatError)throw httpError(heartbeatError.code==='not-a-participant'?404:409,heartbeatError.code||'match-sync-failed',heartbeatError.message);
      throw httpError(409,'match-sync-conflict','Match state changed before the message could be sent.');
    }
    let match=hydrateMatch(transaction.snapshot.val());
    if(!match)throw httpError(404,'match-not-found','Ranked match does not exist.');
    if(match.result){await settleRankedMatch(matchId);throw httpError(409,'match-finished','Ranked match has already finished.');}
    await publishRankedMatch(match);
    const color=match.colors&&match.colors[uid];
    if(color!=='W'&&color!=='B')throw httpError(403,'match-member-required','Player is not a ranked match member.');
    const message={messageId:'rc_'+hash(uid+'|'+context.requestId).slice(0,32),matchId,fromUid:uid,fromColor:color,kind,id,tab,ts:at};
    const updates={};
    for(const participantUid of Object.keys(match.participants))updates[`rankedMessages/${participantUid}/${matchId}`]=message;
    await db.ref().update(updates);
    return {ok:true,message};
  });
}
async function sweepRankedMatchesJob(){
  const cursorRef=db.ref('rankedMaintenance/settlementCursor');
  const savedCursor=(await cursorRef.get()).val();
  const cursor=validServerMatchId(savedCursor)?savedCursor:'';
  let pendingQuery=db.ref('rankedState/matches').orderByChild('settlementStatus');
  pendingQuery=cursor?pendingQuery.startAt('pending',cursor).endAt('pending'):pendingQuery.equalTo('pending');
  const pendingSnapshot=await pendingQuery.limitToFirst(RANKED_SWEEP_LIMIT+1).get();
  const pendingIds=Object.keys(pendingSnapshot.val()||{}).sort().filter(id=>id!==cursor).slice(0,RANKED_SWEEP_LIMIT);
  let recovered=0,recoveryFailed=0;
  for(const matchId of pendingIds){
    if(!validServerMatchId(matchId))continue;
    try{
      const result=await settleRankedMatch(matchId);
      if(result&&result.settlementStatus==='complete')recovered++;
    }catch(error){
      recoveryFailed++;
      logger.error('Pending ranked settlement failed',{matchId,code:error.code||'unknown'});
    }
  }
  // Advance past failures too, so one bad batch cannot starve later matches.
  await cursorRef.set(pendingIds.length?pendingIds[pendingIds.length-1]:null);
  const snapshot=await db.ref('rankedState/matches').orderByChild('status').equalTo('active').limitToFirst(RANKED_SWEEP_LIMIT).get();
  const candidates=snapshot.val()||{};let scanned=0,settled=0,published=0;
  for(const matchId of Object.keys(candidates)){
    if(!validServerMatchId(matchId))continue;scanned++;
    const ref=db.ref(`rankedState/matches/${matchId}`);
    const transaction=await ref.transaction(function(value){
      if(value===null)return null;
      if(!value||value.status!=='active'||value.result)return;
      return sweepRankedState(value,now());
    },undefined,false);
    if(!transaction.committed)continue;
    const match=hydrateMatch(transaction.snapshot.val());
    if(!match)continue;
    if(match.result){await settleRankedMatch(matchId);settled++;}
    else{await publishRankedMatch(match);published++;}
  }
  logger.info('Ranked sweep complete',{scanned,settled,published,recovered,recoveryFailed});
  return {scanned,settled,published,recovered,recoveryFailed};
}
async function leaveRankedBeforeDeletion(uid){
  const activeId=cleanString((await db.ref(`rankedState/activeByUser/${uid}`).get()).val(),40);
  const pending=(await db.ref(`rankedState/pendingSettlementsByUser/${uid}`).get()).val()||{};
  const matchIds=new Set(Object.keys(pending));
  if(validServerMatchId(activeId))matchIds.add(activeId);
  for(const activeMatchId of matchIds){
    if(!validServerMatchId(activeMatchId))throw httpError(409,'pending-settlement-invalid','Pending match reference requires review.');
    const ref=db.ref(`rankedState/matches/${activeMatchId}`),initial=(await ref.get()).val();
    if(pending[activeMatchId]&&(!initial||initial.participants?.[uid]!==true)){
      throw httpError(409,'pending-settlement-missing','Pending match requires review before account deletion.');
    }
    if(initial&&initial.participants&&initial.participants[uid]===true){
      let finalMatch=initial;
      if(initial.status==='active'&&!initial.result){
        const actionId='account-delete-'+hash(uid+'|'+activeMatchId).slice(0,32);
        const transaction=await ref.transaction(function(value){
          if(value===null)return null;
          if(!value||value.status!=='active'||value.result||!value.participants||value.participants[uid]!==true)return;
          return applyRankedAction(value,uid,{type:'resign',actionId,expectedSequence:safeInt(value.sequence,0)},now()).state;
        },undefined,false);
        finalMatch=transaction.committed?transaction.snapshot.val():(await ref.get()).val();
      }
      if(finalMatch&&finalMatch.result&&finalMatch.settlementStatus!=='complete')await settleRankedMatch(activeMatchId);
    }
  }
  await db.ref(`rankedState/queue/${uid}`).remove();
}
async function updatePreferences(context){
  const {uid,body}=context;
  assertBodyKeys(body,['deck','emojiLoadout']);
  let parsedLoadout=null;
  if(Object.prototype.hasOwnProperty.call(body,'emojiLoadout')){
    if(!Array.isArray(body.emojiLoadout)||body.emojiLoadout.length>4)throw httpError(400,'invalid-emoji-loadout','Emoji loadout is invalid.');
    parsedLoadout=[];const seen=new Set();
    for(const value of body.emojiLoadout){
      const emoji=strictString(value,64,'invalid-emoji-loadout');
      if(!knownSelection('emoji',emoji)||seen.has(emoji))throw httpError(400,'invalid-emoji-loadout','Emoji loadout is invalid.');
      seen.add(emoji);parsedLoadout.push(emoji);
    }
  }
  await rateLimit(uid,'updatePreferences',30,60*1000);
  const at=now();
  const result=await transactExistingPlayer(uid,function(profile){
    if(Object.prototype.hasOwnProperty.call(body,'deck')){
      try{profile.deck=validateDeck(body.deck,profile);}catch(error){return {commit:false,error:error&&error.code||'invalid-deck'};}
    }
    if(parsedLoadout&&parsedLoadout.some(function(emoji){return !ownsSelection(profile,'emoji',emoji,at);}))return {commit:false,error:'locked-selection'};
    if(parsedLoadout)profile.emojiLoadout=parsedLoadout;
    profile.updatedAt=at;return {commit:true};
  });
  if(result.decision.error)throw httpError(result.decision.error==='locked-selection'?403:400,result.decision.error,'Preference is invalid.');
  return {ok:true,state:authoritativeState(result.profile,at)};
}

function validUid(value){return /^[A-Za-z0-9_-]{6,128}$/.test(String(value||''));}
function conversationId(first,second){return [String(first),String(second)].sort().join('_');}
async function requirePlayer(uid){
  const profile=(await db.ref(`users/${uid}`).get()).val();
  if(!profile)throw httpError(404,'profile-not-found','Player profile does not exist.');
  return profile;
}
function legalConsentState(profile){
  const consent=profile&&profile.legalConsent&&typeof profile.legalConsent==='object'?profile.legalConsent:{};
  const acceptedAt=safeInt(consent.acceptedAt,0);
  const accepted=!!(
    profile&&validUid(profile.uid)&&consent.uid===profile.uid&&acceptedAt>0&&
    consent.termsVersion===LEGAL_TERMS_VERSION&&consent.privacyVersion===LEGAL_PRIVACY_VERSION&&
    consent.communityVersion===LEGAL_COMMUNITY_VERSION
  );
  return {
    uid:profile&&typeof profile.uid==='string'?profile.uid:'',
    accepted,
    acceptedAt:accepted?acceptedAt:0,
    termsVersion:LEGAL_TERMS_VERSION,
    privacyVersion:LEGAL_PRIVACY_VERSION,
    communityVersion:LEGAL_COMMUNITY_VERSION
  };
}
function assertCurrentLegalConsent(profile,uid){
  const consent=legalConsentState(profile);
  if(!profile||profile.uid!==uid||!consent.accepted){
    throw httpError(403,'legal-consent-required','Current Terms, Privacy and Community Guidelines consent is required before publishing user content.');
  }
  return consent;
}
function seasonState(profile,at){
  profile=productProgressProfile(profile,at);
  const periods=periodSnapshot(at),currentSeason=safeInt(periods.seasonNumber,1),record=profile&&profile.serverSeason&&typeof profile.serverSeason==='object'&&!Array.isArray(profile.serverSeason)?profile.serverSeason:{},rawNumber=Number(record.number),storedSeason=Number.isSafeInteger(rawNumber)&&rawNumber>0?rawNumber:currentSeason,seasonNumber=Math.min(storedSeason,currentSeason),active=storedSeason===currentSeason,ended=storedSeason<currentSeason,score=active||ended?safeInt(record.peakTrophies,0):0,claims=record.claimed&&typeof record.claimed==='object'&&!Array.isArray(record.claimed)?record.claimed:{},economyClaims=profile&&profile.serverEconomy&&profile.serverEconomy.claims&&typeof profile.serverEconomy.claims==='object'?profile.serverEconomy.claims:{},uid=profile&&typeof profile.uid==='string'?profile.uid:'',bounds=seasonBounds(seasonNumber);
  const nextIndex=SEASON_PATH_REWARDS.findIndex(function(tier){return score<tier.minTrophies;});
  const currentIndex=nextIndex<0?SEASON_PATH_REWARDS.length-1:nextIndex;
  const nextTier=nextIndex<0?null:SEASON_PATH_REWARDS[nextIndex],currentTier=SEASON_PATH_REWARDS[currentIndex]||null;
  const lowerBound=nextIndex<=0?0:SEASON_PATH_REWARDS[nextIndex-1].minTrophies,target=nextTier?nextTier.minTrophies:lowerBound;
  function tierClaimed(tierId){
    const sourceId=['s'+seasonNumber,tierId].join(':');
    return (claims[tierId]!==undefined&&claims[tierId]!==null)||Object.prototype.hasOwnProperty.call(economyClaims,sourceClaimKey(uid,'season_path_reward',sourceId));
  }
  return {
    seasonId:'s'+seasonNumber,seasonNumber,status:active?'active':ended?'ended':'syncing',serverTime:Number(at),seasonStartAt:bounds.startAt,seasonEndAt:bounds.endAt,
    currentSeasonId:periods.seasonId,currentSeasonNumber:currentSeason,score,
    currentTierId:currentTier&&currentTier.id||null,nextTierId:nextTier&&nextTier.id||null,nextTrophies:nextTier?nextTier.minTrophies:null,
    progress:target<=lowerBound?1:Math.max(0,Math.min(1,(score-lowerBound)/(target-lowerBound))),claimableCount:SEASON_PATH_REWARDS.filter(function(tier){return active&&score>=tier.minTrophies&&!tierClaimed(tier.id);}).length,
    path:SEASON_PATH_REWARDS.map(function(tier,index){
      const claimed=tierClaimed(tier.id),unlocked=score>=tier.minTrophies;
      return {id:tier.id,title:tier.title,minTrophies:tier.minTrophies,reward:Object.assign({},tier.reward),state:claimed?'claimed':unlocked?'claimable':index===currentIndex?'current':'locked',claimed,unlocked,canClaim:active&&unlocked&&!claimed,isCurrent:index===currentIndex};
    }),
    endReward:(function(){const tier=seasonTier(score);return {tier:tier.tier,reward:Object.assign({},tier.reward)};})(),
    canClaimEndReward:storedSeason<currentSeason
  };
}
function authoritativeState(profile,at,external){
  // Derived entitlements must describe delivery time, not an old request start.
  at=Math.max(at,now());
  const inventory=serverInventory(profile);
  const pass=syncServerPass(profile,at).pass;
  const username=canonicalUsername(profile,profile&&profile.uid);
  return {
    uid:cleanString(profile.uid,128),
    stateRevision:playerStateRevision(profile),
    stateObservedAt:at,
    gold:Number(profile.gold||0),
    gems:Number(profile.gems||0),
    trophies:safeInt(profile.trophies,0),
    arenaIdx:arenaIndexForProfile(profile),
    collectionScore:collectionScoreForProfile(profile),
    xp:Number(profile.xp||0),
    lvl:Number(profile.lvl||1),
    premiumUntil:Number(profile.premiumUntil||0),
    membership:membershipState(profile,at),
    profile:{
      name:username,username,
      usernameRevision:usernameRevision(profile),
      playerCode:cleanString(profile.playerCode||playerCode(profile.uid),13),
      usernameChanges:safeInt(profile.usernameChanges,0),usernameChangedAt:safeInt(profile.usernameChangedAt,0),
      usernameGenerated:profile.usernameGenerated===true,
      country:cleanString(profile.country||'TR',2),avatar:cleanString(profile.avatar||'#e8b840',16),
      avatarEmoji:cleanString(profile.avatarEmoji||'&#9818;',32),bio:safePublicBio(profile.bio),
      frame:cleanString(profile.frame||'none',64),bioFrame:cleanString(profile.bioFrame||'default',64),
      dmFriendsOnly:profile.dmFriendsOnly===true
    },
    deck:canonicalDeckForProfile(profile),
    emojiLoadout:Array.isArray(profile.emojiLoadout)?profile.emojiLoadout:[],
    unlockedCards:profile.unlockedCards||{},
    cardLevel:profile.cardLevel||{},
    inventory,
    shopChests:Object.fromEntries(Object.keys(CHEST_CATALOG).map(id=>[id,chestAvailability(profile,id)])),
    missions:profile.missions||{},
    passState:pass,
    passMissions:profile.passMissions||{},
    season:seasonState(profile,at),
    achievementsClaimed:profile.achievementsClaimed||{},
    stats:profile.stats||{},
    legalConsent:legalConsentState(profile),
    economy:economySnapshot(profile,at),
    rewards:rewardSchedule(profile,at,external||{})
  };
}
async function getPlayerState(context){
  await rateLimit(context.uid,'getPlayerState',60,60*1000);
  const at=now();
  await reconcileUsernameState(context.uid);
  const result=await transactExistingPlayer(context.uid,function(profile){
    if(isIncompleteGuestProfile(profile))return {commit:false,error:'profile-not-found'};
    let changed=normalizeLoginActivity(profile,at);
    const productChanged=normalizeProductEntitlements(profile);
    if(productChanged)changed=true;
    const membershipActive=membershipState(profile,at).active;
    const membershipChanged=profile.publicPremiumActive!==membershipActive;
    if(membershipChanged){profile.publicPremiumActive=membershipActive;changed=true;}
    if(normalizeSeasonRecord(profile,at))changed=true;
    const normalizedDeck=canonicalDeckForProfile(profile);
    if(normalizedDeck.length===6&&JSON.stringify(profile.deck)!==JSON.stringify(normalizedDeck)){
      profile.deck=normalizedDeck;changed=true;
    }
    const passBefore=JSON.stringify(profile.passState||null);
    syncServerPass(profile,at);
    if(JSON.stringify(profile.passState)!==passBefore)changed=true;
    const computedCollectionScore=collectionScoreForProfile(profile);
    const scoreChanged=safeInt(profile.collectionScore,0)!==computedCollectionScore;
    if(scoreChanged){profile.collectionScore=computedCollectionScore;changed=true;}
    if(changed)profile.updatedAt=nextProfileUpdateTime(profile,at);
    return {commit:changed,publishPublicProfile:scoreChanged||productChanged||membershipChanged};
  });
  if(result.decision.error)throw httpError(404,result.decision.error,'Player profile does not exist.');
  let profile=await reconcilePlayerCodeState(context.uid,result.profile);
  profile=await repairBattleV1ProductProgress(context.uid,profile,at);
  if(result.decision.publishPublicProfile)await publishPublicProfile(context.uid,profile,at);
  await assertAccountOperationAllowed(context.uid,'getPlayerState');
  let friendsCount=0;
  try{friendsCount=(await db.ref(`friends/${context.uid}`).get()).numChildren();}
  catch(error){logger.warn('Friend count refresh skipped',{uidHash:hash(context.uid).slice(0,16),error:String(error&&error.code||error)});}
  if(profile.uid!==context.uid)throw httpError(403,'profile-owner-mismatch','Player profile ownership does not match.');
  const battleV1Rank=await readBattleV1Rank(db,context.uid);
  await assertAccountOperationAllowed(context.uid,'getPlayerState');
  return {ok:true,state:Object.assign(authoritativeState(profile,at,{friendsCount}),{battleV1Rank})};
}
async function repairBattleV1ProductProgress(uid,profile,at){
  if(profile.serverProgress?.battleProtocol!==BATTLE_V1_PROTOCOL||profile[PRODUCT_PROGRESS_FIELD]!=null)return profile;
  const envelope=(await db.ref(`battleV1Accounts/${uid}`).get()).val();
  if(!envelope)return profile;
  let account;
  try{account=JSON.parse(envelope.accountJson);}catch(_){throw httpError(503,'battle-v1-product-progress-unavailable','Battle progress cannot be verified.');}
  if(!account||typeof account!=='object'||Array.isArray(account)||
    (account.ratingSettlements!=null&&(typeof account.ratingSettlements!=='object'||Array.isArray(account.ratingSettlements)))){
    throw httpError(503,'battle-v1-product-progress-unavailable','Battle progress cannot be verified.');
  }
  const receipts=Object.entries(account.ratingSettlements||{}).filter(([,receipt])=>receipt?.rated===true&&receipt.outcome!=='cancelled');
  receipts.sort((a,b)=>safeInt(b[1].settledAt,0)-safeInt(a[1].settledAt,0));
  if(!receipts.length)return profile;
  const repaired=await transactExistingPlayer(uid,function(current){
    if(current.uid!==uid)return {commit:false,error:'profile-owner-mismatch'};
    return {commit:projectBattleV1ProductProgress(current,account,receipts[0][0],at)};
  });
  if(repaired.decision.error)throw httpError(403,repaired.decision.error,'Battle progress owner does not match.');
  return repaired.profile;
}
async function acceptLegalTerms(context){
  const {uid,body}=context;
  assertBodyKeys(body,[]);
  await rateLimit(uid,'acceptLegalTerms',12,60*1000);
  const result=await transactExistingPlayer(uid,function(profile){
    if(profile.uid!==uid)return {commit:false,error:'profile-owner-mismatch'};
    if(legalConsentState(profile).accepted)return {commit:false,alreadyAccepted:true};
    profile.legalConsent={
      termsVersion:LEGAL_TERMS_VERSION,
      privacyVersion:LEGAL_PRIVACY_VERSION,
      communityVersion:LEGAL_COMMUNITY_VERSION,
      acceptedAt:ServerValue.TIMESTAMP,
      uid
    };
    profile.updatedAt=ServerValue.TIMESTAMP;
    return {commit:true,alreadyAccepted:false};
  });
  if(result.decision.error)throw httpError(403,result.decision.error,'Player profile ownership does not match.');
  const state=authoritativeState(result.profile,now());
  if(!state.legalConsent.accepted)throw httpError(500,'legal-consent-write-failed','Legal consent could not be recorded.');
  return {ok:true,accepted:true,alreadyAccepted:result.decision.alreadyAccepted===true,legalConsent:state.legalConsent,state};
}
async function claimDailyReward(context){
  const {uid,body}=context;
  assertBodyKeys(body,[]);
  await rateLimit(uid,'claimDailyReward',140,60*1000);
  return idempotent(uid,context.requestId,'claimDailyReward',async function(){
    const at=now();
    const result=await transactExistingPlayer(uid,function(profile){
      if(profile.uid!==uid)return {commit:false,error:'profile-owner-mismatch'};
      const decision=applyDailyRewardClaim(profile,uid,at);
      const progression=reconcileEarlyCardOwnership(profile,uid,at);
      return Object.assign({commit:decision.granted||progression.changed},decision,{early:progression.early});
    });
    if(result.decision.error)throw httpError(403,result.decision.error,'Player profile ownership does not match.');
    if(!result.decision.granted){
      return {
        ok:true,
        granted:false,
        idempotent:true,
        reward:{},
        transactionIds:result.decision.transactionIds||[],
        state:authoritativeState(result.profile,at)
      };
    }
    return {
      ok:true,
      granted:true,
      idempotent:false,
      reward:result.decision.reward,
      transactionIds:result.decision.transactionIds,
      state:authoritativeState(result.profile,at)
    };
  });
}
async function claimOnboardingReward(context){
  const {uid,body}=context;
  assertBodyKeys(body,[]);
  await rateLimit(uid,'claimOnboardingReward',30,60*1000);
  return idempotent(uid,context.requestId,'claimOnboardingReward',async function(){
    const at=now();
    const result=await transactExistingPlayer(uid,function(profile){
      if(profile.uid!==uid)return {commit:false,error:'profile-owner-mismatch'};
      const grant=applyRewardClaim(profile,{uid,sourceType:'onboarding_reward',sourceId:'v1',reward:ONBOARDING_REWARD,at});
      const progression=reconcileEarlyCardOwnership(profile,uid,at);
      if(grant.granted)profile.onboardingRewardClaimedAt=at;
      return Object.assign({commit:grant.granted||progression.changed},grant,{welcome:progression.early.welcomeClaimed});
    });
    if(result.decision.error)throw httpError(403,result.decision.error,'Player profile ownership does not match.');
    return {
      ok:true,granted:result.decision.granted===true,idempotent:result.decision.idempotent===true,
      welcome:{version:1,claimed:result.decision.welcome===true,card:'mine',eligibility:'account_welcome'},
      reward:result.decision.reward||{},transactionIds:result.decision.transactionIds||[],state:authoritativeState(result.profile,at)
    };
  });
}
async function claimSocialVisitReward(context){
  const {uid,body}=context;
  assertBodyKeys(body,['missionId']);
  const missionId=cleanString(body.missionId,32),reward=SOCIAL_VISIT_REWARDS[missionId];
  if(!reward)throw httpError(400,'unknown-social-reward','Social visit reward is unknown.');
  await rateLimit(uid,'claimSocialVisitReward',30,60*1000);
  return idempotent(uid,context.requestId,'claimSocialVisitReward:'+missionId,async function(){
    const at=now();
    const result=await transactExistingPlayer(uid,function(profile){
      const grant=applyRewardClaim(profile,{uid,sourceType:'social_visit_reward',sourceId:missionId,reward,at});
      if(!grant.granted)return Object.assign({commit:false},grant);
      if(!profile.serverProgress||typeof profile.serverProgress!=='object')profile.serverProgress={};
      if(!profile.serverProgress.socialRewards||typeof profile.serverProgress.socialRewards!=='object')profile.serverProgress.socialRewards={};
      profile.serverProgress.socialRewards[missionId]=at;
      if(!profile.passMissions||typeof profile.passMissions!=='object')profile.passMissions={};
      if(!profile.passMissions.specialDone||typeof profile.passMissions.specialDone!=='object')profile.passMissions.specialDone={};
      profile.passMissions.specialDone[missionId]=true;
      return Object.assign({commit:true},grant);
    });
    return {
      ok:true,granted:result.committed,idempotent:result.decision.idempotent===true,missionId,
      reward:result.decision.reward||{},transactionIds:result.decision.transactionIds||[],state:authoritativeState(result.profile,at)
    };
  });
}
function missionPeriodId(category,at){
  const periods=periodSnapshot(at);
  if(category==='daily')return periods.dayKey;
  if(category==='weekly')return periods.weekKey;
  return 'lifetime';
}
function missionPassXp(category){
  return category==='daily'?25:category==='weekly'?80:150;
}
function grantMissionPassXp(profile,category,at){
  const pass=syncServerPass(profile,at).pass;
  let remaining=missionPassXp(category);
  while(remaining>0&&pass.level<30){
    const room=250-safeInt(pass.xp,0),take=Math.min(room,remaining);
    pass.xp+=take;remaining-=take;
    if(pass.xp>=250){pass.level++;pass.xp=0;}
  }
  return {passXp:missionPassXp(category),passLevel:pass.level,passXpRemainder:pass.xp};
}
function selectedMissionIds(profile,category,at){
  const catalog=MISSION_CATALOG[category]||{};
  if(category==='special')return Object.keys(catalog);
  const periodId=missionPeriodId(category,at),period=profile.serverProgress&&profile.serverProgress.missions&&profile.serverProgress.missions[category]&&profile.serverProgress.missions[category][periodId],saved=period&&Array.isArray(period.selected)?period.selected:[];
  const valid=saved.filter(function(id){return typeof id==='string'&&catalog[id];});
  if(profile.serverProgress?.battleProtocol==='LUNO_BATTLE_V1'){
    const claims=profile.serverEconomy?.claims||{};
    const compatible=valid.filter(id=>missionOwned(profile,catalog[id])||claims[sourceClaimKey(profile.uid,'mission_reward',[category,periodId,id].join(':'))]);
    return [...new Set([...compatible,...deterministicMissionIds(profile,category,periodId)])].slice(0,5);
  }
  return valid.length?valid:deterministicMissionIds(profile,category,periodId);
}
function missionProgress(profile,category,periodId,missionId,definition,at=now()){
  if(category==='special'&&missionId==='s1')return arenaIndexForProfile(productProgressProfile(profile,at))>0?1:0;
  const progress=profile.serverProgress&&profile.serverProgress.missions&&profile.serverProgress.missions[category];
  const period=progress&&progress[periodId],counters=period&&period.counters||{};
  return safeInt(counters[definition.counter],0);
}
function missionSchedule(profile,category,at){
  const periodId=missionPeriodId(category,at),catalog=MISSION_CATALOG[category]||{};
  return selectedMissionIds(profile,category,at).map(function(id){
    const definition=catalog[id],sourceId=[category,periodId,id].join(':');
    const claims=profile.serverEconomy&&profile.serverEconomy.claims||{};
    return {
      id,
      periodId,
      title:(MISSION_COPY[id]&&MISSION_COPY[id][0])||id,
      description:(MISSION_COPY[id]&&MISSION_COPY[id][1])||'Bu dönem hedefini tamamla.',
      target:definition.target,
      progress:missionProgress(profile,category,periodId,id,definition,at),
      passXp:missionPassXp(category),
      reward:Object.assign({},definition.reward),
      claimed:!!claims[sourceClaimKey(profile.uid,'mission_reward',sourceId)]
    };
  });
}
function achievementSchedule(profile,at,external){
  const claims=profile.achievementsClaimed&&typeof profile.achievementsClaimed==='object'?profile.achievementsClaimed:{};
  return Object.keys(ACHIEVEMENT_CATALOG).map(function(id){
    const definition=ACHIEVEMENT_CATALOG[id],copy=ACHIEVEMENT_COPY[id]||[id,'Başarımını tamamla.'];
    const progress=achievementValue(profile,definition.statKey,at,external||{});
    return {
      id,title:copy[0],description:copy[1],statKey:definition.statKey,target:definition.target,
      progress, reward:Object.assign({},definition.reward),claimed:Object.prototype.hasOwnProperty.call(claims,id),
      canClaim:progress>=definition.target&&!Object.prototype.hasOwnProperty.call(claims,id)
    };
  });
}
function rewardSchedule(profile,at,external){
  return {
    periods:periodSnapshot(at),
    missions:{
      daily:missionSchedule(profile,'daily',at),
      weekly:missionSchedule(profile,'weekly',at),
      special:missionSchedule(profile,'special',at)
    },
    achievements:achievementSchedule(profile,at,external||{})
  };
}
async function claimMissionReward(context){
  const {uid,body}=context;
  assertBodyKeys(body,['category','missionId']);
  const category=cleanString(body.category,16),missionId=cleanString(body.missionId,64);
  const catalog=MISSION_CATALOG[category],definition=catalog&&catalog[missionId];
  if(!definition)throw httpError(400,'unknown-mission','Mission does not exist.');
  await rateLimit(uid,'claimMissionReward',100,60*1000);
  return idempotent(uid,context.requestId,'claimMissionReward:'+category+':'+missionId,async function(){
    const at=now(),periodId=missionPeriodId(category,at),sourceId=[category,periodId,missionId].join(':');
    const result=await transactExistingPlayer(uid,function(profile){
      if(!selectedMissionIds(profile,category,at).includes(missionId))return {commit:false,error:'mission-not-active'};
      const progress=missionProgress(profile,category,periodId,missionId,definition,at);
      if(progress<definition.target)return {commit:false,error:'mission-not-complete',progress,target:definition.target};
      const grant=applyRewardClaim(profile,{uid,sourceType:'mission_reward',sourceId,reward:definition.reward,at});
      if(!grant.granted)return Object.assign({commit:false},grant);
      const passGrant=grantMissionPassXp(profile,category,at);
      if(!profile.missions||typeof profile.missions!=='object')profile.missions={};
      if(!profile.missions[category]||typeof profile.missions[category]!=='object')profile.missions[category]={};
      profile.missions[category][missionId+'_claimed']=at;
      return Object.assign({commit:true,progress,target:definition.target},grant,passGrant,{reward:Object.assign({},grant.reward,{passXp:passGrant.passXp})});
    });
    if(result.decision.error)throw httpError(409,result.decision.error,'Mission reward is not eligible.');
    return {
      ok:true,
      granted:result.committed,
      idempotent:result.decision.idempotent===true,
      reward:result.decision.reward||{},
      transactionIds:result.decision.transactionIds||[],
      state:authoritativeState(result.profile,at)
    };
  });
}
function achievementValue(profile,statKey,at,external){
  const stats=profile.stats||{},inventory=profile.inventory||{};
  if(statKey==='arenaIdx')return arenaIndexForProfile(productProgressProfile(profile,at))+1;
  if(statKey==='ownedSkinsCount')return stringList(inventory.ownedSkins,['classic']).filter(function(id,index,list){return list.indexOf(id)===index;}).length;
  if(statKey==='friendsCount')return safeInt(external&&external.friendsCount,safeInt(stats.friendsCount,0));
  if(statKey==='gamesPlayed')return safeInt(stats.wins,0)+safeInt(stats.losses,0)+safeInt(stats.draws,0);
  if(statKey==='loginStreak')return safeInt(profile.serverActivity&&profile.serverActivity.loginStreak,0);
  if(statKey==='level')return Math.max(1,safeInt(profile.lvl,1));
  if(statKey==='dailyStreak')return safeInt(profile.serverEconomy&&profile.serverEconomy.daily&&profile.serverEconomy.daily.streak,0);
  if(statKey==='isPremium')return premiumAccess(profile,at)?1:0;
  if(statKey==='premiumDays'){
    const since=safeInt(profile.premiumSince,0);
    return since&&premiumAccess(profile,at)?Math.max(0,Math.floor((at-since)/(24*60*60*1000))):0;
  }
  return safeInt(stats[statKey],0);
}
async function claimAchievementReward(context){
  const {uid,body}=context;
  assertBodyKeys(body,['achievementId']);
  const achievementId=cleanString(body.achievementId,64),definition=ACHIEVEMENT_CATALOG[achievementId];
  if(!definition)throw httpError(400,'unknown-achievement','Achievement does not exist.');
  await rateLimit(uid,'claimAchievementReward',80,60*1000);
  const friendsCount=definition.statKey==='friendsCount'?(await db.ref(`friends/${uid}`).get()).numChildren():0;
  return idempotent(uid,context.requestId,'claimAchievementReward:'+achievementId,async function(){
    const at=now();
    const result=await transactExistingPlayer(uid,function(profile){
      const progress=achievementValue(profile,definition.statKey,at,{friendsCount});
      if(progress<definition.target)return {commit:false,error:'achievement-not-complete',progress,target:definition.target};
      const grant=applyRewardClaim(profile,{uid,sourceType:'achievement_reward',sourceId:achievementId,reward:definition.reward,at});
      if(!grant.granted)return Object.assign({commit:false},grant);
      if(!profile.achievementsClaimed||typeof profile.achievementsClaimed!=='object')profile.achievementsClaimed={};
      profile.achievementsClaimed[achievementId]=at;
      return Object.assign({commit:true,progress,target:definition.target},grant);
    });
    if(result.decision.error)throw httpError(409,result.decision.error,'Achievement reward is not eligible.');
    return {
      ok:true,
      granted:result.committed,
      idempotent:result.decision.idempotent===true,
      reward:result.decision.reward||{},
      transactionIds:result.decision.transactionIds||[],
      state:authoritativeState(result.profile,at,{friendsCount})
    };
  });
}
function syncServerPass(profile,at){
  return syncPassState(profile,at);
}
function grantPassContent(profile,content,at=now()){
  if(!content||typeof content!=='object')return null;
  const kind=cleanString(content.kind,24),id=cleanString(content.id,64);
  if(!kind||!id)throw httpError(500,'invalid-pass-content','Pass content reward is invalid.');
  const synced=syncServerPass(profile,at),token=(kind==='emoji'?'emoji:':kind==='piece_set'?'piece_set:':'chest:')+id;
  if(!synced.pass.unlocks.includes(token))synced.pass.unlocks.push(token);
  const inventory=serverInventory(profile);
  let duplicate=false,compensation=null;
  if(kind==='emoji'){
    if(!knownSelection('emoji',id))throw httpError(500,'invalid-pass-content','Pass emoji reward is invalid.');
    duplicate=inventory.ownedEmojis.includes(id);
    if(!duplicate)inventory.ownedEmojis.push(id);
    else compensation={gold:250};
  }else if(kind==='piece_set'){
    if(!knownSelection('piece_set',id))throw httpError(500,'invalid-pass-content','Pass piece set reward is invalid.');
    duplicate=inventory.ownedSets.includes(id);
    if(!duplicate)inventory.ownedSets.push(id);
    else compensation={gold:1000};
  }else if(kind==='chest'){
    if(!CHEST_CATALOG[id])throw httpError(500,'invalid-pass-content','Pass chest reward is invalid.');
    if(!Array.isArray(inventory.pendingChests))inventory.pendingChests=[];
    inventory.pendingChests.push(id);
  }else throw httpError(500,'invalid-pass-content','Pass content reward is invalid.');
  return {kind,id,token,duplicate,compensation};
}
async function claimPassReward(context){
  const {uid,body}=context;
  assertBodyKeys(body,['level','track']);
  const level=Number(body.level),track=cleanString(body.track,16);
  if(!Number.isInteger(level)||level<1||level>30||!['free','premium'].includes(track))throw httpError(400,'invalid-pass-reward','Pass reward selection is invalid.');
  const content=PASS_CONTENT_REWARDS[track]&&PASS_CONTENT_REWARDS[track][level];
  await rateLimit(uid,'claimPassReward',80,60*1000);
  return idempotent(uid,context.requestId,'claimPassReward',async function(){
    const at=now();
    const result=await transactExistingPlayer(uid,function(profile){
      const synced=syncServerPass(profile,at),pass=synced.pass;
      const definition=passCurrencyReward(pass,track,level);
      if(!definition)return {commit:false,error:'pass-reward-not-configured'};
      if(pass.level<level)return {commit:false,error:'pass-level-locked'};
      if(track==='premium'&&pass.premium!==true)return {commit:false,error:'pass-premium-required'};
      const sourceId=[synced.periods.seasonId,track,level].join(':');
      const grant=applyRewardClaim(profile,{uid,sourceType:'pass_reward',sourceId,reward:definition,at});
      if(!grant.granted)return Object.assign({commit:false},grant);
      const contentGrant=content?grantPassContent(profile,content,at):null;
      if(contentGrant&&contentGrant.compensation){
        const duplicateGrant=applyRewardClaim(profile,{uid,sourceType:'pass_content_duplicate',sourceId:sourceId+':content',reward:contentGrant.compensation,at});
        contentGrant.compensation=duplicateGrant.reward||contentGrant.compensation;
      }
      pass.claimed[track][level]=at;
      return Object.assign({commit:true,content:contentGrant},grant);
    });
    if(result.decision.error)throw httpError(409,result.decision.error,'Pass reward is not eligible.');
    return {ok:true,granted:result.committed,idempotent:result.decision.idempotent===true,reward:result.decision.reward||{},content:result.decision.content||null,transactionIds:result.decision.transactionIds||[],state:authoritativeState(result.profile,at)};
  });
}
function seasonTier(trophies){
  let selected=SEASON_REWARDS[0];
  for(const tier of SEASON_REWARDS)if(safeInt(trophies,0)>=tier.minTrophies)selected=tier;
  return selected;
}
async function claimSeasonReward(context){
  const {uid,body}=context;
  assertBodyKeys(body,[]);
  await rateLimit(uid,'claimSeasonReward',80,60*1000);
  return idempotent(uid,context.requestId,'claimSeasonReward',async function(){
    const at=now(),currentSeason=Number(periodSnapshot(at).seasonId.slice(1));
    const result=await transactExistingPlayer(uid,function(profile){
      repairBattleV1ProductSeasonCursor(profile,at);
      const progress=readBattleV1ProductProgress(profile,at);
      if(!progress&&profile.serverProgress?.battleProtocol!==BATTLE_V1_PROTOCOL)normalizeSeasonRecord(profile,at);
      const season=productProgressProfile(profile,at).serverSeason;
      if(!season||!Number.isInteger(Number(season.number)))return {commit:false,error:'season-migration-required'};
      const previousSeason=Number(season.number);
      if(previousSeason>=currentSeason){
        const lastRewardSeason=safeInt(season.lastRewardSeason,0),claims=profile.serverEconomy&&profile.serverEconomy.claims||{};
        const existing=lastRewardSeason&&claims[sourceClaimKey(uid,'season_reward','s'+lastRewardSeason)];
        if(existing)return {commit:false,idempotent:true,reward:existing.reward||{},transactionIds:existing.transactionIds||[],tier:season.lastRewardTier,seasonNumber:lastRewardSeason};
        return {commit:false,error:'season-reward-not-ready'};
      }
      const tier=seasonTier(season.peakTrophies);
      const sourceId='s'+previousSeason;
      const grant=applyRewardClaim(profile,{uid,sourceType:'season_reward',sourceId,reward:tier.reward,at});
      if(progress){
        const completed=completeBattleV1ProductSeason(profile,previousSeason,at);
        return Object.assign({commit:true,tier:completed.lastRewardTier,seasonNumber:previousSeason},grant);
      }
      if(!grant.granted)return Object.assign({commit:false},grant);
      const arena=arenaIndexForProfile(profile);
      profile.trophies=Math.max(ARENAS[arena].min,0);
      profile.serverSeason={number:currentSeason,seasonId:'s'+currentSeason,peakTrophies:profile.trophies,startedAt:at,claimed:{},lastRewardSeason:previousSeason,lastRewardTier:tier.tier};
      profile.season={number:currentSeason,peakTrophies:profile.trophies,startedAt:at,pendingRewards:[]};
      return Object.assign({commit:true,tier:tier.tier,seasonNumber:previousSeason},grant);
    });
    if(result.decision.error)throw httpError(409,result.decision.error,'Season reward is not eligible.');
    return {ok:true,granted:result.decision.granted===true,idempotent:result.decision.idempotent===true,tier:result.decision.tier,reward:result.decision.reward||{},transactionIds:result.decision.transactionIds||[],state:authoritativeState(result.profile,at)};
  });
}
async function claimSeasonPathReward(context){
  const {uid,body}=context;
  assertBodyKeys(body,['tierId']);
  const tierId=cleanString(body.tierId,32),definition=SEASON_PATH_REWARDS.find(function(tier){return tier.id===tierId;});
  if(!definition)throw httpError(400,'unknown-season-tier','Season path tier is unknown.');
  await rateLimit(uid,'claimSeasonPathReward',100,60*1000);
  return idempotent(uid,context.requestId,'claimSeasonPathReward:'+tierId,async function(){
    const at=now(),periods=periodSnapshot(at),currentSeason=safeInt(periods.seasonNumber,1),sourceId=[periods.seasonId,tierId].join(':');
    const result=await transactExistingPlayer(uid,function(profile){
      const progress=readBattleV1ProductProgress(profile,at);
      if(!progress&&profile.serverProgress?.battleProtocol!==BATTLE_V1_PROTOCOL)normalizeSeasonRecord(profile,at);
      const season=productProgressProfile(profile,at).serverSeason;
      if(!season||!Number.isSafeInteger(Number(season.number)))return {commit:false,error:'season-migration-required'};
      if(Number(season.number)!==currentSeason)return {commit:false,error:'season-reward-not-ready'};
      const score=safeInt(season.peakTrophies,0);
      if(score<definition.minTrophies)return {commit:false,error:'season-tier-locked',score,target:definition.minTrophies};
      const grant=applyRewardClaim(profile,{uid,sourceType:'season_path_reward',sourceId,reward:definition.reward,at});
      if(!grant.granted)return Object.assign({commit:false},grant);
      if(!progress&&profile.serverProgress?.battleProtocol!==BATTLE_V1_PROTOCOL){
        if(!season.claimed||typeof season.claimed!=='object'||Array.isArray(season.claimed))season.claimed={};
        season.claimed[tierId]=at;
      }
      profile.updatedAt=at;
      return Object.assign({commit:true,tierId,seasonNumber:currentSeason,score},grant);
    });
    if(result.decision.error)throw httpError(409,result.decision.error,'Season path reward is not eligible.');
    return {ok:true,granted:result.committed,idempotent:result.decision.idempotent===true,tierId:result.decision.tierId||tierId,reward:result.decision.reward||{},transactionIds:result.decision.transactionIds||[],state:authoritativeState(result.profile,at)};
  });
}
function serverInventory(profile){
  normalizeProductEntitlements(profile);
  if(!profile.inventory||typeof profile.inventory!=='object'||Array.isArray(profile.inventory))profile.inventory={};
  const inventory=profile.inventory;
  const knownOwned=function(value,kind,defaults){
    const result=[],seen=new Set();
    for(const raw of stringList(value,defaults)){
      const id=kind==='piece_set'?canonicalPieceSetId(raw):raw;
      if(!knownSelection(kind,id)||seen.has(id))continue;
      seen.add(id);result.push(id);
    }
    return result;
  };
  inventory.ownedSkins=knownOwned(inventory.ownedSkins,'skin',['classic']);
  inventory.ownedEmojis=knownOwned(inventory.ownedEmojis,'emoji',[]);
  for(const emojiId of FREE_EMOJIS)if(!inventory.ownedEmojis.includes(emojiId))inventory.ownedEmojis.unshift(emojiId);
  inventory.ownedFrames=knownOwned(inventory.ownedFrames,'frame',['none']);
  inventory.ownedBioFrames=knownOwned(inventory.ownedBioFrames,'bio_frame',['default']);
  inventory.ownedCostumes=knownOwned(inventory.ownedCostumes,'costume',[]);
  inventory.ownedSets=knownOwned(inventory.ownedSets,'piece_set',['std']);
  inventory.activeSkin=inventory.ownedSkins.includes(inventory.activeSkin)?inventory.activeSkin:'classic';
  inventory.activePieceSet=inventory.ownedSets.includes(canonicalPieceSetId(inventory.activePieceSet))
    ?canonicalPieceSetId(inventory.activePieceSet):'std';
  // Legacy profiles predate Pass chest content. Normalize the field before
  // every read and transaction so opening an older account cannot throw.
  inventory.pendingChests=stringMultisetList(inventory.pendingChests,[]);
  const activeCostumes={};
  if(inventory.activeCostumes&&typeof inventory.activeCostumes==='object'&&!Array.isArray(inventory.activeCostumes)){
    for(const pieceType of Object.keys(COSTUME_TYPES)){
      const costume=inventory.activeCostumes[pieceType];
      if(typeof costume!=='string'||!costume.startsWith(COSTUME_TYPES[pieceType])||!knownSelection('costume',costume))continue;
      const owned=FREE_COSTUMES.has(costume)||inventory.ownedCostumes.includes(costume)||PASS_COSTUMES.has(costume)&&premiumAccess(profile,now());
      if(owned)activeCostumes[pieceType]=costume;
    }
  }
  inventory.activeCostumes=activeCostumes;
  return inventory;
}
function softItemOwned(profile,definition){
  const grant=definition.grant||{},inventory=serverInventory(profile),id=grant.id;
  if(grant.kind==='pass_premium')return profile.passState&&profile.passState.premium===true;
  if(grant.kind==='piece_set')return inventory.ownedSets.includes(id);
  if(grant.kind==='skin')return inventory.ownedSkins.includes(id);
  if(grant.kind==='emoji')return inventory.ownedEmojis.includes(id);
  if(grant.kind==='frame')return inventory.ownedFrames.includes(id);
  if(grant.kind==='bio_frame')return inventory.ownedBioFrames.includes(id);
  if(grant.kind==='costume')return inventory.ownedCostumes.includes(id);
  if(grant.kind==='costume_pack')return Object.keys(COSTUME_PRICES).every(function(costumeId){return inventory.ownedCostumes.includes(costumeId);});
  return false;
}
function grantSoftItem(profile,definition,at){
  const grant=definition.grant||{},inventory=serverInventory(profile),id=grant.id;
  if(grant.kind==='pass_premium'){
    const synced=syncServerPass(profile,at);synced.pass.premium=true;synced.pass.premiumSource='soft_purchase';
  }else if(grant.kind==='piece_set'){
    if(!inventory.ownedSets.includes(id))inventory.ownedSets.push(id);inventory.activePieceSet=id;
  }else if(grant.kind==='skin'){
    if(!inventory.ownedSkins.includes(id))inventory.ownedSkins.push(id);inventory.activeSkin=id;
  }else if(grant.kind==='emoji'){
    if(!inventory.ownedEmojis.includes(id))inventory.ownedEmojis.push(id);
  }else if(grant.kind==='frame'){
    if(!inventory.ownedFrames.includes(id))inventory.ownedFrames.push(id);profile.frame=id;
  }else if(grant.kind==='bio_frame'){
    if(!inventory.ownedBioFrames.includes(id))inventory.ownedBioFrames.push(id);profile.bioFrame=id;
  }else if(grant.kind==='costume'){
    if(!inventory.ownedCostumes.includes(id))inventory.ownedCostumes.push(id);inventory.activeCostumes[definition.pieceType]=id;
  }else if(grant.kind==='costume_pack'){
    Object.keys(COSTUME_PRICES).forEach(function(costumeId){if(!inventory.ownedCostumes.includes(costumeId))inventory.ownedCostumes.push(costumeId);});
  }else throw new TypeError('Unsupported soft item grant.');
  return {kind:grant.kind,id};
}
function permanentPurchaseReplay(profile,uid,itemId,requestId){
  const record=value=>value!==null&&typeof value==='object'&&!Array.isArray(value),invalid=()=>({commit:false,error:'soft-purchase-receipt-invalid'});
  const economy=profile.serverEconomy;
  if(economy!=null&&!record(economy))return invalid();
  const purchases=economy&&economy.purchases,ledger=economy&&economy.ledger,claims=economy&&economy.claims;
  if([purchases,ledger,claims].some(value=>value!=null&&!record(value)))return invalid();
  const requestIdHash=hash(requestId);
  const passRequests=economy&&economy.passPurchaseRequests;
  if(passRequests!=null&&!record(passRequests))return invalid();
  if(passRequests&&passRequests[requestIdHash]!=null){
    return validPassPurchaseSeason(passRequests[requestIdHash])?{commit:false,error:'request-id-conflict'}:invalid();
  }
  for(const [otherId,otherDefinition] of Object.entries(SOFT_ITEM_CATALOG)){
    if(otherDefinition.seasonScoped)continue;
    const other=purchases&&purchases[sourceClaimKey(uid,'soft_purchase',otherId)];
    if(other&&other.requestIdHash===requestIdHash&&otherId!==itemId){
      return other.uid===uid?{commit:false,error:'request-id-conflict'}:invalid();
    }
  }
  const definition=SOFT_ITEM_CATALOG[itemId],key=sourceClaimKey(uid,'soft_purchase',itemId),purchase=purchases&&purchases[key];
  if(purchase==null){
    for(const currency of ['gold','gems']){
      const transactionId='sp_'+hash([uid,'soft_purchase',itemId,currency].join('|')).slice(0,40);
      if(ledger&&ledger[transactionId]!=null)return invalid();
    }
    return null;
  }
  if(!record(purchase)||!record(purchase.outcome))return invalid();
  const transactionId='sp_'+hash([uid,'soft_purchase',itemId,purchase.currency].join('|')).slice(0,40),spend=ledger&&ledger[transactionId];
  if(purchase.uid!==uid||purchase.idempotencyKey!==key||purchase.sourceType!=='soft_purchase'||purchase.sourceId!==itemId||
    purchase.itemType!==definition.grant.kind||purchase.itemId!==itemId||!['gold','gems'].includes(purchase.currency)||
    !Number.isSafeInteger(purchase.price)||purchase.price<=0||purchase.price>1000000||
    !Number.isSafeInteger(purchase.purchasedAt)||purchase.purchasedAt<=0||purchase.transactionId!==transactionId||
    purchase.requestIdHash!=null&&(typeof purchase.requestIdHash!=='string'||!/^[a-f0-9]{64}$/.test(purchase.requestIdHash))||
    purchase.outcome.kind!==definition.grant.kind||purchase.outcome.id!==definition.grant.id||
    !record(spend)||spend.transactionId!==transactionId||spend.idempotencyKey!==key||spend.uid!==uid||
    spend.sourceType!=='soft_purchase'||spend.sourceId!==itemId||spend.itemType!==definition.grant.kind||spend.itemId!==itemId||
    spend.rewardType!==purchase.currency||spend.amount!==-purchase.price||spend.createdAt!==purchase.purchasedAt||
    !Number.isSafeInteger(spend.previousBalance)||!Number.isSafeInteger(spend.newBalance)||spend.newBalance<0||
    spend.previousBalance-spend.newBalance!==purchase.price||!softItemOwned(profile,definition))return invalid();
  return {commit:false,purchased:false,idempotent:true,transactionId,outcome:{kind:purchase.outcome.kind,id:purchase.outcome.id}};
}
function validPassPurchaseSeason(value){return typeof value==='string'&&/^s[1-9][0-9]{0,8}$/.test(value);}
function passPurchaseReplay(profile,uid,seasonId,requestId){
  const record=value=>value!==null&&typeof value==='object'&&!Array.isArray(value),invalid=()=>({commit:false,error:'pass-purchase-receipt-invalid'});
  const economy=profile.serverEconomy;
  if(economy!=null&&!record(economy))return invalid();
  const purchases=economy&&economy.purchases,ledger=economy&&economy.ledger,claims=economy&&economy.claims,intents=economy&&economy.passPurchaseRequests;
  if([purchases,ledger,claims,intents].some(value=>value!=null&&!record(value)))return invalid();
  const requestHash=hash(requestId),bound=intents&&intents[requestHash];
  if(bound!=null){
    if(!validPassPurchaseSeason(bound))return invalid();
    if(bound!==seasonId)return {commit:false,error:'request-id-conflict'};
  }
  for(const [itemId,definition] of Object.entries(SOFT_ITEM_CATALOG)){
    if(definition.seasonScoped)continue;
    const other=purchases&&purchases[sourceClaimKey(uid,'soft_purchase',itemId)];
    if(other&&other.requestIdHash===requestHash)return other.uid===uid?{commit:false,error:'request-id-conflict'}:invalid();
  }
  const sourceId=seasonId+':pass:premium',key=sourceClaimKey(uid,'soft_purchase',sourceId),purchase=purchases&&purchases[key];
  if(purchase==null){
    if(bound!=null)return invalid();
    for(const currency of ['gold','gems'])if(ledger&&ledger['sp_'+hash([uid,'soft_purchase',sourceId,currency].join('|')).slice(0,40)]!=null)return invalid();
    return null;
  }
  if(!record(purchase)||!record(purchase.outcome))return invalid();
  const transactionId='sp_'+hash([uid,'soft_purchase',sourceId,purchase.currency].join('|')).slice(0,40),spend=ledger&&ledger[transactionId];
  if(purchase.uid!==uid||purchase.idempotencyKey!==key||purchase.sourceType!=='soft_purchase'||purchase.sourceId!==sourceId||
    purchase.itemType!=='pass_premium'||purchase.itemId!=='pass:premium'||!['gold','gems'].includes(purchase.currency)||
    !Number.isSafeInteger(purchase.price)||purchase.price<=0||purchase.price>1000000||
    !Number.isSafeInteger(purchase.purchasedAt)||purchase.purchasedAt<=0||purchase.purchasedAt>8640000000000000||
    periodSnapshot(purchase.purchasedAt).seasonId!==seasonId||purchase.transactionId!==transactionId||
    purchase.outcome.kind!=='pass_premium'||purchase.outcome.id!=='premium'||
    purchase.requestIdHash!=null&&(typeof purchase.requestIdHash!=='string'||!/^[a-f0-9]{64}$/.test(purchase.requestIdHash)||!intents||intents[purchase.requestIdHash]!==seasonId)||
    bound!=null&&purchase.requestIdHash!==requestHash||
    !record(spend)||spend.uid!==uid||spend.transactionId!==transactionId||spend.idempotencyKey!==key||
    spend.sourceType!=='soft_purchase'||spend.sourceId!==sourceId||spend.itemType!=='pass_premium'||spend.itemId!=='pass:premium'||
    spend.rewardType!==purchase.currency||spend.amount!==-purchase.price||spend.createdAt!==purchase.purchasedAt||
    !Number.isSafeInteger(spend.previousBalance)||!Number.isSafeInteger(spend.newBalance)||spend.newBalance<0||spend.previousBalance-spend.newBalance!==purchase.price)return invalid();
  if(periodSnapshot(now()).seasonId===seasonId&&(!record(profile.passState)||profile.passState.seasonKey!=='ranked-'+seasonId+'-v2'||profile.passState.premium!==true))return invalid();
  return {commit:false,purchased:false,idempotent:true,transactionId,outcome:{kind:'pass_premium',id:'premium'}};
}
async function purchasePassPremium(context){
  const {uid,body,requestId}=context,seasonId=body.seasonId,definition=SOFT_ITEM_CATALOG['pass:premium'];
  if(seasonId===undefined)throw httpError(409,'pass-season-required','Refresh the app before purchasing a season-bound Pass.');
  if(!validPassPurchaseSeason(seasonId))throw httpError(400,'invalid-pass-season','Pass season identity is invalid.');
  const operation='purchaseSoftItem:pass:premium:'+seasonId;
  const response=await idempotent(uid,requestId,operation,async function(){
    const result=await transactExistingPlayer(uid,function(profile){
      if(profile.uid!==uid)return {commit:false,error:'profile-owner-mismatch'};
      const replay=passPurchaseReplay(profile,uid,seasonId,requestId);
      if(replay)return replay;
      const at=now();
      if(periodSnapshot(at).seasonId!==seasonId)return {commit:false,error:'pass-season-changed'};
      if(billingReviewRequired(profile))return {commit:false,error:'billing-review-required'};
      syncServerPass(profile,at);
      const purchase=applySoftPurchase(profile,{uid,sourceType:'soft_purchase',sourceId:seasonId+':pass:premium',itemType:'pass_premium',itemId:'pass:premium',currency:definition.currency,price:definition.price,at,
        isOwned:current=>softItemOwned(current,definition),grant:current=>grantSoftItem(current,definition,at)});
      if(purchase.purchased){
        const requestHash=hash(requestId),economy=profile.serverEconomy;
        economy.purchases[purchase.idempotencyKey].requestIdHash=requestHash;
        if(!economy.passPurchaseRequests)economy.passPurchaseRequests={};
        economy.passPurchaseRequests[requestHash]=seasonId;
      }
      return Object.assign({commit:purchase.purchased},purchase);
    });
    if(result.decision.error)throw httpError(result.decision.error==='profile-owner-mismatch'?403:409,result.decision.error,'Premium Pass purchase could not be confirmed.');
    return {ok:true,purchased:result.committed,idempotent:result.decision.idempotent===true};
  });
  const latest=(await db.ref(`users/${uid}`).get()).val();
  if(!latest)throw httpError(404,'profile-not-found','Player profile does not exist.');
  if(latest.uid!==uid)throw httpError(403,'profile-owner-mismatch','Player profile ownership does not match.');
  const replay=passPurchaseReplay(latest,uid,seasonId,requestId);
  if(!replay||replay.error)throw httpError(409,replay&&replay.error||'pass-purchase-receipt-invalid','Premium Pass receipt could not be confirmed.');
  await assertAccountOperationAllowed(uid,'purchaseSoftItem');
  const at=now(),currentSeasonId=periodSnapshot(at).seasonId;
  Object.assign(response,{ok:true,itemId:'pass:premium',seasonId,currentSeasonId,passActive:seasonId===currentSeasonId,
    purchased:response.idempotent===true?false:response.purchased,transactionId:replay.transactionId,grant:replay.outcome,state:authoritativeState(latest,at)});
  await publishPublicProfile(uid,latest);
  return response;
}
async function purchaseSoftItem(context){
  const {uid,body}=context;
  assertBodyKeys(body,['itemId','seasonId']);
  const itemId=cleanString(body.itemId,96),definition=Object.hasOwn(SOFT_ITEM_CATALOG,itemId)?SOFT_ITEM_CATALOG[itemId]:null;
  if(!definition)throw httpError(400,'unknown-item','Item is not in the server catalog.');
  await rateLimit(uid,'purchaseSoftItem',60,60*1000);
  if(definition.seasonScoped)return purchasePassPremium(context);
  assertBodyKeys(body,['itemId']);
  const response=await idempotent(uid,context.requestId,'purchaseSoftItem:'+itemId,async function(){
    const at=now(),periods=periodSnapshot(at),sourceId=definition.seasonScoped?periods.seasonId+':'+itemId:itemId;
    const result=await transactExistingPlayer(uid,function(profile){
      if(profile.uid!==uid)return {commit:false,error:'profile-owner-mismatch'};
      if(!definition.seasonScoped){
        const replay=permanentPurchaseReplay(profile,uid,itemId,context.requestId);
        if(replay)return replay;
      }
      if(billingReviewRequired(profile))return {commit:false,error:'billing-review-required'};
      if(definition.grant.kind==='pass_premium')syncServerPass(profile,at);
      const purchase=applySoftPurchase(profile,{
        uid,sourceType:'soft_purchase',sourceId,itemType:definition.grant.kind,itemId,
        currency:definition.currency,price:definition.price,at,
        isOwned:function(current){return softItemOwned(current,definition);},
        grant:function(current){return grantSoftItem(current,definition,at);}
      });
      if(purchase.purchased&&!definition.seasonScoped){
        profile.serverEconomy.purchases[purchase.idempotencyKey].requestIdHash=hash(context.requestId);
      }
      return Object.assign({commit:purchase.purchased},purchase);
    });
    if(result.decision.error)throw httpError(result.decision.error==='profile-owner-mismatch'?403:409,result.decision.error,'Item purchase could not be confirmed.');
    return {ok:true,purchased:result.committed,idempotent:result.decision.idempotent===true,itemId,transactionId:result.decision.transactionId||null,grant:result.decision.outcome||null,state:authoritativeState(result.profile,at)};
  });
  const latest=(await db.ref(`users/${uid}`).get()).val();
  if(!definition.seasonScoped){
    if(!latest)throw httpError(404,'profile-not-found','Player profile does not exist.');
    if(latest.uid!==uid)throw httpError(403,'profile-owner-mismatch','Player profile ownership does not match.');
    const replay=permanentPurchaseReplay(latest,uid,itemId,context.requestId);
    if(!replay||replay.error)throw httpError(409,replay&&replay.error||'soft-purchase-receipt-invalid','Item purchase receipt could not be confirmed.');
    await assertAccountOperationAllowed(uid,'purchaseSoftItem');
    Object.assign(response,{ok:true,itemId,purchased:response.idempotent===true?false:response.purchased,transactionId:replay.transactionId,grant:replay.outcome,state:authoritativeState(latest,now())});
  }
  if(latest)await publishPublicProfile(uid,latest);
  return response;
}
async function upgradeCard(context){
  const {uid,body}=context;
  assertBodyKeys(body,['family','targetLevel']);
  const family=cleanString(body.family,24),targetLevel=Number(body.targetLevel),levels=CARD_UPGRADE_CATALOG[family],definition=levels&&levels[targetLevel];
  if(!definition||!Number.isInteger(targetLevel)||targetLevel<2||targetLevel>3)throw httpError(400,'invalid-card-upgrade','Card upgrade target is invalid.');
  await rateLimit(uid,'upgradeCard',40,60*1000);
  return idempotent(uid,context.requestId,'upgradeCard:'+family+':'+targetLevel,async function(){
    const at=now(),sourceId=family+':level:'+targetLevel;
    const result=await transactExistingPlayer(uid,function(profile){
      if(billingReviewRequired(profile))return {commit:false,error:'billing-review-required'};
      const currentLevel=Math.max(1,safeInt(profile.cardLevel&&profile.cardLevel[family],1));
      if(currentLevel<targetLevel-1)return {commit:false,error:'upgrade-sequence'};
      if(!profile.unlockedCards||profile.unlockedCards[family+'1']!==true)return {commit:false,error:'card-locked'};
      if(arenaIndexForProfile(profile)<definition.minArenaIdx)return {commit:false,error:'arena-locked'};
      const purchase=applySoftPurchase(profile,{
        uid,sourceType:'card_upgrade',sourceId,itemType:'card_upgrade',itemId:family+':'+targetLevel,
        currency:'gold',price:definition.price,at,
        isOwned:function(current){return safeInt(current.cardLevel&&current.cardLevel[family],1)>=targetLevel;},
        grant:function(current){
          if(!current.cardLevel||typeof current.cardLevel!=='object')current.cardLevel={};
          current.cardLevel[family]=targetLevel;
          if(Array.isArray(current.deck))current.deck=current.deck.map(function(card){
            const value=String(card);
            return value===family||new RegExp('^'+family+'[123]$').test(value)?family+targetLevel:card;
          });
          return {family,targetLevel};
        }
      });
      return Object.assign({commit:purchase.purchased},purchase);
    });
    if(result.decision.error)throw httpError(409,result.decision.error,'Card upgrade is not eligible.');
    return {ok:true,upgraded:result.committed,idempotent:result.decision.idempotent===true,family,targetLevel,transactionId:result.decision.transactionId||null,state:authoritativeState(result.profile,at)};
  });
}
function validChestDrops(rewards){
  const record=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
  const types=new Set(['gold','gems','card','battle_card','emoji','skin','frame_shard','bioframe_shard']);
  return Array.isArray(rewards)&&rewards.length>0&&rewards.every(function(reward){
    return record(reward)&&types.has(reward.type)&&Number.isSafeInteger(reward.amount)&&reward.amount>0&&reward.amount<=1000000&&
      (['gold','gems'].includes(reward.type)||typeof reward.id==='string'&&reward.id.length>0);
  });
}
function shopChestOpeningReplay(profile,uid,requestId,chestId){
  const record=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
  const invalid=()=>({commit:false,error:'chest-purchase-receipt-invalid'}),economy=profile.serverEconomy;
  if(economy!=null&&!record(economy))return invalid();
  const purchases=economy&&economy.purchases,claims=economy&&economy.claims,ledger=economy&&economy.ledger;
  if([purchases,claims,ledger].some(value=>value!=null&&!record(value)))return invalid();
  for(const kind of Object.keys(CHEST_CATALOG)){
    const sourceId=kind+':'+hash(requestId).slice(0,32),key=sourceClaimKey(uid,'chest_purchase',sourceId);
    const purchase=purchases&&purchases[key],rewardKey=sourceClaimKey(uid,'chest_reward',sourceId),claim=claims&&claims[rewardKey];
    if(purchase==null){if(claim!=null)return invalid();continue;}
    if(kind!==chestId)return {commit:false,error:'request-id-conflict'};
    if(!record(purchase)||!record(purchase.outcome))return invalid();
    const outcome=purchase.outcome,rewards=outcome.rewards,ids=outcome.rewardTransactionIds;
    const gold=validChestDrops(rewards)?rewards.filter(reward=>reward.type==='gold').reduce((sum,reward)=>sum+reward.amount,0):0;
    const transactionId='sp_'+hash([uid,'chest_purchase',sourceId,purchase.currency].join('|')).slice(0,40),spend=ledger&&ledger[transactionId];
    if(purchase.uid!==uid||purchase.idempotencyKey!==key||purchase.sourceType!=='chest_purchase'||purchase.sourceId!==sourceId||
      purchase.itemType!=='chest'||purchase.itemId!==chestId||!['gold','gems'].includes(purchase.currency)||
      !Number.isSafeInteger(purchase.price)||purchase.price<=0||purchase.price>1000000||
      !Number.isSafeInteger(purchase.purchasedAt)||purchase.purchasedAt<=0||purchase.transactionId!==transactionId||
      !record(spend)||spend.transactionId!==transactionId||spend.idempotencyKey!==key||spend.uid!==uid||
      spend.sourceType!=='chest_purchase'||spend.sourceId!==sourceId||spend.itemType!=='chest'||spend.itemId!==chestId||
      spend.rewardType!==purchase.currency||spend.amount!==-purchase.price||spend.createdAt!==purchase.purchasedAt||
      !Number.isSafeInteger(spend.previousBalance)||!Number.isSafeInteger(spend.newBalance)||spend.newBalance<0||
      spend.previousBalance-spend.newBalance!==purchase.price||gold<=0||
      !Array.isArray(ids)||ids.length===0||new Set(ids).size!==ids.length||!ids.every(value=>typeof value==='string'&&value.length>0)||
      !record(claim)||claim.idempotencyKey!==rewardKey||claim.sourceType!=='chest_reward'||claim.sourceId!==sourceId||
      !record(claim.reward)||claim.reward.gold!==gold||claim.claimedAt!==purchase.purchasedAt||
      JSON.stringify(claim.transactionIds)!==JSON.stringify(ids))return invalid();
    for(const rewardId of ids){
      const reward=ledger&&ledger[rewardId];
      if(!record(reward)||reward.transactionId!==rewardId||reward.uid!==uid||reward.idempotencyKey!==rewardKey||
        reward.sourceType!=='chest_reward'||reward.sourceId!==sourceId||reward.rewardType!=='gold'||reward.amount!==gold||
        reward.createdAt!==purchase.purchasedAt||!Number.isSafeInteger(reward.previousBalance)||reward.previousBalance<0||
        !Number.isSafeInteger(reward.newBalance)||reward.newBalance-reward.previousBalance!==gold)return invalid();
    }
    return {commit:false,idempotent:true,transactionId,outcome:{rewards:rewards.map(reward=>Object.assign({},reward)),rewardTransactionIds:ids.slice()}};
  }
  return null;
}
async function openChest(context){
  const {uid,body}=context;
  assertBodyKeys(body,['chestId']);
  const chestId=cleanString(body.chestId,32),definition=CHEST_CATALOG[chestId];
  if(!definition)throw httpError(400,'unknown-chest','Chest is not in the server catalog.');
  await rateLimit(uid,'openChest',40,60*1000);
  const response=await idempotent(uid,context.requestId,'openChest:'+chestId,async function(){
    const at=now(),sourceId=chestId+':'+hash(context.requestId).slice(0,32),seed=crypto.randomBytes(32).toString('hex');
    const result=await transactExistingPlayer(uid,function(profile){
      if(profile.uid!==uid)return {commit:false,error:'profile-owner-mismatch'};
      const replay=shopChestOpeningReplay(profile,uid,context.requestId,chestId);
      if(replay)return replay;
      if(billingReviewRequired(profile))return {commit:false,error:'billing-review-required'};
      if(!chestAvailability(profile,chestId).canPurchase)return {commit:false,error:'chest-collection-complete'};
      const purchase=applySoftPurchase(profile,{
        uid,sourceType:'chest_purchase',sourceId,itemType:'chest',itemId:chestId,
        currency:definition.currency,price:definition.price,at,
        grant:function(current){
          const rolled=rollChest(current,chestId,seed),rewards=applyChestInventoryRewards(current,rolled);
          const gold=rewards.reduce(function(total,reward){return total+(reward.type==='gold'?safeInt(reward.amount,0):0);},0);
          let rewardTransactionIds=[];
          if(gold>0){
            const grant=applyRewardClaim(current,{uid,sourceType:'chest_reward',sourceId,reward:{gold},at});
            if(!grant.granted)throw httpError(409,'chest-purchase-receipt-invalid','Chest reward receipt is inconsistent.');
            rewardTransactionIds=grant.transactionIds||[];
          }
          return {rewards,rewardTransactionIds};
        }
      });
      return Object.assign({commit:purchase.purchased},purchase);
    });
    if(result.decision.error)throw httpError(result.decision.error==='profile-owner-mismatch'?403:409,result.decision.error,'Chest purchase could not be confirmed.');
    const outcome=result.decision.outcome||{};
    return {ok:true,opened:result.committed,idempotent:result.decision.idempotent===true,chestId,rewards:outcome.rewards||[],transactionId:result.decision.transactionId||null,rewardTransactionIds:outcome.rewardTransactionIds||[],state:authoritativeState(result.profile,at)};
  });
  if(response.idempotent===true){
    const latest=(await db.ref(`users/${uid}`).get()).val();
    if(!latest)throw httpError(404,'profile-not-found','Player profile does not exist.');
    if(latest.uid!==uid)throw httpError(403,'profile-owner-mismatch','Player profile ownership does not match.');
    const replay=shopChestOpeningReplay(latest,uid,context.requestId,chestId);
    if(!replay||replay.error)throw httpError(409,replay&&replay.error||'chest-purchase-receipt-invalid','Chest purchase receipt could not be confirmed.');
    await assertAccountOperationAllowed(uid,'openChest');
    Object.assign(response,{ok:true,chestId,opened:false,transactionId:replay.transactionId,...replay.outcome,state:authoritativeState(latest,now())});
  }
  return response;
}
function passChestOpeningReplay(profile,uid,requestId,chestId){
  const economy=profile.serverEconomy,claims=economy&&economy.claims;
  const record=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
  if(economy!=null&&!record(economy)||claims!=null&&!record(claims))return {commit:false,error:'pass-chest-receipt-invalid'};
  const requestHash=hash(requestId);
  for(const kind of Object.keys(CHEST_CATALOG)){
    const sourceId='pass:'+kind+':'+requestHash.slice(0,32),claim=claims&&claims[sourceClaimKey(uid,'pass_chest_reward',sourceId)];
    if(claim==null)continue;
    if(kind!==chestId)return {commit:false,error:'request-id-conflict'};
    if(!record(claim))return {commit:false,error:'pass-chest-receipt-invalid'};
    const opening=claim.passChestOpening;
    if(opening==null)return {commit:false,error:'pass-chest-recovery-unavailable'};
    const rewards=opening.rewards,ids=claim.transactionIds;
    const validRewards=validChestDrops(rewards);
    const gold=validRewards?rewards.filter(reward=>reward.type==='gold').reduce((sum,reward)=>sum+reward.amount,0):0;
    if(!record(claim)||!record(opening)||opening.version!==1||opening.requestIdHash!==requestHash||opening.chestId!==chestId||
      opening.uidHash!==hash(uid)||claim.idempotencyKey!==sourceClaimKey(uid,'pass_chest_reward',sourceId)||claim.sourceType!=='pass_chest_reward'||claim.sourceId!==sourceId||
      !Number.isSafeInteger(claim.claimedAt)||claim.claimedAt<=0||!validRewards||!record(claim.reward)||claim.reward.gold!==gold||
      !Array.isArray(ids)||ids.length===0||!ids.every(value=>typeof value==='string'&&value.length>0)){
      return {commit:false,error:'pass-chest-receipt-invalid'};
    }
    return {commit:false,idempotent:true,outcome:{rewards:rewards.map(reward=>Object.assign({},reward)),rewardTransactionIds:ids.slice()}};
  }
  return null;
}
async function openPassChest(context){
  const {uid,body}=context;
  assertBodyKeys(body,['chestId']);
  const chestId=cleanString(body.chestId,32),definition=CHEST_CATALOG[chestId];
  if(!definition)throw httpError(400,'unknown-chest','Chest is not in the server catalog.');
  await rateLimit(uid,'openPassChest',40,60*1000);
  const response=await idempotent(uid,context.requestId,'openPassChest:'+chestId,async function(){
    const at=now(),sourceId='pass:'+chestId+':'+hash(context.requestId).slice(0,32),seed=crypto.randomBytes(32).toString('hex');
    const result=await transactExistingPlayer(uid,function(profile){
      if(profile.uid!==uid)return {commit:false,error:'profile-owner-mismatch'};
      const replay=passChestOpeningReplay(profile,uid,context.requestId,chestId);
      if(replay)return replay;
      const inventory=serverInventory(profile),pendingIndex=inventory.pendingChests.indexOf(chestId);
      if(pendingIndex<0)return {commit:false,error:'pass-chest-not-owned'};
      const rewards=applyChestInventoryRewards(profile,rollChest(profile,chestId,seed));
      const gold=rewards.reduce(function(total,reward){return total+(reward.type==='gold'?safeInt(reward.amount,0):0);},0);
      if(gold<=0)return {commit:false,error:'invalid-chest-reward'};
      const grant=applyRewardClaim(profile,{uid,sourceType:'pass_chest_reward',sourceId,reward:{gold},at});
      if(!grant.granted)return {commit:false,error:'pass-chest-receipt-invalid'};
      const rewardTransactionIds=grant.transactionIds||[];
      profile.serverEconomy.claims[grant.idempotencyKey].passChestOpening={version:1,chestId,uidHash:hash(uid),requestIdHash:hash(context.requestId),rewards};
      inventory.pendingChests.splice(pendingIndex,1);
      return {commit:true,outcome:{rewards,rewardTransactionIds}};
    });
    if(result.decision.error)throw httpError(result.decision.error==='profile-owner-mismatch'?403:409,result.decision.error,'Pass chest opening could not be confirmed.');
    const outcome=result.decision.outcome||{};
    return {ok:true,opened:result.committed,idempotent:result.decision.idempotent===true,chestId,rewards:outcome.rewards||[],rewardTransactionIds:outcome.rewardTransactionIds||[],state:authoritativeState(result.profile,at)};
  });
  if(response.idempotent===true){
    const latest=(await db.ref(`users/${uid}`).get()).val();
    if(!latest)throw httpError(404,'profile-not-found','Player profile does not exist.');
    if(latest.uid!==uid)throw httpError(403,'profile-owner-mismatch','Player profile ownership does not match.');
    await assertAccountOperationAllowed(uid,'openPassChest');
    response.state=authoritativeState(latest,now());
  }
  return response;
}
async function targetPlayer(value,uid){
  const targetUid=cleanString(value,128);
  if(!validUid(targetUid)||targetUid===uid)throw httpError(400,'invalid-target','Player target is invalid.');
  const profile=(await db.ref(`users/${targetUid}`).get()).val();
  if(!profile)throw httpError(404,'target-not-found','Target player does not exist.');
  return {targetUid,profile};
}
async function friendshipState(uid,targetUid){
  const snapshots=await Promise.all([
    db.ref(`friends/${uid}/${targetUid}`).get(),
    db.ref(`friends/${targetUid}/${uid}`).get(),
    db.ref(`outgoingFriendRequests/${uid}/${targetUid}`).get(),
    db.ref(`friendRequests/${uid}/${targetUid}`).get(),
  ]);
  const ownFriend=snapshots[0].exists(),reciprocalFriend=snapshots[1].exists();
  if(ownFriend||reciprocalFriend)return {status:'friends',mutual:ownFriend&&reciprocalFriend};
  if(snapshots[2].exists())return {status:'outgoing',mutual:false};
  if(snapshots[3].exists())return {status:'incoming',mutual:false};
  return {status:'none',mutual:false};
}
async function interactionBlocked(uid,targetUid){
  const snapshots=await Promise.all([db.ref(`blocks/${uid}/${targetUid}`).get(),db.ref(`blocks/${targetUid}/${uid}`).get()]);
  return snapshots[0].exists()||snapshots[1].exists();
}
async function assertInteractionAllowed(uid,targetUid){
  if(await interactionBlocked(uid,targetUid))throw httpError(403,'user-blocked','Interaction is blocked between these players.');
}
function publicPlayerResult(uid,profile){
  // Private collection rows need the same projection as the public mirror.
  if(profile.stats&&typeof profile.stats==='object')profile=publicProfile(Object.assign({},profile,{uid}),now());
  const username=canonicalUsername(profile,uid);
  const collectionScore=profile&&profile.unlockedCards&&typeof profile.unlockedCards==='object'
    ?collectionScoreForProfile(profile):safeInt(profile&&profile.collectionScore,0);
  return {
    uid,
    name:username,
    username,
    usernameRevision:usernameRevision(profile),
    playerCode:cleanString(profile.playerCode||playerCode(uid),13),
    country:cleanString(profile.country||'TR',2),
    avatar:cleanString(profile.avatar||'#e8b840',16),
    avatarEmoji:cleanString(profile.avatarEmoji||'&#9818;',32),
    bio:safePublicBio(profile.bio),
    photoURL:profile.photoURL||null,
    trophies:safeInt(profile.trophies,0),collectionScore,
    seasonScore:safeInt(profile.seasonScore,0),wins:safeInt(profile.wins,0),arenaIdx:arenaIndexForProfile(profile),lvl:safeInt(profile.lvl,1),
    gamesPlayed:Math.max(safeInt(profile.wins,0),safeInt(profile.gamesPlayed,0)),
    isPremium:profile.isPremium===true,dmFriendsOnly:profile.dmFriendsOnly===true
  };
}

function normalizeLeaderboardLimit(value){
  const parsed=Number(value);
  if(!Number.isSafeInteger(parsed)||parsed<1)return LEADERBOARD_MAX_LIMIT;
  return Math.min(parsed,LEADERBOARD_MAX_LIMIT);
}
function leaderboardRows(profiles,mode,limit,selfUid){
  const field=LEADERBOARD_FIELDS[mode];
  if(!field)throw httpError(400,'invalid-leaderboard-mode','Leaderboard mode is invalid.');
  const cap=normalizeLeaderboardLimit(limit),rows=[];
  Object.keys(profiles||{}).forEach(function(uid){
    const profile=profiles[uid];
    if(!profile||!canonicalUsername(profile,uid))return;
    const row=publicPlayerResult(uid,profile);
    row.isMe=uid===selfUid;rows.push(row);
  });
  rows.sort(function(left,right){
    const score=safeInt(right[field],0)-safeInt(left[field],0);
    if(score)return score;
    const leftName=String(left.username||left.name||'');
    const rightName=String(right.username||right.name||'');
    if(leftName<rightName)return -1;
    if(leftName>rightName)return 1;
    return String(left.uid)<String(right.uid)?-1:String(left.uid)>String(right.uid)?1:0;
  });
  return rows.slice(0,cap);
}
async function getLeaderboard(context){
  const {uid,body}=context;
  assertBodyKeys(body,['mode','limit','protocolVersion']);
  const v1=validatePublicBattleProtocol(body);
  const mode=cleanString(body.mode||'trophies',20),field=LEADERBOARD_FIELDS[mode];
  if(!field)throw httpError(400,'invalid-leaderboard-mode','Leaderboard mode is invalid.');
  const limit=normalizeLeaderboardLimit(body.limit);
  await rateLimit(uid,'getLeaderboard',30,60*1000);
  await requirePlayer(uid);
  if(v1&&mode==='trophies')return getBattleV1Leaderboard(uid,limit);
  // Collection score is derived from the private authoritative card unlocks;
  // never order that leaderboard by a stale or missing public mirror field.
  const leaderboardRef=mode==='collection'?db.ref('users'):db.ref('publicProfiles').orderByChild(field).limitToLast(limit);
  const snapshot=await leaderboardRef.get();
  const results=leaderboardRows(snapshot.val()||{},mode,limit,uid);
  const ownIndex=results.findIndex(function(player){return player.uid===uid;});
  return {ok:true,mode,limit,results,myRank:ownIndex<0?0:ownIndex+1,totalPlayers:results.length,hasMore:results.length===limit};
}

function validatePublicBattleProtocol(body){
  if(!Object.hasOwn(body,'protocolVersion'))return false;
  if(body.protocolVersion!==BATTLE_V1_PROTOCOL)throw httpError(400,'INCOMPATIBLE_PROTOCOL','Battle protocol is invalid.');
  return true;
}
async function readBattleV1PublicPlayer(uid,targetUid){
  if(!validUid(targetUid))return null;
  try{await assertAccountOperationAllowed(targetUid,'getPublicPlayerProfile');}
  catch(error){if(isAccountDeletionError(error))return null;throw error;}
  if(uid!==targetUid&&await interactionBlocked(uid,targetUid))return null;
  const [current,mirror]=await Promise.all([
    db.ref(`users/${targetUid}`).get(),db.ref(`publicProfiles/${targetUid}`).get()
  ]);
  const profile=current.val(),publicIdentity=mirror.val();
  if(!profile||profile.uid!==targetUid||publicIdentity&&Object.hasOwn(publicIdentity,'uid')&&publicIdentity.uid!==targetUid)return null;
  // Current owner-checked identity wins over stale names in rating/public mirrors.
  const row=publicPlayerResult(targetUid,profile),battleV1Rank=await readBattleV1Rank(db,targetUid);
  if(typeof row.photoURL!=='string')row.photoURL=null;
  try{await assertAccountOperationAllowed(targetUid,'getPublicPlayerProfile');}
  catch(error){if(isAccountDeletionError(error))return null;throw error;}
  if(uid!==targetUid&&await interactionBlocked(uid,targetUid))return null;
  return Object.assign(row,{battleV1Rank});
}
async function getPublicPlayerProfile(context){
  const {uid,body}=context;
  assertBodyKeys(body,['targetUid','protocolVersion']);validatePublicBattleProtocol(body);
  const targetUid=body.targetUid;
  if(typeof targetUid!=='string'||!validUid(targetUid))throw httpError(400,'invalid-target','Player target is invalid.');
  await rateLimit(uid,'getPublicPlayerProfile',60,60*1000);
  await assertAccountOperationAllowed(uid,'getPublicPlayerProfile');
  const owner=await requirePlayer(uid);
  if(owner.uid!==uid)throw httpError(403,'profile-owner-mismatch','Player profile ownership does not match.');
  const profile=await readBattleV1PublicPlayer(uid,targetUid);
  await assertAccountOperationAllowed(uid,'getPublicPlayerProfile');
  if(!profile)throw httpError(404,'target-not-found','Target player does not exist.');
  return {ok:true,profile};
}
async function getPublicPlayerProfiles(context){
  const {uid,body}=context;
  assertBodyKeys(body,['targetUids','protocolVersion']);validatePublicBattleProtocol(body);
  const targetUids=body.targetUids;
  if(!Array.isArray(targetUids)||targetUids.length>50||
    targetUids.some(targetUid=>typeof targetUid!=='string'||!validUid(targetUid))||
    new Set(targetUids).size!==targetUids.length){
    throw httpError(400,'invalid-targets','At most 50 distinct valid player UIDs are required.');
  }
  await rateLimit(uid,'getPublicPlayerProfiles',60,60*1000);
  await assertAccountOperationAllowed(uid,'getPublicPlayerProfiles');
  const owner=await requirePlayer(uid);
  if(owner.uid!==uid)throw httpError(403,'profile-owner-mismatch','Player profile ownership does not match.');
  const rows=(await readBattleV1PublicPlayers(uid,targetUids)).map(profile=>activeBattleV1PublicPlayer(profile,uid));
  return {ok:true,protocolVersion:BATTLE_V1_PROTOCOL,
    results:await filterBattleV1PublicRows(uid,rows,'getPublicPlayerProfiles')};
}
async function readBattleV1PublicPlayers(uid,targetUids){
  const rows=[];
  // Bound database fan-out while preserving the requested roster order.
  for(let index=0;index<targetUids.length;index+=8){
    const batch=await Promise.all(targetUids.slice(index,index+8).map(targetUid=>readBattleV1PublicPlayer(uid,targetUid)));
    rows.push(...batch.filter(Boolean));
  }
  return rows;
}
async function filterBattleV1PublicRows(uid,rows,route){
  const visible=[];
  for(const row of rows){
    try{await assertAccountOperationAllowed(row.uid,route);}
    catch(error){if(isAccountDeletionError(error))continue;throw error;}
    if(uid!==row.uid&&await interactionBlocked(uid,row.uid))continue;
    visible.push(row);
  }
  await assertAccountOperationAllowed(uid,route);
  return visible;
}
async function getBattleV1Leaderboard(uid,limit){
  await assertAccountOperationAllowed(uid,'getLeaderboard');
  const owner=await requirePlayer(uid);
  if(owner.uid!==uid)throw httpError(403,'profile-owner-mismatch','Player profile ownership does not match.');
  const snapshot=await db.ref('battleV1Ratings').orderByChild('rating').limitToLast(limit).get();
  const indexed=snapshot.val()||{};
  const targetUids=Object.keys(indexed).filter(targetUid=>validBattleV1Rating(targetUid,indexed[targetUid]));
  const results=(await readBattleV1PublicPlayers(uid,targetUids)).map(profile=>activeBattleV1PublicPlayer(profile,uid));
  results.sort((a,b)=>b.trophies-a.trophies||a.username.localeCompare(b.username)||a.uid.localeCompare(b.uid));
  // Recheck privacy after the bounded batch, not only before each row's reads.
  const visible=await filterBattleV1PublicRows(uid,results,'getLeaderboard');
  const ownIndex=visible.findIndex(player=>player.uid===uid);
  return {ok:true,mode:'trophies',protocolVersion:BATTLE_V1_PROTOCOL,limit,results:visible,
    myRank:ownIndex<0?0:ownIndex+1,totalPlayers:visible.length,hasMore:Object.keys(indexed).length===limit};
}
function activeBattleV1PublicPlayer(profile,uid){
  return Object.assign(profile,{trophies:profile.battleV1Rank.trophies,
    arenaIdx:profile.battleV1Rank.arenaIdx,isMe:profile.uid===uid});
}
function isFriendEdge(value){return value===true||!!value&&typeof value==='object'&&!Array.isArray(value);}
function friendPageToken(uid,key){
  const token=Buffer.from(JSON.stringify({v:1,uid,key}),'utf8').toString('base64url');
  if(token.length>2048)throw httpError(503,'friend-pagination-unavailable','Friend pagination is unavailable.');
  return token;
}
function parseFriendPageToken(value,uid){
  const invalid=()=>httpError(400,'invalid-page-token','Friend page token is invalid.');
  if(typeof value!=='string'||value.length<1||value.length>2048||!/^[A-Za-z0-9_-]+$/.test(value))throw invalid();
  const bytes=Buffer.from(value,'base64url');
  if(bytes.toString('base64url')!==value)throw invalid();
  let token;try{token=JSON.parse(bytes.toString('utf8'));}catch(_){throw invalid();}
  if(!token||typeof token!=='object'||Array.isArray(token)||Object.keys(token).sort().join(',')!=='key,uid,v'||
    token.v!==1||token.uid!==uid||typeof token.key!=='string'||token.key.length<1||
    Buffer.byteLength(token.key,'utf8')>768||Buffer.from(token.key,'utf8').toString('utf8')!==token.key||
    /[.#$\[\]\/\u0000-\u001f\u007f]/.test(token.key))throw invalid();
  return token.key;
}
async function getFriends(context){
  const {uid,body}=context;
  assertBodyKeys(body,['protocolVersion','pageToken']);validatePublicBattleProtocol(body);
  const cursor=Object.hasOwn(body,'pageToken')?parseFriendPageToken(body.pageToken,uid):null;
  await rateLimit(uid,'getFriends',60,60*1000);
  await assertAccountOperationAllowed(uid,'getFriends');
  const owner=await requirePlayer(uid);
  if(owner.uid!==uid)throw httpError(403,'profile-owner-mismatch','Player profile ownership does not match.');
  let query=db.ref(`friends/${uid}`).orderByKey();
  if(cursor!==null)query=query.startAfter(cursor);
  const page=await query.limitToFirst(100).get(),edges=[],results=[];
  page.forEach(child=>{edges.push({uid:child.key,value:child.val()});return false;});
  let nextPageToken=null;
  if(edges.length===100){
    const lastKey=edges.at(-1).uid;
    const further=await db.ref(`friends/${uid}`).orderByKey().startAfter(lastKey).limitToFirst(1).get();
    if(further.exists())nextPageToken=friendPageToken(uid,lastKey);
  }
  const targetUids=edges.filter(edge=>validUid(edge.uid)&&edge.uid!==uid&&isFriendEdge(edge.value)).map(edge=>edge.uid);
  for(const profile of await readBattleV1PublicPlayers(uid,targetUids)){
    const targetUid=profile.uid;
    const [friend,presence]=await Promise.all([
      db.ref(`friends/${uid}/${targetUid}`).get(),db.ref(`presence/${targetUid}`).get()
    ]);
    if(!isFriendEdge(friend.val()))continue;
    const activity=presence.val()||{};
    results.push(Object.assign(activeBattleV1PublicPlayer(profile,uid),{online:activity.online===true,lastSeen:safeInt(activity.lastSeen,0)}));
  }
  const visible=[];
  for(const row of results){
    try{await assertAccountOperationAllowed(row.uid,'getFriends');}
    catch(error){if(isAccountDeletionError(error))continue;throw error;}
    if(await interactionBlocked(uid,row.uid)||!isFriendEdge((await db.ref(`friends/${uid}/${row.uid}`).get()).val()))continue;
    visible.push(row);
  }
  await assertAccountOperationAllowed(uid,'getFriends');
  return {ok:true,protocolVersion:BATTLE_V1_PROTOCOL,results:visible,nextPageToken};
}

async function searchPlayers(context){
  const {uid,body}=context;
  assertBodyKeys(body,['query','protocolVersion']);
  const v1=validatePublicBattleProtocol(body);
  const query=normalizeUsername(strictString(body.query,24,'invalid-query'));
  if(query.length<3||!/^(?:[a-z0-9_]{3,16}|luno-[a-f0-9]{3,8})$/.test(query))throw httpError(400,'invalid-query','Search requires a username or Luno player code.');
  await rateLimit(uid,'searchPlayers',20,60*1000);
  await requirePlayer(uid);
  const candidates=new Map();
  if(query.startsWith('luno-')){
    const codeUid=(await db.ref(`playerCodes/${query}`).get()).val();
    if(validUid(codeUid)){
      const profile=(await db.ref(`publicProfiles/${codeUid}`).get()).val();
      if(profile)candidates.set(codeUid,profile);
    }
  }else{
    const snapshot=await db.ref('publicProfiles').orderByChild('username').startAt(query).endAt(query+'\uf8ff').limitToFirst(10).get();
    const profiles=snapshot.val()||{};
    Object.keys(profiles).forEach(function(targetUid){candidates.set(targetUid,profiles[targetUid]);});
  }
  const ownBlocks=(await db.ref(`blocks/${uid}`).get()).val()||{},blockedBy=(await db.ref(`blockedBy/${uid}`).get()).val()||{},results=[];
  for(const [targetUid,profile] of candidates){
    if(targetUid===uid||ownBlocks[targetUid]||blockedBy[targetUid])continue;
    const projected=v1?await readBattleV1PublicPlayer(uid,targetUid):publicPlayerResult(targetUid,profile);
    if(!projected)continue;
    const relationship=await friendshipState(uid,targetUid);
    results.push(Object.assign(v1?activeBattleV1PublicPlayer(projected,uid):projected,{relationship:relationship.status}));
    if(results.length===10)break;
  }
  if(v1){
    return {protocolVersion:BATTLE_V1_PROTOCOL,results:await filterBattleV1PublicRows(uid,results,'searchPlayers'),nextPageToken:null};
  }
  return {results,nextPageToken:null};
}
async function removeBattleV1Invites(uid,targetUid){
  await db.ref('battleV1Control/invites').transaction(function(value){
    if(value===null)return null;
    const invites=Object.assign({},value);
    delete invites[uid+'|'+targetUid];delete invites[targetUid+'|'+uid];
    return invites;
  },undefined,false);
}
async function blockUser(context){
  const {uid,body}=context;
  assertBodyKeys(body,['targetUid']);
  await rateLimit(uid,'blockUser',20,60*1000);
  const target=await targetPlayer(body.targetUid,uid),targetUid=target.targetUid;
  return idempotent(uid,context.requestId,'blockUser:'+targetUid,async function(){
    return withSocialPairMetadata(uid,targetUid,async function(){
      const updates={};
      updates[`blocks/${uid}/${targetUid}`]={createdAt:ServerValue.TIMESTAMP};updates[`blockedBy/${targetUid}/${uid}`]=true;
      updates[`friends/${uid}/${targetUid}`]=null;updates[`friends/${targetUid}/${uid}`]=null;
      updates[`friendRequests/${uid}/${targetUid}`]=null;updates[`friendRequests/${targetUid}/${uid}`]=null;
      updates[`outgoingFriendRequests/${uid}/${targetUid}`]=null;updates[`outgoingFriendRequests/${targetUid}/${uid}`]=null;
      updates[`matchInvites/${uid}/${targetUid}`]=null;updates[`matchInvites/${targetUid}/${uid}`]=null;
      updates[`matchInviteThrottle/${uid}/${targetUid}`]=null;updates[`matchInviteThrottle/${targetUid}/${uid}`]=null;
      updates[`dmInbox/${uid}/${targetUid}`]=null;updates[`dmInbox/${targetUid}/${uid}`]=null;
      updates[`mutes/${uid}/${targetUid}`]=null;updates[`mutes/${targetUid}/${uid}`]=null;
      await removeBattleV1Invites(uid,targetUid);
      await db.ref().update(updates);
      return {blocked:true,targetUid};
    });
  });
}
async function unblockUser(context){
  const {uid,body}=context;
  assertBodyKeys(body,['targetUid']);
  await rateLimit(uid,'unblockUser',20,60*1000);
  const targetUid=strictString(body.targetUid,128,'invalid-target');
  if(!validUid(targetUid)||targetUid===uid)throw httpError(400,'invalid-target','Player target is invalid.');
  await requirePlayer(uid);
  return idempotent(uid,context.requestId,'unblockUser:'+targetUid,async function(){
    return withSocialPairLock(uid,targetUid,async function(){
      const updates={};updates[`blocks/${uid}/${targetUid}`]=null;updates[`blockedBy/${targetUid}/${uid}`]=null;
      await db.ref().update(updates);return {blocked:false,targetUid};
    });
  });
}
async function listBlockedUsers(context){
  const {uid,body}=context;
  assertBodyKeys(body,['pageToken']);
  const invalidToken=()=>httpError(400,'invalid-page-token','Blocked-list page token is invalid.');
  let cursor=null;
  if(Object.hasOwn(body,'pageToken')){
    const raw=body.pageToken;
    if(typeof raw!=='string'||raw.length<1||raw.length>512||!/^[A-Za-z0-9_-]+$/.test(raw))throw invalidToken();
    const bytes=Buffer.from(raw,'base64url');
    if(bytes.toString('base64url')!==raw)throw invalidToken();
    let token;try{token=JSON.parse(bytes.toString('utf8'));}catch(_){throw invalidToken();}
    if(!token||typeof token!=='object'||Array.isArray(token)||Object.keys(token).sort().join(',')!=='after,scope,uid,v'||
      token.v!==1||token.scope!=='blocked-users'||token.uid!==uid||typeof token.after!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(token.after))throw invalidToken();
    cursor=token.after;
  }
  await rateLimit(uid,'listBlockedUsers',60,60*1000);
  const owner=await requirePlayer(uid);
  if(owner.uid!==uid)throw httpError(403,'profile-owner-mismatch','Player profile ownership does not match.');
  const root=db.ref(`blocks/${uid}`);
  let query=root.orderByKey();if(cursor!==null)query=query.startAfter(cursor);
  const snapshot=await query.limitToFirst(25).get(),edges=[];
  snapshot.forEach(child=>{edges.push({uid:child.key,value:child.val()});return false;});
  let nextPageToken=null;
  if(edges.length===25){
    const last=edges.at(-1).uid;
    if(typeof last!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(last))throw httpError(503,'blocked-pagination-unavailable','Blocked-list ordering is unavailable.');
    if((await root.orderByKey().startAfter(last).limitToFirst(1).get()).exists()){
      nextPageToken=Buffer.from(JSON.stringify({v:1,scope:'blocked-users',uid,after:last}),'utf8').toString('base64url');
    }
  }
  const isBlock=value=>value===true||!!value&&typeof value==='object'&&!Array.isArray(value);
  const targetUids=edges.filter(edge=>validUid(edge.uid)&&edge.uid!==uid&&isBlock(edge.value)).map(edge=>edge.uid);
  const results=[];
  // Keep database fan-out small; never disclose private target profile fields.
  for(let offset=0;offset<targetUids.length;offset+=5){
    const rows=await Promise.all(targetUids.slice(offset,offset+5).map(async targetUid=>{
      const [publicSnapshot,playerSnapshot,edge]=await Promise.all([
        db.ref(`publicProfiles/${targetUid}`).get(),db.ref(`users/${targetUid}`).get(),root.child(targetUid).get()
      ]);
      if(!isBlock(edge.val()))return null;
      const profile=publicSnapshot.val(),player=playerSnapshot.val();
      let unavailable=!profile||typeof profile!=='object'||Array.isArray(profile)||!player||player.uid!==targetUid;
      try{await assertAccountOperationAllowed(targetUid,'listBlockedUsers');}
      catch(error){if(isAccountDeletionError(error))unavailable=true;else throw error;}
      if(unavailable)return {uid:targetUid,name:'Silinmiş oyuncu',username:'',unavailable:true};
      const projected=publicPlayerResult(targetUid,profile);
      return {uid:targetUid,name:projected.name,username:projected.username};
    }));
    results.push(...rows.filter(Boolean));
  }
  const visible=[];
  for(const row of results){
    if(!isBlock((await root.child(row.uid).get()).val()))continue;
    try{await assertAccountOperationAllowed(row.uid,'listBlockedUsers');}
    catch(error){
      if(!isAccountDeletionError(error))throw error;
      visible.push({uid:row.uid,name:'Silinmiş oyuncu',username:'',unavailable:true});continue;
    }
    visible.push(row);
  }
  await assertAccountOperationAllowed(uid,'listBlockedUsers');
  return {results:visible,nextPageToken};
}
function reportReason(value){
  const reason=cleanString(value,32).toLowerCase();
  if(!REPORT_REASONS.has(reason))throw httpError(400,'invalid-report-reason','Report reason is invalid.');
  return reason;
}
function reportId(uid,requestIdValue){return 'rp_'+hash(uid+':'+requestIdValue).slice(0,30);}
async function writeModerationReport(entry){
  const owners=[...new Set([entry.reporterUid,entry.targetUid])],ref=db.ref(`moderationReports/${entry.reportId}`);
  for(const uid of owners)await assertAccountOperationAllowed(uid,'writeModerationReport');
  try{
    const result=await ref.transaction(function(value){
      if(value===null)return entry;
      if(value.reporterUid!==entry.reporterUid||value.targetUid!==entry.targetUid||value.anonymizedAt!=null||value.reporterDeleted===true||value.targetDeleted===true)return;
      return value;
    },undefined,false);
    if(!result.committed)throw httpError(409,'report-id-conflict','Report ownership changed.');
    for(const uid of owners)await assertAccountOperationAllowed(uid,'writeModerationReport');
    return result.snapshot.val();
  }catch(error){
    // Check each owner separately: deleting the target must not retire a live reporter.
    let deletionError=null;
    for(const uid of owners){
      try{await assertAccountOperationAllowed(uid,'writeModerationReport');}
      catch(gateError){
        if(!isAccountDeletionError(gateError))throw gateError;
        await anonymizeModerationReport(uid,entry.reportId);deletionError=deletionError||gateError;
      }
    }
    throw deletionError||error;
  }
}
async function reportUser(context){
  const {uid,body}=context;
  assertBodyKeys(body,['targetUid','reason','details']);
  await rateLimit(uid,'reportUser',8,60*60*1000);
  const target=await targetPlayer(body.targetUid,uid),reason=reportReason(body.reason),details=body.details==null?'':strictString(body.details,300,'invalid-report-details');
  return idempotent(uid,context.requestId,'reportUser',async function(){
    const id=reportId(uid,context.requestId);
    await writeModerationReport({reportId:id,reporterUid:uid,targetUid:target.targetUid,messageId:null,reason,details,createdAt:ServerValue.TIMESTAMP,status:'open'});
    return {reported:true,reportId:id};
  });
}
async function reportMessage(context){
  const {uid,body}=context;
  assertBodyKeys(body,['targetUid','messageId','reason']);
  await rateLimit(uid,'reportMessage',8,60*60*1000);
  const target=await targetPlayer(body.targetUid,uid),messageId=strictString(body.messageId,128,'invalid-message-id'),reason=reportReason(body.reason);
  if(/[.#$\[\]\/]/.test(messageId))throw httpError(400,'invalid-message-id','Message id is invalid.');
  const conversation=conversationId(uid,target.targetUid),message=(await db.ref(`dm/${conversation}/msgs/${messageId}`).get()).val();
  if(!message||message.from!==target.targetUid)throw httpError(404,'message-not-found','Reported message does not exist for this conversation.');
  return idempotent(uid,context.requestId,'reportMessage',async function(){
    const id=reportId(uid,context.requestId);
    await writeModerationReport({reportId:id,reporterUid:uid,targetUid:target.targetUid,messageId,conversationId:conversation,reason,messageText:cleanString(message.text,500),createdAt:ServerValue.TIMESTAMP,status:'open'});
    return {reported:true,reportId:id};
  });
}
async function setConversationMuted(context){
  const {uid,body}=context;
  assertBodyKeys(body,['targetUid','muted']);
  await rateLimit(uid,'setConversationMuted',30,60*1000);
  const target=await targetPlayer(body.targetUid,uid),muted=body.muted===true;
  return withSocialPairMetadata(uid,target.targetUid,async function(){
    await db.ref(`mutes/${uid}/${target.targetUid}`).set(muted?{mutedAt:ServerValue.TIMESTAMP}:null);
    return {muted,targetUid:target.targetUid};
  });
}
async function enforceDirectMessageCooldown(uid,targetUid,text,at){
  const ref=db.ref(`messageThrottle/${uid}/${targetUid}`),textHash=hash(text),decision={reason:''};
  const result=await ref.transaction(function(value){
    value=value||{};const lastAt=safeInt(value.at,0),attemptAt=safeInt(value.attemptAt,lastAt);
    if(attemptAt&&at-attemptAt<DM_COOLDOWN_MS){decision.reason='message-rate-limited';return;}
    if(value.textHash===textHash&&lastAt&&at-lastAt<30000){decision.reason='duplicate-message';return;}
    // Throttle attempts without reserving text that privacy or ownership may reject.
    decision.reason='';return Object.assign({},value,{attemptAt:at});
  });
  if(!result.committed)throw httpError(429,decision.reason||'message-rate-limited','Messages are being sent too quickly.');
}
async function sendFriendRequest(context){
  const {uid,body}=context;
  assertBodyKeys(body,['targetUid']);
  await rateLimit(uid,'sendFriendRequest',10,60*1000);
  const sender=await requirePlayer(uid),senderName=canonicalUsername(sender,uid),target=await targetPlayer(body.targetUid,uid),targetUid=target.targetUid;
  return idempotent(uid,context.requestId,'sendFriendRequest',async function(){
    return withSocialPairMetadata(uid,targetUid,async function(){
      await assertInteractionAllowed(uid,targetUid);
      const relation=await friendshipState(uid,targetUid);
      if(relation.status==='friends'){
        if(!relation.mutual){
          const repair={};
          repair[`friends/${uid}/${targetUid}`]={addedAt:ServerValue.TIMESTAMP};
          repair[`friends/${targetUid}/${uid}`]={addedAt:ServerValue.TIMESTAMP};
          await db.ref().update(repair);
        }
        return {ok:true,status:'friends'};
      }
      if(relation.status==='outgoing')return {ok:true,status:'pending'};
      if(relation.status==='incoming'){
        const updates={};
        updates[`friends/${uid}/${targetUid}`]={addedAt:ServerValue.TIMESTAMP};
        updates[`friends/${targetUid}/${uid}`]={addedAt:ServerValue.TIMESTAMP};
        updates[`friendRequests/${uid}/${targetUid}`]=null;
        updates[`friendRequests/${targetUid}/${uid}`]=null;
        updates[`outgoingFriendRequests/${uid}/${targetUid}`]=null;
        updates[`outgoingFriendRequests/${targetUid}/${uid}`]=null;
        updates[`notifications/${targetUid}/${db.ref().push().key}`]={type:'friend_accepted',fromUid:uid,fromName:senderName,fromUsername:senderName,message:senderName+' arkadaşlık isteğini kabul etti.',read:false,ts:ServerValue.TIMESTAMP};
        await db.ref().update(updates);
        return {ok:true,status:'accepted'};
      }
      const request={fromUid:uid,fromName:senderName,fromUsername:senderName,fromAvatar:cleanString(sender.avatarEmoji,32),fromCountry:cleanString(sender.country||'TR',2),fromTrophies:safeInt(sender.trophies,0),sentAt:ServerValue.TIMESTAMP};
      const updates={};
      updates[`friendRequests/${targetUid}/${uid}`]=request;
      updates[`outgoingFriendRequests/${uid}/${targetUid}`]={sentAt:ServerValue.TIMESTAMP};
      updates[`notifications/${targetUid}/${db.ref().push().key}`]={type:'friend_request',fromUid:uid,fromName:senderName,fromUsername:senderName,message:senderName+' sana arkadaşlık isteği gönderdi.',read:false,ts:ServerValue.TIMESTAMP};
      await db.ref().update(updates);
      return {ok:true,status:'sent'};
    });
  });
}
async function respondFriendRequest(context){
  const {uid,body}=context;
  assertBodyKeys(body,['fromUid','accept']);
  if(typeof body.accept!=='boolean')throw httpError(400,'invalid-request-response','Friend request response must be true or false.');
  await rateLimit(uid,'respondFriendRequest',20,60*1000);
  const from=await targetPlayer(body.fromUid,uid),fromUid=from.targetUid;
  return idempotent(uid,context.requestId,'respondFriendRequest:'+fromUid,async function(){
    return withSocialPairMetadata(uid,fromUid,async function(){
      await assertInteractionAllowed(uid,fromUid);
      const request=(await db.ref(`friendRequests/${uid}/${fromUid}`).get()).val();
      if(!request)throw httpError(404,'request-not-found','Friend request does not exist.');
      const accept=body.accept,updates={};
      updates[`friendRequests/${uid}/${fromUid}`]=null;
      updates[`friendRequests/${fromUid}/${uid}`]=null;
      updates[`outgoingFriendRequests/${fromUid}/${uid}`]=null;
      updates[`outgoingFriendRequests/${uid}/${fromUid}`]=null;
      if(accept){
        const accepter=await requirePlayer(uid),accepterName=canonicalUsername(accepter,uid);
        updates[`friends/${uid}/${fromUid}`]={addedAt:ServerValue.TIMESTAMP};
        updates[`friends/${fromUid}/${uid}`]={addedAt:ServerValue.TIMESTAMP};
        updates[`notifications/${fromUid}/${db.ref().push().key}`]={type:'friend_accepted',fromUid:uid,fromName:accepterName,fromUsername:accepterName,message:accepterName+' arkadaşlık isteğini kabul etti.',read:false,ts:ServerValue.TIMESTAMP};
      }
      await db.ref().update(updates);
      return {ok:true,accepted:accept};
    });
  });
}
async function removeFriend(context){
  const {uid,body}=context;
  assertBodyKeys(body,['targetUid']);
  await rateLimit(uid,'removeFriend',20,60*1000);
  const target=await targetPlayer(body.targetUid,uid),targetUid=target.targetUid;
  return idempotent(uid,context.requestId,'removeFriend:'+targetUid,async function(){
    return withSocialPairLock(uid,targetUid,async function(){
      const updates={};
      updates[`friends/${uid}/${targetUid}`]=null;updates[`friends/${targetUid}/${uid}`]=null;
      updates[`friendRequests/${uid}/${targetUid}`]=null;updates[`friendRequests/${targetUid}/${uid}`]=null;
      updates[`outgoingFriendRequests/${uid}/${targetUid}`]=null;updates[`outgoingFriendRequests/${targetUid}/${uid}`]=null;
      updates[`matchInvites/${uid}/${targetUid}`]=null;updates[`matchInvites/${targetUid}/${uid}`]=null;
      updates[`matchInviteThrottle/${uid}/${targetUid}`]=null;updates[`matchInviteThrottle/${targetUid}/${uid}`]=null;
      await removeBattleV1Invites(uid,targetUid);
      await db.ref().update(updates);
      return {ok:true,removed:true};
    });
  });
}
async function markNotificationRead(context){
  const {uid,body}=context;
  assertBodyKeys(body,['notificationId']);
  const notificationId=strictString(body.notificationId,128,'invalid-notification-id');
  if(!/^[A-Za-z0-9_-]+$/.test(notificationId))throw httpError(400,'invalid-notification-id','Notification id is invalid.');
  await rateLimit(uid,'markNotificationRead',120,60*1000);
  await requirePlayer(uid);
  const ref=db.ref(`notifications/${uid}/${notificationId}`),snapshot=await ref.get();
  if(!snapshot.exists())return {ok:true,updated:false};
  let updated=false;
  const result=await ref.transaction(function(value){
    updated=false;
    if(value===null)return null;
    updated=true;
    return Object.assign({},value,{read:true,readAt:ServerValue.TIMESTAMP});
  },undefined,false);
  return {ok:true,updated:result.committed===true&&updated};
}
async function requireFriendship(uid,targetUid){
  const snapshots=await Promise.all([db.ref(`friends/${uid}/${targetUid}`).get(),db.ref(`friends/${targetUid}/${uid}`).get()]);
  if(!snapshots[0].exists()||!snapshots[1].exists())throw httpError(403,'friend-required','Friendly match invitations can only be sent to friends.');
}
async function hasLiveRankedQueue(uid,at){
  const ref=db.ref(`rankedState/queue/${uid}`),value=(await ref.get()).val(),timestamp=safeInt(at,now());
  const seen=safeInt(value&& (value.lastSeenAt||value.joinedAt),0);
  if(value&&value.uid===uid&&seen>0&&timestamp-seen<=RANKED_QUEUE_TTL_MS)return true;
  if(value&&seen>0&&timestamp-seen>RANKED_QUEUE_TTL_MS){
    await ref.transaction(function(current){
      const currentSeen=safeInt(current&& (current.lastSeenAt||current.joinedAt),0);
      return current&&currentSeen===seen?null:undefined;
    }).catch(function(){});
  }
  return false;
}
async function hasOpenFriendlyRoom(uid,at){
  const mappingRef=db.ref(`friendlyRoomByUser/${uid}`),roomCode=cleanString((await mappingRef.get()).val(),6),timestamp=safeInt(at,now());
  if(!/^[A-Z0-9]{6}$/.test(roomCode))return false;
  const room=(await db.ref(`friendlyRooms/${roomCode}`).get()).val();
  if(room&&room.hostUid===uid&&['waiting','matching'].includes(room.status)&&safeInt(room.expiresAt,0)>timestamp)return true;
  await mappingRef.transaction(function(value){return value===roomCode?null:undefined;}).catch(function(){});
  return false;
}
async function activeServerMatchId(uid){
  const matchId=cleanString((await db.ref(`rankedState/activeByUser/${uid}`).get()).val(),40);
  if(!validServerMatchId(matchId))return '';
  const ref=db.ref(`rankedState/matches/${matchId}`),match=hydrateMatch((await ref.get()).val());
  if(!match||!match.participants||match.participants[uid]!==true)return '';
  if(match.result){if(match.settlementStatus!=='complete')await settleRankedMatch(matchId);return '';}
  if(match.status!=='active')return '';
  const at=now(),swept=sweepRankedState(match,at);
  if(!swept.result)return matchId;
  const transaction=await ref.transaction(function(value){
    if(!value||value.status!=='active'||value.result)return value;
    return sweepRankedState(value,at);
  });
  const finalMatch=hydrateMatch(transaction.snapshot.val());
  if(transaction.committed&&finalMatch&&finalMatch.result)await settleRankedMatch(matchId);
  return '';
}
async function enforceFriendlyInviteCooldown(uid,targetUid,at){
  const ref=db.ref(`matchInviteThrottle/${uid}/${targetUid}`);
  const result=await ref.transaction(function(value){
    const last=safeInt(value,0);return last&&at-last<30000?undefined:at;
  });
  if(!result.committed)throw httpError(429,'invite-rate-limited','A friendly match invitation is already pending.');
}
async function createFriendlyServerMatch(uid,targetUid,requestIdValue,durationMinutes){
  durationMinutes=friendlyDurationMinutes(durationMinutes);
  const profiles=await Promise.all([requirePlayer(uid),requirePlayer(targetUid)]),at=now();
  const entries={};entries[uid]={uid,player:profileSummary(profiles[0],uid),deck:canonicalDeckForProfile(profiles[0])};entries[targetUid]={uid:targetUid,player:profileSummary(profiles[1],targetUid),deck:canonicalDeckForProfile(profiles[1])};
  if(entries[uid].deck.length!==6||entries[targetUid].deck.length!==6)throw httpError(409,'invalid-deck','A valid six-card deck is required before starting a friendly match.');
  const matchId=friendlyMatchId(uid,targetUid,requestIdValue),stateRef=db.ref('rankedState');
  let conflict='';
  const transaction=await stateRef.transaction(function(value){
    conflict='';
    value=value&&typeof value==='object'?value:{};value.queue=value.queue&&typeof value.queue==='object'?value.queue:{};
    value.matches=value.matches&&typeof value.matches==='object'?value.matches:{};value.activeByUser=value.activeByUser&&typeof value.activeByUser==='object'?value.activeByUser:{};
    for(const playerUid of [uid,targetUid]){
      const activeId=value.activeByUser[playerUid],active=activeId&&value.matches[activeId];
      if(activeId===matchId&&active&&active.status==='active'&&!active.result)return value;
      if(active&&active.status==='active'&&!active.result){conflict=playerUid===uid?'match-already-active':'opponent-busy';return;}
      if(activeId)delete value.activeByUser[playerUid];
      delete value.queue[playerUid];
    }
    const uidIsWhite=parseInt(hash(matchId+'|color').slice(0,2),16)%2===0;
    const white=uidIsWhite?entries[uid]:entries[targetUid],black=uidIsWhite?entries[targetUid]:entries[uid];
    value.matches[matchId]=createMatchState({
      matchId,mode:'friendly',at,durationMinutes,
      white:{uid:white.uid,profile:white.player,deck:white.deck},
      black:{uid:black.uid,profile:black.player,deck:black.deck}
    });
    value.activeByUser[uid]=matchId;value.activeByUser[targetUid]=matchId;
    return value;
  });
  if(!transaction.committed)throw httpError(409,conflict||'friendly-match-conflict','Friendly match could not be created.');
  if(conflict)throw httpError(409,conflict,'A player already has an active match.');
  const value=transaction.snapshot.val()||{},match=value.matches&&value.matches[matchId];
  if(!match)throw httpError(409,'friendly-match-conflict','Friendly match could not be created.');
  await publishRankedMatch(match);
  return {matchId,match};
}
async function sendMatchInvite(context){
  await battleV1.assertLegacyNewAllowed(context.req?.get('X-Luno-Platform')==='ios'?'ios':'android');
  const {uid,body}=context;assertBodyKeys(body,['targetUid','durationMinutes']);await rateLimit(uid,'sendMatchInvite',8,60*1000);
  const durationMinutes=friendlyDurationMinutes(body.durationMinutes);
  const sender=await requirePlayer(uid),senderName=canonicalUsername(sender,uid),target=await targetPlayer(body.targetUid,uid),targetUid=target.targetUid;
  return idempotent(uid,context.requestId,'sendMatchInvite:'+targetUid,async function(){
    return withSocialPairLock(uid,targetUid,async function(){
      await assertInteractionAllowed(uid,targetUid);await requireFriendship(uid,targetUid);
       if(await activeServerMatchId(uid))throw httpError(409,'match-already-active','Finish the active match before sending an invitation.');
       if(await activeServerMatchId(targetUid))throw httpError(409,'opponent-busy','The invited player is already in a match.');
       const at=now();
       if(await hasLiveRankedQueue(uid,at))throw httpError(409,'ranked-queue-active','Cancel ranked matchmaking before sending an invitation.');
       if(await hasLiveRankedQueue(targetUid,at))throw httpError(409,'opponent-searching','The invited player is currently searching for a ranked match.');
       if(await hasOpenFriendlyRoom(uid,at))throw httpError(409,'friendly-room-active','Cancel the open friendly room before sending an invitation.');
       if(await hasOpenFriendlyRoom(targetUid,at))throw httpError(409,'opponent-room-active','The invited player already has an open friendly room.');
       const ref=db.ref(`matchInvites/${targetUid}/${uid}`),existing=(await ref.get()).val();
      if(existing&&existing.status==='pending'){
        const expiresAt=safeInt(existing.expiresAt,0);
        if(expiresAt>at)return {sent:false,status:'pending',inviteId:cleanString(existing.inviteId,64),durationMinutes:friendlyDurationMinutes(existing.durationMinutes),expiresAt};
        await ref.remove();
      }
      await enforceFriendlyInviteCooldown(uid,targetUid,at);
      const inviteId='fi_'+hash(uid+'|'+targetUid+'|'+context.requestId).slice(0,30),updates={};
      updates[`matchInvites/${targetUid}/${uid}`]={inviteId,fromUid:uid,fromName:senderName,fromUsername:senderName,fromAvatar:cleanString(sender.avatarEmoji||'&#9818;',32),fromCountry:cleanString(sender.country||'TR',2),fromTrophies:safeInt(sender.trophies,0),durationMinutes,sentAt:at,expiresAt:at+FRIENDLY_INVITE_TTL_MS,status:'pending'};
      updates[`notifications/${targetUid}/${db.ref().push().key}`]={type:'match_invite',fromUid:uid,fromName:senderName,fromUsername:senderName,message:senderName+' seninle dostluk ma\u00e7\u0131 yapmak istiyor.',read:false,ts:ServerValue.TIMESTAMP};
      await db.ref().update(updates);return {sent:true,inviteId,durationMinutes,expiresAt:at+FRIENDLY_INVITE_TTL_MS};
    });
  });
}
async function cancelMatchInvite(context){
  const {uid,body}=context;assertBodyKeys(body,['targetUid']);await rateLimit(uid,'cancelMatchInvite',20,60*1000);
  const target=await targetPlayer(body.targetUid,uid),targetUid=target.targetUid;
  return idempotent(uid,context.requestId,'cancelMatchInvite:'+targetUid,async function(){
    return withSocialPairLock(uid,targetUid,async function(){
      const ref=db.ref(`matchInvites/${targetUid}/${uid}`),invite=(await ref.get()).val();
      if(invite&&invite.fromUid===uid)await ref.remove();
      return {cancelled:!!(invite&&invite.fromUid===uid),targetUid};
    });
  });
}
async function respondMatchInvite(context){
  if(context.body?.accept===true)await battleV1.assertLegacyNewAllowed(context.req?.get('X-Luno-Platform')==='ios'?'ios':'android');
  const {uid,body}=context;assertBodyKeys(body,['fromUid','accept']);await rateLimit(uid,'respondMatchInvite',20,60*1000);
  if(typeof body.accept!=='boolean')throw httpError(400,'invalid-invite-response','Match invite response must be true or false.');
  const from=await targetPlayer(body.fromUid,uid),fromUid=from.targetUid;
  return idempotent(uid,context.requestId,'respondMatchInvite:'+fromUid,async function(){
    return withSocialPairLock(uid,fromUid,async function(){
      const ref=db.ref(`matchInvites/${uid}/${fromUid}`),invite=(await ref.get()).val();
      if(invite?.protocolVersion==='LUNO_BATTLE_V1')throw httpError(409,'INCOMPATIBLE_PROTOCOL','Invitation uses a different battle protocol.');
      if(!invite||invite.fromUid!==fromUid)throw httpError(404,'invite-not-found','Friendly match invitation does not exist.');
      if(safeInt(invite.expiresAt,0)<=now()){await ref.remove();throw httpError(410,'invite-expired','Friendly match invitation has expired.');}
      await assertInteractionAllowed(uid,fromUid);await requireFriendship(uid,fromUid);
      if(body.accept!==true){
        await db.ref().update({[`matchInvites/${uid}/${fromUid}`]:null,[`matchInvites/${fromUid}/${uid}`]:null});
        return {accepted:false};
      }
      const at=now();
      if(await activeServerMatchId(uid))throw httpError(409,'match-already-active','Finish the active match before accepting an invitation.');
      if(await activeServerMatchId(fromUid))throw httpError(409,'opponent-busy','The inviting player is already in a match.');
      if(await hasLiveRankedQueue(uid,at))throw httpError(409,'ranked-queue-active','Cancel ranked matchmaking before accepting an invitation.');
      if(await hasLiveRankedQueue(fromUid,at))throw httpError(409,'opponent-searching','The inviting player is currently searching for a ranked match.');
      if(await hasOpenFriendlyRoom(uid,at))throw httpError(409,'friendly-room-active','Cancel your open friendly room before accepting an invitation.');
      if(await hasOpenFriendlyRoom(fromUid,at))throw httpError(409,'opponent-room-active','The inviting player already has an open friendly room.');
      const durationMinutes=friendlyDurationMinutes(invite.durationMinutes);
      const created=await createFriendlyServerMatch(uid,fromUid,context.requestId,durationMinutes),updates={};
      updates[`matchInvites/${uid}/${fromUid}`]=null;updates[`matchInvites/${fromUid}/${uid}`]=null;
      const accepter=await requirePlayer(uid),accepterName=canonicalUsername(accepter,uid);
      updates[`notifications/${fromUid}/${db.ref().push().key}`]={type:'match_invite_accepted',fromUid:uid,fromName:accepterName,fromUsername:accepterName,message:accepterName+' dostluk ma\u00e7ı davetini kabul etti.',read:false,ts:ServerValue.TIMESTAMP};
      await db.ref().update(updates);
      return {accepted:true,matchId:created.matchId,durationMinutes,view:sanitizeMatchView(created.match,uid)};
    });
  });
}
const FRIENDLY_ROOM_ALPHABET='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
function friendlyRoomCode(uid,requestIdValue,attempt){
  const digest=hash(uid+'|'+requestIdValue+'|'+attempt);let code='';
  for(let index=0;index<6;index++)code+=FRIENDLY_ROOM_ALPHABET[parseInt(digest.slice(index*2,index*2+2),16)%FRIENDLY_ROOM_ALPHABET.length];
  return code;
}
async function createFriendlyRoom(context){
  await battleV1.assertLegacyNewAllowed(context.req?.get('X-Luno-Platform')==='ios'?'ios':'android');
  const {uid,body}=context;assertBodyKeys(body,['durationMinutes']);await rateLimit(uid,'createFriendlyRoom',12,60*1000);
  const durationMinutes=friendlyDurationMinutes(body.durationMinutes);
  await requirePlayer(uid);
  return idempotent(uid,context.requestId,'createFriendlyRoom',async function(){
    const at=now();
    if(await activeServerMatchId(uid))throw httpError(409,'match-already-active','Finish the active match before creating a room.');
    if(await hasLiveRankedQueue(uid,at))throw httpError(409,'ranked-queue-active','Cancel ranked matchmaking before creating a friendly room.');
    if(await hasOpenFriendlyRoom(uid,at))throw httpError(409,'friendly-room-active','Cancel the open friendly room before creating another room.');
    const expiresAt=at+FRIENDLY_ROOM_TTL_MS;let roomCode='';
    for(let attempt=0;attempt<12&&!roomCode;attempt++){
      const candidate=friendlyRoomCode(uid,context.requestId,attempt),ref=db.ref(`friendlyRooms/${candidate}`);
      const reservation=await ref.transaction(function(value){
        if(value&&safeInt(value.expiresAt,0)>at)return;
        return {roomCode:candidate,hostUid:uid,durationMinutes,status:'waiting',createdAt:at,expiresAt};
      });
      if(reservation.committed)roomCode=candidate;
    }
    if(!roomCode)throw httpError(503,'room-code-unavailable','A unique room code could not be reserved.');
    const previousCode=cleanString((await db.ref(`friendlyRoomByUser/${uid}`).get()).val(),6),updates={};
    if(previousCode&&previousCode!==roomCode){const previous=(await db.ref(`friendlyRooms/${previousCode}`).get()).val();if(previous&&previous.hostUid===uid)updates[`friendlyRooms/${previousCode}`]=null;}
    updates[`friendlyRoomByUser/${uid}`]=roomCode;await db.ref().update(updates);
    return {created:true,roomCode,durationMinutes,expiresAt};
  });
}
async function cancelFriendlyRoom(context){
  const {uid,body}=context;assertBodyKeys(body,['roomCode']);await rateLimit(uid,'cancelFriendlyRoom',20,60*1000);
  const roomCode=strictString(body.roomCode,6,'invalid-room-code').toUpperCase();
  if(!/^[A-Z0-9]{6}$/.test(roomCode))throw httpError(400,'invalid-room-code','Room code is invalid.');
  const ref=db.ref(`friendlyRooms/${roomCode}`);let decision='missing';
  const transaction=await ref.transaction(function(value){
    // A cold RTDB transaction starts at null and must retry against server data.
    if(!value){decision='missing';return value===null?null:undefined;}
    if(value.hostUid!==uid){decision='owner';return;}
    if(value.status!=='waiting'){decision='claimed';return;}
    decision='cancelled';return null;
  },undefined,false);
  if(decision==='owner')throw httpError(403,'room-owner-required','Only the room owner can cancel it.');
  if(decision==='claimed')throw httpError(409,'room-already-claimed','The friendly room is already being joined.');
  if(decision==='missing'||!transaction.committed)return {cancelled:false};
  await db.ref(`friendlyRoomByUser/${uid}`).transaction(function(value){return value===roomCode?null:value;});
  return {cancelled:true};
}
async function joinFriendlyRoom(context){
  await battleV1.assertLegacyNewAllowed(context.req?.get('X-Luno-Platform')==='ios'?'ios':'android');
  const {uid,body}=context;assertBodyKeys(body,['roomCode']);await rateLimit(uid,'joinFriendlyRoom',16,60*1000);
  const roomCode=strictString(body.roomCode,6,'invalid-room-code').toUpperCase();
  if(!/^[A-Z0-9]{6}$/.test(roomCode))throw httpError(400,'invalid-room-code','Room code is invalid.');
  await requirePlayer(uid);
  const at=now();
  if(await activeServerMatchId(uid))throw httpError(409,'match-already-active','Finish the active match before joining a room.');
  if(await hasLiveRankedQueue(uid,at))throw httpError(409,'ranked-queue-active','Cancel ranked matchmaking before joining a room.');
  if(await hasOpenFriendlyRoom(uid,at))throw httpError(409,'friendly-room-active','Cancel your open friendly room before joining another room.');
  const ref=db.ref(`friendlyRooms/${roomCode}`),initial=(await ref.get()).val();
  if(!initial||initial.status!=='waiting')throw httpError(404,'room-not-found','Friendly room is unavailable.');
  if(safeInt(initial.expiresAt,0)<=now()){await ref.remove();throw httpError(410,'room-expired','Friendly room has expired.');}
  const hostUid=cleanString(initial.hostUid,128);if(!validUid(hostUid)||hostUid===uid)throw httpError(400,'invalid-room-host','Friendly room host is invalid.');
  await targetPlayer(hostUid,uid);await assertInteractionAllowed(uid,hostUid);
  const claim=await ref.transaction(function(value){
    if(value===null)return null;
    if(!value||value.status!=='waiting'||safeInt(value.expiresAt,0)<=now()||
       value.hostUid!==hostUid||value.createdAt!==initial.createdAt)return;
    value.status='matching';value.guestUid=uid;value.claimedAt=now();return value;
  },undefined,false);
  const claimedRoom=claim.snapshot.val();
  if(!claim.committed||!claimedRoom||claimedRoom.status!=='matching'||claimedRoom.guestUid!==uid){
    throw httpError(409,'room-full','Friendly room was joined by another player.');
  }
  try{
    const durationMinutes=friendlyDurationMinutes(claimedRoom.durationMinutes);
    const created=await createFriendlyServerMatch(hostUid,uid,context.requestId,durationMinutes),updates={};
    updates[`friendlyRooms/${roomCode}`]=null;updates[`friendlyRoomByUser/${hostUid}`]=null;await db.ref().update(updates);
    return {joined:true,matchId:created.matchId,durationMinutes,view:sanitizeMatchView(created.match,uid)};
  }catch(error){
    await ref.transaction(function(value){if(value&&value.status==='matching'&&value.guestUid===uid){delete value.guestUid;delete value.claimedAt;value.status='waiting';return value;}return value;});
    throw error;
  }
}
async function ensureConversation(uid,targetUid){
  await assertInteractionAllowed(uid,targetUid);
  const targetProfile=(await targetPlayer(targetUid,uid)).profile;
  const isFriend=(await db.ref(`friends/${uid}/${targetUid}`).get()).exists();
  if(targetProfile.dmFriendsOnly===true&&!isFriend)throw httpError(403,'friends-only','This player accepts messages from friends only.');
  const key=conversationId(uid,targetUid);let conflict=false;
  const result=await db.ref(`dm/${key}`).transaction(function(value){
    conflict=false;
    const members=value&&value.members;
    // Legacy underscore-separated keys are not injective for arbitrary UIDs.
    if(value&&(Object.keys(members||{}).some(member=>member!==uid&&member!==targetUid)||
       !members&&hasRecordValues(value.msgs))){conflict=true;return;}
    return Object.assign({},value||{},{members:{[uid]:true,[targetUid]:true},updatedAt:ServerValue.TIMESTAMP});
  },undefined,false);
  if(conflict)throw httpError(409,'conversation-conflict','Conversation belongs to different participants.');
  if(!result.committed)throw httpError(503,'conversation-unavailable','Conversation could not be prepared.');
  return key;
}
async function openDirectMessage(context){
  const {uid,body}=context;
  assertBodyKeys(body,['targetUid']);
  await rateLimit(uid,'openDirectMessage',20,60*1000);
  assertCurrentLegalConsent(await requirePlayer(uid),uid);
  const target=await targetPlayer(body.targetUid,uid);
  return withDirectMessageMetadata(uid,target.targetUid,async function(){
    assertCurrentLegalConsent(await requirePlayer(uid),uid);
    const key=await ensureConversation(uid,target.targetUid);
    const muted=(await db.ref(`mutes/${uid}/${target.targetUid}`).get()).exists();
    return {ok:true,conversationId:key,muted};
  });
}
async function committedDirectMessage(uid,targetUid,requestId,text){
  let key=conversationId(uid,targetUid),recipient=targetUid;
  const requestHash=hash(requestId);
  const bindingRef=directMessageBindingRef(uid,requestHash),binding=(await bindingRef.get()).val();
  let proof=(await db.ref(`dm/${key}/sendRequests/${hash(uid)}/${requestHash}`).get()).val();
  const invalid=()=>httpError(409,'dm-send-receipt-invalid','Message delivery proof could not be verified.');
  const valid=value=>value&&typeof value==='object'&&!Array.isArray(value)&&value.version===1&&
    value.requestIdHash===requestHash&&value.uidHash===hash(uid)&&
    /^[a-f0-9]{64}$/.test(value.targetUidHash)&&/^[a-f0-9]{64}$/.test(value.textHash)&&
    typeof value.messageId==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(value.messageId)&&
    Number.isSafeInteger(value.createdAt)&&value.createdAt>0&&value.createdAt<=8640000000000000;
  if(binding!==null){
    if(!valid(binding))throw invalid();
    if(binding.targetUidHash!==hash(targetUid)||binding.textHash!==hash(text)){
      throw httpError(409,'request-id-conflict','Request id belongs to another message.');
    }
  }
  if(proof===null){
    // A request belongs to the sender, even when its retry changes the recipient.
    const matches=Object.entries(await ownedDirectMessageConversations(uid)).filter(([,value])=>
      value.sendRequests?.[hash(uid)]?.[requestHash]!=null);
    if(!matches.length){if(binding!==null)throw invalid();return null;}
    if(matches.length!==1)throw invalid();
    const value=matches[0][1];key=matches[0][0];
    const others=Object.keys(value.members||{}).filter(member=>member!==uid);
    if(others.length!==1||!validUid(others[0])||key!==conversationId(uid,others[0]))throw invalid();
    recipient=others[0];proof=value.sendRequests[hash(uid)][requestHash];
  }
  if(!valid(proof)||proof.targetUidHash!==hash(recipient)||binding!==null&&!sameDirectMessageProof(binding,proof))throw invalid();
  if(recipient!==targetUid||proof.textHash!==hash(text))throw httpError(409,'request-id-conflict','Request id belongs to another message.');
  const [membersSnapshot,messageSnapshot]=await Promise.all([
    db.ref(`dm/${key}/members`).get(),db.ref(`dm/${key}/msgs/${proof.messageId}`).get(),
  ]);
  const members=membersSnapshot.val(),message=messageSnapshot.val();
  if(!members||Object.keys(members).length!==2||members[uid]!==true||members[recipient]!==true||
    !message||message.from!==uid||message.text!==text||message.ts!==proof.createdAt)throw invalid();
  if(binding===null){
    const result=await writeAccountMetadata(uid,'socialInteraction',()=>bindingRef.transaction(value=>{
      if(value===null||sameDirectMessageProof(value,proof))return proof;
      return undefined;
    },undefined,false),()=>bindingRef.transaction(value=>
      value===null||sameDirectMessageProof(value,proof)?null:undefined,undefined,false));
    if(!result.committed)throw httpError(409,'request-id-conflict','Request id belongs to another message.');
  }
  return {ok:true,idempotent:true,messageId:proof.messageId};
}
async function sendDirectMessage(context){
  const {uid,body}=context;
  assertBodyKeys(body,['targetUid','text']);
  await rateLimit(uid,'sendDirectMessage',30,60*1000);
  const sender=await requirePlayer(uid),target=await targetPlayer(body.targetUid,uid);
  assertCurrentLegalConsent(sender,uid);
  const raw=normalizeUgcText(body.text,MESSAGE_MAX_LENGTH);
  if(raw===null)throw httpError(400,'invalid-message','Message contains invalid content.');
  return idempotent(uid,context.requestId,'sendDirectMessage',async function(){
    const delivery={};
    return withDirectMessageMetadata(uid,target.targetUid,async function(){
      assertCurrentLegalConsent(await requirePlayer(uid),uid);
      await assertInteractionAllowed(uid,target.targetUid);
      // Replay committed delivery before cooldown or inbox writes, even if the request cache was lost.
      const replay=await committedDirectMessage(uid,target.targetUid,context.requestId,raw);
      if(replay)return replay;
      await enforceDirectMessageCooldown(uid,target.targetUid,raw,now());
      const key=await ensureConversation(uid,target.targetUid),at=now();
      // Keep the admitted-text reservation before potentially ambiguous delivery writes.
      await db.ref(`messageThrottle/${uid}/${target.targetUid}`).transaction(value=>
        Object.assign({},value||{},{at,textHash:hash(raw)}),undefined,false);
      const messageKey=db.ref(`dm/${key}/msgs`).push().key,updates={};
      const requestHash=hash(context.requestId);
      updates[`dm/${key}/msgs/${messageKey}`]={from:uid,text:raw,ts:at};
      const proof={version:1,requestIdHash:requestHash,uidHash:hash(uid),
        targetUidHash:hash(target.targetUid),textHash:hash(raw),messageId:messageKey,createdAt:at};
      updates[`dm/${key}/sendRequests/${hash(uid)}/${requestHash}`]=proof;
      updates[`messageThrottle/${uid}/!sendRequests/${requestHash}`]=proof;
      Object.assign(delivery,{messageId:messageKey,requestHash,text:raw,createdAt:at,proof});
      updates[`dmInbox/${target.targetUid}/${uid}`]={name:canonicalUsername(sender,uid),username:canonicalUsername(sender,uid),messageId:messageKey,last:raw,ts:at,unread:true};
      updates[`dmInbox/${uid}/${target.targetUid}`]={name:canonicalUsername(target.profile,target.targetUid),username:canonicalUsername(target.profile,target.targetUid),messageId:messageKey,last:raw,ts:at,unread:false};
      await db.ref().update(updates);
      return {ok:true,messageId:messageKey};
    },delivery);
  });
}
function directMessageInboxVersion(value){
  if(!value||typeof value!=='object'||Array.isArray(value))return null;
  return JSON.stringify([value.messageId||null,typeof value.last==='string'?value.last:null,safeInt(value.ts,0)]);
}
async function acknowledgeDirectMessage(uid,targetUid,lastMessageId,cursorProvided){
  if(cursorProvided&&lastMessageId===null)return {ok:true,marked:false};
  const ref=db.ref(`dmInbox/${uid}/${targetUid}`),initial=(await ref.get()).val();
  const version=directMessageInboxVersion(initial);
  if(version===null)return {ok:true,marked:false};
  if(cursorProvided&&initial.messageId!==lastMessageId){
    if(initial.messageId)return {ok:true,marked:false};
    // Legacy inbox rows have no ID: require the observed message's exact content/time.
    const key=conversationId(uid,targetUid),seen=(await db.ref(`dm/${key}/msgs/${lastMessageId}`).get()).val();
    if(!seen||(seen.from!==uid&&seen.from!==targetUid)||typeof seen.text!=='string'||
       initial.last!==seen.text||!Number.isSafeInteger(seen.ts)||initial.ts!==seen.ts)return {ok:true,marked:false};
  }
  let marked=false;
  const result=await ref.transaction(function(current){
    marked=false;
    // Probe the server on a cold cache without restoring a deleted inbox row.
    if(current===null)return null;
    if(directMessageInboxVersion(current)!==version)return;
    marked=true;
    return Object.assign({},current,{unread:false,lastReadAt:ServerValue.TIMESTAMP,
      lastReadMessageId:lastMessageId||current.messageId||null});
  },undefined,false);
  return {ok:true,marked:result.committed===true&&marked};
}
async function markDirectMessageRead(context){
  const {uid,body}=context;
  assertBodyKeys(body,['targetUid','lastMessageId']);
  const cursorProvided=Object.prototype.hasOwnProperty.call(body,'lastMessageId');
  const lastMessageId=cursorProvided&&body.lastMessageId!==null?strictString(body.lastMessageId,128,'invalid-message-id'):null;
  if(lastMessageId!==null&&!/^[A-Za-z0-9_-]{1,128}$/.test(lastMessageId))throw httpError(400,'invalid-message-id','Message id is invalid.');
  await rateLimit(uid,'markDirectMessageRead',30,60*1000);
  const target=await targetPlayer(body.targetUid,uid);await assertInteractionAllowed(uid,target.targetUid);
  const key=conversationId(uid,target.targetUid),member=(await db.ref(`dm/${key}/members/${uid}`).get()).val();
  if(member!==true)throw httpError(403,'conversation-denied','Player is not a conversation member.');
  return acknowledgeDirectMessage(uid,target.targetUid,lastMessageId,cursorProvided);
}

let googleApis;
let billingHealthCache={expiresAt:0,value:null};
function playClient(){
  const {google}=googleApis||(googleApis=require('googleapis'));
  const auth=new google.auth.GoogleAuth({scopes:['https://www.googleapis.com/auth/androidpublisher']});
  return google.androidpublisher({version:'v3',auth});
}
async function playRequest(work){
  try{return await work();}
  catch(error){throw httpError(503,'play-billing-unavailable','Google Play billing is temporarily unavailable.');}
}
async function fetchGooglePurchase(productId,purchaseToken,definition){
  const client=playClient();
  if(definition.type==='subs'){
    const response=await playRequest(()=>client.purchases.subscriptionsv2.get({packageName:PACKAGE_NAME,token:purchaseToken}));
    const data=response.data||{};
    const products=(data.lineItems||[]).map(function(item){return item.productId;});
    if(!products.includes(productId))throw httpError(409,'purchase-product-mismatch','Subscription does not contain this product.');
    return {kind:'subs',data};
  }
  const response=await playRequest(()=>client.purchases.productsv2.getproductpurchasev2({packageName:PACKAGE_NAME,token:purchaseToken}));
  const data=response.data||{};
  const products=(data.productLineItem||[]).map(function(item){return item.productId;});
  if(!products.includes(productId))throw httpError(409,'purchase-product-mismatch','Purchase does not contain this product.');
  return {kind:'inapp',data};
}
function subscriptionLifecycle(verified,at){
  const data=verified&&verified.data||{},status=cleanString(data.subscriptionState,80),expiry=subscriptionExpiry(verified),time=Number(at||now());
  const accessStates=new Set(['SUBSCRIPTION_STATE_ACTIVE','SUBSCRIPTION_STATE_IN_GRACE_PERIOD','SUBSCRIPTION_STATE_CANCELED']);
  return {status,expiry,active:accessStates.has(status)&&expiry>time,grace:status==='SUBSCRIPTION_STATE_IN_GRACE_PERIOD',canceled:status==='SUBSCRIPTION_STATE_CANCELED',onHold:status==='SUBSCRIPTION_STATE_ON_HOLD',revoked:status==='SUBSCRIPTION_STATE_REVOKED',expired:status==='SUBSCRIPTION_STATE_EXPIRED'||expiry<=time};
}
async function verifyWithGoogle(productId,purchaseToken,definition,accountHash){
  const verified=await fetchGooglePurchase(productId,purchaseToken,definition);
  if(verified.kind==='subs'){
    const lifecycle=subscriptionLifecycle(verified,now()),external=verified.data.externalAccountIdentifiers||{};
    if(!lifecycle.active)throw httpError(409,'purchase-not-active','Subscription is not active for this product.');
    if(external.obfuscatedExternalAccountId!==accountHash)throw httpError(409,'account-mismatch','Purchase belongs to another player.');
    return verified;
  }
  const data=verified.data||{};
  if(!data.purchaseStateContext||data.purchaseStateContext.purchaseState!=='PURCHASED')throw httpError(409,'purchase-not-complete','Purchase is not in PURCHASED state.');
  if(data.obfuscatedExternalAccountId!==accountHash)throw httpError(409,'account-mismatch','Purchase belongs to another player.');
  return verified;
}
function subscriptionExpiry(verified){
  const lineItems=verified&&verified.data&&verified.data.lineItems||[];
  return lineItems.reduce(function(latest,item){
    const value=Date.parse(item&&item.expiryTime||'');
    return Number.isFinite(value)?Math.max(latest,value):latest;
  },0);
}
function applyPurchaseCurrency(profile,currency,amount){
  const value=Math.max(0,safeInt(amount,0));
  if(!value)return {credited:0,debtPaid:0};
  profile.serverEconomy=profile.serverEconomy||{};
  profile.serverEconomy.billingDebt=profile.serverEconomy.billingDebt||{gold:0,gems:0};
  const debt=Math.max(0,safeInt(profile.serverEconomy.billingDebt[currency],0)),debtPaid=Math.min(debt,value),credited=value-debtPaid;
  profile.serverEconomy.billingDebt[currency]=debt-debtPaid;
  profile[currency]=safeInt(profile[currency],0)+credited;
  profile.serverEconomy.billingReviewRequired=safeInt(profile.serverEconomy.billingDebt.gold,0)>0||safeInt(profile.serverEconomy.billingDebt.gems,0)>0;
  return {credited,debtPaid};
}
function applyVerifiedPurchaseGrant(profile,uid,definition,verified,tokenHashValue){
  if(!profile)return {error:'profile-not-found'};
  if(profile.uid!==uid)return {error:'profile-owner-mismatch'};
  if(verified.kind!=='subs'&&profile.serverEconomy&&profile.serverEconomy.billingReversals&&profile.serverEconomy.billingReversals[tokenHashValue])return {error:'purchase-revoked'};
  profile.serverEconomy=profile.serverEconomy||{};
  profile.serverEconomy.purchaseTokens=profile.serverEconomy.purchaseTokens||{};
  if(verified.kind==='subs'){
    const at=now(),lifecycle=subscriptionLifecycle(verified,at),expiry=lifecycle.expiry;
    if(!lifecycle.active)return {error:'subscription-expired'};
    normalizeProductEntitlements(profile);
    if(safeInt(profile.premiumUntil,0)<=at||safeInt(profile.premiumSince,0)<=0)profile.premiumSince=at;
    profile.premiumUntil=Math.max(Number(profile.premiumUntil||0),expiry);
    profile.serverEconomy.purchaseTokens[tokenHashValue]={productId:verified.productId,kind:'subs',expiry,entitlementStatus:lifecycle.status,active:true,grantedAt:ServerValue.TIMESTAMP};
    profile.updatedAt=ServerValue.TIMESTAMP;
    return {granted:true,expiry};
  }
  const previous=profile.serverEconomy.purchaseTokens[tokenHashValue];
  if(previous){
    if(previous.active===false||previous.entitlementStatus==='voided'||profile.serverEconomy.billingReversals&&profile.serverEconomy.billingReversals[tokenHashValue])return {error:'purchase-revoked'};
    if(previous.productId!==verified.productId||previous.kind!=='inapp'||previous.active!==true||previous.entitlementStatus!=='granted')return {error:'purchase-receipt-invalid'};
    for(const field of ['grantGold','grantGems'])if(!Number.isSafeInteger(previous[field])||previous[field]<0||previous[field]>1000000000)return {error:'purchase-receipt-invalid'};
    return {granted:false,idempotent:true};
  }
  const grant=definition.grant||{};
  const gold=applyPurchaseCurrency(profile,'gold',grant.gold||0),gems=applyPurchaseCurrency(profile,'gems',grant.gems||0);
  profile.serverEconomy.purchaseTokens[tokenHashValue]={productId:verified.productId,kind:'inapp',grantGold:safeInt(grant.gold,0),grantGems:safeInt(grant.gems,0),entitlementStatus:'granted',active:true,grantedAt:ServerValue.TIMESTAMP};
  profile.updatedAt=ServerValue.TIMESTAMP;
  return {granted:true,credited:{gold:gold.credited,gems:gems.credited},debtPaid:{gold:gold.debtPaid,gems:gems.debtPaid}};
}
function applyVoidedPurchaseRevocation(profile,claim,tokenHashValue,at){
  if(!profile)return {error:'profile-not-found'};
  if(!claim||profile.uid!==claim.uid)return {error:'profile-owner-mismatch'};
  const economy=profile.serverEconomy||{},previous=economy.purchaseTokens&&economy.purchaseTokens[tokenHashValue];
  if(economy.billingReversals&&economy.billingReversals[tokenHashValue])return {revoked:false,idempotent:true};
  if(!previous){
    if(claim.status==='verified')return {revoked:false,ungranted:true};
    return {error:'purchase-receipt-invalid'};
  }
  if(previous.productId!==claim.productId||previous.kind!=='inapp'||previous.active!==true||previous.entitlementStatus!=='granted')return {error:'purchase-receipt-invalid'};
  for(const field of ['grantGold','grantGems'])if(!Number.isSafeInteger(previous[field])||previous[field]<0||previous[field]>1000000000||claim[field]!=null&&claim[field]!==previous[field])return {error:'purchase-receipt-invalid'};
  profile.serverEconomy=profile.serverEconomy||{};
  profile.serverEconomy.purchaseTokens=profile.serverEconomy.purchaseTokens||{};
  profile.serverEconomy.billingReversals=profile.serverEconomy.billingReversals||{};
  profile.serverEconomy.billingDebt=profile.serverEconomy.billingDebt||{gold:0,gems:0};
  if(profile.serverEconomy.billingReversals[tokenHashValue])return {revoked:false,idempotent:true};
  const requestedGold=previous.grantGold,requestedGems=previous.grantGems;
  const recoveredGold=Math.min(safeInt(profile.gold,0),requestedGold),recoveredGems=Math.min(safeInt(profile.gems,0),requestedGems);
  profile.gold=safeInt(profile.gold,0)-recoveredGold;profile.gems=safeInt(profile.gems,0)-recoveredGems;
  profile.serverEconomy.billingDebt.gold=safeInt(profile.serverEconomy.billingDebt.gold,0)+(requestedGold-recoveredGold);
  profile.serverEconomy.billingDebt.gems=safeInt(profile.serverEconomy.billingDebt.gems,0)+(requestedGems-recoveredGems);
  profile.serverEconomy.billingReviewRequired=profile.serverEconomy.billingDebt.gold>0||profile.serverEconomy.billingDebt.gems>0;
  const tokenEntry=profile.serverEconomy.purchaseTokens[tokenHashValue]||{};
  tokenEntry.active=false;tokenEntry.entitlementStatus='voided';tokenEntry.revokedAt=at;
  profile.serverEconomy.purchaseTokens[tokenHashValue]=tokenEntry;
  profile.serverEconomy.billingReversals[tokenHashValue]={productId:claim&&claim.productId||'',requestedGold,recoveredGold,requestedGems,recoveredGems,debtGold:requestedGold-recoveredGold,debtGems:requestedGems-recoveredGems,createdAt:at};
  profile.updatedAt=at;
  return {revoked:true,recoveredGold,recoveredGems,debtGold:requestedGold-recoveredGold,debtGems:requestedGems-recoveredGems};
}
function billingReviewRequired(profile){return !!(profile&&profile.serverEconomy&&profile.serverEconomy.billingReviewRequired===true);}
async function writePurchaseClaim(uid,tokenHash,productId,patch,create=false){
  return writeAccountMetadata(uid,'writePurchaseClaim',async function(){
    const result=await db.ref(`purchaseClaims/${tokenHash}`).transaction(function(value){
      if(value===null)return create?Object.assign({},patch,{uid,productId}):null;
      if(value.uid!==uid||value.productId!==productId||purchaseClaimRetired(value))return;
      if(create)return value;
      const consumable=Object.hasOwn(PRODUCT_CATALOG,productId)&&PRODUCT_CATALOG[productId].type!=='subs';
      if(consumable&&(value.voided===true||value.entitlementStatus==='voided')&&(patch.active===true||['granted','complete'].includes(patch.status)))return;
      if(value.status==='complete'&&patch.status==='reconcile-required')return value;
      const next=Object.assign({},value,patch,{uid,productId});
      if(value.status==='complete'&&patch.status==='granted')next.status='complete';
      for(const field of Object.keys(next))if(next[field]===null)delete next[field];
      return next;
    },undefined,false);
    if(!result.committed||!result.snapshot.val())throw httpError(409,'purchase-claim-changed','Purchase claim disappeared or changed owner.');
    return result.snapshot.val();
  },()=>anonymizePurchaseClaim(uid,tokenHash));
}
function completedConsumableReplay(profile,uid,claim,productId,tokenHash){
  if(!profile||profile.uid!==uid)throw httpError(403,'profile-owner-mismatch','Player profile ownership changed.');
  const economy=profile.serverEconomy||{},receipt=economy.purchaseTokens&&economy.purchaseTokens[tokenHash];
  if(claim.voided===true||claim.active===false||claim.entitlementStatus==='voided'||receipt&&receipt.active===false||economy.billingReversals&&economy.billingReversals[tokenHash])throw httpError(409,'purchase-revoked','Purchase was revoked.');
  if(!receipt||receipt.productId!==productId||receipt.kind!=='inapp'||receipt.active!==true||receipt.entitlementStatus!=='granted')throw httpError(409,'purchase-receipt-invalid','Purchase receipt is missing or invalid.');
  for(const field of ['grantGold','grantGems'])if(!Number.isSafeInteger(receipt[field])||receipt[field]<0||receipt[field]>1000000000||claim[field]!=null&&claim[field]!==receipt[field])throw httpError(409,'purchase-receipt-invalid','Purchase receipt amounts are invalid.');
  return {ok:true,verified:true,entitlementGranted:true,idempotent:true};
}
async function fulfillPurchase(uid,body){
  await assertAccountOperationAllowed(uid,'fulfillPurchase');
  const productId=cleanString(body.productId,80),purchaseToken=cleanString(body.purchaseToken,4096);
  const definition=Object.hasOwn(PRODUCT_CATALOG,productId)?PRODUCT_CATALOG[productId]:null;
  if(!definition||!purchaseToken)throw httpError(400,'invalid-product','Unknown product or missing purchase token.');
  const profileBefore=(await db.ref(`users/${uid}`).get()).val();
  if(!profileBefore)throw httpError(404,'profile-not-found','Player profile does not exist.');
  if(profileBefore.uid!==uid)throw httpError(403,'profile-owner-mismatch','Player profile ownership changed.');
  const tokenHash=hash(purchaseToken);
  const claimRef=db.ref(`purchaseClaims/${tokenHash}`);
  const existingBefore=(await claimRef.get()).val()||null;
  if(existingBefore&&(existingBefore.uid!==uid||existingBefore.productId!==productId||purchaseClaimRetired(existingBefore)))throw httpError(409,'purchase-token-used','Purchase token was already claimed.');
  if(existingBefore&&existingBefore.status==='complete'&&definition.type!=='subs'){
    await assertAccountOperationAllowed(uid,'fulfillPurchase');
    const profile=(await db.ref(`users/${uid}`).get()).val();
    const current=(await claimRef.get()).val();
    await assertAccountOperationAllowed(uid,'fulfillPurchase');
    if(!current||current.uid!==uid||current.productId!==productId||current.status!=='complete'||purchaseClaimRetired(current))throw httpError(409,'purchase-claim-changed','Purchase claim changed during verification.');
    return completedConsumableReplay(profile,uid,current,productId,tokenHash);
  }
  if(existingBefore&&existingBefore.voided===true&&definition.type!=='subs')throw httpError(409,'purchase-revoked','Purchase was revoked.');
  const verified=await verifyWithGoogle(productId,purchaseToken,definition,hash(uid));
  verified.productId=productId;
  const consumed=verified.kind==='inapp'&&(verified.data.productLineItem||[]).some(function(item){
    return item.productId===productId&&item.productOfferDetails?.consumptionState==='CONSUMPTION_STATE_CONSUMED';
  });
  await assertAccountOperationAllowed(uid,'fulfillPurchase');
  const claim=await writePurchaseClaim(uid,tokenHash,productId,{status:'verified',verifiedAt:ServerValue.TIMESTAMP},true);
  if(claim.voided===true&&verified.kind!=='subs')throw httpError(409,'purchase-revoked','Purchase was revoked.');
  try{
    const grantResult=await transactExistingPlayer(uid,function(profile){
      // A consumed token can only complete an already committed owned grant.
      if(consumed)completedConsumableReplay(profile,uid,claim,productId,tokenHash);
      const decision=applyVerifiedPurchaseGrant(profile,uid,definition,verified,tokenHash);
      return Object.assign({commit:!decision.error},decision);
    });
    const grantDecision=grantResult.decision;
    if(grantDecision.error)throw httpError(409,grantDecision.error,'Purchase could not be granted to this player.');
    await assertAccountOperationAllowed(uid,'fulfillPurchase');
    await publishPublicProfile(uid,grantResult.profile);
    const lifecycle=verified.kind==='subs'?subscriptionLifecycle(verified,now()):null;
    const verifiedOrderId=cleanString(verified.data&&verified.data.latestOrderId||verified.data&&verified.data.orderId||'',160);
    const receipt=grantResult.profile.serverEconomy.purchaseTokens[tokenHash];
    await writePurchaseClaim(uid,tokenHash,productId,{
      status:'granted',kind:verified.kind,grantedAt:ServerValue.TIMESTAMP,
      entitlementStatus:lifecycle?lifecycle.status:'granted',active:lifecycle?lifecycle.active:true,
      expiry:lifecycle?lifecycle.expiry:null,grantGold:safeInt(receipt.grantGold,0),grantGems:safeInt(receipt.grantGems,0),
      orderIdHash:verifiedOrderId?hash(verifiedOrderId):null,lastError:null
    });
    await assertAccountOperationAllowed(uid,'fulfillPurchase');
    const client=playClient();
    if(verified.kind==='subs'){
      const acknowledged=verified.data.acknowledgementState==='ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED';
      if(!acknowledged)await playRequest(()=>client.purchases.subscriptions.acknowledge({packageName:PACKAGE_NAME,subscriptionId:productId,token:purchaseToken,requestBody:{}}));
    }else if(!consumed){
      await playRequest(()=>client.purchases.products.consume({packageName:PACKAGE_NAME,productId,token:purchaseToken}));
    }
    await writePurchaseClaim(uid,tokenHash,productId,{status:'complete',completedAt:ServerValue.TIMESTAMP});
    return {ok:true,verified:true,entitlementGranted:true,idempotent:!!(grantDecision&&grantDecision.idempotent)};
  }catch(error){
    let deletionError=isAccountDeletionError(error)?error:null;
    if(!deletionError){
      try{await assertAccountOperationAllowed(uid,'fulfillPurchase');}
      catch(gateError){if(isAccountDeletionError(gateError))deletionError=gateError;}
    }
    if(deletionError){await anonymizePurchaseClaim(uid,tokenHash);throw deletionError;}
    logger.error('Purchase fulfillment failed',{uidHash:hash(uid).slice(0,16),productId,tokenHash,errorCode:'purchase-fulfillment-failed'});
    await writePurchaseClaim(uid,tokenHash,productId,{status:'reconcile-required',lastError:null}).catch(function(){});
    throw error;
  }
}
async function verifyPurchase(context){
  const {uid,body}=context;
  assertBodyKeys(body,['productId','purchaseToken','orderId','purchaseState']);
  await rateLimit(uid,'verifyPurchase',12,60*1000);
  return fulfillPurchase(uid,body);
}
async function billingHealth(context){
  assertBodyKeys(context.body,[]);
  await rateLimit(context.uid,'billingHealth',30,60*1000);
  const catalog=Object.keys(PRODUCT_CATALOG).map(function(productId){return {productId,type:PRODUCT_CATALOG[productId].type};});
  if(process.env.FIREBASE_AUTH_EMULATOR_HOST)return {ready:true,catalogReady:true,catalog,environment:'emulator'};
  if(billingHealthCache.value&&billingHealthCache.expiresAt>now())return billingHealthCache.value;
  try{
    const client=playClient();
    const responses=await Promise.all([
      client.inappproducts.list({packageName:PACKAGE_NAME,maxResults:100}),
      client.monetization.subscriptions.list({packageName:PACKAGE_NAME,pageSize:100})
    ]);
    const available=new Set();
    (responses[0].data.inappproduct||[]).forEach(function(item){if(item&&item.sku)available.add(item.sku);});
    (responses[1].data.subscriptions||[]).forEach(function(item){if(item&&item.productId)available.add(item.productId);});
    const missing=catalog.map(function(item){return item.productId;}).filter(function(productId){return !available.has(productId);});
    const value={ready:missing.length===0,catalogReady:missing.length===0,catalog,missingProductIds:missing};
    billingHealthCache={expiresAt:now()+5*60*1000,value};
    return value;
  }catch(error){
    logger.warn('Billing readiness check failed',{error:String(error&&error.message||error)});
    const value={ready:false,catalogReady:false,catalog,reason:'play-catalog-unavailable'};
    billingHealthCache={expiresAt:now()+30*1000,value};
    return value;
  }
}
async function restorePurchases(context){
  const {uid,body}=context;
  assertBodyKeys(body,['purchases']);
  if(!Array.isArray(body.purchases)||body.purchases.length>12)throw httpError(400,'invalid-purchases','Purchase list is invalid.');
  await rateLimit(uid,'restorePurchases',6,60*60*1000);
  // Reject a malformed batch before granting or consuming any earlier item.
  for(const item of body.purchases){
    assertPlainRecord(item,'invalid-purchase');
    assertBodyKeys(item,['productId','purchaseToken','orderId','purchaseState']);
  }
  const seen=new Set(),results=[];
  for(const item of body.purchases){
    const productId=cleanString(item.productId,80),tokenHash=hash(cleanString(item.purchaseToken,4096));
    if(!productId||seen.has(tokenHash))continue;
    seen.add(tokenHash);
    try{
      const restored=await fulfillPurchase(uid,item);
      results.push({productId,restored:restored.entitlementGranted===true,idempotent:restored.idempotent===true});
    }catch(error){
      results.push({productId,restored:false,error:cleanString(error&&error.code||'restore-failed',80)});
    }
  }
  return {restored:results.filter(function(item){return item.restored;}).length,results};
}

function decodeRtdnNotification(event){
  const message=event&&event.data&&event.data.message||event&&event.message||{};
  let payload=null;
  try{if(message.json&&typeof message.json==='object')payload=message.json;}catch(error){}
  if(!payload){
    let raw=message.data;
    if(Buffer.isBuffer(raw))raw=raw.toString('utf8');
    if(typeof raw!=='string'||!raw)throw httpError(400,'invalid-rtdn','RTDN message data is missing.');
    try{
      const decoded=/^\s*\{/.test(raw)?raw:Buffer.from(raw,'base64').toString('utf8');
      payload=JSON.parse(decoded);
    }catch(error){throw httpError(400,'invalid-rtdn','RTDN message is not valid JSON.');}
  }
  if(!payload||typeof payload!=='object'||Array.isArray(payload))throw httpError(400,'invalid-rtdn','RTDN payload is invalid.');
  return payload;
}
function rtdnKind(notification){
  const fields=['subscriptionNotification','oneTimeProductNotification','voidedPurchaseNotification','pendingRefundReviewNotification','testNotification'];
  const present=fields.filter(function(field){return notification&&notification[field]&&typeof notification[field]==='object';});
  if(present.length!==1)throw httpError(400,'invalid-rtdn','RTDN payload must contain exactly one notification.');
  return present[0];
}
async function confirmVoidedWithGoogle(notification,eventAt){
  const purchaseToken=cleanString(notification&&notification.purchaseToken,4096),orderId=cleanString(notification&&notification.orderId,180);
  if(!purchaseToken)throw httpError(400,'invalid-rtdn','Voided purchase token is missing.');
  const current=now(),oldest=Math.max(current-29*24*60*60*1000,Math.max(0,Number(eventAt||current)-24*60*60*1000));
  const seenPages=new Set();let pageToken;
  for(let page=0;page<20;page++){
    const request={packageName:PACKAGE_NAME,startTime:String(oldest),endTime:String(current),type:1,includeQuantityBasedPartialRefund:true,maxResults:100};
    if(pageToken)request.token=pageToken;
    const response=await playRequest(()=>playClient().purchases.voidedpurchases.list(request));
    const items=response.data&&response.data.voidedPurchases||[];
    const match=items.find(function(item){return item&&item.purchaseToken===purchaseToken&&(!orderId||item.orderId===orderId);});
    if(match)return match;
    const next=response.data&&response.data.tokenPagination&&response.data.tokenPagination.nextPageToken;
    if(next==null||next==='')throw httpError(409,'void-not-confirmed','Voided purchase was not confirmed by Google Play.');
    if(typeof next!=='string'||next.length>8192)throw httpError(503,'void-pagination-invalid','Voided purchase pagination is invalid.');
    if(seenPages.has(next))throw httpError(503,'void-pagination-cycle','Voided purchase pagination repeated a page.');
    seenPages.add(next);pageToken=next;
  }
  // A bounded scan that did not find provider proof must never revoke access.
  throw httpError(503,'void-pagination-limit','Voided purchase pagination exceeded its limit.');
}
async function recomputePremiumFromClaims(uid,at){
  await assertAccountOperationAllowed(uid,'recomputePremiumFromClaims');
  const claims=(await db.ref('purchaseClaims').orderByChild('uid').equalTo(uid).get()).val()||{};
  let premiumUntil=0;
  Object.keys(claims).forEach(function(key){
    const claim=claims[key]||{},expiry=safeInt(claim.expiry,0);
    if(!purchaseClaimRetired(claim)&&claim.kind==='subs'&&claim.active===true&&expiry>at)premiumUntil=Math.max(premiumUntil,expiry);
  });
  const result=await transactExistingPlayer(uid,function(profile){
    if(profile.uid!==uid)return {commit:false,error:'profile-owner-mismatch'};
    normalizeProductEntitlements(profile);
    profile.premiumUntil=premiumUntil;
    profile.updatedAt=ServerValue.TIMESTAMP;
    return {commit:true};
  });
  if(result.decision.error)throw httpError(403,result.decision.error,'Player profile ownership changed.');
  await assertAccountOperationAllowed(uid,'recomputePremiumFromClaims');
  if(result.committed)await publishPublicProfile(uid,result.profile);
  return {premiumUntil,active:premiumUntil>at};
}
async function reconcileSubscriptionClaim(claim,tokenHash,purchaseToken,eventAt,eventType){
  const definition=PRODUCT_CATALOG[claim.productId];
  if(!definition||definition.type!=='subs')throw httpError(409,'purchase-product-mismatch','RTDN subscription does not match the server catalog.');
  const verified=await fetchGooglePurchase(claim.productId,purchaseToken,definition),external=verified.data.externalAccountIdentifiers||{};
  if(external.obfuscatedExternalAccountId!==hash(claim.uid))throw httpError(409,'account-mismatch','Subscription belongs to another player.');
  const lifecycle=subscriptionLifecycle(verified,eventAt);
  await writePurchaseClaim(claim.uid,tokenHash,claim.productId,{kind:'subs',entitlementStatus:lifecycle.status,active:lifecycle.active,expiry:lifecycle.expiry,lastRtdnType:eventType,lastReconciledAt:ServerValue.TIMESTAMP});
  const premium=await recomputePremiumFromClaims(claim.uid,eventAt);
  return {eventType,status:lifecycle.status,active:lifecycle.active,expiry:lifecycle.expiry,premiumUntil:premium.premiumUntil};
}
async function reconcilePlayNotification(notification,eventKey){
  if(notification.packageName!==PACKAGE_NAME)throw httpError(400,'package-mismatch','RTDN package does not match Luno Chess.');
  const kind=rtdnKind(notification),eventAt=Math.min(now(),Math.max(0,Number(notification.eventTimeMillis)||now()));
  if(kind==='testNotification')return {eventType:'test',handled:true};
  const detail=notification[kind]||{},purchaseToken=cleanString(detail.purchaseToken,4096),tokenHash=purchaseToken?hash(purchaseToken):'',claimRef=tokenHash?db.ref(`purchaseClaims/${tokenHash}`):null;
  const claim=claimRef?(await claimRef.get()).val():null;
  if(!claim){
    await db.ref(`billingSignals/unmatched/${eventKey}`).set({eventType:kind,productId:cleanString(detail.sku,80),tokenHash:tokenHash||null,seenAt:ServerValue.TIMESTAMP,status:'awaiting-client-claim'});
    return {eventType:kind,handled:false,deferred:true};
  }
  if(purchaseClaimRetired(claim))return {eventType:kind,handled:true,status:'account-deleted'};
  if(!validUid(claim.uid)||!Object.hasOwn(PRODUCT_CATALOG,claim.productId))throw httpError(409,'invalid-purchase-claim','Stored purchase claim is invalid.');
  try{
    await assertAccountOperationAllowed(claim.uid,'reconcilePlayNotification');
    if(kind==='subscriptionNotification'){
      return await reconcileSubscriptionClaim(claim,tokenHash,purchaseToken,eventAt,safeInt(detail.notificationType,0));
    }
    if(kind==='oneTimeProductNotification'){
      const sku=cleanString(detail.sku,80);
      if(sku!==claim.productId)throw httpError(409,'purchase-product-mismatch','RTDN product does not match the claimed product.');
      if(claim.voided===true)return {eventType:'one-time',handled:true,active:false,status:'voided'};
      const verified=await fetchGooglePurchase(claim.productId,purchaseToken,PRODUCT_CATALOG[claim.productId]),data=verified.data||{};
      if(data.obfuscatedExternalAccountId!==hash(claim.uid))throw httpError(409,'account-mismatch','Purchase belongs to another player.');
      const purchased=data.purchaseStateContext&&data.purchaseStateContext.purchaseState==='PURCHASED';
      await writePurchaseClaim(claim.uid,tokenHash,claim.productId,{lastRtdnType:safeInt(detail.notificationType,0),lastReconciledAt:ServerValue.TIMESTAMP,entitlementStatus:purchased?'granted':'pending-canceled',active:purchased});
      if(purchased&&claim.status!=='complete')await fulfillPurchase(claim.uid,{productId:claim.productId,purchaseToken});
      return {eventType:'one-time',active:purchased,status:purchased?'granted':'pending-canceled'};
    }
    if(kind==='pendingRefundReviewNotification'){
      await writePurchaseClaim(claim.uid,tokenHash,claim.productId,{refundReviewStatus:'pending',lastReconciledAt:ServerValue.TIMESTAMP});
      return {eventType:'pending-refund-review',active:claim.active===true,status:'pending-review'};
    }
    const voided=await confirmVoidedWithGoogle(detail,eventAt);
    if(PRODUCT_CATALOG[claim.productId].type==='subs'){
      const subscription=await reconcileSubscriptionClaim(claim,tokenHash,purchaseToken,eventAt,'voided');
      await writePurchaseClaim(claim.uid,tokenHash,claim.productId,{voided:true,voidedAt:safeInt(voided.voidedTimeMillis,eventAt),voidedReason:safeInt(voided.voidedReason,0),voidedOrderIdHash:voided.orderId?hash(voided.orderId):null});
      return Object.assign({eventType:'voided-subscription',voided:true},subscription);
    }
    const revoked=await transactExistingPlayer(claim.uid,function(profile){
      const decision=applyVoidedPurchaseRevocation(profile,claim,tokenHash,eventAt);
      return Object.assign({commit:!decision.error},decision);
    });
    if(revoked.decision.error)throw httpError(403,revoked.decision.error,'Player profile ownership changed.');
    await assertAccountOperationAllowed(claim.uid,'reconcilePlayNotification');
    await publishPublicProfile(claim.uid,revoked.profile);
    await writePurchaseClaim(claim.uid,tokenHash,claim.productId,{active:false,entitlementStatus:'voided',voided:true,voidedAt:safeInt(voided.voidedTimeMillis,eventAt),voidedReason:safeInt(voided.voidedReason,0),voidedOrderIdHash:voided.orderId?hash(voided.orderId):null,lastReconciledAt:ServerValue.TIMESTAMP});
    const revocation=Object.assign({},revoked.decision);delete revocation.commit;
    return Object.assign({eventType:'voided-one-time',voided:true},revocation);
  }catch(error){
    let deletionError=isAccountDeletionError(error)?error:null;
    if(!deletionError){
      try{await assertAccountOperationAllowed(claim.uid,'reconcilePlayNotification');}
      catch(gateError){if(isAccountDeletionError(gateError))deletionError=gateError;}
    }
    if(!deletionError)throw error;
    await anonymizePurchaseClaim(claim.uid,tokenHash);
    return {eventType:kind,handled:true,status:'account-deleted'};
  }
}
async function handlePlayBillingNotification(event){
  const notification=decodeRtdnNotification(event),message=event&&event.data&&event.data.message||{},externalId=cleanString(event&&event.id||message.messageId||'',256);
  const eventKey=hash(externalId||JSON.stringify(notification)).slice(0,48),eventRef=db.ref(`billingEvents/${eventKey}`),startedAt=now();
  const lock=await eventRef.transaction(function(value){
    if(value&&value.status==='complete')return;
    if(value&&value.status==='processing'&&startedAt-safeInt(value.startedAt,0)<5*60*1000)return;
    return {status:'processing',startedAt,attempts:safeInt(value&&value.attempts,0)+1};
  });
  if(!lock.committed)return {duplicate:true,eventKey};
  try{
    const result=await reconcilePlayNotification(notification,eventKey);
    await eventRef.update({status:'complete',completedAt:ServerValue.TIMESTAMP,resultStatus:cleanString(result&&result.status||result&&result.eventType||'handled',80)});
    return result;
  }catch(error){
    await eventRef.update({status:'failed',failedAt:ServerValue.TIMESTAMP,errorCode:cleanString(error&&error.code||'reconcile-failed',80)}).catch(function(){});
    throw error;
  }
}

async function anonymizePurchaseClaim(uid,key){
  const pseudonym=hash(uid),at=now();
  return db.ref(`purchaseClaims/${key}`).transaction(function(value){
    if(value===null)return null;
    return retainPurchaseClaim(value,uid,pseudonym,at);
  },undefined,false);
}
async function anonymizeModerationReport(uid,key){
  const pseudonym=hash(uid),at=now();
  return db.ref(`moderationReports/${key}`).transaction(function(value){
    if(value===null)return null;
    return retainModerationReport(value,uid,pseudonym,at);
  },undefined,false);
}
async function retireAccountRecords(uid){
  const owners=[uid,hash(uid)];
  const purchaseSnapshots=await Promise.all(owners.map(owner=>db.ref('purchaseClaims').orderByChild('uid').equalTo(owner).get()));
  const purchaseKeys=new Set(purchaseSnapshots.flatMap(snapshot=>Object.keys(snapshot.val()||{})));
  await Promise.all(Array.from(purchaseKeys,key=>anonymizePurchaseClaim(uid,key)));
  const reportSnapshots=await Promise.all(owners.flatMap(owner=>['reporterUid','targetUid'].map(field=>db.ref('moderationReports').orderByChild(field).equalTo(owner).get())));
  const reportKeys=new Set(reportSnapshots.flatMap(snapshot=>Object.keys(snapshot.val()||{})));
  await Promise.all(Array.from(reportKeys,key=>anonymizeModerationReport(uid,key)));
}
async function deleteAccount(context){
  const {uid,token,body}=context;
  assertBodyKeys(body,['confirm']);
  if(body.confirm!==true)throw httpError(400,'confirmation-required','Explicit deletion confirmation is required.');
  const provider=token.firebase&&token.firebase.sign_in_provider||'';
  const age=Math.floor(now()/1000)-Number(token.auth_time||0);
  if(provider!=='anonymous'&&age>300)throw httpError(401,'reauth-required','Recent authentication is required.');
  await rateLimit(uid,'deleteAccount',3,60*60*1000);
  return withUsernameLock(uid,async function(){
    const deletionKey=hash(uid),deletionRef=db.ref(`accountDeletions/${deletionKey}`);
    await deletionRef.update({status:'processing',requestIdHash:hash(context.requestId),updatedAt:ServerValue.TIMESTAMP});
    // The tombstone blocks new deliveries before their private erase index is
    // purged. A failed purge leaves user data intact and deletion retryable.
    await productTelemetry.purgeUser(uid);
    await leaveRankedBeforeDeletion(uid);
    await battleV1.leaveAccount(uid);
    const userRef=db.ref(`users/${uid}`),profile=(await userRef.get()).val()||{};
    const username=profile&&Object.keys(profile).length?canonicalUsername(profile,uid):'',usernameReservations=(await db.ref('usernames').orderByValue().equalTo(uid).get()).val()||{};
    const codeReservations=(await db.ref('playerCodes').orderByValue().equalTo(uid).get()).val()||{};
    const linkTickets=(await db.ref('accountLinkTickets').orderByChild('uid').equalTo(uid).get()).val()||{};
    const [friendsSnapshot,requestsSnapshot,outgoingSnapshot,inboxSnapshot,blocksSnapshot,blockedBySnapshot]=await Promise.all([
      db.ref(`friends/${uid}`).get(),db.ref(`friendRequests/${uid}`).get(),db.ref(`outgoingFriendRequests/${uid}`).get(),db.ref(`dmInbox/${uid}`).get(),
      db.ref(`blocks/${uid}`).get(),db.ref(`blockedBy/${uid}`).get()
    ]);
    const related=new Set([
      ...Object.keys(friendsSnapshot.val()||{}),...Object.keys(requestsSnapshot.val()||{}),
      ...Object.keys(outgoingSnapshot.val()||{}),...Object.keys(inboxSnapshot.val()||{}),
      ...Object.keys(blocksSnapshot.val()||{}),...Object.keys(blockedBySnapshot.val()||{})
    ]);
    const dmPairs=new Map(Array.from(related,otherUid=>[conversationId(uid,otherUid),otherUid]));
    for(const [key,value] of Object.entries(await ownedDirectMessageConversations(uid))){
      const members=Object.keys(value.members||{}),others=members.filter(member=>member!==uid);
      if(members.length===2&&others.length===1&&validUid(others[0])){
        related.add(others[0]);dmPairs.set(key,others[0]);
      }
    }
    const updates={};
    updates[`users/${uid}`]=null;updates[`friends/${uid}`]=null;updates[`friendRequests/${uid}`]=null;
    updates[`matchInvites/${uid}`]=null;updates[`notifications/${uid}`]=null;updates[`dmInbox/${uid}`]=null;
    updates[`matches/${uid}`]=null;updates[`matchHistory/${uid}`]=null;updates[`queue/${uid}`]=null;
    updates[`rankedPlayers/${uid}`]=null;updates[`rankedMatchViews/${uid}`]=null;updates[`rankedReplays/${uid}`]=null;
    updates[`rankedMessages/${uid}`]=null;
    updates[`rankedState/queue/${uid}`]=null;updates[`rankedState/activeByUser/${uid}`]=null;
    updates[`battleV1Accounts/${uid}`]=null;updates[`battleV1Ratings/${uid}`]=null;
    updates[`publicProfiles/${uid}`]=null;
    updates[`serverRateLimits/${uid}`]=null;updates[`serverRequests/${uid}`]=null;updates[`auditLogs/${uid}`]=null;
    updates[`outgoingFriendRequests/${uid}`]=null;updates[`presence/${uid}`]=null;updates[`deviceTokens/${uid}`]=null;
    updates[`blocks/${uid}`]=null;updates[`blockedBy/${uid}`]=null;updates[`mutes/${uid}`]=null;updates[`messageThrottle/${uid}`]=null;
    related.forEach(function(otherUid){
      if(!validUid(otherUid))return;
      updates[`friends/${otherUid}/${uid}`]=null;
      updates[`friendRequests/${otherUid}/${uid}`]=null;
      updates[`outgoingFriendRequests/${otherUid}/${uid}`]=null;
      updates[`matchInvites/${otherUid}/${uid}`]=null;
      updates[`notifications/${otherUid}/${uid}`]=null;
      updates[`dmInbox/${otherUid}/${uid}`]=null;
      updates[`blocks/${otherUid}/${uid}`]=null;updates[`blockedBy/${otherUid}/${uid}`]=null;
      updates[`mutes/${otherUid}/${uid}`]=null;updates[`messageThrottle/${otherUid}/${uid}`]=null;
    });
    updates[`deletedAccounts/${hash(uid)}`]={deletedAt:ServerValue.TIMESTAMP,provider,retention:'purchase records retained in pseudonymous form when legally required'};
    await db.ref().update(updates);
    for(const [key,otherUid] of dmPairs)if(validUid(otherUid))await eraseDirectMessagePair(uid,otherUid,null,key);
    // Shared indexes may have a new owner since the query or legacy snapshot.
    const reservedNames=new Set(Object.keys(usernameReservations));if(username)reservedNames.add(username);
    const reservedCodes=new Set(Object.keys(codeReservations)),profileCode=normalizedPlayerCode(profile.playerCode);
    if(profileCode)reservedCodes.add(profileCode.toLowerCase());
    await Promise.all([
      ...Array.from(reservedNames).map(function(name){return releaseOwnedIndex(db.ref(`usernames/${name}`),uid);}),
      ...Array.from(reservedCodes).map(function(code){return releaseOwnedIndex(db.ref(`playerCodes/${code}`),uid);}),
      ...Object.keys(linkTickets).map(function(ticketId){return releaseAccountLinkTicket(uid,ticketId);})
    ]);
    await retireAccountRecords(uid);
    try{await getAuth().deleteUser(uid);}catch(error){if(!error||error.code!=='auth/user-not-found')throw error;}
    await deletionRef.update({status:'complete',completedAt:ServerValue.TIMESTAMP});
    return {ok:true,deleted:true};
  });
}

const ROUTES={
  createGuestPlayer,prepareGoogleLink,completeGoogleLink,recordGoogleLinkConflict,changeUsername,getPlayerState,acceptLegalTerms,claimDailyReward,claimOnboardingReward,claimSocialVisitReward,
  claimMissionReward,claimAchievementReward,claimPassReward,claimSeasonReward,claimSeasonPathReward,
  purchaseSoftItem,upgradeCard,openChest,openPassChest,
  enqueueRanked,cancelRankedQueue,getRankedMatch,submitMatchAction,heartbeatRankedMatch,sendRankedMessage,
  updateProfile,updatePreferences,getLeaderboard,getPublicPlayerProfile,getPublicPlayerProfiles,getFriends,searchPlayers,sendFriendRequest,respondFriendRequest,removeFriend,markNotificationRead,sendMatchInvite,cancelMatchInvite,respondMatchInvite,createFriendlyRoom,cancelFriendlyRoom,joinFriendlyRoom,blockUser,unblockUser,listBlockedUsers,reportUser,reportMessage,setConversationMuted,
  openDirectMessage,sendDirectMessage,markDirectMessageRead,billingHealth,verifyPurchase,restorePurchases,deleteAccount
};
async function resolveLegacyForV1(uid){
  const id=cleanString((await db.ref(`rankedState/activeByUser/${uid}`).get()).val(),40);
  if(!validServerMatchId(id))return;
  const ref=db.ref(`rankedState/matches/${id}`);await ref.get();
  const tx=await ref.transaction(value=>{
    if(value===null)return null;const match=hydrateMatch(value);
    if(match.participants?.[uid]!==true)return;
    if(!match.result){match.result={type:'cancelled',winner:'draw',reason:'protocol-upgrade',finishedAt:now()};match.status='cancelled';match.settlementStatus='pending';}
    return match;
  },undefined,false);
  if(tx.committed&&tx.snapshot.val()?.result)await settleRankedMatch(id);
}
const {installBattleV1Friendly}=require('./lib/battle-v1-friendly');
const {installBattleV1Emotes}=require('./lib/battle-v1-emotes');
const battleV1=installBattleV1Friendly(installBattleV1Recovery(installBattleV1Rollout(createBattleV1Api({db,now,requirePlayer,rateLimit}),{requirePlayer,rateLimit,resolveLegacyForV1}),{requirePlayer,rateLimit,logger}),{requirePlayer,rateLimit,resolveLegacyForV1,assertInteractionAllowed,requireFriendship,withSocialPairLock});
ROUTES.getBattleV1=battleV1.getBattleV1;
installBattleV1Emotes(battleV1,{requirePlayer,rateLimit});
ROUTES.sendBattleV1Emote=battleV1.sendBattleV1Emote;
ROUTES.getBattleV1Emotes=battleV1.getBattleV1Emotes;
ROUTES.submitBattleV1Action=battleV1.submitBattleV1Action;
for(const name of ['enqueueBattleV1','cancelBattleV1Queue','setBattleV1Deck','getBattleV1Deck','getBattleV1Rollout','resignBattleV1','ackBattleV1Result'])ROUTES[name]=battleV1[name];
for(const name of ['createBattleV1Room','cancelBattleV1Room','joinBattleV1Room','sendBattleV1Invite','respondBattleV1Invite'])ROUTES[name]=battleV1[name];
async function handler(req,res){
  const startedAt=Date.now();
  let correlationId=crypto.randomUUID(),route='',uidHash='',appId='';
  try{
    if(applyCors(req,res))return;
    if(req.method!=='POST')throw httpError(405,'method-not-allowed','Only POST is allowed.');
    correlationId=requestId(req);
    route=String(req.path||'').replace(/^\/+|\/+$/g,'');
    const operation=Object.hasOwn(ROUTES,route)?ROUTES[route]:null;
    if(!operation)throw httpError(404,'route-not-found','Unknown API operation.');
    const token=await authenticate(req),uid=token.uid;
    const appCheck=await verifyAppAttestation(req,{allowAuthFallback:AUTH_FALLBACK_ROUTES.has(route)});
    uidHash=hash(uid).slice(0,12);
    appId=cleanString(appCheck&&appCheck.appId||appCheck&&appCheck.app_id||'',96);
    if(appCheck&&appCheck.degraded)logger.warn('Luno API using Firebase Auth fallback',{requestId:correlationId,route,uidHash,appId});
    await assertAccountOperationAllowed(uid,route);
    const result=await operation({uid,token,appCheck,body:req.body||{},requestId:correlationId,req});
    if(route!=='deleteAccount')await assertAccountOperationAllowed(uid,route);
    logger.info('Luno API request complete',{requestId:correlationId,route,uidHash,appId,status:200,latencyMs:Date.now()-startedAt});
    res.status(200).json(Object.assign({ok:true},result||{}));
  }catch(error){
    const status=Number(error&&error.status)||500;
    const code=cleanString(error&&error.code||'internal',80);
    const context={requestId:correlationId,route:route||String(req.path||''),uidHash,appId,status,code,latencyMs:Date.now()-startedAt};
    if(status>=500)logger.error('Luno API error',Object.assign({},context,{error:String(error&&error.stack||error)}));
    else logger.warn('Luno API request rejected',context);
    res.status(status).json({ok:false,error:code,requestId:correlationId});
  }
}

exports.lunoApi=onRequest({invoker:'public'},handler);
exports.sweepRankedMatches=onSchedule({schedule:'every 1 minutes',timeZone:'Etc/UTC',retryCount:0},sweepRankedMatchesJob);
exports.sweepBattleV1=onSchedule({schedule:'every 1 minutes',timeZone:'Etc/UTC',retryCount:0},battleV1.sweep);
exports.playBillingNotifications=onMessagePublished({topic:BILLING_RTDN_TOPIC,retry:true},handlePlayBillingNotification);
const testApi={
  battleV1,
  claimDailyReward,claimOnboardingReward,
  writePurchaseClaim,writeModerationReport,completedConsumableReplay,fulfillPurchase,reconcilePlayNotification,recomputePremiumFromClaims,
  reportUser,reportMessage,
  anonymizePurchaseClaim,anonymizeModerationReport,retireAccountRecords,
  purchaseSoftItem,
  openChest,openPassChest,requestClaimCanRecover,passChestOpeningReplay,shopChestOpeningReplay,PASS_CHEST_RECOVERY_MS,
  writeAccountMetadata,writeAccountAudit,writeAccountLinkTicket,releaseAccountLinkTicket,rateLimit,
  deleteAccount,idempotent,repairPlayerCodeIndex,reconcilePlayerCodeState,releaseOwnedIndex,
  getPlayerState,repairBattleV1ProductProgress,createGuestPlayer,reconcileUsernameState,withUsernameLock,withSocialPairLock,publishPlayerCode,isIncompleteGuestProfile,normalizeLoginActivity,
  getRankedMatch,submitMatchAction,heartbeatRankedMatch,sendRankedMessage,
  acknowledgeDirectMessage,markDirectMessageRead,directMessageInboxVersion,
  updateProfile,
  nextProfileUpdateTime,authoritativeState,
  publishPublicProfile,
  settleRankedMatch,transactExistingPlayer,leaveRankedBeforeDeletion,assertAccountOperationAllowed,
  normalizeUsername,usernameValidationError,canonicalUsername,usernameRevision,applyUsernameProfileChange,releaseUsernameIfOwned,starterProfile,publicProfile,validateDeck,validUid,conversationId,handler,PRODUCT_CATALOG,hash,playerCode,assertBodyKeys,verifyAppAttestation,APP_CHECK_EMULATOR_TOKEN,AUTH_FALLBACK_ROUTES,friendlyDurationMinutes,
  LEGAL_TERMS_VERSION,LEGAL_PRIVACY_VERSION,LEGAL_COMMUNITY_VERSION,legalConsentState,assertCurrentLegalConsent,
  tokenHasProvider,profileHasProtectedProgress,linkAttemptId,
  SERVER_SCHEMA_VERSION,applyDailyRewardClaim,applyRewardClaim,applySoftPurchase,economySnapshot,periodSnapshot,
  sourceClaimKey,utcDayKey,utcDayOrdinal,utcWeekKey,seasonBounds,normalizeSeasonRecord,achievementValue,missionPeriodId,seasonState,
  missionProgress,rewardSchedule,achievementSchedule,missionPassXp,grantMissionPassXp,selectedMissionIds,syncServerPass,ACHIEVEMENT_CATALOG,ACHIEVEMENT_COPY,MISSION_CATALOG,MISSION_COPY,
  PASS_CURRENCY_REWARDS,PASS_CONTENT_REWARDS,SEASON_PATH_REWARDS,SEASON_REWARDS,SOFT_ITEM_CATALOG,CARD_UPGRADE_CATALOG,CHEST_CATALOG,
  softItemOwned,grantSoftItem,grantPassContent,serverInventory,rollChest,applyChestInventoryRewards,knownSelection,ownsSelection,canonicalPieceSetId,canonicalDeckForProfile,
  validRankedMatchId,validServerMatchId,rankedMatchId,friendlyMatchId,friendlyRoomCode,rankedOutcome,queueRange,sweepRankedMatchesJob,applyRankedSettlement,
  LEADERBOARD_FIELDS,LEADERBOARD_MAX_LIMIT,normalizeLeaderboardLimit,leaderboardRows,collectionScoreForProfile,
  getLeaderboard,getPublicPlayerProfile,getPublicPlayerProfiles,getFriends,searchPlayers,readBattleV1PublicPlayer,
  ONBOARDING_REWARD,SOCIAL_VISIT_REWARDS,USERNAME_CHANGE_COST,subscriptionExpiry,subscriptionLifecycle,applyVerifiedPurchaseGrant,applyVoidedPurchaseRevocation,decodeRtdnNotification,rtdnKind
};

// Optional V215 measurement routes share the existing Auth/App Check boundary.
const {createProductTelemetryApi}=require('./lib/product-telemetry');
const productTelemetry=createProductTelemetryApi({db,now,requirePlayer,rateLimit,
  transactExistingPlayer,writeAccountMetadata,assertAccountOperationAllowed});
Object.assign(ROUTES,productTelemetry.routes);
Object.assign(testApi,productTelemetry.routes,{purgeProductTelemetryForUser:productTelemetry.purgeUser});
exports.sweepProductTelemetry=onSchedule({schedule:'every 24 hours',timeZone:'Etc/UTC',retryCount:0},productTelemetry.sweep);
// SDK discovery recursively visits enumerable exports, including cyclic Admin SDK objects.
Object.defineProperty(exports,'_test',{value:testApi,enumerable:false});
