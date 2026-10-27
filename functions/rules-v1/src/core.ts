import {type PieceSymbol} from 'chess.js';
import {CARDS,MOVEMENT,clone,freeze,actionKey,opposite,type Action,type CardId,type PlayerView,type RuleState,type RuleTransition,type Side,type SpecialMoveAuthorization} from './model.js';
import {applyGeometry,forSide,inCheck,normalMoves,squares,sideOf,type GeometryMove} from './board.js';

function turn(state:RuleState):Side {return state.fen.split(' ')[1] as Side;}
function compareText(a:string,b:string):number{return a<b?-1:a>b?1:0;}
function permutations<T>(items:readonly T[]):T[][] {
  if(!items.length)return [[]];
  return items.flatMap((item,i)=>permutations(items.filter((_,j)=>i!==j)).map(rest=>[item,...rest]));
}
function zone(anchor:number):number[] {
  if(anchor<0||anchor>=64||anchor%8===7||Math.floor(anchor/8)===7)return [];
  return [anchor,anchor+1,anchor+8,anchor+9];
}
function restrictions(state:RuleState,move:GeometryMove,side:Side):boolean {
  const board=squares(state.fen),piece=board[move.from];if(!piece||sideOf(piece)!==side)return false;
  const relocations=[{from:move.from,to:move.to}];
  if(move.castle){const r=Math.floor(move.from/8)*8,k=move.to%8===6;relocations.push({from:r+(k?7:0),to:r+(k?5:3)});}
  for(const {from,to} of relocations){
    const p=board[from];if(!p)return false;
    if(p.toLowerCase()==='k')continue;
    const id=state.pieceIds[from],capture=from===move.from&&(!!board[to]||move.ep);
    for(const effect of state.pieceEffects.filter(e=>e.pieceId===id)){
      if(effect.type==='freeze')return false;
      if((effect.type==='chain'||effect.type==='mine_debuff')&&capture)return false;
      if(effect.type==='slow'&&Math.max(Math.abs(to%8-from%8),Math.abs(Math.floor(to/8)-Math.floor(from/8)))>2)return false;
    }
    if(!board[to]&&state.boardEffects.some(e=>e.owner!==side&&(e.type==='locked_square'||e.type==='board_seal')&&e.squares.includes(to)))return false;
  }
  return true;
}
function pureSafe(state:RuleState,move:GeometryMove,side:Side,cardDouble:boolean):boolean {
  return !inCheck(applyGeometry(forSide(state.fen,side),move,cardDouble),side);
}

