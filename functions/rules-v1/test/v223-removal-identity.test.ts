import test from 'node:test';
import assert from 'node:assert/strict';
import {newBattle, playerView, applyAuthoritative} from '../src/authoritative';
import {cardTargets, legalActions} from '../src/core';
import {CARDS, clone, CardId, Side, opposite} from '../src/model';

for (const card of ['purify', 'break_seal'] as const) {
  for (const side of ['w', 'b'] as const) {
    test(`${card}/${side}: ambiguous effect identity rejects without spending`, () => {
      const deck: CardId[] = [card, ...(Object.keys(CARDS) as CardId[]).filter(c => c !== card).slice(0, 9)];
      const state = clone(newBattle(deck, deck));
      state.rules.fen = state.rules.fen.replace(' w ', ` ${side} `);
      state.rules.phase = 'card';
      state.rules.ownTurns = {w: 2, b: 2};
      state.rules.mana = {w: 6, b: 6};
      const enemy: Side = opposite(side);
      const ownId = state.rules.pieceIds[side === 'w' ? 12 : 52]!;
      const enemyId = state.rules.pieceIds[side === 'w' ? 52 : 12]!;
      if (card === 'purify') {
        state.rules.pieceEffects = [
          {id: 'unique', type: 'chain', owner: enemy, pieceId: ownId, responseSide: side, duration: 'move'},
          {id: 'collision', type: 'freeze', owner: enemy, pieceId: ownId, responseSide: side, duration: 'move'},
          {id: 'collision', type: 'shelter', owner: side, pieceId: ownId, responseSide: enemy, duration: 'card'},
          {id: 'collision', type: 'chain', owner: side, pieceId: enemyId, responseSide: enemy, duration: 'move'},
        ];
      } else {
        state.rules.boardEffects = [
          {id: 'unique', type: 'mine', owner: enemy, squares: [26], responseSide: side, duration: 'persistent'},
          {id: 'collision', type: 'mine', owner: enemy, squares: [18], responseSide: side, duration: 'persistent'},
          {id: 'collision', type: 'locked_square', owner: enemy, squares: [19], responseSide: side, duration: 'move'},
          {id: 'collision', type: 'mine', owner: side, squares: [20], responseSide: enemy, duration: 'persistent'},
        ];
      }
      const frozen = JSON.stringify(state);
      const view = playerView(state, side);
      assert.deepEqual(cardTargets(view, card), ['unique']);
      assert.throws(() => applyAuthoritative(state, {type: 'play', card, target: 'collision'}), /illegal-action/);
      assert.equal(JSON.stringify(state), frozen);
      assert.ok(legalActions(view).some(a => a.type === 'pass'));
      assert.ok(legalActions(view).some(a => a.type === 'discard' && a.card === card));
      const valid = applyAuthoritative(state, {type: 'play', card, target: 'unique'});
      const survivors = card === 'purify' ? valid.rules.pieceEffects : valid.rules.boardEffects;
      assert.equal(survivors.length, 3);
      assert.ok(survivors.every(effect => effect.id === 'collision'));
      assert.equal(valid.rules.mana[side], 6 - CARDS[card].cost);
    });
  }
}
