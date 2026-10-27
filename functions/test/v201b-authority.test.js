'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {createBattleV1Api}=require('../lib/battle-v1');
const {STARTER}=require('../rules-v1/dist/src/model.js');
const {PROTOCOL}=require('../rules-v1/dist/src/online/protocol.js');
function fixture(){
 const root={},clone=v=>v===undefined?null:structuredClone(v),read=p=>p.split('/').filter(Boolean).reduce((v,k)=>v?.[k],root);
 function write(p,v){const parts=p.split('/').filter(Boolean),key=parts.pop();let n=root;for(const part of parts)n=n[part]||(n[part]={});if(v===null)delete n[key];else n[key]=clone(v);}
 const snapshot=v=>({val:()=>clone(v)});const db={ref:(p='')=>({get:async()=>snapshot(read(p)),transaction:async f=>{
   // Probe null exactly like a cold Admin SDK transaction, then retry remotely.
   f(null);const v=f(clone(read(p)));if(v!==undefined)write(p,v);return {committed:v!==undefined,snapshot:snapshot(read(p))};
 }})};let at=1000;const api=createBattleV1Api({db,now:()=>at,requirePlayer:async()=>({}),rateLimit:async()=>{}});
 return {api,root,read,setTime:n=>at=n,id:'bv1_'+'2'.repeat(32)};
}
test('production adapter creates once and publishes paired redacted versions',async()=>{const f=fixture(),white={uid:'alice',name:'Alice',bot:false},black={uid:'bob',name:'Bob',bot:false};const first=await f.api.create(f.id,white,black,STARTER,STARTER);const again=await f.api.create(f.id,white,black,STARTER,STARTER);assert.deepEqual(first,again);const p=f.read('matchesV1/'+f.id);assert.equal(p.public.stateVersion,p.private.alice.stateVersion);assert.equal(p.private.alice.handJson,JSON.stringify(first.battle.hidden.hands.w));assert.equal(Object.hasOwn(p,'secret'),false);});
test('production intent request cannot forge state and reconnect never redraws',async()=>{const f=fixture();await f.api.create(f.id,{uid:'alice',name:'A',bot:false},{uid:'bob',name:'B',bot:false},STARTER,STARTER);const body={matchId:f.id,protocolVersion:PROTOCOL,expectedStateVersion:0,actionId:'a0_client-action-0001',intent:{type:'move',uci:'e2e4'}};f.setTime(2000);const reply=await f.api.submitBattleV1Action({uid:'alice',body});assert.equal(reply.view.public.stateVersion,1);const after=f.read('matchSecretsV1/'+f.id);const repeat=await f.api.submitBattleV1Action({uid:'alice',body});assert.equal(repeat.duplicate,true);assert.deepEqual(f.read('matchSecretsV1/'+f.id),after);await assert.rejects(f.api.submitBattleV1Action({uid:'alice',body:{...body,mana:6}}));assert.deepEqual(f.read('matchSecretsV1/'+f.id),after);for(let i=0;i<4;i++)await f.api.getBattleV1({uid:'alice',body:{matchId:f.id,protocolVersion:PROTOCOL}});assert.deepEqual(f.read('matchSecretsV1/'+f.id),after);await assert.rejects(f.api.getBattleV1({uid:'attacker',body:{matchId:f.id,protocolVersion:PROTOCOL}}));});
test('an older publisher cannot overwrite a newer public/private commit',async()=>{const f=fixture(),m=await f.api.create(f.id,{uid:'alice',name:'A',bot:false},{uid:'bob',name:'B',bot:false},STARTER,STARTER);await f.api.submitBattleV1Action({uid:'alice',body:{matchId:f.id,protocolVersion:PROTOCOL,expectedStateVersion:0,actionId:'a0_client-action-0002',intent:{type:'move',uci:'e2e4'}}});await f.api.publish(m);assert.equal(f.read('matchesV1/'+f.id).public.stateVersion,1);assert.equal(f.read('matchesV1/'+f.id).private.bob.stateVersion,1);});
