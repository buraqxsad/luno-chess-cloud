'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'../..'),qa=path.join(root,'luno_chess/qa');
const read=name=>fs.readFileSync(path.join(qa,name),'utf8');
const json=name=>JSON.parse(read(name));
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const collect=(dir,pattern)=>fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>{
  const file=path.join(dir,e.name);
  return e.isDirectory()?collect(file,pattern):pattern.test(e.name)?[file]:[];
});
const security=json('v214-gate1-security.json'),production=json('v214-gate5-production.json');
assert.equal(security.pass,true);assert.equal(security.allowed,4);assert.equal(security.denied,42);
for(const [key,value]of Object.entries({pass:true,fixtureCount:113,allowed:5,denied:42,forgedRejected:29,authenticationRejected:4,fixtureActions:145,fixtureIllegal:81,reconnectChecks:292,sideChannelPairs:4,concurrentReplays:6,maintenanceBatches:2}))assert.equal(production[key],value,key);
const emulator=read('v214-emulator-acceptance-green.txt');
assert.match(emulator,/Script exited successfully \(code 0\)/);
for(const script of ['v201b-security.integration.js','v201b-production.integration.js','v214-social-safety.integration.js'])assert(emulator.includes(script+': passed'));
assert.doesNotMatch(emulator,/Script exited unsuccessfully|unexpected error has occurred/);
const differential=json('v214-differential-summary.json');
assert.equal(differential.scenarioCount,3101);assert.equal(differential.stateCount,10967);
assert.equal(differential.legalSetsCompared,10967);
assert.equal(differential.legalSetDivergences,0);assert.equal(differential.resultingStateDivergences,0);
for(const [key,min]of Object.entries(differential.minima))assert((differential.counts[key]||0)>=min,key);
for(const [key,min]of Object.entries(differential.illegalMinima))assert((differential.illegal[key]||0)>=min,key);
assert(differential.repetitionChecks>0);
const perft=JSON.parse(read('v214-dart-perft.txt').split(/\r?\n/).find(line=>line.startsWith('{')));
assert.equal(perft.results.length,26);assert(perft.results.every(row=>row.pass&&row.actual===row.expected));
const flutter=read('v214-full-flutter-green.txt').match(/\+(\d+): All tests passed!/);
assert(flutter,'Full Flutter regression did not pass');
const flutterTests=Number(flutter[1]);assert(flutterTests>=4505,'Coverage below prior full baseline');
const total=name=>{
 const text=read(name);assert.match(text,/fail 0/);assert.match(text,/skipped 0/);assert.match(text,/cancelled 0/);
 return Number(text.match(/tests (\d+)/)[1]);
};
const backendTests=total('v214-full-backend-green.txt');assert(backendTests>=907);
const typeScriptTests=total('v214-ts-contract.txt');assert.equal(typeScriptTests,229);
assert.match(read('v214-analyze-green.txt'),/No issues found!/);
assert.equal(read('v214-ts-typecheck.txt').trim(),'');
const dartSources=[...collect(path.join(root,'luno_chess/lib'),/\.dart$/),...collect(path.join(root,'luno_chess/test'),/\.dart$/)];
const tsSources=[...collect(path.join(root,'functions/rules-v1/src'),/\.ts$/),...collect(path.join(root,'functions/rules-v1/test'),/\.ts$/)];
const backendSources=[path.join(root,'functions/index.js'),...collect(path.join(root,'functions/lib'),/\.js$/),...collect(path.join(root,'functions/test'),/\.js$/)];
for(const [log,files]of Object.entries({
 'v214-full-flutter-green.txt':dartSources,
 'v214-analyze-green.txt':[...dartSources,path.join(root,'luno_chess/analysis_options.yaml')],
 'v214-full-backend-green.txt':backendSources,
 'v214-ts-contract.txt':tsSources,
 'v214-emulator-acceptance-green.txt':[path.join(root,'database.rules.production.json'),...backendSources,...tsSources],
 'v214-differential-summary.json':[
  ...collect(path.join(root,'luno_chess/lib/battle_v1'),/^(authoritative|core|model)\.dart$/),
  ...collect(path.join(root,'functions/rules-v1/src'),/^(authoritative|core|model)\.ts$/),
 ],
}))for(const file of files)assert(fs.statSync(path.join(qa,log)).mtimeMs>=fs.statSync(file).mtimeMs,`${log} predates ${path.relative(root,file)}`);
const sourceLock=json('rc/source-lock.json');
for(const [relative,expected]of Object.entries(sourceLock.files))assert.equal(hash(path.resolve(root,'luno_chess',relative)),expected,`Source lock mismatch: ${relative}`);
const evidence=['v214-full-flutter-green.txt','v214-full-backend-green.txt','v214-analyze-green.txt','v214-ts-contract.txt','v214-ts-typecheck.txt','v214-dart-perft.txt','v214-differential-summary.json','v214-emulator-acceptance-green.txt','v214-gate1-security.json','v214-gate5-production.json','rc/source-lock.json','rc/asset-audit.json'];
const report={status:'V214 CURRENT-SOURCE LOCAL TECHNICAL ACCEPTANCE PASSED',generatedAt:new Date().toISOString(),flutterTests,backendTests,typeScriptTests,perftChecks:26,differentialScenarios:3101,differentialStates:10967,sourceFiles:Object.keys(sourceLock.files).length,liveDeployed:false,apkAabGenerated:false,deviceVerified:false,evidenceHashes:Object.fromEntries(evidence.map(name=>[name,hash(path.join(qa,name))]))};
fs.writeFileSync(path.join(qa,'v214-local-acceptance.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report,null,2));
