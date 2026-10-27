'use strict';

const test=require('node:test'),assert=require('node:assert/strict');
const {getAuth}=require('firebase-admin/auth');
const {getAppCheck}=require('firebase-admin/app-check');
const {getDatabase}=require('firebase-admin/database');
const logger=require('firebase-functions/logger');
const api=require('../index')._test;
const {memoryDatabase}=require('./helpers/memory-database');

const sender='v219_sender',recipient='v219_recipient',outsider='v219_outsider';
const conversation=api.conversationId(sender,recipient),baseTime=Date.UTC(2026,9,11,12);
function seed(){
  const users={};
  for(const uid of [sender,recipient,outsider]){
    users[uid]=api.starterProfile(uid,uid);
    users[uid].legalConsent={uid,acceptedAt:1,termsVersion:api.LEGAL_TERMS_VERSION,
      privacyVersion:api.LEGAL_PRIVACY_VERSION,communityVersion:api.LEGAL_COMMUNITY_VERSION};
  }
  return {users};
}
function setup(t,data=seed(),options={}){
  let time=baseTime,push=0;
  t.mock.method(Date,'now',()=>time);
  t.mock.method(getAuth(),'verifyIdToken',async uid=>({uid,auth_time:Math.floor(time/1000),firebase:{sign_in_provider:'anonymous'}}));
  t.mock.method(getAuth(),'deleteUser',async()=>{});
  t.mock.method(getAppCheck(),'verifyToken',async()=>({appId:'1:955253747543:android:136188eaab561c9b29d812'}));
  for(const level of ['info','warn','error'])t.mock.method(logger,level,()=>{});
  const db=memoryDatabase(t,data,options),database=getDatabase(),ref=database.ref.bind(database);
  t.mock.method(database,'ref',(path='',...args)=>{
    const node=ref(path,...args);
    return {...node,
      orderByChild(child){
        if(!child.includes('/'))return node.orderByChild(child);
        return {equalTo(expected){
          return {async once(event){
            if(event!=='value')throw new Error('Only one-time value reads are modeled.');
            return this.get();
          },async get(){
            const value=Object.fromEntries(Object.entries(db.read(path)||{}).filter(([,row])=>
              child.split('/').reduce((current,key)=>current&&current[key],row)===expected));
            return {val:()=>structuredClone(value),exists:()=>Object.keys(value).length>0};
          }};
        }};
      },
      push(value){
        if(arguments.length)return node.push(value);
        const key='-v219_'+String(++push).padStart(12,'0');
        return {...ref(path+'/'+key),key};
      },
      async update(values){
        await node.update(values);
        if(options.afterUpdate)await options.afterUpdate(path,values,db);
      },
    };
  });
  return {...db,setTime:value=>{time=value;}};
}
async function request(route,body={},id='v219-social-request',uid=sender){
  const headers={authorization:'Bearer '+uid,'x-firebase-appcheck':'check','x-luno-request-id':id};
  let status,result;
  await api.handler({method:'POST',path:'/'+route,body,get:name=>headers[name.toLowerCase()]||''},
    {set(){return this;},status(value){status=value;return this;},json(value){result=value;}});
  return {status,body:result};
}
function deleteRecipient(store){
  store.write('accountDeletions/'+api.hash(recipient),{status:'complete'});
  store.write('deletedAccounts/'+api.hash(recipient),{deletedAt:baseTime});
  store.write('users/'+recipient,null);
  store.write('dm/'+conversation,null);
  for(const root of ['dmInbox','friends','friendRequests','outgoingFriendRequests','blocks','blockedBy','mutes','messageThrottle']){
    store.write(root+'/'+recipient,null);store.write(root+'/'+sender+'/'+recipient,null);
  }
  store.write('notifications/'+recipient,null);
}
function assertNoPairData(db){
  assert.equal(db.read('dm/'+conversation),null);
  for(const root of ['dmInbox','friends','friendRequests','outgoingFriendRequests','blocks','blockedBy','mutes','messageThrottle']){
    assert.equal(db.read(root+'/'+sender+'/'+recipient),null,root+' sender edge');
    assert.equal(db.read(root+'/'+recipient+'/'+sender),null,root+' recipient edge');
  }
  assert.equal(db.read('notifications/'+recipient),null);
  assert.ok(db.read('users/'+sender));assert.equal(db.read('users/'+recipient),null);
}

