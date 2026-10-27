'use strict';

const {ARENAS}=require('../../functions/lib/ranked');
const rates=[.45,.50,.55,.60,.65,.70];
const previousUpper=[[18,22],[15,25],[12,28]];
function random(seed){let n=seed>>>0;return ()=>{n=(Math.imul(n,1664525)+1013904223)>>>0;return n/4294967296;};}
function fixedArena(arena,rate,seed,matches=10000){
  const rng=random(seed);let trophies=arena.min+200,floorHits=0;
  for(let i=0;i<matches;i++){
    const next=trophies+(rng()<rate?arena.win:-arena.lose);
    if(next<arena.min)floorHits++;
    trophies=Math.max(arena.min,next);
  }
  return {movement:trophies-arena.min-200,floorHitRate:floorHits/matches};
}
function ladder(catalog,rate,seed,matches=5000){
  const rng=random(seed);let trophies=0;const reached=Array(catalog.length).fill(null);reached[0]=0;
  for(let i=0;i<matches;i++){
    const arena=catalog.findLast(a=>trophies>=a.min);
    trophies=Math.max(arena.min,trophies+(rng()<rate?arena.win:-arena.lose));
    const next=catalog.findLastIndex(a=>trophies>=a.min);
    for(let j=0;j<=next;j++)if(reached[j]===null)reached[j]=i+1;
  }
  return {trophies,reached};
}
const proposed=ARENAS.map(a=>({...a}));
const previous=ARENAS.map((a,i)=>i<6?a:{...a,win:previousUpper[i-6][0],lose:previousUpper[i-6][1]});
const result={seed:214,repetitions:100,localModelOnly:true,assumptions:{draws:0,opponentRatingGap:0,streakTrophies:false,arenaFloors:true,seasonTrophyReset:false},
  arenas:proposed.map((a,i)=>({index:i,min:a.min,max:a.max,previousWin:previous[i].win,previousLoss:previous[i].lose,win:a.win,loss:a.lose,
    previousBreakEven:previous[i].lose/(previous[i].win+previous[i].lose),breakEven:a.lose/(a.win+a.lose),
    profiles:rates.map(rate=>{const sims=Array.from({length:100},(_,n)=>fixedArena(a,rate,214+n));const baseline=Array.from({length:100},(_,n)=>fixedArena(previous[i],rate,214+n));return {winRate:rate,
      previousRawExpectedPerMatch:rate*previous[i].win-(1-rate)*previous[i].lose,rawExpectedPerMatch:rate*a.win-(1-rate)*a.lose,
      previousMeanFloorHitRate:baseline.reduce((s,x)=>s+x.floorHitRate,0)/baseline.length,
      meanMovementAfter10000:sims.reduce((s,x)=>s+x.movement,0)/sims.length,meanFloorHitRate:sims.reduce((s,x)=>s+x.floorHitRate,0)/sims.length};})})),
  ladder:rates.map(rate=>{const sims=Array.from({length:100},(_,n)=>ladder(proposed,rate,214+n));return {winRate:rate,meanTrophiesAfter5000:sims.reduce((s,x)=>s+x.trophies,0)/sims.length,
    meanMatchesToArena:proposed.map((_,i)=>{const entries=sims.map(x=>x.reached[i]).filter(x=>x!==null);return {arena:i,reachedRuns:entries.length,meanMatches:entries.length?entries.reduce((s,x)=>s+x,0)/entries.length:null};})};}),
  pass:{cost:450,legacy:{freeGems:120,premiumGems:540,total:660,netGems:210},future:{freeGems:120,premiumGems:330,total:450,netGems:0},
    requiredXp:7500,profiles:rates.map(rate=>({winRate:rate,arenas:proposed.map((_,index)=>{
      const base=20+index*5,win=base+(Math.max(1,Math.floor(base*.5))-1)/2,loss=Math.round(base*.4)+2;
      const xpPerMatch=3*(rate*win+(1-rate)*loss);
      return {arena:index,expectedXpPerMatch:xpPerMatch,regularMatchesToComplete:Math.ceil(7500/xpPerMatch),premiumMatchesToComplete:Math.ceil(7500/(xpPerMatch*2))};
    })}))},
  competitiveUnlocks:{starter:10,earned:14,meaningfulRatedHumanMatches:20,premiumRequired:false,chestRandomnessRequired:false}};
process.stdout.write(JSON.stringify(result,null,2)+'\n');
