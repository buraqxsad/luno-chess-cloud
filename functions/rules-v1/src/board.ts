import {Chess,type Square,type PieceSymbol} from 'chess.js';
import {type Side,opposite} from './model.js';
export interface GeometryMove {uci:string;from:number;to:number;promotion:PieceSymbol|null;castle:boolean;ep:boolean}
export const squareName=(i:number):string=>String.fromCharCode(97+i%8)+(Math.floor(i/8)+1);
export const squareIndex=(s:string):number=>s.charCodeAt(0)-97+8*(Number(s[1])-1);
export const sideOf=(p:string):Side=>p===p.toUpperCase()?'w':'b';
export function squares(fen:string):(string|null)[] {
  const out:(string|null)[]=Array(64).fill(null);
  const ranks=fen.split(' ')[0]!.split('/');
  for(let r=0;r<8;r++){let f=0;for(const ch of ranks[7-r]!) {
    if(/[1-8]/.test(ch))f+=Number(ch);else out[r*8+f++]=ch;
  }}return out;
}
export function boardFen(board:(string|null)[],turn:Side,rights:string,ep:string,half:number,full:number):string {
  const rows:string[]=[];
  for(let r=7;r>=0;r--){let row='',empty=0;for(let f=0;f<8;f++){
    const p=board[r*8+f];if(!p){empty++;continue;}if(empty){row+=empty;empty=0;}row+=p;
  }if(empty)row+=empty;rows.push(row);}
  return `${rows.join('/')} ${turn} ${rights||'-'} ${ep} ${half} ${full}`;
}
export function forSide(fen:string,side:Side):string {
  const fields=fen.split(' ');if(fields[1]!==side)fields[3]='-';fields[1]=side;return fields.join(' ');
}
export function orthodoxPosition(fen?:string):Chess {
  const chess=new Chess(fen);
  const original=chess.fen({forceEnpassantSquare:true}),fields=original.split(' '),board=squares(original);
  // chess.js trusts special-right fields even when their required pieces are absent.
  const homes:Record<string,[number,string,number,string]>={
    K:[4,'K',7,'R'],Q:[4,'K',0,'R'],k:[60,'k',63,'r'],q:[60,'k',56,'r']
  };
  fields[2]=[...fields[2]!].filter(right=>{
    const home=homes[right];
    return home&&board[home[0]]===home[1]&&board[home[2]]===home[3];
  }).join('')||'-';
  if(fields[3]!=='-'){
    const target=squareIndex(fields[3]!),white=fields[1]==='w';
    if(board[target]||board[target+(white?-8:8)]!==(white?'p':'P'))fields[3]='-';
  }
  const normalized=fields.join(' ');
  if(normalized!==original)chess.load(normalized);
  return chess;
}
export function normalMoves(fen:string,side:Side):GeometryMove[] {
  return orthodoxPosition(forSide(fen,side)).moves({verbose:true}).map(m=>({
    uci:m.from+m.to+(m.promotion??''),from:squareIndex(m.from),to:squareIndex(m.to),
    promotion:m.promotion??null,castle:m.isKingsideCastle()||m.isQueensideCastle(),ep:m.isEnPassant()
  }));
}
export function applyGeometry(fen:string,m:GeometryMove,cardDouble=false):string {
  const fields=fen.split(' '),board=squares(fen),piece=board[m.from]!;
  const side=sideOf(piece),capture=!!board[m.to]||m.ep;
  board[m.to]=m.promotion?(side==='w'?m.promotion.toUpperCase():m.promotion):piece;board[m.from]=null;
  if(m.ep)board[m.to+(side==='w'?-8:8)]=null;
  if(m.castle){const rank=Math.floor(m.from/8),kingSide=m.to%8===6;
    const rookFrom=rank*8+(kingSide?7:0),rookTo=rank*8+(kingSide?5:3);
    board[rookTo]=board[rookFrom]??null;board[rookFrom]=null;
  }
  let rights=fields[2]==='-'?'':fields[2]!;
  const revoke:Record<number,string>={0:'Q',7:'K',4:'KQ',56:'q',63:'k',60:'kq'};
  for(const i of [m.from,m.to]) for(const right of revoke[i]??'')rights=rights.replace(right,'');
  let ep='-';
  if(piece.toLowerCase()==='p'&&Math.abs(m.to-m.from)===16&&!cardDouble)ep=squareName((m.to+m.from)/2);
  return boardFen(board,opposite(side),rights,ep,piece.toLowerCase()==='p'||capture?0:Number(fields[4])+1,Number(fields[5])+(side==='b'?1:0));
}
export function inCheck(fen:string,side:Side):boolean {
  const board=squares(fen);const king=board.indexOf(side==='w'?'K':'k');
  if(king<0)throw new Error('missing-king');
  return new Chess(fen).isAttacked(squareName(king) as Square,opposite(side));
}
