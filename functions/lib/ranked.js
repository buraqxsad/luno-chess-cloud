'use strict';

const crypto=require('node:crypto');
const {Chess}=require('chess.js');
const {applyRewardClaim,normalizeSeasonRecord,periodSnapshot}=require('./economy');
const {deterministicMissionIds}=require('./missions');
const {syncPassState}=require('./pass');

const MATCH_SCHEMA_VERSION=1;
const RANKED_DURATION_MS=5*60*1000;
const FRIENDLY_DURATION_MINUTES=Object.freeze([1,3,5,10,30]);
const MATCH_DURATION_MS=RANKED_DURATION_MS;
const HEARTBEAT_STALE_MS=15*1000;
const RECONNECT_GRACE_MS=60*1000;
const DRAW_OFFER_MS=30*1000;
const MAX_EVENTS=512;
const MAX_PROCESSED_ACTIONS=384;
const PROMOTIONS=new Set(['Q','R','B','N']);
const LEGENDARY_CARDS=new Set(['deploy1','deploy2','deploy3','plague','reinforce','ghosts']);
const ARENAS=Object.freeze([
  Object.freeze({min:0,max:100,win:32,lose:8}),
  Object.freeze({min:100,max:300,win:30,lose:10}),
  Object.freeze({min:300,max:600,win:28,lose:12}),
  Object.freeze({min:600,max:1000,win:25,lose:15}),
  Object.freeze({min:1000,max:1500,win:22,lose:18}),
  Object.freeze({min:1500,max:2200,win:20,lose:20}),
  Object.freeze({min:2200,max:3000,win:20,lose:20}),
  Object.freeze({min:3000,max:4000,win:19,lose:21}),
  Object.freeze({min:4000,max:999999999,win:18,lose:22})
]);
const CARDS=Object.freeze({
  trap1:Object.freeze({mana:3,target:'empty',family:'trap',level:1,duration:2,hidden:true}),
  trap2:Object.freeze({mana:4,target:'empty',family:'trap',level:2,duration:2,hidden:true}),
  trap3:Object.freeze({mana:5,target:'empty',family:'trap',level:3,duration:2,hidden:true}),
  radar1:Object.freeze({mana:1,target:'none',family:'radar',level:1,hidden:true}),
  radar2:Object.freeze({mana:2,target:'none',family:'radar',level:2,hidden:true}),
  radar3:Object.freeze({mana:3,target:'none',family:'radar',level:3,hidden:true}),
  resist1:Object.freeze({mana:1,target:'own_pawn',family:'resist',level:1}),
  resist2:Object.freeze({mana:3,target:'own_kn_bi',family:'resist',level:2}),
  resist3:Object.freeze({mana:5,target:'own_piece',family:'resist',level:3}),
  deploy1:Object.freeze({mana:5,target:'empty_own',family:'deploy',level:1,piece:'P'}),
  deploy2:Object.freeze({mana:10,target:'empty_own',family:'deploy',level:2,piece:'B'}),
  deploy3:Object.freeze({mana:10,target:'empty_own',family:'deploy',level:3,piece:'N'}),
  shield1:Object.freeze({mana:4,target:'empty_own',family:'shield',level:1,duration:2}),
  shield2:Object.freeze({mana:5,target:'empty_own',family:'shield',level:2,duration:3}),
  shield3:Object.freeze({mana:6,target:'empty_own',family:'shield',level:3,duration:4}),
  freeze:Object.freeze({mana:7,target:'enemy',duration:2,skipMove:true}),
  poison_q:Object.freeze({mana:5,target:'enemy_queen',duration:1}),
  card_block:Object.freeze({mana:3,target:'none',duration:1}),
  medium:Object.freeze({mana:3,target:'none',hidden:true}),
  barbarian:Object.freeze({mana:4,target:'own_pawn'}),
  glue:Object.freeze({mana:5,target:'own_pawn_pair'}),
  archer:Object.freeze({mana:4,target:'own_pawn'}),
  fog:Object.freeze({mana:3,target:'none',duration:2,hidden:true}),
  angry_n:Object.freeze({mana:3,target:'own_knight',duration:1}),
  angry_b:Object.freeze({mana:3,target:'own_bishop',duration:1}),
  plague:Object.freeze({mana:5,target:'none'}),
  reinforce:Object.freeze({mana:6,target:'own_pawn'}),
  ghosts:Object.freeze({mana:6,target:'none',duration:3}),
  immunity:Object.freeze({mana:5,target:'own_piece'})
});
const KNIGHT_OFFSETS=[[1,2],[2,1],[2,-1],[1,-2],[-1,-2],[-2,-1],[-2,1],[-1,2]];
const KING_OFFSETS=[[1,0],[1,1],[0,1],[-1,1],[-1,0],[-1,-1],[0,-1],[1,-1]];
const PIECE_VALUES={P:1,N:3,B:3,R:5,Q:9,K:0};

function rankedError(code,message){
  const error=new Error(message||code);
  error.code=code;
  return error;
}
function isRecord(value){return value!==null&&typeof value==='object'&&!Array.isArray(value);}
function safeInt(value,fallback){const number=Number(value);return Number.isSafeInteger(number)&&number>=0?number:Number(fallback||0);}
function clamp(value,min,max){return Math.max(min,Math.min(max,value));}
function deepClone(value){return JSON.parse(JSON.stringify(value));}
function otherColor(color){return color==='W'?'B':'W';}
function validSquare(value){return Number.isInteger(value)&&value>=0&&value<64;}
function validCoord(file,rank){return file>=0&&file<8&&rank>=0&&rank<8;}
function compactObject(value){return isRecord(value)?value:{};}
function normalizeList(value){
  if(Array.isArray(value))return value.filter(function(item){return item!==null&&item!==undefined;});
  if(!isRecord(value))return [];
  return Object.keys(value).sort(function(first,second){return Number(first)-Number(second);}).map(function(key){return value[key];}).filter(function(item){return item!==null&&item!==undefined;});
}
function normalizeBoard(value){
  const board=new Array(64).fill(null);
  if(Array.isArray(value)){
    for(let index=0;index<64;index++)board[index]=isRecord(value[index])?value[index]:null;
    return board;
  }
  if(isRecord(value))Object.keys(value).forEach(function(key){const index=Number(key);if(validSquare(index)&&isRecord(value[key]))board[index]=value[key];});
  return board;
}
function hydrateMatch(value){
  if(!isRecord(value))return value;
  value.board=normalizeBoard(value.board);
  value.hands=compactObject(value.hands);
  value.hands.W=normalizeList(value.hands.W);
  value.hands.B=normalizeList(value.hands.B);
  value.traps=compactObject(value.traps);
  value.blocks=compactObject(value.blocks);
  value.pits=compactObject(value.pits);
  value.shields=compactObject(value.shields);
  value.fog=Object.assign({W:0,B:0},compactObject(value.fog));
  value.mediumReveal=Object.assign({W:0,B:0},compactObject(value.mediumReveal));
  value.cardBlock=Object.assign({W:0,B:0},compactObject(value.cardBlock));
  value.mana=Object.assign({W:0,B:0},compactObject(value.mana));
  value.lastCard=Object.assign({W:null,B:null},compactObject(value.lastCard));
  value.captures=Object.assign({W:[],B:[]},compactObject(value.captures));
  value.captures.W=normalizeList(value.captures.W);
  value.captures.B=normalizeList(value.captures.B);
  value.metrics=compactObject(value.metrics);
  value.metrics.W=Object.assign({cardsPlayed:0,captures:0,legendaryCards:0,checks:0,promotions:0,cardUsage:{}},compactObject(value.metrics.W));
  value.metrics.B=Object.assign({cardsPlayed:0,captures:0,legendaryCards:0,checks:0,promotions:0,cardUsage:{}},compactObject(value.metrics.B));
  value.metrics.W.cardUsage=compactObject(value.metrics.W.cardUsage);
  value.metrics.B.cardUsage=compactObject(value.metrics.B.cardUsage);
  value.events=normalizeList(value.events);
  value.processedActions=compactObject(value.processedActions);
  value.positionCounts=compactObject(value.positionCounts);
  value.presence=compactObject(value.presence);
  value.settlement=compactObject(value.settlement);
  value.drawOffer=isRecord(value.drawOffer)?value.drawOffer:null;
  value.cancelOffer=isRecord(value.cancelOffer)?value.cancelOffer:null;
  value.result=isRecord(value.result)?value.result:null;
  value.lastEvent=isRecord(value.lastEvent)?value.lastEvent:null;
  value.epTarget=validSquare(Number(value.epTarget))?Number(value.epTarget):-1;
  return value;
}
function initialBoard(){
  const board=new Array(64).fill(null),back=['R','N','B','Q','K','B','N','R'];
  for(let file=0;file<8;file++){
    board[file]={t:back[file],c:'W'};
    board[8+file]={t:'P',c:'W'};
    board[48+file]={t:'P',c:'B'};
    board[56+file]={t:back[file],c:'B'};
  }
  return board;
}
function profileSummary(profile,uid){
  const candidates=[profile&&profile.username,profile&&profile.name],summaryUid=String(uid||profile&&profile.uid||'');
  let username='';
  for(const candidate of candidates){
    if(typeof candidate!=='string')continue;
    const normalized=candidate.normalize('NFKC').trim().toLowerCase();
    if(/^[a-z0-9][a-z0-9_]{2,15}$/.test(normalized)){username=normalized;break;}
  }
  if(!username)username='luno_'+crypto.createHash('sha256').update(summaryUid||'unknown').digest('hex').slice(0,8);
  return {
    uid:summaryUid,
    name:username,
    username,
    usernameRevision:Math.max(safeInt(profile&&profile.usernameRevision,0),safeInt(profile&&profile.usernameChanges,0)),
    country:String(profile&&profile.country||'TR').slice(0,2),
    avatar:String(profile&&profile.avatar||'#e8b840').slice(0,16),
    avatarEmoji:String(profile&&profile.avatarEmoji||'&#9818;').slice(0,32),
    photoURL:profile&&profile.photoURL||null,
    trophies:safeInt(profile&&profile.trophies,0),
    arenaIdx:arenaIndexForProfile(profile),
    lvl:Math.max(1,safeInt(profile&&profile.lvl,1)),
    activeSkin:String(profile&&profile.activeSkin||profile&&profile.inventory&&profile.inventory.activeSkin||'classic').slice(0,64),
    activePieceSet:String(profile&&profile.activePieceSet||profile&&profile.inventory&&profile.inventory.activePieceSet||'std').slice(0,64),
    activeCostumes:deepClone(profile&&profile.activeCostumes||profile&&profile.inventory&&profile.inventory.activeCostumes||{})
  };
}
function createMatchState(options){
  const at=safeInt(options&&options.at,Date.now()),matchId=String(options&&options.matchId||'');
  const white=options&&options.white,black=options&&options.black;
  const mode=options&&options.mode==='friendly'?'friendly':'ranked';
  const requestedMinutes=Number(options&&options.durationMinutes);
  const timeControlMinutes=mode==='ranked'?5:(FRIENDLY_DURATION_MINUTES.includes(requestedMinutes)?requestedMinutes:5);
  const durationMs=timeControlMinutes*60*1000;
  if(!matchId||!white||!black||!white.uid||!black.uid||white.uid===black.uid)throw rankedError('invalid-match','Two distinct ranked players are required.');
  const whiteDeck=normalizeList(white.deck),blackDeck=normalizeList(black.deck);
  if(whiteDeck.length!==6||blackDeck.length!==6)throw rankedError('invalid-deck','Ranked matches require six cards.');
  const state={
    schemaVersion:MATCH_SCHEMA_VERSION,matchId,mode,timeControlMinutes,status:'active',createdAt:at,updatedAt:at,
    participants:{},colors:{},players:{W:profileSummary(white.profile,white.uid),B:profileSummary(black.profile,black.uid)},
    board:initialBoard(),turn:'W',phase:'card',sequence:0,moveCount:0,halfMove:0,epTarget:-1,
    hands:{W:whiteDeck.slice(),B:blackDeck.slice()},mana:{W:1,B:0},cardUsed:false,cardBlock:{W:0,B:0},lastCard:{W:null,B:null},
    traps:{},blocks:{},pits:{},shields:{},fog:{W:0,B:0},mediumReveal:{W:0,B:0},captures:{W:[],B:[]},
    metrics:{W:{cardsPlayed:0,captures:0,legendaryCards:0,checks:0,promotions:0,cardUsage:{}},B:{cardsPlayed:0,captures:0,legendaryCards:0,checks:0,promotions:0,cardUsage:{}}},
    positionCounts:{},drawOffer:null,cancelOffer:null,result:null,processedActions:{},events:[],settlement:{},
    clock:{W:durationMs,B:durationMs,initialMs:durationMs,activeColor:'W',startedAt:at,deadlineAt:at+durationMs},
    presence:{},lastEvent:null
  };
  state.participants[white.uid]=true;state.participants[black.uid]=true;
  state.colors[white.uid]='W';state.colors[black.uid]='B';
  state.presence[white.uid]={state:'CONNECTED',lastSeenAt:at,disconnectedAt:0,graceUntil:0};
  state.presence[black.uid]={state:'CONNECTED',lastSeenAt:at,disconnectedAt:0,graceUntil:0};
  state.positionCounts[positionKey(state)]=1;
  return state;
}

