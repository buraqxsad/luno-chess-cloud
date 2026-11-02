'use strict';
const fs=require('node:fs'),Module=require('node:module');
const original='/workspace/luno-chess/functions/index.js';
const candidate=process.argv[2],test=process.argv[3];
const loaded=new Module(original,module);loaded.filename=original;loaded.paths=Module._nodeModulePaths('/workspace/luno-chess/functions');require.cache[original]=loaded;loaded._compile(fs.readFileSync(candidate,'utf8'),original);loaded.loaded=true;require(test);
