'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');

const ROOT=path.resolve(__dirname,'..','..');
const html=fs.readFileSync(path.join(ROOT,'luno-chess.html'),'utf8');
const auth=fs.readFileSync(path.join(ROOT,'assets','luno-production-auth.js'),'utf8');
const backend=fs.readFileSync(path.join(ROOT,'functions','index.js'),'utf8');
const androidGradle=fs.readFileSync(path.join(ROOT,'luno_android','android','app','build.gradle'),'utf8');
const appCheckInitializer=fs.readFileSync(path.join(ROOT,'luno_android','android','app','src','main','java','com','luno','chess','LunoAppCheckInitializer.java'),'utf8');

function functionSource(source,name){
  const start=source.indexOf('function '+name+'(');assert.notEqual(start,-1,'Missing '+name);
  const open=source.indexOf('{',start),stack=[];let quote='',escaped=false,line=false,block=false;
  for(let index=open;index<source.length;index+=1){
    const char=source[index],next=source[index+1];
    if(line){if(char==='\n')line=false;continue;}
    if(block){if(char==='*'&&next==='/'){block=false;index+=1;}continue;}
    if(quote){if(escaped){escaped=false;continue;}if(char==='\\'){escaped=true;continue;}if(char===quote)quote='';continue;}
    if(char==='/'&&next==='/'){line=true;index+=1;continue;}
    if(char==='/'&&next==='*'){block=true;index+=1;continue;}
    if(char==='\''||char==='"'||char==='`'){quote=char;continue;}
    if(char==='{')stack.push(char);
    if(char==='}'&&stack.pop()&&stack.length===0)return source.slice(start,index+1);
  }
  assert.fail('Unclosed '+name);
}

test('production client parses and contains no App Check emulator shortcut',function(){
  assert.doesNotThrow(function(){new vm.Script(auth,{filename:'luno-production-auth.js'});});
  assert.doesNotMatch(auth,/LUNO_TEST_APPCHECK|luno-emulator-app-check/);
  assert.match(functionSource(auth,'getAppCheckToken'),/nativeAppCheckPlugin\(\)/);
});

test('production App Check is fail-closed for every API route',function(){
  assert.match(auth,/var AUTH_FALLBACK_PATHS=\{\};/);
  assert.match(backend,/const AUTH_FALLBACK_ROUTES=new Set\(\);/);
  assert.match(backend,/verifyAppAttestation\(req,\{allowAuthFallback:AUTH_FALLBACK_ROUTES\.has\(route\)\}\)/);
  assert.match(functionSource(auth,'secureApi'),/if\(appCheckToken\)headers\['X-Firebase-AppCheck'\]=appCheckToken/);
});

