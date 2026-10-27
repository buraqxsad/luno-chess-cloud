'use strict';

const fs=require('node:fs');
const path=require('node:path');
const {google}=require('googleapis');
const PROJECT='luno-chess';
const NUMBER='955253747543';
const API='https://europe-west1-luno-chess.cloudfunctions.net/lunoApi';
const DB='https://luno-chess-default-rtdb.firebaseio.com';
const root=path.resolve(__dirname,'../../luno_chess/qa/v217');
const journal=JSON.parse(fs.readFileSync(path.join(root,'player-reset-journal.json'),'utf8'));
if(journal.projectId!==PROJECT||journal.projectNumber!==NUMBER||journal.phase!=='access-restored')throw new Error('Restored verified deployment is required.');
const cliRoot=process.env.LUNO_FIREBASE_CLI_ROOT;
if(!cliRoot)throw new Error('LUNO_FIREBASE_CLI_ROOT is required.');
const firebaseAuth=require(path.join(cliRoot,'lib/auth.js'));
const account=firebaseAuth.getGlobalDefaultAccount();
const client=new google.auth.OAuth2();
const routes=[
  'createGuestPlayer','prepareGoogleLink','completeGoogleLink','recordGoogleLinkConflict','changeUsername','getPlayerState','acceptLegalTerms',
  'claimDailyReward','claimOnboardingReward','claimSocialVisitReward','claimMissionReward','claimAchievementReward','claimPassReward','claimSeasonReward','claimSeasonPathReward',
  'purchaseSoftItem','upgradeCard','openChest','openPassChest','enqueueRanked','cancelRankedQueue','getRankedMatch','submitMatchAction','heartbeatRankedMatch','sendRankedMessage',
  'updateProfile','updatePreferences','getLeaderboard','getPublicPlayerProfile','getPublicPlayerProfiles','getFriends','searchPlayers','sendFriendRequest','respondFriendRequest','removeFriend',
  'markNotificationRead','sendMatchInvite','cancelMatchInvite','respondMatchInvite','createFriendlyRoom','cancelFriendlyRoom','joinFriendlyRoom','blockUser','unblockUser','listBlockedUsers',
  'reportUser','reportMessage','setConversationMuted','openDirectMessage','sendDirectMessage','markDirectMessageRead','billingHealth','verifyPurchase','restorePurchases','deleteAccount',
  'getBattleV1','submitBattleV1Action','enqueueBattleV1','cancelBattleV1Queue','setBattleV1Deck','getBattleV1Deck','getBattleV1Rollout','resignBattleV1','ackBattleV1Result',
  'createBattleV1Room','cancelBattleV1Room','joinBattleV1Room','sendBattleV1Invite','respondBattleV1Invite','sendBattleV1Emote','getBattleV1Emotes',
];
const evidence={projectId:PROJECT,observedAt:new Date().toISOString(),checks:[],
  acceptanceScope:'Live route/auth/attestation boundaries only; not authenticated gameplay or a two-client match.'};

async function fetchJson(url,options){
  const response=await fetch(url,{...options,signal:AbortSignal.timeout(30000)});
  let data;
  try{data=await response.json();}catch{throw new Error(`Expected JSON response, received HTTP ${response.status}.`);}
  return {status:response.status,data};
}
async function check(name,route,status,code,{method='POST',headers={},body={}}={}){
  const result=await fetchJson(`${API}/${route}`,{method,headers:{'Content-Type':'application/json',...headers},...(method==='POST'?{body:JSON.stringify(body)}:{})});
  const ok=result.status===status&&result.data?.error===code;
  evidence.checks.push({name,status:result.status,error:result.data?.error??null,ok});
  if(!ok)throw new Error(`Live boundary ${name} did not match the expected response.`);
}

