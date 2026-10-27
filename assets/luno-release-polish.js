(function(){
  'use strict';

  var BASE='assets/luno-art/';
  var ART={
    crest:BASE+'menu-arena-crest-v9.png',
    card:BASE+'luno-card-pack.png',
    trophy:BASE+'luno-trophy.png',
    duel:BASE+'luno-duel.png',
    coin:BASE+'luno-coin.png',
    gem:BASE+'luno-gem.png',
    mana:BASE+'luno-mana.png',
    chest:BASE+'luno-chest.png',
    premium:BASE+'screen-premium-ticket.png',
    bundle:BASE+'screen-shop-bundle.png',
    profile:BASE+'screen-profile-crest.png',
    gallery:BASE+'profile-gallery-v7.png',
    signout:BASE+'profile-signout-v4.png',
    removeFriend:BASE+'friends-action-remove-v6.png',
    baby:BASE+'ai-bebek-v12-mobile.webp',
    lock:BASE+'system-lock-v14.png',
    premiumCrown:BASE+'system-premium-v14.png',
    dailyGift:BASE+'system-daily-gift-v14.png',
    message:BASE+'system-message-v14.png',
    tutorialGuide:BASE+'menu-luno-point-v10-mobile.webp',
    star:BASE+'emoji-star-v12-mobile.webp',
    smile:BASE+'emoji-smile.png',
    fire:BASE+'streak-flame.png',
    statusCoin:BASE+'menu-status-gold-v2.png',
    statusGem:BASE+'menu-status-gem-v2.png',
    statusTrophy:BASE+'menu-status-trophy-v2.png',
    chestCommon:BASE+'shop-chest-common-v3.png',
    chestRare:BASE+'shop-chest-rare-v3.png',
    chestLegendary:BASE+'shop-chest-legendary-v3.png',
    chestRoyal:BASE+'shop-chest-royal-v3.png',
    resultVictory:BASE+'result-victory-v12-mobile.webp',
    resultDefeat:BASE+'result-defeat-v12-mobile.webp',
    resultDraw:BASE+'result-draw-v12-mobile.webp',
    timekeeper:BASE+'emoji-timekeeper-v12-mobile.webp',
    modeFriend:BASE+'match-mode-friend-v16.webp',
    modeRanked:BASE+'match-mode-ranked-v16.webp',
    modeTraining:BASE+'match-mode-training-v16.webp',
    modeLocal:BASE+'match-mode-local-v16.webp',
    modeOnline:BASE+'match-mode-online-v16.webp',
    modeClassic:BASE+'match-mode-classic-v16.webp',
    avatarPawn:BASE+'avatar-pawn-v9.png',
    avatarKnight:BASE+'avatar-knight-v9.png',
    avatarBishop:BASE+'avatar-bishop-v9.png',
    avatarRook:BASE+'avatar-rook-v9.png',
    avatarQueen:BASE+'avatar-queen-v9.png',
    avatarKing:BASE+'avatar-king-v9.png',
    avatarRobot:BASE+'avatar-robot-v9.png',
    avatarRobotKing:BASE+'avatar-robot-king-v9.png',
    avatarCrown:BASE+'avatar-crown-v9.png',
    avatarFire:BASE+'avatar-fire-v9.png',
    avatarLightning:BASE+'avatar-lightning-v9.png',
    seasonEmblem:BASE+'screen-season-emblem.png',
    profileAbout:BASE+'profile-about-v4.png',
    rankCrown:BASE+'ranking-luno-crown-v7.png',
    rankGold:BASE+'ranking-star-gold-v7.png',
    rankSilver:BASE+'ranking-star-silver-v7.png',
    rankBronze:BASE+'ranking-star-bronze-v7.png',
    loadingCards:BASE+'loading-feature-cards-v22.webp',
    loadingArena:BASE+'loading-feature-arena-v22.webp',
    loadingOnline:BASE+'loading-feature-online-v22.webp'
  };
  var PRODUCT_MAP={
    gold_1000:{id:'luno_gold_1000',name:'1.000 Altın',type:'inapp',asset:BASE+'shop-gold-small-v3.png',kind:'gold',amount:1000},
    gold_5500:{id:'luno_gold_5500',name:'5.500 Altın',type:'inapp',asset:BASE+'shop-gold-medium-v3.png',kind:'gold',amount:5500},
    gold_15000:{id:'luno_gold_15000',name:'15.000 Altın',type:'inapp',asset:BASE+'shop-gold-large-v3.png',kind:'gold',amount:15000},
    gem_80:{id:'luno_gem_80',name:'80 Elmas',type:'inapp',asset:BASE+'shop-gem-small-v3.png',kind:'gem',amount:80},
    gem_500:{id:'luno_gem_500',name:'500 Elmas',type:'inapp',asset:BASE+'shop-gem-medium-v3.png',kind:'gem',amount:500},
    gem_1500:{id:'luno_gem_1500',name:'1.500 Elmas',type:'inapp',asset:BASE+'shop-gem-large-v3.png',kind:'gem',amount:1500},
    premium_month:{id:'luno_premium_month',name:'Aylık Luno Premium',type:'subs',asset:ART.premium,kind:'premium',period:'month'},
    premium_year:{id:'luno_premium_year',name:'Yıllık Luno Premium',type:'subs',asset:ART.premium,kind:'premium',period:'year'},
    bundle_starter:{id:'luno_bundle_starter',name:'Başlangıç Paketi',type:'inapp',asset:BASE+'shop-starter-v3.png',kind:'bundle',bundle:'starter'},
    bundle_pro:{id:'luno_bundle_pro',name:'Uzman Paketi',type:'inapp',asset:BASE+'shop-expert-v3.png',kind:'bundle',bundle:'pro'}
  };
  var PRODUCT_BY_ID={};
  Object.keys(PRODUCT_MAP).forEach(function(key){PRODUCT_BY_ID[PRODUCT_MAP[key].id]=PRODUCT_MAP[key];});
  var BILLING_STATE={ready:false,promise:null,products:{},listenerInstalled:false,error:''};

  function byId(id){return document.getElementById(id);}
  function esc(value){
    return String(value==null?'':value)
      .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
      .replace(/"/g,'&quot;').replace(/'/g,'&#39;');
  }
  function fmt(value){
    try{return Number(value||0).toLocaleString('tr-TR');}
    catch(e){return String(value||0);}
  }
  function clickSound(){try{if(typeof window.sndUiClick==='function')window.sndUiClick();}catch(e){}}
  function errorSound(){try{if(typeof window.sndError==='function')window.sndError();}catch(e){}}

  var NAV_MOTION={
    token:0,
    pending:'rise',
    navIndex:2,
    lastFxAt:0
  };
  var dynamicPolishTimer=null;
  var MOTION={
    press:90,
    micro:150,
    screen:250,
    modal:210,
    piece:180,
    reward:360,
    card:680,
    matchFound:480
  };
  window.LUNO_MOTION=MOTION;
  var SCREEN_ORDER={loading:0,menu:1,game:2,result:3};
  var NAV_ORDER={nvMagaza:0,nvKoleksiyon:1,nvSavas:2,nvSezon:3,nvProfil:4};

  function motionTone(name){
    name=String(name||'').toLowerCase();
    if(name.indexOf('game')>=0||name.indexOf('battle')>=0||name.indexOf('savaş')>=0)return '#e77686';
    if(name.indexOf('shop')>=0||name.indexOf('mağaza')>=0||name.indexOf('pass')>=0)return '#f2c85d';
    if(name.indexOf('collection')>=0||name.indexOf('koleksiyon')>=0)return '#73d8cf';
    if(name.indexOf('season')>=0||name.indexOf('sezon')>=0)return '#efb963';
    if(name.indexOf('profile')>=0||name.indexOf('profil')>=0)return '#dba6e9';
    return '#73d8cf';
  }
  function schedulePolishDynamic(delay){
    if(dynamicPolishTimer!==null)return;
    dynamicPolishTimer=setTimeout(function(){
      dynamicPolishTimer=null;
      requestAnimationFrame(polishDynamic);
    },Math.max(0,Number(delay)||0));
  }
  function ensureNavFx(){
    var stage=document.querySelector('.stage');
    if(!stage)return null;
    var fx=stage.querySelector('.luno-nav-fx');
    if(!fx){
      fx=document.createElement('div');
      fx.className='luno-nav-fx';
      fx.setAttribute('aria-hidden','true');
      fx.innerHTML='<i class="luno-nav-beam"></i>';
      stage.appendChild(fx);
    }
    return fx;
  }
  function motionReduced(){
    try{return window.matchMedia&&window.matchMedia('(prefers-reduced-motion: reduce)').matches;}
    catch(e){return false;}
  }
  function restartMotion(node,className,hold,immediate){
    if(!node)return;
    var state=node.__lunoMotionState||(node.__lunoMotionState={});
    var current=state[className]||(state[className]={token:0,timer:null});
    current.token+=1;
    var token=current.token;
    if(current.timer!==null){
      clearTimeout(current.timer);
      current.timer=null;
    }
    node.classList.remove(className);
    var start=function(){
      if(current.token!==token)return;
      node.classList.add(className);
      current.timer=setTimeout(function(){
        if(current.token!==token)return;
        node.classList.remove(className);
        current.timer=null;
      },hold||MOTION.screen+80);
    };
    if(immediate){
      void node.offsetWidth;
      start();
      return;
    }
    requestAnimationFrame(function(){requestAnimationFrame(start);});
  }
  function playNavFx(direction,tone){
    if(window.lunoGraphicsMode==='low'||motionReduced())return;
    var now=Date.now();
    if(now-NAV_MOTION.lastFxAt<55)return;
    NAV_MOTION.lastFxAt=now;
    var fx=ensureNavFx();
    if(!fx)return;
    direction=direction==='back'?'back':(direction==='rise'?'rise':'forward');
    fx.style.setProperty('--luno-nav-accent',motionTone(tone));
    fx.className='luno-nav-fx '+direction;
    restartMotion(fx,'play',MOTION.screen+90,true);
  }
  function clearScreenMotion(node){
    if(!node)return;
    [
      'luno-screen-exit-forward','luno-screen-enter-forward',
      'luno-screen-exit-back','luno-screen-enter-back',
      'luno-screen-exit-rise','luno-screen-enter-rise'
    ].forEach(function(name){node.classList.remove(name);});
  }
  function resolveScreenDirection(fromId,toId){
    if(toId==='game')return 'rise';
    if(fromId==='game'&&toId!=='result')return 'back';
    var from=SCREEN_ORDER[fromId],to=SCREEN_ORDER[toId];
    if(from==null||to==null)return NAV_MOTION.pending||'forward';
    return to<from?'back':'forward';
  }
  function installScreenMotion(){
    var original=window.show;
    if(typeof original!=='function'||original.__lunoReleaseMotion)return;
    var wrapped=function(id){
      var from=document.querySelector('.screen.active');
      var target=byId(id);
      if(!target||!from||from===target)return original.apply(this,arguments);
      var direction=resolveScreenDirection(from.id,id);
      var all=document.querySelectorAll('.screen');
      for(var i=0;i<all.length;i++)clearScreenMotion(all[i]);
      from.classList.add('luno-screen-exit-'+direction);
      var result=original.apply(this,arguments);
      from.classList.remove('screen-leaving');
      target.classList.add('luno-screen-enter-'+direction);
      NAV_MOTION.pending=direction;
      playNavFx(direction,id);
      schedulePolishDynamic(30);
      var token=++NAV_MOTION.token;
      setTimeout(function(){
        if(token!==NAV_MOTION.token)return;
        clearScreenMotion(from);
        clearScreenMotion(target);
      },MOTION.screen+80);
      return result;
    };
    wrapped.__lunoReleaseMotion=true;
    wrapped.__lunoOriginal=original;
    window.show=wrapped;
  }
  function installNavMotion(){
    var original=window.navClick;
    if(typeof original!=='function'||original.__lunoReleaseMotion)return;
    var wrapped=function(el,fn){
      var next=el&&NAV_ORDER[el.id];
      if(next!=null){
        NAV_MOTION.pending=next===NAV_MOTION.navIndex?'rise':(next>NAV_MOTION.navIndex?'forward':'back');
        NAV_MOTION.navIndex=next;
      }
      var result=original.apply(this,arguments);
      if(el){
        restartMotion(el,'luno-nav-settle',MOTION.micro+120);
      }
      return result;
    };
    wrapped.__lunoReleaseMotion=true;
    wrapped.__lunoOriginal=original;
    window.navClick=wrapped;
  }
  function animateSurface(node,direction,tone){
    if(!node)return;
    direction=direction==='back'?'back':(direction==='forward'?'forward':'rise');
    node.classList.remove('luno-surface-enter','luno-surface-back');
    if(direction==='back')node.classList.add('luno-surface-back');
    restartMotion(node,'luno-surface-enter',MOTION.modal+90);
    playNavFx(direction,tone);
  }
  function installOverlayMotion(){
    if(document.documentElement.dataset.lunoOverlayMotion)return;
    document.documentElement.dataset.lunoOverlayMotion='1';
    var body=byId('ovBody');
    var overlay=byId('overlay');
    if(body&&overlay){
      var syncOverlayState=function(){
        var open=overlay.classList.contains('show');
        overlay.setAttribute('aria-hidden',open?'false':'true');
        if(open)overlay.removeAttribute('inert');
        else overlay.setAttribute('inert','');
      };
      syncOverlayState();
      var overlayStateObserver=new MutationObserver(syncOverlayState);
      overlayStateObserver.observe(overlay,{attributes:true,attributeFilter:['class']});
      var bodyObserver=new MutationObserver(function(records){
        var changed=false;
        for(var i=0;i<records.length;i++)if(records[i].target===body){changed=true;break;}
        if(!changed)return;
        var direction=NAV_MOTION.pending||'rise';
        body.classList.toggle('luno-surface-back',direction==='back');
        animateSurface(overlay,direction,(byId('ovTitle')||{}).textContent||'');
      });
      bodyObserver.observe(body,{childList:true});
    }
    var matchOriginal=window.showMatchOverlay;
    if(typeof matchOriginal==='function'&&!matchOriginal.__lunoReleaseMotion){
      var matchWrapped=function(){
        var result=matchOriginal.apply(this,arguments);
        var modal=byId('matchMenuOverlay');
        animateSurface(modal,'rise','battle');
        schedulePolishDynamic(30);
        return result;
      };
      matchWrapped.__lunoReleaseMotion=true;
      matchWrapped.__lunoOriginal=matchOriginal;
      window.showMatchOverlay=matchWrapped;
    }
    document.addEventListener('pointerdown',function(event){
      var target=event.target&&event.target.closest?
        event.target.closest('button,.mn-navitem,.mn-qbtn,.mm-mode,[role="button"]'):null;
      if(!target||target.classList.contains('sq')||target.classList.contains('cell'))return;
      restartMotion(target,'luno-pressing',MOTION.press+60);
    },{passive:true});
  }
  function installNavigationMotion(){
    installScreenMotion();
    installNavMotion();
    installOverlayMotion();
    ensureNavFx();
  }

  function ensureStyles(){
    var link=byId('luno-release-polish-css');
    var href='assets/luno-release-polish-v22.css?v=156-0823a';
    if(!link){
      link=document.createElement('link');
      link.id='luno-release-polish-css';
      link.rel='stylesheet';
    }
    if(link.getAttribute('href')!==href)link.href=href;
    document.head.appendChild(link);
  }

  function featureHtml(extraClass,img,label){
    return '<div class="luno-v13-feature '+extraClass+'">'+
      '<img src="'+img+'" alt="">'+
      '<strong>'+label+'</strong>'+
    '</div>';
  }
  function installFeatureRows(){
    var loading=document.querySelector('#appLoader .al-img');
    if(loading&&!loading.querySelector('.luno-v13-feature-strip')){
      var row=document.createElement('div');
      row.className='luno-v13-feature-strip is-loading';
      row.setAttribute('aria-label','20 üzeri kart, 9 arena, online PVP');
      row.innerHTML=featureHtml('luno-feature-card',ART.loadingCards,'20+ KART')+
        featureHtml('luno-feature-arena',ART.loadingArena,'9 ARENA')+
        featureHtml('luno-feature-online',ART.loadingOnline,'ONLINE PVP');
      loading.appendChild(row);
    }
  }

  function rebuildAuth(){
    // Legacy email/password surfaces were removed from the guest-first product.
  }

  function polishUsername(){
    var ov=byId('unameOv');
    if(!ov||ov.dataset.lunoV13)return;
    ov.dataset.lunoV13='1';
    ov.classList.add('luno-v13-uname');
    var panel=ov.firstElementChild;
    if(!panel)return;
    panel.classList.add('luno-uname-panel');
    if(panel.children[0]){
      panel.children[0].className='luno-uname-crest';
      panel.children[0].innerHTML='<img src="'+ART.profile+'" alt="Luno profil rozeti">';
    }
    if(panel.children[1])panel.children[1].classList.add('luno-uname-title');
    if(panel.children[2])panel.children[2].classList.add('luno-uname-sub');
    if(panel.children[3])panel.children[3].classList.add('luno-uname-input');
  }

  function polishOnboarding(){
    var ov=byId('onboardCard');
    if(!ov||ov.dataset.lunoV13)return;
    ov.dataset.lunoV13='1';
    ov.classList.add('luno-v13-onboard');
    var panel=byId('onboardInner');
    if(!panel)return;
    panel.classList.add('luno-onboard-panel');
    var title=(panel.children[1]&&panel.children[1].textContent)||'';
    if(panel.children[0]){
      panel.children[0].className='luno-onboard-art';
      panel.children[0].innerHTML='<img src="'+(title.indexOf('BEBEK')>=0?ART.baby:ART.crest)+'" alt="Luno">';
    }
    if(panel.children[1])panel.children[1].classList.add('luno-onboard-title');
    if(panel.children[2])panel.children[2].classList.add('luno-onboard-copy');
  }

  function tutorialCardKey(){
    try{
      return window.ITUT_STEPS&&window.ITUT?ITUT_STEPS[ITUT.step].card:null;
    }catch(e){return null;}
  }
  function polishTutorial(){
    var key=tutorialCardKey();
    var glyph=document.querySelector('#itutOv .itut-cglyph');
    if(glyph&&key&&window.CARD_IMG&&CARD_IMG[key]&&!glyph.querySelector('img')){
      glyph.innerHTML='<img src="'+CARD_IMG[key]+'" alt="">';
    }
    var hint=byId('itutHint');
    if(hint&&!hint.querySelector('img')){
      hint.innerHTML='<img src="'+ART.tutorialGuide+'" alt=""><span>YUKARIDA GOSTERILEN HAMLEYI YAP</span>';
      hint.classList.add('luno-v14-tutorial-hint');
    }
    var board=byId('itutBoard');
    if(!board||!window.ITUT||!ITUT.board||typeof window.pieceHTML!=='function')return;
    var squares=board.querySelectorAll('.itut-sq');
    var pos=0;
    for(var dr=7;dr>=0;dr--){
      for(var f=0;f<8;f++){
        var idx=dr*8+f,p=ITUT.board[idx],sq=squares[pos++];
        if(!p||!sq)continue;
        var pc=sq.querySelector('.itut-pc');
        if(!pc||pc.querySelector('.pc-img'))continue;
        pc.innerHTML=pieceHTML(p.t,p.c)+
          (p.frozen?'<span class="itut-ice">❄</span>':'')+
          (p.barb?'<span class="itut-barb">⚔</span>':'');
      }
    }
  }

  function currentAvatarValue(){
    try{
      var pf=window.PLAYER&&PLAYER.profile||{};
      return pf.avatarEmoji||pf.avatarIcon||'av_king';
    }catch(e){return 'av_king';}
  }
  function avatarMarkup(value){
    if(typeof window.avHtml==='function'){
      try{return avHtml(value);}catch(e){}
    }
    var src=window.AVATAR_IMGS&&AVATAR_IMGS[value];
    return src?'<img class="luno-v13-mm-avatar" src="'+src+'" alt="" loading="lazy" decoding="async">':'♛';
  }

  function stableAvatarHash(value){
    value=String(value||'Luno');
    var hash=2166136261;
    for(var i=0;i<value.length;i++){
      hash^=value.charCodeAt(i);
      hash+=(hash<<1)+(hash<<4)+(hash<<7)+(hash<<8)+(hash<<24);
    }
    return hash>>>0;
  }

  function generatedAvatarSrc(value,seed){
    value=String(value||'');
    var key=normalizeUiText(value);
    var direct={
      AV_PAWN:ART.avatarPawn,
      AV_KNIGHT:ART.avatarKnight,
      AV_BISHOP:ART.avatarBishop,
      AV_ROOK:ART.avatarRook,
      AV_QUEEN:ART.avatarQueen,
      AV_KING:ART.avatarKing,
      AV_ROBOT:ART.avatarRobot,
      AV_ROBOT_KING:ART.avatarRobotKing,
      AV_CROWN:ART.avatarCrown,
      AV_FIRE:ART.avatarFire,
      AV_LIGHTNING:ART.avatarLightning
    };
    if(direct[key])return direct[key];
    if(/[\u2659\u265F]/.test(value))return ART.avatarPawn;
    if(/[\u2658\u265E]/.test(value))return ART.avatarKnight;
    if(/[\u2657\u265D]/.test(value))return ART.avatarBishop;
    if(/[\u2656\u265C]/.test(value))return ART.avatarRook;
    if(/[\u2655\u265B]/.test(value))return ART.avatarQueen;
    if(/[\u2654\u265A]/.test(value))return ART.avatarKing;
    var choices=[
      ART.avatarPawn,ART.avatarKnight,ART.avatarBishop,ART.avatarRook,
      ART.avatarQueen,ART.avatarKing,ART.avatarRobot,ART.avatarRobotKing
    ];
    return choices[stableAvatarHash(seed||value)%choices.length];
  }

  function hasPhotoBackground(node){
    if(!node)return false;
    var style=String(node.getAttribute('style')||'').toLowerCase();
    return style.indexOf('url(')>=0||node.classList.contains('pf2-avatar-photo');
  }

  function installGeneratedAvatar(node,seed,src){
    if(!node||hasPhotoBackground(node))return;
    var existing=node.querySelector('img');
    if(existing){
      existing.classList.add('luno-v16-avatar-art');
      return;
    }
    var value=String(node.textContent||'').trim();
    if(value==='?'||value==='-'||value==='')return;
    node.textContent='';
    var image=document.createElement('img');
    image.className='luno-v16-avatar-art';
    image.decoding='async';
    var screen=node.closest&&node.closest('.screen');
    image.loading=screen&&screen.classList.contains('active')?'eager':'lazy';
    image.src=src||generatedAvatarSrc(value,seed);
    image.alt='';
    node.appendChild(image);
    node.classList.add('luno-v16-avatar-host');
  }

  function polishAvatars(){
    var selector=[
      '.pf2-av-emoji',
      '.fh-av > span',
      '.fh-req-avatar',
      '.rk-row-avatar',
      '.rk-row-av > span',
      '.rk-pod-avatar > span',
      '.pp-av-letter',
      '.pe-frame-ic',
      '#tagYouIcon',
      '#tagEnemyIcon'
    ].join(',');
    var nodes=document.querySelectorAll(selector);
    for(var i=0;i<nodes.length;i++){
      var row=nodes[i].closest('.fh-row,.fh-req-row,.rk-row,.rk-pod-col,.pf2-card,.pp-card,.ptag');
      var seed=(row&&row.textContent)||nodes[i].textContent||('luno-'+i);
      installGeneratedAvatar(nodes[i],seed);
    }

    var bio=document.querySelectorAll('.pe-bf-prev > span');
    for(var j=0;j<bio.length;j++){
      var option=bio[j].closest('.pe-bf-opt');
      installGeneratedAvatar(bio[j],option&&option.textContent,ART.profileAbout);
    }
  }

  function polishProfileLeague(){
    var cards=document.querySelectorAll('.pf2-bcard');
    for(var i=0;i<cards.length;i++){
      var title=normalizeUiText((cards[i].querySelector('.pf2-btitle')||{}).textContent);
      if(title.indexOf('SEZON LIGI')<0)continue;
      setUtilityArt(cards[i].querySelector('.pf2-bic'),ART.seasonEmblem,'luno-v16-profile-league','Season league');
    }
  }

  function polishRankingArt(){
    var columns=document.querySelectorAll('.rk-pod-col');
    for(var i=0;i<columns.length;i++){
      var rank=columns[i].classList.contains('rk-pod-1')?1:
        (columns[i].classList.contains('rk-pod-2')?2:3);
      var medal=columns[i].querySelector('.rk-pod-medal');
      if(medal&&!medal.querySelector('.luno-v16-rank-medal')){
        medal.innerHTML='<img class="luno-v16-rank-medal" src="'+
          (rank===1?ART.rankGold:(rank===2?ART.rankSilver:ART.rankBronze))+'" alt="">';
      }
      var crown=columns[i].querySelector('.rk-crown');
      if(crown&&!crown.querySelector('img')){
        crown.innerHTML='<img src="'+ART.rankCrown+'" alt="">';
        crown.classList.add('luno-v16-rank-crown');
      }
    }
    var stars=document.querySelectorAll('.rk-pst');
    for(var j=0;j<stars.length;j++)stars[j].classList.add('luno-v16-rank-star');
    var rows=document.querySelectorAll('.rk-row,.rk-podium-title,.rk-list-title');
    for(var k=0;k<rows.length;k++)replaceInlineSymbols(rows[k]);
  }

  function polishLegacyTypography(){
    var nodes=document.querySelectorAll(
      '.screen:not(#loading):not(#intro) *,#ovTitle,#ovBody *,#matchMenuOverlay *,.mm-overlay-content *,#game *,'+
      '#cardActMenu *,#cardActionOv *,#lvlChooser *'
    );
    for(var i=0;i<nodes.length;i++){
      var node=nodes[i];
      if(node.dataset.lunoTypeV18||node.closest('.rtitle,.lpx-season-name,.luno-auth-title,.luno-onboard-title,.itut-title'))continue;
      node.dataset.lunoTypeV18='1';
      var style=getComputedStyle(node);
      var family=String(style.fontFamily||'');
      var size=parseFloat(style.fontSize)||0;
      if(size>22||!/Cinzel|Georgia|Spectral/i.test(family))continue;
      node.style.setProperty('font-family','var(--luno-font-ui)','important');
      node.style.setProperty('letter-spacing','0','important');
    }
  }

  function polishMatchmaking(){
    var avatar=document.querySelector('.mm-me-av');
    if(avatar&&!avatar.dataset.lunoV13){
      avatar.dataset.lunoV13='1';
      avatar.innerHTML=avatarMarkup(currentAvatarValue());
      var image=avatar.querySelector('img');
      if(image)image.classList.add('luno-v13-mm-avatar');
    }
    var trophies=document.querySelector('.mm-me-trophies');
    if(trophies&&!trophies.dataset.lunoV13){
      trophies.dataset.lunoV13='1';
      var value=(window.PLAYER&&PLAYER.trophies)||0;
      trophies.innerHTML='<img src="'+ART.trophy+'" alt=""><span>'+fmt(value)+' kupa</span>';
    }
    var status=byId('mmStatus');
    var spinnerBox=document.querySelector('.mm-spinner-box');
    if(status&&spinnerBox){
      var found=String(status.textContent||'').toLocaleUpperCase('tr-TR').indexOf('RAKİP BULUNDU')>=0;
      spinnerBox.classList.toggle('is-found',found);
    }
    var noOpponent=document.querySelector('.mm-no-opp');
    if(noOpponent&&!noOpponent.dataset.lunoV13){
      noOpponent.dataset.lunoV13='1';
      noOpponent.innerHTML='<img src="'+ART.baby+'" alt="Luno eğitmeni">';
    }
  }

  function polishLocalPass(){
    var ov=byId('localPassOv');
    if(!ov||ov.dataset.lunoV13)return;
    ov.dataset.lunoV13='1';
    var piece=ov.querySelector('.lp-pip');
    if(piece)piece.innerHTML='<img src="'+ART.duel+'" alt="Luno yüz yüze maç">';
  }

  function polishReconnect(){
    var proposals=document.querySelectorAll('.mm-proposal');
    for(var i=0;i<proposals.length;i++){
      var name=proposals[i].querySelector('.mm-prop-name');
      var icon=proposals[i].querySelector('.mm-prop-icon');
      if(!name||!icon||icon.dataset.lunoReconnect)continue;
      if(String(name.textContent||'').toLocaleUpperCase('tr-TR').indexOf('YENİDEN BAĞLAN')<0)continue;
      icon.dataset.lunoReconnect='1';
      icon.innerHTML='<img class="luno-reconnect-art" src="'+ART.duel+'" alt="Devam eden Luno maçı">';
    }
  }

  function setUtilityArt(node,src,className,alt){
    if(!node)return;
    var image=node.querySelector('img.luno-v14-utility-art');
    if(!image){
      node.textContent='';
      image=document.createElement('img');
      image.className='luno-v14-utility-art';
      node.appendChild(image);
    }
    image.src=src;
    image.alt=alt||'';
    if(className)node.classList.add(className);
  }

  function cssAsset(src){
    return String(src||'').replace(/^assets\//,'');
  }

  function replaceInlineSymbols(node){
    if(!node||node.querySelector('img.luno-inline-art'))return;
    var html=node.innerHTML;
    var symbols=[
      ['\uD83D\uDC51',ART.premiumCrown],
      ['\uD83C\uDFC6',ART.statusTrophy],
      ['\uD83C\uDF81',ART.dailyGift],
      ['\uD83D\uDC8E',ART.statusGem],
      ['\uD83E\uDE99',ART.statusCoin],
      ['\u2694',ART.duel],
      ['\u2728',ART.star],
      ['\uD83D\uDE09',ART.smile],
      ['\uD83D\uDCA7',ART.mana],
      ['\uD83D\uDD25',ART.fire],
      ['\uD83D\uDCBE',ART.card],
      ['\uD83C\uDCCF',ART.card],
      ['\u265F',ART.crest],
      ['\u26A1',ART.mana],
      ['\uD83C\uDF89',ART.star]
    ];
    for(var i=0;i<symbols.length;i++){
      var image='<img class="luno-inline-art" src="'+symbols[i][1]+'" alt="">';
      html=html.split(symbols[i][0]+'\uFE0F').join(image);
      html=html.split(symbols[i][0]).join(image);
    }
    if(html!==node.innerHTML)node.innerHTML=html;
  }

  function setChestRewardArt(node,src){
    if(!node)return;
    node.textContent='';
    node.classList.add('luno-v14-reward-art');
    node.style.setProperty('--luno-chest-reward','url("'+cssAsset(src)+'")');
  }

  function replaceChestSymbols(node){
    if(!node||node.querySelector('.luno-v14-chest-inline'))return;
    var html=node.innerHTML;
    var symbols=[
      ['\uD83C\uDFC6',ART.statusTrophy],
      ['\u2728',ART.star]
    ];
    for(var i=0;i<symbols.length;i++){
      var span='<span class="luno-v14-chest-inline" style="--luno-chest-inline:url(&quot;'+cssAsset(symbols[i][1])+'&quot;)"></span>';
      html=html.split(symbols[i][0]+'\uFE0F').join(span);
      html=html.split(symbols[i][0]).join(span);
    }
    if(html!==node.innerHTML)node.innerHTML=html;
  }

  function normalizeUiText(value){
    return String(value||'')
      .toLocaleUpperCase('tr-TR')
      .replace(/\u0130/g,'I')
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g,'');
  }

  function polishMatchModeToast(){
    var node=byId('toast');
    if(!node)return;
    if(node.dataset.lunoModeKey&&node.querySelector('.luno-v16-mode-art'))return;
    var label=String(node.textContent||'').trim();
    var text=normalizeUiText(label);
    var key='';
    if(text.indexOf('SIRALAMALI MAC')===0)key='ranked';
    else if(text.indexOf('ANTRENMAN MAC')===0)key='training';
    else if(text.indexOf('ARKADAS MACI')===0)key='friend';
    else if(text.indexOf('YUZ YUZE MAC')===0)key='local';
    else if(text.indexOf('ONLINE MAC')===0)key='online';
    else if(text.indexOf('KLASIK MAC')===0)key=(window.G&&G.mode==='online')?'online':'classic';
    var map={
      friend:ART.modeFriend,
      ranked:ART.modeRanked,
      training:ART.modeTraining,
      local:ART.modeLocal,
      online:ART.modeOnline,
      classic:ART.modeClassic
    };
    if(!key||!map[key]){
      node.classList.remove('luno-v16-mode-toast');
      delete node.dataset.lunoModeKey;
      return;
    }
    node.dataset.lunoModeKey=key;
    node.classList.add('luno-v16-mode-toast');
    node.setAttribute('aria-label',label);
    node.innerHTML='<img class="luno-v16-mode-art" src="'+map[key]+'" alt="'+esc(label)+'">';
  }

  function polishMatchHistory(){
    var rows=document.querySelectorAll('.mh-row');
    for(var i=0;i<rows.length;i++){
      var icon=rows[i].querySelector('.mh-row-icon');
      var result=rows[i].classList.contains('mh-row-win')?ART.resultVictory:
        (rows[i].classList.contains('mh-row-loss')?ART.resultDefeat:ART.resultDraw);
      setUtilityArt(icon,result,'luno-v16-history-result','');
      replaceInlineSymbols(rows[i].querySelector('.mh-row-opp-trophy'));
      var replay=rows[i].querySelector('.mh-replay-btn');
      if(replay)replay.classList.add('luno-v16-replay-action');
      var unavailable=rows[i].querySelector('.mh-no-replay');
      if(unavailable)setUtilityArt(unavailable,ART.lock,'luno-v16-no-replay','Replay unavailable');
    }
  }

  function polishReplay(){
    var replay=byId('replayOverlay');
    if(!replay)return;
    var title=replay.querySelector('.rp-title');
    if(title&&!title.dataset.lunoV16){
      title.dataset.lunoV16='1';
      title.innerHTML='<img src="'+ART.timekeeper+'" alt=""><span>MA\u00c7 TEKRARI</span>';
    }
    var controls=replay.querySelectorAll('.rp-ctrl,.rp-close');
    for(var i=0;i<controls.length;i++)controls[i].classList.add('luno-v16-control-plate');
  }

  function polishAchievements(){
    if(!Array.isArray(window.ACHIEVEMENTS))return;
    var cards=document.querySelectorAll('.ach-card');
    for(var i=0;i<cards.length&&i<ACHIEVEMENTS.length;i++){
      var def=ACHIEVEMENTS[i];
      var icon=cards[i].querySelector('.ach-icon');
      var src=BASE+'achievement-'+String(def.id||'').replace(/_/g,'-')+'-v4.png';
      setUtilityArt(icon,src,'luno-v16-achievement-icon',def.name||'');
      replaceInlineSymbols(cards[i].querySelector('.ach-reward'));
      var locked=cards[i].querySelector('.ach-locked-ic');
      if(locked)setUtilityArt(locked,ART.lock,'luno-v16-achievement-lock','Locked');
      var claim=cards[i].querySelector('.ach-claim-btn');
      if(claim)claim.classList.add('luno-v16-achievement-claim');
    }
  }

  function polishPromotion(){
    var promo=byId('promo');
    if(!promo)return;
    var codes=['Q','R','B','N'];
    var names={Q:'queen',R:'rook',B:'bishop',N:'knight'};
    var color=(window.G&&G.turn==='B')?'B':'W';
    var setId='';
    try{
      setId=typeof window.pieceSetFor==='function'?pieceSetFor(color):
        ((window.PLAYER&&PLAYER.activePieceSet)||'');
    }catch(e){}
    if(!setId||setId==='std')setId='luno';
    var set=window.PIECE_IMG&&PIECE_IMG[setId];
    var picks=promo.querySelectorAll('.promo-pick');
    for(var i=0;i<picks.length&&i<codes.length;i++){
      var holder=picks[i].querySelector('span');
      if(!holder)continue;
      var src=set&&set[color]&&set[color][codes[i]];
      if(!src)src=BASE+'piece-luno-'+color.toLowerCase()+'-'+names[codes[i]]+'-v22-mobile.webp';
      if(holder.dataset.lunoPieceSrc===src)continue;
      holder.dataset.lunoPieceSrc=src;
      holder.innerHTML='<img src="'+src+'" alt="" loading="eager" decoding="async" fetchpriority="high">';
      picks[i].classList.add('luno-v16-promo-pick');
    }
    var box=promo.querySelector('.promobox');
    if(box)box.classList.add('luno-v16-promo-box');
  }

  function polishArenaPromotion(){
    var children=document.body.children;
    for(var i=0;i<children.length;i++){
      var node=children[i];
      if(node.tagName!=='DIV'||node.id||node.classList.contains('screen'))continue;
      var text=normalizeUiText(node.textContent);
      if(text.indexOf('KART YUVASI')<0||
        (text.indexOf('YENI KARTLAR ACILDI')<0&&text.indexOf('YENI ARENA ACILDI')<0))continue;
      node.classList.add('luno-v16-arena-promotion');
      var divs=node.querySelectorAll('div');
      for(var j=0;j<divs.length;j++){
        var own=normalizeUiText(divs[j].textContent);
        if(own.indexOf('KART YUVASI')<0||own.length>32)continue;
        replaceInlineSymbols(divs[j]);
        var slotBox=divs[j].parentElement;
        if(slotBox){
          slotBox.classList.add('luno-v16-arena-slots');
          slotBox.style.setProperty('opacity','1','important');
          slotBox.style.setProperty('transform','scale(1)','important');
          slotBox.style.setProperty('display','flex','important');
          if(slotBox.children[1]){
            var slotRow=slotBox.children[1];
            slotRow.classList.add('luno-v16-arena-slot-row');
            for(var sc=0;sc<slotRow.children.length;sc++){
              slotRow.children[sc].style.setProperty('opacity','1','important');
              slotRow.children[sc].style.setProperty('transform','none','important');
            }
          }
          if(slotBox.children[2]){
            slotBox.children[2].classList.add('luno-v16-arena-slot-copy');
            replaceInlineSymbols(slotBox.children[2]);
          }
        }
        var rewardRow=slotBox&&slotBox.nextElementSibling;
        if(rewardRow&&rewardRow.tagName==='DIV'){
          rewardRow.classList.add('luno-v16-arena-rewards');
          rewardRow.style.setProperty('opacity','1','important');
          rewardRow.style.setProperty('transform','none','important');
          var rewardCards=rewardRow.children;
          for(var rc=0;rc<rewardCards.length;rc++){
            rewardCards[rc].style.setProperty('opacity','1','important');
            rewardCards[rc].style.setProperty('transform','none','important');
          }
        }
        break;
      }
    }
  }

  function polishNotifications(){
    var notifications=document.querySelectorAll('.notif-popup');
    for(var i=0;i<notifications.length;i++){
      notifications[i].classList.add('luno-v16-notification');
      var title=normalizeUiText((notifications[i].querySelector('.np-title')||{}).textContent);
      var src=title.indexOf('MAC')>=0?ART.duel:
        (title.indexOf('SONUC')>=0?ART.resultVictory:
          (title.indexOf('CEVRIMICI')>=0?ART.star:ART.message));
      setUtilityArt(notifications[i].querySelector('.np-icon'),src,'luno-v16-notification-icon','');
      var close=notifications[i].querySelector('.np-close');
      if(close)close.setAttribute('aria-label','Kapat');
    }
  }

  function polishScreenBackdrops(){
    var overlay=byId('overlay');
    if(!overlay)return;
    var title=normalizeUiText((byId('ovTitle')||{}).textContent);
    var classes=[
      'luno-bg-club','luno-bg-war','luno-bg-arena',
      'luno-bg-market','luno-bg-tutorial'
    ];
    for(var i=0;i<classes.length;i++)overlay.classList.remove(classes[i]);

    var selected='luno-bg-club';
    if(/MAGAZA|DUKKAN|LUNO PREMIUM/.test(title)){
      selected='luno-bg-market';
    }else if(/ARENA|SEZON|LUNO PASS/.test(title)){
      selected='luno-bg-arena';
    }else if(/EGITIM|REHBER|MAC TEKRARI/.test(title)){
      selected='luno-bg-tutorial';
    }else if(/SIRALI|ONLINE|ODA|SAVAS|YAPAY|ARKADASINLA|RAKIP|YENIDEN BAGLAN|MAC GECMISI/.test(title)){
      selected='luno-bg-war';
    }
    overlay.classList.add(selected);
  }

  function polishButtons(){
    var buttons=document.querySelectorAll('button');
    var skip=/\b(luno-auth-eye|luno-auth-back|luno-auth-check|luno-auth-link|iconbtn|cam-btn-ic|chat-emoji-btn|emoji-quick-btn-inline|mn-qbtn|mn-navitem|l12-back-btn|chat-send-btn-inline)\b/;
    for(var i=0;i<buttons.length;i++){
      var button=buttons[i];
      var classes=String(button.className||'');
      if(skip.test(classes)||button.closest('.luno-auth-switch')||button.closest('#intro'))continue;
      var rect=button.getBoundingClientRect();
      if(rect.width<88||rect.height<30||rect.height>76||rect.width/rect.height<1.65)continue;
      var key=normalizeUiText(classes+' '+String(button.textContent||''));
      var variant='primary';
      if(/REMOVE|REJECT|RESIGN|DANGER|SIGNOUT|TESLIM|ARKADASLIKTAN|REDDET|CIKIS|SIL/.test(key)){
        variant='danger';
      }else if(/GOOGLE|DAVET|MESAJ|KOPYALA|DETAY|REHBER|KURAL|TEKRAR|PAYLAS|BERABERLIK|GALERI|BILGI|INCELE|DM|INVITE|COPY|RULES|HISTORY|REPLAY|SHARE|CHAT|DRAW/.test(key)){
        variant='secondary';
      }else if(/CANCEL|GHOST|ALT|BOT|IPTAL|VAZGEC|KAPAT|GERI|SONRA|HAYIR/.test(key)){
        variant='neutral';
      }
      if(button.disabled)variant='neutral';
      button.classList.remove(
        'luno-v14-plate-primary','luno-v14-plate-secondary',
        'luno-v14-plate-neutral','luno-v14-plate-danger'
      );
      button.classList.add('luno-v14-plate-button','luno-v14-plate-'+variant);
    }
  }

  function polishUtilityArt(){
    setUtilityArt(document.querySelector('.lp-crown-big'),ART.premiumCrown,'luno-v14-premium-crown','Luno Premium');
    setUtilityArt(document.querySelector('.ol-info-icon'),ART.message,'luno-v14-online-info','Online friends');
    setUtilityArt(document.querySelector('.ol-join-hero'),ART.lock,'luno-v14-join-lock','Room code');
    setUtilityArt(document.querySelector('.wr-sp-center'),ART.lock,'luno-v14-wait-lock','Waiting room');

    var onlineCards=document.querySelectorAll('.ol-card-icon');
    if(onlineCards[0])setUtilityArt(onlineCards[0],ART.lock,'luno-v14-online-card','Create room');
    if(onlineCards[1])setUtilityArt(onlineCards[1],ART.message,'luno-v14-online-card','Join room');

    var tournament=document.querySelector('.l12-tournament .l12-css-lock');
    if(tournament)setUtilityArt(tournament,ART.lock,'luno-v14-tournament-lock','Tournament locked');

    var inboxImages=document.querySelectorAll('.l12-inbox-hero > img,.l12-inbox-empty > img,.dm-empty > img,.dm-send > img');
    for(var i=0;i<inboxImages.length;i++){
      inboxImages[i].src=ART.message;
      inboxImages[i].classList.add('luno-v14-message-art');
    }

    var proposals=document.querySelectorAll('.mm-proposal');
    for(var j=0;j<proposals.length;j++){
      var text=String(proposals[j].textContent||'').toLocaleUpperCase('tr-TR');
      replaceInlineSymbols(proposals[j]);
      var icon=proposals[j].querySelector('.mm-prop-icon');
      if(!icon)continue;
      if(text.indexOf('G\u00dcNL\u00dcK \u00d6D\u00dcL')>=0){
        setUtilityArt(icon,ART.dailyGift,'luno-v14-proposal-art','Daily reward');
      }else if(text.indexOf('PREMIUM')>=0){
        setUtilityArt(icon,ART.premiumCrown,'luno-v14-proposal-art','Luno Premium');
        var premiumPanel=proposals[j].closest('.mm-overlay-content');
        if(premiumPanel)premiumPanel.classList.add('luno-v15-pass-buy');
      }else if(text.indexOf('SEZON TAMAMLANDI')>=0){
        setUtilityArt(icon,ART.trophy,'luno-v14-proposal-art','Season reward');
      }
    }

    replaceInlineSymbols(document.querySelector('.mn-luno-bubble'));
    replaceInlineSymbols(byId('toast'));

    var actionButtons=document.querySelectorAll('.mm-action-close');
    for(var a=0;a<actionButtons.length;a++){
      var actionText=String(actionButtons[a].textContent||'').toLocaleUpperCase('tr-TR');
      if(actionText.indexOf('VAZGE\u00c7')>=0)actionButtons[a].classList.add('luno-v14-secondary-action');
      if(actionText.indexOf('\u0130PTAL')>=0)actionButtons[a].classList.add('luno-v14-danger-action');
    }

    var copyMark=document.querySelector('.wr-btn-copy span');
    if(copyMark){
      copyMark.textContent='';
      copyMark.classList.add('luno-v14-copy-mark');
    }

    var chest=byId('chestOpenOv');
    if(chest){
      var chestTitle=chest.querySelector('.chest-title');
      var chestName=String(chestTitle&&chestTitle.textContent||'').toLocaleUpperCase('tr-TR');
      var chestKey=chestName.replace(/\u0130/g,'I').normalize('NFD').replace(/[\u0300-\u036f]/g,'');
      var chestArt=chestKey.indexOf('KRALIYET')>=0?ART.chestRoyal:
        (chestKey.indexOf('EFSANEVI')>=0?ART.chestLegendary:
          (chestKey.indexOf('NADIR')>=0?ART.chestRare:ART.chestCommon));
      setUtilityArt(chest.querySelector('.chest-shape'),chestArt,'luno-v14-chest-shape','Luno chest');
      var rewardsTitle=chest.querySelector('.chest-rewards-title');
      if(rewardsTitle&&!rewardsTitle.dataset.lunoV14){
        rewardsTitle.dataset.lunoV14='1';
        rewardsTitle.innerHTML=
          '<span class="luno-v14-chest-title-art" style="--luno-chest-inline:url(&quot;'+cssAsset(ART.statusTrophy)+'&quot;)"></span>'+
          '<span class="luno-v14-chest-title-copy">KAZANDIKLARIN</span>'+
          '<span class="luno-v14-chest-title-art" style="--luno-chest-inline:url(&quot;'+cssAsset(ART.statusTrophy)+'&quot;)"></span>';
      }
      var rewardItems=chest.querySelectorAll('.cr-item');
      for(var r=0;r<rewardItems.length;r++){
        var rewardIcon=rewardItems[r].querySelector('.cr-ic');
        var rewardText=String(rewardItems[r].textContent||'').toLocaleUpperCase('tr-TR');
        if(rewardItems[r].classList.contains('cr-gold')){
          setChestRewardArt(rewardIcon,ART.statusCoin);
        }else if(rewardText.indexOf('\u00c7ER\u00c7EVE')>=0){
          setChestRewardArt(rewardIcon,ART.gallery);
        }else if(rewardText.indexOf('KRAL LUNO')>=0){
          setChestRewardArt(rewardIcon,ART.premiumCrown);
        }
        replaceChestSymbols(rewardItems[r].querySelector('.cr-name'));
        replaceChestSymbols(rewardItems[r].querySelector('.cr-amount'));
      }
    }

    var coming=document.querySelector('.cs-wrap');
    if(coming){
      var comingTitle=coming.querySelector('.cs-title');
      var comingIcon=coming.querySelector('.cs-icon');
      var title=String(comingTitle&&comingTitle.textContent||'').toLocaleUpperCase('tr-TR');
      setUtilityArt(
        comingIcon,
        title.indexOf('TURNUVA')>=0?ART.lock:(title.indexOf('MA\u00c7')>=0?ART.duel:ART.message),
        'luno-v14-coming-art',
        'Coming soon'
      );
    }

    var invite=byId('inviteWaitOv');
    if(invite){
      var invitePanel=invite.firstElementChild;
      if(invitePanel)invitePanel.classList.add('luno-v14-invite-panel');
      setUtilityArt(invite.querySelector('.mm-wait-spinner'),ART.message,'luno-v14-invite-art','Invitation sent');
      var inviteButton=invite.querySelector('button');
      if(inviteButton)inviteButton.classList.add('luno-v14-invite-cancel');
    }

    var tips=byId('tipsOv');
    if(tips){
      var tipsPanel=tips.firstElementChild;
      if(tipsPanel)tipsPanel.classList.add('luno-v14-tips-panel');
      var rows=tipsPanel?tipsPanel.querySelectorAll(':scope > div[style*="display:flex"]'):[];
      var tipArt=[ART.card,BASE+'level-tier-02-v9.png',ART.dailyGift];
      for(var k=0;k<rows.length&&k<tipArt.length;k++){
        rows[k].classList.add('luno-v14-tip-row');
        setUtilityArt(rows[k].firstElementChild,tipArt[k],'luno-v14-tip-icon','');
      }
      if(tipsPanel){
        var direct=tipsPanel.children;
        for(var m=0;m<direct.length;m++){
          if(String(direct[m].textContent||'').toLocaleUpperCase('tr-TR').indexOf('\u0130LK ZAFER\u0130N!')===0){
            direct[m].textContent='\u0130LK ZAFER\u0130N!';
            direct[m].classList.add('luno-v14-tips-title');
          }
        }
        var tipsButton=tipsPanel.querySelector('button');
        if(tipsButton)tipsButton.classList.add('luno-v14-tips-button');
      }
    }
    polishButtons();
  }

  function repairMenu(){
    var trophy=document.querySelector('#menu .cur-trophy');
    if(trophy&&!trophy.dataset.lunoSeasonLink){
      trophy.dataset.lunoSeasonLink='1';
      trophy.setAttribute('role','button');
      trophy.setAttribute('tabindex','0');
      trophy.setAttribute('aria-label','Sezon ekranını aç');
      trophy.addEventListener('click',function(){
        clickSound();
        if(typeof window.openSeasonScreen==='function')window.openSeasonScreen();
      });
      trophy.addEventListener('keydown',function(event){
        if(event.key==='Enter'||event.key===' '){event.preventDefault();trophy.click();}
      });
    }
    var name=byId('arenaName'),pts=byId('arenaPts'),fill=byId('arenaFill');
    if(!name||!pts||!window.PLAYER||!Array.isArray(window.ARENAS))return;
    var index=0,trophies=Number(PLAYER.trophies||0);
    for(var i=0;i<ARENAS.length;i++)if(trophies>=Number(ARENAS[i].min||0))index=i;
    var arena=ARENAS[index];
    if(!arena)return;
    name.textContent=arena.name||'Luno Arenası';
    if(index===ARENAS.length-1){
      pts.textContent=fmt(trophies)+' · ZİRVE';
      if(fill)fill.style.width='100%';
    }else{
      pts.textContent=fmt(trophies)+' / '+fmt(arena.max);
    }
  }

  function showLunoConfirm(options,onConfirm){
    var old=byId('lunoV13Confirm');
    if(old)old.remove();
    options=options||{};
    var ov=document.createElement('div');
    ov.id='lunoV13Confirm';
    ov.className='luno-v13-confirm';
    var price=options.price?'<div class="luno-v13-confirm-price">'+
      (options.currency?'<img src="'+options.currency+'" alt="">':'')+
      '<span>'+esc(options.price)+'</span></div>':'';
    ov.innerHTML='<div class="luno-v13-confirm-card" role="dialog" aria-modal="true" aria-labelledby="lunoV13ConfirmTitle">'+
      '<img class="luno-v13-confirm-art" src="'+(options.asset||ART.crest)+'" alt="">'+
      '<div class="luno-v13-confirm-kicker">'+esc(options.kicker||'LUNO GÜVENLİ ONAY')+'</div>'+
      '<h3 id="lunoV13ConfirmTitle">'+esc(options.title||'Onaylıyor musun?')+'</h3>'+
      '<p>'+esc(options.message||'Bu işlem hesabına hemen uygulanacak.')+'</p>'+
      price+
      '<div class="luno-v13-confirm-actions">'+
        '<button type="button" class="luno-v13-confirm-cancel">VAZGEÇ</button>'+
        '<button type="button" class="luno-v13-confirm-ok">'+esc(options.ok||'ONAYLA')+'</button>'+
      '</div>'+
    '</div>';
    document.body.appendChild(ov);
    var close=function(){
      ov.classList.remove('show');
      setTimeout(function(){if(ov.parentNode)ov.parentNode.removeChild(ov);},180);
    };
    ov.querySelector('.luno-v13-confirm-cancel').onclick=function(){clickSound();close();};
    ov.querySelector('.luno-v13-confirm-ok').onclick=function(){
      clickSound();
      close();
      if(typeof onConfirm==='function')setTimeout(onConfirm,190);
    };
    ov.addEventListener('click',function(event){if(event.target===ov)close();});
    requestAnimationFrame(function(){ov.classList.add('show');});
  }
  window.lunoReleaseConfirm=showLunoConfirm;

  function withConfirmBypass(fn,context,args){
    var previous=window.confirm;
    window.confirm=function(){return true;};
    try{return fn.apply(context,args||[]);}
    finally{window.confirm=previous;}
  }

  function wrapResourcePurchase(name,describe){
    var original=window[name];
    if(typeof original!=='function'||original.__lunoV13Confirm)return;
    var wrapped=function(){
      var args=Array.prototype.slice.call(arguments);
      var info=null;
      try{info=describe.apply(this,args);}catch(e){}
      if(!info||info.skip)return original.apply(this,args);
      var context=this;
      showLunoConfirm(info,function(){withConfirmBypass(original,context,args);});
    };
    wrapped.__lunoV13Confirm=true;
    wrapped.__lunoOriginal=original;
    window[name]=wrapped;
  }

  function findById(list,id){
    if(!Array.isArray(list))return null;
    for(var i=0;i<list.length;i++)if(list[i]&&list[i].id===id)return list[i];
    return null;
  }
  function chestAsset(id){
    var map={
      common:BASE+'shop-chest-common-v3.png',
      rare:BASE+'shop-chest-rare-v3.png',
      legendary:BASE+'shop-chest-legendary-v3.png',
      royal:BASE+'shop-chest-royal-v3.png'
    };
    return map[id]||ART.chest;
  }
  function installResourceConfirmations(){
    wrapResourcePurchase('openChest',function(id){
      var chest=findById(window.CHESTS,id);
      if(!chest)return {skip:true};
      var gem=chest.price&&chest.price.gem!=null;
      var amount=gem?chest.price.gem:chest.price.gold;
      var have=gem?Number(PLAYER.gems||0):Number(PLAYER.gold||0);
      if(have<amount)return {skip:true};
      return {asset:chestAsset(id),kicker:'SANDIK ONAYI',title:chest.name,message:'Ödüller sandık açılır açılmaz hesabına eklenecek.',price:fmt(amount)+' '+(gem?'ELMAS':'ALTIN'),currency:gem?ART.gem:ART.coin,ok:'SANDIĞI AÇ'};
    });
    wrapResourcePurchase('buySkin',function(id){
      var skin=findById(window.PAWN_SKINS,id);
      if(!skin||(PLAYER.ownedSkins||[]).indexOf(id)>=0||typeof window.skinPrice!=='function')return {skip:true};
      var price=skinPrice(skin.rarity),have=price.cur==='gem'?Number(PLAYER.gems||0):Number(PLAYER.gold||0);
      if(have<price.amt)return {skip:true};
      return {asset:skin.img||ART.crest,kicker:'KOSTÜM ONAYI',title:skin.name,message:'Kostüm koleksiyonuna kalıcı olarak eklenecek.',price:fmt(price.amt)+' '+(price.cur==='gem'?'ELMAS':'ALTIN'),currency:price.cur==='gem'?ART.gem:ART.coin,ok:'SATIN AL'};
    });
    wrapResourcePurchase('buyEmojiPack',function(id){
      var item=findById(window.EMOJI_LIST,id);
      if(!item||(PLAYER.ownedEmojis||[]).indexOf(id)>=0)return {skip:true};
      var prices={common:500,rare:1500,legendary:4000,mythic:10000},price=prices[item.rarity]||1000;
      if(Number(PLAYER.gold||0)<price)return {skip:true};
      return {asset:item.anim||item.img||ART.crest,kicker:'EMOJİ ONAYI',title:item.name,message:'Emoji koleksiyonuna kalıcı olarak eklenecek.',price:fmt(price)+' ALTIN',currency:ART.coin,ok:'SATIN AL'};
    });
    wrapResourcePurchase('selectBioFrame',function(id){
      if(typeof window.getBioFrame!=='function'||typeof window.isBioFrameOwned!=='function')return {skip:true};
      var item=getBioFrame(id);
      if(!item||isBioFrameOwned(id)||item.premiumOnly||item.shards)return {skip:true};
      var have=item.cur==='gem'?Number(PLAYER.gems||0):Number(PLAYER.gold||0);
      if(have<item.price)return {skip:true};
      return {asset:ART.gallery,kicker:'BİYO ÇERÇEVESİ',title:item.name,message:'Çerçeve profil koleksiyonuna kalıcı olarak eklenecek.',price:fmt(item.price)+' '+(item.cur==='gem'?'ELMAS':'ALTIN'),currency:item.cur==='gem'?ART.gem:ART.coin,ok:'SATIN AL'};
    });
    wrapResourcePurchase('selectProfileFrame',function(id){
      if(typeof window.getAvailableFrames!=='function')return {skip:true};
      var item=findById(getAvailableFrames(),id);
      if(!item||item.unlocked||item.premiumOnly||item.shards)return {skip:true};
      var have=item.cur==='gem'?Number(PLAYER.gems||0):Number(PLAYER.gold||0);
      if(have<item.price)return {skip:true};
      return {asset:ART.gallery,kicker:'AVATAR ÇERÇEVESİ',title:item.name,message:'Çerçeve profil koleksiyonuna kalıcı olarak eklenecek.',price:fmt(item.price)+' '+(item.cur==='gem'?'ELMAS':'ALTIN'),currency:item.cur==='gem'?ART.gem:ART.coin,ok:'SATIN AL'};
    });
    wrapResourcePurchase('confirmSignOut',function(){
      return {asset:ART.signout,kicker:'HESAP',title:'Çıkış yapılsın mı?',message:'Tekrar giriş yapana kadar bu cihazdaki oturum kapanacak.',ok:'ÇIKIŞ YAP'};
    });
    wrapResourcePurchase('removeFriend',function(uid,name){
      return {asset:ART.removeFriend,kicker:'ARKADAŞLAR',title:(name||'Bu oyuncu')+' silinsin mi?',message:'Oyuncu arkadaş listenden kaldırılacak.',ok:'ARKADAŞLIKTAN ÇIKAR'};
    });
  }

  function billingBridge(){
    try{
      if(window.Capacitor&&Capacitor.Plugins&&Capacitor.Plugins.LunoBilling)return Capacitor.Plugins.LunoBilling;
      if(window.LunoBilling&&typeof window.LunoBilling.purchase==='function')return window.LunoBilling;
    }catch(e){}
    return null;
  }
  function billingVerifier(){
    return typeof window.lunoVerifyPurchaseToken==='function'
      ? window.lunoVerifyPurchaseToken
      : null;
  }
  function billingTimeout(promise,milliseconds){
    return new Promise(function(resolve,reject){
      var timer=setTimeout(function(){reject(new Error('billing-timeout'));},milliseconds);
      Promise.resolve(promise).then(function(value){clearTimeout(timer);resolve(value);},function(error){clearTimeout(timer);reject(error);});
    });
  }
  function installBillingListener(bridge){
    if(BILLING_STATE.listenerInstalled||!bridge||typeof bridge.addListener!=='function')return;
    BILLING_STATE.listenerInstalled=true;
    try{
      bridge.addListener('purchaseUpdated',function(result){
        var product=PRODUCT_BY_ID[result&&result.productId];
        if(product)verifyBillingPurchase(product,result).catch(function(){});
      });
    }catch(e){BILLING_STATE.listenerInstalled=false;}
  }
  function refreshBillingPrices(){
    var nodes=document.querySelectorAll('[data-luno-product]');
    for(var i=0;i<nodes.length;i++){
      var id=nodes[i].getAttribute('data-luno-product'),details=BILLING_STATE.products[id];
      nodes[i].classList.toggle('luno-billing-disabled',!BILLING_STATE.ready||!details);
      nodes[i].setAttribute('aria-disabled',BILLING_STATE.ready&&details?'false':'true');
    }
    var prices=document.querySelectorAll('[data-luno-price]');
    for(var j=0;j<prices.length;j++){
      var productId=prices[j].getAttribute('data-luno-price'),productDetails=BILLING_STATE.products[productId];
      prices[j].textContent=productDetails&&productDetails.formattedPrice?productDetails.formattedPrice:'GOOGLE PLAY';
    }
  }
  function prepareBilling(force){
    if(BILLING_STATE.ready&&!force)return Promise.resolve(BILLING_STATE);
    if(BILLING_STATE.promise)return BILLING_STATE.promise;
    var bridge=billingBridge(),user=null;
    try{user=window.firebase&&firebase.auth?firebase.auth().currentUser:null;}catch(e){}
    if(!user||!user.uid)return Promise.reject(new Error('auth-not-ready'));
    if(!bridge||typeof bridge.connect!=='function'||typeof bridge.getProducts!=='function')return Promise.reject(new Error('billing-not-available'));
    if(typeof window.lunoGetAppCheckToken!=='function'||typeof window.lunoSecureApi!=='function')return Promise.reject(new Error('app-check-not-ready'));
    installBillingListener(bridge);
    BILLING_STATE.ready=false;BILLING_STATE.error='';refreshBillingPrices();
    BILLING_STATE.promise=billingTimeout(Promise.all([
      window.lunoGetAppCheckToken(false),
      bridge.connect({})
    ]),12000).then(function(){
      return billingTimeout(Promise.all([
        window.lunoSecureApi('/billingHealth',{}),
        bridge.getProducts({})
      ]),18000);
    }).then(function(results){
      var health=results[0]||{},nativeCatalog=results[1]||{},serverProducts={},products={};
      (health.catalog||[]).forEach(function(item){if(item&&item.productId)serverProducts[item.productId]=item.type;});
      (nativeCatalog.products||[]).forEach(function(item){
        var expected=PRODUCT_BY_ID[item&&item.productId];
        if(expected&&item.formattedPrice&&item.productType===expected.type&&serverProducts[item.productId]===expected.type)products[item.productId]=item;
      });
      var required=Object.keys(PRODUCT_BY_ID),complete=required.every(function(id){return !!products[id];});
      if(health.ready!==true||health.catalogReady!==true||nativeCatalog.ready!==true||!complete)throw new Error('billing-catalog-not-ready');
      BILLING_STATE.products=products;BILLING_STATE.ready=true;BILLING_STATE.error='';refreshBillingPrices();
      try{window.dispatchEvent(new CustomEvent('luno:billing-ready'));}catch(e){}
      return BILLING_STATE;
    }).catch(function(error){
      BILLING_STATE.ready=false;BILLING_STATE.products={};BILLING_STATE.error=String(error&&error.message||error);refreshBillingPrices();throw error;
    }).finally(function(){BILLING_STATE.promise=null;});
    return BILLING_STATE.promise;
  }
  function verifyBillingPurchase(product,result){
    var verifier=billingVerifier();
    if(!verifier||!result||!result.purchaseToken)return Promise.reject(new Error('purchase-verifier-not-ready'));
    if(result.pending||Number(result.purchaseState)!==1){
      if(typeof window.toast==='function')toast('Satın alma Google Play onayı bekliyor.');
      return Promise.resolve({pending:true});
    }
    return Promise.resolve(verifier({
      productId:product.id,
      purchaseToken:result.purchaseToken,
      orderId:result.orderId||'',
      purchaseState:result.purchaseState
    })).then(function(verification){
      if(!verification||verification.verified!==true||verification.entitlementGranted!==true)throw new Error('entitlement-not-granted');
      if(typeof window.toast==='function')toast('Satın alma doğrulandı. Ödül hesabına işlendi.','neon');
      if(typeof window.lunoRefreshAuthoritativeState==='function')return window.lunoRefreshAuthoritativeState().then(function(){return verification;});
      return verification;
    }).catch(function(error){
      errorSound();
      if(typeof window.toast==='function')toast('Satın alma doğrulanamadı. Ürün hesabına eklenmedi.');
      throw error;
    });
  }
  function storeStatus(product){
    if(!product)return Promise.reject(new Error('unknown-product'));
    if(typeof window.toast==='function')toast('Google Play kontrol ediliyor...');
    return prepareBilling(false).then(function(){
      var bridge=billingBridge(),details=BILLING_STATE.products[product.id],billingUser=null;
      try{billingUser=window.firebase&&firebase.auth?firebase.auth().currentUser:null;}catch(e){}
      if(!billingUser||!billingUser.uid||!details)throw new Error('billing-not-ready');
      showLunoConfirm({
        asset:product.asset,
        kicker:'GOOGLE PLAY GÜVENLİ ÖDEME',
        title:product.name,
        message:'Ödeme Google Play üzerinden tamamlanır. Ürün yalnız sunucu doğrulamasından sonra hesabına işlenir.',
        price:details.formattedPrice,
        ok:'GOOGLE PLAY İLE AL'
      },function(){
        Promise.resolve(bridge.purchase({productId:product.id,accountId:billingUser.uid}))
          .then(function(result){return verifyBillingPurchase(product,result);})
          .catch(function(error){
            if(String(error&&error.message||error).toLowerCase().indexOf('iptal')<0){
              errorSound();if(typeof window.toast==='function')toast('Satın alma geçici olarak kullanılamıyor.');
            }
          });
      });
      return true;
    }).catch(function(){
      errorSound();
      if(typeof window.toast==='function')toast('Satın alma geçici olarak kullanılamıyor.');
      return false;
    });
  }
  function restorePurchases(){
    if(typeof window.toast==='function')toast('Satın alma hakların kontrol ediliyor...');
    return prepareBilling(true).then(function(){
      var bridge=billingBridge();
      if(!bridge||typeof bridge.restorePurchases!=='function')throw new Error('restore-not-available');
      return billingTimeout(bridge.restorePurchases({}),15000);
    }).then(function(nativeResult){
      var purchases=(nativeResult&&nativeResult.purchases||[]).filter(function(item){
        return item&&item.purchaseToken&&PRODUCT_BY_ID[item.productId]&&!item.pending&&Number(item.purchaseState)===1;
      }).map(function(item){return {productId:item.productId,purchaseToken:item.purchaseToken,orderId:item.orderId||'',purchaseState:item.purchaseState};});
      return window.lunoSecureApi('/restorePurchases',{purchases:purchases});
    }).then(function(result){
      if(typeof window.lunoRefreshAuthoritativeState==='function')window.lunoRefreshAuthoritativeState().catch(function(){});
      if(typeof window.toast==='function')toast(result&&result.restored?'Satın alma hakların yenilendi.':'Geri yüklenecek etkin satın alma bulunamadı.','neon');
      return result;
    }).catch(function(error){
      errorSound();if(typeof window.toast==='function')toast('Satın alma hakları şu anda yenilenemiyor.');throw error;
    });
  }
  window.lunoRefreshBillingPrices=function(){refreshBillingPrices();prepareBilling(false).catch(function(){});};
  window.lunoPrepareBilling=prepareBilling;
  window.lunoStartBillingPurchase=function(key){return storeStatus(PRODUCT_MAP[key]);};
  window.lunoRestorePurchases=restorePurchases;
  function installFiatPurchases(){
    if(typeof window.buyCurrency==='function'&&!window.buyCurrency.__lunoV13Store){
      var currency=function(type,amount){
        clickSound();
        var product=PRODUCT_MAP[type+'_'+amount];
        if(product)storeStatus(product);
      };
      currency.__lunoV13Store=true;
      window.buyCurrency=currency;
    }
    if(typeof window.buyPremium==='function'&&!window.buyPremium.__lunoV13Store){
      var premium=function(period){
        clickSound();
        var product=PRODUCT_MAP['premium_'+period];
        if(product)storeStatus(product);
      };
      premium.__lunoV13Store=true;
      window.buyPremium=premium;
    }
    if(typeof window.buyBundle==='function'&&!window.buyBundle.__lunoV13Store){
      var bundle=function(id){
        clickSound();
        var product=PRODUCT_MAP['bundle_'+id];
        if(product)storeStatus(product);
      };
      bundle.__lunoV13Store=true;
      window.buyBundle=bundle;
    }
  }

  function patchReleaseSettings(){
    var wrap=document.querySelector('#overlay.show .set-wrap');
    if(!wrap)return;
    var subtitles=wrap.querySelectorAll('.set-row-sub');
    for(var i=0;i<subtitles.length;i++){
      if(/^Sürüm\s+/i.test((subtitles[i].textContent||'').trim())){
        subtitles[i].textContent=typeof window.lunoBuildLabel==='function'?lunoBuildLabel(true):'Sürüm 1.5.0 · Yapım 3';
      }
    }
    if(byId('lunoAccountDeleteRow'))return;
    var titles=wrap.querySelectorAll('.set-section-title');
    var accountList=null;
    for(var j=0;j<titles.length;j++){
      if((titles[j].textContent||'').toUpperCase().indexOf('HESAP')>=0){
        accountList=titles[j].nextElementSibling;
        break;
      }
    }
    if(!accountList)return;
    var row=document.createElement('div');
    row.id='lunoAccountDeleteRow';
    row.className='set-row set-row-danger';
    row.setAttribute('role','button');
    row.setAttribute('tabindex','0');
    row.onclick=requestAccountDeletion;
    row.onkeydown=function(event){if(event.key==='Enter'||event.key===' '){event.preventDefault();requestAccountDeletion();}};
    row.innerHTML='<div class="set-row-icon">'+
      (typeof window.setUi==='function'?setUi('set_exit'):'')+
      '</div><div class="set-row-info"><div class="set-row-title">HESABIMI SİL</div>'+
      '<div class="set-row-sub">Hesabın ve oyun verilerin için silme talebi oluştur</div></div>'+
      '<div class="set-row-arrow">&#10095;</div>';
    accountList.appendChild(row);
  }

  function requestAccountDeletion(){
    if(typeof window.lunoRequestSecureAccountDeletion==='function'){
      return window.lunoRequestSecureAccountDeletion();
    }
    errorSound();
    if(typeof window.toast==='function')toast('Güvenli hesap silme servisi henüz hazır değil. Hiçbir veri silinmedi.');
  }

  function installReleaseSettings(){
    if(typeof window.openSettings!=='function'||window.openSettings.__lunoReleaseSettings)return;
    var originalOpenSettings=window.openSettings;
    var wrappedOpenSettings=function(){
      var result=originalOpenSettings.apply(this,arguments);
      requestAnimationFrame(patchReleaseSettings);
      return result;
    };
    wrappedOpenSettings.__lunoReleaseSettings=true;
    wrappedOpenSettings.__lunoOriginal=originalOpenSettings;
    window.openSettings=wrappedOpenSettings;
    window.lunoRequestAccountDeletion=requestAccountDeletion;
  }

  function installEngineHardening(){
    if(typeof window.applyMoveToBoard==='function'&&!window.applyMoveToBoard.__lunoReleaseHalfMove){
      var originalApplyMove=window.applyMoveToBoard;
      var safeApplyMove=function(from,to,promoType){
        var moving=window.G&&G.board?G.board[from]:null;
        var wasPawn=!!(moving&&moving.t==='P');
        var result=originalApplyMove.call(this,from,to,promoType);
        if(wasPawn&&result&&!result.blocked&&window.G)G.halfMove=0;
        return result;
      };
      safeApplyMove.__lunoReleaseHalfMove=true;
      window.applyMoveToBoard=safeApplyMove;
    }

    if(typeof window.insufficientMaterial==='function'&&!window.insufficientMaterial.__lunoReleaseDeadPosition){
      var deadPosition=function(){
        if(!window.G||!G.board)return false;
        var minors=[],others=0;
        for(var i=0;i<64;i++){
          var p=G.board[i];
          if(!p||p.t==='K')continue;
          if(p.t==='N'||p.t==='B')minors.push({t:p.t,sq:i});
          else others++;
        }
        if(others>0)return false;
        if(minors.length<=1)return true;
        for(var j=0;j<minors.length;j++)if(minors[j].t!=='B')return false;
        var color=((minors[0].sq%8)+((minors[0].sq/8)|0))&1;
        for(var k=1;k<minors.length;k++){
          if(((((minors[k].sq%8)+((minors[k].sq/8)|0))&1))!==color)return false;
        }
        return true;
      };
      deadPosition.__lunoReleaseDeadPosition=true;
      window.insufficientMaterial=deadPosition;
    }

    if(typeof window.positionKey==='function'&&!window.positionKey.__lunoReleaseVariantState){
      var variantPositionKey=function(){
        if(!window.G||!G.board)return'';
        var state='';
        for(var i=0;i<64;i++){
          var p=G.board[i];
          if(!p){state+='.';continue;}
          state+=(p.c==='W'?p.t:p.t.toLowerCase());
          var effects=[];
          if(p.frozen>0)effects.push('f'+p.frozen);
          if(p.resist>0)effects.push('r'+p.resist);
          if(p.resistLock)effects.push('l');
          if(p.barbarian)effects.push('b');
          if(p.poisoned)effects.push('p'+(p.poisonedDur||0));
          if(p.trapped>0)effects.push('t'+p.trapped);
          if(p.linkTo!=null)effects.push('k'+p.linkTo);
          if(p.gluePick)effects.push('u');
          if(p.angryN)effects.push('n');
          if(p.angryB)effects.push('a');
          if(p.ghost)effects.push('g'+(p.ghostDur||0));
          if(effects.length)state+='['+effects.join(',')+']';
        }
        function rookRight(square){
          var rook=G.board[square];
          return rook&&rook.t==='R'&&!rook.moved?'1':'0';
        }
        function kingRight(square){
          var king=G.board[square];
          return king&&king.t==='K'&&!king.moved?'1':'0';
        }
        function mapState(value){
          if(!value)return'';
          return Object.keys(value).sort(function(a,b){return(+a)-(+b);}).map(function(key){
            return key+':'+JSON.stringify(value[key]);
          }).join(',');
        }
        var ep=-1;
        if(G.epTarget!=null&&G.epTarget>=0&&typeof window.legal==='function'){
          var file=G.epTarget%8,rank=(G.epTarget/8)|0;
          var sourceRank=rank+(G.turn==='W'?-1:1);
          for(var delta=-1;delta<=1;delta+=2){
            var sourceFile=file+delta;
            if(sourceFile<0||sourceFile>7||sourceRank<0||sourceRank>7)continue;
            var source=sourceRank*8+sourceFile,pawn=G.board[source];
            if(pawn&&pawn.t==='P'&&pawn.c===G.turn&&legal(G.board,source).indexOf(G.epTarget)>=0){
              ep=G.epTarget;
              break;
            }
          }
        }
        return state+'|'+G.turn+'|'+ep+'|'+
          kingRight(4)+rookRight(0)+rookRight(7)+kingRight(60)+rookRight(56)+rookRight(63)+'|'+
          mapState(G.blocks)+'|'+mapState(G.shields)+'|'+mapState(G.traps)+'|'+mapState(G.pits);
      };
      variantPositionKey.__lunoReleaseVariantState=true;
      window.positionKey=variantPositionKey;
    }
  }

  function installOnlineActionHardening(){
    function integerSquare(value){return Number.isInteger(value)&&value>=0&&value<64;}
    function rememberBounded(map,key,limit,keep){
      map[key]=Date.now();
      var keys=Object.keys(map);
      if(keys.length<=limit)return;
      keys.sort(function(a,b){return map[a]-map[b];});
      for(var i=0;i<keys.length-keep;i++)delete map[keys[i]];
    }
    function remoteTargetValid(key,idx,color,act){
      var card=window.CARDS&&CARDS[key];
      if(!card||!window.G||!G.board)return false;
      var enemy=color==='W'?'B':'W',piece=integerSquare(idx)?G.board[idx]:null;
      if(card.target==='none')return idx==null||idx===-1;
      if(!integerSquare(idx))return false;
      var ok=false;
      switch(card.target){
        case'enemy':ok=!!(piece&&piece.c===enemy&&piece.t!=='K'&&!(piece.resist>0));break;
        case'enemy_queen':ok=!!(piece&&piece.c===enemy&&piece.t==='Q'&&!(piece.resist>0));break;
        case'own_pawn':ok=!!(piece&&piece.c===color&&piece.t==='P'&&!piece.ghost);break;
        case'own_pawn_pair':ok=!!(piece&&piece.c===color&&piece.t==='P'&&!piece.ghost&&piece.linkTo==null);break;
        case'own_knight':ok=!!(piece&&piece.c===color&&piece.t==='N');break;
        case'own_bishop':ok=!!(piece&&piece.c===color&&piece.t==='B');break;
        case'own_kn_bi':ok=!!(piece&&piece.c===color&&(piece.t==='N'||piece.t==='B'));break;
        case'own_queen':ok=!!(piece&&piece.c===color&&piece.t==='Q');break;
        case'own_piece':ok=!!(piece&&piece.c===color&&piece.t!=='K');break;
        case'empty':
          ok=!piece&&!(G.blocks&&G.blocks[idx]>0)&&!(G.shields&&G.shields[idx])&&!(G.traps&&G.traps[idx]);
          break;
        case'empty_own':
          ok=!piece&&!(G.blocks&&G.blocks[idx]>0)&&!(G.shields&&G.shields[idx])&&!(G.traps&&G.traps[idx])&&
            (color==='W'?idx<32:idx>=32);
          break;
        case'any_sq':ok=!piece;break;
      }
      if(!ok)return false;
      if(key==='archer'&&typeof window.archerTargets==='function'&&!archerTargets(idx,color).length)return false;
      if(key==='glue'){
        var a=act&&act.glueA,b=act&&act.glueB;
        if(!integerSquare(a)||!integerSquare(b)||a===b)return false;
        var pa=G.board[a],pb=G.board[b];
        if(!pa||!pb||pa.c!==color||pb.c!==color||pa.t!=='P'||pb.t!=='P')return false;
        if(pa.ghost||pb.ghost||pa.linkTo!=null||pb.linkTo!=null)return false;
        if(((a/8)|0)!==((b/8)|0)||Math.abs((a%8)-(b%8))!==1)return false;
      }
      return true;
    }

    if(typeof window.sendActionToServer==='function'&&!window.sendActionToServer.__lunoReleaseActionId){
      var originalSendAction=window.sendActionToServer;
      var safeSendAction=function(payload){
        if(!payload||typeof payload!=='object')return;
        var room=(window.ONLINE&&ONLINE.roomCode)||'room';
        if(ONLINE._actionRoom!==room){
          ONLINE._actionRoom=room;
          ONLINE._actionSeq=0;
          try{
            var random=new Uint32Array(2);crypto.getRandomValues(random);
            ONLINE._actionSession=random[0].toString(36)+random[1].toString(36);
          }catch(e){ONLINE._actionSession=Date.now().toString(36)+Math.random().toString(36).slice(2,8);}
        }
        var action=Object.assign({},payload);
        action.matchId=room;
        action.seq=++ONLINE._actionSeq;
        action.actionId=[room,ONLINE.myColor||'X',ONLINE._actionSession,action.seq].join(':');
        return originalSendAction.call(this,action);
      };
      safeSendAction.__lunoReleaseActionId=true;
      window.sendActionToServer=safeSendAction;
    }

    /* Firebase child_added normally replays the entire queue and the legacy
       listener tried to filter that replay with the sender's wall clock. A
       forged far-future timestamp could therefore suppress every later move.
       Listen from a freshly generated Firebase push key instead: ordering is
       based on queue keys, while action validation and dedup stay independent
       from untrusted client clocks. */
    if(typeof window.listenForOpponentActions==='function'&&!window.listenForOpponentActions.__lunoReleaseQueueKey){
      var safeListenForOpponentActions=function(){
        if(!window.ONLINE||!ONLINE.roomRef)return;
        var room=ONLINE.roomCode||'';
        if(ONLINE._receiveRoom!==room){
          ONLINE._receiveRoom=room;
          ONLINE._seenRemotePushKeys={};
          ONLINE._seenActionIds={};
        }

        var actsRef=ONLINE.roomRef.child('acts');
        var startKey='';
        try{
          var pending=actsRef.push();
          startKey=pending&&pending.key||'';
        }catch(e){}
        var actionQuery=actsRef;
        try{
          if(startKey&&actsRef.orderByKey)actionQuery=actsRef.orderByKey().startAt(startKey);
        }catch(e){actionQuery=actsRef;}
        var actionListener=actionQuery.on('child_added',function(snap){
          var act=snap&&snap.val?snap.val():null;
          var pushKey=snap&&snap.key!=null?String(snap.key):'';
          if(!act||typeof act!=='object'||act.by===ONLINE.myColor)return;
          if(ONLINE.myColor&&act.by!==(ONLINE.myColor==='W'?'B':'W'))return;
          if(act.matchId&&room&&act.matchId!==room)return;
          if(!ONLINE._seenRemotePushKeys)ONLINE._seenRemotePushKeys={};
          var queueId=pushKey||String(act.actionId||'');
          if(!queueId||ONLINE._seenRemotePushKeys[queueId])return;
          rememberBounded(ONLINE._seenRemotePushKeys,queueId,512,384);
          var safeAct=Object.assign({},act);
          if(!safeAct.matchId)safeAct.matchId=room;
          if(!safeAct.actionId)safeAct.actionId='firebase:'+room+':'+queueId;
          applyOpponentAction(safeAct);
        });
        ONLINE.listeners.push({ref:actionQuery,event:'child_added',fn:actionListener});

        var disconnectRef=ONLINE.roomRef.child('disconnect');
        var disconnectListener=disconnectRef.on('value',function(snap){
          var data=snap&&snap.val?snap.val():null;
          if(data&&data.by!==ONLINE.myColor&&window.G&&!(G.over||G._endTriggered)){
            try{if(typeof window.toast==='function')toast('Rakip bağlantıyı kesti. Maçı kazandın!','neon');}catch(e){}
            setTimeout(function(){
              if(!window.G||G.over||G._endTriggered)return;
              G.over=true;
              if(typeof window.endGame==='function')endGame(true,'Rakip bağlantıyı kesti');
            },1500);
          }
        });
        ONLINE.listeners.push({ref:disconnectRef,event:'value',fn:disconnectListener});

        var resultRef=ONLINE.roomRef.child('result');
        var resultListener=resultRef.on('value',function(snap){
          var result=snap&&snap.val?snap.val():null;
          if(!result||['W','B','draw'].indexOf(result.winner)<0)return;
          if(!window.G||G._endTriggered)return;
          var reason=typeof result.reason==='string'?result.reason.slice(0,80):'Sonuç';
          if(result.winner==='draw'){
            if(typeof window.endGame==='function')endGame(null,reason||'Beraberlik');
            return;
          }
          if(typeof window.endGameAbs==='function')endGameAbs(result.winner==='W',reason||'Sonuç');
        });
        ONLINE.listeners.push({ref:resultRef,event:'value',fn:resultListener});
      };
      safeListenForOpponentActions.__lunoReleaseQueueKey=true;
      window.listenForOpponentActions=safeListenForOpponentActions;
    }

    if(typeof window.applyOpponentCard==='function'&&!window.applyOpponentCard.__lunoReleaseValidated){
      var validatedOpponentCard=function(act){
        if(!act||!window.G||G.over||G.turn!==act.by||G.phase!=='card')return false;
        var key=act.cardKey,idx=act.target,color=act.by;
        var card=window.CARDS&&CARDS[key];
        if(!card||!(color==='W'||color==='B'))return false;
        if(window.ONLINE&&ONLINE.myColor&&color===ONLINE.myColor)return false;
        if(G.cardUsed||(G.cardBlock&&G.cardBlock[color]>0))return false;
        var cost=Number(card.mana||0),available=Number(G.mana&&G.mana[color]||0);
        if(!Number.isFinite(cost)||available<cost)return false;
        if(!remoteTargetValid(key,idx,color,act))return false;
        var applied;
        if(key==='glue'){
          G.board[act.glueA].linkTo=act.glueB;
          G.board[act.glueB].linkTo=act.glueA;
          applied=true;
        }else{
          applied=typeof window.applyCardEffect==='function'?applyCardEffect(key,idx,color):false;
        }
        if(applied===false)return false;
        G.mana[color]=Math.max(0,available-cost);
        G.cardUsed=true;
        if(!G.lastCard)G.lastCard={W:null,B:null};
        G.lastCard[color]=key;
        try{if(typeof window.sndCardByKey==='function')sndCardByKey(key);}catch(e){}
        if(!card.hidden){
          try{if(typeof window.showCardPlayAnimation==='function')showCardPlayAnimation(key,color);}catch(e){}
          try{if(typeof window.toast==='function')toast(card.glyph+' '+card.name+' (Rakip)','neon');}catch(e){}
        }
        if(!card.hidden&&integerSquare(idx))try{if(typeof window.flashFx==='function')flashFx(idx,key);}catch(e){}
        if(card.skipMove){
          try{if(typeof window.renderAll==='function')renderAll();}catch(e){}
          setTimeout(function(){if(window.G&&!G.over&&G.turn===color&&typeof window.forceEndTurn==='function')forceEndTurn();},400);
          return true;
        }
        try{if(typeof window.renderAll==='function')renderAll();}catch(e){}
        return true;
      };
      validatedOpponentCard.__lunoReleaseValidated=true;
      window.applyOpponentCard=validatedOpponentCard;
    }

    if(typeof window.applyOpponentAction==='function'&&!window.applyOpponentAction.__lunoReleaseDedup){
      var originalOpponentAction=window.applyOpponentAction;
      var safeOpponentAction=function(act){
        if(!act||typeof act!=='object'||!window.G||G.over)return false;
        if(!(act.by==='W'||act.by==='B'))return false;
        if(window.ONLINE&&ONLINE.myColor&&act.by===ONLINE.myColor)return false;
        if(act.matchId&&ONLINE.roomCode&&act.matchId!==ONLINE.roomCode)return false;
        var id=typeof act.actionId==='string'&&act.actionId.length<=180?act.actionId:
          [act.type,act.by,act.ts,act.from,act.to,act.cardKey,act.target].join(':');
        if(!ONLINE._seenActionIds)ONLINE._seenActionIds={};
        if(ONLINE._seenActionIds[id])return false;
        if(act.type==='move'){
          if(G.turn!==act.by||!integerSquare(act.from)||!integerSquare(act.to))return false;
          var moving=G.board[act.from];
          if(!moving||moving.c!==act.by)return false;
          if(G.forcePiece!=null&&G.forcePiece!==act.from)return false;
          if(typeof window.legal!=='function'||legal(G.board,act.from).indexOf(act.to)<0)return false;
          if(act.promo!=null&&['Q','R','B','N'].indexOf(act.promo)<0)return false;
          var promotion=moving.t==='P'&&(((act.to/8)|0)===0||((act.to/8)|0)===7);
          if(!promotion&&act.promo!=null)return false;
        }else if(act.type==='card'){
          var cardApplied=window.applyOpponentCard(act);
          if(cardApplied)rememberBounded(ONLINE._seenActionIds,id,512,384);
          return cardApplied;
        }else if(act.type!=='skip_card'){
          return false;
        }else if(G.turn!==act.by||G.phase!=='card'){
          return false;
        }
        rememberBounded(ONLINE._seenActionIds,id,512,384);
        return originalOpponentAction.call(this,act);
      };
      safeOpponentAction.__lunoReleaseDedup=true;
      window.applyOpponentAction=safeOpponentAction;
    }
  }

  function installFunctionPatches(){
    installEngineHardening();
    installOnlineActionHardening();
    installFirstVictoryTips();
    if(typeof window.getSkinPieces==='function'&&!window.getSkinPieces.__lunoV13Clamp){
      var originalPieces=window.getSkinPieces;
      var clamped=function(id){
        var value=Number(originalPieces.call(this,id)||0);
        var target=typeof window.getSkinTarget==='function'?Number(getSkinTarget(id)||0):0;
        return target>0?Math.min(value,target):value;
      };
      clamped.__lunoV13Clamp=true;
      window.getSkinPieces=clamped;
    }
    installResourceConfirmations();
    installFiatPurchases();
    installReleaseSettings();
  }

  function installFirstVictoryTips(){
    if(typeof window.showPostWinTips!=='function'||window.showPostWinTips.__lunoReleaseV23)return;

    window.closeLunoFirstWinTips=function(){
      var overlay=byId('tipsOv');
      if(!overlay)return;
      overlay.classList.remove('is-visible');
      document.body.classList.remove('luno-first-win-open');
      setTimeout(function(){if(overlay.parentNode)overlay.parentNode.removeChild(overlay);},220);
    };

    var polished=function(){
      try{if(localStorage.getItem('lunoTips1')==='1')return;}catch(e){}
      try{localStorage.setItem('lunoTips1','1');}catch(e){}
      if(byId('tipsOv'))return;

      var mascot=(window.LUNO_MASCOT&&LUNO_MASCOT.tm_11)||ART.resultVictory;
      var overlay=document.createElement('div');
      overlay.id='tipsOv';
      overlay.className='luno-first-win';
      overlay.setAttribute('role','dialog');
      overlay.setAttribute('aria-modal','true');
      overlay.setAttribute('aria-labelledby','lunoFirstWinTitle');
      overlay.innerHTML=
        '<div class="luno-first-win-card">'+
          '<img class="luno-first-win-hero" src="'+mascot+'" alt="">'+
          '<div class="luno-first-win-kicker">LUNO ARENA NOTU</div>'+
          '<h2 id="lunoFirstWinTitle">İLK ZAFERİN!</h2>'+
          '<p class="luno-first-win-lead">Tahtadaki ilk galibiyetin tamam. Sıradaki maç için üç kısa ipucu:</p>'+
          '<div class="luno-first-win-list">'+
            '<div class="luno-first-win-tip">'+
              '<img src="'+BASE+'guide-cards-v7.png" alt="">'+
              '<div><b>Kartlarını tanı</b><p>Dondurma rakibi durdurur, güçlendirme kartları kendi taşını büyütür. Ayrıntıları Koleksiyon’da görebilirsin.</p></div>'+
            '</div>'+
            '<div class="luno-first-win-tip">'+
              '<img src="'+BASE+'guide-level-v7.png" alt="">'+
              '<div><b>Seviyeyi akıllı seç</b><p>Yüksek seviye daha güçlüdür; düşük seviye ise daha az mana harcar. Turuna göre karar ver.</p></div>'+
            '</div>'+
            '<div class="luno-first-win-tip">'+
              '<img src="'+ART.chestRoyal+'" alt="">'+
              '<div><b>Yeni kartlar aç</b><p>Sandıklardan ve arena ilerlemesinden kart kazan. En iyi 6 kartı aktif destende birleştir.</p></div>'+
            '</div>'+
          '</div>'+
          '<button id="lunoFirstWinClose" type="button" onclick="closeLunoFirstWinTips()">'+
            '<img src="'+BASE+'match-control-continue-v12-mobile.webp" alt=""><span>DEVAM ET</span><i aria-hidden="true">›</i>'+
          '</button>'+
        '</div>';
      overlay.addEventListener('click',function(event){if(event.target===overlay)window.closeLunoFirstWinTips();});
      document.body.classList.add('luno-first-win-open');
      document.body.appendChild(overlay);
      requestAnimationFrame(function(){overlay.classList.add('is-visible');});
      setTimeout(function(){try{byId('lunoFirstWinClose').focus({preventScroll:true});}catch(e){}},260);
      try{if(typeof window.sndTrophyGain==='function')sndTrophyGain();}catch(e){}
    };
    polished.__lunoReleaseV23=true;
    window.showPostWinTips=polished;
  }

  function installPerformanceGovernor(){
    var root=document.documentElement;
    var ua=(navigator.userAgent||'').toLowerCase();
    var nativeApp=false;
    try{
      nativeApp=!!(window.Capacitor&&Capacitor.isNativePlatform&&Capacitor.isNativePlatform());
    }catch(e){}
    nativeApp=nativeApp||
      (location.protocol==='https:'&&location.hostname==='localhost')||
      ua.indexOf('; wv')>=0;
    var touch=(navigator.maxTouchPoints||0)>0;
    var compact=false;
    try{compact=!!(window.matchMedia&&matchMedia('(max-width:900px)').matches);}catch(e){}
    var constrainedMemory=!!(navigator.deviceMemory&&navigator.deviceMemory<=6);
    var constrainedCpu=!!(navigator.hardwareConcurrency&&navigator.hardwareConcurrency<=6);
    var mobilePerf=nativeApp||(touch&&(compact||constrainedMemory||constrainedCpu));

    root.classList.toggle('luno-mobile-perf',mobilePerf);
    root.classList.add('luno-v22');
    if(mobilePerf){
      if(!root.classList.contains('luno-gfx-high')&&!root.classList.contains('luno-gfx-low')){
        root.classList.add('luno-gfx-balanced');
      }
      window.lunoLowFxOn=true;
      try{
        if(window._particleInterval){
          clearInterval(window._particleInterval);
          window._particleInterval=null;
        }
      }catch(e){}
    }

    var replayWasPlaying=false;
    function syncVisibility(){
      var hidden=document.hidden;
      root.classList.toggle('luno-app-hidden',hidden);
      try{
        if(window.SFX&&SFX.ctx){
          var audioTransition=null;
          if(hidden&&SFX.ctx.state==='running')audioTransition=SFX.ctx.suspend();
          else if(!hidden&&window.SETTINGS&&SETTINGS.musicEnabled&&SFX.ctx.state==='suspended')audioTransition=SFX.ctx.resume();
          if(audioTransition&&typeof audioTransition.catch==='function')audioTransition.catch(function(){});
        }
      }catch(e){}
      try{
        if(hidden&&window.ONLINE){
          if(ONLINE.presenceInterval){clearInterval(ONLINE.presenceInterval);ONLINE.presenceInterval=null;}
          if(ONLINE.friendsCheckInterval){clearInterval(ONLINE.friendsCheckInterval);ONLINE.friendsCheckInterval=null;}
        }else if(!hidden&&window.ONLINE&&ONLINE.myPlayerId&&typeof window.startPresenceSystem==='function'){
          startPresenceSystem();
        }
      }catch(e){}
      try{
        if(hidden&&window.REPLAY&&REPLAY.playing){replayWasPlaying=true;replayStop();}
        else if(!hidden&&replayWasPlaying&&window.REPLAY&&REPLAY.active){replayWasPlaying=false;replayPlay();}
      }catch(e){replayWasPlaying=false;}
      try{
        if(hidden&&window._aiWorker){
          if(window.G&&!G.over&&G.mode==='ai'&&G.turn==='B')G._resumeAiOnVisible=true;
          _aiWorker.terminate();
          _aiWorker=null;
        }else if(!hidden&&window.G&&G._resumeAiOnVisible&&!G.over&&G.mode==='ai'&&G.turn==='B'){
          G._resumeAiOnVisible=false;
          setTimeout(function(){if(window.G&&!G.over&&G.mode==='ai'&&G.turn==='B'&&typeof window.aiTurn==='function')aiTurn();},180);
        }
      }catch(e){}
      try{
        if(hidden&&window._missionTimerInt){clearInterval(_missionTimerInt);_missionTimerInt=null;}
        else if(!hidden&&byId('msTimerVal')&&typeof window.startMissionTimer==='function')startMissionTimer();
      }catch(e){}
    }
    syncVisibility();
    document.addEventListener('visibilitychange',syncVisibility,{passive:true});
  }

  function polishDynamic(){
    polishUsername();
    polishOnboarding();
    polishTutorial();
    polishMatchmaking();
    polishLocalPass();
    polishReconnect();
    polishScreenBackdrops();
    polishUtilityArt();
    polishMatchModeToast();
    polishMatchHistory();
    polishReplay();
    polishAchievements();
    polishPromotion();
    polishArenaPromotion();
    polishNotifications();
    polishAvatars();
    polishProfileLeague();
    polishRankingArt();
    polishLegacyTypography();
    repairMenu();
  }

  function boot(){
    document.documentElement.classList.add('luno-release-v13');
    try{if(typeof window.lunoBuildLabel==='function')window.LUNO_BUILD=lunoBuildLabel(false);}catch(e){}
    installPerformanceGovernor();
    ensureStyles();
    installFeatureRows();
    rebuildAuth();
    installNavigationMotion();
    installFunctionPatches();
    polishDynamic();

    var observer=new MutationObserver(function(records){
      var useful=false;
      for(var i=0;i<records.length;i++){
        if(records[i].addedNodes&&records[i].addedNodes.length){useful=true;break;}
      }
      if(!useful)return;
      schedulePolishDynamic(0);
    });
    /* Overlay content has its own observer. Watching the full battle subtree
       made every board redraw re-scan the entire interface on mobile. */
    observer.observe(document.body,{childList:true});

    [240,900].forEach(function(delay){
      setTimeout(function(){
        ensureStyles();
        installFeatureRows();
        installNavigationMotion();
        installFunctionPatches();
        schedulePolishDynamic(0);
      },delay);
    });
  }

  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});
  else boot();
})();