test('native App Check keeps production on Play Integrity and isolates the revocable QA provider',function(){
  assert.match(androidGradle,/defaultConfig[\s\S]*LUNO_APPCHECK_PROVIDER_FACTORY[\s\S]*playintegrity\.PlayIntegrityAppCheckProviderFactory/);
  assert.match(androidGradle,/debug\s*\{[\s\S]*LUNO_APPCHECK_PROVIDER_FACTORY[\s\S]*debug\.DebugAppCheckProviderFactory/);
  assert.match(androidGradle,/releaseQa\s*\{[\s\S]*LUNO_APPCHECK_PROVIDER_FACTORY[\s\S]*debug\.DebugAppCheckProviderFactory/);
  assert.match(androidGradle,/releaseImplementation\s+"com\.google\.firebase:firebase-appcheck-playintegrity"/);
  assert.match(androidGradle,/releaseQaImplementation\s+"com\.google\.firebase:firebase-appcheck-debug"/);
  assert.doesNotMatch(androidGradle,/releaseImplementation\s+"com\.google\.firebase:firebase-appcheck-debug"/);
  assert.doesNotMatch(androidGradle,/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/i);
  assert.match(appCheckInitializer,/BuildConfig\.LUNO_APPCHECK_PROVIDER_FACTORY/);
  assert.match(appCheckInitializer,/BuildConfig\.LUNO_APPCHECK_DEBUG_SECRET/);
  assert.doesNotMatch(appCheckInitializer,/DebugAppCheckProviderFactory|FLAG_DEBUGGABLE/);
});

test('production release signing is externalized and cannot use the QA certificate',function(){
  assert.match(androidGradle,/rootProject\.file\("keystore\.properties"\)/);
  assert.match(androidGradle,/release\s*\{[\s\S]*signingConfig\s+signingConfigs\.release/);
  assert.match(androidGradle,/releaseQa\s*\{[\s\S]*signingConfig\s+signingConfigs\.debug/);
  assert.doesNotMatch(androidGradle,/(?:storePassword|keyPassword)\s+["'][^"']+["']/);
});

test('native balanced profile freezes only decorative auth particles',function(){
  const css=fs.readFileSync(path.join(ROOT,'assets','luno-release-polish-v22.css'),'utf8');
  assert.match(css,/luno-native-shell\.luno-gfx-balanced #intro[\s\S]*\.ix2-mote/);
  assert.match(css,/luno-native-shell\.luno-gfx-balanced :is\(#login,#register\) \.fx2-tw/);
  assert.doesNotMatch(css,/luno-native-shell[^\n]*#appLoader[^\{]*\{[^}]*display:none/);
});

test('daily chest removal leaves every inline game script parseable',function(){
  const scripts=[...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi)];
  assert.ok(scripts.length>=8,'inline scripts were not discovered');
  scripts.forEach(function(match,index){
    assert.doesNotThrow(function(){new vm.Script(match[1],{filename:'luno-inline-'+(index+1)+'.js'});});
  });
});

test('disabled daily chest reward runtime is physically absent',function(){
  assert.doesNotMatch(html,/dailyChestTap|lunoDailyChest|dailyChestBtn/);
  assert.doesNotMatch(html,/\.daily-chest|\.dc-ring|\.dc-img|\.dc-lbl|\.dc-sub/);
  assert.match(html,/function rollChest\(chest\)/,'normal store chest logic was removed');
  assert.match(html,/function applyChestRewards\(results\)/,'normal store chest rewards were removed');
});

test('legal consent is server-versioned and enforced only on DM creation',function(){
  assert.match(backend,/LEGAL_TERMS_VERSION='terms-\d{4}-\d{2}-\d{2}'/);
  assert.match(backend,/LEGAL_PRIVACY_VERSION='privacy-\d{4}-\d{2}-\d{2}'/);
  assert.match(functionSource(backend,'acceptLegalTerms'),/assertBodyKeys\(body,\[\]\)/);
  assert.match(functionSource(backend,'acceptLegalTerms'),/acceptedAt:ServerValue\.TIMESTAMP/);
  assert.match(functionSource(backend,'sendDirectMessage'),/assertCurrentLegalConsent\(sender,uid\)/);
  assert.doesNotMatch(functionSource(backend,'blockUser'),/assertCurrentLegalConsent/);
  assert.doesNotMatch(functionSource(backend,'reportUser'),/assertCurrentLegalConsent/);
  assert.doesNotMatch(functionSource(backend,'reportMessage'),/assertCurrentLegalConsent/);
});

test('client consent UI waits for authoritative success and preserves failed messages',function(){
  const prompt=functionSource(auth,'showLegalConsentPrompt');
  const send=functionSource(auth,'sendDirectMessageSecure');
  assert.match(prompt,/href="terms\.html"/);
  assert.match(prompt,/href="privacy\.html"/);
  assert.match(prompt,/role="checkbox"/);
  assert.match(prompt,/secureApi\('\/acceptLegalTerms',\{\}\)\.then/);
  assert.match(prompt,/applyAuthoritativeState\(result&&result\.state\)/);
  assert.doesNotMatch(prompt,/localStorage|sessionStorage/);
  assert.match(send,/ensureLegalConsent\(\)/);
  assert.match(auth,/sendDirectMessageSecure\(\{targetUid:target,text:value\.slice\(0,500\)\}\)[\s\S]*input\.value=''/);
  assert.match(auth,/catch\(function\(error\)\{[\s\S]*if\(!input\.value\)input\.value=value/);
});
