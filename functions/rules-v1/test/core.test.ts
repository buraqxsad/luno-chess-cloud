import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {newBattle,playerView,applyAuthoritative} from '../src/authoritative.js';
import {legalActions,legalRuleMoves,specialMoves,cardTargets,effectiveCost,chooseBotAction,publicFingerprint} from '../src/core.js';
import {STARTER,CARDS,clone,actionKey,type AuthoritativeBattleState,type CardId,type Action,type Side,type BoardEffect,type PieceEffect} from '../src/model.js';

function ready(cards:CardId[],fen?:string):AuthoritativeBattleState {
  const deck=[...cards,...Object.keys(CARDS).map(c=>c as CardId).filter(c=>!cards.includes(c))].slice(0,10);
  const s=clone(newBattle(deck,STARTER,fen));s.rules.ownTurns={w:2,b:2};s.rules.phase='card';s.rules.mana={w:6,b:6};s.rules.repetitions={};return s;
}
function has(s:AuthoritativeBattleState,a:Action,side:Side='w'):boolean{return legalActions(playerView(s,side)).some(x=>actionKey(x)===actionKey(a));}
function move(s:AuthoritativeBattleState,uci:string):AuthoritativeBattleState{return applyAuthoritative(s,{type:'move',uci});}
function pass(s:AuthoritativeBattleState):AuthoritativeBattleState{return applyAuthoritative(s,{type:'pass'});}
function pe(s:AuthoritativeBattleState,type:PieceEffect['type'],square:number,owner:Side='b',duration:PieceEffect['duration']='move'):void {
  s.rules.pieceEffects.push({id:'test-'+type,type,pieceId:s.rules.pieceIds[square]!,owner,responseSide:owner==='w'?'b':'w',duration});
}
function be(s:AuthoritativeBattleState,type:BoardEffect['type'],sq:number[],owner:Side='b',duration:BoardEffect['duration']='move'):void {
  s.rules.boardEffects.push({id:'test-'+type,type,squares:sq,owner,responseSide:owner==='w'?'b':'w',duration});
}
test('manifest and canonical starter exactly match manually authored contract',()=> {
  const contract=JSON.parse(readFileSync(resolve(__dirname,'../../../../battle_contract/v1/cards.json'),'utf8'));
  assert.deepEqual(Object.values(CARDS),contract.cards);assert.deepEqual(STARTER,contract.starter);assert.equal(Object.keys(CARDS).length,24);
});
test('deck validation: length, uniqueness, unknown ID',()=> {
  assert.throws(()=>newBattle(STARTER.slice(1),STARTER),/invalid-deck/);
  assert.throws(()=>newBattle([...STARTER.slice(1),STARTER[1]!],STARTER),/invalid-deck/);
  assert.throws(()=>newBattle([...STARTER.slice(1),'unknown' as CardId],STARTER),/invalid-deck/);
});
test('first own turns chess only, both mana 1, one draw to four, second own mana increment',()=> {
  let s=newBattle(STARTER,STARTER);assert.deepEqual(s.rules.mana,{w:1,b:1});
  assert.ok(legalActions(playerView(s,'w')).every(a=>a.type==='move'));
  for(const a of [{type:'pass'},{type:'play',card:'radar',target:'radar'},{type:'discard',card:'radar'}] as Action[])assert.throws(()=>applyAuthoritative(s,a),/illegal-action/);
  s=move(s,'e2e4');assert.deepEqual(s.rules.handCounts,{w:4,b:3});assert.deepEqual(s.rules.mana,{w:1,b:1});
  s=move(s,'e7e5');assert.equal(s.rules.phase,'card');assert.deepEqual(s.rules.mana,{w:2,b:1});
  assert.equal(s.rules.deckCounts.w,6);
});
test('one action; discard permanent/free; card does not increment halfmove; no recycle',()=> {
  const s=ready(['radar','prophecy','shelter']);const before=JSON.stringify(s);
  const d=applyAuthoritative(s,{type:'discard',card:'radar'});
  assert.equal(d.rules.mana.w,6);assert.deepEqual(d.rules.discarded.w,['radar']);assert.equal(d.rules.fen,s.rules.fen);
  assert.throws(()=>applyAuthoritative(d,{type:'pass'}),/illegal-action/);assert.equal(JSON.stringify(s),before);
  const after=move(d,'e2e4');assert.equal(after.rules.handCounts.w,3);assert.equal(after.hidden.decks.w.includes('radar'),false);
});
test('insufficient mana and illegal target atomic',()=> {
  const s=ready(['freeze']);s.rules.mana.w=3;const before=JSON.stringify(s);
  assert.throws(()=>applyAuthoritative(s,{type:'play',card:'freeze',target:48}),/illegal-action/);
  assert.throws(()=>applyAuthoritative(s,{type:'play',card:'freeze',target:60}),/illegal-action/);assert.equal(JSON.stringify(s),before);
});
for(const [card,fen,from,to] of [
  ['pawn_deviation','7k/8/8/8/8/4P3/8/4K3 w - - 0 1',20,'e3d4'],
  ['pawn_advance','7k/8/8/8/8/4P3/8/4K3 w - - 0 1',20,'e3e5'],
  ['rook_bend','7k/8/8/8/8/8/8/R3K3 w Q - 0 1',0,'a1b2'],
  ['angry_n','7k/8/8/8/8/8/8/1N2K3 w - - 0 1',1,'b1b2'],
  ['shadow_pass','7k/8/8/8/8/P7/8/R3K3 w Q - 0 1',0,'a1a4']
] as const)test(`${card} binding, only special destinations, different piece rejected`,()=> {
  const s=ready([card],fen),after=applyAuthoritative(s,{type:'play',card,target:from});
  assert.ok(after.rules.special);assert.ok(legalActions(playerView(after,'w')).every(a=>a.type==='move'&&a.uci.startsWith(to.slice(0,2))));
  assert.throws(()=>move(after,'e1d1'),/illegal-action/);assert.throws(()=>move(after,'e1f1'),/illegal-action/);assert.ok(has(after,{type:'move',uci:to}));
  const moved=move(after,to);assert.equal(moved.rules.special,null);assert.equal(moved.rules.fen.split(' ')[3],'-');
  if(card==='rook_bend'||card==='shadow_pass')assert.equal(moved.rules.fen.split(' ')[2],'-');
});
test('special pawn standard double creates EP; moved pawn double does not',()=> {
  let s=ready(['pawn_advance']);s=applyAuthoritative(s,{type:'play',card:'pawn_advance',target:12});s=move(s,'e2e4');assert.equal(s.rules.fen.split(' ')[3],'e3');
  let t=ready(['pawn_advance'],'7k/8/8/8/8/4P3/8/4K3 w - - 23 1');t=applyAuthoritative(t,{type:'play',card:'pawn_advance',target:20});t=move(t,'e3e5');assert.equal(t.rules.fen.split(' ')[3],'-');assert.equal(t.rules.fen.split(' ')[4],'0');
});
test('special king safety; pinned pawn cannot deviate; no promotion special advance',()=> {
  const s=ready(['pawn_deviation'],'k3r3/8/8/8/8/8/4P3/4K3 w - - 0 1');assert.deepEqual(specialMoves(s.rules,'pawn_deviation',12,'w'),[]);
  const t=ready(['pawn_advance'],'7k/4P3/8/8/8/8/8/4K3 w - - 0 1');assert.deepEqual(specialMoves(t.rules,'pawn_advance',52,'w'),[]);
});
test('nonmovement can play in check but chess must resolve check',()=> {
  const s=ready(['radar'],'k3r3/8/8/8/8/8/3P4/4K3 w - - 0 1');const t=applyAuthoritative(s,{type:'play',card:'radar',target:'radar'});
  assert.throws(()=>move(t,'d2d3'),/illegal-action/);assert.ok(has(t,{type:'move',uci:'e1d1'}));
});
test('king direct targets excluded; chain capture forbidden, slow max2, frozen movement forbidden',()=> {
  for(const card of ['freeze','chain','slow','hunt_vow'] as const){const s=ready([card]);assert.equal(cardTargets(playerView(s,'w'),card).includes(60),false);}
  const fen='7k/8/8/8/8/8/p7/R3K3 w - - 0 1';const s=ready(['radar'],fen);pe(s,'chain',0);s.rules.phase='chess';
  assert.equal(has(s,{type:'move',uci:'a1a2'}),false);assert.equal(has(s,{type:'move',uci:'a1b1'}),true);
  const t=ready(['radar'],'7k/8/8/8/8/8/8/R3K3 w - - 0 1');pe(t,'slow',0);t.rules.phase='chess';assert.equal(has(t,{type:'move',uci:'a1a3'}),true);assert.equal(has(t,{type:'move',uci:'a1a4'}),false);
  pe(t,'freeze',0);assert.ok(legalActions(playerView(t,'w')).every(a=>a.type!=='move'||!a.uci.startsWith('a1')));
});
test('other-piece chess move consumes response-window freeze/chain/slow',()=> {
  const s=ready(['radar']);pe(s,'freeze',0);pe(s,'chain',1);pe(s,'slow',3);s.rules.phase='chess';const t=move(s,'e2e4');assert.equal(t.rules.pieceEffects.length,0);
});
for(const boardType of ['locked_square','board_seal'] as const)test(`${boardType}: empty blocked, occupied capture allowed, king immune, EP blocked`,()=> {
  const s=ready(['radar'],'7k/8/8/8/8/8/p7/R3K3 w - - 0 1');be(s,boardType,[8,1,5]);s.rules.phase='chess';
  assert.equal(has(s,{type:'move',uci:'a1a2'}),true);assert.equal(has(s,{type:'move',uci:'a1b1'}),false);assert.equal(has(s,{type:'move',uci:'e1f1'}),true);
  const ep=ready(['radar'],'7k/8/8/3pP3/8/8/8/4K3 w - d6 0 1');be(ep,boardType,[43]);ep.rules.phase='chess';assert.equal(has(ep,{type:'move',uci:'e5d6'}),false);
  const promo=ready(['radar'],'k6r/6P1/8/8/8/8/8/4K3 w - - 0 1');be(promo,boardType,[62,63]);promo.rules.phase='chess';assert.equal(has(promo,{type:'move',uci:'g7g8q'}),false);assert.equal(has(promo,{type:'move',uci:'g7h8n'}),true);
});
test('castling: frozen rook illegal; slow short legal/long illegal; rook zone blocks, king zone does not',()=> {
  const fen='4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1';
  const s=ready(['radar'],fen);s.rules.phase='chess';pe(s,'slow',7);pe(s,'slow',0);
  assert.equal(has(s,{type:'move',uci:'e1g1'}),true);assert.equal(has(s,{type:'move',uci:'e1c1'}),false);
  pe(s,'freeze',7);assert.equal(has(s,{type:'move',uci:'e1g1'}),false);
  const t=ready(['radar'],fen);t.rules.phase='chess';be(t,'locked_square',[6]);assert.equal(has(t,{type:'move',uci:'e1g1'}),true);be(t,'board_seal',[5]);assert.equal(has(t,{type:'move',uci:'e1g1'}),false);
});
test('Mine + watch simultaneous on castling rook; debuff new move does not consume; king immune',()=> {
  const s=ready(['radar'],'4k3/8/8/8/8/8/8/4K2R w K - 0 1');be(s,'mine',[5],'b','persistent');s.rules.vows.push({id:'v',type:'watch',owner:'b',pieceId:null,square:5,remainingMoves:1});s.rules.mana.b=1;s.rules.phase='chess';
  const t=move(s,'e1g1');assert.equal(t.rules.boardEffects.length,0);assert.equal(t.rules.pieceEffects[0]!.type,'mine_debuff');assert.equal(t.rules.mana.b,4);assert.equal(t.rules.vows.length,0);
  const king=ready(['radar'],'7k/8/8/8/8/8/8/4K3 w - - 0 1');be(king,'mine',[5],'b','persistent');king.rules.phase='chess';const k=move(king,'e1f1');assert.equal(k.rules.boardEffects.length,1);assert.equal(k.rules.pieceEffects.length,0);
});
test('persistent Mine debuff survives other-piece move; blocks capture, ends on affected-piece move',()=> {
  const s=ready(['radar'],'7k/8/8/8/8/8/p7/R3K3 w - - 0 1');pe(s,'mine_debuff',0,'b','piece_move');s.rules.phase='chess';
  assert.equal(has(s,{type:'move',uci:'a1a2'}),false);
  let t=move(s,'e1f1');assert.equal(t.rules.pieceEffects.length,1);t=move(pass(t),'h8g8');t=move(pass(t),'a1b1');assert.equal(t.rules.pieceEffects.length,0);
});
test('overlapping removal: opponent-only, one instance, Mine slot remains occupied',()=> {
  const s=ready(['break_seal','mine']);be(s,'mine',[20],'w','persistent');be(s,'locked_square',[20],'b');be(s,'board_seal',[20,21,28,29],'b');
  assert.equal(cardTargets(playerView(s,'w'),'break_seal').includes('test-mine'),false);assert.equal(cardTargets(playerView(s,'w'),'mine').length,0);
  const t=applyAuthoritative(s,{type:'play',card:'break_seal',target:'test-locked_square'});assert.equal(t.rules.boardEffects.length,2);assert.ok(t.rules.boardEffects.some(e=>e.type==='mine'));assert.ok(t.rules.boardEffects.some(e=>e.type==='board_seal'));
});
test('Siper/Sis protect direct cards, not normal capture; purify only one negative own-piece effect',()=> {
  const s=ready(['freeze','hunt_vow'],'7k/8/8/8/8/8/p7/R3K3 w - - 0 1');pe(s,'shelter',8,'b','card');assert.equal(cardTargets(playerView(s,'w'),'freeze').includes(8),false);s.rules.phase='chess';assert.equal(has(s,{type:'move',uci:'a1a2'}),true);
  const t=ready(['purify']);pe(t,'chain',0);pe(t,'slow',0);const u=applyAuthoritative(t,{type:'play',card:'purify',target:'test-chain'});assert.equal(u.rules.pieceEffects.length,1);
  const fog=ready(['freeze']);be(fog,'fog',[48,49,56,57],'b','card');assert.equal(cardTargets(playerView(fog,'w'),'freeze').includes(48),false);
});
test('Radar public target legality independent of opponent hand, private positive/negative and staleness',()=> {
  const s=ready(['radar']);const positive=applyAuthoritative(s,{type:'play',card:'radar',target:'radar'});assert.equal(positive.hidden.knowledge.w.radarObservations[0]!.result,'IN_HAND');assert.equal(playerView(positive,'b').knowledge.radarObservations.length,0);
  let negative=applyAuthoritative(s,{type:'play',card:'radar',target:'purify'});assert.equal(negative.hidden.knowledge.w.radarObservations[0]!.result,'NOT_IN_HAND');negative=move(negative,'e2e4');negative=move(pass(negative),'e7e5');assert.equal(negative.hidden.knowledge.w.radarObservations[0]!.stale,true);
});
test('Kehanet inspects <=2, blocks unrelated, reorder no immediate draw, knowledge shifts',()=> {
  let s=ready(['prophecy']);s=applyAuthoritative(s,{type:'play',card:'prophecy'});assert.equal(s.rules.phase,'pending');assert.equal(s.hidden.knowledge.w.pendingCards.length,2);
  assert.throws(()=>move(s,'e2e4'),/illegal-action/);assert.throws(()=>pass(s),/illegal-action/);const ordered=[...s.hidden.knowledge.w.pendingCards].reverse();s=applyAuthoritative(s,{type:'resolve',order:ordered});assert.equal(s.rules.handCounts.w,2);assert.deepEqual(s.hidden.knowledge.w.knownUpcomingCards,ordered);s=move(s,'e2e4');assert.equal(s.hidden.hands.w.at(-1),ordered[0]);assert.deepEqual(s.hidden.knowledge.w.knownUpcomingCards,ordered.slice(1));
});
test('Kader Takasi sacrifice, inspect max3, choose1, remaining order, later normal draw',()=> {
  let s=ready(['fate_exchange','radar']);s=applyAuthoritative(s,{type:'play',card:'fate_exchange',sacrifice:'radar'});const inspected=s.hidden.knowledge.w.pendingCards;assert.equal(inspected.length,3);const selected=inspected[1]!,order=[inspected[2]!,inspected[0]!];s=applyAuthoritative(s,{type:'resolve',selected,order});assert.equal(s.hidden.hands.w.includes(selected),true);assert.deepEqual(s.rules.discarded.w,['radar']);assert.deepEqual(s.hidden.decks.w.slice(0,2),order);const d=s.rules.drawCounts.w;s=move(s,'e2e4');assert.equal(s.rules.drawCounts.w,d+1);
});
test('Antlasma next-turn discount, min1, sabotage combination, PASS/DISCARD expiry',()=> {
  const s=ready(['freeze','radar']);s.rules.modifiers=[{id:'d',type:'discount',owner:'w',responseSide:'w',targetCard:null,ownTurn:2},{id:'s',type:'mana_sabotage',owner:'b',responseSide:'w',targetCard:'freeze',ownTurn:2}];assert.equal(effectiveCost(s.rules,'w','freeze'),3);assert.equal(effectiveCost(s.rules,'w','radar'),1);
  const t=applyAuthoritative(s,{type:'discard',card:'radar'});assert.equal(t.rules.modifiers.length,0);assert.equal(t.rules.mana.w,6);
  const c=ready(['shadow_contract','radar']);const d=applyAuthoritative(c,{type:'play',card:'shadow_contract',sacrifice:'radar'});assert.equal(d.rules.modifiers[0]!.ownTurn,3);assert.equal(d.rules.mana.w,5);
});
test('Mana sabotage cost5->6, card block PLAY only, echo exact play not discard',()=> {
  const s=ready(['board_seal','radar']);s.rules.modifiers=[{id:'s',type:'mana_sabotage',owner:'b',responseSide:'w',targetCard:'board_seal',ownTurn:2},{id:'l',type:'card_block',owner:'b',responseSide:'w',targetCard:'radar',ownTurn:2},{id:'e',type:'echo',owner:'b',responseSide:'w',targetCard:'radar',ownTurn:2}];assert.equal(effectiveCost(s.rules,'w','board_seal'),6);assert.equal(has(s,{type:'play',card:'radar',target:'radar'}),false);assert.equal(has(s,{type:'discard',card:'radar'}),true);
  s.rules.mana.b=1;const d=applyAuthoritative(s,{type:'discard',card:'radar'});assert.equal(d.rules.mana.b,1);
  s.rules.modifiers=s.rules.modifiers.filter(m=>m.type!=='card_block');const p=applyAuthoritative(s,{type:'play',card:'radar',target:'radar'});assert.equal(p.rules.mana.b,3);
});
test('Hunt normal capture reward, special capture no reward; expiry two own moves',()=> {
  const s=ready(['hunt_vow'],'7k/8/8/8/8/8/p7/R3K3 w - - 0 1');let t=applyAuthoritative(s,{type:'play',card:'hunt_vow',target:8});t=move(t,'a1a2');assert.equal(t.rules.mana.w,6);assert.equal(t.rules.vows.length,0);
  const a=ready(['angry_n'],'7k/8/8/8/8/8/1p6/1N2K3 w - - 0 1');a.rules.vows=[{id:'v',type:'hunt',owner:'w',pieceId:a.rules.pieceIds[9]!,square:null,remainingMoves:2}];let u=applyAuthoritative(a,{type:'play',card:'angry_n',target:1});u=move(u,'b1b2');assert.equal(u.rules.mana.w,3);assert.equal(u.rules.vows.length,0);
});
test('terminal after chess move only; checkmate/stalemate prevent draw',()=> {
  const s=ready(['radar'],'7k/8/5KQ1/8/8/8/8/8 w - - 0 1');let t=applyAuthoritative(s,{type:'play',card:'radar',target:'radar'});assert.equal(t.rules.terminal,null);const count=t.rules.drawCounts.w;t=move(t,'g6g7');assert.equal(t.rules.terminal!.reason,'checkmate');assert.equal(t.rules.drawCounts.w,count);
  const stale=ready(['radar'],'7k/5K2/8/6Q1/8/8/8/8 w - - 0 1');const v=move(pass(stale),'g5g6');assert.equal(v.rules.terminal!.reason,'stalemate');assert.equal(v.rules.drawCounts.w,3);
});
test('redacted view has no decks/opponent hand/private knowledge; authority immutable; bot always legal',()=> {
  let s=newBattle(STARTER,STARTER);for(let i=0;i<40&&s.rules.phase!=='terminal';i++){
    const side=s.rules.fen.split(' ')[1] as Side,v=playerView(s,side),before=JSON.stringify(s);const a=chooseBotAction(v);assert.ok(a);assert.ok(has(s,a,side));s=applyAuthoritative(s,a);assert.equal(JSON.stringify(v).includes('"decks"'),false);assert.equal(Object.hasOwn(v,'opponentHand'),false);assert.notEqual(JSON.stringify(s),before);
  }
  const frozen=newBattle(STARTER,STARTER);assert.throws(()=>frozen.hidden.decks.w.push('radar'));assert.throws(()=>frozen.rules.mana.w=6);
});
test('stable public fingerprint excludes hidden/private state and intermediate choices',()=> {
  const s=ready(['prophecy']);const v=playerView(s,'w');assert.equal(publicFingerprint(v.rules),publicFingerprint(s.rules));const pending=applyAuthoritative(s,{type:'play',card:'prophecy'});assert.throws(()=>publicFingerprint(pending.rules),/not-stable-boundary/);
  assert.throws(()=>publicFingerprint(pass(s).rules),/not-stable-boundary/);
});

