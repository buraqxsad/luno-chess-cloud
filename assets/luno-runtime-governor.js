(function(){
  'use strict';

  var STORAGE_KEY='lunoGraphicsMode';
  var validModes={high:true,balanced:true,low:true};
  var resumeGameTimer=false;
  var resumeMatchStats=false;
  var explicitMode=false;
  var autoConstrained=false;
  var frameProbeRuns=0;

  function isNative(){
    try{if(window.Capacitor&&Capacitor.isNativePlatform&&Capacitor.isNativePlatform())return true;}catch(e){}
    var ua=(navigator.userAgent||'').toLowerCase();
    return (location.protocol==='https:'&&location.hostname==='localhost')||ua.indexOf('; wv')>=0;
  }
  function selectedMode(){
    var stored='';try{stored=localStorage.getItem(STORAGE_KEY)||'';}catch(e){}
    explicitMode=!!validModes[stored];
    if(explicitMode)return stored;
    var memory=Number(navigator.deviceMemory||0);
    var cores=Number(navigator.hardwareConcurrency||0);
    var saveData=!!(navigator.connection&&navigator.connection.saveData);
    if(isNative()&&(saveData||(memory>0&&memory<=2)||(cores>0&&cores<=2)))return 'low';
    return isNative()?'balanced':'high';
  }
  function applyMode(mode,persist){
    if(!validModes[mode])mode='balanced';
    var root=document.documentElement;
    root.classList.remove('luno-gfx-high','luno-gfx-balanced','luno-gfx-low');
    root.classList.add('luno-gfx-'+mode);
    var reduced=mode!=='high';
    root.classList.toggle('lowfx',mode==='low');
    root.classList.toggle('luno-mobile-perf',reduced||isNative());
    window.lunoLowFxOn=reduced;
    window.lunoGraphicsMode=mode;
    if(persist){
      explicitMode=true;
      autoConstrained=false;
      root.classList.remove('luno-auto-constrained');
      delete root.dataset.lunoPerfReason;
      try{localStorage.setItem(STORAGE_KEY,mode);}catch(e){}
    }
    try{window.dispatchEvent(new CustomEvent('luno:graphics-mode',{detail:{mode:mode}}));}catch(e){}
    updateGraphicsButtons();
    return mode;
  }
  function constrainAutomatically(reason,severe){
    if(explicitMode||autoConstrained)return;
    autoConstrained=true;
    var root=document.documentElement;
    root.classList.add('luno-auto-constrained');
    root.dataset.lunoPerfReason=String(reason||'runtime');
    if(severe&&window.lunoGraphicsMode!=='low')applyMode('low',false);
  }
  function runFiniteFrameProbe(){
    if(explicitMode||autoConstrained||document.hidden||frameProbeRuns>=2||!window.requestAnimationFrame)return;
    frameProbeRuns++;
    var started=0,last=0,frames=0,longFrames=0;
    function sample(now){
      if(!started){started=now;last=now;}
      else{
        var delta=now-last;
        frames++;
        if(delta>34)longFrames++;
        last=now;
      }
      if(now-started<1500){requestAnimationFrame(sample);return;}
      var average=frames?(now-started)/frames:99;
      var longRatio=frames?longFrames/frames:1;
      if(average>24||longRatio>.22){
        constrainAutomatically('frame-budget',average>30||longRatio>.42);
        return;
      }
      if(frameProbeRuns<2)setTimeout(runFiniteFrameProbe,4200);
    }
    requestAnimationFrame(sample);
  }
  function scheduleAdaptiveProtection(){
    if(!isNative()||explicitMode||autoConstrained)return;
    var memory=Number(navigator.deviceMemory||0);
    var cores=Number(navigator.hardwareConcurrency||0);
    var saveData=!!(navigator.connection&&navigator.connection.saveData);
    if(saveData||(memory>0&&memory<=2)||(cores>0&&cores<=2))constrainAutomatically('device-budget',true);
    if(navigator.getBattery){
      navigator.getBattery().then(function(battery){
        if(!battery.charging&&battery.level<=.15)constrainAutomatically('battery-budget',true);
      }).catch(function(){});
    }
    setTimeout(runFiniteFrameProbe,3200);
  }
  function updateGraphicsButtons(){
    var buttons=document.querySelectorAll('[data-luno-graphics]');
    for(var i=0;i<buttons.length;i++){
      var active=buttons[i].getAttribute('data-luno-graphics')===window.lunoGraphicsMode;
      buttons[i].classList.toggle('active',active);
      buttons[i].setAttribute('aria-pressed',active?'true':'false');
    }
  }
  function patchGraphicsSettings(){
    var wrap=document.querySelector('#overlay.show .set-wrap');
    if(!wrap||document.getElementById('lunoGraphicsSetting'))return;
    var titles=wrap.querySelectorAll('.set-section-title'),anchor=null;
    for(var i=0;i<titles.length;i++){
      var text=(titles[i].textContent||'').toUpperCase();
      if(text.indexOf('GÖRSEL')>=0||text.indexOf('VISUAL')>=0){anchor=titles[i].nextElementSibling;break;}
    }
    if(!anchor)return;
    var row=document.createElement('div');
    row.id='lunoGraphicsSetting';row.className='set-row luno-graphics-row';
    row.innerHTML='<div class="set-row-info"><div class="set-row-title">GRAFİK KALİTESİ</div></div><div class="luno-graphics-segments" role="group" aria-label="Grafik kalitesi">'+
      '<button type="button" data-luno-graphics="high">YÜKSEK</button><button type="button" data-luno-graphics="balanced">DENGELİ</button><button type="button" data-luno-graphics="low">DÜŞÜK</button></div>';
    anchor.appendChild(row);
    var buttons=row.querySelectorAll('button');
    for(var j=0;j<buttons.length;j++)buttons[j].onclick=function(){applyMode(this.getAttribute('data-luno-graphics'),true);};
    updateGraphicsButtons();
  }
  function patchSettings(){
    if(typeof window.openSettings!=='function'||window.openSettings.__lunoRuntimeGovernor)return;
    var previous=window.openSettings;
    var wrapped=function(){
      var result=previous.apply(this,arguments);
      requestAnimationFrame(function(){requestAnimationFrame(patchGraphicsSettings);});
      return result;
    };
    wrapped.__lunoRuntimeGovernor=true;wrapped.__lunoOriginal=previous;window.openSettings=wrapped;
  }
  function syncVisibility(){
    document.documentElement.classList.toggle('luno-app-hidden',document.hidden);
    if(document.hidden){
      try{
        resumeGameTimer=!!(window.G&&G.timerOn&&window._gameTimerInt);
        if(resumeGameTimer&&typeof window.stopGameTimer==='function')stopGameTimer();
      }catch(e){resumeGameTimer=false;}
      try{
        resumeMatchStats=!!(window.MATCH_STATS&&MATCH_STATS.timerInt);
        if(resumeMatchStats&&typeof window.stopMatchStatsTimer==='function')stopMatchStatsTimer();
      }catch(e){resumeMatchStats=false;}
      return;
    }
    try{
      if(resumeGameTimer&&window.G&&!G.over&&G.timerOn&&typeof window.startGameTimer==='function'){
        G.timerLast=Date.now();startGameTimer();
      }
    }catch(e){}
    try{if(resumeMatchStats&&window.G&&!G.over&&typeof window.startMatchStatsTimer==='function')startMatchStatsTimer();}catch(e){}
    resumeGameTimer=false;resumeMatchStats=false;
  }
  function injectStyles(){
    if(document.getElementById('lunoRuntimeGovernorStyles'))return;
    var style=document.createElement('style');style.id='lunoRuntimeGovernorStyles';
    style.textContent='.luno-graphics-row{display:flex;align-items:center;gap:10px;min-height:62px}.luno-graphics-row .set-row-info{min-width:0}.luno-graphics-segments{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));width:min(62%,238px);border:1px solid rgba(220,195,246,.3);border-radius:6px;overflow:hidden}.luno-graphics-segments button{min-width:0;min-height:34px;padding:4px 3px;border:0;border-right:1px solid rgba(220,195,246,.22);background:#211741;color:#cfc2e4;font:800 8px/1.1 Cinzel,serif;letter-spacing:0}.luno-graphics-segments button:last-child{border-right:0}.luno-graphics-segments button.active{background:#d8a52e;color:#1b102f}.luno-gfx-balanced .particle,.luno-gfx-balanced .spark,.luno-gfx-low .particle,.luno-gfx-low .spark,.luno-app-hidden *{animation-play-state:paused!important}.luno-mobile-perf .screen:not(.active):not(.screen-leaving),.luno-mobile-perf #overlay:not(.show){visibility:hidden!important;content-visibility:hidden;contain:layout style paint}.luno-app-hidden *{animation-play-state:paused!important}@media(max-width:370px){.luno-graphics-row{align-items:flex-start;flex-direction:column}.luno-graphics-segments{width:100%}}';
    document.head.appendChild(style);
  }

  window.lunoSetGraphicsMode=function(mode){return applyMode(mode,true);};
  var initialMode=selectedMode();
  injectStyles();applyMode(initialMode,false);patchSettings();
  if(!explicitMode&&initialMode==='low')constrainAutomatically('device-budget',true);
  scheduleAdaptiveProtection();
  syncVisibility();
  document.addEventListener('visibilitychange',syncVisibility,{passive:true});
})();