for(const route of ['openDirectMessage','sendDirectMessage']){
  test(route+' cannot recreate a conversation when recipient deletion wins after prechecks',async t=>{
    let erased=false;
    const db=setup(t,seed(),{beforeTransaction(path,count,store){
      if(!erased&&path==='dm/'+conversation){erased=true;deleteRecipient(store);}
    }});
    const result=await request(route,{targetUid:recipient,...(route==='sendDirectMessage'?{text:'late private message'}:{})});
    assert.equal(erased,true);assert.equal(result.status,404,JSON.stringify(result.body));
    assert.equal(result.body.error,'target-not-found');assertNoPairData(db);
  });
}
for(const route of ['sendDirectMessage','sendFriendRequest','blockUser','setConversationMuted']){
  test(route+' removes late pair metadata when deletion occurs immediately before its write',async t=>{
    let erased=false;
    const db=setup(t,seed(),{beforeWrite(path,kind,store){
      const values=store.values||{};
      const writesPair=path===''&&Object.keys(values).some(key=>
        key.startsWith('dm/'+conversation+'/msgs/')||key.startsWith('friendRequests/'+recipient+'/')||key==='blocks/'+sender+'/'+recipient);
      if(!erased&&(writesPair||path==='mutes/'+sender+'/'+recipient)){
        erased=true;deleteRecipient(store);
      }
    }});
    const result=await request(route,{targetUid:recipient,...(route==='sendDirectMessage'?{text:'late private message'}:{}),
      ...(route==='setConversationMuted'?{muted:true}:{})});
    assert.equal(erased,true);assert.equal(result.status,404,JSON.stringify(result.body));
    assert.equal(result.body.error,'target-not-found');assertNoPairData(db);
  });
}
test('sender deletion after DM prechecks is fenced without restoring sender data',async t=>{
  let erased=false;
  const db=setup(t,seed(),{beforeTransaction(path,count,store){
    if(!erased&&path==='dm/'+conversation){
      erased=true;store.write('users/'+sender,null);
      store.write('deletedAccounts/'+api.hash(sender),{deletedAt:baseTime});
      store.write('dm/'+conversation,null);
    }
  }});
  const result=await request('sendDirectMessage',{targetUid:recipient,text:'late sender'});
  assert.equal(result.status,403);assert.equal(result.body.error,'account-deleted');
  assert.equal(db.read('dm/'+conversation),null);assert.equal(db.read('dmInbox/'+recipient+'/'+sender),null);
  assert.equal(db.read('users/'+sender),null);assert.ok(db.read('users/'+recipient));
  assert.equal(db.read('messageThrottle/'+sender),null);
});
test('recipient privacy is reread inside the social lock rather than using a cached profile',async t=>{
  let changed=false;
  const db=setup(t,seed(),{afterRead(path,count,store){
    if(!changed&&path==='users/'+recipient){changed=true;store.write(path+'/dmFriendsOnly',true);}
  }});
  const result=await request('sendDirectMessage',{targetUid:recipient,text:'not a friend'});
  assert.equal(result.status,403);assert.equal(result.body.error,'friends-only');
  assert.equal(db.read('dm/'+conversation),null);assert.equal(db.read('dmInbox/'+recipient+'/'+sender),null);
});
test('recipient deletion after a committed DM write also removes its durable proof',async t=>{
  let erased=false;
  const db=setup(t,seed(),{afterUpdate(path,values,store){
    if(!erased&&path===''&&Object.keys(values).some(key=>key.startsWith('dm/'+conversation+'/msgs/'))){
      erased=true;deleteRecipient(store);
      // Simulate a late sibling write arriving after the deletion cleanup.
      for(const [key,value] of Object.entries(values))store.write(key,value);
      throw new Error('committed delivery response lost during deletion');
    }
  }});
  const result=await request('sendDirectMessage',{targetUid:recipient,text:'deleted after commit'});
  assert.equal(erased,true);assert.equal(result.status,404);assert.equal(result.body.error,'target-not-found');
  assertNoPairData(db);
});
test('accepting a friend request cannot restore friendship after recipient deletion wins the write',async t=>{
  const data=seed();data.friendRequests={[sender]:{[recipient]:{fromUid:recipient}}};
  data.outgoingFriendRequests={[recipient]:{[sender]:{sentAt:1}}};
  data.friends={[sender]:{[outsider]:{addedAt:2}},[outsider]:{[sender]:{addedAt:2}}};
  data.notifications={[sender]:{unrelated:{fromUid:outsider,type:'friend_request'}}};
  let erased=false;
  const db=setup(t,data,{beforeWrite(path,kind,store){
    if(!erased&&path===''&&store.values&&store.values['friends/'+sender+'/'+recipient]){
      erased=true;deleteRecipient(store);
    }
  }});
  const result=await request('respondFriendRequest',{fromUid:recipient,accept:true});
  assert.equal(erased,true);assert.equal(result.status,404);assertNoPairData(db);
  assert.deepEqual(db.read('friends/'+sender+'/'+outsider),{addedAt:2});
  assert.deepEqual(db.read('notifications/'+sender+'/unrelated'),{fromUid:outsider,type:'friend_request'});
});
test('deleted targets remain unblockable and unrelated social data survives cleanup',async t=>{
  const data=seed();delete data.users[recipient];data.deletedAccounts={[api.hash(recipient)]:{deletedAt:baseTime}};
  data.blocks={[sender]:{[recipient]:{createdAt:1},[outsider]:{createdAt:2}}};
  data.blockedBy={[recipient]:{[sender]:true},[outsider]:{[sender]:true}};
  const db=setup(t,data),result=await request('unblockUser',{targetUid:recipient});
  assert.equal(result.status,200);assert.equal(db.read('blocks/'+sender+'/'+recipient),null);
  assert.deepEqual(db.read('blocks/'+sender+'/'+outsider),{createdAt:2});
});

