from pathlib import Path
import ast
old=Path('/workspace/luno-review/bug-audit-round4/runtime-billing');r=Path('/workspace/luno-review/bug-audit-round5/runtime-billing');r.mkdir(exist_ok=True)
s=(old/'run-proof.py').read_text().replace('bug-audit-round4','bug-audit-round5').replace('demo-luno-billing-fence-r4-final','demo-luno-billing-fence-r5-final')
s=s.replace("'tests':7,'pass':7", "'tests':9,'pass':9").replace("len(result['observations'])==7", "len(result['observations'])==9").replace('time.monotonic()+35,started+34','time.monotonic()+45,started+44')
ast.parse(s);(r/'run-proof.py').write_text(s)
s=(old/'fences.cjs').read_text().replace('demo-luno-billing-fence-r4-final','demo-luno-billing-fence-r5-final')
s+='''

function localIdentity(t){
 const {getAuth}=req('firebase-admin/auth'),{getAppCheck}=req('firebase-admin/app-check');
 t.mock.method(getAuth(),'verifyIdToken',async uid=>({uid,auth_time:Math.floor(Date.now()/1000),firebase:{sign_in_provider:'anonymous'}}));
 t.mock.method(getAuth(),'deleteUser',async()=>{});
 t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
 for(const level of ['info','warn','error'])t.mock.method(logger,level,()=>{});
}
async function localRequest(uid,route,body,id){
 const headers={authorization:'Bearer '+uid,'x-firebase-appcheck':'local-sdk-round5','x-luno-request-id':id};
 let status,value;await api.handler({method:'POST',path:'/'+route,body,get:name=>headers[name.toLowerCase()]||''},
  {set(){return this;},status(code){status=code;return this;},json(result){value=result;}});
 assert.equal(status,200,JSON.stringify({route,status,error:value?.error}));return value;
}
test('real SDK: actual deletion retires both acknowledged V1 histories and preserves peer results',{timeout:16000},async t=>{
 localIdentity(t);
 const owner='sdk_r5_history_owner',peer='sdk_r5_history_peer',{protocol}=req('./lib/battle-v1');
 await checker.ref().set({users:{[owner]:api.starterProfile(owner,'SDK retired alias'),[peer]:api.starterProfile(peer,'SDK surviving peer')},battleRollout:{config:{...protocol.LEGACY_ONLY,configVersion:2,v1MatchmakingEnabled:true}}});
 const ids=[],results=[];
 const client={platform:'android',build:19,protocolVersion:protocol.PROTOCOL};
 for(let number=1;number<=2;number++){
  assert.equal((await localRequest(owner,'enqueueBattleV1',{client},'sdk-r5-history-owner-'+number)).status,'queued');
  const joined=await localRequest(peer,'enqueueBattleV1',{client},'sdk-r5-history-peer-'+number);
  const ended=await localRequest(owner,'resignBattleV1',{matchId:joined.matchId,protocolVersion:protocol.PROTOCOL,expectedStateVersion:0,actionId:'a0_sdk-r5-resign-'+number},'sdk-r5-history-resign-'+number);
  assert.equal(ended.view.public.settlementStatus,'complete');ids.push(joined.matchId);
  results.push(api.battleV1.hydrate((await checker.ref('matchSecretsV1/'+joined.matchId).get()).val()).result);
  await localRequest(owner,'ackBattleV1Result',{matchId:joined.matchId,protocolVersion:protocol.PROTOCOL},'sdk-r5-history-ack-'+number);
 }
 const peerGold=(await checker.ref('users/'+peer+'/gold').get()).val();
 assert.equal((await localRequest(owner,'deleteAccount',{confirm:true},'sdk-r5-history-delete')).deleted,true);
 assert.equal((await checker.ref('users/'+owner).get()).exists(),false);
 for(let n=0;n<ids.length;n++){
  const canonical=api.battleV1.hydrate((await checker.ref('matchSecretsV1/'+ids[n]).get()).val()),projection=(await checker.ref('matchesV1/'+ids[n]).get()).val();
  const side=canonical.players.w.uid===owner?'w':'b';assert.deepEqual(canonical.result,results[n]);assert.equal(canonical.players[side].name,'Deleted player');assert.equal(canonical.deletedParticipants[owner],true);
  assert.equal(projection.public.participants[owner],undefined);assert.equal(projection.private[owner],undefined);assert.equal(projection.public.participants[peer],true);assert.ok(projection.private[peer]);
 }
 assert.equal((await checker.ref('users/'+peer+'/gold').get()).val(),peerGold);
 assert.equal((await checker.ref('accountDeletions/'+api.hash(owner)+'/battleV1HistoryErased').get()).val(),true);
 record({case:'actual-V1-historical-account-erasure',matches:ids.length,acknowledged_before_delete:true,deleted_profile_absent:true,historical_names_retired:true,deleted_public_membership_and_private_projection_absent:true,peer_results_and_gold_preserved:true});
});
test('real SDK: surviving peer heartbeat does not recreate erased legacy account state',{timeout:16000},async t=>{
 localIdentity(t);
 const owner='sdk_r5_legacy_owner',peer='sdk_r5_legacy_peer',{protocol}=req('./lib/battle-v1');
 await checker.ref().set({users:{[owner]:api.starterProfile(owner,'SDK legacy erased alias'),[peer]:api.starterProfile(peer,'SDK legacy survivor')},battleRollout:{config:{...protocol.LEGACY_ONLY,configVersion:3}}});
 const room=await localRequest(owner,'createFriendlyRoom',{durationMinutes:5},'sdk-r5-legacy-room');
 const joined=await localRequest(peer,'joinFriendlyRoom',{roomCode:room.roomCode},'sdk-r5-legacy-join');
 const result=await localRequest(owner,'submitMatchAction',{matchId:joined.matchId,type:'resign',actionId:'sdk-r5-legacy-resign',expectedSequence:0},'sdk-r5-legacy-action');
 assert.equal(result.view.result.reason,'resignation');
 assert.equal((await localRequest(owner,'deleteAccount',{confirm:true},'sdk-r5-legacy-delete')).deleted,true);
 await localRequest(peer,'heartbeatRankedMatch',{matchId:joined.matchId},'sdk-r5-legacy-heartbeat');
 for(const tree of ['matchHistory','rankedReplays','rankedMatchViews','rankedPlayers']){
  assert.equal((await checker.ref(tree+'/'+owner).get()).exists(),false);assert.equal((await checker.ref(tree+'/'+peer).get()).exists(),true);
 }
 assert.equal((await checker.ref('users/'+owner).get()).exists(),false);assert.equal((await checker.ref('users/'+peer).get()).exists(),true);
 record({case:'actual-legacy-terminal-erasure-heartbeat',deleted_profile_absent:true,erased_history_replay_view_presence_absent:true,peer_result_state_preserved:true});
});
'''
(r/'fences.cjs').write_text(s)
print('Prepared9 actual localhost SDK cases;6 financial+legacy reservation+2new erasure paths. Deferred until build/Gradle stop.')
