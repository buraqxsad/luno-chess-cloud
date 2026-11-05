const fs=require('node:fs'),Module=require('node:module');
const original=Module._extensions['.js'];
const root='/workspace/luno-chess/functions/';
Module._extensions['.js']=function(module,filename){
 if(filename===root+'lib/battle-v1-friendly.js')return module._compile(fs.readFileSync('/workspace/luno-review/bug-audit-round5/online/candidate-battle-v1-friendly.js','utf8'),filename);
 if(filename===root+'lib/battle-v1-recovery.js'){
  let source=fs.readFileSync(filename,'utf8');
  const old="if(v.lastMatch?.[context.uid]===m.matchId)delete v.lastMatch[context.uid];return v;},undefined,false);return {ok:true,acknowledged:true};";
  if(!source.includes(old))throw new Error('ACK proposal anchor missing');
  return module._compile(source.replace(old,"if(v.active?.[context.uid]===m.matchId)delete v.active[context.uid];"+old),filename);
 }
 if(filename===root+'index.js'){
  let source=fs.readFileSync(filename,'utf8');const old='    await battleV1.leaveAccount(uid);\n';
  if(!source.includes(old))throw new Error('Erasure proposal anchor missing');
  return module._compile(source.replace(old,old+'    await battleV1.eraseAccountHistory(uid,deletionRef);\n'),filename);
 }
 return original(module,filename);
};