function cloneBoard(board){
  return normalizeBoard(board).map(function(piece){return piece?Object.assign({},piece):null;});
}
function findKing(board,color){for(let index=0;index<64;index++)if(board[index]&&board[index].t==='K'&&board[index].c===color)return index;return -1;}
function castBlocked(state,square,color,ignore){
  if(ignore)return false;
  if(safeInt(state.blocks&&state.blocks[square],0)>0)return true;
  const shield=state.shields&&state.shields[square];if(shield&&shield.by!==color)return true;
  const trap=state.traps&&state.traps[square];return !!(trap&&safeInt(trap.level||trap.lvl,0)===1);
}
function pseudoMoves(state,index,special,includeKing,ignore){
  const board=state.board,piece=board[index];if(!piece)return [];
  const file=index%8,rank=Math.floor(index/8),moves=[];
  function canHit(target){return !!target&&target.c!==piece.c&&(includeKing||target.t!=='K');}
  if(piece.t==='P'){
    const direction=piece.c==='W'?1:-1,start=piece.c==='W'?1:6;
    if(piece.barbarian){
      for(let step=1;step<=2;step++){
        const nextRank=rank+direction*step;if(!validCoord(file,nextRank)||board[nextRank*8+file])break;
        moves.push(nextRank*8+file);
      }
    }else if(validCoord(file,rank+direction)&&!board[(rank+direction)*8+file]){
      moves.push((rank+direction)*8+file);
      if(rank===start&&!board[(rank+2*direction)*8+file])moves.push((rank+2*direction)*8+file);
    }
    for(const deltaFile of [-1,1]){
      const nextFile=file+deltaFile,nextRank=rank+direction;if(!validCoord(nextFile,nextRank))continue;
      const targetIndex=nextRank*8+nextFile,target=board[targetIndex];
      const epVictim=rank*8+nextFile;
      const canEnPassant=special&&!piece.barbarian&&
        !target&&state.epTarget===targetIndex&&
        board[epVictim]&&board[epVictim].c!==piece.c&&board[epVictim].t==='P'&&
        !board[epVictim].barbarian&&safeInt(board[epVictim].resist,0)<=0;
      if(canHit(target)||canEnPassant)moves.push(targetIndex);
    }
    return moves;
  }
  if(piece.t==='N'||piece.t==='K'){
    let offsets=piece.t==='N'?KNIGHT_OFFSETS:KING_OFFSETS;
    if(piece.t==='N'&&piece.angryN){const forward=piece.c==='W'?3:-3;offsets=[[1,forward],[-1,forward]];}
    offsets.forEach(function(offset){
      const nextFile=file+offset[0],nextRank=rank+offset[1];if(!validCoord(nextFile,nextRank))return;
      const target=board[nextRank*8+nextFile];if(!target||canHit(target))moves.push(nextRank*8+nextFile);
    });
    if(piece.t==='K'&&special&&!piece.moved){
      const enemy=otherColor(piece.c),homeRank=piece.c==='W'?0:7;
      if(index===homeRank*8+4&&!attacked(state,index,enemy)){
        const kingRook=board[homeRank*8+7];
        if(kingRook&&kingRook.t==='R'&&kingRook.c===piece.c&&!kingRook.moved&&!board[homeRank*8+5]&&!board[homeRank*8+6]&&
          !attacked(state,homeRank*8+5,enemy)&&!attacked(state,homeRank*8+6,enemy)&&
          !castBlocked(state,homeRank*8+5,piece.c,ignore)&&!castBlocked(state,homeRank*8+6,piece.c,ignore))moves.push(homeRank*8+6);
        const queenRook=board[homeRank*8];
        if(queenRook&&queenRook.t==='R'&&queenRook.c===piece.c&&!queenRook.moved&&!board[homeRank*8+1]&&!board[homeRank*8+2]&&!board[homeRank*8+3]&&
          !attacked(state,homeRank*8+2,enemy)&&!attacked(state,homeRank*8+3,enemy)&&
          !castBlocked(state,homeRank*8+1,piece.c,ignore)&&!castBlocked(state,homeRank*8+2,piece.c,ignore)&&!castBlocked(state,homeRank*8+3,piece.c,ignore))moves.push(homeRank*8+2);
      }
    }
    return moves;
  }
  const directions=[];
  if(piece.t==='R'||piece.t==='Q')directions.push([1,0],[-1,0],[0,1],[0,-1]);
  if(piece.t==='B'||piece.t==='Q')directions.push([1,1],[1,-1],[-1,1],[-1,-1]);
  directions.forEach(function(direction){
    let nextFile=file+direction[0],nextRank=rank+direction[1];
    while(validCoord(nextFile,nextRank)){
      const targetIndex=nextRank*8+nextFile,target=board[targetIndex];
      if(!target)moves.push(targetIndex);else{if(canHit(target))moves.push(targetIndex);break;}
      nextFile+=direction[0];nextRank+=direction[1];
    }
  });
  if(piece.t==='B'&&piece.angryB){
    [-1,1].forEach(function(delta){const nextFile=file+delta;if(!validCoord(nextFile,rank))return;const target=board[rank*8+nextFile];if(!target||canHit(target))moves.push(rank*8+nextFile);});
  }
  return moves;
}
function attacked(state,square,byColor){
  if(!validSquare(square))return false;
  const squareFile=square%8,squareRank=Math.floor(square/8);
  for(let index=0;index<64;index++){
    const piece=state.board[index];if(!piece||piece.c!==byColor)continue;
    if(piece.t==='P'){
      const file=index%8,rank=Math.floor(index/8),direction=piece.c==='W'?1:-1;
      if(rank+direction===squareRank&&(file-1===squareFile||file+1===squareFile))return true;
    }else if(pseudoMoves(state,index,false,true,false).includes(square))return true;
  }
  return false;
}
function legalMoves(state,index,ignoreCardBlocks){
  hydrateMatch(state);
  const piece=state.board[index];if(!piece)return [];
  if(!ignoreCardBlocks&&((safeInt(piece.frozen,0)>0)||(safeInt(piece.plagueUntil,0)>safeInt(state.moveCount,0))||(safeInt(piece.trapped,0)>0)||piece.resistLock))return [];
  if(piece.ghost)return [];
  if(findKing(state.board,piece.c)<0)return [];
  let candidates=pseudoMoves(state,index,true,false,ignoreCardBlocks);
  if(piece.poisoned&&piece.t==='Q'){
    const fromFile=index%8,fromRank=Math.floor(index/8);
    candidates=candidates.filter(function(target){return Math.abs(target%8-fromFile)<=1&&Math.abs(Math.floor(target/8)-fromRank)<=1;});
  }
  return candidates.filter(function(target){
    if(!ignoreCardBlocks&&castBlocked(state,target,piece.c,false))return false;
    const occupied=state.board[target];if(!ignoreCardBlocks&&occupied&&safeInt(occupied.resist,0)>0&&occupied.c!==piece.c)return false;
    const simulation=Object.assign({},state,{board:cloneBoard(state.board)}),moving=simulation.board[index];
    if(moving.t==='P'&&target%8!==index%8&&!simulation.board[target]&&state.epTarget===target){
      const capturedIndex=Math.floor(index/8)*8+(target%8),captured=simulation.board[capturedIndex];
      if(captured&&captured.t==='P'&&!captured.barbarian&&safeInt(captured.resist,0)<=0)simulation.board[capturedIndex]=null;
    }
    simulation.board[target]=moving;simulation.board[index]=null;
    const landingTrap=state.traps[target];
    if(landingTrap&&safeInt(landingTrap.level||landingTrap.lvl,0)>=3&&moving.t!=='K')simulation.board[target]=null;
    if(piece.linkTo!==undefined&&piece.linkTo!==null)return linkedMoveAllowed(state,index,target);
    const king=findKing(simulation.board,piece.c);
    if(king<0||attacked(simulation,king,otherColor(piece.c)))return false;
    return true;
  });
}

