from pathlib import Path
import hashlib,json,subprocess,difflib
repo=Path('/workspace/luno-chess');out=Path('/workspace/luno-review/bug-audit-round2/runtime/sdk-proof');out.mkdir(exist_ok=True)
base=Path('/workspace/luno-review/system-bug-hunt/economy/sdk-proof/inherited-proxy-timeout')
s=(base/'fences.cjs').read_text().replace('demo-luno-billing-fence','demo-luno-billing-fence-r2')
assert 'ExactLoopbackNativeClient' not in s
insert="""
// The Admin SDK embeds its own websocket client inside database-compat/standalone.
// Compile exactly one transport-condition change in memory. SDK files and all
// database data/transaction logic remain byte-identical on disk and in memory.
const standalonePath=req.resolve('@firebase/database-compat/standalone');
assert.equal(require.cache[standalonePath],undefined);
const standaloneOriginal=readFileSync(standalonePath,'utf8');
const transportNeedle="if (proxy) {\\n                    options['proxy'] = { origin: proxy };\\n                }";
assert.equal(standaloneOriginal.split(transportNeedle).length-1,1);
const transportAudit={selected_connections:0,rejected_other_urls:0,headers_or_proxy_environment_changed:false,smoke_pass:false};
const proxyKeys=['HTTP_PROXY','HTTPS_PROXY','http_proxy','https_proxy','NO_PROXY','no_proxy'];
const inheritedProxyValues=Object.fromEntries(proxyKeys.map(key=>[key,process.env[key]]));
assert.ok(process.env.HTTP_PROXY||process.env.http_proxy,'This proof diagnoses the inherited-proxy path.');
function saveAudit(){transportAudit.inherited_proxy_environment_unchanged=proxyKeys.every(key=>process.env[key]===inheritedProxyValues[key]);writeFileSync(resolve(dirname(__filename),'transport-audit.json'),JSON.stringify(transportAudit,null,2)+'\\n');}
globalThis.__LUNO_PROOF_LOOPBACK__=url=>{
 const parsed=new URL(url);
 if(parsed.protocol!=='ws:'||parsed.hostname!=='127.0.0.1'||parsed.port!=='19000'||parsed.pathname!=='/.ws'||parsed.searchParams.get('ns')!==namespace||parsed.username||parsed.password){transportAudit.rejected_other_urls++;saveAudit();throw new Error('Proof refuses a non-local emulator socket.');}
 transportAudit.selected_connections++;saveAudit();return true;
};
const standalonePatched=standaloneOriginal.replace(transportNeedle,transportNeedle.replace('if (proxy)', 'if (proxy && !globalThis.__LUNO_PROOF_LOOPBACK__(this.connURL))'));
const standaloneModule=new Module(standalonePath,module);standaloneModule.filename=standalonePath;standaloneModule.paths=Module._nodeModulePaths(dirname(standalonePath));require.cache[standalonePath]=standaloneModule;standaloneModule._compile(standalonePatched,standalonePath);standaloneModule.loaded=true;
const transportProvenance={standalone_module:standalonePath,original_sha256:createHash('sha256').update(standaloneOriginal).digest('hex'),in_memory_sha256:createHash('sha256').update(standalonePatched).digest('hex'),exact_replaced_blocks:1,changed_transport_condition_only:true,repo_or_sdk_disk_files_modified:false};
writeFileSync(resolve(dirname(__filename),'transport-provenance.json'),JSON.stringify(transportProvenance,null,2)+'\\n');
"""
s=s.replace("const root=dirname(__filename),original=",insert+"\nconst root=dirname(__filename),original=",1)
# Original first-run harness has createHash import, retained at its top.
assert "const {createHash}=require('node:crypto');" in s
s=s.replace("test.after(async()=>{await Promise.all(getApps().map(deleteApp));});", """test.before(async()=>{
 const timer=setTimeout(()=>{},3000);clearTimeout(timer);
 let timeout;
 try{
  await Promise.race([(async()=>{await checker.ref('round2Smoke').set({value:7});assert.equal((await checker.ref('round2Smoke/value').get()).val(),7);await checker.ref('round2Smoke').remove();})(),new Promise((_,reject)=>{timeout=setTimeout(()=>reject(new Error('3s isolated SDK seed/read smoke failed.')),3000);})]);
  transportAudit.smoke_pass=true;saveAudit();
 }finally{clearTimeout(timeout);}
});
test.after(async()=>{await Promise.all(getApps().map(deleteApp));saveAudit();assert.equal(transportAudit.inherited_proxy_environment_unchanged,true);assert.equal(createHash('sha256').update(readFileSync(standalonePath)).digest('hex'),transportProvenance.original_sha256);});""")
assert 'test.before' in s
(out/'fences.cjs').write_text(s)
source=subprocess.check_output(['git','show','b1b9c7a2f76282c6588383d5ab7926ec8b438e5f:functions/index.js'],cwd=repo)
assert hashlib.sha256(source).hexdigest()=='5b0a8ef98fd05ee3d8414db884b617fdef44881c2c3c27ade8be5fbaa82aaf59'
(out/'fixed-index.cjs').write_bytes(source)
# Record the exact one-line transport condition change without changing SDK disk.
standalone=repo/'functions/node_modules/@firebase/database-compat/dist/index.standalone.js'
original=standalone.read_text();needle="if (proxy) {\n                    options['proxy'] = { origin: proxy };\n                }"
assert original.count(needle)==1
modified=original.replace(needle,needle.replace('if (proxy)','if (proxy && !globalThis.__LUNO_PROOF_LOOPBACK__(this.connURL))'))
(out/'standalone-transport.patch').write_text(''.join(difflib.unified_diff(original.splitlines(True),modified.splitlines(True),fromfile='installed-standalone.js (unchanged on disk)',tofile='in-memory-standalone.js')))
print('Prepared external SDK proof with exactly one in-memory transport condition change.')
