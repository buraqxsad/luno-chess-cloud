const {Module}=require('node:module');
const {readFileSync}=require('node:fs');
const {dirname,resolve}=require('node:path');
for(const [original,captured] of [
 ['/workspace/luno-chess/functions/lib/battle-v1-rollout.js',resolve(__dirname,'baseline-rollout.js')],
 ['/workspace/luno-chess/functions/lib/battle-v1-friendly.js',resolve(__dirname,'friendly-before.js')],
 ['/workspace/luno-chess/functions/index.js',resolve(__dirname,'baseline-index.js')],
]){
 const loaded=new Module(original,module);loaded.filename=original;loaded.paths=Module._nodeModulePaths(dirname(original));
 loaded._compile(readFileSync(captured,'utf8'),original);loaded.loaded=true;require.cache[original]=loaded;
}