for(const failure of ['completion-write','lost-message-write-response']){
  test('durable DM proof survives '+failure+' and replay cannot rewind newer inboxes',async t=>{
    const id='v219-durable-'+failure,requestPath='serverRequests/'+sender+'/'+api.hash(id).slice(0,48);
    let failed=false;
    const db=setup(t,seed(),{
      beforeTransaction(path,count){
        if(failure==='completion-write'&&!failed&&path===requestPath&&count===2){failed=true;throw new Error('completion unavailable');}
      },
      afterUpdate(path,values){
        if(failure==='lost-message-write-response'&&!failed&&path===''&&Object.keys(values).some(key=>key.startsWith('dm/'+conversation+'/msgs/'))){
          failed=true;throw new Error('committed response lost');
        }
      },
    });
    const first=await request('sendDirectMessage',{targetUid:recipient,text:'original delivery'},id);
    assert.equal(first.status,500);assert.equal(failed,true);
    const original=Object.keys(db.read('dm/'+conversation+'/msgs')||{});
    assert.equal(original.length,1);assert.equal(db.read(requestPath),null);
    db.setTime(baseTime+31000);
    const newer=await request('sendDirectMessage',{targetUid:recipient,text:'newer delivery'},id+'-newer');
    assert.equal(newer.status,200,JSON.stringify(newer.body));
    db.write('dmInbox/'+recipient+'/'+sender+'/unread',false);
    db.write('dmInbox/'+recipient+'/'+sender+'/lastReadMessageId',newer.body.messageId);
    const inbox=structuredClone(db.read('dmInbox')),throttle=structuredClone(db.read('messageThrottle'));
    db.setTime(baseTime+62000);
    const replay=await request('sendDirectMessage',{targetUid:recipient,text:'original delivery'},id);
    assert.equal(replay.status,200,JSON.stringify(replay.body));assert.equal(replay.body.idempotent,true);
    assert.equal(replay.body.messageId,original[0]);
    assert.equal(Object.keys(db.read('dm/'+conversation+'/msgs')).length,2);
    assert.deepEqual(db.read('dmInbox'),inbox);assert.deepEqual(db.read('messageThrottle'),throttle);
  });
}
test('committed DM replay bypasses cooldown but changed payload fails closed',async t=>{
  const db=setup(t),id='v219-payload-proof',path='serverRequests/'+sender+'/'+api.hash(id).slice(0,48);
  const first=await request('sendDirectMessage',{targetUid:recipient,text:'same content'},id);
  assert.equal(first.status,200);db.write(path,null);
  const replay=await request('sendDirectMessage',{targetUid:recipient,text:'same content'},id);
  assert.equal(replay.status,200,JSON.stringify(replay.body));assert.equal(replay.body.messageId,first.body.messageId);
  db.write(path,null);db.setTime(baseTime+31000);
  const before=structuredClone(db.read('dm/'+conversation));
  const conflict=await request('sendDirectMessage',{targetUid:recipient,text:'different content'},id);
  assert.equal(conflict.status,409);assert.equal(conflict.body.error,'request-id-conflict');
  assert.deepEqual(db.read('dm/'+conversation),before);
});
test('DM request IDs remain sender-scoped for both participants',async t=>{
  const db=setup(t),id='v219-both-senders';
  const first=await request('sendDirectMessage',{targetUid:recipient,text:'sender delivery'},id);
  const second=await request('sendDirectMessage',{targetUid:sender,text:'recipient delivery'},id,recipient);
  assert.equal(first.status,200);assert.equal(second.status,200,JSON.stringify(second.body));
  assert.notEqual(first.body.messageId,second.body.messageId);
  assert.equal(Object.keys(db.read('dm/'+conversation+'/msgs')).length,2);
  for(const uid of [sender,recipient])db.write('serverRequests/'+uid+'/'+api.hash(id).slice(0,48),null);
  const before=structuredClone(db.read('dmInbox'));
  const replay=await request('sendDirectMessage',{targetUid:sender,text:'recipient delivery'},id,recipient);
  assert.equal(replay.status,200);assert.equal(replay.body.messageId,second.body.messageId);
  assert.deepEqual(db.read('dmInbox'),before);
});
for(const damage of ['missing-message','wrong-sender','wrong-receipt-owner']){
  test('DM committed proof fails closed for '+damage,async t=>{
    const db=setup(t),id='v219-proof-damage-'+damage;
    const first=await request('sendDirectMessage',{targetUid:recipient,text:'verified content'},id);
    assert.equal(first.status,200);
    const messagePath='dm/'+conversation+'/msgs/'+first.body.messageId;
    const proofPath='dm/'+conversation+'/sendRequests/'+api.hash(sender)+'/'+api.hash(id);
    if(damage==='missing-message')db.write(messagePath,null);
    if(damage==='wrong-sender')db.write(messagePath+'/from',outsider);
    if(damage==='wrong-receipt-owner')db.write(proofPath+'/uidHash',api.hash(outsider));
    db.write('serverRequests/'+sender+'/'+api.hash(id).slice(0,48),null);db.setTime(baseTime+31000);
    const before=structuredClone(db.read('dm')),inbox=structuredClone(db.read('dmInbox'));
    const replay=await request('sendDirectMessage',{targetUid:recipient,text:'verified content'},id);
    assert.equal(replay.status,409);assert.equal(replay.body.error,'dm-send-receipt-invalid');
    assert.deepEqual(db.read('dm'),before);assert.deepEqual(db.read('dmInbox'),inbox);
  });
}

