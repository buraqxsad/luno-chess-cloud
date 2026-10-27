import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {mkdirSync,readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {applyAuthoritative,playerView} from '../src/authoritative.js';
import {legalActions,legalRuleMoves,chooseBotAction,cardTargets,publicFingerprint} from '../src/core.js';
import {normalMoves,squares,inCheck,sideOf} from '../src/board.js';
import {CARDS,STARTER,clone,actionKey,opposite,type CardId,type Side,type Action,type AuthoritativeBattleState} from '../src/model.js';
import {initial,at,type Fixture,type FixtureStep} from './fixture_support.js';

const defaultQa=resolve(__dirname,'../../../../luno_chess/qa');
const qa=process.env.LUNO_DIFFERENTIAL_QA?resolve(process.env.LUNO_DIFFERENTIAL_QA):defaultQa;
mkdirSync(qa,{recursive:true});
const fixtures=JSON.parse(readFileSync(resolve(__dirname,'../../../../battle_contract/v1/rules.json'),'utf8')).fixtures as Fixture[];
// Explicit argv supports SDK source runners when an OS cannot launch an AOT exe.
const runner=process.env.LUNO_DART_RUNNER??resolve(defaultQa,'v201a-battle-runner.exe');
const runnerArgs:unknown=JSON.parse(process.env.LUNO_DART_RUNNER_ARGS??'[]');
assert.ok(Array.isArray(runnerArgs)&&runnerArgs.every(value=>typeof value==='string'),'Runner arguments must be a JSON string array');
const child=spawn(runner,runnerArgs as string[],{stdio:['pipe','pipe','inherit']});
const lines=createInterface({input:child.stdout});
const waiting:Array<(value:any)=>void>=[];
lines.on('line',line=>{const callback=waiting.shift();if(!callback)throw new Error('unsolicited-dart-output');callback(JSON.parse(line));});
child.on('error',e=>{throw e;});
let sequence=0,scenarioCount=0,stateCount=0,setCount=0,repetitionChecks=0,redactionChecks=0;
const counts:Record<string,number>={},illegal:Record<string,number>={};
let currentTrace:{scenarioId:string;seed:number;initial:Fixture;initialState:AuthoritativeBattleState;actions:Action[];rejections:number[]}|undefined;
const bump=(key:string,n=1):void=>{counts[key]=(counts[key]??0)+n;};
const localResults=new WeakMap<AuthoritativeBattleState,Record<string,unknown>>();
const cards=Object.keys(CARDS) as CardId[];
function deck(first:CardId[]):CardId[]{return [...first,...cards.filter(c=>!first.includes(c))].slice(0,10);}
function rng(seed:number):()=>number {let n=seed;return ()=>{n=(Math.imul(n,1664525)+1013904223)>>>0;return n/4294967296;};}
function shuffled<T>(items:readonly T[],random:()=>number):T[]{const out=[...items];for(let i=out.length-1;i;i--){const j=Math.floor(random()*(i+1));[out[i],out[j]]=[out[j]!,out[i]!];}return out;}
async function ask(request:unknown):Promise<any>{const reply=new Promise<any>(done=>waiting.push(done));child.stdin.write(JSON.stringify(request)+'\n');return reply;}
function local(s:AuthoritativeBattleState):Record<string,unknown> {
  const cached=localResults.get(s);if(cached)return cached;
  const side=s.rules.fen.split(' ')[1] as Side,v=playerView(s,side);
  const actions=legalActions(v),bot=chooseBotAction(v);
  assert.ok(bot===null?actions.length===0:actions.some(a=>actionKey(a)===actionKey(bot)),'bot legality');
  for(const color of ['w','b'] as const){const view=playerView(s,color);assert.equal(Object.hasOwn(view,'hidden'),false);assert.equal(Object.hasOwn(view,'decks'),false);assert.equal(Object.hasOwn(view,'opponentHand'),false);}
  const result={state:s,legal:actions.map(actionKey).sort(),bot:bot? actionKey(bot):null,check:{w:inCheck(s.rules.fen,'w'),b:inCheck(s.rules.fen,'b')},error:null};localResults.set(s,result);return result;
}
function compare(s:AuthoritativeBattleState,d:any,label:string,error:string|null=null):void {
  assert.notEqual(d.error,'runner-error',`${label}: ${d.message}`);
  const expected:Record<string,unknown>={...local(s),error};
  assert.deepEqual(d.legal,expected.legal,`${label}: COMPLETE LEGAL ACTION SET`);setCount++;
  assert.deepEqual(d.state,expected.state,`${label}: CANONICAL RESULTING STATE`);stateCount++;
  assert.deepEqual(d.check,expected.check,`${label}: CHECK`);assert.equal(d.bot,expected.bot,`${label}: BOT`);
}
function coverage(before:AuthoritativeBattleState,after:AuthoritativeBattleState,a:Action,seen:Set<string>):void {
  const s=before.rules,t=after.rules,side=s.fen.split(' ')[1] as Side,enemy=opposite(side);
  const once=(key:string):void=>{if(!seen.has(key)){bump(key);seen.add(key);}};
  if(a.type==='play'&&a.card!=='prophecy'&&a.card!=='fate_exchange')bump('card:'+a.card);
  if(a.type==='resolve'&&s.pending)bump('card:'+s.pending.card);
  if(a.type==='play'&&s.modifiers.some(m=>m.type==='discount'&&m.responseSide===side&&m.ownTurn===s.ownTurns[side]))bump('contractConsumed');
  if((a.type==='pass'||a.type==='discard')&&s.modifiers.some(m=>m.type==='discount'&&m.responseSide===side&&m.ownTurn===s.ownTurns[side]))bump('contractExpired');
  if(a.type==='play'&&a.card==='radar'){const o=after.hidden.knowledge[side].radarObservations.at(-1)!;bump(o.result==='IN_HAND'?'radarPositive':'radarNegative');}
  for(const color of ['w','b'] as const)after.hidden.knowledge[color].radarObservations.forEach((o,i)=>{if(o.result==='NOT_IN_HAND'&&o.stale&&!before.hidden.knowledge[color].radarObservations[i]?.stale)bump('radarStale');});
  for(const mine of s.boardEffects.filter(e=>e.type==='mine'))if(!t.boardEffects.some(e=>e.id===mine.id)){bump('mineRemoved');if(a.type==='move'&&t.pieceEffects.some(e=>e.type==='mine_debuff'&&!s.pieceEffects.some(p=>p.id===e.id)))bump('mineTrigger');}
  if(a.type==='play'&&a.card==='break_seal'){
    const selected=s.boardEffects.find(e=>e.id===a.target)!;
    if(s.boardEffects.some(e=>e.id!==selected.id&&e.squares.some(q=>selected.squares.includes(q)))){
      assert.equal(s.boardEffects.length-t.boardEffects.length,1,'single overlap removal');bump('breakOverlap');}
  }
  if(s.boardEffects.some((e,i)=>s.boardEffects.slice(i+1).some(f=>e.squares.some(q=>f.squares.includes(q)))))once('overlap');
  const v=playerView(before,side);
  for(const type of ['shelter','fog'] as const){
    const protectedSquares=type==='shelter'?s.pieceEffects.filter(e=>e.type==='shelter'&&e.owner===enemy).flatMap(e=>s.pieceIds.flatMap((id,i)=>id===e.pieceId?[i]:[])):s.boardEffects.filter(e=>e.type==='fog'&&e.owner===enemy).flatMap(e=>e.squares);
    for(const c of v.ownHand.filter(c=>['opponent_piece','opponent_slider'].includes(CARDS[c].target))){
      const targets=cardTargets(v,c),board=squares(s.fen);
      if(protectedSquares.some(q=>board[q]&&sideOf(board[q]!)===enemy&&board[q]!.toLowerCase()!=='k'&&!targets.includes(q)))once(type+'Blocked');
    }
  }
  if(s.phase==='chess'){
    const normal=normalMoves(s.fen,side),legal=legalRuleMoves(s,side,s.special),board=squares(s.fen);
    for(const type of ['locked_square','board_seal'] as const){const zones=s.boardEffects.filter(e=>e.type===type&&e.owner!==side).flatMap(e=>e.squares);
      if(normal.some(m=>zones.includes(m.to)&&!board[m.to]&&board[m.from]!.toLowerCase()!=='k'&&!legal.some(n=>n.uci===m.uci)))once(type+'Blocked');
      if(normal.some(m=>zones.includes(m.to)&&!!board[m.to]&&board[m.from]!.toLowerCase()!=='k'&&legal.some(n=>n.uci===m.uci)))once(type+'Capture');
    }
  }
  if(a.type==='move'){
    const m=legalRuleMoves(s,side,s.special).find(m=>m.uci===a.uci)!;
    if(s.special)bump('movement:'+s.special.card);if(m.castle)bump('castling');if(m.ep)bump('enPassant');if(m.promotion)bump('promotion');
    if(inCheck(t.fen,enemy))bump('checks');if(t.terminal?.reason==='checkmate')bump('checkmate');if(t.terminal?.reason==='stalemate')bump('stalemate');
    const moved=[s.pieceIds[m.from]];if(m.castle)moved.push(s.pieceIds[Math.floor(m.from/8)*8+(m.to%8===6?7:0)]);
    if(s.pieceEffects.some(e=>e.type==='mine_debuff'&&moved.includes(e.pieceId)&&!t.pieceEffects.some(p=>p.id===e.id)))bump('mineDebuffConsumed');
    for(const vow of s.vows.filter(e=>!t.vows.some(v=>v.id===e.id))){
      const capture=m.ep?m.to+(side==='w'?-8:8):m.to;
      const success=vow.type==='hunt'?vow.owner===side&&!s.special&&s.pieceIds[capture]===vow.pieceId:vow.owner===enemy&&vow.square!==null&&!!squares(t.fen)[vow.square]&&sideOf(squares(t.fen)[vow.square]!)===side;
      bump(vow.type+(success?'Success':'Failure'));
      if(vow.type==='watch'&&success&&s.boardEffects.some(e=>e.type==='mine'&&e.squares.includes(vow.square!)&&!t.boardEffects.some(f=>f.id===e.id)))bump('mineWatch');
    }
  }
}
async function scenario(f:Fixture,seed:number,generate?:{biased:boolean;steps:number},probe?:(s:AuthoritativeBattleState)=>Array<{a:Action;branch:string}>):Promise<void>{
  scenarioCount++;let s=initial(f),d=await ask({id:++sequence,initial:f});compare(s,d,f.fixtureId+':initial');
  const log={scenarioId:f.fixtureId,seed,initial:f,initialState:clone(s),actions:[] as Action[],rejections:[] as number[]};currentTrace=log;const seen=new Set<string>(),publicSecrets=new Map<string,string>();
  const invariants=(chessBoundary=false):void=>{
    const ownTurn=s.rules.ownTurns[s.rules.fen.split(' ')[1] as Side];
    if((s.rules.phase==='card'&&ownTurn>=2)||(s.rules.phase==='chess'&&ownTurn===1)){
      const key=publicFingerprint(s.rules),secrets=JSON.stringify({hands:s.hidden.hands,decks:s.hidden.decks}),previous=publicSecrets.get(key);
      if(previous!==undefined){assert.equal(secrets,previous,'same public fingerprint cannot conceal changed hands/decks over time');if(chessBoundary)repetitionChecks++;}publicSecrets.set(key,secrets);
    }
    if(log.actions.length%8!==0&&s.rules.phase!=='pending')return;
    const side=s.rules.fen.split(' ')[1] as Side,enemy=opposite(side),other=clone(s),v=playerView(s,side);
    const enemyCards=[...other.hidden.hands[enemy],...other.hidden.decks[enemy]].reverse();
    other.hidden.hands[enemy]=enemyCards.slice(0,s.rules.handCounts[enemy]);other.hidden.decks[enemy]=enemyCards.slice(s.rules.handCounts[enemy]);
    other.hidden.knowledge[enemy]={knownUpcomingCards:[],pendingCards:[],radarObservations:[]};
    // Preserve legitimate own reveal prefix; only unobserved own deck changes.
    const prefix=s.rules.phase==='pending'?v.knowledge.pendingCards.length:v.knowledge.knownUpcomingCards.length;
    other.hidden.decks[side]=[...other.hidden.decks[side].slice(0,prefix),...other.hidden.decks[side].slice(prefix).reverse()];
    const otherView=playerView(other,side);assert.deepEqual(otherView,v,'PlayerView contains no unrevealed secrets');
    assert.deepEqual(legalActions(otherView).map(actionKey).sort(),local(s).legal,'redacted legality independent of secrets');
    const changedBot=chooseBotAction(otherView);
    assert.equal(changedBot? actionKey(changedBot):null,local(s).bot,'bot uses only PlayerView');redactionChecks++;
  };
  invariants();
  const execute=async(a:Action,valid=true,branch?:string):Promise<void>=>{
    log.actions.push(a);if(!valid)log.rejections.push(log.actions.length-1);
    const before=s,encoded=JSON.stringify(before);if(valid)s=applyAuthoritative(s,a);else{assert.throws(()=>applyAuthoritative(s,a),/illegal-action/);assert.equal(JSON.stringify(before),encoded);if(branch)illegal[branch]=(illegal[branch]??0)+1;}
    d=await ask({id:++sequence,state:d.state,action:a});compare(s,d,f.fixtureId+':'+log.actions.length,valid?null:'illegal-action');if(valid)coverage(before,s,a,seen);invariants(valid&&a.type==='move');
  };
  if(probe)for(const p of probe(s))await execute(p.a,false,p.branch);
  const random=rng(seed);
  if(generate){for(let i=0;i<generate.steps&&s.rules.phase!=='terminal';i++){
    const all=legalActions(playerView(s,s.rules.fen.split(' ')[1] as Side));if(!all.length)throw new Error('nonterminal-stuck');
    const plays=all.filter(a=>a.type==='play'),pool=generate.biased&&plays.length&&random()<.9?plays:!generate.biased&&s.rules.phase==='card'&&random()<.65?all.filter(a=>a.type==='pass'||a.type==='discard'):all;
    await execute(pool[Math.floor(random()*pool.length)]!);
  }}else for(const step of f.steps){
    const keys=legalActions(playerView(s,s.rules.fen.split(' ')[1] as Side)).map(actionKey);
    for(const k of step.contains??[])assert.ok(keys.includes(k),f.fixtureId+' missing '+k);
    for(const k of step.excludes??[])assert.ok(!keys.includes(k),f.fixtureId+' extra '+k);
    if(step.action)await execute(step.action,step.legal!==false,step.legal===false?step.branch??f.fixtureId:undefined);
    for(const [path,expected]of Object.entries(step.expect??{}))assert.deepEqual(at(s,path),expected,f.fixtureId+' '+path);
  }
}
const BASE='4k3/1p2r3/8/8/3p4/2P1B3/PP1N4/R3K2R w KQ - 0 1';
function target(id:string,fen:string,rules:Record<string,unknown>,steps:FixtureStep[],first:CardId[]=['radar']):Fixture {
  return {fixtureId:id,intent:id,fen,ready:true,whiteDeckOrder:deck(first),blackDeckOrder:[...STARTER],setup:{rules},steps};
}
const be=(id:string,type:string,sq:number[],duration='move',owner:Side='b'):unknown=>({id,type,squares:sq,duration,owner,responseSide:opposite(owner)});
const pe=(id:string,type:string,pieceId:string,duration='move',owner:Side='b'):unknown=>({id,type,pieceId,duration,owner,responseSide:opposite(owner)});
const modifier=(type:string,targetCard:CardId|null,ownTurn=2):unknown=>({id:type,type,owner:type==='discount'?'w':'b',responseSide:'w',targetCard,ownTurn});
const pass:Action={type:'pass'},move=(uci:string):Action=>({type:'move',uci}),play=(card:CardId,target?:number|string,sacrifice?:CardId):Action=>({type:'play',card,...(target===undefined?{}:{target}),...(sacrifice?{sacrifice}:{})});

async function main():Promise<void>{
  for(const f of fixtures)await scenario(f,0);
  // Two distinct generator families. A single harness generates explicit decks.
  for(const biased of [false,true])for(let seed=1;seed<=24;seed++){
    const random=rng(seed+(biased?10000:0)),f:Fixture={fixtureId:(biased?'card-biased':'natural')+'-'+seed,intent:'seeded legal game',whiteDeckOrder:shuffled(cards,random).slice(0,10),blackDeckOrder:shuffled(cards,random).slice(0,10),steps:[]};
    await scenario(f,seed,{biased,steps:80});
  }
  // Vary unused deck order, clock and fullmove across deterministic edge cases.
  for(let variant=0;variant<20;variant++){
    for(const original of fixtures.filter(f=>f.ready&&f.fixtureId!=='discard-once'&&f.fixtureId!=='low-mana')){
      const f=clone(original);f.fixtureId+='-v'+variant;
      if(f.fen){const fields=f.fen.split(' ');fields[4]=String(variant);fields[5]=String(variant+1);f.fen=fields.join(' ');}
      // Geometry goldens use original clocks; keep other manually authored checks.
      for(const step of f.steps)if(step.expect)delete step.expect['rules.fen'];
      const tail=f.whiteDeckOrder.slice(6);f.whiteDeckOrder=[...f.whiteDeckOrder.slice(0,6),...tail.slice(variant%4),...tail.slice(0,variant%4)];
      await scenario(f,variant);
    }
    await scenario(target('ep-'+variant,'7k/8/8/3pP3/8/8/8/4K3 w - d6 0 1',{phase:'chess',boardEffects:[be('mine','mine',[43],'persistent')]},[{action:move('e5d6')}]),variant);
    await scenario(target('promote-'+variant,'k6r/6P1/8/8/8/8/8/4K3 w - - 0 1',{phase:'chess'},[{action:move('g7h8'+(['q','r','b','n'][variant%4]))}]),variant);
    await scenario(target('hunt-success-'+variant,'7k/8/8/8/8/8/p7/R3K3 w - - 0 1',{},[{action:play('hunt_vow',8)},{action:move('a1a2')}],['hunt_vow']),variant);
    await scenario(target('hunt-fail-'+variant,'7k/8/8/8/8/8/p7/R3K3 w - - 0 1',{},[{action:play('hunt_vow',8)},{action:move('e1f1')},{action:pass},{action:move('h8g8')},{action:pass},{action:move('f1g1')}],['hunt_vow']),variant);
    await scenario(target('watch-fail-'+variant,'7k/8/8/8/8/8/8/4K3 w - - 0 1',{},[{action:play('watch_vow',20)},{action:move('e1f1')},{action:pass},{action:move('h8g8')}],['watch_vow']),variant);
    for(const consumed of [false,true])await scenario(target('contract-'+consumed+'-'+variant,BASE,{modifiers:[modifier('discount',null)]},[{action:consumed?play('radar','radar'):pass}]),variant);
    await scenario(target('radar-positive-'+variant,BASE,{},[{action:play('radar','radar')}]),variant);
  }
  // Meaningful rejection branches have an explicit, enforced coverage registry.
  for(let variant=0;variant<5;variant++)for(const card of cards){
    const original=fixtures.find(f=>f.fixtureId==='card-'+card)!,a=original.steps[0]!.action!;
    for(const [name,rules]of [['mana',{mana:{w:0,b:6}}],['phase',{phase:'chess'}],['first-turn',{ownTurns:{w:1,b:2}}]] as const){
      const f=clone(original);f.fixtureId='reject-'+card+'-'+name+'-'+variant;f.steps=[];f.setup={rules:{...f.setup?.rules,...rules}};
      await scenario(f,variant,undefined,()=>[{a,branch:card+':'+name}]);
    }
    const f=clone(original);f.fixtureId='reject-'+card+'-target-'+variant;f.steps=[];
    await scenario(f,variant,undefined,()=>[{a:{...a,target:'invalid'} as Action,branch:card+':target'}]);
    const unowned=clone(original);unowned.fixtureId='reject-'+card+'-not-held-'+variant;unowned.steps=[];
    unowned.whiteDeckOrder=[...unowned.whiteDeckOrder.slice(1,4),unowned.whiteDeckOrder[0]!,...unowned.whiteDeckOrder.slice(4)];
    await scenario(unowned,variant,undefined,()=>[{a,branch:card+':not-held'}]);
  }
  const minima:Record<string,number>={castling:20,enPassant:20,promotion:20,checks:50,checkmate:10,stalemate:10,mineTrigger:20,mineRemoved:20,mineDebuffConsumed:20,huntSuccess:20,huntFailure:20,watchSuccess:20,watchFailure:20,mineWatch:10,overlap:20,breakOverlap:20,contractConsumed:20,contractExpired:20,radarPositive:20,radarNegative:20,radarStale:20,shelterBlocked:20,fogBlocked:20,locked_squareBlocked:20,locked_squareCapture:20,board_sealBlocked:20,board_sealCapture:20};
  for(const card of cards)minima['card:'+card]=20;
  for(const card of ['pawn_deviation','pawn_advance','rook_bend','angry_n','shadow_pass'])minima['movement:'+card]=20;
  for(const [key,min]of Object.entries(minima))assert.ok((counts[key]??0)>=min,`coverage ${key}: ${counts[key]??0} < ${min}`);
  const illegalMinima=Object.fromEntries([...cards.flatMap(c=>['mana','phase','first-turn','target','not-held'].map(b=>c+':'+b)),...fixtures.flatMap(f=>f.steps.filter(s=>s.branch).map(s=>s.branch!))].map(key=>[key,5]));
  for(const [branch,min]of Object.entries(illegalMinima))assert.ok((illegal[branch]??0)>=min,'illegal coverage '+branch);
  assert.ok(repetitionChecks>0,'public repetition invariant must revisit a fingerprint');
  writeFileSync(resolve(qa,'v201a-differential-summary.json'),JSON.stringify({scenarioCount,stateCount,legalSetsCompared:setCount,legalSetDivergences:0,resultingStateDivergences:0,repetitionChecks,redactionChecks,counts,illegal,minima,illegalMinima},null,2));
  console.log(JSON.stringify({scenarioCount,stateCount,setCount,counts,illegal},null,2));
}
main().catch(error=>{writeFileSync(resolve(qa,'v201a-differential-failure.json'),JSON.stringify({message:String(error),stack:error.stack,scenario:currentTrace},null,2));console.error(error);process.exitCode=1;}).finally(()=>{child.stdin.end();lines.close();child.kill();});
