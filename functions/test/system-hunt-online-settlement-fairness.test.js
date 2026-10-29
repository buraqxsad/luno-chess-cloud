'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {fixture}=require('./helpers/battle-v1-fixture');
const {authority}=require('../lib/battle-v1');
const {STARTER}=require('../rules-v1/dist/src/model');

function orderedQuery(f,child,range={}){
 const next=changes=>orderedQuery(f,child,{...range,...changes});
 return {
  startAt(value,key){return next({start:value,startKey:key});},
  endAt(value){return next({end:value});},
  equalTo(value){return next({equal:value});},
  limitToFirst(limit){return next({limit});},
  async get(){
   const rows=Object.entries(f.read('matchSecretsV1')||{}).sort(([a,av],[b,bv])=>{
    if(av[child]!==bv[child])return av[child]<bv[child]?-1:1;
    return a<b?-1:a>b?1:0;
   }).filter(([key,value])=>{
    const v=value[child];
    if(range.equal!==undefined&&v!==range.equal)return false;
    if(range.start!==undefined&&(v<range.start||v===range.start&&range.startKey!==undefined&&key<range.startKey))return false;
    return range.end===undefined||v<=range.end;
   }).slice(0,range.limit||Infinity);
   f.selectedPages.push({child,range:{...range},ids:rows.map(([key])=>key)});
   const value=rows.length?Object.fromEntries(rows):null;
   return {val:()=>structuredClone(value),exists:()=>value!==null};
  },
 };
}
async function backlog(failedCount=80){
 const f=fixture();f.selectedPages=[];await f.enable();
 await f.api.migrate('alice');await f.api.migrate('bob');
 const base=f.api.db.ref;
 f.failEarly=true;
 const blocked=new Set();
 for(let i=1;i<=failedCount+1;i++){
  const id='bv1_'+i.toString(16).padStart(32,'0'),late=i===failedCount+1;
  const white=late?{uid:'alice',name:'Alice',bot:false}:{uid:'earlier_white_'+i,name:'Earlier white',bot:false};
  const black=late?{uid:'bob',name:'Bob',bot:false}:{uid:'earlier_black_'+i,name:'Earlier black',bot:false};
  const active=authority.createServerMatch(id,white,black,STARTER,STARTER,1000,true);
  active.ratingAtStart={w:0,b:0};
  const finished=authority.finishMatch(active,{reason:'resign',winner:'w',finishedAt:1001});
  f.write('matchSecretsV1/'+id,f.api.stored(finished));
  if(!late)blocked.add(id);else f.lateId=id;
 }
 f.api.db.ref=(path='')=>{
  if(path==='matchSecretsV1')return {orderByChild:child=>orderedQuery(f,child)};
  const ref=base(path),get=ref.get;
  ref.get=async()=>{
   if(f.failEarly&&blocked.has(path.replace(/^matchSecretsV1\//,''))){
    const error=new Error('temporary-record-read-failure');error.code='TEMPORARILY_UNAVAILABLE';throw error;
   }
   return get();
  };
  return ref;
 };
 return f;
}
function late(f){return f.api.hydrate(f.read('matchSecretsV1/'+f.lateId));}

test('V1 pending settlement maintenance advances beyond a full failing page',async()=>{
 const f=await backlog();
 await f.api.sweep();assert.equal(late(f).settlementStatus,'pending');
 await f.api.sweep();
 assert.equal(late(f).settlementStatus,'complete','An unrelated failed page must not indefinitely starve later terminal results.');
 assert.equal(JSON.parse(f.read('battleV1Accounts/alice').accountJson).games,1);
 assert.equal(JSON.parse(f.read('battleV1Accounts/bob').accountJson).games,1);
 assert.ok(f.selectedPages.every(page=>page.ids.length<=80),'Each maintenance query must remain bounded.');
});

test('V1 pending cursor wraps to retry failed records after reaching the tail',async()=>{
 const f=await backlog();await f.api.sweep();await f.api.sweep();
 assert.equal(late(f).settlementStatus,'complete');
 f.failEarly=false;await f.api.sweep();
 for(let i=1;i<=80;i++)assert.equal(f.api.hydrate(f.read('matchSecretsV1/bv1_'+i.toString(16).padStart(32,'0'))).settlementStatus,'complete');
 assert.equal(JSON.parse(f.read('battleV1Accounts/alice').accountJson).games,1,'Wrap retry cannot double-settle the healthy match.');
});

test('V1 maintenance still settles a short healthy backlog without a saved cursor',async()=>{
 const f=await backlog(1);f.failEarly=false;await f.api.sweep();
 assert.equal(late(f).settlementStatus,'complete');
 assert.equal(JSON.parse(f.read('battleV1Accounts/alice').accountJson).games,1);
});