test('a colliding replacement preserves foreign members and removes only the late owned delivery',async t=>{
  const a='alpha1_beta22',b='gamma3',c='alpha1',d='beta22_gamma3',key=api.conversationId(a,b);
  assert.equal(key,api.conversationId(c,d));
  const data=seed();
  for(const uid of [a,b,c,d]){
    data.users[uid]=api.starterProfile(uid,uid);
    data.users[uid].legalConsent={uid,acceptedAt:1,termsVersion:api.LEGAL_TERMS_VERSION,
      privacyVersion:api.LEGAL_PRIVACY_VERSION,communityVersion:api.LEGAL_COMMUNITY_VERSION};
  }
  const foreign={members:{[c]:true,[d]:true},msgs:{kept:{from:c,text:'foreign history',ts:1}},updatedAt:1};
  let replaced=false;
  const db=setup(t,data,{beforeWrite(path,kind,store){
    if(!replaced&&path===''&&Object.keys(store.values||{}).some(path=>path.startsWith('dm/'+key+'/msgs/'))){
      replaced=true;store.write('users/'+b,null);store.write('deletedAccounts/'+api.hash(b),{deletedAt:baseTime});
      store.write('dm/'+key,foreign);
    }
  }});
  const result=await request('sendDirectMessage',{targetUid:b,text:'late secret'},'v219-collision-delivery',a);
  assert.equal(replaced,true);assert.equal(result.status,404);
  assert.deepEqual(db.read('dm/'+key),foreign);
  assert.equal(db.read('dmInbox/'+a+'/'+b),null);assert.equal(db.read('dmInbox/'+b+'/'+a),null);
  for(const uid of [a,c,d])assert.ok(db.read('users/'+uid));
});