function linkedMoveAllowed(state,from,to){
  const moving=state.board[from];
  if(!moving||moving.t!=='P'||moving.linkTo===undefined||moving.linkTo===null)return true;
  const linkedIndex=Number(moving.linkTo),mate=validSquare(linkedIndex)?state.board[linkedIndex]:null;
  if(!mate||mate.t!=='P'||mate.c!==moving.c||mate.linkTo!==from)return false;
  const deltaFile=to%8-from%8,deltaRank=Math.floor(to/8)-Math.floor(from/8);
  const nextFile=linkedIndex%8+deltaFile,nextRank=Math.floor(linkedIndex/8)+deltaRank;
  if(!validCoord(nextFile,nextRank))return false;
  const destination=nextRank*8+nextFile;
  if(destination===to||castBlocked(state,destination,moving.c,false))return false;
  const occupied=state.board[destination];
  if(occupied&&(occupied.c===moving.c||occupied.t==='K'||safeInt(occupied.resist,0)>0))return false;
  const simulation=Object.assign({},state,{board:cloneBoard(state.board)});
  simulation.board[from]=null;simulation.board[linkedIndex]=null;
  simulation.board[to]=Object.assign({},moving);
  simulation.board[destination]=Object.assign({},mate);
  const mainTrap=state.traps[to],mateTrap=state.traps[destination];
  if(mainTrap&&safeInt(mainTrap.level||mainTrap.lvl,0)>=3&&simulation.board[to].t!=='K')simulation.board[to]=null;
  if(mateTrap&&safeInt(mateTrap.level||mateTrap.lvl,0)>=3&&simulation.board[destination].t!=='K')simulation.board[destination]=null;
  const king=findKing(simulation.board,moving.c);
  return king>=0&&!attacked(simulation,king,otherColor(moving.c));
}
function allLegalMoves(state,color,ignoreCardBlocks){
  const moves=[];
  for(let index=0;index<64;index++)if(state.board[index]&&state.board[index].c===color)legalMoves(state,index,ignoreCardBlocks).forEach(function(target){moves.push([index,target]);});
  return moves;
}
function squareName(index){return String.fromCharCode(97+index%8)+String(Math.floor(index/8)+1);}
function boardToFen(state){
  const rows=[];
  for(let rank=7;rank>=0;rank--){
    let row='',empty=0;
    for(let file=0;file<8;file++){
      const piece=state.board[rank*8+file];
      if(!piece){empty++;continue;}
      if(empty){row+=String(empty);empty=0;}
      row+=piece.c==='W'?piece.t:piece.t.toLowerCase();
    }
    if(empty)row+=String(empty);rows.push(row);
  }
  let castling='';
  const wk=state.board[4],bk=state.board[60];
  if(wk&&wk.t==='K'&&wk.c==='W'&&!wk.moved){const wrH=state.board[7],wrA=state.board[0];if(wrH&&wrH.t==='R'&&wrH.c==='W'&&!wrH.moved)castling+='K';if(wrA&&wrA.t==='R'&&wrA.c==='W'&&!wrA.moved)castling+='Q';}
  if(bk&&bk.t==='K'&&bk.c==='B'&&!bk.moved){const brH=state.board[63],brA=state.board[56];if(brH&&brH.t==='R'&&brH.c==='B'&&!brH.moved)castling+='k';if(brA&&brA.t==='R'&&brA.c==='B'&&!brA.moved)castling+='q';}
  return rows.join('/')+' '+(state.turn==='W'?'w':'b')+' '+(castling||'-')+' '+(validSquare(state.epTarget)?squareName(state.epTarget):'-')+' '+safeInt(state.halfMove,0)+' '+(Math.floor(safeInt(state.moveCount,0)/2)+1);
}
function isPureStandardState(state){
  if(Object.keys(compactObject(state.traps)).length||Object.keys(compactObject(state.blocks)).length||Object.keys(compactObject(state.pits)).length||Object.keys(compactObject(state.shields)).length)return false;
  if(safeInt(state.fog&&state.fog.W,0)||safeInt(state.fog&&state.fog.B,0)||safeInt(state.cardBlock&&state.cardBlock.W,0)||safeInt(state.cardBlock&&state.cardBlock.B,0))return false;
  for(const piece of state.board){
    if(!piece)continue;
    for(const key of Object.keys(piece))if(!['t','c','moved'].includes(key)&&piece[key])return false;
  }
  return true;
}
function chessJsAcceptsMove(state,from,to,promotion){
  if(!isPureStandardState(state))return true;
  const moving=state.board[from];
  if(!moving)return false;
  const reachesPromotion=moving.t==='P'&&((moving.c==='W'&&to>=56)||(moving.c==='B'&&to<8));
  if(reachesPromotion){
    if(!PROMOTIONS.has(String(promotion===null||promotion===undefined?'':promotion).toUpperCase()))return false;
  }else if(promotion!==null&&promotion!==undefined)return false;
  try{
    const chess=new Chess(boardToFen(state));
    const move={from:squareName(from),to:squareName(to)};
    if(promotion!==null&&promotion!==undefined)move.promotion=String(promotion).toLowerCase();
    return !!chess.move(move);
  }catch(error){return false;}
}
function capturePiece(state,color,piece){
  if(!piece)return;
  state.captures[color].push(piece.t);
  state.metrics[color].captures=safeInt(state.metrics[color].captures,0)+1;
  if(piece.linkTo!==undefined&&piece.linkTo!==null&&state.board[piece.linkTo])delete state.board[piece.linkTo].linkTo;
}
function triggerTrap(state,index){
  const trap=state.traps[index],piece=state.board[index];
  if(!trap||!piece||safeInt(trap.level||trap.lvl,0)<2)return;
  delete state.traps[index];
  const level=safeInt(trap.level||trap.lvl,1);
  if(level===2||piece.t==='K'){
    piece.trapped=2;
    return;
  }
  capturePiece(state,trap.by,piece);
  state.board[index]=null;
}
function applyLinkedPawn(state,linkedIndex,from,to){
  const mate=state.board[linkedIndex],mover=state.board[to];if(!mate||mate.t!=='P'||!mover||mate.c!==mover.c)return;
  if(mate.linkTo!==from){delete mover.linkTo;return;}
  const deltaFile=to%8-from%8,deltaRank=Math.floor(to/8)-Math.floor(from/8),nextFile=linkedIndex%8+deltaFile,nextRank=Math.floor(linkedIndex/8)+deltaRank;
  if(!validCoord(nextFile,nextRank))return;
  const destination=nextRank*8+nextFile;if(destination===to)return;
  const occupied=state.board[destination];if(occupied&&occupied.c===mate.c)return;
  if(occupied&&occupied.t==='K')return;
  if(castBlocked(state,destination,mate.c,false))return;
  if(occupied&&safeInt(occupied.resist,0)>0)return;
  const simulation=Object.assign({},state,{board:cloneBoard(state.board)});
  simulation.board[destination]=simulation.board[linkedIndex];simulation.board[linkedIndex]=null;
  const king=findKing(simulation.board,mate.c);if(king<0||attacked(simulation,king,otherColor(mate.c)))return;
  if(occupied)capturePiece(state,mate.c,occupied);
  state.board[destination]=mate;state.board[linkedIndex]=null;mover.linkTo=destination;mate.linkTo=to;mate.moved=true;
  if((mate.c==='W'&&nextRank===7)||(mate.c==='B'&&nextRank===0)){mate.t='Q';delete mate.linkTo;delete mover.linkTo;}
  triggerTrap(state,destination);
  return occupied != null;
}
function applyMove(state,from,to,promotion){
  if(!validSquare(from)||!validSquare(to))throw rankedError('invalid-square','Move square is invalid.');
  const moving=state.board[from];if(!moving||moving.c!==state.turn)throw rankedError('invalid-piece','The selected piece cannot move for this player.');
  const legal=legalMoves(state,from,false);if(!legal.includes(to))throw rankedError('illegal-move','The move is not legal in the authoritative position.');
  if(!linkedMoveAllowed(state,from,to))throw rankedError('illegal-linked-move','A linked pawn cannot complete this move safely.');
  const originalType=moving.t;
  const reachesPromotion=originalType==='P'&&((moving.c==='W'&&to>=56)||(moving.c==='B'&&to<8));
  if(reachesPromotion){
    promotion=promotion===null||promotion===undefined?'':String(promotion).toUpperCase();
    if(!PROMOTIONS.has(promotion))throw rankedError('invalid-promotion','A promotion piece is required.');
  }else if(promotion!==null&&promotion!==undefined){
    throw rankedError('invalid-promotion','Only pawns may be promoted.');
  }else promotion=null;
  if(!chessJsAcceptsMove(state,from,to,promotion))throw rankedError('rules-engine-disagreement','Move was rejected by the standard chess rules engine.');
  const fromFile=from%8,toFile=to%8,fromRank=Math.floor(from/8),linkedIndex=moving.t==='P'&&moving.linkTo!==undefined?moving.linkTo:null;
  let captured=state.board[to],enPassant=false;
  if(captured&&captured.t==='K')throw rankedError('king-capture-forbidden','Kings are never captured.');
  if(moving.t==='P'&&fromFile!==toFile&&!captured&&state.epTarget===to){
    const captureIndex=fromRank*8+toFile,candidate=state.board[captureIndex];
    if(candidate&&candidate.t==='P'&&!candidate.barbarian&&safeInt(candidate.resist,0)<=0){captured=candidate;state.board[captureIndex]=null;enPassant=true;}
  }
  if(moving.t==='K'&&Math.abs(toFile-fromFile)===2){
    if(toFile===6){state.board[fromRank*8+5]=state.board[fromRank*8+7];state.board[fromRank*8+7]=null;if(state.board[fromRank*8+5])state.board[fromRank*8+5].moved=true;}
    else{state.board[fromRank*8+3]=state.board[fromRank*8];state.board[fromRank*8]=null;if(state.board[fromRank*8+3])state.board[fromRank*8+3].moved=true;}
  }
  if(captured)capturePiece(state,moving.c,captured);
  state.board[to]=moving;state.board[from]=null;moving.moved=true;
  let promoted=false;
  if(reachesPromotion){moving.t=promotion;promoted=true;if(moving.linkTo!==undefined){if(state.board[moving.linkTo])delete state.board[moving.linkTo].linkTo;delete moving.linkTo;}}
  state.epTarget=-1;if(originalType==='P'&&!moving.barbarian&&Math.abs(to-from)===16)state.epTarget=(from+to)/2;
  state.halfMove=originalType==='P'||captured?0:safeInt(state.halfMove,0)+1;
  triggerTrap(state,to);
  if(linkedIndex!==null&&!promoted)applyLinkedPawn(state,linkedIndex,from,to);
  const pit=state.pits[to];
  if(pit&&pit!==moving.c){delete state.pits[to];state.board[from]=state.board[to];state.board[to]=captured||null;state.epTarget=-1;return {from,to,promotion,captured:captured&&captured.t||null,enPassant,pit:true,promoted};}
  return {from,to,promotion,captured:captured&&captured.t||null,enPassant,promoted};
}

