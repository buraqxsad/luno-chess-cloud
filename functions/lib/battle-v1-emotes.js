'use strict';
const {protocol}=require('./battle-v1');
const {PROTOCOL,BattleError,requireRecord,exactKeys,sideForUid}=protocol;
const IDS=new Set(['smile','heart','laugh','cry','angry','think','fire','star','thunder','bomb','strat','trophy','crown','rainbow']);
const COOLDOWN=3000,TTL=60000;
function installBattleV1Emotes(api,deps){
  async function prepare(context,extra){
    const b=requireRecord(context.body);exactKeys(b,['matchId','protocolVersion',...extra]);
    if(b.protocolVersion!==PROTOCOL)throw new BattleError('INCOMPATIBLE_PROTOCOL',400);
    const player=await deps.requirePlayer(context.uid);
    const match=await api.load(b.matchId,context.uid);
    if(match.deletedParticipants?.[context.uid])throw new BattleError('NOT_PARTICIPANT',403);
    return {b,player,match,side:sideForUid(match,context.uid)};
  }
  async function sendBattleV1Emote(context){
    const {b,player,match,side}=await prepare(context,['emojiId']);
    if(match.result)throw new BattleError('MATCH_FINISHED');
    if(!IDS.has(b.emojiId))throw new BattleError('INVALID_EMOTE',400);
    const inventory=player.inventory||{};
    if(b.emojiId!=='smile'&&(!Array.isArray(inventory.ownedEmojis)||
      !inventory.ownedEmojis.includes(b.emojiId)))throw new BattleError('EMOTE_NOT_OWNED',403);
    if(typeof context.requestId!=='string'||!/^[a-zA-Z0-9_-]{1,128}$/.test(context.requestId))throw new BattleError('INVALID_REQUEST_ID',400);
    await deps.rateLimit(context.uid,'sendBattleV1Emote',20,60000);
    const at=api.now();let error;
    const tx=await api.db.ref('matchEmotesV1/'+b.matchId).transaction(value=>{
      error=null;const v=value||{sequence:0,events:[],last:{},receipts:[]};
      v.events=(v.events||[]).filter(e=>at-e.at<=TTL).slice(-15);
      v.receipts=(v.receipts||[]).filter(e=>at-e.at<=TTL).slice(-31);
      const receipt=v.receipts.find(e=>e.side===side&&e.requestId===context.requestId);
      if(receipt){
        if(receipt.emojiId!==b.emojiId){error=new BattleError('REQUEST_ID_CONFLICT',409);return;}
        return v;
      }
      const previous=v.last?.[side];
      if(previous?.requestId===context.requestId){
        if(previous.emojiId!==b.emojiId){error=new BattleError('REQUEST_ID_CONFLICT',409);return;}
        return v;
      }
      if(previous&&at-previous.at<COOLDOWN){error=new BattleError('EMOTE_COOLDOWN',429);return;}
      v.sequence++;const event={sequence:v.sequence,side,emojiId:b.emojiId,at};
      v.events.push(event);v.receipts.push({...event,requestId:context.requestId});
      v.last={...v.last,[side]:{...event,requestId:context.requestId}};return v;
    },undefined,false);
    if(!tx.committed)throw error||new BattleError('TEMPORARILY_UNAVAILABLE',503);
    const state=tx.snapshot.val(),event=state.receipts.find(e=>e.side===side&&e.requestId===context.requestId)||state.last[side];
    return {ok:true,event:{sequence:event.sequence,side:event.side,emojiId:event.emojiId,at:event.at}};
  }
  async function getBattleV1Emotes(context){
    const {b}=await prepare(context,['after']);
    if(!Number.isSafeInteger(b.after)||b.after<0)throw new BattleError('INVALID_CURSOR',400);
    await deps.rateLimit(context.uid,'getBattleV1Emotes',45,60000);
    const ref=api.db.ref('matchEmotesV1/'+b.matchId);
    let state=(await ref.get()).val();
    const at=api.now();
    if((state?.events||[]).some(e=>at-e.at>TTL)||Object.values(state?.last||{}).some(e=>at-e.at>TTL)){
      const tx=await ref.transaction(v=>{
        if(!v)return v;
        return {...v,events:(v.events||[]).filter(e=>at-e.at<=TTL),
          receipts:(v.receipts||[]).filter(e=>at-e.at<=TTL),
          last:Object.fromEntries(Object.entries(v.last||{}).filter(([,e])=>at-e.at<=TTL))};
      },undefined,false);
      state=tx.snapshot.val();
    }
    return {ok:true,sequence:state?.sequence||0,events:(state?.events||[])
      .filter(e=>e.sequence>b.after&&api.now()-e.at<=TTL).slice(-16)};
  }
  const originalAck=api.ackBattleV1Result;
  if(originalAck)api.ackBattleV1Result=async context=>{
    const response=await originalAck(context);
    try{await api.db.ref('matchEmotesV1/'+context.body.matchId).remove();}
    catch(e){deps.logger?.warn('Battle emote cleanup deferred',{code:e.code||'TEMPORARILY_UNAVAILABLE'});}
    return response;
  };
  Object.assign(api,{sendBattleV1Emote,getBattleV1Emotes});return api;
}
module.exports={installBattleV1Emotes,COOLDOWN,TTL};