export function legalRuleMoves(state:RuleState,side:Side,authorization:SpecialMoveAuthorization|null=null):GeometryMove[] {
  if(authorization){return specialMoves(state,authorization.card,authorization.from,side).filter(m=>authorization.moves.includes(m.uci));}
  return normalMoves(state.fen,side).filter(m=>{
    const p=squares(state.fen)[m.from];
    if(p?.toLowerCase()==='p'&&Math.abs(m.to-m.from)===16&&state.movedPawns.includes(state.pieceIds[m.from]!))return false;
    return restrictions(state,m,side);
  });
}
export function specialMoves(state:RuleState,card:CardId,from:number,side:Side):GeometryMove[] {
  if(!Number.isInteger(from)||from<0||from>=64)return [];
  const board=squares(state.fen),p=board[from];if(!p||sideOf(p)!==side)return [];
  const type=p.toLowerCase(),f=from%8,r=Math.floor(from/8),dir=side==='w'?1:-1;
  const destinations:number[]=[];
  const add=(nf:number,nr:number,capture=false):void=>{
    if(nf<0||nf>7||nr<0||nr>7)return;
    const to=nr*8+nf,target=board[to];
    if(!target||(capture&&sideOf(target)!==side&&target.toLowerCase()!=='k'))destinations.push(to);
  };
  if(card==='pawn_deviation'&&type==='p'&&r+dir!==0&&r+dir!==7){add(f-1,r+dir);add(f+1,r+dir);}
  if(card==='pawn_advance'&&type==='p'&&r+2*dir>0&&r+2*dir<7&&!board[from+8*dir])add(f,r+2*dir);
  if(card==='rook_bend'&&type==='r')for(const df of [-1,1])for(const dr of [-1,1])add(f+df,r+dr);
  if(card==='angry_n'&&type==='n')for(const [df,dr] of [[1,0],[-1,0],[0,1],[0,-1]])add(f+df!,r+dr!,true);
  if(card==='shadow_pass'&&(type==='b'||type==='r')){
    const dirs=type==='b'?[[1,1],[1,-1],[-1,1],[-1,-1]]:[[1,0],[-1,0],[0,1],[0,-1]];
    for(const [df,dr] of dirs){let nf=f+df!,nr=r+dr!,crossed=0;
      while(nf>=0&&nf<8&&nr>=0&&nr<8){const to=nr*8+nf,target=board[to];
        if(target){if(sideOf(target)!==side||target.toLowerCase()==='k'||++crossed>1)break;}
        else if(crossed===1)destinations.push(to);
        nf+=df!;nr+=dr!;
      }
    }
  }
  if(!destinations.length)return [];
  const standard=card==='pawn_advance'?new Set(normalMoves(state.fen,side).map(m=>m.uci)):new Set<string>();
  return destinations.map(to=>({uci:squareText(from)+squareText(to),from,to,promotion:null as PieceSymbol|null,castle:false,ep:false})).filter(m=>
    restrictions(state,m,side)&&pureSafe(state,m,side,card==='pawn_advance'&&(!standard.has(m.uci)||state.movedPawns.includes(state.pieceIds[from]!))));
}
function squareText(i:number):string{return String.fromCharCode(97+i%8)+(Math.floor(i/8)+1);}
function protectedTarget(state:RuleState,index:number,attacker:Side):boolean {
  return state.pieceEffects.some(e=>e.type==='shelter'&&e.owner!==attacker&&e.pieceId===state.pieceIds[index])||
    state.boardEffects.some(e=>e.type==='fog'&&e.owner!==attacker&&e.squares.includes(index));
}
export function effectiveCost(state:RuleState,side:Side,card:CardId):number {
  let cost=CARDS[card].cost;
  for(const m of state.modifiers)if(m.responseSide===side&&m.ownTurn===state.ownTurns[side]){
    if(m.type==='mana_sabotage'&&m.targetCard===card)cost++;
    if(m.type==='discount')cost-=2;
  }
  return Math.max(1,cost);
}
export function cardTargets(view:PlayerView,card:CardId):(number|string|undefined)[] {
  const state=view.rules,side=view.viewer,enemy=opposite(side),board=squares(state.fen),definition=CARDS[card];
  if(!definition)return [];
  if(definition.category==='movement')return Array.from({length:64},(_,i)=>i).filter(i=>specialMoves(state,card,i,side).length>0);
  if(definition.category==='vow'&&state.vows.some(v=>v.owner===side))return [];
  switch(definition.target){
    case 'opponent_card':return state.arsenals[enemy].filter(c=>!state.used[enemy].includes(c)&&!state.discarded[enemy].includes(c));
    case 'own_piece':return board.flatMap((p,i)=>p&&sideOf(p)===side&&p.toLowerCase()!=='k'?[i]:[]);
    case 'opponent_piece':case 'opponent_slider':return board.flatMap((p,i)=>
      p&&sideOf(p)===enemy&&p.toLowerCase()!=='k'&&(definition.target!=='opponent_slider'||['r','b','q'].includes(p.toLowerCase()))&&!protectedTarget(state,i,side)?[i]:[]);
    case 'empty_square':
      if(card==='mine'&&state.boardEffects.some(e=>e.type==='mine'&&e.owner===side))return [];
      return board.flatMap((p,i)=>!p&&(card!=='mine'||!state.boardEffects.some(e=>e.type==='mine'&&e.squares.includes(i)))?[i]:[]);
    case 'zone':return Array.from({length:64},(_,i)=>i).filter(i=>zone(i).length===4&&(card!=='board_seal'||zone(i).some(s=>!board[s])));
    case 'own_piece_effect':return state.pieceEffects.filter(e=>e.type!=='shelter'&&state.pieceEffects.filter(other=>other.id===e.id).length===1&&state.pieceIds.some((id,i)=>id===e.pieceId&&board[i]&&sideOf(board[i]!)===side)).map(e=>e.id);
    case 'opponent_board_effect':return state.boardEffects.filter(e=>e.owner===enemy&&state.boardEffects.filter(other=>other.id===e.id).length===1).map(e=>e.id);
    case 'none':return card==='prophecy'&&state.deckCounts[side]<1?[]:[undefined];
    case 'sacrifice':return view.ownHand.some(c=>c!==card)&&(card!=='fate_exchange'||state.deckCounts[side]>=1)?[undefined]:[];
    default:return [];
  }
}
function checkView(view:PlayerView):void {
  const s=view.rules,side=view.viewer;
  if(view.ownHand.length!==s.handCounts[side]||new Set(view.ownHand).size!==view.ownHand.length||
    view.ownHand.some(c=>!Object.hasOwn(CARDS,c)||!s.arsenals[side].includes(c)||s.used[side].includes(c)||s.discarded[side].includes(c)))throw new Error('invalid-player-view');
  const validKnown=(items:CardId[],limit:number):boolean=>items.length<=limit&&new Set(items).size===items.length&&items.every(c=>Object.hasOwn(CARDS,c)&&s.arsenals[side].includes(c)&&!view.ownHand.includes(c)&&!s.used[side].includes(c)&&!s.discarded[side].includes(c));
  const pendingLimit=s.phase==='pending'&&s.pending?.owner===side?Math.min(s.deckCounts[side],s.pending.card==='prophecy'?2:3):0;
  if(!validKnown(view.knowledge.pendingCards,pendingLimit)||view.knowledge.pendingCards.length!==pendingLimit||!validKnown(view.knowledge.knownUpcomingCards,Math.min(2,s.deckCounts[side])))throw new Error('invalid-player-knowledge');
}

