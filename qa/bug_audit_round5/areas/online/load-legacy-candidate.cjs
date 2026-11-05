const fs=require('node:fs'),Module=require('node:module'),original=Module._extensions['.js'];
Module._extensions['.js']=function(module,filename){if(filename==='/workspace/luno-chess/functions/index.js')return module._compile(fs.readFileSync('/workspace/luno-review/bug-audit-round5/online/candidate-index-legacy.js','utf8'),filename);return original(module,filename);};
