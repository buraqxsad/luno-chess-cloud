import {Chess, type Move, type Color} from 'chess.js';
import {orthodoxPosition} from './board.js';

export type ChessStatus = 'ongoing'|'checkmate'|'stalemate'|'dead_position'|'seventy_five_moves'|'fivefold'|'fifty_move_claim'|'threefold_claim';

export function uci(move: Move): string {
  return move.from + move.to + (move.promotion ?? '');
}

export function legalChessMoves(fen: string): string[] {
  return orthodoxPosition(fen).moves({verbose:true}).map(uci).sort();
}

export function repetitionKey(chess: Chess): string {
  const position=orthodoxPosition(chess.fen({forceEnpassantSquare:true}));
  const fields = position.fen({forceEnpassantSquare:true}).split(' ');
  if (!position.moves({verbose:true}).some(m=>m.isEnPassant())) fields[3] = '-';
  return fields.slice(0,4).join(' ');
}

export function perft(chess: Chess, depth: number): number {
  if (!Number.isSafeInteger(depth) || depth < 0) throw new RangeError('Invalid perft depth');
  // chess.js perft does not stop at claimable/automatic draw counters.
  return chess.perft(depth);
}

export function divide(fen: string, depth: number): Record<string,number> {
  if (!Number.isSafeInteger(depth) || depth < 1) throw new RangeError('Invalid divide depth');
  const chess = orthodoxPosition(fen);
  const result: Record<string,number> = {};
  for (const move of chess.moves({verbose:true})) {
    chess.move({from:move.from,to:move.to,...(move.promotion?{promotion:move.promotion}:{})});
    result[uci(move)] = perft(chess,depth-1);
    chess.undo();
  }
  return Object.fromEntries(Object.entries(result).sort(([a],[b])=>a.localeCompare(b)));
}

export class PureChessGame {
  private readonly chess: Chess;
  private readonly counts = new Map<string,number>();
  private result: ChessStatus = 'ongoing';

  constructor(fen?: string) {
    this.chess = orthodoxPosition(fen);
    this.record();
    this.refresh();
  }
  get fen(): string { return this.chess.fen({forceEnpassantSquare:true}); }
  get status(): ChessStatus { return this.result; }
  get turn(): Color { return this.chess.turn(); }
  get inCheck(): boolean { return this.chess.isCheck(); }
  get legalMoves(): string[] { return this.result==='ongoing'?this.chess.moves({verbose:true}).map(uci).sort():[]; }
  get halfmove(): number { return Number(this.fen.split(' ')[4]); }
  get positionCount(): number { return this.counts.get(repetitionKey(this.chess))??0; }
  get canClaimFifty(): boolean { return this.result==='ongoing' && this.halfmove>=100; }
  get canClaimThreefold(): boolean { return this.result==='ongoing' && this.positionCount>=3; }

  play(requested: string): boolean {
    if (!this.legalMoves.includes(requested)) return false;
    const promotion = requested[4];
    this.chess.move({from:requested.slice(0,2),to:requested.slice(2,4),...(promotion?{promotion}:{})});
    this.record(); this.refresh(); return true;
  }
  claimFifty(): boolean {
    if (!this.canClaimFifty) return false;
    this.result='fifty_move_claim'; return true;
  }
  claimThreefold(): boolean {
    if (!this.canClaimThreefold) return false;
    this.result='threefold_claim'; return true;
  }
  private record(): void {
    const key=repetitionKey(this.chess);
    this.counts.set(key,(this.counts.get(key)??0)+1);
  }
  private refresh(): void {
    if (this.chess.isCheckmate()) this.result='checkmate';
    else if (this.chess.isStalemate()) this.result='stalemate';
    else if (this.chess.isInsufficientMaterial()) this.result='dead_position';
    else if (this.halfmove>=150) this.result='seventy_five_moves';
    else if (this.positionCount>=5) this.result='fivefold';
    else this.result='ongoing';
  }
}
