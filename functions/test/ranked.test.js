'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {availableCards}=require('../lib/chests');
const {periodSnapshot}=require('../lib/economy');
const {
  ARENAS,DRAW_OFFER_MS,FRIENDLY_DURATION_MINUTES,HEARTBEAT_STALE_MS,MATCH_DURATION_MS,RECONNECT_GRACE_MS,applyRankedAction,applyRankedSettlement,arenaForTrophies,arenaIndexForProfile,boardToFen,
  chessJsAcceptsMove,createMatchState,heartbeatRankedState,initialBoard,legalMoves,positionKey,sanitizeMatchView,sweepRankedState
}=require('../lib/ranked');

function profile(uid,trophies){
  return {
    uid,name:uid,username:uid,country:'TR',avatar:'#e8b840',avatarEmoji:'&#9818;',trophies:trophies||0,arenaIdx:0,lvl:1,xp:0,gold:1250,gems:42,
    deck:['barbarian','card_block','poison_q','angry_n','glue','freeze'],inventory:{activeSkin:'classic',activePieceSet:'std',activeCostumes:{}},
    stats:{wins:0,losses:0,draws:0,bestStreak:0,winStreak:0,cardsPlayed:0,chestsOpened:0},
    serverEconomy:{claims:{},ledger:{},purchases:{},daily:{}},serverProgress:{missions:{daily:{},weekly:{},special:{}},passMissions:{daily:{},weekly:{},special:{}}}
  };
}
function match(at){
  const white=profile('white-player',200),black=profile('black-player',240);
  return createMatchState({matchId:'rm_test_match_0001',at:at||1000000,white:{uid:white.uid,profile:white,deck:white.deck},black:{uid:black.uid,profile:black,deck:black.deck}});
}
function action(state,uid,type,extra,at){
  const payload=Object.assign({type,actionId:type+'-'+uid+'-'+String(state.sequence).padStart(4,'0'),expectedSequence:state.sequence},extra||{});
  return applyRankedAction(state,uid,payload,at||state.updatedAt+1000).state;
}
function purePosition(at,halfMove){
  const state=match(at||1000000);
  state.board=new Array(64).fill(null);
  state.board[4]={t:'K',c:'W',moved:true};
  state.board[60]={t:'K',c:'B',moved:true};
  state.board[0]={t:'R',c:'W',moved:true};
  state.turn='W';state.phase='move';state.halfMove=halfMove||0;state.epTarget=-1;
  state.positionCounts={};state.positionCounts[positionKey(state)]=1;
  state.clock.activeColor='W';state.clock.startedAt=at||1000000;state.clock.deadlineAt=(at||1000000)+MATCH_DURATION_MS;
  return state;
}

test('skip-move cards expire en passant after both players skip',function(){
  let state=purePosition();
  state.phase='card';
  state.board[36]={t:'P',c:'W',moved:true};
  state.board[35]={t:'P',c:'B',moved:true};
  state.board[56]={t:'R',c:'B',moved:true};
  state.epTarget=43;state.mana.W=10;state.mana.B=10;
  assert.ok(legalMoves(state,36).includes(43));
  state=action(state,'white-player','card',{cardKey:'freeze',target:56});
  assert.equal(state.epTarget,-1);
  state=action(state,'black-player','card',{cardKey:'freeze',target:0});
  assert.equal(state.turn,'W');
  assert.ok(!legalMoves(state,36).includes(43));
});