async function main(){
  if(!account?.tokens?.refresh_token)throw new Error('Firebase CLI login is required.');
  const session=await firebaseAuth.getAccessToken(account.tokens.refresh_token,[]);
  client.setCredentials({access_token:session.access_token,expiry_date:session.expires_at});
  const project=(await client.request({url:`https://firebase.googleapis.com/v1beta1/projects/${PROJECT}`,timeout:30000})).data;
  if(project.projectId!==PROJECT||String(project.projectNumber)!==NUMBER)throw new Error('Project identity mismatch.');
  for(const route of routes)await check(`${route}: anonymous rejection`,route,401,'auth-required');
  await check('unknown route','not-a-luno-operation',404,'route-not-found');
  await check('inherited route','constructor',404,'route-not-found');
  await check('HTTP method','getPlayerState',405,'method-not-allowed',{method:'GET'});
  await check('invalid Firebase token','getPlayerState',401,'invalid-token',{headers:{Authorization:'Bearer invalid-live-smoke-token'}});
  const db=await fetchJson(`${DB}/.json`,{});
  const denied=db.status===401&&db.data?.error==='Permission denied';
  evidence.checks.push({name:'unauthenticated database root',status:db.status,ok:denied});
  if(!denied)throw new Error('Database root did not reject unauthenticated access.');

  const config=JSON.parse(fs.readFileSync(path.resolve(__dirname,'../../luno_chess/android/app/google-services.json'),'utf8'));
  if(config.project_info?.project_id!==PROJECT||String(config.project_info.project_number)!==NUMBER)throw new Error('Android Firebase config identity mismatch.');
  const android=config.client?.find(value=>value.client_info?.android_client_info?.package_name==='com.luno.chess');
  const key=android?.api_key?.[0]?.current_key;
  if(typeof key!=='string'||!key)throw new Error('Android Firebase public API key is missing.');
  let syntheticUid;
  try{
    const signup=await fetchJson(`https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${encodeURIComponent(key)}`,{
      method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({returnSecureToken:true})});
    if(signup.status!==200||!signup.data.localId||!signup.data.idToken)throw new Error('Live anonymous sign-up did not succeed.');
    syntheticUid=signup.data.localId;
    evidence.anonymousSignup={ok:true,syntheticAccount:true};
    await check('real anonymous ID token without App Check','getPlayerState',401,'app-check-required',{
      headers:{Authorization:`Bearer ${signup.data.idToken}`}});
  }finally{
    if(syntheticUid){
      const deleted=(await client.request({method:'POST',url:`https://identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts:batchDelete`,
        data:{localIds:[syntheticUid],force:true},timeout:30000})).data;
      if(deleted.errors?.length)throw new Error('Synthetic Auth account cleanup failed.');
      const lookup=(await client.request({method:'POST',url:`https://identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts:lookup`,
        data:{localId:[syntheticUid]},timeout:30000})).data;
      if(lookup.users?.length)throw new Error('Synthetic Auth account remains after cleanup.');
      evidence.syntheticAccountCleanup={ok:true,playerProfileCreated:false};
    }
  }
  evidence.completedAt=new Date().toISOString();
  evidence.passed=evidence.checks.every(value=>value.ok)&&evidence.anonymousSignup?.ok===true&&evidence.syntheticAccountCleanup?.ok===true;
  fs.writeFileSync(path.join(root,'firebase-live-api-smoke.json'),`${JSON.stringify(evidence,null,2)}\n`);
  process.stdout.write(`${JSON.stringify({passed:evidence.passed,checks:evidence.checks.length,
    anonymousSignup:evidence.anonymousSignup,syntheticAccountCleanup:evidence.syntheticAccountCleanup,
    authenticatedGameplay:'NOT TESTED',playIntegrityOnDevice:'NOT TESTED'},null,2)}\n`);
}
main().catch(error=>{
  evidence.passed=false;
  evidence.failure={status:error.response?.status??null,message:error.response?.data?.error?.message??error.message};
  fs.writeFileSync(path.join(root,'firebase-live-api-smoke.json'),`${JSON.stringify(evidence,null,2)}\n`);
  process.stderr.write(`${JSON.stringify(evidence.failure)}\n`);
  process.exitCode=1;
});
