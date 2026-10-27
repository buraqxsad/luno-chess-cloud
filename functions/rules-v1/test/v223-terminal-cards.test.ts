import test from 'node:test';
import assert from 'node:assert/strict';
import {newBattle, playerView, applyAuthoritative} from '../src/authoritative.js';
import {legalActions} from '../src/core.js';
import {CARDS, clone, type CardId, type Side} from '../src/model.js';
import {commitAction, createServerMatch, expireClock, finishMatch} from '../src/online/authority.js';
import {PROTOCOL, type ActionRequest, type ServerMatch} from '../src/online/protocol.js';

function deck(first: CardId): CardId[] {
  return [first, ...Object.keys(CARDS).filter(c => c !== first) as CardId[]].slice(0, 10);
}

function ready(side: Side, card: CardId): ServerMatch {
  const cards = deck(card);
  const match = createServerMatch('bv1_' + 'a'.repeat(32),
    {uid: 'alice', name: 'Alice', bot: false},
    {uid: 'bob', name: 'Bob', bot: false}, cards, cards, 1000);
  match.battle = clone(newBattle(cards, cards,
    `4k3/pp3ppp/8/8/8/8/PP3PPP/4K3 ${side} - - 0 10`));
  match.battle.rules.phase = 'card';
  match.battle.rules.ownTurns = {w: 2, b: 2};
  match.battle.rules.mana = {w: 6, b: 6};
  match.clock.activeSide = side;
  return match;
}

function request(match: ServerMatch, intent: ActionRequest['intent']): ActionRequest {
  return {protocolVersion: PROTOCOL, matchId: match.matchId,
    expectedStateVersion: match.stateVersion,
    actionId: `a${match.stateVersion}_terminal-card-regression`, intent};
}

for (const side of ['w', 'b'] as const) {
  const uid = side === 'w' ? 'alice' : 'bob', enemy = side === 'w' ? 'b' : 'w';
  for (const card of ['prophecy', 'fate_exchange'] as const) {
    for (const ending of ['timeout', 'resign'] as const) {
      test(`${side}/${card}/${ending}: abandon only unresolved private choice`, () => {
        const initial = ready(side, card);
        const cast = request(initial, {type: 'play', card,
          ...(card === 'fate_exchange' ? {sacrifice: initial.battle.hidden.hands[side][1]!} : {})});
        const pending = commitAction(initial, uid, cast, 2000).match;
        const saved = clone(pending);
        assert.ok(pending.battle.hidden.knowledge[side].pendingCards.length > 0);
        const ended = ending === 'timeout'
          ? expireClock(pending, 301000)
          : finishMatch(pending, {reason: 'resign', winner: enemy, finishedAt: 5000});
        assert.deepEqual(pending, saved, 'termination must not mutate its input');
        assert.equal(ended.battle.rules.phase, 'terminal');
        assert.equal(ended.battle.rules.pending, null);
        for (const viewer of ['w', 'b'] as const) {
          assert.deepEqual(ended.battle.hidden.knowledge[viewer].pendingCards, []);
          assert.deepEqual(legalActions(playerView(ended.battle, viewer)), []);
          assert.deepEqual(ended.battle.hidden.knowledge[viewer].knownUpcomingCards,
            saved.battle.hidden.knowledge[viewer].knownUpcomingCards);
          assert.deepEqual(ended.battle.hidden.knowledge[viewer].radarObservations,
            saved.battle.hidden.knowledge[viewer].radarObservations);
        }
        for (const key of ['hands', 'decks'] as const) {
          assert.deepEqual(ended.battle.hidden[key], saved.battle.hidden[key]);
        }
        for (const key of ['mana', 'drawCounts', 'used', 'discarded', 'handCounts', 'deckCounts'] as const) {
          assert.deepEqual(ended.battle.rules[key], saved.battle.rules[key]);
        }
        const retried = commitAction(ended, uid, cast, 400000);
        assert.equal(retried.duplicate, true);
        assert.deepEqual(retried.match, ended);
        assert.throws(() => commitAction(ended, uid,
          request(ended, {type: 'resolve', order: []}), 400000));
        assert.equal(expireClock(ended, 500000), ended);
        assert.deepEqual(finishMatch(ended,
          {reason: 'resign', winner: side, finishedAt: 500000}), ended);
      });
    }
  }

  for (const restriction of [null, 'chain', 'mine_debuff'] as const) {
    test(`${side}/pawn_deviation/${restriction}: quiet EP alias is a special mate`, () => {
      const cards = deck('pawn_deviation');
      const fen = side === 'w'
        ? 'B6R/2k5/4B3/2KpP3/3r4/8/8/8 w - d6 0 10'
        : '8/8/8/4R3/3pPk2/3b4/5K2/r6b b - e3 0 10';
      const state = clone(newBattle(cards, cards, fen));
      state.rules.phase = 'card';
      state.rules.ownTurns = {w: 2, b: 2};
      state.rules.mana = {w: 6, b: 6};
      const from = side === 'w' ? 36 : 27, remainingPawn = side === 'w' ? 35 : 28;
      if (restriction) state.rules.pieceEffects.push({id: 'old-restriction',
        type: restriction, owner: enemy, responseSide: side,
        pieceId: state.rules.pieceIds[from]!,
        duration: restriction === 'chain' ? 'move' : 'piece_move'});
      const cast = applyAuthoritative(state, {type: 'play', card: 'pawn_deviation', target: from});
      const moved = applyAuthoritative(cast,
        {type: 'move', uci: side === 'w' ? 'e5d6' : 'd4e3'});
      assert.equal(moved.rules.pieceIds[remainingPawn], state.rules.pieceIds[remainingPawn]);
      assert.equal(moved.rules.terminal?.reason, 'checkmate');
      assert.equal(moved.rules.terminal?.winner, side);
      assert.equal(moved.rules.terminal?.mateBySpecialMove, true);
      assert.equal(moved.rules.drawCounts[side], state.rules.drawCounts[side]);
      assert.equal(moved.rules.phase, 'terminal');
    });
  }
}