test('account erasure finds a DM orphan after block and unblock without removing unrelated conversations',async t=>{
  const db=setup(t),id='v219-orphan-delivery';
  const sent=await request('sendDirectMessage',{targetUid:recipient,text:'erase this private history'},id);
  assert.equal(sent.status,200);
  const blocked=await request('blockUser',{targetUid:recipient},'v219-orphan-block');assert.equal(blocked.status,200);
  const unblocked=await request('unblockUser',{targetUid:recipient},'v219-orphan-unblock');assert.equal(unblocked.status,200);
  assert.equal(db.read('dmInbox/'+sender),null);assert.equal(db.read('blocks/'+sender),null);
  const unrelatedKey=api.conversationId(recipient,outsider),unrelated={members:{[recipient]:true,[outsider]:true},msgs:{kept:{from:outsider,text:'unrelated',ts:1}}};
  db.write('dm/'+unrelatedKey,unrelated);
  const erased=await request('deleteAccount',{confirm:true},'v219-orphan-delete');
  assert.equal(erased.status,200,JSON.stringify(erased.body));assert.equal(db.read('users/'+sender),null);
  assert.equal(db.read('dm/'+conversation),null);assert.deepEqual(db.read('dm/'+unrelatedKey),unrelated);
  assert.ok(db.read('users/'+recipient));assert.ok(db.read('users/'+outsider));
});

test('durable sender/request binding rejects a different recipient after generic cache loss',async t=>{
  const db=setup(t),id='v219-cross-recipient-proof';
  const first=await request('sendDirectMessage',{targetUid:recipient,text:'bound recipient'},id);
  assert.equal(first.status,200);db.write('serverRequests/'+sender,null);db.setTime(baseTime+31000);
  const before=structuredClone(db.read('dm')),inbox=structuredClone(db.read('dmInbox'));
  const conflict=await request('sendDirectMessage',{targetUid:outsider,text:'bound recipient'},id);
  assert.equal(conflict.status,409);assert.equal(conflict.body.error,'request-id-conflict');
  assert.deepEqual(db.read('dm'),before);assert.deepEqual(db.read('dmInbox'),inbox);
  const replay=await request('sendDirectMessage',{targetUid:recipient,text:'bound recipient'},id);
  assert.equal(replay.status,200);assert.equal(replay.body.messageId,first.body.messageId);
  assert.deepEqual(db.read('dm'),before);assert.deepEqual(db.read('dmInbox'),inbox);
});

test('sender/request binding survives recipient erasure without retaining the erased conversation',async t=>{
  const db=setup(t),id='v219-binding-after-erasure';
  const sent=await request('sendDirectMessage',{targetUid:recipient,text:'private erased message'},id);assert.equal(sent.status,200);
  const erased=await request('deleteAccount',{confirm:true},'v219-delete-binding-target',recipient);
  assert.equal(erased.status,200,JSON.stringify(erased.body));assert.equal(db.read('dm/'+conversation),null);
  db.write('serverRequests/'+sender,null);
  const binding=db.read('messageThrottle/'+sender+'/!sendRequests/'+api.hash(id));assert.ok(binding);
  assert.equal(JSON.stringify(binding).includes('private erased message'),false);
  const retry=await request('sendDirectMessage',{targetUid:outsider,text:'private erased message'},id);
  assert.equal(retry.status,409);assert.equal(retry.body.error,'request-id-conflict');
  assert.equal(db.read('dm/'+api.conversationId(sender,outsider)),null);
});

test('legacy committed proof backfills its sender binding without changing inbox or cooldown state',async t=>{
  const db=setup(t),id='v219-legacy-proof-binding';
  const first=await request('sendDirectMessage',{targetUid:recipient,text:'legacy committed delivery'},id);
  assert.equal(first.status,200);db.write('serverRequests/'+sender,null);
  db.write('messageThrottle/'+sender+'/!sendRequests',null);
  const inbox=structuredClone(db.read('dmInbox')),cooldown=structuredClone(db.read('messageThrottle/'+sender+'/'+recipient));
  const conflict=await request('sendDirectMessage',{targetUid:outsider,text:'legacy committed delivery'},id);
  assert.equal(conflict.status,409);assert.equal(conflict.body.error,'request-id-conflict');
  const replay=await request('sendDirectMessage',{targetUid:recipient,text:'legacy committed delivery'},id);
  assert.equal(replay.status,200);assert.equal(replay.body.messageId,first.body.messageId);
  assert.ok(db.read('messageThrottle/'+sender+'/!sendRequests/'+api.hash(id)));
  assert.deepEqual(db.read('dmInbox'),inbox);assert.deepEqual(db.read('messageThrottle/'+sender+'/'+recipient),cooldown);
});