test('ranked initial board uses the same 0=a1 orientation and standard chess validation',function(){
  const state=match();
  assert.equal(MATCH_DURATION_MS,5*60*1000);
  assert.equal(state.timeControlMinutes,5);
  assert.equal(state.clock.W,5*60*1000);
  assert.deepEqual(initialBoard()[12],{t:'P',c:'W'});
  assert.deepEqual(legalMoves(state,12),[20,28]);
  assert.equal(chessJsAcceptsMove(state,12,28,null),true);
  assert.equal(chessJsAcceptsMove(state,12,28,'Q'),false);
  assert.equal(chessJsAcceptsMove(state,12,36,'Q'),false);
  assert.match(boardToFen(state),/^rnbqkbnr\/pppppppp\/8\/8\/8\/8\/PPPPPPPP\/RNBQKBNR w KQkq - 0 1$/);
  assert.doesNotMatch(positionKey(state),/[.#$\[\]\/]/);
});

test('friendly matches accept only supported time controls and ranked ignores overrides',function(){
  const white=profile('friendly-white',200),black=profile('friendly-black',240);
  for(const durationMinutes of FRIENDLY_DURATION_MINUTES){
    const state=createMatchState({matchId:'fm_duration_'+durationMinutes,mode:'friendly',durationMinutes,white:{uid:white.uid,profile:white,deck:white.deck},black:{uid:black.uid,profile:black,deck:black.deck}});
    assert.equal(state.timeControlMinutes,durationMinutes);
    assert.equal(state.clock.W,durationMinutes*60*1000);
    assert.equal(state.clock.initialMs,durationMinutes*60*1000);
  }
  const ranked=createMatchState({matchId:'rm_fixed_duration',durationMinutes:30,white:{uid:white.uid,profile:white,deck:white.deck},black:{uid:black.uid,profile:black,deck:black.deck}});
  assert.equal(ranked.timeControlMinutes,5);
  assert.equal(ranked.clock.W,5*60*1000);
});

test('ranked arena boundaries match the client contract',function(){
  assert.deepEqual(ARENAS.map(function(arena){return arena.min}),[0,100,300,600,1000,1500,2200,3000,4000]);
  assert.deepEqual(ARENAS.map(function(arena){return arena.max}),[100,300,600,1000,1500,2200,3000,4000,999999999]);
  const checks=[[0,0],[99,0],[100,1],[299,1],[300,2],[599,2],[600,3],[999,3],[1000,4],[1499,4],[1500,5],[2199,5],[2200,6],[2999,6],[3000,7],[3999,7],[4000,8]];
  checks.forEach(function(pair){assert.equal(arenaForTrophies(pair[0]),pair[1],'trophies '+pair[0]);});
  assert.equal(arenaForTrophies(-50),0);
  assert.equal(arenaForTrophies(1000000),8);
  assert.equal(arenaIndexForProfile({trophies:150,arenaIdx:0}),1);
  assert.equal(arenaIndexForProfile({trophies:50,arenaIdx:2}),0);
  assert.equal(arenaIndexForProfile({trophies:300,arenaIdx:1}),2);
});

test('ranked settlements keep every arena floor and reject stale high rank state',function(){
  ARENAS.forEach(function(arena,index){
    const player=profile('floor-player-'+index,arena.min);player.arenaIdx=index;
    const result=applyRankedSettlement(player,{
      uid:player.uid,matchId:'rm_floor_'+index,outcome:'loss',opponentTrophies:arena.min,
      metrics:{},at:Date.parse('2026-08-10T12:00:00Z')+index
    });
    assert.ok(result.newTrophies>=arena.min,'arena '+index+' dropped below its floor');
    assert.equal(player.arenaIdx,index,'arena '+index+' changed after a floor loss');
    assert.ok(result.trophyDelta<=0,'loss awarded trophies in arena '+index);
  });
  const stale=profile('stale-rank-player',50);stale.arenaIdx=8;
  const repaired=applyRankedSettlement(stale,{uid:stale.uid,matchId:'rm_stale_rank',outcome:'loss',opponentTrophies:50,metrics:{},at:Date.parse('2026-08-10T12:01:00Z')});
  assert.ok(repaired.newTrophies<4000);
  assert.equal(stale.arenaIdx,0);
});

test('chest card unlocks follow normalized rank instead of stale arena state',function(){
  const stale=profile('stale-chest-rank',50);stale.arenaIdx=8;
  const staleCards=availableCards(stale);
  assert.equal(staleCards.includes('immunity'),false);
  assert.equal(staleCards.includes('barbarian'),true);
  const high=profile('high-chest-rank',2200);high.arenaIdx=7;
  const highCards=availableCards(high);
  assert.equal(highCards.includes('ghosts'),true);
  assert.equal(highCards.includes('immunity'),false);
});

test('ranked actions reject illegal moves, wrong turns and stale sequence numbers',function(){
  const state=match();
  assert.throws(function(){action(state,'black-player','move',{from:52,to:36});},/not this player's turn/i);
  assert.throws(function(){action(state,'white-player','move',{from:12,to:36});},/not legal/i);
  assert.throws(function(){applyRankedAction(state,'white-player',{type:'skip_card',actionId:'stale-action-0001',expectedSequence:99},1001000);},/stale/i);
});

test('standard ranked promotion requires and preserves the selected piece',function(){
  const missing=purePosition(1500000);
  missing.board[0]=null;
  missing.board[48]={t:'P',c:'W',moved:true};
  assert.throws(function(){applyRankedAction(missing,'white-player',{type:'move',actionId:'promote-missing-1',expectedSequence:0,from:48,to:56},1501000);},/promotion/i);
  for(const promotion of ['Q','R','B','N']){
    const state=purePosition(1510000);
    state.board[0]=null;
    state.board[63]={t:'R',c:'B',moved:true};
    state.board[48]={t:'P',c:'W',moved:true};
    const after=action(state,'white-player','move',{from:48,to:56,promotion},1511000);
    assert.equal(after.board[56].t,promotion);
    assert.equal(after.result,null);
  }
});

test('standard ranked draw thresholds follow claimable versus automatic FIDE rules',function(){
  const fifty=purePosition(1600000,100);
  const afterMove=action(fifty,'white-player','move',{from:0,to:8},1601000);
  assert.equal(afterMove.result,null);
  const claimed=action(afterMove,'black-player','claim_fifty_move',{},1602000);
  assert.equal(claimed.result.winner,'draw');
  assert.equal(claimed.result.reason,'fifty-move-claim');

  const threefold=purePosition(1610000);
  threefold.positionCounts[positionKey(threefold)]=3;
  const threefoldClaim=action(threefold,'white-player','claim_threefold',{},1611000);
  assert.equal(threefoldClaim.result.reason,'threefold-repetition-claim');

  const seventyFive=purePosition(1620000,149);
  const automatic=action(seventyFive,'white-player','move',{from:0,to:8},1621000);
  assert.equal(automatic.result.winner,'draw');
  assert.equal(automatic.result.reason,'seventy-five-move-rule');
});

test('a repeated action id is idempotent and cannot advance the match twice',function(){
  const state=match(),payload={type:'skip_card',actionId:'skip-white-0001',expectedSequence:0};
  const first=applyRankedAction(state,'white-player',payload,1001000);
  const replay=applyRankedAction(first.state,'white-player',payload,1002000);
  assert.equal(first.state.sequence,1);
  assert.equal(replay.state.sequence,1);
  assert.equal(replay.idempotent,true);
});

test('server recognizes Fool\'s Mate and alone decides the winner',function(){
  let state=match(2000000);
  state=action(state,'white-player','move',{from:13,to:21},2001000);
  state=action(state,'black-player','move',{from:52,to:36},2002000);
  state=action(state,'white-player','move',{from:14,to:30},2003000);
  const finalAction={type:'move',actionId:'mate-black-0003',expectedSequence:state.sequence,from:59,to:31};
  const final=applyRankedAction(state,'black-player',finalAction,2004000);state=final.state;
  assert.equal(state.status,'finished');
  assert.equal(state.result.winner,'B');
  assert.equal(state.result.reason,'checkmate');
  const replay=applyRankedAction(state,'black-player',finalAction,2005000);
  assert.equal(replay.idempotent,true);
  assert.equal(replay.state.sequence,state.sequence);
});

test('authoritative card play checks deck, mana, target and one-card-per-turn',function(){
  let state=match(3000000);state.mana.W=10;
  state=action(state,'white-player','card',{cardKey:'barbarian',target:8},3001000);
  assert.equal(state.board[8].barbarian,true);
  assert.equal(state.mana.W,6);
  assert.equal(state.cardUsed,true);
  assert.throws(function(){action(state,'white-player','card',{cardKey:'freeze',target:48},3002000);},/one card/i);
  const next=match(3100000);next.mana.W=10;
  assert.throws(function(){action(next,'white-player','card',{cardKey:'ghosts'},3101000);},/not in the authoritative hand/i);
  assert.throws(function(){action(next,'white-player','card',{cardKey:'freeze',target:8},3101000);},/target is invalid/i);
});

test('family-owned level-one cards resolve to their authoritative variant',function(){
  const state=match(3200000);state.hands.W=['trap'];state.mana.W=10;
  const result=action(state,'white-player','card',{cardKey:'trap1',target:20},3201000);
  assert.equal(result.traps[20].level,1);
  assert.equal(result.lastCard.W,'trap1');
});

test('authoritative upgraded cards can resolve to a lower affordable level',function(){
  const state=match(3300000);state.hands.W=['trap3'];state.mana.W=3;
  const result=action(state,'white-player','card',{cardKey:'trap1',target:20},3301000);
  assert.equal(result.traps[20].level,1);
  assert.equal(result.mana.W,0);
});

test('authoritative glued pawns reject stale or unsafe partner links',function(){
  const state=match(3400000);
  state.board=new Array(64).fill(null);
  state.board[4]={t:'K',c:'W',moved:true};state.board[60]={t:'K',c:'B',moved:true};
  state.board[27]={t:'P',c:'W'};state.board[28]={t:'P',c:'W'};
  state.hands.W=['glue'];state.mana.W=10;state.phase='card';state.turn='W';
  let after=action(state,'white-player','card',{cardKey:'glue',target:27,secondaryTarget:28},3401000);
  after=action(after,'white-player','skip_card',{},3402000);
  after.board[35]={t:'N',c:'W'};
  assert.throws(function(){
    action(after,'white-player','move',{from:28,to:36},3403000);
  },/not legal|linked/i);

  const stale=match(3410000);
  stale.board=new Array(64).fill(null);
  stale.board[4]={t:'K',c:'W',moved:true};stale.board[60]={t:'K',c:'B',moved:true};
  stale.board[27]={t:'P',c:'W',linkTo:28};stale.board[28]={t:'P',c:'W'};
  stale.phase='move';stale.turn='W';stale.positionCounts={};stale.positionCounts[positionKey(stale)]=1;
  assert.throws(function(){
    action(stale,'white-player','move',{from:27,to:35},3411000);
  },/not legal|linked/i);
});

test('authoritative glued partner resolves its landing trap without a runtime error',function(){
  const state=match(3450000);
  state.board=new Array(64).fill(null);
  state.board[4]={t:'K',c:'W'};state.board[60]={t:'K',c:'B'};
  state.board[27]={t:'P',c:'W'};state.board[28]={t:'P',c:'W'};
  state.hands.W=['glue'];state.mana.W=10;state.phase='card';state.turn='W';
  let after=action(state,'white-player','card',{cardKey:'glue',target:27,secondaryTarget:28},3451000);
  after.traps[36]={by:'B',duration:2,level:3,life:4};
  after=action(after,'white-player','move',{from:27,to:35},3452000);
  assert.equal(after.board[35].t,'P');
  assert.equal(after.board[36],null);
  assert.equal(after.traps[36],undefined);
  assert.equal(after.board[35].linkTo,undefined);
});

test('authoritative main glued pawn resolves its landing trap before moving the partner',function(){
  const state=match(3460000);
  state.board=new Array(64).fill(null);
  state.board[4]={t:'K',c:'W'};state.board[60]={t:'K',c:'B'};
  state.board[27]={t:'P',c:'W'};state.board[28]={t:'P',c:'W'};
  state.hands.W=['glue'];state.mana.W=10;state.phase='card';state.turn='W';
  let after=action(state,'white-player','card',{cardKey:'glue',target:27,secondaryTarget:28},3461000);
  after.traps[35]={by:'B',duration:2,level:3,life:4};
  after=action(after,'white-player','move',{from:27,to:35},3462000);
  assert.equal(after.board[35],null);
  assert.equal(after.board[28].t,'P');
  assert.equal(after.board[28].linkTo,undefined);
  assert.equal(after.traps[35],undefined);
});

test('authoritative pit trap spares but locks the king like the local engine',function(){
  const state=match(3500000);
  state.board=new Array(64).fill(null);
  state.board[4]={t:'K',c:'W'};state.board[60]={t:'K',c:'B'};
  state.hands.W=['trap3'];state.mana.W=10;state.phase='card';state.turn='W';
  state.traps[12]={by:'W',duration:2,level:3,life:4};
  let after=action(state,'white-player','card',{cardKey:'trap3',target:20},3501000);
  after=action(after,'white-player','skip_card',{},3502000);
  after=action(after,'white-player','move',{from:4,to:12},3503000);
  assert.equal(after.board[12].t,'K');
  assert.equal(after.board[12].trapped,2);
});

test('authoritative reinforcement refuses a hidden trap square',function(){
  const state=match(3600000);
  state.board=new Array(64).fill(null);
  state.board[4]={t:'K',c:'W'};state.board[60]={t:'K',c:'B'};
  state.board[36]={t:'P',c:'W'};state.traps[28]={by:'B',duration:2,level:2,life:4};
  state.hands.W=['reinforce'];state.mana.W=10;state.phase='card';state.turn='W';
  assert.throws(function(){
    action(state,'white-player','card',{cardKey:'reinforce',target:36},3601000);
  },/no pawn can be created/i);
  assert.equal(state.board[28],null);
});

test('hidden cards and traps never leak into the opponent view',function(){
  let state=match(4000000);
  state.hands.W=['trap1','barbarian','card_block','poison_q','angry_n','freeze'];state.mana.W=10;
  state=action(state,'white-player','card',{cardKey:'trap1',target:20},4001000);
  const white=sanitizeMatchView(state,'white-player'),black=sanitizeMatchView(state,'black-player');
  assert.equal(white.traps[20].level,1);
  assert.equal(black.traps[20],undefined);
  assert.equal(black.lastEvent.cardKey,'hidden');
  assert.equal(black.lastEvent.target,null);
  assert.equal(black.opponentHand,null);
  assert.equal(black.mana.W,null);
  assert.equal(black.fog.W,0);
  assert.deepEqual(black.hand,state.hands.B);
});

test('sanitized views restore nullable fields omitted by Realtime Database',function(){
  const stored=match(4500000);
  delete stored.result;delete stored.lastEvent;delete stored.drawOffer;delete stored.cancelOffer;
  const view=sanitizeMatchView(stored,'white-player');
  assert.equal(view.result,null);
  assert.equal(view.lastEvent,null);
  assert.equal(view.drawOffer,null);
  assert.equal(view.cancelOffer,null);
  assert.doesNotMatch(JSON.stringify(view),/undefined/);
});

test('server clock expires from trusted time and client heartbeat cannot reset it',function(){
  const state=match(5000000),heartbeatAt=5000000+MATCH_DURATION_MS-1000;
  state.presence['white-player'].lastSeenAt=heartbeatAt;
  state.presence['black-player'].lastSeenAt=heartbeatAt;
  const heartbeat=heartbeatRankedState(state,'white-player',heartbeatAt);
  assert.equal(heartbeat.status,'active');
  assert.equal(heartbeat.clock.W,1000);
  const expired=sweepRankedState(heartbeat,5000000+MATCH_DURATION_MS+1);
  assert.equal(expired.status,'finished');
  assert.equal(expired.result.winner,'B');
  assert.equal(expired.result.reason,'timeout');
});

test('temporary disconnect gets a grace period and a single stale player forfeits',function(){
  const state=match(6000000);
  state.presence['black-player'].lastSeenAt=6000000;
  state.presence['white-player'].lastSeenAt=6000000+RECONNECT_GRACE_MS;
  const temporary=sweepRankedState(state,6000000+20000);
  assert.equal(temporary.status,'active');
  assert.equal(temporary.presence['black-player'].state,'TEMP_DISCONNECTED');
  const forfeited=sweepRankedState(temporary,6000000+RECONNECT_GRACE_MS+1);
  assert.equal(forfeited.status,'finished');
  assert.equal(forfeited.result.winner,'W');
  assert.equal(forfeited.result.reason,'disconnect-forfeit');
});

test('a late heartbeat cannot resurrect a player after the reconnect grace window',function(){
  const state=match(6500000),late=6500000+RECONNECT_GRACE_MS+HEARTBEAT_STALE_MS+1;
  state.presence['white-player'].lastSeenAt=6500000;
  state.presence['black-player'].lastSeenAt=late;
  const result=heartbeatRankedState(state,'white-player',late);
  assert.equal(result.status,'finished');
  assert.equal(result.result.winner,'B');
  assert.equal(result.result.reason,'disconnect-forfeit');
  assert.equal(result.presence['white-player'].state,'FORFEITED');
});

test('a late action cannot revive a disconnected player or bypass the forfeit',function(){
  const state=match(6600000),late=6600000+RECONNECT_GRACE_MS+HEARTBEAT_STALE_MS+1;
  state.presence['white-player'].lastSeenAt=6600000;
  state.presence['black-player'].lastSeenAt=late;
  const actionResult=applyRankedAction(state,'white-player',{
    type:'resign',actionId:'late-resign-white-0001',expectedSequence:0
  },late);
  assert.equal(actionResult.state.status,'finished');
  assert.equal(actionResult.state.result.winner,'B');
  assert.equal(actionResult.state.result.reason,'disconnect-forfeit');
});

test('draw and opening cancellation offers are visible, respondable and expire',function(){
  let state=match(6700000);
  state=action(state,'white-player','offer_draw',{},6701000);
  assert.equal(state.drawOffer.by,'white-player');
  assert.throws(function(){action(state,'white-player','offer_draw',{},6702000);},/active/i);
  assert.throws(function(){action(state,'black-player','offer_cancel',{},6702500);},/draw offer/i);
  state=action(state,'black-player','reject_draw',{},6703000);
  assert.equal(state.drawOffer,null);
  state=action(state,'white-player','offer_draw',{},6704000);
  state=action(state,'black-player','accept_draw',{},6705000);
  assert.equal(state.result.reason,'draw-agreement');

  state=match(6800000);
  state=action(state,'white-player','offer_cancel',{},6801000);
  assert.equal(state.cancelOffer.by,'white-player');
  state=action(state,'black-player','reject_cancel',{},6802000);
  assert.equal(state.cancelOffer,null);
  state=action(state,'white-player','offer_cancel',{},6803000);
  state=action(state,'white-player','skip_card',{},6803000+DRAW_OFFER_MS+1);
  assert.equal(state.cancelOffer,null);
  state=action(state,'white-player','offer_draw',{},6804000);
  state=action(state,'black-player','accept_draw',{},6805000);
  assert.equal(state.drawOffer,null);
  assert.equal(state.cancelOffer,null);
});

test('ranked settlement is deterministic, arena-protected and idempotent',function(){
  const player=profile('settle-player',301);player.arenaIdx=1;
  const options={uid:player.uid,matchId:'rm_settlement_0001',outcome:'loss',opponentTrophies:900,moveCount:24,metrics:{cardsPlayed:2,captures:3,legendaryCards:0,cardUsage:{barbarian:2}},at:Date.parse('2026-08-09T12:00:00Z')};
  const first=applyRankedSettlement(player,options),snapshot=JSON.stringify(player),second=applyRankedSettlement(player,options);
  assert.equal(first.applied,true);
  assert.equal(first.newTrophies,300);
  assert.equal(first.trophyDelta,-1);
  assert.equal(second.idempotent,true);
  assert.equal(JSON.stringify(player),snapshot);
  assert.equal(player.stats.losses,1);
  assert.equal(player.stats.cardsPlayed,2);
  assert.equal(Object.keys(player.serverEconomy.ledger).length,1);
});

for(const outcome of ['win','loss','draw','cancelled']){
  test(`ranked ${outcome} settlement survives 100 duplicate retries`,function(){
    const player=profile('repeat-'+outcome,900);
    const options={uid:player.uid,matchId:'repeat-'+outcome,outcome,opponentTrophies:950,moveCount:24,metrics:{cardsPlayed:3,captures:2,checks:1},at:Date.parse('2026-08-09T12:00:00Z')};
    const first=applyRankedSettlement(player,options),snapshot=JSON.stringify(player);
    assert.equal(first.applied,true);
    for(let retry=0;retry<100;retry++){
      const repeated=applyRankedSettlement(player,{...options,at:options.at+retry*1000,metrics:{cardsPlayed:999,captures:999},outcome:retry%2?'win':outcome});
      assert.equal(repeated.applied,false);
      assert.equal(repeated.idempotent,true);
      assert.equal(repeated.outcome,outcome);
      assert.equal(JSON.stringify(player),snapshot);
    }
  });
}

test('ranked settlement feeds daily and weekly mission counters from authoritative metrics',function(){
  const player=profile('mission-metrics-player',200),at=Date.parse('2026-08-10T12:00:00Z');
  applyRankedSettlement(player,{uid:player.uid,matchId:'rm_mission_metrics_0001',outcome:'draw',opponentTrophies:200,metrics:{cardsPlayed:4,captures:7,legendaryCards:2,checks:3,promotions:1,cardUsage:{barbarian:2}},at});
  const periods=periodSnapshot(at),daily=player.serverProgress.missions.daily[periods.dayKey].counters,weekly=player.serverProgress.missions.weekly[periods.weekKey].counters;
  assert.equal(player.stats.draws,1);
  assert.equal(player.stats.captures,7);
  assert.equal(player.stats.checks,3);
  assert.equal(player.stats.promotions,1);
  assert.equal(daily.d_draw,1);
  assert.equal(daily.d_capture,7);
  assert.equal(daily.d_checks,3);
  assert.equal(daily.d_legend,2);
  assert.equal(weekly.w_draw,1);
  assert.equal(weekly.w_capture,7);
  assert.equal(weekly.w_checks,3);
  assert.equal(weekly.w_promote,1);
  assert.equal(weekly.w_cards,4);
});

test('ranked settlement advances the Pass with the same server XP contract',function(){
  const regular=profile('pass-xp-regular',200),premium=profile('pass-xp-premium',200);
  premium.passState={seasonKey:'ranked-s4-v2',season:4,seasonStartedAt:1,level:0,xp:0,premium:true,claimed:{free:{},premium:{}}};
  const regularResult=applyRankedSettlement(regular,{
    uid:regular.uid,matchId:'rm_pass_xp_regular',outcome:'win',opponentTrophies:200,metrics:{},at:Date.parse('2026-08-09T12:00:00Z')
  });
  const premiumResult=applyRankedSettlement(premium,{
    uid:premium.uid,matchId:'rm_pass_xp_premium',outcome:'win',opponentTrophies:200,metrics:{},at:Date.parse('2026-08-09T12:00:00Z')
  });
  assert.equal(regularResult.applied,true);
  assert.equal(premiumResult.applied,true);
  assert.equal(regular.passState.level,0);
  assert.equal(regular.passState.xp,regularResult.xp*3);
  assert.equal(premium.passState.level,0);
  assert.equal(premium.passState.xp,premiumResult.xp*6);

  const capped=profile('pass-xp-capped',200);
  capped.passState={seasonKey:'ranked-s4-v2',season:4,seasonStartedAt:1,level:30,xp:249,premium:false,claimed:{free:{},premium:{}}};
  applyRankedSettlement(capped,{uid:capped.uid,matchId:'rm_pass_xp_capped',outcome:'win',opponentTrophies:200,metrics:{},at:Date.parse('2026-08-09T12:00:00Z')});
  assert.equal(capped.passState.level,30);
  assert.equal(capped.passState.xp,249);
});
