(function(){
  'use strict';

  var DURATIONS=[1,3,5,10,30];
  var state={mode:'ranked',aiMinutes:5,friendMinutes:5,localMinutes:10};

  function validDuration(value,fallback){
    value=Number(value);
    return DURATIONS.indexOf(value)>=0?value:fallback;
  }
  function loadPreferences(){
    try{
      state.mode=localStorage.getItem('lunoBattleMode')||'ranked';
      state.aiMinutes=validDuration(localStorage.getItem('lunoAiMinutes'),5);
      state.friendMinutes=validDuration(localStorage.getItem('lunoFriendMinutes'),5);
      state.localMinutes=validDuration(localStorage.getItem('lunoLocalMinutes'),10);
    }catch(error){}
    if(['ranked','ai','friend','local'].indexOf(state.mode)<0)state.mode='ranked';
    window.LUNO_AI_DURATION_MINUTES=state.aiMinutes;
    window.LUNO_FRIEND_DURATION_MINUTES=state.friendMinutes;
    window.LUNO_LOCAL_DURATION_MINUTES=state.localMinutes;
  }
  function savePreference(key,value){try{localStorage.setItem(key,String(value));}catch(error){}}
  function esc(value){
    return String(value==null?'':value).replace(/[&<>"']/g,function(char){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char];});
  }
  function image(source,alt){return '<img src="'+esc(source||'')+'" alt="'+esc(alt||'')+'" draggable="false">';}
  function modeArt(mode){
    if(typeof window.LUNO_UI==='undefined')return '';
    return LUNO_UI['mode_'+mode]||LUNO_UI.mode_ranked||'';
  }
  function durationPicker(kind,value){
    return '<div class="lbf-time" role="group" aria-label="Maç süresi">'+DURATIONS.map(function(minutes){
      return '<button type="button" class="'+(minutes===value?'selected':'')+'" onclick="lunoBattleSetDuration(\''+kind+'\','+minutes+')"><b>'+minutes+'</b><small>DK</small></button>';
    }).join('')+'</div>';
  }
  function trainerPicker(){
    var levels=window.AI_LEVELS||[],current=window.AI_DIFFICULTY&&AI_DIFFICULTY.current||'bebek';
    return '<div class="lbf-trainers" role="list">'+levels.map(function(level){
      var source=typeof window.LUNO_UI!=='undefined'&&LUNO_UI['ai_'+level.id];
      return '<button type="button" role="listitem" class="'+(level.id===current?'selected':'')+'" onclick="lunoBattleSelectAi(\''+esc(level.id)+'\')">'+
        (source?image(source,level.name):'<span>'+level.icon+'</span>')+'<small>'+esc(level.name.replace(' Luno',''))+'</small></button>';
    }).join('')+'</div>';
  }
  function panelMarkup(){
    if(state.mode==='ranked')return '<section class="lbf-panel is-ranked"><div class="lbf-panel-copy"><span>REKABETÇİ</span><h3>Sıralı Maç</h3><p>Her oyuncu için sabit 5 dakika. Kupa ve arena ilerlemesi etkindir.</p></div><div class="lbf-fixed-time"><b>5:00</b><small>HER OYUNCU</small></div><button class="lbf-primary" onclick="lunoBattleStartRanked()">RAKİP ARA</button></section>';
    if(state.mode==='ai')return '<section class="lbf-panel"><div class="lbf-panel-copy"><span>RİSKSİZ ANTRENMAN</span><h3>Luno Eğitmeni</h3><p>Eğitmenini ve maç süresini seç, tek dokunuşla tahtaya geç.</p></div>'+trainerPicker()+durationPicker('ai',state.aiMinutes)+'<button class="lbf-primary" onclick="lunoBattleStartAi()">ANTRENMANI BAŞLAT</button></section>';
    if(state.mode==='friend')return '<section class="lbf-panel"><div class="lbf-panel-copy"><span>ÖZEL ONLINE MAÇ</span><h3>Arkadaşınla Oyna</h3><p>Seçilen süre davete ve oda koduna sunucu tarafından eklenir.</p></div>'+durationPicker('friend',state.friendMinutes)+'<div class="lbf-friend-actions"><button onclick="openFriendInvitePicker()">ARKADAŞA DAVET</button><button onclick="onlineCreateRoom()">ODA KUR</button><button onclick="onlineJoinPrompt()">KODLA KATIL</button></div></section>';
    return '<section class="lbf-panel"><div class="lbf-panel-copy"><span>AYNI CİHAZ</span><h3>Yüz Yüze Oyna</h3><p>Telefonu sırayla kullanın; bağlantı ve kupa etkisi yoktur.</p></div>'+durationPicker('local',state.localMinutes)+'<button class="lbf-primary" onclick="lunoBattleStartLocal()">MAÇI BAŞLAT</button></section>';
  }
  function render(){
    var body=document.getElementById('ovBody'),overlay=document.getElementById('overlay'),title=document.getElementById('ovTitle');
    if(!body||!overlay)return;
    if(title)title.textContent='SAVAŞ';
    body.classList.add('is-luno-battle-v23');
    var arena=window.ARENAS&&ARENAS[window.PLAYER&&PLAYER.arenaIdx||0]||{name:'Acemi Kampı'};
    body.innerHTML='<main class="lbf-wrap">'+
      '<header class="lbf-hero"><div class="lbf-hero-art">'+image(modeArt(state.mode),'')+'</div><div><span>ARENA HAZIR</span><h2>'+esc(arena.name)+'</h2><p>Modunu seç, kurallarını gör ve doğrudan savaşa gir.</p></div></header>'+
      '<nav class="lbf-modes" aria-label="Savaş modu">'+
        [['ranked','SIRALI'],['ai','YAPAY ZEKA'],['friend','ARKADAŞ'],['local','YÜZ YÜZE']].map(function(item){return '<button type="button" class="'+(state.mode===item[0]?'selected':'')+'" onclick="lunoBattleSelectMode(\''+item[0]+'\')">'+image(modeArt(item[0]),'')+'<span>'+item[1]+'</span></button>';}).join('')+
      '</nav>'+panelMarkup()+'</main>';
    body.scrollTop=0;
    overlay.classList.add('show');
  }

  window.lunoBattleSelectMode=function(mode){
    if(['ranked','ai','friend','local'].indexOf(mode)<0)return;
    state.mode=mode;savePreference('lunoBattleMode',mode);
    try{if(typeof window.sndUiClick==='function')sndUiClick();}catch(error){}
    render();
  };
  window.lunoBattleSetDuration=function(kind,minutes){
    minutes=validDuration(minutes,5);
    if(kind==='ai'){state.aiMinutes=minutes;window.LUNO_AI_DURATION_MINUTES=minutes;savePreference('lunoAiMinutes',minutes);}
    else if(kind==='friend'){state.friendMinutes=minutes;window.LUNO_FRIEND_DURATION_MINUTES=minutes;savePreference('lunoFriendMinutes',minutes);}
    else{state.localMinutes=minutes;window.LUNO_LOCAL_DURATION_MINUTES=minutes;savePreference('lunoLocalMinutes',minutes);}
    try{if(typeof window.sndUiClick==='function')sndUiClick();}catch(error){}
    render();
  };
  window.lunoBattleSelectAi=function(id){
    var exists=(window.AI_LEVELS||[]).some(function(level){return level.id===id;});
    if(!exists)return;
    if(window.AI_DIFFICULTY)AI_DIFFICULTY.current=id;
    render();
  };
  window.lunoBattleStartRanked=function(){
    if(typeof window.closeOverlay==='function')closeOverlay();
    setTimeout(function(){if(typeof window.openRankedMatchmaking==='function')openRankedMatchmaking();},130);
  };
  window.lunoBattleStartAi=function(){
    window.LUNO_AI_DURATION_MINUTES=state.aiMinutes;
    if(typeof window.closeOverlay==='function')closeOverlay();
    setTimeout(function(){if(typeof window.startMatch==='function')startMatch('ai');},130);
  };
  window.lunoBattleStartLocal=function(){
    window.LUNO_LOCAL_DURATION_MINUTES=state.localMinutes;
    if(typeof window.closeOverlay==='function')closeOverlay();
    setTimeout(function(){if(typeof window.startMatch==='function')startMatch('local');},130);
  };
  window.openMatchModes=function(){
    try{if(typeof window.sndUiOpen==='function')sndUiOpen();}catch(error){}
    try{if(typeof window.lunoSetMainRoute==='function')lunoSetMainRoute('battle');}catch(error){}
    render();
  };

  function installMenuBattleHero(){
    window.LUNO_MENU_MOTION_OWNER='battle-hero-v23';
    try{if(typeof window.lunoStopLegacyMenuMotion==='function')lunoStopLegacyMenuMotion();}catch(error){}
    try{if(typeof window.lunoStopMenuLunoMotion==='function')lunoStopMenuLunoMotion();}catch(error){}
    try{if(typeof window.lunoStopDecorativeParticles==='function')lunoStopDecorativeParticles();}catch(error){}
    var live=document.getElementById('mnLunoLive');if(live)live.remove();
    var stage=document.getElementById('menuStage');if(!stage)return;
    stage.classList.add('is-luno-battle-hero-v23');
    stage.style.backgroundImage='url("assets/luno-art/menu-battle-hero-v23.webp")';
    if(!stage.querySelector('.mn-battle-entry')){
      var button=document.createElement('button');button.type='button';button.className='mn-battle-entry';button.onclick=window.openMatchModes;
      button.innerHTML='<span>TAHTAN HAZIR</span><b>SAVAŞA GİR</b><small>Modunu ve süreni seç</small>';
      stage.appendChild(button);
    }
  }

  loadPreferences();
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',installMenuBattleHero,{once:true});
  else installMenuBattleHero();
})();