for(const card of Object.keys(CARDS) as CardId[])test(`${card} successful rule resolution`,()=> {
  let s=ready([card],'4k3/1p2r3/8/8/3p4/2P1B3/PP1N4/R3K2R w KQ - 0 1');
  if(card==='purify')pe(s,'chain',0);
  if(card==='break_seal')be(s,'mine',[20],'b','persistent');
  const actions=legalActions(playerView(s,'w')).filter(a=>a.type==='play'&&a.card===card);
  assert.ok(actions.length,card);s=applyAuthoritative(s,actions[0]!);
  assert.ok(s.rules.used.w.includes(card));
  if(s.rules.phase==='pending')s=applyAuthoritative(s,legalActions(playerView(s,'w'))[0]!);
  assert.equal(s.rules.phase,'chess');assert.equal(s.rules.pending,null);
});

test('deck exhaustion: prophecy/fate unavailable at zero; one inspected card is sufficient',()=> {
  for(const count of [0,1,2])for(const card of ['prophecy','fate_exchange'] as const){
    let s=ready([card,'radar']);const removed=s.hidden.decks.w.splice(count);
    s.rules.deckCounts.w=count;s.rules.discarded.w.push(...removed);s.rules.discarded.w.sort();
    const plays=legalActions(playerView(s,'w')).filter(a=>a.type==='play'&&a.card===card);
    assert.equal(plays.length>0,count>0);
    if(count){s=applyAuthoritative(s,plays[0]!);assert.equal(s.hidden.knowledge.w.pendingCards.length,count);
      s=applyAuthoritative(s,legalActions(playerView(s,'w'))[0]!);assert.equal(s.rules.phase,'chess');}
  }
});