function targetAllowed(state,definition,target,color,secondaryTarget){
  if(definition.target==='none')return target===null||target===undefined||target===-1;
  if(!validSquare(target))return false;
  const piece=state.board[target],enemy=otherColor(color);
  if(definition.target==='enemy')return !!piece&&piece.c===enemy&&piece.t!=='K'&&safeInt(piece.resist,0)<=0;
  if(definition.target==='enemy_queen')return !!piece&&piece.c===enemy&&piece.t==='Q'&&safeInt(piece.resist,0)<=0;
  if(definition.target==='own_pawn')return !!piece&&piece.c===color&&piece.t==='P';
  if(definition.target==='own_knight')return !!piece&&piece.c===color&&piece.t==='N';
  if(definition.target==='own_bishop')return !!piece&&piece.c===color&&piece.t==='B';
  if(definition.target==='own_kn_bi')return !!piece&&piece.c===color&&(piece.t==='N'||piece.t==='B');
  if(definition.target==='own_piece')return !!piece&&piece.c===color&&piece.t!=='K';
  if(definition.target==='empty')return !piece&&!castBlocked(state,target,color,false)&&!state.traps[target]&&!state.shields[target];
  if(definition.target==='empty_own')return !piece&&!castBlocked(state,target,color,false)&&!state.traps[target]&&!state.shields[target]&&(color==='W'?target<32:target>=32);
  if(definition.target==='own_pawn_pair'){
    if(!piece||piece.c!==color||piece.t!=='P'||!validSquare(secondaryTarget))return false;
    const second=state.board[secondaryTarget];return !!second&&second.c===color&&second.t==='P'&&(piece.linkTo===undefined||piece.linkTo===null)&&(second.linkTo===undefined||second.linkTo===null)&&Math.floor(target/8)===Math.floor(secondaryTarget/8)&&Math.abs(target%8-secondaryTarget%8)===1;
  }
  return false;
}
function revealTraps(state,color,level){
  const enemy=otherColor(color);let count=0;
  Object.keys(state.traps).forEach(function(key){
    const trap=state.traps[key];if(!trap||trap.by!==enemy||safeInt(state.fog[enemy],0)>0)return;
    const index=Number(key),rank=Math.floor(index/8),ownLow=color==='W'?0:4,ownHigh=color==='W'?3:7;
    const inRegion=level>=3||(level===1&&rank>=ownLow&&rank<=ownHigh)||(level===2&&(rank>=ownLow&&rank<=ownHigh||rank===3||rank===4));
    if(inRegion){trap.revealedBy=color;count++;}
  });
  return count;
}
function archerTargets(state,index,color){
  const file=index%8,rank=Math.floor(index/8),forward=color==='W'?1:-1,targets=[];
  [-1,1].forEach(function(delta){const nextFile=file+delta,nextRank=rank+forward;if(!validCoord(nextFile,nextRank))return;const targetIndex=nextRank*8+nextFile,piece=state.board[targetIndex];if(piece&&piece.c!==color&&piece.t!=='K'&&safeInt(piece.resist,0)<=0)targets.push(targetIndex);});
  return targets;
}
function reinforce(state,index,color){
  const file=index%8,rank=Math.floor(index/8),back=color==='W'?-1:1;let made=0;
  for(let step=1;step<=3;step++){
    const nextRank=rank+back*step;if(!validCoord(file,nextRank))break;
    const target=nextRank*8+file;
    if(state.board[target]||state.blocks[target]||state.traps[target]||state.shields[target])break;
    state.board[target]={t:'P',c:color,moved:true};made++;
  }
  return made>0;
}
function spawnGhosts(state,color){
  const king=findKing(state.board,color);if(king<0)return false;
  const file=king%8,rank=Math.floor(king/8),nextRank=rank+(color==='W'?1:-1);if(nextRank<0||nextRank>7)return false;
  let placed=0;
  [0,-1,1].forEach(function(delta){
    if(placed>=2)return;const nextFile=file+delta;if(!validCoord(nextFile,nextRank))return;
    const target=nextRank*8+nextFile;
    if(state.board[target]||state.blocks[target]||state.shields[target]||state.traps[target])return;
    state.board[target]={t:'P',c:color,moved:true,ghost:true,ghostDur:3};placed++;
  });
  return placed>0;
}
function resolveHandCard(state,color,requested){
  const definition=CARDS[requested];if(!definition)return null;
  const hand=state.hands[color]||[];
  if(hand.includes(requested))return requested;
  if(!definition.family)return null;
  const held=hand.find(function(key){
    if(key===definition.family)return safeInt(definition.level,1)===1;
    const card=CARDS[key];
    return card&&card.family===definition.family&&safeInt(card.level,1)>=safeInt(definition.level,1);
  });
  return held?requested:null;
}
function applyCard(state,color,key,target,secondaryTarget){
  const definition=CARDS[key];if(!definition)throw rankedError('unknown-card','Card is not in the ranked catalog.');
  if(!targetAllowed(state,definition,target,color,secondaryTarget))throw rankedError('invalid-card-target','Card target is invalid.');
  const enemy=otherColor(color);
  if(definition.skipMove){const king=findKing(state.board,color);if(king>=0&&attacked(state,king,enemy))throw rankedError('king-in-check','A skip-move card cannot be used while the king is in check.');}
  if(key.startsWith('trap'))state.traps[target]={by:color,duration:definition.duration,level:definition.level,life:definition.duration*2};
  else if(key.startsWith('radar'))revealTraps(state,color,definition.level);
  else if(key.startsWith('resist')){state.board[target].resist=1;state.board[target].resistLock=true;}
  else if(key.startsWith('deploy'))state.board[target]={t:definition.piece,c:color,moved:true,resistLock:true};
  else if(key.startsWith('shield'))state.shields[target]={by:color,duration:definition.duration*2};
  else if(key==='freeze')state.board[target].frozen=definition.duration+1;
  else if(key==='poison_q'){state.board[target].poisoned=true;state.board[target].poisonedDur=2;}
  else if(key==='card_block')state.cardBlock[enemy]=definition.duration+1;
  else if(key==='medium')state.mediumReveal[color]=safeInt(state.moveCount,0)+1;
  else if(key==='barbarian')state.board[target].barbarian=true;
  else if(key==='glue'){state.board[target].linkTo=secondaryTarget;state.board[secondaryTarget].linkTo=target;}
  else if(key==='archer'){
    const targets=archerTargets(state,target,color);if(!targets.length)throw rankedError('no-archer-target','Archer pawn has no valid target.');
    targets.sort(function(first,second){const value=PIECE_VALUES[state.board[second].t]-PIECE_VALUES[state.board[first].t];return value||first-second;});
    const victim=state.board[targets[0]];capturePiece(state,color,victim);state.board[targets[0]]=null;
  }
  else if(key==='fog')state.fog[color]=definition.duration+1;
  else if(key==='angry_n')state.board[target].angryN=true;
  else if(key==='angry_b')state.board[target].angryB=true;
  else if(key==='plague'){
    for(const piece of state.board){
      if(piece&&piece.t==='P'&&safeInt(piece.resist,0)<=0)piece.plagueUntil=Math.max(safeInt(piece.plagueUntil,0),safeInt(state.moveCount,0)+2);
    }
  }
  else if(key==='reinforce'){
    if(!reinforce(state,target,color))throw rankedError('no-reinforce-space','No pawn can be created behind this pawn.');
  }
  else if(key==='ghosts'){
    if(!spawnGhosts(state,color))throw rankedError('no-ghost-space','No ghost pawn can be created.');
  }
  else if(key==='immunity'){const piece=state.board[target];piece.frozen=0;piece.plagueUntil=0;piece.poisoned=false;piece.poisonedDur=0;piece.trapped=0;}
  return definition;
}
function advanceTurnEffects(state){
  for(let index=0;index<64;index++){
    const piece=state.board[index];if(!piece)continue;
    if(safeInt(piece.plagueUntil,0)>0&&safeInt(piece.plagueUntil,0)<=safeInt(state.moveCount,0))piece.plagueUntil=0;
    if(piece.c===state.turn){
      if(safeInt(piece.frozen,0)>0)piece.frozen--;
      if(safeInt(piece.trapped,0)>0)piece.trapped--;
      if(safeInt(piece.resist,0)>0)piece.resist--;
      if(piece.ghost){piece.ghostDur=safeInt(piece.ghostDur,0)-1;if(piece.ghostDur<=0){state.board[index]=null;continue;}}
      if(safeInt(piece.poisonedDur,0)>0){piece.poisonedDur--;if(piece.poisonedDur<=0){piece.poisoned=false;piece.poisonedDur=0;}}
    }else{piece.resistLock=false;piece.angryN=false;piece.angryB=false;piece.archer=false;}
  }
  Object.keys(state.blocks).forEach(function(key){state.blocks[key]=safeInt(state.blocks[key],0)-1;if(state.blocks[key]<=0)delete state.blocks[key];});
  Object.keys(state.traps).forEach(function(key){const trap=state.traps[key];trap.life=safeInt(trap.life,12)-1;if(trap.life<=0)delete state.traps[key];});
  Object.keys(state.shields).forEach(function(key){const shield=state.shields[key];shield.duration=safeInt(shield.duration||shield.dur,0)-1;if(shield.duration<=0)delete state.shields[key];});
  if(safeInt(state.cardBlock[state.turn],0)>0)state.cardBlock[state.turn]--;
  if(safeInt(state.fog[state.turn],0)>0)state.fog[state.turn]--;
  state.mana[state.turn]=Math.min(10,safeInt(state.mana[state.turn],0)+1);state.cardUsed=false;
}
function positionKey(state){
  let board='';for(const piece of state.board)board+=piece?(piece.c==='W'?piece.t:piece.t.toLowerCase()):'.';
  function unmoved(square,type,color){const piece=state.board[square];return piece&&piece.t===type&&piece.c===color&&!piece.moved?'1':'0';}
  let ep=-1;
  if(validSquare(state.epTarget)&&!state.board[state.epTarget]){
    const targetFile=state.epTarget%8,targetRank=Math.floor(state.epTarget/8),sourceRank=targetRank+(state.turn==='W'?-1:1),victim=sourceRank*8+targetFile;
    const captured=validSquare(victim)?state.board[victim]:null;
    if(captured&&captured.t==='P'&&captured.c!==state.turn){
      for(const deltaFile of [-1,1]){
        const sourceFile=targetFile+deltaFile;
        if(!validCoord(sourceFile,sourceRank))continue;
        const source=sourceRank*8+sourceFile,piece=state.board[source];
        if(piece&&piece.t==='P'&&piece.c===state.turn&&legalMoves(state,source,false).includes(state.epTarget)){ep=state.epTarget;break;}
      }
    }
  }
  const signature=board+'|'+state.turn+'|'+ep+'|'+unmoved(4,'K','W')+unmoved(0,'R','W')+unmoved(7,'R','W')+unmoved(60,'K','B')+unmoved(56,'R','B')+unmoved(63,'R','B');
  return Buffer.from(signature,'utf8').toString('base64url');
}
function variantPositionKey(state){
  if(isPureStandardState(state))return positionKey(state);
  const board=state.board.map(function(piece){
    if(!piece)return null;
    return [piece.t,piece.c,piece.moved===true?1:0,safeInt(piece.frozen,0),safeInt(piece.resist,0),
      piece.resistLock===true?1:0,piece.barbarian===true?1:0,piece.poisoned===true?1:0,
      safeInt(piece.poisonedDur,0),safeInt(piece.plagueUntil,0),safeInt(piece.trapped,0),
      piece.angryN===true?1:0,piece.angryB===true?1:0,piece.ghost===true?1:0,
      safeInt(piece.ghostDur,0),piece.linkTo===undefined||piece.linkTo===null?-1:safeInt(piece.linkTo,-1)];
  });
  const sortedEntries=function(value,mapper){
    return Object.keys(compactObject(value)).sort(function(a,b){return Number(a)-Number(b);}).map(mapper);
  };
  const signature={
    board,turn:state.turn,ep:state.epTarget,mana:state.mana,cardBlock:state.cardBlock,
    fog:state.fog,mediumReveal:state.mediumReveal,hands:state.hands,cardUsed:state.cardUsed,
    traps:sortedEntries(state.traps,function(key){const trap=state.traps[key]||{};return [key,trap.by,safeInt(trap.duration||trap.dur,0),safeInt(trap.level||trap.lvl,0),safeInt(trap.life,0),trap.revealedBy||null];}),
    shields:sortedEntries(state.shields,function(key){const shield=state.shields[key]||{};return [key,shield.by,safeInt(shield.duration||shield.dur,0)];}),
    blocks:sortedEntries(state.blocks,function(key){return [key,safeInt(state.blocks[key],0)];}),
    pits:sortedEntries(state.pits,function(key){return [key,state.pits[key]];})
  };
  return Buffer.from(JSON.stringify(signature),'utf8').toString('base64url');
}
function insufficientMaterial(state){
  const bishops=[];let minors=0;
  for(let square=0;square<64;square++){
    const piece=state.board[square];if(!piece||piece.t==='K')continue;
    if(piece.t==='B'){bishops.push(square);minors++;}else if(piece.t==='N')minors++;else return false;
  }
  if(minors<=1)return true;
  if(bishops.length===minors){const colors=new Set(bishops.map(function(square){return (square%8+Math.floor(square/8))&1;}));return colors.size===1;}
  return false;
}
function onlyBlockedByEffects(state,color){return allLegalMoves(state,color,false).length===0&&allLegalMoves(state,color,true).length>0;}
function finishResult(state,winner,reason,at,type){
  if(state.result)return state.result;
  state.status=type==='cancelled'?'cancelled':'finished';
  state.settlementStatus='pending';
  state.result={winner:winner||'draw',reason:String(reason||'completed').slice(0,80),type:type||'completed',finishedAt:at,sequence:safeInt(state.sequence,0)};
  state.drawOffer=null;state.cancelOffer=null;
  state.clock.activeColor=null;state.clock.startedAt=at;state.clock.deadlineAt=0;
  return state.result;
}
function evaluateGameEnd(state,at){
  for(let passes=0;passes<8;passes++){
    const moves=allLegalMoves(state,state.turn,false),king=findKing(state.board,state.turn),inCheck=king>=0&&attacked(state,king,otherColor(state.turn));
    if(moves.length){
      if(isPureStandardState(state)){
        if(insufficientMaterial(state))return finishResult(state,'draw','dead-position',at);
        if(state.halfMove>=150)return finishResult(state,'draw','seventy-five-move-rule',at);
        const key=variantPositionKey(state);state.positionCounts[key]=safeInt(state.positionCounts[key],0)+1;
        if(state.positionCounts[key]>=5)return finishResult(state,'draw','fivefold-repetition',at);
      }else{
        if(state.halfMove>=100)return finishResult(state,'draw','fifty-move-rule',at);
        if(insufficientMaterial(state))return finishResult(state,'draw','insufficient-material',at);
        const key=variantPositionKey(state);state.positionCounts[key]=safeInt(state.positionCounts[key],0)+1;
        if(state.positionCounts[key]>=3)return finishResult(state,'draw','threefold-repetition',at);
      }
      return null;
    }
    if(onlyBlockedByEffects(state,state.turn)){
      state.epTarget=-1;state.moveCount=safeInt(state.moveCount,0)+1;state.turn=otherColor(state.turn);advanceTurnEffects(state);state.phase='card';continue;
    }
    return finishResult(state,inCheck?otherColor(state.turn):'draw',inCheck?'checkmate':'stalemate',at);
  }
  return finishResult(state,'draw','effect-lock',at);
}
function switchTurn(state,at){
  state.moveCount=safeInt(state.moveCount,0)+1;state.turn=otherColor(state.turn);advanceTurnEffects(state);state.phase='card';
  if(state.moveCount>=3)state.cancelOffer=null;
  state.clock.activeColor=state.turn;state.clock.startedAt=at;state.clock.deadlineAt=at+safeInt(state.clock[state.turn],0);
  return evaluateGameEnd(state,at);
}
function settleClock(state,at){
  if(state.status!=='active'||state.result)return state.result;
  const clock=state.clock||{},color=clock.activeColor||state.turn;if(!['W','B'].includes(color))return null;
  const startedAt=safeInt(clock.startedAt,at),elapsed=Math.max(0,at-startedAt),remaining=Math.max(0,safeInt(clock[color],MATCH_DURATION_MS)-elapsed);
  clock[color]=remaining;clock.activeColor=color;clock.startedAt=at;clock.deadlineAt=at+remaining;state.clock=clock;
  if(remaining<=0)return finishResult(state,otherColor(color),'timeout',at);
  return null;
}
function updatePresence(state,uid,at,status){
  if(!state.participants||state.participants[uid]!==true)throw rankedError('not-a-participant','Player is not in this match.');
  state.presence[uid]={state:status||'CONNECTED',lastSeenAt:at,disconnectedAt:0,graceUntil:0};
}
function expireOffers(state,at){
  if(state.drawOffer&&safeInt(state.drawOffer.expiresAt,0)<=at)state.drawOffer=null;
  if(state.cancelOffer&&(safeInt(state.cancelOffer.expiresAt,0)<=at||safeInt(state.moveCount,0)>=3))state.cancelOffer=null;
}
function sweepConnections(state,at){
  if(state.status!=='active'||state.result)return state.result;
  const stale=[];
  Object.keys(state.participants||{}).forEach(function(uid){
    const presence=state.presence[uid]||{},lastSeen=safeInt(presence.lastSeenAt,state.createdAt);
    if(at-lastSeen>HEARTBEAT_STALE_MS){
      const graceUntil=lastSeen+RECONNECT_GRACE_MS;
      presence.state=at>=graceUntil?'FORFEITED':'TEMP_DISCONNECTED';presence.disconnectedAt=lastSeen;presence.graceUntil=graceUntil;state.presence[uid]=presence;
      if(at>=graceUntil)stale.push(uid);
    }
  });
  if(stale.length===2)return finishResult(state,'draw','both-disconnected',at);
  if(stale.length===1){const loserColor=state.colors[stale[0]];return finishResult(state,otherColor(loserColor),'disconnect-forfeit',at);}
  return null;
}
function rememberProcessed(state,actionId,result){
  state.processedActions[actionId]={sequence:state.sequence,result:result||null};
  const keys=Object.keys(state.processedActions);if(keys.length>MAX_PROCESSED_ACTIONS)keys.sort(function(a,b){return safeInt(state.processedActions[a].sequence,0)-safeInt(state.processedActions[b].sequence,0);}).slice(0,keys.length-MAX_PROCESSED_ACTIONS).forEach(function(key){delete state.processedActions[key];});
}
function appendEvent(state,event){
  state.events.push(event);if(state.events.length>MAX_EVENTS)state.events=state.events.slice(state.events.length-MAX_EVENTS);state.lastEvent=event;
}
function applyRankedAction(inputState,uid,action,at){
  const state=hydrateMatch(deepClone(inputState)),timestamp=safeInt(at,Date.now());
  if(!state||!state.participants||state.participants[uid]!==true)throw rankedError('not-a-participant','Player is not in this match.');
  if(!isRecord(action))throw rankedError('invalid-action','Action must be an object.');
  const actionId=String(action.actionId||'');if(!/^[A-Za-z0-9:_-]{8,160}$/.test(actionId))throw rankedError('invalid-action-id','Action id is invalid.');
  if(state.processedActions[actionId])return {state,idempotent:true,result:state.processedActions[actionId].result||state.result||null};
  if(state.status!=='active'||state.result)throw rankedError('match-finished','Ranked match is already complete.');
  const expected=Number(action.expectedSequence);if(!Number.isInteger(expected)||expected!==safeInt(state.sequence,0))throw rankedError('stale-sequence','Client state is stale.');
  settleClock(state,timestamp);if(state.result){rememberProcessed(state,actionId,state.result);return {state,idempotent:false,result:state.result};}
  // Sweep before restoring the caller's presence. Otherwise a client that was
  // offline beyond the reconnect grace window could revive itself by sending a
  // late move or surrender request.
  sweepConnections(state,timestamp);if(state.result){rememberProcessed(state,actionId,state.result);return {state,idempotent:false,result:state.result};}
  updatePresence(state,uid,timestamp,'CONNECTED');
  expireOffers(state,timestamp);
  const color=state.colors[uid],type=String(action.type||''),event={sequence:state.sequence+1,actionId,type,by:color,at:timestamp};
  if(['move','card','skip_card','claim_fifty_move','claim_threefold'].includes(type)&&state.turn!==color)throw rankedError('not-your-turn','It is not this player\'s turn.');
  if(type==='move'){
    if(!['card','move'].includes(state.phase))throw rankedError('invalid-phase','A move cannot be played in this phase.');
    const detail=applyMove(state,Number(action.from),Number(action.to),action.promotion);Object.assign(event,detail);
    if(detail.promoted)state.metrics[color].promotions=safeInt(state.metrics[color].promotions,0)+1;
    state.phase='move';switchTurn(state,timestamp);
    const checkedKing=findKing(state.board,state.turn);
    if(checkedKing>=0&&attacked(state,checkedKing,color)){
      state.metrics[color].checks=safeInt(state.metrics[color].checks,0)+1;
      event.check=true;
    }
  }else if(type==='card'){
    if(state.phase!=='card')throw rankedError('invalid-phase','Cards can only be played before the move.');
    if(state.cardUsed)throw rankedError('card-already-used','Only one card may be used each turn.');
    if(safeInt(state.cardBlock[color],0)>0)throw rankedError('cards-blocked','Cards are blocked for this turn.');
    const key=resolveHandCard(state,color,String(action.cardKey||''));if(!key)throw rankedError('card-not-in-deck','Card is not in the authoritative hand.');
    const definition=CARDS[key];if(safeInt(state.mana[color],0)<definition.mana)throw rankedError('insufficient-mana','Not enough authoritative mana.');
    applyCard(state,color,key,action.target===undefined?null:Number(action.target),action.secondaryTarget===undefined?null:Number(action.secondaryTarget));
    state.mana[color]-=definition.mana;state.cardUsed=true;state.lastCard[color]=key;
    state.metrics[color].cardsPlayed++;state.metrics[color].cardUsage[key]=safeInt(state.metrics[color].cardUsage[key],0)+1;if(LEGENDARY_CARDS.has(key))state.metrics[color].legendaryCards++;
    event.cardKey=key;event.target=action.target===undefined?null:Number(action.target);event.secondaryTarget=action.secondaryTarget===undefined?null:Number(action.secondaryTarget);event.hidden=definition.hidden===true;
    if(definition.skipMove){state.epTarget=-1;switchTurn(state,timestamp);}
  }else if(type==='skip_card'){
    if(state.phase!=='card')throw rankedError('invalid-phase','Card phase is already complete.');state.phase='move';
  }else if(type==='claim_fifty_move'){
    if(!isPureStandardState(state)||safeInt(state.halfMove,0)<100)throw rankedError('draw-claim-unavailable','The fifty-move draw is not claimable.');
    finishResult(state,'draw','fifty-move-claim',timestamp);
  }else if(type==='claim_threefold'){
    if(!isPureStandardState(state)||safeInt(state.positionCounts[positionKey(state)],0)<3)throw rankedError('draw-claim-unavailable','The threefold draw is not claimable.');
    finishResult(state,'draw','threefold-repetition-claim',timestamp);
  }else if(type==='resign')finishResult(state,otherColor(color),'resignation',timestamp);
  else if(type==='offer_draw'){
    if(state.cancelOffer)throw rankedError('cancel-offer-pending','Respond to the active cancellation offer first.');
    if(state.drawOffer)throw rankedError(state.drawOffer.by===uid?'draw-offer-already-active':'draw-offer-pending','Respond to the active draw offer first.');
    state.drawOffer={by:uid,color,offeredAt:timestamp,expiresAt:timestamp+DRAW_OFFER_MS};
  }
  else if(type==='accept_draw'){
    if(!state.drawOffer||state.drawOffer.by===uid||safeInt(state.drawOffer.expiresAt,0)<timestamp)throw rankedError('draw-offer-missing','There is no active opponent draw offer.');
    finishResult(state,'draw','draw-agreement',timestamp);
  }else if(type==='reject_draw'){if(state.drawOffer&&state.drawOffer.by!==uid)state.drawOffer=null;else throw rankedError('draw-offer-missing','There is no opponent draw offer.');}
  else if(type==='cancel_draw'){if(state.drawOffer&&state.drawOffer.by===uid)state.drawOffer=null;else throw rankedError('draw-offer-missing','There is no owned draw offer.');}
  else if(type==='offer_cancel'){
    if(state.moveCount>=3)throw rankedError('cancel-window-closed','Match cancellation is available only during the opening.');
    if(state.drawOffer)throw rankedError('draw-offer-pending','Respond to the active draw offer first.');
    if(state.cancelOffer)throw rankedError(state.cancelOffer.by===uid?'cancel-offer-already-active':'cancel-offer-pending','Respond to the active cancellation offer first.');
    state.cancelOffer={by:uid,color,offeredAt:timestamp,expiresAt:timestamp+DRAW_OFFER_MS};
  }else if(type==='accept_cancel'){
    if(!state.cancelOffer||state.cancelOffer.by===uid||safeInt(state.cancelOffer.expiresAt,0)<timestamp||state.moveCount>=3)throw rankedError('cancel-offer-missing','There is no valid opponent cancellation offer.');
    finishResult(state,'draw','mutual-cancellation',timestamp,'cancelled');
  }else if(type==='reject_cancel'){if(state.cancelOffer&&state.cancelOffer.by!==uid)state.cancelOffer=null;else throw rankedError('cancel-offer-missing','There is no opponent cancellation offer.');}
  else if(type==='cancel_cancel'){if(state.cancelOffer&&state.cancelOffer.by===uid)state.cancelOffer=null;else throw rankedError('cancel-offer-missing','There is no owned cancellation offer.');}
  else throw rankedError('unknown-action','Unknown ranked action.');
  state.sequence++;event.sequence=state.sequence;state.updatedAt=timestamp;
  appendEvent(state,event);rememberProcessed(state,actionId,state.result||null);
  return {state,idempotent:false,result:state.result||null,event};
}
function heartbeatRankedState(inputState,uid,at){
  const state=hydrateMatch(deepClone(inputState)),timestamp=safeInt(at,Date.now());
  if(!state||!state.participants||state.participants[uid]!==true)throw rankedError('not-a-participant','Player is not in this match.');
  if(state.status==='active'&&!state.result){
    settleClock(state,timestamp);
    if(!state.result){
      // The stale sweep must happen before the caller is marked connected.
      // This makes the reconnect grace period a real deadline.
      sweepConnections(state,timestamp);
      if(!state.result){updatePresence(state,uid,timestamp,'CONNECTED');expireOffers(state,timestamp);sweepConnections(state,timestamp);}
    }
  }
  state.updatedAt=timestamp;return state;
}
function sweepRankedState(inputState,at){
  const state=hydrateMatch(deepClone(inputState)),timestamp=safeInt(at,Date.now());
  if(state&&state.status==='active'&&!state.result){settleClock(state,timestamp);if(!state.result){expireOffers(state,timestamp);sweepConnections(state,timestamp);}state.updatedAt=timestamp;}
  return state;
}
function publicEvent(event,viewerColor){
  if(!event)return null;const output=Object.assign({},event);
  if(output.type==='card'&&output.by!==viewerColor&&output.hidden){output.cardKey='hidden';output.target=null;output.secondaryTarget=null;}
  delete output.hidden;delete output.actionId;return output;
}
function sanitizedTraps(state,viewerColor){
  const output={};Object.keys(state.traps).forEach(function(key){const trap=state.traps[key];if(trap.by===viewerColor||trap.revealedBy===viewerColor)output[key]=Object.assign({},trap);});return output;
}
function sanitizeMatchView(inputState,uid){
  const state=hydrateMatch(deepClone(inputState));if(!state.participants||state.participants[uid]!==true)throw rankedError('not-a-participant','Player is not in this match.');
  expireOffers(state,Date.now());
  const color=state.colors[uid],enemy=otherColor(color),enemyPlayer=state.players[enemy],ownPlayer=state.players[color],opponentUid=enemyPlayer.uid;
  const revealOpponent=safeInt(state.mediumReveal&&state.mediumReveal[color],0)>safeInt(state.moveCount,0);
  const opponentPresence=state.presence[opponentUid]||{};
  const visibleLastCard={W:null,B:null};visibleLastCard[color]=state.lastCard[color];visibleLastCard[enemy]=state.lastCard[enemy]?'played':null;
  const visibleMana={W:null,B:null};visibleMana[color]=safeInt(state.mana[color],0);if(revealOpponent)visibleMana[enemy]=safeInt(state.mana[enemy],0);
  const visibleFog={W:0,B:0};visibleFog[color]=safeInt(state.fog[color],0);
  return {
    schemaVersion:state.schemaVersion,matchId:state.matchId,status:state.status,mode:state.mode,
    timeControlMinutes:safeInt(state.timeControlMinutes,Math.round(safeInt(state.clock&&state.clock.initialMs||state.clock&&state.clock.W,MATCH_DURATION_MS)/60000)),
    viewerColor:color,sequence:state.sequence,serverNow:Date.now(),
    player:ownPlayer,opponent:enemyPlayer,board:state.board,turn:state.turn,phase:state.phase,moveCount:state.moveCount,halfMove:state.halfMove,epTarget:state.epTarget,
    hand:state.hands[color].slice(),opponentHandCount:state.hands[enemy].length,opponentHand:revealOpponent?state.hands[enemy].slice():null,
    mana:visibleMana,cardUsed:state.cardUsed,cardBlock:state.cardBlock,lastCard:visibleLastCard,
    traps:sanitizedTraps(state,color),blocks:state.blocks,pits:state.pits,shields:state.shields,fog:visibleFog,captures:state.captures,
    clock:state.clock,connection:{self:state.presence[uid]||{},opponent:opponentPresence},
    drawOffer:state.drawOffer?{bySelf:state.drawOffer.by===uid,offeredAt:state.drawOffer.offeredAt,expiresAt:state.drawOffer.expiresAt}:null,
    cancelOffer:state.cancelOffer?{bySelf:state.cancelOffer.by===uid,offeredAt:state.cancelOffer.offeredAt,expiresAt:state.cancelOffer.expiresAt}:null,
    lastEvent:publicEvent(state.lastEvent,color)||null,result:state.result||null,settlement:state.settlement[color]||null,updatedAt:state.updatedAt
  };
}
function sanitizeMatchReplay(inputState,uid){
  const state=hydrateMatch(deepClone(inputState));if(!state.participants||state.participants[uid]!==true)throw rankedError('not-a-participant','Player is not in this match.');
  const color=state.colors[uid];
  return {
    schemaVersion:state.schemaVersion,matchId:state.matchId,mode:state.mode,viewerColor:color,players:state.players,
    createdAt:state.createdAt,finishedAt:state.result&&state.result.finishedAt||0,result:state.result||null,
    events:state.events.map(function(event){return publicEvent(event,color);}),finalBoard:state.board,
    captures:state.captures,settlement:state.settlement[color]||null
  };
}

