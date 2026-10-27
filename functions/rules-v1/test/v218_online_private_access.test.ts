import test from 'node:test';
import assert from 'node:assert/strict';
import {STARTER} from '../src/model.js';
import {createServerMatch,finishMatch,postMatchAnalysis,sanitizedActionResponse} from '../src/online/authority.js';
import {BattleError,reconnectSnapshot,sideForUid,toPlayerPrivateState,toPublicMatchState} from '../src/online/protocol.js';

function fixture(whiteUid='alice',blackBot=false){
  return createServerMatch('bv1_'+'a'.repeat(32),
    {uid:whiteUid,name:'Alice',bot:false},{uid:'bob',name:'Bob',bot:blackBot},
    STARTER,STARTER,1000);
}
const denied=(error:unknown)=>error instanceof BattleError&&error.code==='NOT_PARTICIPANT'&&error.status===403;

test('deleted participant loses private snapshots and analysis but retains internal identity',()=>{
  const match=finishMatch(fixture(),{reason:'account-deleted',winner:'b',finishedAt:2000});
  match.deletedParticipants={alice:true};
  match.settlementStatus='complete';
  assert.equal(sideForUid(match,'alice'),'w');
  assert.equal(Object.hasOwn(toPublicMatchState(match).participants,'alice'),false);
  assert.throws(()=>toPlayerPrivateState(match,'alice'),denied);
  assert.throws(()=>reconnectSnapshot(match,'alice'),denied);
  assert.throws(()=>sanitizedActionResponse(match,'alice',true,0),denied);
  assert.throws(()=>postMatchAnalysis(match,'alice'),denied);
  assert.equal(toPlayerPrivateState(match,'bob').viewer,'b');
  assert(postMatchAnalysis(match,'bob'));
});

test('bot identity is internal-only and cannot receive a human private projection',()=>{
  const match=fixture('alice',true);
  assert.equal(sideForUid(match,'bob'),'b');
  assert.equal(Object.hasOwn(toPublicMatchState(match).participants,'bob'),false);
  assert.throws(()=>toPlayerPrivateState(match,'bob'),denied);
  assert.throws(()=>reconnectSnapshot(match,'bob'),denied);
  assert.throws(()=>postMatchAnalysis(match,'bob'),denied);
  assert.equal(reconnectSnapshot(match,'alice').view.private.viewer,'w');
});

for(const uid of ['__proto__','constructor','toString']){
  test('valid UID is an own participant key even when it matches Object.prototype: '+uid,()=>{
    const match=fixture(uid);
    match.deletedParticipants={};
    const participants=toPublicMatchState(match).participants;
    assert.equal(Object.hasOwn(participants,uid),true);
    assert.equal(participants[uid],true);
    assert.equal(reconnectSnapshot(match,uid).view.private.viewer,'w');
    match.deletedParticipants=JSON.parse(JSON.stringify({[uid]:true}));
    assert.equal(Object.hasOwn(toPublicMatchState(match).participants,uid),false);
    assert.throws(()=>toPlayerPrivateState(match,uid),denied);
  });
}