test('proof retention does not silently expire a committed request after a long retry delay',async t=>{
  const db=setup(t),id='v219-long-lived-proof';
  const first=await request('sendDirectMessage',{targetUid:recipient,text:'long lived delivery'},id);assert.equal(first.status,200);
  db.write('serverRequests/'+sender,null);db.setTime(baseTime+720*86400000);
  const before=structuredClone(db.read('dmInbox')),binding=structuredClone(db.read('messageThrottle/'+sender+'/!sendRequests'));
  const replay=await request('sendDirectMessage',{targetUid:recipient,text:'long lived delivery'},id);
  assert.equal(replay.status,200);assert.equal(replay.body.messageId,first.body.messageId);
  assert.deepEqual(db.read('dmInbox'),before);assert.deepEqual(db.read('messageThrottle/'+sender+'/!sendRequests'),binding);
  assert.equal(Object.keys(db.read('dm/'+conversation+'/msgs')).length,1);
});

test('account erasure preserves a foreign colliding conversation despite a stale inbox edge',async t=>{
  const a='alpha1_beta22',b='gamma3',c='alpha1',d='beta22_gamma3',key=api.conversationId(a,b),data=seed();
  data.users[a]=api.starterProfile(a,a);data.users[b]=api.starterProfile(b,b);
  data.dmInbox={[a]:{[b]:{last:'stale'}}};
  const foreign={members:{[c]:true,[d]:true},msgs:{kept:{from:c,text:'preserved foreign history',ts:1}}};
  data.dm={[key]:foreign};
  const db=setup(t,data),result=await request('deleteAccount',{confirm:true},'v219-delete-colliding-index',a);
  assert.equal(result.status,200,JSON.stringify(result.body));assert.equal(db.read('users/'+a),null);
  assert.deepEqual(db.read('dm/'+key),foreign);assert.ok(db.read('users/'+b));
});

test('colliding peers cannot reclaim a freed conversation key before late-delivery cleanup finishes',async t=>{
  const a='alpha1_beta22',b='gamma3',c='alpha1',d='beta22_gamma3',key=api.conversationId(a,b),data=seed();
  for(const uid of [a,b,c,d]){
    data.users[uid]=api.starterProfile(uid,uid);
    data.users[uid].legalConsent={uid,acceptedAt:1,termsVersion:api.LEGAL_TERMS_VERSION,
      privacyVersion:api.LEGAL_PRIVACY_VERSION,communityVersion:api.LEGAL_COMMUNITY_VERSION};
  }
  let second,started=false,finished=false;
  const db=setup(t,data,{async afterUpdate(path,values,store){
    if(!started&&path===''&&Object.keys(values).some(path=>path.startsWith('dm/'+key+'/msgs/'))){
      started=true;store.write('users/'+b,null);store.write('deletedAccounts/'+api.hash(b),{deletedAt:baseTime});
      store.write('dm/'+key,null);
      second=request('openDirectMessage',{targetUid:d},'v219-colliding-lease-second',c).then(result=>{finished=true;return result;});
      await new Promise(resolve=>setImmediate(resolve));
      assert.equal(finished,false);
    }
  }});
  const first=await request('sendDirectMessage',{targetUid:b,text:'lease fenced delivery'},'v219-colliding-lease-first',a);
  assert.equal(started,true);assert.equal(first.status,404);
  const reopened=await second;assert.equal(reopened.status,200,JSON.stringify(reopened.body));
  assert.deepEqual(db.read('dm/'+key+'/members'),{[c]:true,[d]:true});
  assert.equal(db.read('dm/'+key+'/msgs'),null);assert.equal(db.read('dm/'+key+'/sendRequests'),null);
});

test('a damaged sender binding cannot fall back to a new delivery',async t=>{
  const db=setup(t),id='v219-damaged-sender-binding';
  const first=await request('sendDirectMessage',{targetUid:recipient,text:'bound delivery'},id);assert.equal(first.status,200);
  db.write('serverRequests/'+sender,null);
  db.write('messageThrottle/'+sender+'/!sendRequests/'+api.hash(id)+'/uidHash',api.hash(outsider));
  const before=structuredClone(db.read('dm')),inbox=structuredClone(db.read('dmInbox'));
  const replay=await request('sendDirectMessage',{targetUid:recipient,text:'bound delivery'},id);
  assert.equal(replay.status,409);assert.equal(replay.body.error,'dm-send-receipt-invalid');
  assert.deepEqual(db.read('dm'),before);assert.deepEqual(db.read('dmInbox'),inbox);
});
