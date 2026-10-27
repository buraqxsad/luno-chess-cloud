'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {createProductTelemetryApi,analyticsSample,diagnosticSample,delivery,consentValue,EVENTS}=require('../lib/product-telemetry');
const uid='player_self',other='player_other';
const clone=value=>value==null?null:structuredClone(value);
function setup({consent,afterRead}={}){
  let time=Date.parse('2026-10-09T23:59:00Z'),deleted=false;
  const root={users:{[uid]:{uid,username:'PRIVATE_NAME',productTelemetryConsent:consent},[other]:{uid:other}}},writes=[],limits=[];
  const read=path=>clone(path.split('/').filter(Boolean).reduce((v,k)=>v?.[k],root));
  function write(path,value){const keys=path.split('/').filter(Boolean),last=keys.pop();let node=root;
    for(const key of keys)node=node[key]??={};if(value==null)delete node[last];else node[last]=clone(value);writes.push(path);}
  const snap=value=>({val:()=>clone(value),exists:()=>value!=null,forEach(fn){for(const key of Object.keys(value||{}).sort())if(fn({key,val:()=>clone(value[key])})===true)break;}});
  function ref(path='',q={}){return {child:key=>ref(path+'/'+key),
    orderByKey:()=>ref(path,{...q,order:true}),endBefore:end=>ref(path,{...q,end}),startAfter:after=>ref(path,{...q,after}),limitToFirst:limit=>ref(path,{...q,limit}),
    async get(){let value=read(path);if(q.order){let rows=Object.entries(value||{}).filter(([key])=>(!q.end||key<q.end)&&(!q.after||key>q.after)).sort(([a],[b])=>a.localeCompare(b));if(q.limit)rows=rows.slice(0,q.limit);value=rows.length?Object.fromEntries(rows):null;}
      afterRead?.(path,{write,root});return snap(value);},
    async set(value){write(path,value);},async remove(){write(path,null);},
    async update(values){for(const [key,value] of Object.entries(values))write([path,key].filter(Boolean).join('/'),value);},
    async transaction(change){change(null);const next=change(read(path));if(next!==undefined)write(path,next);return {committed:next!==undefined,snapshot:snap(read(path))};}
  };}
  const allowed=async()=>{if(deleted)throw Object.assign(new Error('deleted'),{code:'account-deleted',status:410});};
  const api=createProductTelemetryApi({db:{ref},now:()=>time,
    requirePlayer:async id=>{await allowed();const p=read('users/'+id);if(!p)throw new Error('missing');return p;},
    rateLimit:async(...args)=>limits.push(args),assertAccountOperationAllowed:allowed,
    writeAccountMetadata:async(_uid,_operation,work,cleanup)=>{await allowed();const value=await work();try{await allowed();}catch(error){await cleanup();throw error;}return value;},
    transactExistingPlayer:async(id,mutate)=>{const p=read('users/'+id),decision=mutate(p);if(decision.commit!==false)write('users/'+id,p);return {profile:read('users/'+id),decision};}});
  return {api:api.routes,purge:api.purgeUser,sweep:api.sweep,root,read,write,writes,limits,
    advance:ms=>time+=ms,delete:()=>{deleted=true;}};
}
const approved={version:1,revision:1,analytics:true,diagnostics:true};
const body=(extra={})=>({version:1,kind:'analytics',consentRevision:1,deliveryId:'a'.repeat(32),samples:[{event:'first_match_completed',elapsedMs:120000,mode:'ai',result:'win'}],...extra});
const context=value=>({uid,body:value});

