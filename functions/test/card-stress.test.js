'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {
  CARDS,applyRankedAction,createMatchState,legalMoves
}=require('../lib/ranked');

const CARD_KEYS=Object.keys(CARDS);
const FILLERS=['barbarian','card_block','poison_q','angry_n','glue','freeze'];

function profile(uid){
  return {uid,name:uid,username:uid,country:'TR',avatar:'#5b3c93',avatarEmoji:'av_pawn',trophies:500,arenaIdx:2,lvl:8};
}

function deckFor(card){
  const deck=[card];
  for(const filler of FILLERS)if(!deck.includes(filler)&&deck.length<6)deck.push(filler);
  return deck;
}

function stateFor(card,scenario){
  const white=profile('stress-white'),black=profile('stress-black'),deck=deckFor(card);
  const state=createMatchState({
    matchId:'rm_stress_'+card+'_'+String(scenario).padStart(3,'0'),
    at:1000000+scenario*1000,
    white:{uid:white.uid,profile:white,deck},black:{uid:black.uid,profile:black,deck}
  });
  const color=scenario%2===0?'W':'B';
  state.turn=color;state.clock.activeColor=color;state.clock.startedAt=state.updatedAt;
  state.mana[color]=10;state.hands[color]=deck.slice();state.moveCount=scenario%80;
  state.halfMove=scenario%50;
  const noiseSquare=color==='W'?40:23;
  if(scenario%3===0)state.blocks[noiseSquare]=1+(scenario%3);
  if(scenario%5===0)state.shields[noiseSquare]={by:color,duration:2};
  if(scenario%7===0&&state.board[color==='W'?1:57])state.board[color==='W'?1:57].moved=true;
  return {state,color,uid:color==='W'?'stress-white':'stress-black'};
}

function legalTarget(state,color,key,scenario){
  const definition=CARDS[key],targetType=definition.target;
  const own=color==='W'?{pawns:[8,9,10,11,12,13,14,15],knights:[1,6],bishops:[2,5],pieces:[0,3,8,9]}:{pawns:[48,49,50,51,52,53,54,55],knights:[57,62],bishops:[58,61],pieces:[56,59,48,49]};
  const enemy=color==='W'?{pawns:[48,49,50,51,52,53,54,55],queen:59}:{pawns:[8,9,10,11,12,13,14,15],queen:3};
  if(key==='archer'){
    const target=color==='W'?27:36,victim=color==='W'?36:27;
    state.board[target]={t:'P',c:color,moved:true};state.board[victim]={t:'R',c:color==='W'?'B':'W',moved:true};
    return {target,secondaryTarget:null};
  }
  if(key==='reinforce'){
    const target=color==='W'?27:36;state.board[target]={t:'P',c:color,moved:true};
    for(const delta of (color==='W'?[-8,-16]:[8,16]))state.board[target+delta]=null;
    return {target,secondaryTarget:null};
  }
  if(key==='ghosts'){
    for(const square of (color==='W'?[11,12,13]:[51,52,53]))state.board[square]=null;
    return {target:null,secondaryTarget:null};
  }
  if(targetType==='none')return {target:null,secondaryTarget:null};
  if(targetType==='enemy')return {target:enemy.pawns[scenario%enemy.pawns.length],secondaryTarget:null};
  if(targetType==='enemy_queen')return {target:enemy.queen,secondaryTarget:null};
  if(targetType==='own_pawn')return {target:own.pawns[scenario%own.pawns.length],secondaryTarget:null};
  if(targetType==='own_knight')return {target:own.knights[scenario%own.knights.length],secondaryTarget:null};
  if(targetType==='own_bishop')return {target:own.bishops[scenario%own.bishops.length],secondaryTarget:null};
  if(targetType==='own_kn_bi'){
    const choices=own.knights.concat(own.bishops);return {target:choices[scenario%choices.length],secondaryTarget:null};
  }
  if(targetType==='own_piece')return {target:own.pieces[scenario%own.pieces.length],secondaryTarget:null};
  if(targetType==='own_pawn_pair'){
    const offset=scenario%7;return {target:own.pawns[offset],secondaryTarget:own.pawns[offset+1]};
  }
  const empties=color==='W'?[16,17,18,19,20,21,22,24,25,26,27,28,29,30,31]:[32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47];
  let target=empties[scenario%empties.length];
  while(state.board[target]||state.blocks[target]||state.shields[target]||state.traps[target])target=empties[(empties.indexOf(target)+1)%empties.length];
  return {target,secondaryTarget:null};
}

