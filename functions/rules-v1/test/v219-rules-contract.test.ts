import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {applyAuthoritative,playerView} from '../src/authoritative.js';
import {cardTargets,legalActions,publicFingerprint} from '../src/core.js';
import {actionKey,clone,emptyKnowledge,opposite,STARTER,type RuleState,type Side} from '../src/model.js';
import {commitAction,createServerMatch} from '../src/online/authority.js';
import {PROTOCOL,reconnectSnapshot} from '../src/online/protocol.js';
import {initial,runFixture,type Fixture} from './fixture_support.js';

const fixtures=(JSON.parse(readFileSync(resolve(__dirname,'../../../../battle_contract/v1/rules.json'),'utf8')) as {fixtures:Fixture[]}).fixtures;
function fixture(id:string):Fixture {
  const f=fixtures.find(f=>f.fixtureId===id);
  assert.ok(f,id);
  // initial() shares nested setup objects; variants must not mutate the contract.
  return clone(f);
}
const base=initial(fixture('card-mine')).rules;
function changed(edit:(state:RuleState)=>void,rules:RuleState=base):RuleState {
  const s=clone(rules);edit(s);return s;
}

for(const owner of ['w','b'] as const)test(`Mine stays public through server commit and reconnect: ${owner}`,()=>{
  const f=clone(fixture('card-mine')),fen=f.fen!.split(' ');fen[1]=owner;f.fen=fen.join(' ');
  f.blackDeckOrder=[...f.whiteDeckOrder];
  const before=initial(f),match=createServerMatch('bv1_'+'a'.repeat(32),
    {uid:'alice',name:'Alice',bot:false},{uid:'bob',name:'Bob',bot:false},STARTER,STARTER,1000);
  match.battle=before;match.clock.activeSide=owner;
  const committed=commitAction(match,owner==='w'?'alice':'bob',{
    matchId:match.matchId,protocolVersion:PROTOCOL,expectedStateVersion:0,
    actionId:'a0_v219_public_mine',intent:{type:'play',card:'mine',target:21}
  },1001).match;
  assert.equal(committed.battle.rules.mana[owner],before.rules.mana[owner]-2);
  assert.equal(committed.battle.rules.boardEffects[0]!.duration,'persistent');
  assert.equal(committed.lastEvent!.target,21);
  for(const viewer of ['w','b'] as const){
    const snapshot=reconnectSnapshot(committed,viewer==='w'?'alice':'bob');
    const publicState=JSON.parse(snapshot.view.public.rulesJson) as RuleState;
    assert.deepEqual(publicState.boardEffects,[...committed.battle.rules.boardEffects]);
    assert.deepEqual(publicState.boardEffects[0]!.squares,[21]);
    assert.deepEqual(JSON.parse(snapshot.view.private.handJson),committed.battle.hidden.hands[viewer]);
    assert.deepEqual(JSON.parse(snapshot.view.private.knowledgeJson),committed.battle.hidden.knowledge[viewer]);
    assert.deepEqual(Object.keys(snapshot.view.private).sort(),['handJson','knowledgeJson','stateVersion','viewer']);
    for(const secret of ['hidden','hands','decks','knowledge','shuffleSeed'])assert.equal(Object.hasOwn(publicState,secret),false);
    assert.equal(snapshot.view.public.protocolVersion,PROTOCOL);
    assert.equal(snapshot.view.public.rulesetVersion,1);
  }
});

test('public Mine blocks duplicate placement and remains a Break Seal target',()=>{
  const state=initial(fixture('card-mine'));
  state.rules.boardEffects=[{id:'enemy-mine',type:'mine',owner:'b',squares:[21],responseSide:'w',duration:'persistent'}];
  const view=playerView(state,'w'),before=JSON.stringify(state);
  assert.equal(cardTargets(view,'mine').includes(21),false);
  assert.deepEqual(cardTargets(view,'break_seal'),['enemy-mine']);
  assert.throws(()=>applyAuthoritative(state,{type:'play',card:'mine',target:21}),/illegal-action/);
  assert.equal(JSON.stringify(state),before);
});

for(const kingArrival of [false,true])test(`persistent Mine ignores ${kingArrival?'enemy king':'own rook'} arrival`,()=>{
  const state=initial(fixture('mine-watch-castle'));state.rules.vows=[];
  const trap=state.rules.boardEffects[0]!;
  if(kingArrival)trap.squares=[6];else{trap.owner='w';trap.responseSide='b';}
  const after=applyAuthoritative(state,{type:'move',uci:'e1g1'});
  assert.deepEqual(after.rules.boardEffects,state.rules.boardEffects);
  assert.deepEqual(after.rules.pieceEffects,[]);
});

