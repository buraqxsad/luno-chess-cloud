'use strict';

const {authHost,databaseHost}=require('./helpers/local-emulators').requireLocalEmulators();
const assert=require('node:assert/strict');
const {initializeApp,getApps,deleteApp}=require('firebase-admin/app');
const {getDatabase}=require('firebase-admin/database');

const namespace='luno-chess-default-rtdb';
const db=getDatabase(initializeApp({projectId:'luno-chess',databaseURL:`http://${databaseHost}?ns=${namespace}`},'online-integration-test'));
const handler=require('../index.js')._test.handler;

async function anonymousUser(){
  const response=await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-key`,{
    method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({returnSecureToken:true}),signal:AbortSignal.timeout(15000)
  });
  const body=await response.json();assert.equal(response.status,200,JSON.stringify(body));return body;
}

async function api(path,token,body,id){
  const headers={authorization:'Bearer '+token,'content-type':'application/json','x-firebase-appcheck':'luno-emulator-app-check','x-luno-request-id':id,origin:'https://localhost'};
  const req={method:'POST',path,body:body||{},get:function(name){return headers[String(name||'').toLowerCase()]||'';}};
  let status=200,responseBody={};
  const res={set:function(){return this;},status:function(value){status=value;return this;},send:function(value){responseBody=value;return this;},json:function(value){responseBody=value;return this;}};
  let timer;
  try{
    await Promise.race([handler(req,res),new Promise(function(_,reject){timer=setTimeout(function(){reject(new Error('API timeout: '+path));},45000);})]);
  }finally{if(timer)clearTimeout(timer);}
  return {status,body:responseBody};
}

function ok(result,label){assert.equal(result.status,200,label+': '+JSON.stringify(result.body));return result.body;}

async function main(){
  const suffix=Date.now().toString(36),first=await anonymousUser(),second=await anonymousUser(),users=[first,second];
  try{
    ok(await api('/createGuestPlayer',first.idToken,{username:'oa_'+suffix},'online-create-a-'+suffix),'create player A');
    ok(await api('/createGuestPlayer',second.idToken,{username:'ob_'+suffix},'online-create-b-'+suffix),'create player B');

    ok(await api('/cancelRankedQueue',first.idToken,{},'online-cancel-empty-'+suffix),'cancel empty queue');
    const queued=ok(await api('/enqueueRanked',first.idToken,{},'online-queue-a-'+suffix),'queue player A');
    assert.equal(queued.status,'queued');
    assert.equal(ok(await api('/getRankedMatch',first.idToken,{matchId:''},'online-queued-state-'+suffix),'read queued state').status,'queued');
    const cancelled=ok(await api('/cancelRankedQueue',first.idToken,{},'online-cancel-a-'+suffix),'cancel queue');
    assert.equal(cancelled.status,'idle');
    assert.equal((await db.ref(`rankedState/queue/${first.localId}`).get()).exists(),false);
    assert.equal(ok(await api('/getRankedMatch',first.idToken,{matchId:''},'online-idle-after-cancel-'+suffix),'read cancelled state').status,'idle');

    const staleQueue={uid:first.localId,joinedAt:Date.now()-3*60*1000,lastSeenAt:Date.now()-3*60*1000,player:{uid:first.localId,trophies:0,name:'oa_'+suffix},deck:['barbarian','card_block','poison_q','angry_n','glue','freeze']};
    await db.ref(`rankedState/queue/${first.localId}`).set(staleQueue);
    await db.ref(`rankedState/activeByUser/${first.localId}`).set('rm_stale_pointer');
    const staleCancelled=ok(await api('/cancelRankedQueue',first.idToken,{},'online-cancel-stale-pointer-'+suffix),'clear stale queue pointer');
    assert.equal(staleCancelled.status,'idle');
    assert.equal((await db.ref(`rankedState/activeByUser/${first.localId}`).get()).exists(),false);

    ok(await api('/enqueueRanked',first.idToken,{},'online-ranked-a-'+suffix),'rank player A');
    const matched=ok(await api('/enqueueRanked',second.idToken,{},'online-ranked-b-'+suffix),'rank player B');
    assert.equal(matched.status,'matched');assert.match(matched.matchId,/^rm_[a-f0-9]{32}$/);
    const matchId=matched.matchId;
    const firstView=ok(await api('/getRankedMatch',first.idToken,{matchId},'online-ranked-read-a-'+suffix),'read player A match');
    const secondView=ok(await api('/getRankedMatch',second.idToken,{matchId},'online-ranked-read-b-'+suffix),'read player B match');
    assert.notEqual(firstView.view.viewerColor,secondView.view.viewerColor);
    ok(await api('/heartbeatRankedMatch',first.idToken,{matchId},'online-heartbeat-a-'+suffix),'heartbeat player A');
    const whiteUser=firstView.view.viewerColor==='W'?first:second;
    const blackUser=whiteUser===first?second:first;
    const legalMove=ok(await api('/submitMatchAction',whiteUser.idToken,{matchId,type:'move',from:12,to:28,
      actionId:'online-legal-move-'+suffix,expectedSequence:0},'online-legal-move-request-'+suffix),'play legal opening move');
    assert.equal(legalMove.view.sequence,1);
    assert.equal(legalMove.view.moveCount,1);
    const duplicateMove=ok(await api('/submitMatchAction',whiteUser.idToken,{matchId,type:'move',from:12,to:28,
      actionId:'online-legal-move-'+suffix,expectedSequence:0},'online-legal-move-retry-'+suffix),'retry opening move');
    assert.equal(duplicateMove.idempotent,true);
    assert.equal(duplicateMove.view.sequence,1);
    const staleMove=await api('/submitMatchAction',blackUser.idToken,{matchId,type:'move',from:52,to:36,
      actionId:'online-stale-move-'+suffix,expectedSequence:0},'online-stale-move-request-'+suffix);
    assert.equal(staleMove.status,409,JSON.stringify(staleMove.body));
    assert.equal(staleMove.body.error,'stale-sequence');
    const chat=ok(await api('/sendRankedMessage',first.idToken,{matchId,kind:'preset',tab:'greetings',id:'good_luck'},'online-chat-'+suffix),'ranked chat');
    assert.equal(chat.message.id,'good_luck');
    assert.equal((await db.ref(`rankedMessages/${second.localId}/${matchId}`).get()).val().messageId,chat.message.messageId);
    const finished=ok(await api('/submitMatchAction',first.idToken,{matchId,type:'resign',actionId:'online-resign-'+suffix,expectedSequence:1},'online-resign-request-'+suffix),'finish ranked match');
    assert.equal(finished.view.status,'finished');assert.equal(finished.view.mode,'ranked');

    const room=ok(await api('/createFriendlyRoom',first.idToken,{durationMinutes:3},'online-room-create-'+suffix),'create room');
    assert.match(room.roomCode,/^[A-Z0-9]{6}$/);
    const roomCancelled=ok(await api('/cancelFriendlyRoom',first.idToken,{roomCode:room.roomCode},'online-room-cancel-'+suffix),'cancel room');
    assert.equal(roomCancelled.cancelled,true);
    const room2=ok(await api('/createFriendlyRoom',first.idToken,{durationMinutes:1},'online-room-create-2-'+suffix),'create second room');
    const joined=ok(await api('/joinFriendlyRoom',second.idToken,{roomCode:room2.roomCode},'online-room-join-'+suffix),'join room');
    assert.match(joined.matchId,/^fm_[a-f0-9]{32}$/);assert.equal(joined.view.mode,'friendly');
    const friendlyFinished=ok(await api('/submitMatchAction',second.idToken,{matchId:joined.matchId,type:'resign',actionId:'online-friendly-resign-'+suffix,expectedSequence:0},'online-friendly-resign-request-'+suffix),'finish friendly match');
    assert.equal(friendlyFinished.view.status,'finished');
    console.log('ONLINE_INTEGRATION_PASS');
  }finally{
    for(const user of users){
      try{await api('/deleteAccount',user.idToken,{confirm:true},'online-cleanup-'+user.localId+'-'+suffix);}catch(_){/* best-effort cleanup */}
    }
  }
}

main().catch(function(error){console.error(error&&error.stack||error);process.exitCode=1;})
  .finally(async function(){await Promise.all(getApps().map(deleteApp));});
