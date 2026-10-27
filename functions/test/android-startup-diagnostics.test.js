'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');

const ROOT=path.resolve(__dirname,'..','..');
const APP=path.join(ROOT,'luno_android','android','app');
const JAVA=path.join(APP,'src','main','java','com','luno','chess');
const main=fs.readFileSync(path.join(JAVA,'MainActivity.java'),'utf8');
const application=fs.readFileSync(path.join(JAVA,'LunoApplication.java'),'utf8');
const diagnostics=fs.readFileSync(path.join(JAVA,'LunoBootDiagnostics.java'),'utf8');
const appCheck=fs.readFileSync(path.join(JAVA,'LunoAppCheckInitializer.java'),'utf8');
const manifest=fs.readFileSync(path.join(APP,'src','main','AndroidManifest.xml'),'utf8');
const gradle=fs.readFileSync(path.join(APP,'build.gradle'),'utf8');
const styles=fs.readFileSync(path.join(APP,'src','main','res','values','styles.xml'),'utf8');
const stylesV27=fs.readFileSync(path.join(APP,'src','main','res','values-v27','styles.xml'),'utf8');
const stylesV29=fs.readFileSync(path.join(APP,'src','main','res','values-v29','styles.xml'),'utf8');
const startupSource=[main,application,diagnostics,appCheck].join('\n');

test('release QA contains every requested startup breadcrumb',function(){
  for(let index=1;index<=12;index+=1){
    const marker='LUNO_BOOT_'+String(index).padStart(2,'0')+'_';
    assert.match(startupSource,new RegExp(marker),marker+' is missing');
  }
});

test('diagnostics are QA-only and do not log protected values',function(){
  assert.match(gradle,/buildFeatures\s*\{[\s\S]*buildConfig\s+true[\s\S]*\}/);
  assert.match(gradle,/defaultConfig[\s\S]*LUNO_BOOT_DIAGNOSTICS"\s*,\s*"false"/);
  assert.match(gradle,/releaseQa[\s\S]*LUNO_BOOT_DIAGNOSTICS"\s*,\s*"true"/);
  assert.match(diagnostics,/if \(BuildConfig\.LUNO_BOOT_DIAGNOSTICS\)/);
  assert.doesNotMatch(diagnostics,/\b(?:uid|email|purchaseToken|credential|firebase token|app check token)\b/i);
});

test('application and activity markers bracket Android startup in order',function(){
  assert.match(manifest,/android:name="\.LunoApplication"/);
  assert.match(manifest,/android:theme="@style\/AppTheme\.NoActionBarLaunch"/);
  assert.match(styles,/name="LunoBaseTheme"\s+parent="Theme\.AppCompat\.DayNight\.NoActionBar"/);
  assert.match(styles,/name="AppTheme\.NoActionBarLaunch"\s+parent="@style\/AppTheme\.NoActionBar"/);
  assert.doesNotMatch(styles,/name="AppTheme\.NoActionBarLaunch"\s+parent="Theme\.SplashScreen"/);
  for(const qualifiedStyles of [stylesV27,stylesV29]){
    assert.match(qualifiedStyles,/name="AppTheme"\s+parent="@style\/LunoBaseTheme"/);
    assert.match(qualifiedStyles,/name="AppTheme\.NoActionBar"\s+parent="@style\/LunoBaseTheme"/);
  }
  assert.match(application,/static \{[\s\S]*LUNO_BOOT_01_PROCESS[\s\S]*onCreate\(\)[\s\S]*super\.onCreate\(\)[\s\S]*LUNO_BOOT_02_APPLICATION/);

  const activityEnter=main.indexOf('LUNO_BOOT_03_ACTIVITY_ENTER');
  const pluginsDone=main.indexOf('LUNO_BOOT_04_PLUGIN_REGISTRATION"');
  const superBegin=main.indexOf('LUNO_BOOT_05_SUPER_ONCREATE_BEGIN');
  const superCall=main.indexOf('super.onCreate(savedInstanceState)');
  const superEnd=main.indexOf('LUNO_BOOT_06_SUPER_ONCREATE_END');
  const webDiagnostics=main.indexOf('startBootWebDiagnostics();');
  assert.ok(activityEnter>=0&&activityEnter<pluginsDone);
  assert.ok(pluginsDone<superBegin&&superBegin<superCall);
  assert.ok(superCall<superEnd&&superEnd<webDiagnostics);
});

test('WebView, first-frame, Firebase and menu probes fail without exposing data',function(){
  assert.match(main,/LUNO_BOOT_07_WEBVIEW_CREATED/);
  assert.match(main,/OnDrawListener[\s\S]*LUNO_BOOT_08_FIRST_FRAME/);
  assert.match(appCheck,/LUNO_BOOT_09_FIREBASE_INIT_BEGIN/);
  assert.match(appCheck,/LUNO_BOOT_10_APPCHECK_INIT_BEGIN/);
  assert.match(main,/LUNO_BOOT_11_WEB_READY/);
  assert.match(main,/LUNO_BOOT_12_MENU_READY/);
  assert.match(main,/BOOT_PROBE_TIMEOUT_MS\s*=\s*60_000L/);
  assert.match(main,/removeCallbacksAndMessages\(null\)/);
});
