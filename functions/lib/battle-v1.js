'use strict';

const crypto=require('node:crypto');
const protocol=require('../rules-v1/dist/src/online/protocol.js');
const authority=require('../rules-v1/dist/src/online/authority.js');
const {clone}=require('../rules-v1/dist/src/model.js');
const {PROTOCOL,BattleError,exactKeys,requireRecord,validMatchId,sideForUid,reconnectSnapshot,toPublicMatchState,toPlayerPrivateState,parseActionRequest}=protocol;

function stored(match){return {recordJson:JSON.stringify(match),stateVersion:match.stateVersion,status:match.result?'finished':'active',settlementStatus:match.settlementStatus};}
function hydrate(value){
  if(!value||typeof value.recordJson!=='string')throw new BattleError('MATCH_NOT_FOUND',404);
  let match;try{match=JSON.parse(value.recordJson);}catch{throw new BattleError('TEMPORARILY_UNAVAILABLE',503);}
  if(match.protocolVersion!==PROTOCOL||match.rulesetVersion!==1)throw new BattleError('INCOMPATIBLE_PROTOCOL',400);
  return match;
}
function createBattleV1Api(deps){
  const {db,requirePlayer,rateLimit}=deps,now=deps.now||Date.now;
  const matchRef=id=>db.ref('matchSecretsV1/'+id);
  async function load(id,uid){if(!validMatchId(id))throw new BattleError('INVALID_MATCH_ID',400);const match=hydrate((await matchRef(id).get()).val());sideForUid(match,uid);return match;}
  function snapshot(match,uid){
    const response=reconnectSnapshot(match,uid),analysis=authority.postMatchAnalysis(match,uid),receipt=match.settlements?.[sideForUid(match,uid)];
    if(analysis)response.view.private.analysisJson=JSON.stringify(analysis);
    if(receipt)response.view.private.settlementJson=JSON.stringify(receipt);
    response.serverNow=now();return response;
  }
  async function publish(match){
    const publicState=toPublicMatchState(match),privateState={};
    for(const player of Object.values(match.players))if(!player.bot&&!match.deletedParticipants?.[player.uid]){
      const own=toPlayerPrivateState(match,player.uid),analysis=authority.postMatchAnalysis(match,player.uid);
      privateState[player.uid]={...own,...(analysis?{analysisJson:JSON.stringify(analysis)}:{}),...(match.settlements?.[sideForUid(match,player.uid)]?{settlementJson:JSON.stringify(match.settlements[sideForUid(match,player.uid)])}:{})};
    }
    // One projection transaction gives every readable leaf the SAME commit version.
    await db.ref('matchesV1/'+match.matchId).transaction(value=>{
      if(value?.public?.stateVersion>=match.stateVersion)return value;
      return {public:publicState,private:privateState};
    },undefined,false);
  }
  async function transact(id,uid,change){
    await load(id,uid);let decision=null,error=null;
    const result=await matchRef(id).transaction(value=>{
      error=null;decision=null;if(value===null)return null;
      try{const current=hydrate(value);sideForUid(current,uid);decision=change(current);return stored(decision.match);}catch(cause){error=cause;return;}
    },undefined,false);
    if(!result.committed||!result.snapshot.val()){if(error)throw error;throw new BattleError('TEMPORARILY_UNAVAILABLE',503);}
    return {match:hydrate(result.snapshot.val()),decision};
  }
  async function create(id,white,black,whiteDeck,blackDeck,rated=true,ratingAtStart={w:0,b:0}){
    if(!validMatchId(id)||!protocol.validUid(white.uid)||!protocol.validUid(black.uid))throw new BattleError('INVALID_MATCH',400);
    const prepared=authority.createServerMatch(id,white,black,whiteDeck,blackDeck,now(),rated);prepared.ratingAtStart=clone(ratingAtStart);let conflict=false;
    const tx=await matchRef(id).transaction(value=>{
      conflict=false;if(value){const existing=hydrate(value);if(existing.players.w.uid!==white.uid||existing.players.b.uid!==black.uid){conflict=true;return;}return value;}
      return stored(prepared);
    },undefined,false);
    if(!tx.committed||conflict)throw new BattleError('MATCH_CREATION_CONFLICT');
    const match=hydrate(tx.snapshot.val());await publish(match);return match;
  }
  async function getBattleV1(context){
    const body=requireRecord(context.body);exactKeys(body,['matchId','protocolVersion']);
    if(body.protocolVersion!==PROTOCOL)throw new BattleError('INCOMPATIBLE_PROTOCOL',400);
    await rateLimit(context.uid,'getBattleV1',90,60000);await requirePlayer(context.uid);
    const at=now(),tx=await transact(body.matchId,context.uid,m=>({match:authority.expireClock(m,at)}));
    await publish(tx.match);return snapshot(tx.match,context.uid);
  }
  async function submitBattleV1Action(context){
    const request=parseActionRequest(context.body);await rateLimit(context.uid,'submitBattleV1Action',120,60000);await requirePlayer(context.uid);
    const at=now();let timeout=false;
    const tx=await transact(request.matchId,context.uid,m=>{
      timeout=false;
      const expired=authority.expireClock(m,at);
      if(expired!==m){timeout=true;return {match:expired,duplicate:false,acceptedVersion:expired.stateVersion};}
      return authority.commitAction(m,context.uid,request,at);
    });
    await publish(tx.match);
    if(timeout)throw new BattleError('MATCH_TIMEOUT');
    return authority.sanitizedActionResponse(tx.match,context.uid,tx.decision.duplicate,tx.decision.acceptedVersion);
  }
  return {getBattleV1,submitBattleV1Action,create,load,transact,publish,stored,hydrate,snapshot,now,db};
}
module.exports={createBattleV1Api,stored,hydrate,protocol,authority};
