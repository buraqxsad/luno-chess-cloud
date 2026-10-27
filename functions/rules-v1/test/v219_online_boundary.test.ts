import test from 'node:test';
import assert from 'node:assert/strict';
import {STARTER,clone} from '../src/model.js';
import {commitAction,createServerMatch,finishMatch,postMatchAnalysis} from '../src/online/authority.js';
import {BattleError,PROTOCOL,parseActionRequest,reconnectSnapshot,type ServerMatch} from '../src/online/protocol.js';

function fixture():ServerMatch {
  return createServerMatch('bv1_'+'a'.repeat(32),
    {uid:'alice',name:'Alice',bot:false},{uid:'bob',name:'Bob',bot:false},
    STARTER,STARTER,1000);
}

function request(match:ServerMatch) {
  return parseActionRequest({matchId:match.matchId,protocolVersion:PROTOCOL,
    expectedStateVersion:match.stateVersion,actionId:`a${match.stateVersion}_v219-original-action`,
    intent:{type:'move',uci:'e2e4'}});
}

const rejected=(code:string)=>(error:unknown)=>error instanceof BattleError&&error.code===code;

test('V219 recovered original action is applied once and conflicting ID never mutates',()=>{
  const initial=fixture(),body=request(initial);
  const accepted=commitAction(initial,'alice',body,2000).match;
  const before=clone(accepted);
  const recovered=commitAction(accepted,'alice',body,3000);
  assert.equal(recovered.duplicate,true);
  assert.equal(recovered.acceptedVersion,1);
  assert.deepEqual(recovered.match,before);
  assert.throws(()=>commitAction(accepted,'alice',{
    ...body,intent:{type:'move',uci:'d2d4'},
  },3000),rejected('ACTION_ID_CONFLICT'));
  assert.throws(()=>commitAction(accepted,'bob',body,3000),rejected('ACTION_ID_CONFLICT'));
  assert.deepEqual(accepted,before);
});

test('V219 unauthorized, illegal and forged-envelope requests do not mutate authority',()=>{
  const match=fixture(),before=clone(match),body=request(match);
  assert.throws(()=>commitAction(match,'attacker',body,2000),rejected('NOT_PARTICIPANT'));
  assert.throws(()=>commitAction(match,'bob',body,2000),rejected('NOT_YOUR_TURN'));
  assert.throws(()=>commitAction(match,'alice',{
    ...body,intent:{type:'move',uci:'e2e5'},
  },2000),rejected('INVALID_ACTION'));
  for(const injected of [{uid:'bob'},{mana:6},{hand:['freeze']},{state:before}]) {
    assert.throws(()=>parseActionRequest({...body,...injected}),rejected('INVALID_ACTION'));
  }
  for(const intent of [
    {type:'move',uci:'e2e4',uid:'bob'},
    {type:'resolve',order:['radar','radar']},
    {type:'resolve',order:['radar'],selected:42},
    {type:'play',card:'freeze',target:64},
  ]) assert.throws(()=>parseActionRequest({...body,intent}),rejected('INVALID_ACTION'));
  assert.deepEqual(match,before);
});

test('V219 active reconnect exposes only the viewer private data, never analysis',()=>{
  const match=fixture(),changed=clone(match);
  changed.battle.hidden.hands.b.reverse();
  changed.battle.hidden.decks.b.reverse();
  changed.battle.hidden.knowledge.b.pendingCards=['freeze'];
  changed.battle.hidden.knowledge.b.knownUpcomingCards=['radar'];
  assert.deepEqual(reconnectSnapshot(match,'alice'),reconnectSnapshot(changed,'alice'));
  assert.equal(postMatchAnalysis(match,'alice'),null);
  const own=reconnectSnapshot(changed,'alice').view.private;
  assert.deepEqual(Object.keys(own).sort(),['handJson','knowledgeJson','stateVersion','viewer']);
  assert.throws(()=>reconnectSnapshot(match,'attacker'),rejected('NOT_PARTICIPANT'));
});

test('V219 original action remains idempotent after terminal state',()=>{
  const match=fixture(),body=request(match);
  const accepted=commitAction(match,'alice',body,2000).match;
  const terminal=finishMatch(accepted,{reason:'resign',winner:'w',finishedAt:3000});
  const before=clone(terminal);
  const replay=commitAction(terminal,'alice',body,4000);
  assert.equal(replay.duplicate,true);
  assert.equal(replay.acceptedVersion,1);
  assert.deepEqual(terminal,before);
  assert.throws(()=>commitAction(terminal,'alice',{
    ...body,actionId:'a0_v219-new-terminal-action',
  },4000),rejected('MATCH_TERMINAL'));
  assert.deepEqual(terminal,before);
});

test('V219 existing post-match analysis policy stays participant-only and settlement-gated',()=>{
  const match=fixture(),terminal=finishMatch(match,{reason:'resign',winner:'b',finishedAt:2000});
  assert.equal(postMatchAnalysis(terminal,'alice'),null);
  terminal.settlementStatus='complete';
  const analysis=postMatchAnalysis(terminal,'alice');
  assert(analysis);
  assert.deepEqual(analysis.history,terminal.audit);
  assert.throws(()=>postMatchAnalysis(terminal,'attacker'),rejected('NOT_PARTICIPANT'));
});