test('positive Radar remains until public use/discard, independent of later draws',()=> {
  let s=applyAuthoritative(ready(['radar']),{type:'play',card:'radar',target:'radar'});
  s=move(s,'e2e4');s=move(pass(s),'e7e5');assert.equal(s.hidden.knowledge.w.radarObservations[0]!.stale,false);
  s=move(pass(s),'g1f3');s=applyAuthoritative(s,{type:'discard',card:'radar'});
  assert.equal(s.hidden.knowledge.w.radarObservations[0]!.stale,true);
});

test('restriction-assisted mate and stalemate require a genuine lost defense',()=> {
  const a=ready(['freeze'],'7k/r7/5KQ1/8/8/8/8/8 w - - 0 1');
  const mate=move(applyAuthoritative(a,{type:'play',card:'freeze',target:48}),'g6g7');
  assert.equal(mate.rules.terminal?.mateByRestriction,true);assert.equal(mate.rules.terminal?.mateBySpecialMove,false);
  const ordinary=move(pass(a),'g6g7');assert.equal(ordinary.rules.terminal,null);
  const c=ready(['freeze'],'r6k/5K2/8/6Q1/8/8/8/8 w - - 0 1');
  const stale=move(applyAuthoritative(c,{type:'play',card:'freeze',target:56}),'g5g6');
  assert.equal(stale.rules.terminal?.stalemateByRestriction,true);assert.equal(stale.rules.terminal?.reason,'stalemate');
});