function arenaForTrophies(trophies){const normalized=safeInt(trophies,0);for(let index=ARENAS.length-1;index>=0;index--)if(normalized>=ARENAS[index].min)return index;return 0;}
function arenaIndexForProfile(profile){
  const trophies=safeInt(profile&&profile.trophies,0),trophyArena=arenaForTrophies(trophies);
  const storedArena=clamp(safeInt(profile&&profile.arenaIdx,trophyArena),0,ARENAS.length-1);
  return storedArena>trophyArena&&trophies>=ARENAS[storedArena].min?storedArena:trophyArena;
}
function deterministicInt(seed,max){if(max<=0)return 0;return parseInt(crypto.createHash('sha256').update(String(seed)).digest('hex').slice(0,12),16)%max;}
function levelThreshold(level){return Math.round(100*Math.pow(1.2,Math.max(0,level-1)));}
function pruneMissionPeriods(profile,category,periodId){
  if(category==='special')return;
  const periods=profile.serverProgress&&profile.serverProgress.missions&&profile.serverProgress.missions[category];
  if(!isRecord(periods))return;
  const rank=function(key){
    if(category==='daily'&&/^\d{4}-\d{2}-\d{2}$/.test(key))return Date.parse(key+'T00:00:00.000Z');
    if(category==='weekly'&&/^w\d+$/.test(key))return Number(key.slice(1));
    return null;
  };
  const entries=Object.keys(periods).map(function(key){return {key,value:rank(key)};}).filter(function(entry){return entry.value!==null&&!Number.isNaN(entry.value);});
  const limit=category==='daily'?14:8;
  if(entries.length<=limit)return;
  entries.sort(function(first,second){return first.value-second.value;});
  const keep=new Set(entries.slice(-limit).map(function(entry){return entry.key;}));
  Object.keys(periods).forEach(function(key){if(!keep.has(key))delete periods[key];});
}
function ensureMissionPeriod(profile,category,periodId){
  if(!isRecord(profile.serverProgress))profile.serverProgress={};if(!isRecord(profile.serverProgress.missions))profile.serverProgress.missions={};
  if(!isRecord(profile.serverProgress.missions[category]))profile.serverProgress.missions[category]={};
  pruneMissionPeriods(profile,category,periodId);
  if(!isRecord(profile.serverProgress.missions[category][periodId]))profile.serverProgress.missions[category][periodId]={counters:{}};
  const period=profile.serverProgress.missions[category][periodId];if(!isRecord(period.counters))period.counters={};
  if(category!=='special'&&!Array.isArray(period.selected))period.selected=deterministicMissionIds(profile,category,periodId);
  pruneMissionPeriods(profile,category,periodId);
  // A late settlement can fall outside retention; its other rewards still commit.
  return period.counters;
}
function incrementCounter(counters,key,amount){counters[key]=safeInt(counters[key],0)+safeInt(amount,0);}
function applyMissionProgress(profile,metrics,outcome,at){
  const periods=periodSnapshot(at),daily=ensureMissionPeriod(profile,'daily',periods.dayKey),weekly=ensureMissionPeriod(profile,'weekly',periods.weekKey);
  incrementCounter(daily,'d2',1);incrementCounter(daily,'d3',metrics.cardsPlayed);incrementCounter(daily,'d_cap',metrics.captures);incrementCounter(daily,'d_capture',metrics.captures);incrementCounter(daily,'d_checks',metrics.checks);incrementCounter(daily,'d_legend',metrics.legendaryCards);
  incrementCounter(weekly,'w2',metrics.legendaryCards);incrementCounter(weekly,'w3',metrics.captures);incrementCounter(weekly,'w_capture',metrics.captures);incrementCounter(weekly,'w_checks',metrics.checks);incrementCounter(weekly,'w_promote',metrics.promotions);incrementCounter(weekly,'w_cards',metrics.cardsPlayed);
  if(outcome==='draw'){incrementCounter(daily,'d_draw',1);incrementCounter(weekly,'w_draw',1);}
  if(outcome==='win'){incrementCounter(daily,'d1',1);incrementCounter(weekly,'w1',1);if(metrics.moveCount<30)incrementCounter(daily,'d4',1);weekly.w4=Math.max(safeInt(weekly.w4,0),safeInt(profile.stats&&profile.stats.winStreak,0));}
  Object.keys(metrics.cardUsage||{}).forEach(function(key){
    const count=safeInt(metrics.cardUsage[key],0),definition=CARDS[key];incrementCounter(daily,'cu_'+key,count);incrementCounter(weekly,'cu_'+key,count);
    if(definition&&definition.family){incrementCounter(daily,'cf_'+definition.family,count);incrementCounter(weekly,'cf_'+definition.family,count);}
    if(profile.serverProgress?.battleProtocol==='LUNO_BATTLE_V1'&&key==='radar'){incrementCounter(daily,'cf_radar',count);incrementCounter(weekly,'cf_radar',count);}
    if(key==='angry_n'||key==='angry_b'){incrementCounter(daily,'cu2_angry',count);incrementCounter(weekly,'cu2_angry',count);}
  });
}
function syncMatchPass(profile,at){
  const savedSeason=safeInt(profile.passState?.season,0);
  // A delayed settlement must not replace an already opened later-season Pass.
  if(savedSeason>periodSnapshot(at).seasonNumber&&profile.passState.seasonKey==='ranked-s'+savedSeason+'-v2')return null;
  return syncPassState(profile,at).pass;
}
function applyRankedSettlement(profile,options){
  if(!isRecord(profile))throw rankedError('invalid-profile','Profile is required.');
  const uid=String(options.uid||''),matchId=String(options.matchId||''),at=safeInt(options.at,Date.now()),outcome=String(options.outcome||'draw');
  if(!uid||!matchId||!['win','loss','draw','cancelled'].includes(outcome))throw rankedError('invalid-settlement','Ranked settlement is invalid.');
  if(!isRecord(profile.serverProgress))profile.serverProgress={};if(!isRecord(profile.serverProgress.rankedSettlements))profile.serverProgress.rankedSettlements={};
  const settlementKey=crypto.createHash('sha256').update(uid+'|'+matchId).digest('hex').slice(0,48),existing=profile.serverProgress.rankedSettlements[settlementKey];
  if(isRecord(existing))return Object.assign({applied:false,idempotent:true},deepClone(existing));
  normalizeSeasonRecord(profile,at);
  if(!isRecord(profile.stats))profile.stats={wins:0,losses:0,draws:0,bestStreak:0,winStreak:0,cardsPlayed:0,chestsOpened:0};
  const beforeTrophies=safeInt(profile.trophies,0),beforeArena=arenaIndexForProfile(profile),arena=ARENAS[beforeArena];
  const opponentTrophies=safeInt(options.opponentTrophies,beforeTrophies),adjustment=clamp(Math.round((opponentTrophies-beforeTrophies)/80),-8,8);
  let trophyDelta=0;
  if(outcome==='win')trophyDelta=Math.max(8,arena.win+adjustment);
  else if(outcome==='loss')trophyDelta=-Math.max(4,arena.lose-adjustment);
  let trophies=Math.max(0,beforeTrophies+trophyDelta);if(outcome==='loss')trophies=Math.max(trophies,arena.min);
  if(Number.isSafeInteger(options.trophyCap)&&options.trophyCap>=0)trophies=Math.min(trophies,options.trophyCap);
  trophyDelta=trophies-beforeTrophies;
  profile.trophies=trophies;profile.arenaIdx=Math.max(beforeArena,arenaForTrophies(trophies));
  if(outcome==='win'){profile.stats.wins=safeInt(profile.stats.wins,0)+1;profile.stats.winStreak=safeInt(profile.stats.winStreak,0)+1;profile.stats.bestStreak=Math.max(safeInt(profile.stats.bestStreak,0),profile.stats.winStreak);}
  else if(outcome==='loss'){profile.stats.losses=safeInt(profile.stats.losses,0)+1;profile.stats.winStreak=0;}
  else if(outcome==='draw')profile.stats.draws=safeInt(profile.stats.draws,0)+1;
  const metrics=Object.assign({cardsPlayed:0,captures:0,legendaryCards:0,checks:0,promotions:0,cardUsage:{},moveCount:safeInt(options.moveCount,0)},options.metrics||{});
  profile.stats.cardsPlayed=safeInt(profile.stats.cardsPlayed,0)+safeInt(metrics.cardsPlayed,0);
  profile.stats.captures=safeInt(profile.stats.captures,0)+safeInt(metrics.captures,0);
  profile.stats.checks=safeInt(profile.stats.checks,0)+safeInt(metrics.checks,0);
  profile.stats.promotions=safeInt(profile.stats.promotions,0)+safeInt(metrics.promotions,0);
  let gold=0,xp=0,levelGold=0;
  if(outcome!=='cancelled'){
    const arenaIndex=clamp(safeInt(profile.arenaIdx,0),0,ARENAS.length-1),baseXp=20+arenaIndex*5;
    if(outcome==='win'){
      gold=50+arenaIndex*12+deterministicInt(matchId+'|'+uid+'|gold',40);
      if(profile.stats.winStreak>=2)gold+=20*(Math.min(profile.stats.winStreak,6)-1);
      xp=baseXp+deterministicInt(matchId+'|'+uid+'|xp',Math.max(1,Math.floor(baseXp*.5)));
    }else if(outcome==='loss'){
      gold=12+arenaIndex*3+deterministicInt(matchId+'|'+uid+'|gold',12);xp=Math.round(baseXp*.4)+deterministicInt(matchId+'|'+uid+'|xp',5);
    }else xp=Math.max(5,Math.round(baseXp*.3));
    profile.xp=safeInt(profile.xp,0)+xp;profile.lvl=Math.max(1,safeInt(profile.lvl,1));
    while(profile.xp>=levelThreshold(profile.lvl)){profile.xp-=levelThreshold(profile.lvl);profile.lvl++;const amount=100+profile.lvl*20;levelGold+=amount;}
    if(gold+levelGold>0)applyRewardClaim(profile,{uid,sourceType:'ranked_match',sourceId:matchId,reward:{gold:gold+levelGold},matchId,at});
    const pass=syncMatchPass(profile,at);
    if(pass){
      let remaining=xp*3*(pass.premium===true?2:1);
      while(remaining>0&&pass.level<30){const room=250-pass.xp,take=Math.min(room,remaining);pass.xp+=take;remaining-=take;if(pass.xp>=250){pass.level++;pass.xp=0;}}
    }
    applyMissionProgress(profile,metrics,outcome,at);
  }
  if(!isRecord(profile.serverSeason))profile.serverSeason={};
  // Keep a finished season immutable until its end reward starts the next one.
  // A match completed after rollover must not rewrite the previous season's peak.
  if(safeInt(profile.serverSeason.number,0)===periodSnapshot(at).seasonNumber)profile.serverSeason.peakTrophies=Math.max(safeInt(profile.serverSeason.peakTrophies,0),trophies);
  if(!isRecord(profile.serverCompetition))profile.serverCompetition={};if(!isRecord(profile.serverCompetition.ledger))profile.serverCompetition.ledger={};
  profile.serverCompetition.ledger[settlementKey]={matchId,uid,outcome,trophyDelta,previousTrophies:beforeTrophies,newTrophies:trophies,createdAt:at};
  const settlement={matchId,outcome,trophyDelta,gold,xp,levelGold,newTrophies:trophies,newArenaIdx:profile.arenaIdx,newLevel:profile.lvl,settledAt:at};
  profile.serverProgress.rankedSettlements[settlementKey]=settlement;profile.updatedAt=at;
  return Object.assign({applied:true,idempotent:false},deepClone(settlement));
}

module.exports={
  ARENAS,CARDS,DRAW_OFFER_MS,FRIENDLY_DURATION_MINUTES,HEARTBEAT_STALE_MS,MATCH_DURATION_MS,MATCH_SCHEMA_VERSION,RANKED_DURATION_MS,RECONNECT_GRACE_MS,
  advanceTurnEffects,applyCard,applyRankedAction,applyRankedSettlement,attacked,boardToFen,chessJsAcceptsMove,createMatchState,expireOffers,findKing,
  arenaForTrophies,arenaIndexForProfile,heartbeatRankedState,hydrateMatch,initialBoard,isPureStandardState,legalMoves,positionKey,profileSummary,
  rankedError,sanitizeMatchReplay,sanitizeMatchView,sweepRankedState,targetAllowed
};
