'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');

const ROOT=path.resolve(__dirname,'..','..');
const API_BASE=process.env.LUNO_LIVE_API_BASE||'https://europe-west1-luno-chess.cloudfunctions.net/lunoApi';

function firebaseApiKey(){
  const config=JSON.parse(fs.readFileSync(path.join(ROOT,'luno_android','android','app','google-services.json'),'utf8'));
  const client=(config.client||[]).find(function(entry){
    return entry&&entry.client_info&&entry.client_info.android_client_info&&entry.client_info.android_client_info.package_name==='com.luno.chess';
  });
  const key=client&&client.api_key&&client.api_key[0]&&client.api_key[0].current_key;
  if(!key)throw new Error('Firebase Android API key is missing.');
  return key;
}

async function json(response){
  const body=await response.json().catch(function(){return {};});
  return {status:response.status,body};
}

async function anonymousUser(apiKey){
  const response=await fetch('https://identitytoolkit.googleapis.com/v1/accounts:signUp?key='+encodeURIComponent(apiKey),{
    method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({returnSecureToken:true}),signal:AbortSignal.timeout(15000)
  });
  const result=await json(response);
  assert.equal(result.status,200,JSON.stringify(result.body));
  assert.ok(result.body.localId&&result.body.idToken,'Anonymous sign-in did not return credentials.');
  return {uid:result.body.localId,idToken:result.body.idToken};
}

async function api(user,route,body,requestId){
  const appCheckToken=process.env.LUNO_LIVE_APPCHECK_TOKEN||'';
  const response=await fetch(API_BASE+route,{
    method:'POST',
    headers:Object.assign({authorization:'Bearer '+user.idToken,'content-type':'application/json','x-luno-request-id':requestId},appCheckToken?{'x-firebase-appcheck':appCheckToken}:{}),
    body:JSON.stringify(body||{}),
    signal:AbortSignal.timeout(20000)
  });
  return json(response);
}

function expectOk(result,label){
  assert.equal(result.status,200,label+': '+JSON.stringify(result.body));
  assert.notEqual(result.body.ok,false,label+': '+JSON.stringify(result.body));
  return result.body;
}

async function removeUser(user,label){
  if(!user||!user.idToken)return;
  const result=await api(user,'/deleteAccount',{confirm:true},'live-smoke-delete-'+label+'-'+Date.now());
  assert.equal(result.status,200,label+' cleanup failed: '+JSON.stringify(result.body));
  assert.equal(result.body.deleted,true,label+' cleanup did not delete the account');
}