test('king and enemy blockers cannot be crossed by Shadow Pass; special captures never take kings',()=> {
  for(const blocker of ['K','p']){
    const s=ready(['shadow_pass'],`7k/8/8/8/8/${blocker}7/8/R${blocker==='K'?'7':'3K3'} w - - 0 1`);
    assert.deepEqual(specialMoves(s.rules,'shadow_pass',0,'w'),[]);
  }
  const n=ready(['angry_n'],'8/8/8/8/8/8/1k6/1N2K3 w - - 0 1');
  assert.equal(specialMoves(n.rules,'angry_n',1,'w').some(m=>m.uci==='b1b2'),false);
});

test('malformed private reveals are rejected before permutation generation',()=> {
  const s=applyAuthoritative(ready(['prophecy']),{type:'play',card:'prophecy'}),v=clone(playerView(s,'w'));
  v.knowledge.pendingCards=[...s.hidden.decks.w];assert.throws(()=>legalActions(v),/invalid-player-knowledge/);
  v.knowledge.pendingCards=[];assert.throws(()=>legalActions(v),/invalid-player-knowledge/);
});
test('terminal initial FENs cannot start a fresh action phase',()=> {
  for(const [fen,reason]of [['7k/6Q1/5K2/8/8/8/8/8 b - - 0 1','checkmate'],['7k/5K2/6Q1/8/8/8/8/8 b - - 0 1','stalemate'],['7k/8/8/8/8/8/8/R3K3 w - - 150 1','seventy_five_moves']]){
    const s=newBattle(STARTER,STARTER,fen);assert.equal(s.rules.terminal?.reason,reason);assert.deepEqual(legalActions(playerView(s,s.rules.fen.split(' ')[1] as Side)),[]);
  }
});
test('invalid initial boards rejected at the authority boundary',()=> {
  for(const fen of ['7k/8/8/8/8/8/8/8 w - - 0 1','7k/8/8/8/8/8/8/P3K3 w - - 0 1'])assert.throws(()=>newBattle(STARTER,STARTER,fen));
});
test('finite deck exhaustion never recycles and stable fivefold ends without drawing',()=> {
  let s=newBattle(STARTER,STARTER,'6nk/8/8/8/8/8/8/KN6 w - - 0 1'),ply=0;
  while(s.rules.phase!=='terminal'&&ply<60){const side=s.rules.fen.split(' ')[1] as Side;
    if(s.rules.phase==='card')s=applyAuthoritative(s,s.hidden.hands[side].length?{type:'discard',card:s.hidden.hands[side][0]!}:{type:'pass'});
    s=move(s,['b1c3','g8f6','c3b1','f6g8'][ply++%4]!);
  }
  assert.equal(s.rules.terminal?.reason,'fivefold');assert.deepEqual(s.rules.drawCounts,{w:10,b:10});assert.deepEqual(s.rules.deckCounts,{w:0,b:0});assert.deepEqual(s.hidden.decks,{w:[],b:[]});
});
test('canonical bot tie breaking uses fixed character order, not locale collation',()=> {
  const a=chooseBotAction(playerView(ready(['locked_square'], '4k3/1p2r3/8/8/3p4/2P1B3/PP1N4/R3K2R w KQ - 0 1'),'w'));
  assert.equal(actionKey(a!),'play:locked_square:10:');
});
