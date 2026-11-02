'use strict';
const fs=require('node:fs'),Module=require('node:module');
const root='/workspace/luno-chess/';
const replacements=new Map([['functions/index.js','index.js'],['functions/lib/battle-v1-recovery.js','battle-v1-recovery.js']].map(([name,file])=>[root+name,__dirname+'/'+file]));
const original=Module._extensions['.js'];
Module._extensions['.js']=function(module,filename){const replacement=replacements.get(filename);if(replacement)return module._compile(fs.readFileSync(replacement,'utf8'),filename);return original(module,filename);};