test('Mine fixture variants cannot mutate the canonical contract or later initial states',()=>{
  const canonical=fixtures.find(f=>f.fixtureId==='mine-watch-castle');assert.ok(canonical);
  const before=clone(canonical),variant=initial(fixture('mine-watch-castle'));
  const trap=variant.rules.boardEffects[0]!;trap.owner='w';trap.responseSide='b';trap.squares=[6];
  variant.rules.vows[0]!.owner='w';variant.rules.vows[0]!.square=6;
  const restored=initial(fixture('mine-watch-castle'));
  assert.deepEqual(restored.rules.boardEffects,[{
    id:'trap',type:'mine',squares:[5],duration:'persistent',owner:'b',responseSide:'w'
  }]);
  assert.deepEqual(restored.rules.vows,before.setup!.rules!.vows);
  assert.deepEqual(canonical,before);
  assert.deepEqual(fixture('mine-watch-castle'),before);
});

test('black castling rook triggers public Mine and Watch Vow in the same order',()=>{
  const f=clone(fixture('mine-watch-castle'));f.fen='4k2r/8/8/8/8/8/8/4K3 b k - 0 1';
  const state=initial(f);state.rules.mana={w:1,b:6};
  const trap=state.rules.boardEffects[0]!;trap.owner='w';trap.responseSide='b';trap.squares=[61];
  const vow=state.rules.vows[0]!;vow.owner='w';vow.square=61;
  const after=applyAuthoritative(state,{type:'move',uci:'e8g8'});
  assert.equal(after.rules.fen,'5rk1/8/8/8/8/8/8/4K3 w - - 1 2');
  assert.deepEqual(after.rules.boardEffects,[]);assert.deepEqual(after.rules.vows,[]);
  assert.equal(after.rules.pieceEffects[0]!.type,'mine_debuff');
  assert.equal(after.rules.pieceEffects[0]!.pieceId,'r:63');
  assert.equal(after.rules.pieceEffects[0]!.responseSide,'b');
  assert.equal(after.rules.mana.w,4);
});

test('untriggered Mine does not expire at either player turn boundary',()=>{
  let state=applyAuthoritative(initial(fixture('card-mine')),{type:'play',card:'mine',target:21});
  const trap=clone(state.rules.boardEffects);
  state=applyAuthoritative(state,{type:'move',uci:'a1b1'});assert.deepEqual(state.rules.boardEffects,trap);
  state=applyAuthoritative(state,{type:'pass'});assert.deepEqual(state.rules.boardEffects,trap);
  state=applyAuthoritative(state,{type:'move',uci:'e7e6'});assert.deepEqual(state.rules.boardEffects,trap);
});

for(const id of ['mine-capture-overlap','fog-mine-overlap','mine-debuff-purify',
  'mine-debuff-piece-captured','mine-watch-castle','persistent-mine','break-one-overlap']){
  test(`canonical Mine lifecycle survives serialized authority restoration: ${id}`,()=>{
    const f=fixture(id),expected=runFixture(f);let state=initial(f);
    for(const step of f.steps){
      state=JSON.parse(JSON.stringify(state)) as typeof state;
      if(!step.action)continue;
      if(step.legal===false){
        const before=JSON.stringify(state);
        assert.throws(()=>applyAuthoritative(state,step.action!),/illegal-action/);
        assert.equal(JSON.stringify(state),before);
      }else state=applyAuthoritative(state,step.action);
    }
    assert.deepEqual(state,expected);
  });
}

const changes:Record<string,(s:RuleState)=>void>={
  mana:s=>{s.mana.w=5;},
  'hand counts':s=>{s.handCounts.w=2;},
  'deck counts':s=>{s.deckCounts.w=6;},
  'draw counts':s=>{s.drawCounts.w=4;},
  'used cards':s=>{s.used.w=['shelter'];},
  'discarded cards':s=>{s.discarded.w=['shelter'];},
  'moved pawn rights':s=>{s.movedPawns=['P:8'];},
  'piece identity':s=>{s.pieceIds[0]='promoted-rook';},
  'piece effect':s=>{s.pieceEffects=[{id:'chain',type:'chain',owner:'b',pieceId:'R:0',responseSide:'w',duration:'move'}];},
  'public Mine':s=>{s.boardEffects=[{id:'mine',type:'mine',owner:'b',squares:[21],responseSide:'w',duration:'persistent'}];},
  modifier:s=>{s.modifiers=[{id:'sabotage',type:'mana_sabotage',owner:'b',responseSide:'w',targetCard:'mine',ownTurn:2}];},
  'castling rights':s=>{const fen=s.fen.split(' ');fen[2]='-';s.fen=fen.join(' ');},
  'first-turn phase':s=>{s.phase='chess';s.ownTurns.w=1;}
};
for(const [name,edit] of Object.entries(changes))test(`Luno repetition distinguishes ${name}`,()=>{
  assert.notEqual(publicFingerprint(changed(edit)),publicFingerprint(base));
});

test('public Mine location changes repetition equivalence',()=>{
  const first=changed(changes['public Mine']!);
  const second=changed(s=>{s.boardEffects[0]!.squares=[22];},first);
  assert.notEqual(publicFingerprint(first),publicFingerprint(second));
});

