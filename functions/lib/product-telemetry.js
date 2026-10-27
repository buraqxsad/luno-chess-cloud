'use strict';

const crypto=require('node:crypto');
const VERSION=1,RETENTION_DAYS=30,MAX_BATCH=16;
const EVENTS=Object.freeze([
  'first_open','intro_started','intro_step','intro_completed','intro_skipped','first_home',
  'first_match_cta_pressed','first_match_started','first_match_abandoned','first_match_completed',
  'first_result','second_match_pressed','second_match_started','academy_opened','deck_opened','deck_saved',
  'card_unlocked','card_added_to_deck','ranked_started','ranked_completed','reconnect','matchmaking_wait_bucket',
  'card_drawn','card_played','card_discarded','card_cancelled'
]);
const EVENT_SET=new Set(EVENTS),MODES=new Set(['ai','local','online']),RESULTS=new Set(['win','loss','draw']);
const WAIT=new Set(['under5s','from5to15s','from15to30s','from30to60s','over60s']);
const SOURCES=new Set(['framework','async','navigation','startup']);
const ERRORS=new Set(['assertion','state','format','range','timeout','network','unknown']);
const COMPONENTS=new Set(['battle','startup','navigation','network','store','unknown']);
const record=value=>!!value&&typeof value==='object'&&!Array.isArray(value);
const hash=value=>crypto.createHash('sha256').update(value).digest('hex');
function failure(status,code){return Object.assign(new Error(code),{status,code});}
function keys(value,allowed){
  if(!record(value)||Object.keys(value).some(key=>!allowed.includes(key)))throw failure(400,'invalid-telemetry');
}
function integer(value,min,max){return Number.isSafeInteger(value)&&value>=min&&value<=max;}
function consentValue(value){
  if(value==null)return {version:VERSION,revision:0,analytics:false,diagnostics:false};
  if(!record(value)||value.version!==VERSION||!integer(value.revision,1,1e9)||
    typeof value.analytics!=='boolean'||typeof value.diagnostics!=='boolean')throw failure(503,'telemetry-consent-unavailable');
  return {version:VERSION,revision:value.revision,analytics:value.analytics,diagnostics:value.diagnostics};
}
function analyticsSample(value){
  keys(value,['event','elapsedMs','step','mode','result','waitBucket']);
  if(!EVENT_SET.has(value.event)||!integer(value.elapsedMs,0,86400000))throw failure(400,'invalid-telemetry');
  if(Object.hasOwn(value,'step')&&(value.event!=='intro_step'||!integer(value.step,0,63)))throw failure(400,'invalid-telemetry');
  if(Object.hasOwn(value,'mode')&&!MODES.has(value.mode)||Object.hasOwn(value,'result')&&!RESULTS.has(value.result))throw failure(400,'invalid-telemetry');
  if(Object.hasOwn(value,'waitBucket')&&(value.event!=='matchmaking_wait_bucket'||!WAIT.has(value.waitBucket)))throw failure(400,'invalid-telemetry');
  // No card IDs, board state, user/device identity or free-form properties.
  return {...value};
}
function diagnosticSample(value){
  keys(value,['source','category','component','fingerprint']);
  if(!SOURCES.has(value.source)||!ERRORS.has(value.category)||!COMPONENTS.has(value.component)||
    typeof value.fingerprint!=='string'||!/^[a-f0-9]{16}$/.test(value.fingerprint))throw failure(400,'invalid-telemetry');
  return {...value};
}
function delivery(body){
  keys(body,['version','kind','consentRevision','deliveryId','samples']);
  if(body.version!==VERSION||!['analytics','diagnostics'].includes(body.kind)||
    !integer(body.consentRevision,1,1e9)||typeof body.deliveryId!=='string'||!/^[a-f0-9]{32}$/.test(body.deliveryId)||
    !Array.isArray(body.samples)||body.samples.length<1||body.samples.length>MAX_BATCH)throw failure(400,'invalid-telemetry');
  const samples=body.samples.map(body.kind==='analytics'?analyticsSample:diagnosticSample);
  const counts={};
  for(const sample of samples){
    const name=body.kind==='analytics'
      ?[sample.event,sample.mode||'none',sample.result||'none',sample.step??'none',sample.waitBucket||'none',Math.min(5,Math.floor(sample.elapsedMs/60000))].join(':')
      :[sample.source,sample.category,sample.component,sample.fingerprint].join(':');
    counts[name]=(counts[name]||0)+1;
  }
  return {kind:body.kind,consentRevision:body.consentRevision,deliveryId:body.deliveryId,counts,
    digest:hash(JSON.stringify({kind:body.kind,samples})),accepted:samples.length};
}

