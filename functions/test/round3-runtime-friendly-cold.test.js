'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {installBattleV1Friendly}=require('../lib/battle-v1-friendly');

const sender='round3_cold_sender',recipient='round3_cold_recipient',key=sender+'|'+recipient;
const now=1000,copy=value=>value==null?null:structuredClone(value);

function setup({cold,present=true,empty=false}){
 let control=empty?null:{invites:present?{[key]:{from:{uid:sender,player:{name:'Sender'}},to:recipient,requestId:'seed-invite',expiresAt:now+120000}}:{},unrelated:{preserved:7}};
 let notification=present;
 const calls=[],completions=[];
 const snapshot=value=>({val:()=>copy(value)});
 const db={ref(path){
  if(path==='matchInvites/'+recipient+'/'+sender)return {async remove(){notification=false;}};
  assert.equal(path,'battleV1Control');
  return {async transaction(update,_complete,applyLocally){
   assert.equal(applyLocally,false);
   // Actual SDK14.2.0/RTDB4.11.2 localhost proof established both branches:
   // undefined aborts immediately; a null no-op CAS retries a populated remote
   // root, but commits without retry when the real remote node is also null.
   let cached=cold?null:copy(control);
   function run(value){const event={inputNull:value===null,hasInvite:!!value?.invites?.[key]};calls.push(event);const next=update(value);event.returnedUndefined=next===undefined;return next;}
   let next=run(cached);
   if(next===undefined)return {committed:false,snapshot:snapshot(cached)};
   if(cold&&control!==null){cached=copy(control);next=run(cached);}
   if(next===undefined)return {committed:false,snapshot:snapshot(cached)};
   control=copy(next);return {committed:true,snapshot:snapshot(control)};
  }};
 }};
 const api={db,now:()=>now,admission:async()=>{},entry:async uid=>({uid,player:{name:uid}}),matchId:()=> 'round3_cold_match',
  async completeReservation(id){completions.push(id);assert.equal(control.reservations[id].w.uid,sender);assert.equal(control.reservations[id].b.uid,recipient);return {matchId:id};},
  snapshot:match=>({matchId:match.matchId})};
 const deps={requirePlayer:async()=>({}),rateLimit:async()=>{},withSocialPairLock:async(a,b,run)=>run(),assertInteractionAllowed:async()=>{},requireFriendship:async()=>{}};
 installBattleV1Friendly(api,deps);
 const context=accept=>({uid:recipient,requestId:'response',body:{client:{},fromUid:sender,accept}});
 return {api,context,calls,completions,read:()=>copy(control),hasNotification:()=>notification};
}

for(const accept of [false,true]){
 const action=accept?'accept':'decline';
 for(const cold of [true,false])test('Friendly '+action+' succeeds with '+(cold?'cold-null':'warm')+' cache and existing valid invite',async()=>{
  const f=setup({cold}),result=await f.api.respondBattleV1Invite(f.context(accept));
  assert.equal(result.accepted,accept);assert.equal(f.hasNotification(),false);
  assert.equal(f.read().unrelated.preserved,7);
  if(cold){assert.equal(f.calls[0].inputNull,true);assert.equal(f.calls.length,2);assert.equal(f.calls[1].hasInvite,true);}
  else assert.equal(f.calls[0].hasInvite,true);
  if(accept){
   assert.equal(result.matchId,'round3_cold_match');assert.deepEqual(f.completions,['round3_cold_match']);
   assert.equal(f.read().active[sender],'round3_cold_match');assert.equal(f.read().active[recipient],'round3_cold_match');
  }else {assert.equal(f.read().invites[key],undefined);assert.deepEqual(f.completions,[]);}
 });
 test('Friendly '+action+' preserves 404 when cold null is the truly empty remote root',async()=>{
  const f=setup({cold:true,present:false,empty:true});
  await assert.rejects(f.api.respondBattleV1Invite(f.context(accept)),{code:'INVITE_UNAVAILABLE',status:404});
  assert.equal(f.read(),null);assert.deepEqual(f.completions,[]);assert.equal(f.calls.length,1);
 });
 test('Friendly '+action+' preserves 404 for a warm root with no matching invite',async()=>{
  const f=setup({cold:false,present:false});
  await assert.rejects(f.api.respondBattleV1Invite(f.context(accept)),{code:'INVITE_UNAVAILABLE',status:404});
  assert.equal(f.read().unrelated.preserved,7);assert.deepEqual(f.completions,[]);
 });
}