async function main(){
  if(!process.argv.includes('--confirm-production'))throw new Error('Pass --confirm-production to run against production.');
  if(!process.env.LUNO_LIVE_APPCHECK_TOKEN)throw new Error('Set LUNO_LIVE_APPCHECK_TOKEN to a valid Play Integrity App Check token before running production smoke.');
  const key=firebaseApiKey(),suffix=Date.now().toString(36).slice(-7);
  const users=[];
  const report={apiBase:API_BASE,checks:[],cleanup:[]};
  try{
    const first=await anonymousUser(key),second=await anonymousUser(key);users.push(first,second);
    report.checks.push('anonymous-auth');

    expectOk(await api(first,'/createGuestPlayer',{username:'q'+suffix+'a'},'live-smoke-create-a-'+suffix),'create player A');
    expectOk(await api(second,'/createGuestPlayer',{username:'q'+suffix+'b'},'live-smoke-create-b-'+suffix),'create player B');
    report.checks.push('guest-bootstrap-auth-fallback');

    const firstState=expectOk(await api(first,'/getPlayerState',{},'live-smoke-state-a-'+suffix),'read player A');
    const secondState=expectOk(await api(second,'/getPlayerState',{},'live-smoke-state-b-'+suffix),'read player B');
    assert.equal(firstState.state.uid,first.uid);
    assert.equal(secondState.state.uid,second.uid);
    report.checks.push('authoritative-player-state');

    const liveBio='Live bio '+suffix;
    const profileUpdate=expectOk(await api(first,'/updateProfile',{bio:liveBio},'live-smoke-profile-'+suffix),'update profile bio');
    assert.equal(profileUpdate.state.profile.bio,liveBio);
    const profileSearch=expectOk(await api(second,'/searchPlayers',{query:'q'+suffix+'a'},'live-smoke-profile-search-'+suffix),'search updated profile');
    assert.equal(profileSearch.results.some(function(player){return player.uid===first.uid&&player.bio===liveBio;}),true,JSON.stringify(profileSearch.body));
    report.checks.push('profile-bio-and-public-search');

    const daily=expectOk(await api(first,'/claimDailyReward',{},'live-smoke-daily-'+suffix),'claim daily reward');
    assert.equal(daily.granted,true);
    assert.ok(daily.state&&daily.state.economy&&daily.state.economy.daily.nextReward.gold>0);
    const protectedPurchase=await api(first,'/purchaseSoftItem',{itemId:'skin:obsidian'},'live-smoke-strict-'+suffix);
    assert.equal(protectedPurchase.status,401,JSON.stringify(protectedPurchase.body));
    assert.equal(protectedPurchase.body.error,'app-check-required');
    report.checks.push('bounded-reward-fallback-and-purchase-app-check');

    expectOk(await api(first,'/getLeaderboard',{mode:'trophies',limit:10},'live-smoke-board-'+suffix),'leaderboard');
    expectOk(await api(first,'/sendFriendRequest',{targetUid:second.uid},'live-smoke-friend-send-'+suffix),'send friend request');
    expectOk(await api(second,'/respondFriendRequest',{fromUid:first.uid,accept:true},'live-smoke-friend-accept-'+suffix),'accept friend request');
    report.checks.push('leaderboard-and-friends');

    expectOk(await api(first,'/acceptLegalTerms',{},'live-smoke-legal-'+suffix),'accept legal terms');
    expectOk(await api(first,'/openDirectMessage',{targetUid:second.uid},'live-smoke-dm-open-'+suffix),'open direct message');
    expectOk(await api(first,'/sendDirectMessage',{targetUid:second.uid,text:'Luno live smoke '+suffix},'live-smoke-dm-send-'+suffix),'send direct message');
    expectOk(await api(second,'/markDirectMessageRead',{targetUid:first.uid},'live-smoke-dm-read-'+suffix),'read direct message');
    report.checks.push('direct-messages');

    const room=expectOk(await api(first,'/createFriendlyRoom',{durationMinutes:30},'live-smoke-room-create-'+suffix),'create friendly room');
    assert.equal(room.durationMinutes,30);
    assert.match(room.roomCode,/^[A-Z0-9]{6}$/);
    const joined=expectOk(await api(second,'/joinFriendlyRoom',{roomCode:room.roomCode},'live-smoke-room-join-'+suffix),'join friendly room');
    assert.match(joined.matchId,/^fm_[a-f0-9]{32}$/);
    const firstView=expectOk(await api(first,'/getRankedMatch',{matchId:joined.matchId},'live-smoke-match-read-'+suffix),'read friendly match');
    assert.equal(firstView.view.mode,'friendly');
    assert.equal(firstView.view.timeControlMinutes,30);
    assert.equal(firstView.view.clock.initialMs,1800000);
    const resigned=expectOk(await api(first,'/submitMatchAction',{matchId:joined.matchId,type:'resign',actionId:'live-smoke-resign-'+suffix,expectedSequence:0},'live-smoke-match-resign-'+suffix),'finish friendly match');
    assert.equal(resigned.view.status,'finished');
    report.checks.push('friendly-room-and-authoritative-match');

    const queued=expectOk(await api(first,'/enqueueRanked',{},'live-smoke-ranked-a-'+suffix),'enqueue ranked player A');
    assert.equal(queued.status,'queued');
    const matched=expectOk(await api(second,'/enqueueRanked',{},'live-smoke-ranked-b-'+suffix),'enqueue ranked player B');
    assert.equal(matched.status,'matched');
    assert.match(matched.matchId,/^rm_[a-f0-9]{32}$/);
    const rankedFirst=expectOk(await api(first,'/getRankedMatch',{matchId:matched.matchId},'live-smoke-ranked-read-a-'+suffix),'read ranked player A');
    const rankedSecond=expectOk(await api(second,'/getRankedMatch',{matchId:matched.matchId},'live-smoke-ranked-read-b-'+suffix),'read ranked player B');
    assert.notEqual(rankedFirst.view.viewerColor,rankedSecond.view.viewerColor);
    assert.equal(rankedFirst.view.timeControlMinutes,5);
    assert.equal(rankedFirst.view.clock.initialMs,300000);
    const rankedFinished=expectOk(await api(first,'/submitMatchAction',{matchId:matched.matchId,type:'resign',actionId:'live-smoke-ranked-resign-'+suffix,expectedSequence:0},'live-smoke-ranked-finish-'+suffix),'finish ranked match');
    assert.equal(rankedFinished.view.status,'finished');
    assert.equal(rankedFinished.view.mode,'ranked');
    report.checks.push('ranked-matchmaking-and-server-settlement');
  }finally{
    for(let index=users.length-1;index>=0;index-=1){
      try{await removeUser(users[index],String(index));report.cleanup.push('user-'+index+'-deleted');}
      catch(error){report.cleanup.push('user-'+index+'-cleanup-failed:'+String(error&&error.message||error));}
    }
  }
  assert.equal(report.cleanup.some(function(value){return value.includes('failed');}),false,JSON.stringify(report));
  console.log(JSON.stringify({result:'pass',report},null,2));
}

main().catch(function(error){console.error(error&&error.stack||error);process.exitCode=1;});
