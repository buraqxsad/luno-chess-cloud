'use strict';
const {requireLocalEmulators}=require('./helpers/local-emulators');
requireLocalEmulators();
const {spawnSync}=require('node:child_process');
const fs=require('node:fs'),path=require('node:path');
const qa=path.resolve(__dirname,'../../luno_chess/qa');
const checks=[
  ['v201b-security.integration.js','v201b-gate1-security.json','v214-gate1-security.json'],
  ['v201b-production.integration.js','v201b-gate5-production.json','v214-gate5-production.json'],
  ['v214-social-safety.integration.js',null,null],
];
for(const [script,from,to] of checks){
  const result=spawnSync(process.execPath,[path.join(__dirname,script)],{env:process.env,encoding:'utf8',timeout:180000});
  fs.writeFileSync(path.join(qa,`v214-${script}.txt`),(result.stdout||'')+(result.stderr||''));
  if(result.status!==0){
    process.stderr.write(`${script} failed: ${result.error||result.status}\n${result.stderr||''}`);
    process.exit(1);
  }
  if(from)fs.copyFileSync(path.join(qa,from),path.join(qa,to));
  process.stdout.write(`${script}: passed\n`);
}
