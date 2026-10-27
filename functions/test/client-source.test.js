'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');

const ROOT=path.resolve(__dirname,'..','..');
const html=fs.readFileSync(path.join(ROOT,'luno-chess.html'),'utf8');
const auth=fs.readFileSync(path.join(ROOT,'assets','luno-production-auth.js'),'utf8');
const polish=fs.readFileSync(path.join(ROOT,'assets','luno-release-polish.js'),'utf8');
const art=fs.readFileSync(path.join(ROOT,'assets','luno-art-override.js'),'utf8');
const buildConfig=fs.readFileSync(path.join(ROOT,'assets','luno-build-config.js'),'utf8');
const runtimeGovernor=fs.readFileSync(path.join(ROOT,'assets','luno-runtime-governor.js'),'utf8');
const battleFlow=fs.readFileSync(path.join(ROOT,'assets','luno-battle-flow-v23.js'),'utf8');
const battleCss=fs.readFileSync(path.join(ROOT,'assets','luno-battle-flow-v23.css'),'utf8');
const releaseCss=fs.readFileSync(path.join(ROOT,'assets','luno-release-polish-v22.css'),'utf8');
const androidMain=fs.readFileSync(path.join(ROOT,'luno_android','android','app','src','main','java','com','luno','chess','MainActivity.java'),'utf8');
const androidAppCheck=fs.readFileSync(path.join(ROOT,'luno_android','android','app','src','main','java','com','luno','chess','LunoAppCheckInitializer.java'),'utf8');
const androidBilling=fs.readFileSync(path.join(ROOT,'luno_android','android','app','src','main','java','com','luno','chess','LunoBillingPlugin.java'),'utf8');
const androidManifest=fs.readFileSync(path.join(ROOT,'luno_android','android','app','src','main','AndroidManifest.xml'),'utf8');
const googleServices=JSON.parse(fs.readFileSync(path.join(ROOT,'luno_android','android','app','google-services.json'),'utf8'));
const androidWebHtml=fs.readFileSync(path.join(ROOT,'luno_android','www','index.html'),'utf8');
const androidPackagedHtml=fs.readFileSync(path.join(ROOT,'luno_android','android','app','src','main','assets','public','index.html'),'utf8');
const androidPackagedAuth=fs.readFileSync(path.join(ROOT,'luno_android','android','app','src','main','assets','public','assets','luno-production-auth.js'),'utf8');

function namedFunctionSource(source,name){
  const marker='function '+name+'(';
  const start=source.indexOf(marker);
  assert.notEqual(start,-1,'Missing function '+name);
  const open=source.indexOf('{',start+marker.length);
  let depth=0,quote='',escaped=false,lineComment=false,blockComment=false;
  for(let index=open;index<source.length;index+=1){
    const char=source[index],next=source[index+1];
    if(lineComment){if(char==='\n')lineComment=false;continue;}
    if(blockComment){if(char==='*'&&next==='/'){blockComment=false;index+=1;}continue;}
    if(quote){
      if(escaped){escaped=false;continue;}
      if(char==='\\'){escaped=true;continue;}
      if(char===quote)quote='';
      continue;
    }
    if(char==='/'&&next==='/'){lineComment=true;index+=1;continue;}
    if(char==='/'&&next==='*'){blockComment=true;index+=1;continue;}
    if(char==='\''||char==='"'||char==='`'){quote=char;continue;}
    if(char==='{')depth+=1;
    if(char==='}'&&--depth===0)return source.slice(start,index+1);
  }
  assert.fail('Unclosed function '+name);
}

test('every inline game script parses before the UI boots',function(){
  const scripts=[...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi)];
  assert.ok(scripts.length>=8,'inline game scripts were not discovered');
  scripts.forEach(function(match,index){
    assert.doesNotThrow(function(){
      new vm.Script(match[1],{filename:'luno-inline-'+(index+1)+'.js'});
    });
  });
});