function createProductTelemetryApi({db,now,requirePlayer,rateLimit,transactExistingPlayer,writeAccountMetadata,assertAccountOperationAllowed}){
  const dayKey=at=>new Date(at).toISOString().slice(0,10);
  async function consentFor(uid){
    const profile=await requirePlayer(uid);
    if(profile.uid!==uid)throw failure(403,'profile-owner-mismatch');
    return consentValue(profile.productTelemetryConsent);
  }
  async function purgeUser(uid){
    // This private index exists only to erase short-lived diagnostic records.
    // It is never returned in public/player views or sent as event properties.
    const index=(await db.ref(`productTelemetryOwners/${uid}`).get()).val()||{};
    const updates={};
    for(const [key,value] of Object.entries(index)){
      if(/^[a-f0-9]{64}$/.test(key)&&record(value)&&/^\d{4}-\d{2}-\d{2}$/.test(value.day)){
        updates[`productTelemetryDaily/${value.day}/${key}`]=null;
      }
    }
    updates[`productTelemetryOwners/${uid}`]=null;
    await db.ref().update(updates);
  }
  async function getProductTelemetryConsent({uid,body}){
    keys(body,[]);await rateLimit(uid,'getProductTelemetryConsent',30,60000);
    return {ok:true,consent:await consentFor(uid)};
  }
  async function setProductTelemetryConsent({uid,body}){
    keys(body,['version','expectedRevision','analytics','diagnostics']);
    if(body.version!==VERSION||!integer(body.expectedRevision,0,1e9-1)||typeof body.analytics!=='boolean'||typeof body.diagnostics!=='boolean')throw failure(400,'invalid-telemetry-consent');
    await rateLimit(uid,'setProductTelemetryConsent',12,60000);
    const result=await transactExistingPlayer(uid,profile=>{
      if(profile.uid!==uid)throw failure(403,'profile-owner-mismatch');
      const current=consentValue(profile.productTelemetryConsent);
      if(current.analytics===body.analytics&&current.diagnostics===body.diagnostics&&current.revision>0)return {commit:false};
      if(current.revision!==body.expectedRevision)throw failure(409,'telemetry-consent-changed');
      profile.productTelemetryConsent={version:VERSION,revision:current.revision+1,analytics:body.analytics,diagnostics:body.diagnostics,updatedAt:now()};
      return {commit:true};
    });
    const consent=consentValue(result.profile.productTelemetryConsent);
    if(!consent.analytics&&!consent.diagnostics)await purgeUser(uid);
    return {ok:true,consent};
  }
  async function submitProductTelemetry({uid,body}){
    const item=delivery(body);
    const check=async()=>{
      await assertAccountOperationAllowed(uid,'submitProductTelemetry');
      const current=await consentFor(uid);
      if(current.revision!==item.consentRevision||current[item.kind]!==true)throw failure(403,'telemetry-consent-required');
    };
    await check();
    await rateLimit(uid,'submitProductTelemetry',12,60000);
    await rateLimit(uid,'productTelemetryDaily',300,86400000);
    const key=hash(`${uid}|${item.deliveryId}`),ownerIndex=db.ref(`productTelemetryOwners/${uid}`);
    const cutoff=dayKey(now()-RETENTION_DAYS*86400000);
    const claimed=await writeAccountMetadata(uid,'submitProductTelemetry',()=>ownerIndex.transaction(value=>{
      const entries=record(value)?{...value}:{};
      for(const [id,entry] of Object.entries(entries)){
        if(!record(entry)||typeof entry.day!=='string'||entry.day<cutoff)delete entries[id];
      }
      if(!entries[key])entries[key]={day:dayKey(now())};
      return entries;
    },undefined,false),()=>ownerIndex.child(key).remove());
    const day=claimed.snapshot.val()[key].day,ref=db.ref(`productTelemetryDaily/${day}/${key}`),index=ownerIndex.child(key);
    let conflict=false;
    try{
      await check();
      const outcome=await ref.transaction(value=>{
        if(value!=null){conflict=value.digest!==item.digest;return undefined;}
        return {version:VERSION,kind:item.kind,digest:item.digest,receivedAt:now(),counts:item.counts};
      },undefined,false);
      if(conflict)throw failure(409,'telemetry-delivery-conflict');
      await check();
      return {ok:true,accepted:item.accepted,idempotent:!outcome.committed};
    }catch(error){
      if(error.code==='telemetry-consent-required'||error.code==='account-deleted'||error.code==='account-deletion-in-progress'){
        await Promise.all([ref.remove(),index.remove()]);
      }
      throw error;
    }
  }
  async function sweep(){
    const cutoff=dayKey(now()-RETENTION_DAYS*86400000);
    const old=await db.ref('productTelemetryDaily').orderByKey().endBefore(cutoff).limitToFirst(32).get();
    const updates={};old.forEach(child=>{updates[`productTelemetryDaily/${child.key}`]=null;});
    if(Object.keys(updates).length)await db.ref().update(updates);
    // Expire the private erase index too; bounded cursor scans include inactive
    // owners instead of retaining their delivery bookmarks indefinitely.
    const state=db.ref('productTelemetryMaintenance/ownerCursor');
    const cursor=(await state.get()).val();
    let query=db.ref('productTelemetryOwners').orderByKey();
    if(typeof cursor==='string'&&/^[A-Za-z0-9_-]{6,128}$/.test(cursor))query=query.startAfter(cursor);
    const owners=await query.limitToFirst(128).get();
    let last=null,count=0;
    const pruned={};
    owners.forEach(owner=>{
      last=owner.key;count++;
      for(const [id,entry] of Object.entries(owner.val()||{})){
        if(/^[a-f0-9]{64}$/.test(id)&&record(entry)&&typeof entry.day==='string'&&entry.day<cutoff){
          pruned[`productTelemetryOwners/${owner.key}/${id}`]=null;
        }
      }
    });
    if(Object.keys(pruned).length)await db.ref().update(pruned);
    await state.set(count===128?last:null);
  }
  return {routes:{getProductTelemetryConsent,setProductTelemetryConsent,submitProductTelemetry},purgeUser,sweep};
}
module.exports={createProductTelemetryApi,analyticsSample,diagnosticSample,delivery,consentValue,EVENTS,VERSION,MAX_BATCH,RETENTION_DAYS};
