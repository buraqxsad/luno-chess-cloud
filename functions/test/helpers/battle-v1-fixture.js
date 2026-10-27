'use strict';
const {createBattleV1Api,protocol}=require('../../lib/battle-v1');
const {installBattleV1Rollout}=require('../../lib/battle-v1-rollout');
const {installBattleV1Recovery}=require('../../lib/battle-v1-recovery');
const {installBattleV1Friendly}=require('../../lib/battle-v1-friendly');
function fixture(){
 const root={},copy=v=>v===undefined?null:structuredClone(v),read=p=>p.split('/').filter(Boolean).reduce((v,k)=>v?.[k],root);
 function write(p,v){const parts=p.split('/').filter(Boolean),key=parts.pop();let n=root;for(const part of parts)n=n[part]||(n[part]={});if(v===null)delete n[key];else n[key]=copy(v);}
 const snap=v=>({val:()=>copy(v),exists:()=>v!==undefined&&v!==null});
 const db={ref:(p='')=>({get:async()=>snap(read(p)),set:async v=>write(p,v),remove:async()=>write(p,null),transaction:async f=>{f(null);const v=f(copy(read(p)));if(v!==undefined)write(p,v);return {committed:v!==undefined,snapshot:snap(read(p))};}})};
 const pairs=new Map();
 async function withSocialPairLock(first,second,operation){
  const key=[first,second].sort().join('|'),previous=pairs.get(key)||Promise.resolve();
  const work=previous.catch(()=>{}).then(operation);pairs.set(key,work);
  try{return await work;}finally{if(pairs.get(key)===work)pairs.delete(key);}
 }
 let at=1000;const deps={db,now:()=>at,requirePlayer:async uid=>{const p=read('users/'+uid);if(!p)throw new Error('player missing');return copy(p);},rateLimit:async()=>{},assertInteractionAllowed:async(first,second)=>{if(read('blocks/'+first+'/'+second)||read('blocks/'+second+'/'+first))throw new protocol.BattleError('user-blocked',403);},requireFriendship:async()=>{},withSocialPairLock};
 for(const uid of ['alice','bob','attacker'])write('users/'+uid,{uid,username:uid,trophies:1200,arenaIdx:4,gold:100,games:0,wins:0,losses:0,draws:0,serverCompetition:{legacy:true},serverSeason:{legacy:true}});
 const api=installBattleV1Friendly(installBattleV1Recovery(installBattleV1Rollout(createBattleV1Api(deps),deps),deps),deps);
 const client={platform:'android',build:17,protocolVersion:protocol.PROTOCOL};
 return {api,root,read,write,withSocialPairLock,setTime:n=>at=n,client,context:(uid,body,requestId='request-1')=>({uid,body,requestId}),enable:()=>api.updateConfig({...protocol.LEGACY_ONLY,configVersion:2,v1MatchmakingEnabled:true},1)};
}
module.exports={fixture};