test('protected purchase entry points fail closed instead of mutating local balances',function(){
  const names=[
    'buyCostume','buyCostumePack','buyOrEquipOttoman','openChest','buySkin','buyEmojiPack',
    'confirmBuyPass','selectBioFrame','buyFrame','buyOrEquipPieceSet','upgradeCard'
  ];
  names.forEach(function(name){
    const body=namedFunctionSource(html,name);
    assert.doesNotMatch(body,/PLAYER\.(?:gold|gems)\s*(?:\+|-)?=/,name+' changes a local balance');
    assert.doesNotMatch(body,/inventory\.(?:ownedSkins|ownedEmojis|ownedFrames|ownedBioFrames|ownedCostumes|ownedSets)\.push\s*\(/,name+' grants local ownership');
    assert.match(body,/luno(?:PurchaseSoftItem|OpenChestSecure|UpgradeCardSecure)/,name+' does not delegate to the secure bridge');
  });
});

test('production bridge owns every protected purchase entry point',function(){
  const routes=['/purchaseSoftItem','/openChest','/upgradeCard'];
  routes.forEach(function(route){assert.match(auth,new RegExp("secureApi\\('"+route.replace('/','\\/')+"'"));});
  const overrides=[
    'buySkin','buyEmojiPack','buyCostume','buyCostumePack','buyOrEquipPieceSet','buyOrEquipOttoman',
    'confirmBuyPass','buyFrame','selectBioFrame','openChest','upgradeCard'
  ];
  overrides.forEach(function(name){assert.match(auth,new RegExp('window\\.'+name+'\\s*='),name+' is not overridden securely');});
});

test('the secure production bridge loads after the visual override layer',function(){
  const build=html.indexOf('assets/luno-build-config.js');
  const artIndex=html.indexOf('assets/luno-art-override.js');
  const polish=html.indexOf('assets/luno-release-polish.js');
  const flow=html.indexOf('assets/luno-v12-flow.js');
  const authIndex=html.indexOf('assets/luno-production-auth.js');
  assert.ok(build>=0&&artIndex>build,'build config and art layer load order is invalid');
  assert.ok(polish>=0,'release polish script is missing');
  assert.ok(flow>polish,'V12 flow must load statically after release polish');
  assert.ok(authIndex>flow,'production auth must load after every visual override');
  assert.doesNotMatch(art,/createElement\(['"]script['"]\)/,'critical V12 flow is still injected dynamically');
  assert.match(html,/id="luno-v12-flow-css"/,'V12 stylesheet is not statically declared');
});

test('battle flow is single-entry, duration-aware and loaded after the secure bridge',function(){
  assert.ok(html.indexOf('luno-production-auth.js')<html.indexOf('luno-battle-flow-v23.js'));
  assert.match(battleFlow,/\[1,3,5,10,30\]/);
  assert.match(battleFlow,/window\.openMatchModes=function/);
  assert.match(battleFlow,/window\.LUNO_FRIEND_DURATION_MINUTES=state\.friendMinutes/);
  assert.match(auth,/durationMinutes:Number\(window\.LUNO_FRIEND_DURATION_MINUTES\)\|\|5/);
  assert.match(battleCss,/\.lbf-modes/);
  assert.equal(fs.existsSync(path.join(ROOT,'assets','luno-art','menu-battle-hero-v23.webp')),true);
});

test('native startup applies the balanced thermal profile before hidden screens are parsed',function(){
  const bootstrap=html.indexOf('id="lunoNativeBootstrap"');
  const firebase=html.indexOf('firebase-app-compat.js');
  const body=html.indexOf('<body>');
  assert.ok(bootstrap>=0&&bootstrap<firebase&&bootstrap<body,'native bootstrap runs too late');
  assert.match(html,/luno-native-shell/,'native shell marker is missing');
  assert.match(releaseCss,/screen:not\(\.active\):not\(\.screen-leaving\)[\s\S]*content-visibility:hidden/);
  assert.match(runtimeGovernor,/classList\.toggle\('lowfx',mode==='low'\)/,'balanced mode still enables the destructive low profile');
  assert.match(art,/LUNO_MENU_MOTION_OWNER='image-art-v10'/);
  assert.doesNotMatch(art,/Object\.keys\(poses\)\.forEach\([^\n]*new Image/,'all mascot poses are decoded during cold boot');
});

test('screen transitions use a bounded compositor-only motion budget',function(){
  const keyframes=[...releaseCss.matchAll(/@keyframes luno-screen-[^{]+\{([\s\S]*?)^\}/gm)];
  assert.equal(keyframes.length,6,'the directional screen transition set is incomplete');
  keyframes.forEach(function(match){
    assert.doesNotMatch(match[1],/(?:filter|backdrop-filter|box-shadow)\s*:/,'a screen transition paints an expensive effect every frame');
    assert.match(match[1],/transform:/,'a screen transition is not compositor driven');
  });
  assert.match(releaseCss,/\.screen\{will-change:auto!important;backface-visibility:hidden/);
  assert.match(releaseCss,/\.screen\[class\*="luno-screen-enter-"\][\s\S]{0,160}will-change:transform,opacity/);
  assert.match(releaseCss,/\.mn-navitem\.luno-nav-settle[\s\S]{0,140}280ms/);
  assert.doesNotMatch(html,/\.board\s*,\s*\.sq\s*,\s*\.pc\s*,/,'every board square and piece still receives its own forced GPU layer');
  assert.doesNotMatch(html,/[^{}]*\.sq[^{}]*\{[^{}]*transform\s*:\s*translateZ\(0\)/,'board squares still receive individual compositor layers');
  assert.doesNotMatch(html,/@keyframes screen-(?:enter|leave)\{[^@]*filter\s*:/,'the legacy transition fallback still animates blur');
  assert.match(html,/\.board\s*,\s*\.flypiece\s*,\s*\.fly-card\s*\{\s*(?:-webkit-)?transform:translateZ\(0\)/);
});

test('native thermal protection is adaptive, finite and user-overridable',function(){
  assert.match(runtimeGovernor,/frameProbeRuns>=2/,'frame sampling is not capped');
  assert.match(runtimeGovernor,/luno-auto-constrained/,'adaptive decoration limiting is missing');
  assert.match(runtimeGovernor,/average>30\|\|longRatio>\.42/,'severe frame pressure does not lower the graphics profile');
  assert.match(runtimeGovernor,/if\(persist\)[\s\S]{0,220}luno-auto-constrained/,'an explicit graphics choice cannot override adaptation');
  assert.doesNotMatch(runtimeGovernor,/setInterval\s*\(/,'the thermal governor runs a perpetual polling loop');
  assert.match(releaseCss,/html\.luno-mobile-perf \.stage::after\{display:none!important;\}/);
  assert.match(releaseCss,/html\.luno-auto-constrained \.screen\.active/);
});

test('Android startup fails open when optional Firebase services are unavailable',function(){
  assert.match(androidManifest,/FirebaseInitProvider[\s\S]*tools:node="remove"/);
  assert.match(androidMain,/super\.onCreate\(savedInstanceState\);[\s\S]*postDeferredStartup\(\)/);
  assert.match(androidMain,/WebView\.setWebContentsDebuggingEnabled\(false\)/);
  assert.match(androidAppCheck,/FirebaseOptions\.fromResource\(context\)/);
  assert.match(androidAppCheck,/if \(options == null\)[\s\S]*return false/);
  assert.doesNotMatch(androidBilling,/getUnfetchedProductList\(\)\.forEach/,'billing still calls an Android 7 API on API 23');
});

test('Android Firebase identity matches the production package and project',function(){
  const client=googleServices.client.find(function(entry){
    return entry&&entry.client_info&&entry.client_info.android_client_info&&entry.client_info.android_client_info.package_name==='com.luno.chess';
  });
  assert.ok(client,'com.luno.chess is missing from google-services.json');
  assert.equal(googleServices.project_info.project_id,'luno-chess');
  assert.equal(client.client_info.mobilesdk_app_id,'1:955253747543:android:136188eaab561c9b29d812');
});

test('critical board and promotion piece images are never lazy loaded',function(){
  const pieceMarkup=namedFunctionSource(html,'pieceHTML');
  assert.match(pieceMarkup,/loading="eager"/);
  assert.match(pieceMarkup,/fetchpriority="high"/);
  assert.match(pieceMarkup,/preloadPieceSet\(setId\)/);
  assert.match(namedFunctionSource(html,'preloadPieceSet'),/_piecePreloadOrder\.length>2/);
  assert.match(polish,/promo[\s\S]*loading="eager"[\s\S]*fetchpriority="high"/);
});

test('build metadata is centralized and matches Android release metadata',function(){
  const gradle=fs.readFileSync(path.join(ROOT,'luno_android','android','app','build.gradle'),'utf8');
  assert.match(buildConfig,/versionName:'1\.5\.7'/);
  assert.match(buildConfig,/versionCode:12/);
  assert.match(gradle,/versionName\s+"1\.5\.7"/);
  assert.match(gradle,/versionCode\s+12/);
  assert.doesNotMatch(polish,/Yapım 2/);
  assert.doesNotMatch(html,/RELEASE 2/);
});

test('Android package contains the current online bridge and cache-busted release assets',function(){
  assert.equal(androidWebHtml,html,'Android www index drifted from the source index');
  assert.equal(androidPackagedHtml,html,'packaged Android index drifted from the source index');
  assert.equal(androidPackagedAuth,auth,'packaged production bridge drifted from the source bridge');
  assert.match(html,/luno-production-auth\.js\?v=156-0823a/);
  assert.match(html,/luno-v12-flow\.css\?v=156-0823a/);
  assert.doesNotMatch(androidPackagedHtml,/v=150-0813a/);
  assert.doesNotMatch(androidPackagedAuth,/startLegacyRecovery/);
});

test('guest-first release contains no legacy email or password collection surface',function(){
  const shipped=[html,polish,auth,androidWebHtml,androidPackagedHtml,androidPackagedAuth].join('\n');
  assert.doesNotMatch(shipped,/type=["']password/i);
  assert.doesNotMatch(shipped,/current-password|new-password|loginPw|regPw|forgotPassword/i);
  assert.doesNotMatch(shipped,/HESABINA GİRİŞ YAP|GOOGLE İLE KAYDOL|ŞİFRE TEKRARI/i);
  assert.doesNotMatch(html,/<(?:section|div)[^>]+id=["'](?:intro|login|register)["']/i);
});

test('interactive tutorial resumes safely, advances through every step and completes once',function(){
  const start=namedFunctionSource(html,'tutStart');
  const advance=namedFunctionSource(html,'tutAdvance');
  const close=namedFunctionSource(html,'tutClose');
  const finish=namedFunctionSource(html,'tutFinish');
  const stepBlock=html.slice(html.indexOf('var ITUT_STEPS=['),html.indexOf('var ITUT=',html.indexOf('var ITUT_STEPS=[')));
  const stepCount=(stepBlock.match(/\{masc:/g)||[]).length;
  assert.equal(stepCount,9,'the guided tutorial must keep all nine authored steps');
  assert.match(stepBlock,/action:'select'/,'tutorial does not teach selection interactively');
  assert.match(stepBlock,/action:'move'/,'tutorial does not teach movement interactively');
  assert.match(stepBlock,/action:'capture'/,'tutorial does not teach capture interactively');
  assert.match(stepBlock,/action:'card'/,'tutorial does not teach card targeting interactively');
  assert.match(start,/Math\.max\(0,Math\.min\(ITUT_STEPS\.length-1/,'a damaged saved step is not clamped');
  assert.match(start,/!localStorage\.getItem\('lunoTutorialDone'\)/,'a completed tutorial can resume unexpectedly');
  assert.match(advance,/ITUT\.step\+\+/,'tutorial advance does not move exactly one step');
  assert.match(advance,/localStorage\.setItem\('lunoTutorialStep',String\(ITUT\.step\)\)/,'tutorial progress is not persisted');
  assert.match(advance,/ITUT\.step>=ITUT_STEPS\.length-1/,'the last step is not guarded');
  assert.match(advance,/tutFinish\(\);return/,'the last step can wrap back to the beginning');
  assert.match(close,/localStorage\.setItem\('lunoTutorialDone','1'\)/,'tutorial completion is not persisted');
  assert.match(close,/localStorage\.removeItem\('lunoTutorialStep'\)/,'stale progress remains after completion');
  assert.match(finish,/tutClose\(\)/,'the finish path bypasses durable completion');
  assert.match(finish,/startOnboarding|onboardVsBebekLuno/,'tutorial completion does not continue into first-match onboarding');
});

test('username changes are server-authoritative and legacy e-mail lookup is absent',function(){
  const body=namedFunctionSource(html,'openUsernameChange');
  assert.match(body,/lunoOpenUsernameChangeSecure/);
  assert.doesNotMatch(body,/PLAYER\.(?:gold|usernameChanges)\s*(?:\+|-)?=/);
  assert.doesNotMatch(body,/FB_DB\.ref\(['"](?:users|usernames)\//);
  assert.match(auth,/secureApi\('\/changeUsername'/);
  assert.match(auth,/window\.openUsernameChange\s*=\s*openUsernameChangeSecure/);
  assert.doesNotMatch(html,/usernameEmails/);
});

test('legacy progression helpers cannot mutate protected currency or trophy state',function(){
  ['applyChestRewards','awardMatchGold','gainXp','claimSpecialPassMission','updateTrophies','checkSeasonChange'].forEach(function(name){
    const body=namedFunctionSource(html,name);
    assert.doesNotMatch(body,/PLAYER\.(?:gold|gems|trophies)\s*(?:\+|-)?=/,name+' mutates protected local state');
  });
  ['saveInventory','saveMissions','savePassMissions','saveSeason'].forEach(function(name){
    assert.doesNotMatch(namedFunctionSource(html,name),/FB_DB\.ref\(/,name+' writes protected Firebase state');
  });
  assert.equal(auth.includes("'/claimOnboardingReward'"),true);
  assert.equal(auth.includes("'/claimSocialVisitReward'"),true);
});

test('Google linking preserves the guest UID and records conflicts without persisting credentials',function(){
  assert.match(auth,/secureApi\('\/prepareGoogleLink'/);
  assert.match(auth,/secureApi\('\/completeGoogleLink'/);
  assert.match(auth,/secureApi\('\/recordGoogleLinkConflict'/);
  assert.match(namedFunctionSource(html,'_lgLinkCredential'),/user\.linkWithCredential\(credential\)/);
  assert.match(namedFunctionSource(html,'googleAuth'),/\.linkWithPopup\(provider\)/);
  assert.match(namedFunctionSource(html,'_lgOnUser'),/user\.uid!==_lgOriginUid/);
  assert.match(namedFunctionSource(html,'_lgErr'),/lunoRecordGoogleLinkConflictSecure/);
  assert.match(auth,/MEVCUT BULUT HESABIMLA DEVAM ET/);
  assert.match(auth,/DESTEK İLE BİRLEŞTİR/);
  assert.doesNotMatch(html,/localStorage\.setItem\([^\n]*(?:Credential|idToken|Google)/i);
  assert.doesNotMatch(auth,/localStorage\.setItem\([^\n]*(?:Credential|idToken|Google)/i);
});

test('ranked matchmaking and match actions are owned by the secure production bridge',function(){
  const body=namedFunctionSource(auth,'installSecureRanked');
  ['/enqueueRanked','/cancelRankedQueue','/getRankedMatch','/submitMatchAction','/heartbeatRankedMatch','/sendRankedMessage'].forEach(function(route){
    assert.match(body,new RegExp("secureApi\\('"+route.replace('/','\\/')+"'"),route+' is missing from the ranked bridge');
  });
  ['startMatchmaking','cancelMatchmaking','sendActionToServer','sendMoveToServer','startGameTimer','endGame','endGameAbs','resign','sendChatMessage','sendEmoji'].forEach(function(name){
    assert.match(body,new RegExp('window\\.'+name+'\\s*='),name+' is not overridden for authoritative ranked play');
  });
  assert.doesNotMatch(body,/FB_DB\.ref\(['"](?:queue|matches|rooms)\//,'secure ranked bridge writes a legacy client-authoritative match path');
  assert.doesNotMatch(body,/winner\s*:/,'client ranked bridge submits a winner');
  assert.match(body,/rankedMessages\//,'secure ranked chat listens only to the owner feed');
  assert.doesNotMatch(body,/child\(['"](?:chat|emoji)['"]\)\.set/,'secure ranked chat must not write legacy room chat paths');
  assert.match(body,/rankedShow\.__lunoOriginal=previous\.show/,'ranked route wrapper breaks the guarded show ownership chain');
  assert.match(auth,/getIdToken\(false\)/,'API calls should reuse Firebase tokens instead of forcing a refresh for every move');
});

test('secure social bridge owns indexed search, moderation and direct messages',function(){
  const body=namedFunctionSource(auth,'installSecureSocial');
  ['/searchPlayers','/sendFriendRequest','/respondFriendRequest','/removeFriend','/openDirectMessage','/markDirectMessageRead','/blockUser','/unblockUser','/listBlockedUsers','/reportUser','/reportMessage','/setConversationMuted'].forEach(function(route){
    assert.match(body,new RegExp("secureApi\\('"+route.replace('/','\\/')+"'"),route+' is missing from the secure social bridge');
  });
  const directMessage=namedFunctionSource(auth,'sendDirectMessageSecure');
  assert.match(directMessage,/secureApi\('\/sendDirectMessage'/,'direct messages do not pass through the legal-consent-aware secure helper');
  assert.match(body,/sendDirectMessageSecure\(/,'the secure social bridge bypasses the direct-message helper');
  ['searchPlayers','addFriendByUid','acceptFriendRequest','rejectFriendRequest','removeFriend','openDM','sendDM','markDMRead','markDMInboxRead','sendWelcomeDM'].forEach(function(name){
    assert.match(body,new RegExp('window\\.'+name+'\\s*='),name+' is not securely overridden');
  });
  assert.doesNotMatch(body,/FB_DB\.ref\(['"]publicProfiles['"]\)\.once/,'secure player search downloads all public profiles');
  assert.doesNotMatch(body,/FB_DB\.ref\(['"](?:friends|friendRequests|dm|dmInbox)\//,'secure social bridge writes a legacy social path');
  assert.match(html,/Kullanıcı adı veya LUNO kodu ile ara/);
});

test('guest bootstrap retries the authoritative profile flow and never traps the player behind a retry gate',function(){
  const bootstrap=namedFunctionSource(html,'bootstrapAuthenticatedPlayer');
  const gate=namedFunctionSource(auth,'showGuestBootError');
  assert.match(bootstrap,/lunoRefreshAuthoritativeState/);
  assert.match(bootstrap,/profile-not-found/);
  assert.match(bootstrap,/requestGuestUsername/);
  assert.doesNotMatch(bootstrap,/FB_DB\.ref\(['"]users\//,'guest bootstrap probes the protected profile path directly');
  assert.match(html,/window\.lunoRetryGuestBootstrap=function\(\)[\s\S]{0,700}lunoEnsureGuestSession[\s\S]{0,500}bootstrapAuthenticatedPlayer/);
  assert.match(gate,/lunoStartOfflineGuest/);
  assert.doesNotMatch(gate,/lunoGuestRetry|TEKRAR DENE/);
  assert.match(html,/window\.lunoStartOfflineGuest=function/);
  assert.doesNotMatch(auth,/lunoStartLegacyRecovery|startLegacyRecovery/,'removed legacy account recovery still aborts the production bridge');
  assert.match(auth,/injectStyles\(\);installSettingsPatch\(\);installSecureSocial\(\);installSecureRanked\(\)/);
  assert.doesNotMatch(auth,/installShowGuard|screenId==='login'|screenId==='register'/);
});

test('production HTML contains no direct client write to protected Firebase paths',function(){
  const protectedPath=/^(?:users|inventory|gold|gems|trophies|premium|pass|season|achievement|achievements|missions|friends|friendRequests|outgoingFriendRequests|matchInvites|rooms|queue|notifications|ranked|rankedState|purchaseEntitlements|rewardLedger|matchHistory|matches|dm|dmInbox)(?:\/|$)/;
  const directWrites=html.split(/\r?\n/).filter(function(line){
    return /FB_DB\.ref\(/.test(line)&&/\.(?:set|update|push|transaction|remove)\s*\(/.test(line)&&
      /FB_DB\.ref\(\s*['"`](?:users|inventory|gold|gems|trophies|premium|pass|season|achievement|achievements|missions|friends|friendRequests|outgoingFriendRequests|matchInvites|rooms|queue|notifications|ranked|rankedState|purchaseEntitlements|rewardLedger|matchHistory|matches|dm|dmInbox)(?:\/|['"`])/.test(line);
  });
  const functionNames=['addFriendByUid','sendMatchInvite','createOnlineRoomWithCode','onlineCreateRoom','sendNotification','startMatchmaking','searchAndAddFriend','sendDM','markDMRead','markDMInboxRead','saveMatchHistory'];
  functionNames.forEach(function(name){
    const body=namedFunctionSource(html,name),aliases=[];
    const aliasPattern=/(?:var|let|const)\s+([A-Za-z_$][\w$]*)\s*=\s*FB_DB\.ref\(\s*(['"`])([^'"`]+)\2[^)]*\)/g;
    let alias;
    while((alias=aliasPattern.exec(body))){if(protectedPath.test(alias[3]))aliases.push(alias[1]);}
    aliases.forEach(function(identifier){
      const writePattern=new RegExp('\\b'+identifier.replace(/[$]/g,'\\$&')+'\\s*\\.\\s*(?:set|update|push|transaction|remove)\\s*\\(');
      if(writePattern.test(body))directWrites.push(name+':'+identifier);
    });
  });
  assert.deepEqual(directWrites,[],'protected Firebase writes remain in the production client');
  assert.match(html,/FB_DB\.ref\(['"]presence\//,'the allowed user-owned presence write disappeared');
  assert.doesNotMatch(html,/FB_DB\.ref\(['"]publicProfiles['"]\)\.once/,'leaderboard still downloads every public profile');
  assert.match(html,/lunoSecureApi\('\/getLeaderboard'/);
  assert.match(html,/lunoSecureApi\('\/markNotificationRead'/);
});

test('friendly invitations and room codes use the server-authoritative match bridge',function(){
  const body=namedFunctionSource(auth,'installSecureSocial');
  for(const route of ['/sendMatchInvite','/cancelMatchInvite','/respondMatchInvite','/createFriendlyRoom','/cancelFriendlyRoom','/joinFriendlyRoom']){
    assert.match(body,new RegExp("secureApi\\('"+route.replace('/','\\/')+"'"),route+' is missing from the production bridge');
  }
  for(const name of ['sendMatchInvite','acceptMatchInvite','rejectMatchInvite','onlineCreateRoom','onlineJoinRoom','cancelRoom','joinRoomByCode']){
    assert.match(body,new RegExp('window\\.'+name+'\\s*='),name+' is not overridden by the secure bridge');
  }
  assert.doesNotMatch(body,/FB_DB\.ref\(['"](?:rooms|matchInvites)\//,'secure friendly bridge writes a legacy client-authoritative path');
  assert.match(body,/lunoStartServerMatch/,'friendly matches do not enter the authoritative board runtime');
});

test('account deletion has one authoritative API path',function(){
  assert.match(auth,/secureApi\('\/deleteAccount',\{confirm:true\}\)/);
  assert.match(polish,/lunoRequestSecureAccountDeletion/);
  assert.doesNotMatch(polish,/accountDeletionRequests/);
});