export function initializeTerminal(s:RuleState):void {
  const side=turn(s),check=inCheck(s.fen,side);
  if(!legalRuleMoves(s,side).length)s.terminal={reason:check?'checkmate':'stalemate',winner:check?opposite(side):null,mateByRestriction:false,mateBySpecialMove:false,stalemateByRestriction:false};
  else if(Number(s.fen.split(' ')[4])>=150)s.terminal={reason:'seventy_five_moves',winner:null,mateByRestriction:false,mateBySpecialMove:false,stalemateByRestriction:false};
  if(s.terminal)s.phase='terminal';else recordRepetition(s);
}
export function legalActions(view:PlayerView):Action[] {
  checkView(view);const s=view.rules,side=view.viewer;
  if(turn(s)!==side||s.phase==='terminal')return [];
  if(s.phase==='pending'){
    if(s.pending?.owner!==side)return [];
    const inspected=view.knowledge.pendingCards;
    if(!inspected.length)return [];
    if(s.pending.card==='prophecy')return permutations(inspected).map(order=>({type:'resolve',order}));
    return inspected.flatMap(selected=>permutations(inspected.filter(c=>c!==selected)).map(order=>({type:'resolve' as const,selected,order})));
  }
  if(s.phase==='chess')return legalRuleMoves(s,side,s.special).map(m=>({type:'move',uci:m.uci}));
  if(s.ownTurns[side]<2)return [];
  const actions:Action[]=[{type:'pass'},...view.ownHand.map(card=>({type:'discard' as const,card}))];
  for(const card of view.ownHand){
    if(s.mana[side]<effectiveCost(s,side,card)||s.modifiers.some(m=>m.type==='card_block'&&m.responseSide===side&&m.ownTurn===s.ownTurns[side]&&m.targetCard===card))continue;
    for(const target of cardTargets(view,card)){
      const base={type:'play' as const,card,...(target===undefined?{}:{target})};
      if(card==='fate_exchange'||card==='shadow_contract')for(const sacrifice of view.ownHand.filter(c=>c!==card))actions.push({...base,sacrifice});
      else actions.push(base);
    }
  }
  return actions.sort((a,b)=>compareText(actionKey(a),actionKey(b)));
}
function closeCardWindow(s:RuleState,side:Side):void {
  s.pieceEffects=s.pieceEffects.filter(e=>!(e.duration==='card'&&e.responseSide===side));
  s.boardEffects=s.boardEffects.filter(e=>!(e.duration==='card'&&e.responseSide===side));
  s.modifiers=s.modifiers.filter(m=>!(m.responseSide===side&&m.ownTurn<=s.ownTurns[side]));
  s.phase='chess';
}
function nextEffect(s:RuleState):string {return `e${++s.effectSequence}`;}
function applyCard(s:RuleState,view:PlayerView,a:Extract<Action,{type:'play'}>):{radar:CardId|null;inspect:number} {
  const side=view.viewer,enemy=opposite(side),card=a.card,target=a.target;
  s.mana[side]-=effectiveCost(s,side,card);s.handCounts[side]--;s.used[side].push(card);s.used[side].sort();
  if(a.sacrifice){s.discarded[side].push(a.sacrifice);s.discarded[side].sort();s.handCounts[side]--;}
  for(const m of s.modifiers)if(m.type==='echo'&&m.responseSide===side&&m.ownTurn===s.ownTurns[side]&&m.targetCard===card)s.mana[m.owner]=Math.min(6,s.mana[m.owner]+2);
  let radar:CardId|null=null,inspect=0;
  if(MOVEMENT.includes(card))s.special={card,from:target as number,moves:specialMoves(s,card,target as number,side).map(m=>m.uci).sort()};
  else switch(card){
    case 'radar':radar=target as CardId;break;
    case 'prophecy':case 'fate_exchange':
      s.pending={card,owner:side};s.phase='pending';inspect=card==='prophecy'?2:3;break;
    case 'shelter':case 'chain':case 'slow':case 'freeze':
      s.pieceEffects.push({id:nextEffect(s),type:card,owner:side,pieceId:s.pieceIds[target as number]!,responseSide:enemy,duration:card==='shelter'?'card':'move'});break;
    case 'purify':s.pieceEffects=s.pieceEffects.filter(e=>e.id!==target);break;
    case 'mine':case 'locked_square':case 'fog':case 'board_seal':
      s.boardEffects.push({id:nextEffect(s),type:card,owner:side,squares:card==='fog'||card==='board_seal'?zone(target as number):[target as number],responseSide:enemy,duration:card==='mine'?'persistent':card==='fog'?'card':'move'});break;
    case 'break_seal':s.boardEffects=s.boardEffects.filter(e=>e.id!==target);break;
    case 'mana_sabotage':case 'card_block':case 'echo':
      s.modifiers.push({id:nextEffect(s),type:card,owner:side,responseSide:enemy,targetCard:target as CardId,ownTurn:s.ownTurns[enemy]+1});break;
    case 'shadow_contract':
      s.modifiers.push({id:nextEffect(s),type:'discount',owner:side,responseSide:side,targetCard:null,ownTurn:s.ownTurns[side]+1});break;
    case 'hunt_vow':case 'watch_vow':
      s.vows.push({id:nextEffect(s),type:card==='hunt_vow'?'hunt':'watch',owner:side,pieceId:card==='hunt_vow'?s.pieceIds[target as number]!:null,square:card==='watch_vow'?target as number:null,remainingMoves:card==='hunt_vow'?2:1});break;
  }
  if(!inspect)closeCardWindow(s,side);
  return {radar,inspect};
}
function counterfactualDefenses(s:RuleState,side:Side):GeometryMove[] {
  const free=clone(s);
  free.pieceEffects=free.pieceEffects.filter(e=>e.type==='shelter'||!free.pieceIds.some((id,i)=>id===e.pieceId&&squares(free.fen)[i]&&sideOf(squares(free.fen)[i]!)===side));
  free.boardEffects=free.boardEffects.filter(e=>e.owner===side||!(e.type==='locked_square'||e.type==='board_seal'));
  return legalRuleMoves(free,side);
}
function resolveMove(s:RuleState,m:GeometryMove,side:Side):Side|null {
  const before=squares(s.fen),enemy=opposite(side),special=s.special!==null;
  const normal=normalMoves(s.fen,side).some(n=>n.uci===m.uci&&n.ep===m.ep&&n.castle===m.castle&&n.promotion===m.promotion);
  const moverId=s.pieceIds[m.from]!,captureSquare=m.ep?m.to+(side==='w'?-8:8):m.to;
  const capturedId=before[captureSquare]?s.pieceIds[captureSquare]:null;
  const movingIds=[moverId],relocations=[m.to],oldEffects=new Set(s.pieceEffects.map(e=>e.id));
  s.pieceIds[m.from]=null;if(capturedId)s.pieceIds[captureSquare]=null;s.pieceIds[m.to]=moverId;
  if(m.castle){const rank=Math.floor(m.from/8)*8,k=m.to%8===6,rf=rank+(k?7:0),rt=rank+(k?5:3);
    movingIds.push(s.pieceIds[rf]!);s.pieceIds[rt]=s.pieceIds[rf]!;s.pieceIds[rf]=null;relocations.push(rt);
  }
  const cardDouble=s.special?.card==='pawn_advance'&&(!normal||s.movedPawns.includes(moverId));
  s.fen=applyGeometry(s.fen,m,cardDouble);s.ply++;
  if(before[m.from]!.toLowerCase()==='p'&&!s.movedPawns.includes(moverId)){s.movedPawns.push(moverId);s.movedPawns.sort();}
  // Capture triggers, then entry triggers, then final-position conditions.
  s.vows=s.vows.filter(v=>{
    if(v.type!=='hunt')return true;
    if(v.pieceId===capturedId){if(v.owner===side&&!special)s.mana[side]=Math.min(6,s.mana[side]+2);return false;}
    if(v.owner===side)v.remainingMoves--;return v.remainingMoves>0;
  });
  const after=squares(s.fen);
  s.boardEffects=s.boardEffects.filter(e=>{
    if(e.type!=='mine'||e.owner===side)return true;
    const arrived=relocations.find(to=>e.squares.includes(to)&&after[to]&&after[to]!.toLowerCase()!=='k');
    if(arrived===undefined)return true;
    s.pieceEffects.push({id:nextEffect(s),type:'mine_debuff',owner:e.owner,pieceId:s.pieceIds[arrived]!,responseSide:side,duration:'piece_move'});return false;
  });
  s.vows=s.vows.filter(v=>{
    if(v.type!=='watch'||v.owner===side)return true;
    if(v.square!==null&&after[v.square]&&sideOf(after[v.square]!)===side)s.mana[v.owner]=Math.min(6,s.mana[v.owner]+2);
    return false;
  });
  s.pieceEffects=s.pieceEffects.filter(e=>s.pieceIds.includes(e.pieceId)&&!(e.duration==='move'&&e.responseSide===side)&&!(e.duration==='piece_move'&&oldEffects.has(e.id)&&movingIds.includes(e.pieceId)));
  s.boardEffects=s.boardEffects.filter(e=>!(e.duration==='move'&&e.responseSide===side));
  s.special=null;
  const defense=legalRuleMoves(s,enemy),check=inCheck(s.fen,enemy);
  if(!defense.length){const restriction=counterfactualDefenses(s,enemy).length>0;
    s.terminal={reason:check?'checkmate':'stalemate',winner:check?side:null,mateByRestriction:check&&restriction,mateBySpecialMove:check&&special&&!normal,stalemateByRestriction:!check&&restriction};
  }else if(Number(s.fen.split(' ')[4])>=150)s.terminal={reason:'seventy_five_moves',winner:null,mateByRestriction:false,mateBySpecialMove:false,stalemateByRestriction:false};
  if(s.terminal){s.phase='terminal';return null;}
  let draw:Side|null=null;
  if(s.handCounts[side]<4&&s.deckCounts[side]>0){s.handCounts[side]++;s.deckCounts[side]--;s.drawCounts[side]++;draw=side;}
  s.ownTurns[enemy]++;if(s.ownTurns[enemy]>1)s.mana[enemy]=Math.min(6,s.mana[enemy]+1);
  s.phase=s.ownTurns[enemy]===1?'chess':'card';
  recordRepetition(s);return draw;
}
function sortedObject(value:unknown):unknown {
  if(Array.isArray(value))return value.map(sortedObject);
  if(value&&typeof value==='object')return Object.fromEntries(Object.entries(value).sort(([a],[b])=>compareText(a,b)).map(([k,v])=>[k,sortedObject(v)]));
  return value;
}
export function publicFingerprint(s:RuleState):string {
  if(!(s.phase==='card'&&s.ownTurns[turn(s)]>=2)&&!(s.phase==='chess'&&s.ownTurns[turn(s)]===1))throw new Error('not-stable-boundary');
  const fen=s.fen.split(' ');
  if(!legalRuleMoves(s,turn(s)).some(m=>m.ep))fen[3]='-';
  return JSON.stringify(sortedObject({fen:fen.slice(0,4).join(' '),phase:s.phase,firstTurns:{w:s.ownTurns.w<=1,b:s.ownTurns.b<=1},
    mana:s.mana,handCounts:s.handCounts,deckCounts:s.deckCounts,drawCounts:s.drawCounts,arsenals:s.arsenals,used:s.used,discarded:s.discarded,
    pieceIds:s.pieceIds,movedPawns:s.movedPawns,pieceEffects:s.pieceEffects,boardEffects:s.boardEffects,vows:s.vows,
    modifiers:s.modifiers.map(m=>({...m,ownTurn:m.ownTurn-s.ownTurns[m.responseSide]})),special:s.special}));
}
export function recordRepetition(s:RuleState):void {
  const key=publicFingerprint(s);s.repetitions[key]=(s.repetitions[key]??0)+1;
  if(s.repetitions[key]>=5){s.phase='terminal';s.terminal={reason:'fivefold',winner:null,mateByRestriction:false,mateBySpecialMove:false,stalemateByRestriction:false};}
}
function matchesAction(requested:unknown,canonical:Action):boolean {
  if(!requested||typeof requested!=='object'||Array.isArray(requested))return false;
  const a=requested as Record<string,unknown>;
  if(a.type!==canonical.type)return false;
  switch(canonical.type){
    case 'pass':return true;
    case 'move':return a.uci===canonical.uci;
    case 'discard':return a.card===canonical.card;
    case 'play':return a.card===canonical.card&&(a.target??null)===(canonical.target??null)&&(a.sacrifice??null)===(canonical.sacrifice??null);
    case 'resolve':return (a.selected??null)===(canonical.selected??null)&&Array.isArray(a.order)&&a.order.length===canonical.order.length&&a.order.every((c,i)=>c===canonical.order[i]);
  }
}
export function transition(view:PlayerView,action:Action):RuleTransition {
  const canonical=legalActions(view).find(a=>matchesAction(action,a));
  if(!canonical)throw new Error('illegal-action');
  // Canonicalize payload: caller-supplied extra fields never influence rules.
  const s=clone(view.rules),side=view.viewer;
  let draw:Side|null=null,radar:CardId|null=null,inspect=0;
  switch(canonical.type){
    case 'pass':closeCardWindow(s,side);break;
    case 'discard':s.handCounts[side]--;s.discarded[side].push(canonical.card);s.discarded[side].sort();closeCardWindow(s,side);break;
    case 'play':({radar,inspect}=applyCard(s,view,canonical));break;
    case 'resolve':if(s.pending!.card==='fate_exchange'){s.handCounts[side]++;s.deckCounts[side]--;s.drawCounts[side]++;}s.pending=null;closeCardWindow(s,side);break;
    case 'move':draw=resolveMove(s,legalRuleMoves(s,side,s.special).find(m=>m.uci===canonical.uci)!,side);break;
  }
  return freeze({rules:s,draw,radar,inspect});
}
export function chooseBotAction(view:PlayerView):Action|null {
  const actions=legalActions(view);if(!actions.length)return null;
  // The planner's entire input is PlayerView. No authoritative object is accepted.
  const board=squares(view.rules.fen);
  const score=(a:Action):number=>a.type==='move'?10+(board[parseDestination(a.uci)]?10:0):a.type==='play'?30:a.type==='resolve'?40:a.type==='pass'?1:0;
  return actions.sort((a,b)=>score(b)-score(a)||compareText(actionKey(a),actionKey(b)))[0]!;
}
function parseDestination(uci:string):number{return uci.charCodeAt(2)-97+8*(Number(uci[3])-1);}