test('absolute counters and repetition history do not change equivalence',()=>{
  const other=changed(s=>{
    const fen=s.fen.split(' ');fen[4]='99';fen[5]='42';s.fen=fen.join(' ');
    s.ownTurns={w:12,b:12};s.ply=82;s.effectSequence=99;s.repetitions={'historical-public-position':4};
  });
  assert.equal(publicFingerprint(other),publicFingerprint(base));
});

test('modifier timing is relative to response side own turn',()=>{
  const modifier=changed(changes.modifier!);
  const shifted=changed(s=>{s.ownTurns={w:12,b:12};s.modifiers[0]!.ownTurn=12;},modifier);
  assert.equal(publicFingerprint(shifted),publicFingerprint(modifier));
  assert.notEqual(publicFingerprint(changed(s=>{s.modifiers[0]!.ownTurn=13;},shifted)),publicFingerprint(modifier));
});

test('EP contributes only when legal under chess and card restrictions',()=>{
  const ep=initial({...fixture('card-mine'),fen:'7k/8/8/3pP3/8/8/8/4K3 w - d6 0 1'}).rules;
  const withoutEp=(s:RuleState):RuleState=>changed(t=>{const fen=t.fen.split(' ');fen[3]='-';t.fen=fen.join(' ');},s);
  assert.notEqual(publicFingerprint(ep),publicFingerprint(withoutEp(ep)));
  const chained=changed(s=>{s.pieceEffects=[{id:'chain',type:'chain',owner:'b',pieceId:'P:36',responseSide:'w',duration:'move'}];},ep);
  assert.equal(publicFingerprint(chained),publicFingerprint(withoutEp(chained)));
});

test('intermediate card resolution cannot record a repetition',()=>{
  assert.throws(()=>publicFingerprint(changed(s=>{s.phase='chess';})),/not-stable-boundary/);
  assert.throws(()=>publicFingerprint(changed(s=>{s.phase='pending';s.pending={card:'prophecy',owner:'w'};})),/not-stable-boundary/);
});

const cardFixtures=fixtures.filter(f=>f.fixtureId.startsWith('card-'));
test('private-order coverage includes all 24 canonical cards',()=>{assert.equal(cardFixtures.length,24);});
for(const f of cardFixtures)test(`${f.fixtureId}: private order is excluded without weakening secrecy`,()=>{
  const original=initial(f),other=clone(original);
  for(const side of ['w','b'] as const){other.hidden.hands[side].reverse();other.hidden.decks[side].reverse();}
  assert.equal(publicFingerprint(other.rules),publicFingerprint(original.rules));
  const viewer=original.rules.fen.split(' ')[1] as Side,enemy=opposite(viewer),opponentOnly=clone(original);
  const handCount=opponentOnly.hidden.hands[enemy].length;
  const cards=[...opponentOnly.hidden.hands[enemy],...opponentOnly.hidden.decks[enemy]].reverse();
  opponentOnly.hidden.hands[enemy]=cards.slice(0,handCount);
  opponentOnly.hidden.decks[enemy]=cards.slice(handCount);
  opponentOnly.hidden.knowledge[enemy]={...emptyKnowledge(),knownUpcomingCards:opponentOnly.hidden.decks[enemy].slice(0,2)};
  const redacted=playerView(opponentOnly,viewer),view=playerView(original,viewer);
  assert.deepEqual(redacted,view);
  assert.deepEqual(legalActions(redacted).map(actionKey),legalActions(view).map(actionKey));
  assert.deepEqual(Object.keys(view).sort(),['knowledge','ownHand','rules','viewer']);
});

test('private knowledge is excluded while legitimate own knowledge stays visible',()=>{
  const original=initial(fixture('card-prophecy')),other=clone(original);
  other.hidden.knowledge.w={...emptyKnowledge(),knownUpcomingCards:other.hidden.decks.w.slice(0,2)};
  assert.equal(publicFingerprint(other.rules),publicFingerprint(original.rules));
  assert.deepEqual(playerView(other,'w').knowledge.knownUpcomingCards,other.hidden.decks.w.slice(0,2));
  assert.deepEqual(playerView(other,'b'),playerView(original,'b'));
});

test('canonical finite-deck fivefold remains automatic after authority restoration',()=>{
  const f=fixture('finite-deck-fivefold');let state=initial(f);
  for(const step of f.steps){
    if(!step.action)continue;
    state=JSON.parse(JSON.stringify(state)) as typeof state;
    const before=state;state=applyAuthoritative(state,step.action);
    if(state.rules.terminal){
      assert.deepEqual(state.rules.drawCounts,before.rules.drawCounts);
      assert.deepEqual(state.rules.handCounts,before.rules.handCounts);
    }
  }
  assert.deepEqual(state,runFixture(f));
  assert.equal(state.rules.terminal!.reason,'fivefold');
  assert.deepEqual(state.rules.deckCounts,{w:0,b:0});
  for(const viewer of ['w','b'] as const)assert.deepEqual(legalActions(playerView(state,viewer)),[]);
});
