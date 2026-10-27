import {Chess} from 'chess.js';
import {squares} from './board.js';
import {initializeTerminal,transition} from './core.js';
import {clone,emptyKnowledge,freeze,validateDeck,opposite,type Action,type AuthoritativeBattleState,type CardId,type PlayerView,type RuleState,type Side} from './model.js';

export function newBattle(white:readonly CardId[],black:readonly CardId[],fen=new Chess().fen()):AuthoritativeBattleState {
  validateDeck(white);validateDeck(black);new Chess(fen);
  const side=fen.split(' ')[1] as Side;
  const state:RuleState={fen,pieceIds:squares(fen).map((p,i)=>p?`${p}:${i}`:null),movedPawns:[],phase:'chess',
    mana:{w:1,b:1},ownTurns:{w:side==='w'?1:0,b:side==='b'?1:0},handCounts:{w:3,b:3},deckCounts:{w:7,b:7},drawCounts:{w:3,b:3},
    arsenals:{w:[...white].sort(),b:[...black].sort()},used:{w:[],b:[]},discarded:{w:[],b:[]},
    pieceEffects:[],boardEffects:[],modifiers:[],vows:[],special:null,pending:null,terminal:null,effectSequence:0,ply:0,repetitions:{}};
  initializeTerminal(state);
  return freeze({rules:state,hidden:{hands:{w:white.slice(0,3),b:black.slice(0,3)},decks:{w:white.slice(3),b:black.slice(3)},knowledge:{w:emptyKnowledge(),b:emptyKnowledge()}}});
}
export function playerView(state:AuthoritativeBattleState,side:Side):PlayerView {
  return freeze({rules:clone(state.rules),viewer:side,ownHand:[...state.hidden.hands[side]],knowledge:clone(state.hidden.knowledge[side])});
}
function updateKnowledge(state:AuthoritativeBattleState):void {
  for(const side of ['w','b'] as const){const enemy=opposite(side);
    for(const observation of state.hidden.knowledge[side].radarObservations){
      if(observation.result==='IN_HAND'&&(state.rules.used[enemy].includes(observation.queriedCardId)||state.rules.discarded[enemy].includes(observation.queriedCardId)))observation.stale=true;
      if(observation.result==='NOT_IN_HAND'&&state.rules.drawCounts[enemy]>observation.opponentCumulativeDrawCountAtObservation)observation.stale=true;
    }
  }
}
function takeDraw(state:AuthoritativeBattleState,side:Side):void {
  const card=state.hidden.decks[side].shift();if(!card)throw new Error('draw-state-inconsistent');
  state.hidden.hands[side].push(card);
  const known=state.hidden.knowledge[side].knownUpcomingCards;
  if(known[0]===card)known.shift();else if(known.length)known.splice(0);
}
export function applyAuthoritative(input:AuthoritativeBattleState,action:Action):AuthoritativeBattleState {
  const side=input.rules.fen.split(' ')[1] as Side,view=playerView(input,side);
  const change=transition(view,action),state=clone(input);
  state.rules=clone(change.rules);
  if(action.type==='play'||action.type==='discard'){
    const i=state.hidden.hands[side].indexOf(action.card);if(i<0)throw new Error('hidden-hand-inconsistent');state.hidden.hands[side].splice(i,1);
    if(action.type==='play'&&action.sacrifice){const j=state.hidden.hands[side].indexOf(action.sacrifice);if(j<0)throw new Error('hidden-sacrifice-inconsistent');state.hidden.hands[side].splice(j,1);}
  }
  if(change.radar){const enemy=opposite(side);
    state.hidden.knowledge[side].radarObservations.push({queriedCardId:change.radar,result:state.hidden.hands[enemy].includes(change.radar)?'IN_HAND':'NOT_IN_HAND',observedTurn:state.rules.ply,opponentCumulativeDrawCountAtObservation:state.rules.drawCounts[enemy],stale:false});
  }
  if(change.inspect)state.hidden.knowledge[side].pendingCards=state.hidden.decks[side].slice(0,change.inspect);
  if(action.type==='resolve'){
    const inspected=state.hidden.knowledge[side].pendingCards;
    const rest=state.hidden.decks[side].slice(inspected.length);
    state.hidden.decks[side]=[...action.order,...rest];
    state.hidden.knowledge[side].knownUpcomingCards=[...action.order];
    state.hidden.knowledge[side].pendingCards=[];
    if(action.selected)state.hidden.hands[side].push(action.selected);
  }
  if(change.draw)takeDraw(state,change.draw);
  updateKnowledge(state);
  for(const color of ['w','b'] as const)if(state.hidden.hands[color].length!==state.rules.handCounts[color]||state.hidden.decks[color].length!==state.rules.deckCounts[color])throw new Error('hidden-count-inconsistent');
  return freeze(state);
}
