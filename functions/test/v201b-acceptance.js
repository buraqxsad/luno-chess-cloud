'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'../..'),qa=path.join(root,'luno_chess/qa');
const read=name=>fs.readFileSync(path.join(qa,name),'utf8');
const json=name=>JSON.parse(read(name));
const security=json('v201b-gate1-security.json'),integration=json('v201b-gate5-production.json');
assert.equal(security.pass,true);assert.equal(security.allowed,4);assert.equal(security.denied,42);
assert.equal(integration.pass,true);assert.equal(integration.fixtureCount,113);
assert.equal(integration.allowed,5);assert.equal(integration.denied,42);
assert.equal(integration.forgedRejected,29);assert.equal(integration.authenticationRejected,4);assert.equal(integration.fixtureActions,145);
assert.equal(integration.fixtureIllegal,81);assert.equal(integration.reconnectChecks,292);
assert.equal(integration.sideChannelPairs,4);assert.equal(integration.concurrentReplays,6);
assert.equal(integration.maintenanceBatches,2);
for(const log of ['v201b-gate1-emulator.txt','v201b-gate5-emulator.txt']){
 const text=read(log);assert.match(text,/Script exited successfully \(code 0\)/);
 assert.doesNotMatch(text,/Script exited unsuccessfully|unexpected error has occurred|Error: Script/);
}
const differential=json('v201b-differential-summary.json');
assert.equal(differential.scenarioCount,3101);assert.equal(differential.stateCount,10967);
assert.equal(differential.legalSetsCompared,10967);
assert.equal(differential.legalSetDivergences,0);assert.equal(differential.resultingStateDivergences,0);
for(const [key,minimum] of Object.entries(differential.minima))assert((differential.counts[key]||0)>=minimum,key);
for(const [key,minimum] of Object.entries(differential.illegalMinima))assert((differential.illegal[key]||0)>=minimum,key);
assert(differential.repetitionChecks>0);
const perft=JSON.parse(read('v201b-dart-perft.txt').split(/\r?\n/).find(s=>s.startsWith('{')));
assert.equal(perft.results.length,26);assert(perft.results.every(r=>r.pass&&r.actual===r.expected));
const flutter=read('v201b-full-flutter.txt');
const flutterMatch=flutter.match(/\+(\d+): All tests passed!/);
assert(flutterMatch,'Full Flutter regression did not pass');
const flutterTests=Number(flutterMatch[1]);assert(flutterTests>=3041,'Flutter test coverage fell below the V201-B baseline');
const nodeTotal=name=>{const text=read(name);assert.match(text,/fail 0/);assert.match(text,/skipped 0/);return Number(text.match(/tests (\d+)/)[1]);};
assert.equal(nodeTotal('v201b-full-backend.txt'),806);assert.equal(nodeTotal('v201b-ts-contract.txt'),229);
assert.match(read('v201b-analyze.txt'),/No issues found!/);
assert.equal(read('v201b-ts-typecheck.txt').trim(),'');
const lib=path.join(root,'luno_chess/lib');
function dartFiles(dir){return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?dartFiles(path.join(dir,e.name)):e.name.endsWith('.dart')?[path.join(dir,e.name)]:[]);}
const relative=file=>path.relative(root,file).replaceAll('\\','/');
const battleUiSources=[...dartFiles(path.join(lib,'battle_ui')),...dartFiles(path.join(lib,'battle_v1')),path.join(lib,'i18n/battle_v1_copy.dart')].map(relative);
const battleUiTests=[...dartFiles(path.join(root,'luno_chess/test/battle_ui')),...dartFiles(path.join(root,'luno_chess/test/battle_v1')),path.join(root,'luno_chess/test/result_rematch_test.dart')].map(relative);
const battleArt=fs.readdirSync(path.join(root,'luno_chess/assets/native_art')).filter(f=>f.startsWith('battle-v202b-')).map(f=>`luno_chess/assets/native_art/${f}`);
const allFlutterSources=dartFiles(lib).map(relative);
const allFlutterTests=dartFiles(path.join(root,'luno_chess/test')).map(relative);
for(const file of dartFiles(lib)){
 if(['game_screen.dart','online_match_screen.dart'].includes(path.basename(file)))continue;
 const source=fs.readFileSync(file,'utf8');
 assert.doesNotMatch(source,/\b(?:GameScreen|OnlineMatchScreen)\s*\(/,file);
 assert.doesNotMatch(source,/import [^;]*(?:game_screen|online_match_screen)\.dart/,file);
}
const freshness={
 'v201b-full-flutter.txt':[...allFlutterSources,...allFlutterTests,...battleArt],
 'v201b-analyze.txt':[...allFlutterSources,...allFlutterTests],
 'v201b-full-backend.txt':['functions/index.js','functions/lib/battle-v1-recovery.js','functions/rules-v1/src/online/authority.ts'],
 'v201b-ts-contract.txt':['functions/rules-v1/src/online/protocol.ts','functions/rules-v1/src/online/authority.ts','functions/rules-v1/src/online/migration.ts'],
 'v201b-gate1-emulator.txt':['database.rules.production.json','functions/test/v201b-security.integration.js'],
 'v201b-gate5-emulator.txt':['functions/test/v201b-production.integration.js','functions/lib/battle-v1-recovery.js','functions/rules-v1/src/online/authority.ts'],
 'v201b-differential-summary.json':['luno_chess/lib/battle_v1/authoritative.dart','luno_chess/lib/battle_v1/core.dart','functions/rules-v1/src/authoritative.ts','functions/rules-v1/src/core.ts','battle_contract/v1/rules.json'],
};
for(const [log,files] of Object.entries(freshness))for(const file of files)assert(fs.statSync(path.join(qa,log)).mtimeMs>=fs.statSync(path.join(root,file)).mtimeMs,`Stale evidence: ${log} predates ${file}`);
const evidence=['v201b-gate1-emulator.txt','v201b-gate1-security.json','v201b-gate5-emulator.txt','v201b-gate5-production.json','v201b-differential.txt','v201b-differential-summary.json','v201b-dart-perft.txt','v201b-ts-contract.txt','v201b-full-flutter.txt','v201b-full-backend.txt','v201b-analyze.txt','v201b-ts-typecheck.txt'];
const sources=['functions/index.js','functions/lib/battle-v1.js','functions/lib/battle-v1-rollout.js','functions/lib/battle-v1-recovery.js','functions/lib/battle-v1-rating.js','functions/lib/battle-v1-friendly.js','functions/rules-v1/src/online/protocol.ts','functions/rules-v1/src/online/authority.ts','functions/rules-v1/src/online/migration.ts','database.rules.production.json','luno_chess/lib/battle_v1/online.dart','luno_chess/lib/battle_v1/local_clock.dart','luno_chess/lib/screens/battle_v1_screen.dart','battle_contract/v1/cards.json','battle_contract/v1/rules.json','battle_contract/v1/perft.json'];
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const report={status:'V201-B LOCAL ACCEPTANCE PASSED',generatedAt:new Date().toISOString(),liveDeployed:false,apkAabGenerated:false,gates:[1,2,3,4,5],flutterTests,backendTests:806,typeScriptTests:229,dartPerftChecks:26,mandatoryPerftEachLanguage:20,differentialScenarios:3101,differentialStates:10967,evidenceHashes:Object.fromEntries(evidence.map(file=>[file,hash(path.join(qa,file))])),sourceHashes:Object.fromEntries([...new Set([...sources,...battleUiSources,...battleArt])].map(file=>[file,hash(path.join(root,file))]))};
fs.writeFileSync(path.join(qa,'v201b-acceptance.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report,null,2));
