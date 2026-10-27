export type Side = 'w'|'b';
export type CardId = 'radar'|'prophecy'|'shelter'|'chain'|'slow'|'pawn_deviation'|'pawn_advance'|'locked_square'|'freeze'|'purify'|'mine'|'break_seal'|'fog'|'mana_sabotage'|'card_block'|'rook_bend'|'angry_n'|'shadow_pass'|'hunt_vow'|'watch_vow'|'echo'|'fate_exchange'|'shadow_contract'|'board_seal';
export type Phase = 'card'|'chess'|'pending'|'terminal';
export type Rarity = 'common'|'rare'|'epic'|'legendary';
export interface CardDefinition {id:CardId;cost:number;rarity:Rarity;category:string;target:string}
export type Pair<T> = {w:T;b:T};
export const opposite = (side:Side):Side => side==='w'?'b':'w';
export interface PieceEffect {
  id:string;type:'shelter'|'chain'|'slow'|'freeze'|'mine_debuff';owner:Side;
  pieceId:string;responseSide:Side;duration:'card'|'move'|'piece_move';
}
export interface BoardEffect {
  id:string;type:'mine'|'locked_square'|'fog'|'board_seal';owner:Side;
  squares:number[];responseSide:Side;duration:'card'|'move'|'persistent';
}
export interface Modifier {
  id:string;type:'mana_sabotage'|'card_block'|'echo'|'discount';owner:Side;
  responseSide:Side;targetCard:CardId|null;ownTurn:number;
}
export interface Vow {
  id:string;type:'hunt'|'watch';owner:Side;pieceId:string|null;square:number|null;remainingMoves:number;
}
export interface SpecialMoveAuthorization {card:CardId;from:number;moves:string[]}
export interface PendingResolution {card:'prophecy'|'fate_exchange';owner:Side}
export interface Terminal {
  reason:'checkmate'|'stalemate'|'seventy_five_moves'|'fivefold';winner:Side|null;
  mateByRestriction:boolean;mateBySpecialMove:boolean;stalemateByRestriction:boolean;
}
export interface RuleState {
  fen:string;pieceIds:(string|null)[];movedPawns:string[];phase:Phase;
  mana:Pair<number>;ownTurns:Pair<number>;handCounts:Pair<number>;deckCounts:Pair<number>;drawCounts:Pair<number>;
  arsenals:Pair<CardId[]>;used:Pair<CardId[]>;discarded:Pair<CardId[]>;
  pieceEffects:PieceEffect[];boardEffects:BoardEffect[];modifiers:Modifier[];vows:Vow[];
  special:SpecialMoveAuthorization|null;pending:PendingResolution|null;terminal:Terminal|null;
  effectSequence:number;ply:number;repetitions:Record<string,number>;
}
export interface RadarObservation {
  queriedCardId:CardId;result:'IN_HAND'|'NOT_IN_HAND';observedTurn:number;
  opponentCumulativeDrawCountAtObservation:number;stale:boolean;
}
export interface PlayerKnowledgeState {knownUpcomingCards:CardId[];radarObservations:RadarObservation[];pendingCards:CardId[]}
export interface PlayerView {rules:RuleState;viewer:Side;ownHand:CardId[];knowledge:PlayerKnowledgeState}
export interface AuthoritativeHiddenState {hands:Pair<CardId[]>;decks:Pair<CardId[]>;knowledge:Pair<PlayerKnowledgeState>}
export interface AuthoritativeBattleState {rules:RuleState;hidden:AuthoritativeHiddenState}
export type Action =
  | {type:'move';uci:string}
  | {type:'play';card:CardId;target?:number|string;sacrifice?:CardId}
  | {type:'discard';card:CardId}
  | {type:'pass'}
  | {type:'resolve';order:CardId[];selected?:CardId};
export interface RuleTransition {rules:RuleState;draw:Side|null;radar:CardId|null;inspect:number}

export const CARDS:Readonly<Record<CardId,CardDefinition>> = Object.freeze(Object.fromEntries([
  ['radar',1,'common','knowledge','opponent_card'],['prophecy',1,'rare','knowledge','none'],
  ['shelter',2,'common','protection','own_piece'],['chain',2,'common','restriction','opponent_piece'],
  ['slow',2,'common','restriction','opponent_slider'],['pawn_deviation',2,'common','movement','own_pawn'],
  ['pawn_advance',2,'common','movement','own_pawn'],['locked_square',2,'common','board','empty_square'],
  ['freeze',4,'rare','restriction','opponent_piece'],['purify',1,'common','removal','own_piece_effect'],
  ['mine',2,'rare','board','empty_square'],['break_seal',1,'rare','removal','opponent_board_effect'],
  ['fog',3,'rare','protection','zone'],['mana_sabotage',2,'rare','modifier','opponent_card'],
  ['card_block',3,'rare','modifier','opponent_card'],['rook_bend',2,'epic','movement','own_rook'],
  ['angry_n',3,'epic','movement','own_knight'],['shadow_pass',3,'epic','movement','own_bishop_rook'],
  ['hunt_vow',2,'epic','vow','opponent_piece'],['watch_vow',2,'epic','vow','empty_square'],
  ['echo',2,'epic','modifier','opponent_card'],['fate_exchange',3,'legendary','knowledge','sacrifice'],
  ['shadow_contract',1,'legendary','modifier','sacrifice'],['board_seal',5,'legendary','board','zone']
].map(([id,cost,rarity,category,target])=>[id,Object.freeze({id,cost,rarity,category,target})])) as Record<CardId,CardDefinition>);
export const STARTER:readonly CardId[]=Object.freeze(['radar','prophecy','shelter','chain','slow','pawn_deviation','pawn_advance','locked_square','freeze','purify']);
export const MOVEMENT:readonly CardId[]=Object.freeze(['pawn_deviation','pawn_advance','rook_bend','angry_n','shadow_pass']);
export function validateDeck(deck:readonly CardId[]):void {
  if(deck.length!==10||new Set(deck).size!==10||deck.some(c=>!Object.hasOwn(CARDS,c))) throw new Error('invalid-deck');
}
export function emptyKnowledge():PlayerKnowledgeState {return {knownUpcomingCards:[],radarObservations:[],pendingCards:[]};}
export function clone<T>(value:T):T {return structuredClone(value);}
export function freeze<T>(value:T):T {
  if (value && typeof value==='object') {
    Object.freeze(value);
    for(const child of Object.values(value)) if(child && typeof child==='object'&&!Object.isFrozen(child)) freeze(child);
  }
  return value;
}
export function actionKey(a:Action):string {
  switch(a.type){
    case 'move':return `move:${a.uci}`;
    case 'pass':return 'pass';
    case 'discard':return `discard:${a.card}`;
    case 'play':return `play:${a.card}:${a.target??''}:${a.sacrifice??''}`;
    case 'resolve':return `resolve:${a.selected??''}:${a.order.join(',')}`;
  }
}