test('event wire catalog has all 23 required events plus three existing typed funnel events',()=>{
  assert.equal(EVENTS.length,26);assert.equal(new Set(EVENTS).size,26);
  for(const event of ['intro_step','intro_completed','first_match_abandoned','first_match_completed','card_drawn','card_played','card_discarded','card_cancelled','matchmaking_wait_bucket'])assert.ok(EVENTS.includes(event));
});
test('missing consent is OFF; UGC acceptance is not analytics consent',async()=>{
  const s=setup();s.root.users[uid].legalConsent={accepted:true};
  assert.deepEqual((await s.api.getProductTelemetryConsent(context({}))).consent,{version:1,revision:0,analytics:false,diagnostics:false});
  await assert.rejects(s.api.submitProductTelemetry(context(body())),{code:'telemetry-consent-required'});assert.equal(s.writes.length,0);
});
test('independent choices persist with a monotonic revision and idempotent replay',async()=>{
  const s=setup(),choice={version:1,expectedRevision:0,analytics:true,diagnostics:false};
  const first=await s.api.setProductTelemetryConsent(context(choice)),again=await s.api.setProductTelemetryConsent(context(choice));
  assert.equal(first.consent.revision,1);assert.deepEqual(again.consent,first.consent);assert.equal(s.root.users[uid].username,'PRIVATE_NAME');
  await assert.rejects(s.api.submitProductTelemetry(context(body({kind:'diagnostics',samples:[{source:'async',category:'unknown',component:'unknown',fingerprint:'a'.repeat(16)}]}))),{code:'telemetry-consent-required'});
});
test('stale opt-in cannot undo a later opt-out',async()=>{
  const s=setup({consent:approved});
  await s.api.setProductTelemetryConsent(context({version:1,expectedRevision:1,analytics:false,diagnostics:false}));
  await assert.rejects(s.api.setProductTelemetryConsent(context({version:1,expectedRevision:1,analytics:true,diagnostics:true})),{code:'telemetry-consent-changed'});
  assert.equal(s.root.users[uid].productTelemetryConsent.analytics,false);
});
for(const invalid of [null,{},[],{version:1,revision:0,analytics:true,diagnostics:false},{...approved,revision:'1'},{...approved,analytics:1},{...approved,version:2}]){
  if(invalid===null)continue;
  test('corrupt consent never becomes enabled: '+JSON.stringify(invalid),()=>assert.throws(()=>consentValue(invalid),{code:'telemetry-consent-unavailable'}));
}
test('aggregate delivery stores no UID, identity, raw sample or private card data',async()=>{
  const s=setup({consent:approved}),result=await s.api.submitProductTelemetry(context(body()));
  assert.deepEqual(result,{ok:true,accepted:1,idempotent:false});
  const records=s.root.productTelemetryDaily['2026-10-09'];assert.equal(Object.keys(records).length,1);
  const saved=Object.values(records)[0];assert.deepEqual(saved.counts,{'first_match_completed:ai:win:none:none:2':1});
  for(const secret of [uid,'PRIVATE_NAME','samples','FEN','token','deck'])assert.ok(!JSON.stringify(records).includes(secret));
  assert.ok(s.limits.some(row=>row[1]==='productTelemetryDaily'&&row[2]===300));
});
test('duplicate requests and midnight retries cannot double-count',async()=>{
  const s=setup({consent:approved});
  await s.api.submitProductTelemetry(context(body()));s.advance(120000);
  assert.equal((await s.api.submitProductTelemetry(context(body()))).idempotent,true);
  assert.equal(Object.keys(s.root.productTelemetryDaily).length,1);
  assert.equal(Object.keys(s.root.productTelemetryDaily['2026-10-09']).length,1);
});
test('same delivery id with another payload is rejected, not counted twice',async()=>{
  const s=setup({consent:approved});await s.api.submitProductTelemetry(context(body()));
  await assert.rejects(s.api.submitProductTelemetry(context(body({samples:[{event:'deck_opened',elapsedMs:0}]}))),{code:'telemetry-delivery-conflict'});
  assert.equal(Object.keys(s.root.productTelemetryDaily['2026-10-09']).length,1);
});
for(const extra of [{uid:'private'}, {username:'private'},{token:'private'},{fen:'private'},{cardId:'freeze'},{deck:['private']},{message:'private'},{bio:'private'}]){
  test('rejects unapproved private analytics properties: '+Object.keys(extra)[0],async()=>{
    const s=setup({consent:approved});await assert.rejects(s.api.submitProductTelemetry(context(body({samples:[{event:'card_played',elapsedMs:0,...extra}]}))),{code:'invalid-telemetry'});assert.equal(s.writes.length,0);
  });
}
for(const samples of [[],new Array(17).fill({event:'first_open',elapsedMs:0}),[{event:'unknown',elapsedMs:0}],[{event:'card_played',elapsedMs:-1}],[{event:'first_open',elapsedMs:0,step:1}],[{event:'intro_step',elapsedMs:0,step:64}],[{event:'first_open',elapsedMs:0,mode:'friend_username'}]]){
  test('strict sample bounds: '+JSON.stringify(samples).slice(0,80),()=>assert.throws(()=>delivery(body({samples})),{code:'invalid-telemetry'}));
}
test('diagnostics accept only coarse enums and sanitized fingerprint',()=>{
  assert.deepEqual(diagnosticSample({source:'framework',category:'state',component:'battle',fingerprint:'a'.repeat(16)}),{source:'framework',category:'state',component:'battle',fingerprint:'a'.repeat(16)});
  for(const extra of [{message:'secret'},{stack:'secret'},{url:'secret'}])assert.throws(()=>diagnosticSample({source:'async',category:'unknown',component:'unknown',fingerprint:'a'.repeat(16),...extra}),{code:'invalid-telemetry'});
  assert.throws(()=>diagnosticSample({source:'unknown',category:'unknown',component:'unknown',fingerprint:'a'.repeat(16)}),{code:'invalid-telemetry'});
});
test('all-off revocation purges prior optional records and private indexes',async()=>{
  const s=setup({consent:approved});await s.api.submitProductTelemetry(context(body()));
  await s.api.setProductTelemetryConsent(context({version:1,expectedRevision:1,analytics:false,diagnostics:false}));
  assert.deepEqual(s.root.productTelemetryDaily['2026-10-09'],{});assert.equal(s.read('productTelemetryOwners/'+uid),null);
});
test('account deletion hook purges only that account records',async()=>{
  const s=setup({consent:approved});s.root.users[other].productTelemetryConsent=approved;
  await s.api.submitProductTelemetry(context(body()));await s.api.submitProductTelemetry({uid:other,body:body()});
  await s.purge(uid);assert.equal(Object.keys(s.root.productTelemetryDaily['2026-10-09']).length,1);assert.ok(s.read('productTelemetryOwners/'+other));
});
test('expired day records are removed by bounded retention sweep',async()=>{
  const s=setup({consent:approved});s.root.productTelemetryDaily={'2026-08-01':{old:{counts:{first_open:1}}},'2026-10-09':{current:{counts:{first_open:1}}}};
  await s.sweep();assert.equal(s.read('productTelemetryDaily/2026-08-01'),null);assert.ok(s.read('productTelemetryDaily/2026-10-09'));
});
test('retention also removes inactive-account private erase bookmarks',async()=>{
  const s=setup();s.root.productTelemetryOwners={[uid]:{['a'.repeat(64)]:{day:'2026-08-01'},['b'.repeat(64)]:{day:'2026-10-09'}}};
  await s.sweep();assert.equal(s.read('productTelemetryOwners/'+uid+'/'+'a'.repeat(64)),null);
  assert.ok(s.read('productTelemetryOwners/'+uid+'/'+'b'.repeat(64)));
});
test('late consent revocation removes a committed in-flight delivery',async()=>{
  let checks=0;
  // Inject revocation at the final profile read, after the record transaction.
  const db={ref(path){return {async get(){return {val:()=>null};},async transaction(fn){const v=fn(null);checks++;return {committed:true,snapshot:{val:()=>v}};},async remove(){},child(){return this;}};}};
  let profiles=0,removed=0;
  const api=createProductTelemetryApi({db:{ref(path){const r=db.ref(path);r.set=async()=>{};r.remove=async()=>{removed++;};return r;}},now:()=>Date.parse('2026-10-09'),rateLimit:async()=>{},
    requirePlayer:async()=>({uid,productTelemetryConsent:++profiles>=3?{...approved,revision:2,analytics:false}:approved}),
    assertAccountOperationAllowed:async()=>{},writeAccountMetadata:async(_u,_o,work)=>work(),transactExistingPlayer:async()=>{}});
  await assert.rejects(api.routes.submitProductTelemetry(context(body())),{code:'telemetry-consent-required'});
  assert.equal(checks,2);assert.ok(removed>=1);
});
