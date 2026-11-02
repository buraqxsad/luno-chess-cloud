'use strict';
const {spawnSync}=require('node:child_process');
const fs=require('node:fs');
const out='/workspace/luno-review/bug-audit-round3/rules';
const root='/workspace/luno-chess';
const files=['v218-rule-actions','v223-removal-identity','v224-card-wire-targets'];
const rows=[];
for(const name of files){
  const run=spawnSync(process.execPath,[root+'/functions/rules-v1/dist/test/'+name+'.test.js'],{cwd:root,encoding:'utf8',timeout:120000,maxBuffer:8*1024*1024,env:{...process.env,LUNO_DART_RUNNER:'/workspace/luno-review/bug-audit-round3/rules/round3-rules-dart-runner.sh',LUNO_DIFFERENTIAL_QA:out}});
  const log=run.stdout+run.stderr;fs.writeFileSync(out+'/'+name+'.log',log);
  const counts={};for(const key of ['tests','pass','fail','skipped','cancelled'])counts[key]=Number(log.match(new RegExp('^# '+key+' (\\d+)$','m'))?.[1]??-1);
  rows.push({file:name+'.test.js',exitCode:run.status,error:run.error?.message??null,...counts});
  if(run.status!==0||run.error||counts.tests<1||counts.fail!==0||counts.skipped!==0)throw new Error(JSON.stringify(rows));
}
fs.writeFileSync(out+'/targeted-node-result.json',JSON.stringify({status:'PASS',rows,counts:rows.reduce((a,r)=>({tests:a.tests+r.tests,pass:a.pass+r.pass,fail:a.fail+r.fail,skipped:a.skipped+r.skipped}),{tests:0,pass:0,fail:0,skipped:0})},null,2)+'\n');
console.log(JSON.stringify(rows));
