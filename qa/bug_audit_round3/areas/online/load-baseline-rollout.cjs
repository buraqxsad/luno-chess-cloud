'use strict';
const fs=require('node:fs'),Module=require('node:module');
const target='/workspace/luno-chess/functions/lib/battle-v1-rollout.js';
const original=Module._extensions['.js'];
Module._extensions['.js']=function(module,filename){if(filename===target)return module._compile(fs.readFileSync(__dirname+'/baseline-battle-v1-rollout.js','utf8'),filename);return original(module,filename);};
