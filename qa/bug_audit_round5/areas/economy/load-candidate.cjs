const Module=require('node:module'),fs=require('node:fs');
const old=Module._extensions['.js'];
const replacements={
 '/workspace/luno-chess/functions/index.js':__dirname+'/candidate-index.js',
 '/workspace/luno-chess/functions/lib/pass.js':__dirname+'/candidate-pass.js',
};
Module._extensions['.js']=function(module,filename){
 if(replacements[filename])return module._compile(fs.readFileSync(replacements[filename],'utf8'),filename);
 return old(module,filename);
};