function cardAction(state,key,target,secondaryTarget,scenario){
  const action={type:'card',cardKey:key,actionId:'stress-'+key+'-'+String(scenario).padStart(3,'0'),expectedSequence:state.sequence};
  if(target!==null)action.target=target;
  if(secondaryTarget!==null)action.secondaryTarget=secondaryTarget;
  return action;
}

test('29 authoritative cards survive 300 varied deterministic scenarios each',function(){
  assert.equal(CARD_KEYS.length,29);
  const totals={};
  for(const key of CARD_KEYS){
    totals[key]=0;
    for(let scenario=0;scenario<300;scenario++){
      const built=stateFor(key,scenario),valid=legalTarget(built.state,built.color,key,scenario);
      const action=cardAction(built.state,key,valid.target,valid.secondaryTarget,scenario);
      const category=scenario%20;
      if(category===17){
        action.target=CARDS[key].target==='none'?0:-1;
        assert.throws(()=>applyRankedAction(built.state,built.uid,action,built.state.updatedAt+10),/target is invalid/i);
      }else if(category===18){
        built.state.mana[built.color]=0;
        assert.throws(()=>applyRankedAction(built.state,built.uid,action,built.state.updatedAt+10),/not enough authoritative mana/i);
      }else if(category===19){
        action.expectedSequence=99;
        assert.throws(()=>applyRankedAction(built.state,built.uid,action,built.state.updatedAt+10),/stale/i);
      }else{
        let result;
        try{
          result=applyRankedAction(built.state,built.uid,action,built.state.updatedAt+10);
        }catch(error){
          error.message=key+' scenario '+scenario+': '+error.message;
          throw error;
        }
        assert.equal(result.state.metrics[built.color].cardUsage[key],1);
        assert.equal(result.state.sequence,1);
        if(scenario%23===0){
          const replay=applyRankedAction(result.state,built.uid,action,built.state.updatedAt+20);
          assert.equal(replay.idempotent,true);assert.equal(replay.state.sequence,1);
        }
      }
      totals[key]++;
    }
    assert.equal(totals[key],300,key+' scenario count');
  }
  assert.equal(Object.values(totals).reduce((sum,value)=>sum+value,0),8700);
});

test('Black Plague blocks both colors for the same global turn window',function(){
  const built=stateFor('plague',2),valid=legalTarget(built.state,built.color,'plague',2);
  const played=applyRankedAction(built.state,built.uid,cardAction(built.state,'plague',valid.target,valid.secondaryTarget,2),built.state.updatedAt+10).state;
  assert.equal(legalMoves(played,8).length,0);
  assert.equal(legalMoves(played,48).length,0);
  played.moveCount+=2;
  assert.ok(legalMoves(played,8).length>0);
  assert.ok(legalMoves(played,48).length>0);
});

test('Angry Knight legal targets stay complete on center and board edges',function(){
  const built=stateFor('angry_n',4),state=built.state;
  state.board=new Array(64).fill(null);state.board[4]={t:'K',c:'W'};state.board[60]={t:'K',c:'B'};
  state.board[27]={t:'N',c:'W',angryN:true};
  assert.deepEqual(legalMoves(state,27).sort((a,b)=>a-b),[50,52]);
  state.board[27]=null;state.board[8]={t:'N',c:'W',angryN:true};
  assert.deepEqual(legalMoves(state,8),[33]);
});
