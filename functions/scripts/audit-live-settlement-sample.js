'use strict';
const {execFileSync}=require('node:child_process');
const {createHash}=require('node:crypto');
const {auditSettlements}=require('../lib/settlement-audit');

// Explicitly scoped read-only CLI calls; raw player data stays in memory.
function main(){
  const cli=process.argv[2];
  if(!cli||process.argv.length!==3)throw new Error('Provide the installed firebase CLI JavaScript entrypoint.');
  let reads=0;
  function read(path,extra=[]){
    reads++;
    const output=execFileSync(process.execPath,[cli,'database:get',path,'--project','luno-chess',
      '--instance','luno-chess-default-rtdb',...extra],{encoding:'utf8',timeout:60000,maxBuffer:8*1024*1024,stdio:['ignore','pipe','pipe']});
    return JSON.parse(output);
  }
  const matches=read('/rankedState/matches',['--order-by-key','--start-at','rm_','--limit-to-first','1'])||{};
  const root={rankedState:{matches,activeByUser:{}},users:{},rankedPlayers:{},matchHistory:{},rankedReplays:{},rankedMatchViews:{}};
  for(const [id,match] of Object.entries(matches)){
    if(!/^rm_[a-f0-9]{32}$/.test(id))throw new Error('Unexpected match key; audit stopped.');
    for(const color of ['W','B']){
      const uid=match.players?.[color]?.uid;
      if(typeof uid!=='string'||!uid||/[.#$\[\]\/\x00-\x1f\x7f]/.test(uid))throw new Error('Invalid participant key; audit stopped.');
      const exists=read(`/users/${uid}`,['--shallow']);
      if(exists){
        const key=createHash('sha256').update(uid+'|'+id).digest('hex').slice(0,48);
        const ledger=read(`/users/${uid}/serverProgress/rankedSettlements/${key}`);
        root.users[uid]={serverProgress:{rankedSettlements:{[key]:ledger}}};
      }
      for(const branch of ['matchHistory','rankedReplays','rankedMatchViews']){
        root[branch][uid]={[id]:read(`/${branch}/${uid}/${id}`)};
      }
      root.rankedState.activeByUser[uid]=read(`/rankedState/activeByUser/${uid}`);
      root.rankedPlayers[uid]=read(`/rankedPlayers/${uid}`);
    }
    // Independent reads are not an atomic snapshot. Detect a changed source match.
    const after=read(`/rankedState/matches/${id}`);
    if(JSON.stringify(after)!==JSON.stringify(match))throw new Error('Match changed during audit; rerun against stable data.');
  }
  return {project:'luno-chess',selection:'first ranked match by key; not representative',reads,
    observedAt:new Date().toISOString(),...auditSettlements(root)};
}
try{process.stdout.write(JSON.stringify(main(),null,2)+'\n');}
catch(error){
  // Do not echo CLI buffers or potentially sensitive server responses.
  process.stderr.write('Read-only live audit failed: '+(error.status!==undefined?'Firebase CLI read failed.':error.message)+'\n');
  process.exitCode=1;
}
