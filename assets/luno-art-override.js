(function(){
  'use strict';

  var BASE='assets/luno-art/';
  var A={
    coin:BASE+'luno-coin.png',
    gem:BASE+'luno-gem.png',
    mana:BASE+'luno-mana.png',
    trophy:BASE+'luno-trophy.png',
    chest:BASE+'luno-chest.png',
    pack:BASE+'luno-card-pack.png',
    deck:BASE+'luno-deck.png',
    duel:BASE+'luno-duel.png',
    pass:BASE+'luno-pass-badge.png',
    chat:BASE+'luno-chat.png',
    guide:BASE+'luno-guide.png',
    profile:BASE+'screen-profile-crest.png',
    season:BASE+'screen-season-emblem.png',
    friend:BASE+'screen-friend-badge.png',
    mission:BASE+'screen-mission-star.png',
    shop:BASE+'screen-shop-bundle.png',
    album:BASE+'screen-card-album.png',
    daily:BASE+'screen-daily-chest.png',
    premium:BASE+'screen-premium-ticket.png',
    navShop:BASE+'nav-shop.png',
    navCollection:BASE+'nav-collection.png',
    navBattle:BASE+'nav-battle.png',
    navSeason:BASE+'nav-season.png',
    navProfile:BASE+'nav-profile.png',
    menuLunoIdle:BASE+'menu-luno-idle-v10-mobile.webp',
    menuLunoWave:BASE+'menu-luno-wave-v10-mobile.webp',
    menuLunoTalk:BASE+'menu-luno-talk-v10-mobile.webp',
    menuLunoPoint:BASE+'menu-luno-point-v10-mobile.webp',
    menuLunoBlink:BASE+'menu-luno-blink-v10-mobile.webp',
    collectionDeck:BASE+'collection-deck-v10-mobile.webp',
    collectionCards:BASE+'collection-cards-v10-mobile.webp',
    collectionCostumes:BASE+'collection-costumes-v10-mobile.webp',
    collectionEmojis:BASE+'collection-emojis-v10-mobile.webp',
    cardSelected:BASE+'card-selected-v10-mobile.webp',
    cardUpgrade:BASE+'card-upgrade-v10-mobile.webp',
    menuPass:BASE+'menu-action-pass-v2.png',
    menuFriends:BASE+'menu-action-friends-v2.png',
    menuMissions:BASE+'menu-action-missions-v2.png',
    menuRanking:BASE+'menu-action-ranking-v2.png',
    menuGuide:BASE+'menu-action-guide-v2.png',
    menuSettings:BASE+'menu-action-settings-v2.png',
    statusProfile:BASE+'menu-status-profile-v2.png',
    statusTrophy:BASE+'menu-status-trophy-v2.png',
    statusGold:BASE+'menu-status-gold-v2.png',
    statusGem:BASE+'menu-status-gem-v2.png',
    statusDm:BASE+'menu-status-dm-v2.png',
    statusArena:BASE+'menu-status-arena-v2.png',
    menuArenaFrame:BASE+'menu-arena-frame-v3.png',
    menuArenaCrest:BASE+'menu-arena-crest-v9.png',
    shopPremium:BASE+'shop-premium-v3.png',
    shopDaily:BASE+'shop-daily-v3.png',
    shopStarter:BASE+'shop-starter-v3.png',
    shopExpert:BASE+'shop-expert-v3.png',
    shopChestCommon:BASE+'shop-chest-common-v3.png',
    shopChestRare:BASE+'shop-chest-rare-v3.png',
    shopChestLegendary:BASE+'shop-chest-legendary-v3.png',
    shopChestRoyal:BASE+'shop-chest-royal-v3.png',
    shopGoldSmall:BASE+'shop-gold-small-v3.png',
    shopGoldMedium:BASE+'shop-gold-medium-v3.png',
    shopGoldLarge:BASE+'shop-gold-large-v3.png',
    shopGemSmall:BASE+'shop-gem-small-v3.png',
    shopGemMedium:BASE+'shop-gem-medium-v3.png',
    shopGemLarge:BASE+'shop-gem-large-v3.png',
    passSeason:BASE+'pass-season-v5.png',
    passMissions:BASE+'pass-missions-v5.png',
    passPremium:BASE+'pass-premium-v5.png',
    passTrackFree:BASE+'pass-track-free-v5.png',
    passTrackPremium:BASE+'pass-track-premium-v5.png',
    passLevelFrame:BASE+'pass-level-frame-v5.png',
    friendsTab:BASE+'friends-tab-v6.png',
    friendsRequestsTab:BASE+'friends-requests-tab-v6.png',
    friendsRankingTab:BASE+'friends-ranking-tab-v6.png',
    friendsSearch:BASE+'friends-search-v6.png',
    friendsEmpty:BASE+'friends-empty-v6.png',
    friendsRequestsEmpty:BASE+'friends-requests-empty-v6.png',
    friendsActionMessage:BASE+'friends-action-message-v6.png',
    friendsActionBattle:BASE+'friends-action-battle-v6.png',
    friendsActionRemove:BASE+'friends-action-remove-v6.png',
    friendsActionAccept:BASE+'friends-action-accept-v6.png',
    friendsActionReject:BASE+'friends-action-reject-v6.png',
    friendsActionAdd:BASE+'friends-action-add-v6.png',
    missionsHero:BASE+'missions-hero-v6.png',
    missionsDailyTab:BASE+'missions-daily-tab-v6.png',
    missionsWeeklyTab:BASE+'missions-weekly-tab-v6.png',
    missionsSpecialTab:BASE+'missions-special-tab-v6.png',
    rankingBackdrop:BASE+'ranking-podium-backdrop-v9.jpg',
    rankingPodiumSilver:BASE+'ranking-podium-silver-v7.png',
    rankingPodiumGold:BASE+'ranking-podium-gold-v7.png',
    rankingPodiumBronze:BASE+'ranking-podium-bronze-v7.png',
    rankingStarSilver:BASE+'ranking-star-silver-v7.png',
    rankingStarGold:BASE+'ranking-star-gold-v7.png',
    rankingStarBronze:BASE+'ranking-star-bronze-v7.png',
    rankingCrown:BASE+'ranking-luno-crown-v7.png',
    settingsLanguageTr:BASE+'settings-language-tr-v8.png',
    settingsLanguageEn:BASE+'settings-language-en-v8.png',
    settingsSound:BASE+'settings-sound-v8.png',
    settingsMusic:BASE+'settings-music-v8.png',
    settingsVibration:BASE+'settings-vibration-v8.png',
    settingsAnimation:BASE+'settings-animation-v8.png',
    settingsGame:BASE+'settings-game-v8.png',
    settingsHints:BASE+'settings-hints-v8.png',
    settingsNotification:BASE+'settings-notification-v9.png',
    settingsFriendsDm:BASE+'settings-friends-dm-v9.png',
    settingsGuide:BASE+'settings-guide-v9.png',
    settingsEdit:BASE+'settings-edit-v9.png',
    settingsSignout:BASE+'settings-signout-v8.png',
    settingsInstagram:BASE+'settings-instagram-v8.png',
    settingsTiktok:BASE+'settings-tiktok-v8.png',
    settingsAbout:BASE+'settings-about-v8.png',
    passMissionStar:BASE+'pass-mission-star-v8.png',
    passMissionDaily:BASE+'pass-mission-daily-v8.png',
    passMissionWeekly:BASE+'pass-mission-weekly-v8.png',
    passMissionSpecial:BASE+'pass-mission-special-v8.png',
    passMissionLogin:BASE+'pass-mission-login-v8.png',
    passMissionPlay:BASE+'pass-mission-play-v8.png',
    passMissionWin:BASE+'pass-mission-win-v8.png',
    passMissionRanked:BASE+'pass-mission-ranked-v8.png',
    passMissionCard:BASE+'pass-mission-card-v8.png',
    passMissionLegendary:BASE+'pass-mission-legendary-v8.png',
    passMissionCapture:BASE+'pass-mission-capture-v8.png',
    passMissionStreak:BASE+'pass-mission-streak-v8.png',
    passMissionQuick:BASE+'pass-mission-quick-v8.png',
    passMissionInstagram:BASE+'pass-mission-instagram-v8.png',
    passMissionTiktok:BASE+'pass-mission-tiktok-v8.png',
    passMissionYoutube:BASE+'pass-mission-youtube-v8.png',
    guidePurpose:BASE+'guide-purpose-v7.png',
    guideTurn:BASE+'guide-turn-v7.png',
    guidePieces:BASE+'guide-pieces-v7.png',
    guideMana:BASE+'guide-mana-v7.png',
    guideCards:BASE+'guide-cards-v7.png',
    guideLevel:BASE+'guide-level-v7.png',
    guideDeck:BASE+'guide-deck-v7.png',
    guideBattle:BASE+'guide-battle-v7.png',
    guideSeason:BASE+'guide-season-v7.png',
    guideEconomy:BASE+'guide-economy-v7.png',
    guidePass:BASE+'guide-pass-v7.png',
    guideMissions:BASE+'guide-missions-v7.png',
    guideCostumes:BASE+'guide-costumes-v7.png',
    guideFriends:BASE+'guide-friends-v7.png',
    guideProfile:BASE+'guide-profile-v7.png',
    guideTips:BASE+'guide-tips-v7.png',
    profileGallery:BASE+'profile-gallery-v7.png',
    profilePhotoRemove:BASE+'profile-photo-remove-v7.png',
    profileCountry:BASE+'profile-country-v7.png',
    profileSave:BASE+'profile-save-v7.png',
    profileTrophy:BASE+'profile-stat-trophy-v4.png',
    profileWins:BASE+'profile-stat-wins-v4.png',
    profileRate:BASE+'profile-stat-rate-v4.png',
    profileStreak:BASE+'profile-stat-streak-v4.png',
    profileAbout:BASE+'profile-about-v4.png',
    profileMatchStats:BASE+'profile-match-stats-v4.png',
    profileLoginStreak:BASE+'profile-login-streak-v4.png',
    profilePass:BASE+'profile-pass-v4.png',
    profileCountryTR:BASE+'profile-country-tr-v4.png',
    profileJoinDate:BASE+'profile-join-date-v4.png',
    profileCollection:BASE+'profile-collection-v4.png',
    profileAchievements:BASE+'profile-achievements-v4.png',
    profileHistory:BASE+'profile-history-v4.png',
    profileSignout:BASE+'profile-signout-v4.png',
    resultVictory:BASE+'result-victory.png',
    resultDefeat:BASE+'result-defeat.png',
    resultDraw:BASE+'result-draw.png'
  };

  A.achievements={
    first_win:BASE+'achievement-first-win-v4.png',
    first_card:BASE+'achievement-first-card-v4.png',
    win_10:BASE+'achievement-win-10-v4.png',
    win_50:BASE+'achievement-win-50-v4.png',
    win_100:BASE+'achievement-win-100-v4.png',
    win_500:BASE+'achievement-win-500-v4.png',
    streak_3:BASE+'achievement-streak-3-v4.png',
    streak_5:BASE+'achievement-streak-5-v4.png',
    streak_10:BASE+'achievement-streak-10-v4.png',
    arena_3:BASE+'achievement-arena-3-v4.png',
    arena_5:BASE+'achievement-arena-5-v4.png',
    arena_7:BASE+'achievement-arena-7-v4.png',
    arena_8:BASE+'achievement-arena-8-v4.png',
    arena_9:BASE+'achievement-arena-9-v4.png',
    cards_100:BASE+'achievement-cards-100-v4.png',
    cards_500:BASE+'achievement-cards-500-v4.png',
    skin_3:BASE+'achievement-skin-3-v4.png',
    skin_all:BASE+'achievement-skin-all-v4.png',
    friends_5:BASE+'achievement-friends-5-v4.png',
    chests_10:BASE+'achievement-chests-10-v4.png',
    games_50:BASE+'achievement-games-50-v4.png',
    games_200:BASE+'achievement-games-200-v4.png',
    login_7:BASE+'achievement-login-7-v4.png',
    login_30:BASE+'achievement-login-30-v4.png',
    level_10:BASE+'achievement-level-10-v4.png',
    level_25:BASE+'achievement-level-25-v4.png',
    daily_7:BASE+'achievement-daily-7-v4.png',
    premium_member:BASE+'achievement-premium-member-v4.png',
    premium_30:BASE+'achievement-premium-30-v4.png'
  };

  A.avatarIcons={
    av_pawn:BASE+'avatar-pawn-v9.png',
    av_knight:BASE+'avatar-knight-v9.png',
    av_bishop:BASE+'avatar-bishop-v9.png',
    av_rook:BASE+'avatar-rook-v9.png',
    av_queen:BASE+'avatar-queen-v9.png',
    av_king:BASE+'avatar-king-v9.png',
    av_robot:BASE+'avatar-robot-v9.png',
    av_robotcrown:BASE+'avatar-robot-king-v9.png',
    av_crown:BASE+'avatar-crown-v9.png',
    av_lightning:BASE+'avatar-lightning-v9.png',
    av_fire:BASE+'avatar-fire-v9.png'
  };

  A.levelTiers=Array.from({length:10},function(_,index){
    return BASE+'level-tier-'+String(index+1).padStart(2,'0')+'-v9.png';
  });

  A.missionTasks={
    d1:BASE+'mission-d1-v6.png',d2:BASE+'mission-d2-v6.png',d3:BASE+'mission-d3-v6.png',d4:BASE+'mission-d4-v6.png',
    d_cap:BASE+'mission-d-cap-v6.png',dc_freeze:BASE+'mission-dc-freeze-v6.png',dc_barb:BASE+'mission-dc-barb-v6.png',
    dc_pois:BASE+'mission-dc-pois-v6.png',dc_block:BASE+'mission-dc-block-v6.png',dc_glue:BASE+'mission-dc-glue-v6.png',
    dc_angry:BASE+'mission-dc-angry-v6.png',dc_arch:BASE+'mission-dc-arch-v6.png',dc_trapf:BASE+'mission-dc-trapf-v6.png',
    dc_radarf:BASE+'mission-dc-radarf-v6.png',dc_resf:BASE+'mission-dc-resf-v6.png',dc_shf:BASE+'mission-dc-shf-v6.png',
    dc_fog:BASE+'mission-dc-fog-v6.png',w1:BASE+'mission-w1-v6.png',w2:BASE+'mission-w2-v6.png',
    w3:BASE+'mission-w3-v6.png',w4:BASE+'mission-w4-v6.png',wc_freeze:BASE+'mission-wc-freeze-v6.png',
    wc_barb:BASE+'mission-wc-barb-v6.png',wc_trapf:BASE+'mission-wc-trapf-v6.png',wc_deployf:BASE+'mission-wc-deployf-v6.png',
    wc_plague:BASE+'mission-wc-plague-v6.png',wc_ghost:BASE+'mission-wc-ghost-v6.png',wc_imm:BASE+'mission-wc-imm-v6.png',
    wc_med:BASE+'mission-wc-med-v6.png',s1:BASE+'mission-s1-v6.png'
  };

  window.LUNO_IMAGE2_ART=A;

  window.LUNO_ART=window.LUNO_ART||{};
  Object.assign(window.LUNO_ART,{
    coin:A.coin,
    gem:A.gem,
    trophy:A.trophy,
    chest_common:A.daily,
    chest_rare:A.chest,
    chest_epic:A.chest,
    chest_legendary:A.premium,
    chest_royal:A.premium,
    ssn_sec_grid:A.pack,
    ssn_sec_banner:A.season
  });

  window.LUNO_NAV=window.LUNO_NAV||{};
  Object.assign(window.LUNO_NAV,{
    pass:A.pass,
    shop:A.navShop,
    collection:A.navCollection,
    battle:A.navBattle,
    season:A.navSeason,
    profile:A.navProfile,
    friends:A.friend,
    missions:A.mission,
    ranking:A.trophy,
    guide:A.guide,
    chat:A.chat,
    cur_gold:A.coin,
    cur_gem:A.gem,
    cur_trophy:A.trophy,
    cur_mana:A.mana
  });

  window.LUNO_UI=window.LUNO_UI||{};
  Object.assign(window.LUNO_UI,{
    coll_deste:A.collectionDeck,
    coll_cards:A.collectionCards,
    coll_costume:A.collectionCostumes,
    coll_emoji:A.collectionEmojis,
    miss_special:A.mission,
    ps_kupa:A.trophy,
    ps_galibiyet:A.duel,
    ps_oran:BASE+'luno-board-token.png',
    shop_bundle:A.shop,
    premium_ticket:A.premium,
    season_emblem:A.season
  });

  function setCardArt(){
    window.CARD_IMG=window.CARD_IMG||{};
    Object.assign(window.CARD_IMG,{
      trap1:BASE+'card-trap1-v10-mobile.webp',
      trap2:BASE+'card-trap2-v10-mobile.webp',
      trap3:BASE+'card-trap3-v10-mobile.webp',
      radar1:BASE+'card-radar1-v10-mobile.webp',
      radar2:BASE+'card-radar2-v10-mobile.webp',
      radar3:BASE+'card-radar3-v10-mobile.webp',
      resist1:BASE+'card-resist1-v10-mobile.webp',
      resist2:BASE+'card-resist2-v10-mobile.webp',
      resist3:BASE+'card-resist3-v10-mobile.webp',
      deploy1:BASE+'card-deploy1-v10-mobile.webp',
      deploy2:BASE+'card-deploy2-v10-mobile.webp',
      deploy3:BASE+'card-deploy3-v10-mobile.webp',
      shield1:BASE+'card-shield1-v10-mobile.webp',
      shield2:BASE+'card-shield2-v10-mobile.webp',
      shield3:BASE+'card-shield3-v10-mobile.webp',
      freeze:BASE+'card-freeze-v10-mobile.webp',
      poison_q:BASE+'card-poison_q-v10-mobile.webp',
      card_block:BASE+'card-card_block-v10-mobile.webp',
      medium:BASE+'card-medium-v10-mobile.webp',
      barbarian:BASE+'card-barbarian-v10-mobile.webp',
      glue:BASE+'card-glue-v10-mobile.webp',
      archer:BASE+'card-archer-v10-mobile.webp',
      fog:BASE+'card-fog-v10-mobile.webp',
      angry_n:BASE+'card-angry_n-v10-mobile.webp',
      angry_b:BASE+'card-angry_b-v10-mobile.webp',
      plague:BASE+'card-plague-v10-mobile.webp',
      reinforce:BASE+'card-reinforce-v10-mobile.webp',
      ghosts:BASE+'card-ghosts-v10-mobile.webp',
      immunity:BASE+'card-immunity-v10-mobile.webp'
    });
    if(window.CARDS){
      if(CARDS.deploy2)CARDS.deploy2.name='Gelişmiş Fil Seferi';
      if(CARDS.deploy3)CARDS.deploy3.name='Gelişmiş At Seferi';
    }
    if(window._poolHTMLCache)window._poolHTMLCache.sig=null;
  }

  function setEmojiArt(){
    if(!Array.isArray(window.EMOJI_LIST))return;
    var map={
      smile:BASE+'emoji-smile.png',
      heart:BASE+'emoji-heart.png',
      laugh:BASE+'emoji-laugh.png',
      cry:BASE+'emoji-cry.png',
      angry:BASE+'emoji-angry.png',
      think:BASE+'emoji-wow.png',
      fire:BASE+'streak-flame.png',
      star:BASE+'result-levelup.png',
      thunder:BASE+'result-arena.png',
      bomb:BASE+'emoji-oops.png',
      strat:BASE+'tutorial-guide-mini.png',
      trophy:BASE+'emoji-trophy.png',
      crown:BASE+'result-victory.png',
      rainbow:BASE+'result-draw.png'
    };
    window.EMOJI_LIST.forEach(function(e){
      if(!e||!map[e.id])return;
      e.img=map[e.id];
      e.icon='<img class="cb-eimg" src="'+map[e.id]+'" alt="">';
    });
  }

  var V11_SET_ORDER=['ottoman','roma','brit','viking','tasdevri','samuray','ice','dragon','neon'];
  var V11_PIECE_NAMES={K:'king',Q:'queen',R:'rook',B:'bishop',N:'knight',P:'pawn'};
  var V22_DEFAULT_META={
    id:'luno',
    name:'Luno \u0130mza',
    label:'RESM\u0130 ARENA TAKIMI',
    note:'\u0130nci seramik, turkuaz mine ve arena alt\u0131n\u0131',
    rarity:'STANDART',
    currency:'gold',
    price:0,
    accent:'#f2c75d',
    deep:'#151a3a',
    mid:'#227a78'
  };
  var V11_SET_META={
    ottoman:{name:'Osmanl\u0131',label:'SARAY PORSELEN\u0130',note:'\u0130znik dokusu ve saray alt\u0131n\u0131',rarity:'NAD\u0130R',currency:'gold',price:1000,accent:'#f2c75d',deep:'#4e1d32',mid:'#12515b'},
    roma:{name:'Roma',label:'MERMER LEJYONU',note:'Carrara mermeri ve bronz i\u015f\u00e7ilik',rarity:'NAD\u0130R',currency:'gem',price:480,accent:'#d8b477',deep:'#3d3430',mid:'#676152'},
    brit:{name:'Britanya',label:'TA\u00c7 MUHAFIZLARI',note:'Lacivert porselen ve Tudor g\u00fcl\u00fc',rarity:'NAD\u0130R',currency:'gem',price:480,accent:'#efc9b3',deep:'#142d51',mid:'#653246'},
    viking:{name:'Viking',label:'KUZEY OYMASI',note:'Dumanl\u0131 me\u015fe ve d\u00f6vme demir',rarity:'NAD\u0130R',currency:'gem',price:480,accent:'#c9d0c8',deep:'#27333b',mid:'#684b34'},
    tasdevri:{name:'Ta\u015f Devri',label:'\u0130LK USTALAR',note:'Kire\u00e7ta\u015f\u0131, \u00e7akmakta\u015f\u0131 ve obsidyen',rarity:'NAD\u0130R',currency:'gem',price:480,accent:'#d9b879',deep:'#3c342b',mid:'#70553a'},
    samuray:{name:'Samuray',label:'LAKE SARAYI',note:'Kabuto hatlar\u0131 ve k\u0131rm\u0131z\u0131 lake',rarity:'NAD\u0130R',currency:'gem',price:480,accent:'#efc766',deep:'#351820',mid:'#74252c'},
    ice:{name:'Buz Krall\u0131\u011f\u0131',label:'DONMU\u015e SARAY',note:'Buzlu porselen ve safir g\u00f6lgeler',rarity:'EFSANEV\u0130',currency:'gem',price:720,accent:'#bdefff',deep:'#153b54',mid:'#2d5f88'},
    dragon:{name:'Ejderha',label:'KIZIL PEN\u00c7E',note:'Fildi\u015fi pullar ve bak\u0131r boynuzlar',rarity:'EFSANEV\u0130',currency:'gem',price:720,accent:'#f0b66b',deep:'#3d1720',mid:'#742b27'},
    neon:{name:'Neon Krall\u0131k',label:'GECE DEVRES\u0130',note:'Grafit seramik ve kontroll\u00fc neon',rarity:'M\u0130T\u0130K',currency:'gem',price:980,accent:'#66f0df',deep:'#102f3a',mid:'#482557'}
  };

  function v11PieceSource(setId,color,code){
    var piece=V11_PIECE_NAMES[code];
    return piece?BASE+'piece-'+setId+'-'+color.toLowerCase()+'-'+piece+'-v11-mobile.webp':'';
  }

  function v22DefaultPieceSource(color,code){
    var piece=V11_PIECE_NAMES[code];
    return piece?BASE+'piece-luno-'+color.toLowerCase()+'-'+piece+'-v22-mobile.webp':'';
  }

  function setV11PieceSets(){
    if(!window.PIECE_IMG)return;
    var luno={W:{},B:{}};
    Object.keys(V11_PIECE_NAMES).forEach(function(code){
      luno.W[code]=v22DefaultPieceSource('w',code);
      luno.B[code]=v22DefaultPieceSource('b',code);
    });
    window.PIECE_IMG.luno=luno;
    window.PIECE_IMG.std=luno;
    V11_SET_ORDER.forEach(function(setId){
      var set={W:{},B:{}};
      Object.keys(V11_PIECE_NAMES).forEach(function(code){
        set.W[code]=v11PieceSource(setId,'w',code);
        set.B[code]=v11PieceSource(setId,'b',code);
      });
      window.PIECE_IMG[setId]=set;
    });
    if(!document.getElementById('lunoPieceV11Scale')){
      var scaleStyle=document.createElement('style');
      scaleStyle.id='lunoPieceV11Scale';
      scaleStyle.textContent='.pc-img,.pc-i-R,.pc-i-B,.pc-i-N,.pc-i-P{transform:none!important;}';
      document.head.appendChild(scaleStyle);
    }
  }

  function setOttomanPieces(){setV11PieceSets();}

  function prepareImage(image,eager){
    if(!image)return;
    image.decoding='async';
    image.loading=eager?'eager':'lazy';
    try{image.fetchPriority=eager?'high':'low';}catch(e){}
  }

  function imageShouldBeEager(node){
    var screen=node&&node.closest?node.closest('.screen'):null;
    return !!(screen&&screen.classList.contains('active'));
  }

  function setImage(selector,src){
    var el=document.querySelector(selector);
    if(el&&el.tagName==='IMG'){
      prepareImage(el,imageShouldBeEager(el));
      el.src=src;
    }
  }

  function ensureImage(hostSelector,imageSelector,src,className){
    var host=document.querySelector(hostSelector);
    if(!host)return;
    var image=host.querySelector(imageSelector);
    if(!image){
      var oldIcon=host.querySelector('svg');
      if(oldIcon)oldIcon.remove();
      image=document.createElement('img');
      image.className=className;
      image.alt='';
      host.insertBefore(image,host.firstChild);
    }
    prepareImage(image,imageShouldBeEager(host));
    image.src=src;
  }

  function applyStaticSlots(){
    var nav={
      nvMagaza:A.navShop,
      nvKoleksiyon:A.navCollection,
      nvSavas:A.navBattle,
      nvSezon:A.navSeason,
      nvProfil:A.navProfile
    };
    Object.keys(nav).forEach(function(id){
      setImage('#'+id+' .luno-navimg',nav[id]);
    });
    setImage('.lp-icon .luno-passimg',A.pass);
    setImage('.cur-gold .luno-curimg',A.coin);
    setImage('.cur-gem .luno-curimg',A.gem);
    setImage('.cur-trophy .luno-curimg',A.trophy);
  }

  function applyMainMenuArt(){
    var mascot=document.getElementById('mnLunoImg');
    var live=document.getElementById('mnLunoLive');
    if(mascot){
      prepareImage(mascot,imageShouldBeEager(mascot));
      mascot.src=A.menuLunoIdle;
      mascot.alt='Luno';
      mascot.dataset.menuPose='idle';
    }
    if(live){
      live.setAttribute('aria-label','Luno ile konuş');
      live.classList.add('is-luno-v10');
    }
    var bubble=document.getElementById('mnLunoBubble');
    if(bubble)bubble.setAttribute('data-speaker','LUNO');

    var pass=document.getElementById('lunoPassBtn');
    if(pass)pass.setAttribute('data-label','LUNO PASS');
    ensureImage('.mn-luno-pass .lp-icon','.luno-passimg',A.menuPass,'luno-passimg');

    var quick={
      '.mn-qbtn-friends':A.menuFriends,
      '#qbGorevler':A.menuMissions,
      '#qbSiralama':A.menuRanking,
      '#qbRehber':A.menuGuide,
      '.mn-qbtn-settings':A.menuSettings
    };
    Object.keys(quick).forEach(function(selector){
      ensureImage(selector,'.luno-qbimg',quick[selector],'luno-qbimg');
    });

    ensureImage('.cur-trophy .cur-ic','.luno-curimg',A.statusTrophy,'luno-curimg');
    ensureImage('.cur-gold .cur-ic','.luno-curimg',A.statusGold,'luno-curimg');
    ensureImage('.cur-gem .cur-ic','.luno-curimg',A.statusGem,'luno-curimg');
    ensureImage('#dmInboxBtn','.luno-chatimg',A.statusDm,'luno-chatimg');
    enhanceArenaBar();
    var arenaSeasonSlot=document.querySelector('.mn-arena-pill .ap-crown');
    if(arenaSeasonSlot&&!arenaSeasonSlot.querySelector('.luno-arena-crest')){
      arenaSeasonSlot.innerHTML='<img class="luno-arena-crest" src="'+A.menuArenaCrest+'" alt="" loading="lazy" decoding="async">';
      arenaSeasonSlot.setAttribute('aria-hidden','true');
    }
    fitArenaBarText();
    applyDefaultProfileCrest();
    document.querySelectorAll('.mn-bottomnav .nv-lbl').forEach(function(label){
      label.style.setProperty('display','block','important');
      label.style.setProperty('visibility','visible','important');
      label.style.setProperty('opacity','1','important');
    });

  }

  function applyDefaultProfileCrest(){
    var icon=document.getElementById('menuAvatarIcon');
    if(!icon)return;
    var profile=window.PLAYER&&PLAYER.profile?PLAYER.profile:null;
    if(profile&&profile.photoURL)return;
    var selected=profile&&profile.avatarEmoji?profile.avatarEmoji:'';
    var isDefault=!selected||selected==='&#9818;'||selected==='&#9823;'||selected==='&#9817;';
    if(!isDefault)return;
    icon.innerHTML='<img class="luno-profile-status-icon" src="'+A.statusProfile+'" alt="" loading="lazy" decoding="async">';
  }

  function patchTopbarProfile(){
    var original=window.updateTopbarName;
    if(typeof original!=='function'||original.__lunoMenuPolish)return;
    window.updateTopbarName=function(){
      var out=original.apply(this,arguments);
      applyDefaultProfileCrest();
      return out;
    };
    window.updateTopbarName.__lunoMenuPolish=true;
  }

  function enhanceArenaBar(){
    var pill=document.querySelector('.mn-arena-pill');
    if(!pill)return;
    if(pill.classList.contains('is-enhanced')){fitArenaBarText();return;}
    var title=pill.querySelector('.ap-title');
    var progress=pill.querySelector('.ap-progress');
    var arrow=pill.querySelector('.ap-arrow');
    var fill=progress&&progress.querySelector('.ap-fill');
    var points=progress&&progress.querySelector('.ap-pts');
    if(!title||!progress||!arrow||!fill||!points)return;

    var titleText=title.textContent||'Acemi Kamp\u0131';
    var pointsText=points.textContent||'0 / 100';
    var fillWidth=fill.style.width||'0%';
    pill.innerHTML=
      '<div class="ap-crown" aria-hidden="true"><img class="luno-arena-crest" src="'+A.menuArenaCrest+'" alt="" loading="lazy" decoding="async"></div>'+ 
      '<div class="ap-main">'+
        '<div class="ap-kicker">MEVCUT ARENA</div>'+ 
        '<div class="ap-title" id="arenaName"></div>'+ 
        '<div class="ap-progress"><div class="ap-bar"><div class="ap-fill" id="arenaFill"></div></div><span class="ap-pts" id="arenaPts"></span></div>'+ 
      '</div>'+ 
      '<div class="ap-arrow" aria-hidden="true">&#10095;</div>';
    pill.querySelector('#arenaName').textContent=titleText;
    pill.querySelector('#arenaPts').textContent=pointsText;
    pill.querySelector('#arenaFill').style.width=fillWidth;
    pill.style.backgroundImage='none';
    pill.classList.add('is-enhanced');
    fitArenaBarText();
  }

  function fitArenaBarText(){
    var pill=document.querySelector('.mn-arena-pill.is-enhanced');
    if(!pill)return;
    var title=pill.querySelector('#arenaName');
    var points=pill.querySelector('#arenaPts');
    pill.classList.toggle('has-long-arena',!!title&&(title.textContent||'').trim().length>18);
    pill.classList.toggle('has-long-points',!!points&&(points.textContent||'').replace(/\s/g,'').length>12);
  }

  function patchArenaBarUpdates(){
    var original=window.refreshMenuUI;
    if(typeof original!=='function'||original.__lunoArenaV9)return;
    window.refreshMenuUI=function(){
      var result=original.apply(this,arguments);
      enhanceArenaBar();
      fitArenaBarText();
      requestAnimationFrame(fitArenaBarText);
      return result;
    };
    window.refreshMenuUI.__lunoArenaV9=true;
  }

  function shopImage(src,className,alt){
    return '<img class="'+className+'" src="'+src+'" alt="'+(alt||'')+'">';
  }

  function v11SetStyle(meta){
    return '--set-accent:'+meta.accent+';--set-deep:'+meta.deep+';--set-mid:'+meta.mid+';';
  }

  function v11SetOwned(setId){
    var owned=(window.PLAYER&&PLAYER.ownedSets)||[];
    return owned.indexOf(setId)>=0;
  }

  function v11SetAction(setId){
    return 'lunoV11ToggleSet(\''+setId+'\')';
  }

  function v11PieceImage(setId,color,code,className,eager){
    var set=window.PIECE_IMG&&window.PIECE_IMG[setId];
    var src=(set&&set[color]&&set[color][code])||v11PieceSource(setId,color,code);
    return '<img class="lps-piece '+className+'" src="'+src+'" alt="" draggable="false" decoding="async" loading="'+(eager?'eager':'lazy')+'">';
  }

  function v11SetStage(meta,variant,eager){
    return '<div class="lps-stage '+(variant||'')+'" style="'+v11SetStyle(meta)+'" aria-hidden="true">'+
      '<span class="lps-stage-sheen"></span>'+ 
      v11PieceImage(meta.id,'B','R','is-rook',eager)+
      v11PieceImage(meta.id,'W','K','is-king',eager)+
      v11PieceImage(meta.id,'B','N','is-knight',eager)+
    '</div>';
  }

  function v11SetPrice(meta,className){
    var icon=meta.currency==='gold'?A.statusGold:A.statusGem;
    return '<span class="'+(className||'lps-price')+'"><img src="'+icon+'" alt=""><b>'+meta.price.toLocaleString('tr-TR')+'</b></span>';
  }

  function v11CostumeCard(meta,index){
    var active=!!(window.PLAYER&&PLAYER.activePieceSet===meta.id);
    var owned=v11SetOwned(meta.id);
    var state=active?'G\u0130Y\u0130L\u0130':(owned?'KOLEKS\u0130YONDA':'K\u0130L\u0130TL\u0130');
    var action=active?'STANDARTA D\u00d6N':(owned?'TAKIMI G\u0130YD\u0130R':'SATIN AL');
    return '<article class="lps-card'+(active?' is-active':'')+'" data-set-id="'+meta.id+'" data-rarity="'+meta.rarity+'" style="'+v11SetStyle(meta)+'">'+
      v11SetStage(meta,'is-card',index<2)+
      '<div class="lps-card-copy">'+
        '<div class="lps-card-head"><div><span class="lps-card-label">'+meta.label+'</span><h3>'+meta.name+'</h3></div><span class="lps-rarity">'+meta.rarity+'</span></div>'+ 
        '<p class="lps-card-note">'+meta.note+'</p>'+ 
        '<div class="lps-facts"><span>12 TA\u015e</span><span>BEYAZ + S\u0130YAH</span></div>'+ 
        '<div class="lps-card-state '+(active?'is-equipped':(owned?'is-owned':'is-locked'))+'"><span>'+state+'</span>'+(active||owned?'':v11SetPrice(meta,'lps-price'))+'</div>'+ 
        '<button class="lps-action" type="button" onclick="'+v11SetAction(meta.id)+'">'+action+'</button>'+ 
      '</div>'+
    '</article>';
  }

  function v11ShopSetCard(meta,index){
    var active=!!(window.PLAYER&&PLAYER.activePieceSet===meta.id);
    var owned=v11SetOwned(meta.id);
    var state=active?'G\u0130Y\u0130L\u0130':(owned?'G\u0130YD\u0130R':'');
    return '<button class="luno-shop-set-card'+(active?' is-active':'')+'" type="button" data-set-id="'+meta.id+'" style="'+v11SetStyle(meta)+'" onclick="'+v11SetAction(meta.id)+'" aria-label="'+meta.name+' tak\u0131m\u0131">'+
      v11SetStage(meta,'is-shop',index<3)+
      '<span class="luno-shop-set-copy"><small>'+meta.rarity+'</small><b>'+meta.name+'</b></span>'+ 
      '<span class="luno-shop-set-state '+(active?'is-equipped':'')+'">'+(state?'<b>'+state+'</b>':v11SetPrice(meta,'luno-shop-set-price'))+'</span>'+ 
    '</button>';
  }

  function installPieceSetStyles(){
    if(document.getElementById('lunoPieceSetV11Styles'))return;
    var style=document.createElement('style');
    style.id='lunoPieceSetV11Styles';
    style.textContent=[
      '#ovBody .luno-set-screen,#ovBody .luno-set-screen *{box-sizing:border-box;letter-spacing:0;}',
      '#ovBody .luno-set-screen{width:100%;padding:5px 14px 28px;color:#f7f1eb;font-family:"Trebuchet MS",system-ui,sans-serif;}',
      '#ovBody .lps-hero{position:relative;display:grid;grid-template-columns:132px minmax(0,1fr);align-items:center;gap:10px;min-height:146px;margin:0 0 8px;padding:8px 11px 8px 5px;border:1px solid rgba(238,204,105,.62);border-radius:8px;background:linear-gradient(135deg,#123f4a 0%,#2a2147 53%,#562d3d 100%);box-shadow:inset 0 1px 0 rgba(255,255,255,.14),0 6px 14px rgba(5,4,19,.42);overflow:hidden;}',
      '#ovBody .lps-hero::after{content:"";position:absolute;inset:5px;border:1px solid rgba(255,255,255,.06);border-radius:6px;pointer-events:none;}',
      '#ovBody .lps-hero-copy{position:relative;z-index:2;min-width:0;}',
      '#ovBody .lps-hero-kicker{display:block;margin-bottom:4px;color:#75ded3;font-size:7.5px;line-height:10px;font-weight:900;}',
      '#ovBody .lps-hero h2{margin:0;color:#fff0c7;font-family:Cinzel,Georgia,serif;font-size:15px;line-height:19px;font-weight:900;overflow-wrap:anywhere;}',
      '#ovBody .lps-hero p{margin:5px 0 0;color:#ded4e6;font-size:9px;line-height:13px;font-weight:700;}',
      '#ovBody .lps-stage{position:relative;width:144px;height:136px;min-width:0;isolation:isolate;overflow:hidden;}',
      '#ovBody .lps-stage::before{content:"";position:absolute;left:8%;right:8%;top:9%;bottom:8%;z-index:-2;border-radius:50%;background:radial-gradient(circle at 50% 34%,rgba(255,255,255,.21),transparent 43%),linear-gradient(155deg,var(--set-mid),var(--set-deep));opacity:.72;}',
      '#ovBody .lps-stage::after{content:"";position:absolute;left:17%;right:17%;bottom:7px;height:13px;z-index:-1;border-radius:50%;background:rgba(4,5,16,.55);box-shadow:0 0 12px var(--set-accent);opacity:.62;}',
      '#ovBody .lps-stage-sheen{position:absolute;left:24%;right:24%;top:8%;height:2px;border-radius:2px;background:var(--set-accent);box-shadow:0 0 9px var(--set-accent);opacity:.62;}',
      '#ovBody .lps-piece{position:absolute;display:block;object-fit:contain;filter:drop-shadow(0 4px 4px rgba(0,0,0,.58));pointer-events:none;}',
      '#ovBody .lps-piece.is-rook{left:-1px;bottom:8px;z-index:2;width:66px;height:82px;}',
      '#ovBody .lps-piece.is-king{left:50%;bottom:5px;z-index:4;width:92px;height:116px;transform:translateX(-50%);}',
      '#ovBody .lps-piece.is-knight{right:-3px;bottom:6px;z-index:3;width:73px;height:90px;}',
      '#ovBody .lps-hero .lps-stage{width:126px;height:126px;}',
      '#ovBody .lps-summary{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));min-height:45px;margin:0 1px 10px;border-top:1px solid rgba(107,220,208,.27);border-bottom:1px solid rgba(238,204,105,.2);}',
      '#ovBody .lps-summary span{display:flex;min-width:0;flex-direction:column;align-items:center;justify-content:center;color:#aebec6;font-size:6.8px;line-height:9px;font-weight:900;text-align:center;}',
      '#ovBody .lps-summary span+span{border-left:1px solid rgba(255,255,255,.08);}',
      '#ovBody .lps-summary b{color:#ffe08a;font-family:Cinzel,Georgia,serif;font-size:10px;line-height:14px;font-weight:900;}',
      '#ovBody .lps-list{display:flex;flex-direction:column;gap:10px;}',
      '#ovBody .lps-card{position:relative;display:grid;grid-template-columns:146px minmax(0,1fr);align-items:stretch;gap:7px;min-height:176px;padding:9px 9px 9px 4px;border:1px solid color-mix(in srgb,var(--set-accent) 58%,transparent);border-radius:8px;background:linear-gradient(145deg,var(--set-deep),#17132d 58%,var(--set-mid));box-shadow:inset 0 1px 0 rgba(255,255,255,.12),0 5px 12px rgba(4,3,16,.38);overflow:hidden;}',
      '#ovBody .lps-card::after{content:"";position:absolute;inset:5px;border:1px solid rgba(255,255,255,.055);border-radius:6px;pointer-events:none;}',
      '#ovBody .lps-card.is-active{border-color:#6fe0c9;box-shadow:inset 0 1px 0 rgba(255,255,255,.15),0 0 0 1px rgba(111,224,201,.2),0 6px 14px rgba(3,14,18,.48);}',
      '#ovBody .lps-card .lps-stage{align-self:center;width:142px;height:154px;}',
      '#ovBody .lps-card-copy{position:relative;z-index:3;display:flex;min-width:0;flex-direction:column;padding:3px 0 1px;}',
      '#ovBody .lps-card-head{display:flex;min-width:0;align-items:flex-start;justify-content:space-between;gap:5px;}',
      '#ovBody .lps-card-head>div{min-width:0;}',
      '#ovBody .lps-card-label{display:block;color:var(--set-accent);font-size:6.7px;line-height:9px;font-weight:900;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}',
      '#ovBody .lps-card h3{margin:1px 0 0;color:#fff3d4;font-family:Cinzel,Georgia,serif;font-size:13px;line-height:17px;font-weight:900;overflow-wrap:anywhere;}',
      '#ovBody .lps-rarity{flex:0 0 auto;min-width:37px;padding:3px 4px;border:1px solid rgba(255,255,255,.14);border-radius:5px;background:rgba(7,10,24,.46);color:#e7dceb;font-size:6px;line-height:8px;font-weight:900;text-align:center;}',
      '#ovBody .lps-card-note{min-height:24px;margin:6px 0 4px;color:#ddd4df;font-size:8.5px;line-height:12px;font-weight:700;}',
      '#ovBody .lps-facts{display:flex;align-items:center;gap:5px;margin-bottom:5px;color:#96dcd4;font-size:6.5px;line-height:9px;font-weight:900;}',
      '#ovBody .lps-facts span+span::before{content:"";display:inline-block;width:3px;height:3px;margin:0 5px 1px 0;border-radius:50%;background:var(--set-accent);}',
      '#ovBody .lps-card-state{display:flex;height:27px;align-items:center;justify-content:space-between;gap:5px;margin-top:auto;padding:3px 6px;border:1px solid rgba(255,255,255,.1);border-radius:6px;background:rgba(8,8,23,.5);color:#bcb1c8;font-size:7px;line-height:9px;font-weight:900;}',
      '#ovBody .lps-card-state.is-equipped{border-color:rgba(111,224,201,.45);color:#83ead8;background:rgba(13,70,68,.44);}',
      '#ovBody .lps-card-state.is-owned{color:#f1d481;}',
      '#ovBody .lps-price,#ovBody .luno-shop-set-price{display:inline-flex;align-items:center;justify-content:center;gap:4px;color:#fff1c1;}',
      '#ovBody .lps-price img{width:21px;height:21px;object-fit:contain;}',
      '#ovBody .lps-price b{font-family:Cinzel,Georgia,serif;font-size:9px;line-height:12px;}',
      '#ovBody .lps-action{width:100%;height:35px;margin-top:6px;padding:0 5px;border:1px solid color-mix(in srgb,var(--set-accent) 76%,white);border-radius:7px;background:linear-gradient(180deg,var(--set-accent),#aa762b);color:#211326;font-family:"Trebuchet MS",system-ui,sans-serif;font-size:8.5px;line-height:11px;font-weight:900;box-shadow:inset 0 1px 0 rgba(255,255,255,.37),0 3px 6px rgba(0,0,0,.32);cursor:pointer;}',
      '#ovBody .lps-card.is-active .lps-action{border-color:rgba(123,235,215,.7);background:#164a4c;color:#d7fff7;}',
      '#ovBody .lps-footer-action{display:flex;width:100%;height:42px;align-items:center;justify-content:center;margin-top:12px;border:1px solid rgba(116,218,207,.38);border-radius:8px;background:#193647;color:#e9f9f4;font-family:"Trebuchet MS",system-ui,sans-serif;font-size:9px;font-weight:900;cursor:pointer;}',
      '#ovBody .shx-sec.luno-set-section{display:flex!important;align-items:center!important;gap:7px!important;}',
      '#ovBody .luno-shop-set-heading-piece{display:block!important;width:29px!important;height:29px!important;object-fit:contain!important;filter:drop-shadow(0 2px 3px rgba(0,0,0,.45))!important;}',
      '#ovBody .luno-shop-set-all{display:flex!important;height:26px!important;align-items:center!important;margin-left:auto!important;padding:0 7px!important;border:1px solid rgba(105,218,206,.38)!important;border-radius:6px!important;background:#193b49!important;color:#dff9f4!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:7px!important;line-height:9px!important;font-weight:900!important;cursor:pointer!important;}',
      '#ovBody .luno-shop-set-row{display:flex!important;gap:9px!important;overflow-x:auto!important;scroll-snap-type:x proximity!important;padding:2px 1px 9px!important;}',
      '#ovBody .luno-shop-set-card{position:relative!important;display:grid!important;grid-template-rows:105px 37px 27px!important;width:148px!important;height:179px!important;flex:0 0 148px!important;scroll-snap-align:start!important;box-sizing:border-box!important;padding:5px 7px!important;border:1px solid color-mix(in srgb,var(--set-accent) 58%,transparent)!important;border-radius:8px!important;background:linear-gradient(150deg,var(--set-deep),#16122c 60%,var(--set-mid))!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.12),0 4px 10px rgba(4,3,15,.42)!important;color:#fff!important;text-align:left!important;overflow:hidden!important;cursor:pointer!important;}',
      '#ovBody .luno-shop-set-card.is-active{border-color:#70e0ca!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.15),0 0 0 1px rgba(112,224,202,.19),0 5px 11px rgba(3,11,16,.48)!important;}',
      '#ovBody .luno-shop-set-card .lps-stage{width:132px!important;height:104px!important;}',
      '#ovBody .luno-shop-set-card .lps-piece.is-rook{width:54px!important;height:67px!important;bottom:5px!important;}',
      '#ovBody .luno-shop-set-card .lps-piece.is-king{width:76px!important;height:94px!important;bottom:2px!important;}',
      '#ovBody .luno-shop-set-card .lps-piece.is-knight{width:61px!important;height:73px!important;bottom:4px!important;}',
      '#ovBody .luno-shop-set-copy{display:flex;min-width:0;flex-direction:column;align-items:center;justify-content:center;border-top:1px solid rgba(255,255,255,.09);text-align:center;}',
      '#ovBody .luno-shop-set-copy small{color:var(--set-accent);font-family:"Trebuchet MS",system-ui,sans-serif;font-size:6px;line-height:8px;font-weight:900;}',
      '#ovBody .luno-shop-set-copy b{display:block;width:100%;color:#fff1d2;font-family:Cinzel,Georgia,serif;font-size:9.5px;line-height:13px;font-weight:900;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}',
      '#ovBody .luno-shop-set-state{display:flex;align-items:center;justify-content:center;gap:4px;border:1px solid rgba(255,255,255,.1);border-radius:6px;background:rgba(7,7,21,.56);color:#f6dfa0;font-family:"Trebuchet MS",system-ui,sans-serif;font-size:7.5px;line-height:10px;font-weight:900;}',
      '#ovBody .luno-shop-set-state.is-equipped{border-color:rgba(112,224,202,.44);background:rgba(14,70,67,.5);color:#94efdf;}',
      '#ovBody .luno-shop-set-price img{width:19px!important;height:19px!important;object-fit:contain!important;}',
      '#ovBody .luno-shop-set-price b{font-family:Cinzel,Georgia,serif;font-size:8.5px;line-height:11px;}',
      '@media(max-width:360px){#ovBody .luno-set-screen{padding-left:10px;padding-right:10px}#ovBody .lps-hero{grid-template-columns:119px minmax(0,1fr);padding-left:2px;padding-right:8px}#ovBody .lps-hero .lps-stage{width:118px}#ovBody .lps-card{grid-template-columns:136px minmax(0,1fr);gap:5px;padding-right:7px}#ovBody .lps-card .lps-stage{width:134px}#ovBody .lps-card h3{font-size:12px;line-height:16px}#ovBody .lps-card-note{font-size:8px;line-height:11px}#ovBody .lps-rarity{min-width:34px;padding-left:3px;padding-right:3px;font-size:5.6px}#ovBody .lps-action{font-size:8px}}'
    ].join('');
    document.head.appendChild(style);
  }

  function patchCostumeExperience(){
    setV11PieceSets();
    installPieceSetStyles();
    window.lunoV11ToggleSet=function(setId){
      if(setId==='ottoman'){
        if(typeof window.buyOrEquipOttoman==='function')window.buyOrEquipOttoman();
      }else if(typeof window.buyOrEquipPieceSet==='function'){
        window.buyOrEquipPieceSet(setId);
      }
      if(document.querySelector('.luno-set-screen')&&typeof window.openCostumes==='function')window.openCostumes();
    };
    if(typeof window.openCostumes!=='function'||window.openCostumes.__lunoPieceSetV11)return;
    window.openCostumes=function(){
      try{if(typeof sndUiOpen==='function')sndUiOpen();}catch(e){}
      var title=document.getElementById('ovTitle');
      var body=document.getElementById('ovBody');
      var overlay=document.getElementById('overlay');
      if(!body||!overlay)return;
      if(title)title.textContent='TA\u015e KOST\u00dcMLER\u0130';
      overlay.classList.remove('fp-imgmode');
      body.classList.add('is-luno-costumes-v11');
      var activeId=(window.PLAYER&&PLAYER.activePieceSet)||'std';
      var active=(activeId==='std'||activeId==='luno')?V22_DEFAULT_META:(V11_SET_META[activeId]||V22_DEFAULT_META);
      var activeCustom=true;
      var cards=V11_SET_ORDER.map(function(id,index){var meta=V11_SET_META[id];meta.id=id;return v11CostumeCard(meta,index);}).join('');
      active.id=active.id||activeId;
      body.innerHTML='<div class="luno-set-screen">'+
        '<section class="lps-hero" style="'+v11SetStyle(active)+'">'+
          v11SetStage(active,'is-hero',true)+
          '<div class="lps-hero-copy"><span class="lps-hero-kicker">'+(activeCustom?'AKT\u0130F TAKIM':'TA\u015e KOLEKS\u0130YONU')+'</span><h2>'+(activeCustom?active.name.toLocaleUpperCase('tr-TR')+' TAKIMI':'DOKUZ \u00c7A\u011e, TEK TAHTA')+'</h2><p>'+(activeCustom?active.note:'Her sette beyaz ve siyah i\u00e7in alt\u0131\u015far \u00f6zg\u00fcn ta\u015f.')+'</p></div>'+ 
        '</section>'+ 
        '<div class="lps-summary"><span><b>9 TAM SET</b>D\u00d6NEM KOLEKS\u0130YONU</span><span><b>108 TA\u015e</b>\u00d6ZG\u00dcN S\u0130LUET</span><span><b>2 RENK</b>BEYAZ + S\u0130YAH</span></div>'+ 
        '<div class="lps-list">'+cards+'</div>'+ 
        '<button class="lps-footer-action" type="button" onclick="openCollectionHub()">KOLEKS\u0130YONA D\u00d6N</button>'+ 
      '</div>';
      body.scrollTop=0;
      overlay.classList.add('show');
    };
    window.openCostumes.__lunoPieceSetV11=true;
  }

  function updateShopDailyBadge(){
    var nav=document.getElementById('nvMagaza');
    if(!nav)return;
    var badge=document.getElementById('shopDailyBadge');
    if(!badge){
      badge=document.createElement('span');
      badge.id='shopDailyBadge';
      badge.className='luno-shop-badge';
      badge.textContent='1';
      badge.setAttribute('aria-label','G\u00fcnl\u00fck \u00f6d\u00fcl haz\u0131r');
      nav.appendChild(badge);
    }
    var available=false;
    try{available=typeof canClaimDailyReward==='function'&&canClaimDailyReward();}catch(e){}
    badge.style.display=available?'flex':'none';
  }

  function shopCurrencyValue(node,src,className){
    if(!node)return;
    var value=(node.textContent||'').replace(/[^0-9.,]/g,'').trim();
    if(!value)return;
    node.innerHTML=shopImage(src,className||'luno-shop-price-art','')+'<span>'+value+'</span>';
  }

  function polishShopCurrencyIcons(wrap){
    if(!wrap)return;
    wrap.querySelectorAll('.shx-card-price.shx-gold').forEach(function(node){shopCurrencyValue(node,A.statusGold);});
    wrap.querySelectorAll('.shx-card-price.shx-gem').forEach(function(node){shopCurrencyValue(node,A.statusGem);});
    wrap.querySelectorAll('.shx-cur-card').forEach(function(card){
      var amount=card.querySelector('.shx-cur-amt');
      shopCurrencyValue(amount,card.classList.contains('shx-cur-m')?A.statusGem:A.statusGold,'luno-shop-pack-currency-art');
    });
    wrap.querySelectorAll('.shx-curcol-h').forEach(function(head,index){
      head.innerHTML=shopImage(index?A.statusGem:A.statusGold,'luno-shop-heading-currency-art','')+'<span>'+(index?'ELMAS PAKETLER\u0130':'ALTIN PAKETLER\u0130')+'</span>';
    });
    var daily=wrap.querySelector('.shx-daily-sub');
    if(daily){
      var dailyValue=(daily.textContent||'').replace(/[^0-9.,]/g,'').trim();
      daily.innerHTML=shopImage(A.statusGold,'luno-shop-daily-currency-art','')+'<span>'+dailyValue+' ALTIN</span>';
    }
  }

  function polishShopDom(){
    var wrap=document.querySelector('#ovBody .shx-wrap');
    if(!wrap||wrap.classList.contains('is-luno-polished'))return;
    wrap.classList.add('is-luno-polished');
    var shopBody=document.getElementById('ovBody');
    if(shopBody)shopBody.classList.remove('is-luno-costumes-v11');

    var top=wrap.querySelector('.shx-topcur');
    if(top){
      var gold=(window.PLAYER&&PLAYER.gold)||0;
      var gems=(window.PLAYER&&PLAYER.gems)||0;
      top.innerHTML=
        '<button class="shx-pill" onclick="openShopForCurrency(\'gold\')">'+shopImage(A.statusGold,'shx-pill-art','')+'<span>'+gold.toLocaleString('tr-TR')+'</span><span class="shx-pill-plus">+</span></button>'+ 
        '<button class="shx-pill" onclick="openShopForCurrency(\'gem\')">'+shopImage(A.statusGem,'shx-pill-art','')+'<span>'+gems.toLocaleString('tr-TR')+'</span><span class="shx-pill-plus">+</span></button>';
    }

    var premium=wrap.querySelector('.shx-premium');
    if(premium){
      premium.innerHTML=
        shopImage(A.shopPremium,'shx-premium-art','')+
        '<div class="shx-premium-mid"><div class="shx-premium-kicker">AYLIK AYRICALIKLAR</div><div class="shx-premium-title">LUNO PREMIUM</div><div class="shx-premium-feats"><span>\u265f \u00d6zel Set</span><span>Bonus Alt\u0131n</span><span>Ta\u00e7 Rozeti</span></div></div>'+ 
        '<div class="shx-premium-btn">KE\u015eFET</div>';
      if(top)top.insertAdjacentElement('afterend',premium);
      else wrap.insertBefore(premium,wrap.firstChild);
    }

    var sections=wrap.querySelectorAll('.shx-sec');
    if(sections[0])sections[0].innerHTML=shopImage(A.shopStarter,'shx-hdr-ic','')+'<span>\u00d6ZEL TEKL\u0130FLER</span>';
    if(sections[1])sections[1].innerHTML=shopImage(A.shopChestCommon,'shx-hdr-ic','')+'<span>SANDIKLAR</span>';
    if(sections[2]){
      sections[2].classList.add('luno-set-section');
      sections[2].innerHTML='<img class="luno-shop-set-heading-piece" src="'+v22DefaultPieceSource('w','K')+'" alt=""><span>TA\u015e KOST\u00dcMLER\u0130</span><button class="luno-shop-set-all" type="button" onclick="closeOverlay();setTimeout(openCostumes,220)">T\u00dcM\u00dcN\u00dc G\u00d6R &#10095;</button>';
    }

    var offers=wrap.querySelectorAll('.shx-ocard');
    [A.shopStarter,A.shopExpert].forEach(function(src,index){
      var card=offers[index];
      if(!card)return;
      card.classList.add(index?'is-expert':'is-starter');
      var art=card.querySelector('.shx-ocard-art');
      if(art)art.src=src;
      else{
        var offerTop=card.querySelector('.shx-ocard-top');
        if(offerTop)offerTop.insertAdjacentHTML('afterbegin',shopImage(src,'shx-ocard-art',''));
      }
    });

    var chestArt=[A.shopChestCommon,A.shopChestRare,A.shopChestLegendary,A.shopChestRoyal];
    var chestCards=sections[1]&&sections[1].nextElementSibling;
    if(chestCards){
      chestCards.classList.add('shx-chest-row');
      chestCards.querySelectorAll('.shx-card').forEach(function(card,index){
        var art=card.querySelector('.shx-art');
        if(art&&chestArt[index])art.src=chestArt[index];
      });
    }

    var costumeRow=sections[2]&&sections[2].nextElementSibling;
    if(costumeRow){
      costumeRow.classList.remove('shx-costume-slots');
      costumeRow.classList.add('luno-shop-set-row');
      costumeRow.innerHTML=V11_SET_ORDER.map(function(id,index){var meta=V11_SET_META[id];meta.id=id;return v11ShopSetCard(meta,index);}).join('');
    }

    var currencyArt=[A.shopGoldSmall,A.shopGoldMedium,A.shopGoldLarge,A.shopGemSmall,A.shopGemMedium,A.shopGemLarge];
    wrap.querySelectorAll('.shx-cur-card').forEach(function(card,index){
      var art=card.querySelector('.shx-art-sm');
      if(art&&currencyArt[index])art.src=currencyArt[index];
    });

    var daily=wrap.querySelector('.shx-daily');
    if(daily){
      var oldArt=daily.querySelector('.shx-daily-coin,.shx-daily-ic');
      if(oldArt)oldArt.outerHTML=shopImage(A.shopDaily,'shx-daily-art','');
      daily.classList.add('is-shop-last');
      wrap.appendChild(daily);
    }
    polishShopCurrencyIcons(wrap);
    updateShopDailyBadge();
  }

  function patchShopExperience(){
    if(typeof window.openShop==='function'&&!window.openShop.__lunoShopPolish){
      var originalOpenShop=window.openShop;
      window.openShop=function(){
        var result=originalOpenShop.apply(this,arguments);
        polishShopDom();
        setTimeout(polishShopDom,0);
        return result;
      };
      window.openShop.__lunoShopPolish=true;
    }
    if(typeof window.claimDailyReward==='function'&&!window.claimDailyReward.__lunoShopPolish){
      var originalClaim=window.claimDailyReward;
      window.claimDailyReward=function(){
        var result=originalClaim.apply(this,arguments);
        setTimeout(updateShopDailyBadge,40);
        return result;
      };
      window.claimDailyReward.__lunoShopPolish=true;
    }
    window.addEventListener('focus',updateShopDailyBadge);
    document.addEventListener('visibilitychange',updateShopDailyBadge);
    updateShopDailyBadge();
  }

  function profileImage(src,className){
    return '<img class="'+className+'" src="'+src+'" alt="">';
  }

  function installAvatarArt(){
    if(typeof window.AVATAR_IMGS==='undefined')window.AVATAR_IMGS={};
    Object.keys(A.avatarIcons).forEach(function(key){window.AVATAR_IMGS[key]=A.avatarIcons[key];});
  }

  function tierSourceForLevel(level){
    var safe=Math.max(1,Math.min(50,parseInt(level,10)||1));
    return A.levelTiers[Math.min(9,Math.floor((safe-1)/5))];
  }

  function installLevelArt(){
    if(typeof window.LUNO_LVL==='undefined')window.LUNO_LVL={};
    for(var level=1;level<=50;level++)window.LUNO_LVL['lvl_'+level]=tierSourceForLevel(level);
  }

  function polishProfileLevelBadge(wrap){
    var badge=wrap&&wrap.querySelector('.pf2-lvlbadge');
    if(!badge)return;
    var level=(window.PLAYER&&PLAYER.profile&&PLAYER.profile.lvl)||1;
    badge.innerHTML=profileImage(tierSourceForLevel(level),'pf2-lvlimg')+'<span class="luno-profile-level-number">'+level+'</span>';
    badge.setAttribute('aria-label','Seviye '+level+' \u00f6d\u00fcllerini g\u00f6r');
  }

  function polishProfileDom(){
    var wrap=document.querySelector('#ovBody .pf2-wrap');
    if(!wrap)return;
    wrap.classList.add('is-luno-profile');

    var stats=wrap.querySelectorAll('.pf2-stat-ic');
    [A.profileTrophy,A.profileWins,A.profileRate,A.profileStreak].forEach(function(src,index){
      if(stats[index])stats[index].innerHTML=profileImage(src,'luno-profile-stat-art');
    });

    var about=wrap.querySelector('.pf2-about-head');
    if(about)about.innerHTML=profileImage(A.profileAbout,'luno-profile-head-art')+'<span>HAKKINDA</span>';

    var sectionHeads=wrap.querySelectorAll('.pf2-ms-head');
    if(sectionHeads[0]){
      var matchIcon=sectionHeads[0].querySelector('.pf2-ms-ic');
      if(matchIcon)matchIcon.innerHTML=profileImage(A.profileMatchStats,'luno-profile-section-art');
    }
    if(sectionHeads[1]){
      var achievementIcon=sectionHeads[1].querySelector('.pf2-ms-ic');
      if(achievementIcon)achievementIcon.innerHTML=profileImage(A.profileAchievements,'luno-profile-section-art');
      var achievementSection=sectionHeads[1].closest('.pf2-ms');
      if(achievementSection)achievementSection.classList.add('luno-achievement-section');
    }

    var loginIcon=wrap.querySelector('.pf2-strk-login .pf2-strk-ic');
    if(loginIcon)loginIcon.innerHTML=profileImage(A.profileLoginStreak,'luno-profile-streak-art');
    var passIcon=wrap.querySelector('.pf2-strk-prem .pf2-strk-ic,.pf2-strk-noprem .pf2-strk-ic');
    if(passIcon)passIcon.innerHTML=profileImage(A.profilePass,'luno-profile-streak-art');

    var pills=wrap.querySelectorAll('.pf2-pill');
    if(pills[0]){
      var countryIcon=pills[0].querySelector('.pf2-pill-ic');
      if(countryIcon){
        var country=(window.PLAYER&&PLAYER.profile&&PLAYER.profile.country)||'TR';
        countryIcon.innerHTML=typeof window.flagEmoji==='function'?window.flagEmoji(country):country;
      }
    }
    if(pills[1]){
      var rankIcon=pills[1].querySelector('.pf2-pill-ic');
      if(rankIcon){rankIcon.innerHTML='';rankIcon.className='pf2-pill-ic luno-profile-empty-rank';rankIcon.setAttribute('aria-hidden','true');}
    }

    var bottomCards=wrap.querySelectorAll('.pf2-bcard');
    if(bottomCards[0]){
      var joinIcon=bottomCards[0].querySelector('.pf2-bic');
      if(joinIcon)joinIcon.innerHTML=profileImage(A.profileJoinDate,'luno-profile-bottom-art');
    }
    if(bottomCards[1]){
      var seasonIcon=bottomCards[1].querySelector('.pf2-bic');
      if(seasonIcon){seasonIcon.innerHTML='';seasonIcon.className='pf2-bic luno-profile-empty-season';seasonIcon.setAttribute('aria-hidden','true');}
    }
    if(bottomCards[2]){
      var collectionIcon=bottomCards[2].querySelector('.pf2-bic');
      if(collectionIcon)collectionIcon.innerHTML=profileImage(A.profileCollection,'luno-profile-bottom-art');
    }

    polishProfileLevelBadge(wrap);

    var achievementDefs=typeof ACHIEVEMENTS!=='undefined'?ACHIEVEMENTS:[];
    wrap.querySelectorAll('.mp-ach').forEach(function(row){
      var nameNode=row.querySelector('.mp-ach-name');
      var iconNode=row.querySelector('.mp-ach-icon');
      if(!nameNode||!iconNode)return;
      var label=(nameNode.textContent||'').trim();
      var def=achievementDefs.find(function(item){return item.name===label;});
      if(!def||!A.achievements[def.id])return;
      row.dataset.achievementId=def.id;
      iconNode.innerHTML=profileImage(A.achievements[def.id],'luno-achievement-art');
      iconNode.classList.add('has-luno-art');
    });

    var history=wrap.querySelector('.mp-history-btn .mp-hist-ic');
    if(history)history.innerHTML=profileImage(A.profileHistory,'luno-profile-action-art');
    var signout=wrap.querySelector('.mp-signout span:first-child');
    if(signout)signout.innerHTML=profileImage(A.profileSignout,'luno-profile-action-art');
  }

  function patchProfileExperience(){
    if(typeof window.openMyProfile!=='function'||window.openMyProfile.__lunoProfilePolish)return;
    var originalOpenProfile=window.openMyProfile;
    window.openMyProfile=function(){
      var result=originalOpenProfile.apply(this,arguments);
      polishProfileDom();
      setTimeout(polishProfileDom,0);
      return result;
    };
    window.openMyProfile.__lunoProfilePolish=true;
  }

  function levelBadgeMarkup(level,className){
    return '<div class="luno-level-badge '+(className||'')+'"><img src="'+tierSourceForLevel(level)+'" alt=""><span>'+level+'</span></div>';
  }

  function patchLevelExperience(){
    installLevelArt();
    window.closeLevelRewardsV9=function(){
      var overlay=document.getElementById('lvlRewOv');
      if(!overlay)return;
      overlay.classList.remove('show');
      setTimeout(function(){if(overlay.parentNode)overlay.parentNode.removeChild(overlay);},260);
      try{if(typeof sndUiClick==='function')sndUiClick();}catch(e){}
    };
    window.showLevelUpPopup=function(newLevel){
      var level=Math.max(1,Math.min(50,parseInt(newLevel,10)||1));
      try{if(typeof sndTrophyGain==='function')sndTrophyGain();}catch(e){}
      var old=document.getElementById('lvlupOv');if(old)old.remove();
      var overlay=document.createElement('div');
      overlay.id='lvlupOv';
      overlay.className='luno-level-overlay luno-level-up-overlay';
      overlay.setAttribute('role','dialog');
      overlay.setAttribute('aria-modal','true');
      overlay.setAttribute('aria-label','Seviye atlad\u0131n');
      overlay.innerHTML='<div class="luno-level-card">'+
        '<div class="luno-level-sparkles" aria-hidden="true"><i></i><i></i><i></i><i></i></div>'+ 
        levelBadgeMarkup(level,'is-level-up')+
        '<div class="luno-level-kicker">YEN\u0130 A\u015eAMA</div>'+ 
        '<div class="luno-level-title">SEV\u0130YE ATLADIN!</div>'+ 
        '<div class="luno-level-subtitle">Seviye '+level+' a\u00e7\u0131ld\u0131</div>'+ 
        '<div class="luno-level-reward"><img src="'+A.statusGold+'" alt=""><div><strong>+'+(100+level*20)+'</strong><span>Alt\u0131n \u00f6d\u00fcl\u00fc</span></div></div>'+ 
        '<button class="luno-level-confirm" type="button" onclick="closeLevelUp()">HAR\u0130KA!</button>'+ 
      '</div>';
      document.body.appendChild(overlay);
      requestAnimationFrame(function(){overlay.classList.add('show');});
    };
    window.showLevelUpPopup.__lunoLevelV9=true;
    window.showLevelRewards=function(){
      var level=(window.PLAYER&&PLAYER.profile&&PLAYER.profile.lvl)||1;
      var nextReward=100+(level+1)*20;
      try{if(typeof sndUiClick==='function')sndUiClick();}catch(e){}
      var old=document.getElementById('lvlRewOv');if(old)old.remove();
      var overlay=document.createElement('div');
      overlay.id='lvlRewOv';
      overlay.className='luno-level-overlay luno-level-rewards-overlay';
      overlay.setAttribute('role','dialog');
      overlay.setAttribute('aria-modal','true');
      overlay.setAttribute('aria-label','Seviye \u00f6d\u00fclleri');
      overlay.innerHTML='<div class="luno-level-card">'+
        levelBadgeMarkup(level,'is-current-level')+
        '<div class="luno-level-kicker">MEVCUT SEV\u0130YEN</div>'+ 
        '<div class="luno-level-title">SEV\u0130YE \u00d6D\u00dcLLER\u0130</div>'+ 
        '<div class="luno-level-subtitle">Ma\u00e7 oynad\u0131k\u00e7a XP kazan, rozetini geli\u015ftir.</div>'+ 
        '<div class="luno-level-reward is-next"><img src="'+A.statusGold+'" alt=""><div><strong>+'+nextReward+'</strong><span>Sonraki seviyede alt\u0131n</span></div></div>'+ 
        '<div class="luno-level-note"><b>Seviye 10</b> ve <b>Seviye 25</b> ba\u015far\u0131mlar\u0131nda ek alt\u0131n ve elmas \u00f6d\u00fclleri bulunur.</div>'+ 
        '<button class="luno-level-confirm" type="button" onclick="closeLevelRewardsV9()">ANLADIM</button>'+ 
      '</div>';
      document.body.appendChild(overlay);
      requestAnimationFrame(function(){overlay.classList.add('show');});
    };
    window.showLevelRewards.__lunoLevelV9=true;
  }

  function passArt(src,className){
    return '<img class="'+className+'" src="'+src+'" alt="">';
  }

  function passRewardArt(reward){
    if(!reward)return '';
    if(reward.type==='gold')return A.statusGold;
    if(reward.type==='gem')return A.statusGem;
    if(reward.type==='card_pack'){
      var name=reward.name||'';
      if(name.indexOf('Efsane')>=0)return A.shopChestLegendary;
      if(name.indexOf('Nadir')>=0)return A.shopChestRare;
      return A.shopChestCommon;
    }
    return '';
  }

  function polishPassDom(){
    var wrap=document.querySelector('#ovBody .lpx-wrap');
    if(!wrap)return;
    wrap.classList.add('is-luno-pass');

    var bannerContent=wrap.querySelector('.lpx-banner-content');
    if(bannerContent&&!bannerContent.querySelector('.luno-pass-season-head')){
      var tag=bannerContent.querySelector('.lpx-season-tag');
      var name=bannerContent.querySelector('.lpx-season-name');
      var row=bannerContent.querySelector('.lpx-banner-row');
      var head=document.createElement('div');
      head.className='luno-pass-season-head';
      var copy=document.createElement('div');
      copy.className='luno-pass-season-copy';
      head.innerHTML=passArt(A.passSeason,'luno-pass-season-art');
      if(tag)copy.appendChild(tag);
      if(name)copy.appendChild(name);
      head.appendChild(copy);
      bannerContent.insertBefore(head,row||bannerContent.firstChild);
    }

    var missions=Array.prototype.find.call(wrap.children,function(node){
      return node.getAttribute&&node.getAttribute('onclick')==='openPassMissions()';
    });
    if(missions){
      missions.removeAttribute('style');
      missions.className='luno-pass-missions';
      missions.innerHTML=passArt(A.passMissions,'luno-pass-missions-art')+
        '<div class="luno-pass-missions-copy"><div class="luno-pass-missions-title">GÖREVLER</div><div class="luno-pass-missions-sub">Luno Yıldızı topla, Pass seviyeni yükselt</div></div>'+
        '<span class="luno-pass-arrow" aria-hidden="true">›</span>';
    }

    var crown=wrap.querySelector('.lpx-up-crown');
    if(crown)crown.innerHTML=passArt(A.passPremium,'luno-pass-premium-art');
    var premiumDesc=wrap.querySelector('.lpx-up-desc');
    if(premiumDesc)premiumDesc.textContent='30 seviyede ek ödüllerin kilidini aç';
    var premiumGem=wrap.querySelector('.lpx-up-val');
    if(premiumGem){
      premiumGem.innerHTML='<span>'+((typeof PASS_PREMIUM_GEMS!=='undefined')?PASS_PREMIUM_GEMS:450)+'</span>'+passArt(A.statusGem,'luno-pass-price-gem');
    }

    var freeHead=wrap.querySelector('.lpx-th-free');
    if(freeHead){
      freeHead.querySelectorAll('.lpx-th-ic').forEach(function(node){node.remove();});
      if(!freeHead.querySelector('.luno-pass-track-art'))freeHead.insertAdjacentHTML('afterbegin',passArt(A.passTrackFree,'luno-pass-track-art'));
    }
    var premiumHead=wrap.querySelector('.lpx-th-prem');
    if(premiumHead){
      premiumHead.querySelectorAll('.lpx-th-ic').forEach(function(node){node.remove();});
      if(!premiumHead.querySelector('.luno-pass-track-art'))premiumHead.insertAdjacentHTML('afterbegin',passArt(A.passTrackPremium,'luno-pass-track-art'));
    }

    var rows=wrap.querySelectorAll('.lpx-row');
    rows.forEach(function(row,index){
      var rewardRow=(typeof PASS_REWARDS!=='undefined')?PASS_REWARDS[index]:null;
      var cells=row.querySelectorAll('.lpx-cell');
      [rewardRow&&rewardRow.free,rewardRow&&rewardRow.prem].forEach(function(reward,cellIndex){
        var cell=cells[cellIndex];
        if(!cell||!reward)return;
        cell.dataset.rewardType=reward.type||'';
        var icon=cell.querySelector('.lpx-cell-icon');
        if(!icon)return;
        var src=passRewardArt(reward);
        if(src){
          icon.innerHTML=passArt(src,'luno-pass-reward-art');
          cell.classList.add('has-luno-pass-art');
        }else{
          icon.innerHTML='';
          icon.setAttribute('aria-hidden','true');
          cell.classList.add('luno-pass-art-pending');
        }
      });
      var level=row.querySelector('.lpx-level-pill');
      if(level)level.style.setProperty('--luno-level-frame','url("'+A.passLevelFrame+'")');
    });

    wrap.querySelectorAll('.lpx-cell-lock').forEach(function(lock){
      lock.innerHTML='<span class="luno-pass-lock-body"><span class="luno-pass-lock-shackle"></span><span class="luno-pass-lock-key"></span></span>';
    });
  }

  function patchPassExperience(){
    if(typeof window.openLunoPass!=='function'||window.openLunoPass.__lunoPassPolish)return;
    var originalOpenPass=window.openLunoPass;
    window.openLunoPass=function(){
      var result=originalOpenPass.apply(this,arguments);
      polishPassDom();
      setTimeout(polishPassDom,0);
      return result;
    };
    window.openLunoPass.__lunoPassPolish=true;
  }

  var settingsRows=[
    {art:'settingsSound',tr:['SES EFEKTLER\u0130','Hamle, kart ve aray\u00fcz sesleri'],en:['SOUND EFFECTS','Move, card and interface sounds']},
    {art:'settingsMusic',tr:['ARKA PLAN M\u00dcZ\u0130\u011e\u0130','Men\u00fc ve sava\u015f m\u00fczi\u011fi'],en:['BACKGROUND MUSIC','Menu and battle music']},
    {art:'settingsVibration',tr:['T\u0130TRE\u015e\u0130M','Kritik hamlelerde hafif titre\u015fim'],en:['VIBRATION','Gentle vibration on key moves']},
    {art:'settingsAnimation',tr:['AN\u0130MASYONLAR','Ak\u0131c\u0131 ge\u00e7i\u015fler ve oyun efektleri'],en:['ANIMATIONS','Smooth transitions and game effects']},
    {art:'settingsHints',tr:['\u0130PU\u00c7LARI','Ma\u00e7 s\u0131ras\u0131nda yard\u0131mc\u0131 \u00f6neriler'],en:['HINTS','Helpful suggestions during matches']},
    {art:'settingsNotification',tr:['B\u0130LD\u0130R\u0130MLER','Davet, \u00f6d\u00fcl ve ma\u00e7 uyar\u0131lar\u0131'],en:['NOTIFICATIONS','Invite, reward and match alerts']},
    {art:'settingsFriendsDm',tr:['SADECE ARKADA\u015e MESAJI','Yaln\u0131zca arkada\u015flardan \u00f6zel mesaj al'],en:['FRIENDS-ONLY MESSAGES','Only receive private messages from friends']},
    {art:'settingsGuide',tr:['REHBER\u0130 TEKRAR \u0130ZLE','Luno ile \u00f6\u011fretici turu yeniden ba\u015flat'],en:['REPLAY TUTORIAL','Restart the guided tour with Luno']},
    {art:'settingsEdit',tr:['PROF\u0130L\u0130 D\u00dcZENLE','\u0130sim, \u00fclke ve profil g\u00f6rselini de\u011fi\u015ftir'],en:['EDIT PROFILE','Change name, country and profile image']},
    {art:'settingsSignout',tr:['\u00c7IKI\u015e YAP','Bu cihazdaki oturumunu kapat'],en:['SIGN OUT','Sign out on this device']},
    {art:'settingsInstagram',tr:['INSTAGRAM','Luno Chess payla\u015f\u0131mlar\u0131n\u0131 takip et'],en:['INSTAGRAM','Follow Luno Chess updates']},
    {art:'settingsTiktok',tr:['TIKTOK','K\u0131sa Luno Chess videolar\u0131n\u0131 izle'],en:['TIKTOK','Watch short Luno Chess videos']},
    {art:'settingsAbout',tr:['LUNO CHESS','S\u00fcr\u00fcm 1.0.0 \u00b7 Kartlarla yeni nesil satran\u00e7'],en:['LUNO CHESS','Version 1.0.0 \u00b7 A new generation of card chess']}
  ];

  function polishSettingsDom(){
    var body=document.getElementById('ovBody');
    var wrap=body&&body.querySelector('.set-wrap');
    if(!wrap)return;
    body.classList.add('is-luno-settings');
    wrap.classList.add('is-luno-settings-wrap');
    var english=(window.LUNO_LANG||'tr')==='en';
    var title=document.getElementById('ovTitle');
    if(title)title.textContent=english?'SETTINGS':'AYARLAR';

    var lists=wrap.querySelectorAll('.set-list');
    lists.forEach(function(list,index){list.classList.add('luno-settings-group-'+index);});
    var languageList=lists[0];
    if(languageList){
      languageList.removeAttribute('style');
      languageList.classList.add('luno-language-list');
      var lang=(window.LUNO_LANG||'tr');
      Array.prototype.forEach.call(languageList.children,function(card,index){
        var code=index===0?'tr':'en';
        card.removeAttribute('style');
        card.className='luno-language-card'+(lang===code?' is-active':'');
        card.innerHTML='<img class="luno-language-art" src="'+(code==='tr'?A.settingsLanguageTr:A.settingsLanguageEn)+'" alt="">'+
          '<span class="luno-language-copy"><b>'+(code==='tr'?'T\u00fcrk\u00e7e':'English')+'</b><small>'+(code==='tr'?'TR':'EN')+'</small></span>'+
          '<span class="luno-language-check" aria-hidden="true">&#10003;</span>';
      });
    }

    var sectionIcons=[A.settingsLanguageTr,A.settingsSound,A.settingsGame,A.settingsEdit,A.settingsInstagram,A.settingsAbout];
    var sectionLabels=english?['LANGUAGE','SOUND & VISUAL','GAME','ACCOUNT','FOLLOW US','ABOUT']:['D\u0130L / LANGUAGE','SES & G\u00d6RSEL','OYUN','HESAP','B\u0130Z\u0130 TAK\u0130P ET','HAKKINDA'];
    wrap.querySelectorAll('.set-section-title').forEach(function(section,index){
      section.innerHTML='<img class="luno-settings-section-art" src="'+sectionIcons[index]+'" alt=""><span>'+sectionLabels[index]+'</span>';
    });

    wrap.querySelectorAll('.set-row').forEach(function(row,index){
      var config=settingsRows[index];if(!config)return;
      row.dataset.lunoSetting=String(index);
      if(index===9)row.classList.add('is-luno-danger');
      var icon=row.querySelector('.set-row-icon');
      if(icon)icon.innerHTML='<img class="luno-settings-row-art" src="'+A[config.art]+'" alt="">';
      var copy=english?config.en:config.tr;
      var rowTitle=row.querySelector('.set-row-title');if(rowTitle)rowTitle.textContent=copy[0];
      var sub=row.querySelector('.set-row-sub');if(sub)sub.textContent=copy[1];
      var arrow=row.querySelector('.set-row-arrow');if(arrow)arrow.innerHTML='&#8250;';
      var toggle=row.querySelector('.set-toggle');
      if(toggle)toggle.setAttribute('aria-label',copy[0]);
    });
  }

  function patchSettingsExperience(){
    if(typeof window.openSettings!=='function'||window.openSettings.__lunoSettingsV8)return;
    var originalOpenSettings=window.openSettings;
    window.openSettings=function(){var result=originalOpenSettings.apply(this,arguments);polishSettingsDom();setTimeout(polishSettingsDom,0);return result;};
    window.openSettings.__lunoSettingsV8=true;
  }

  function passMissionSource(eventName){
    return eventName==='login'?A.passMissionLogin:
      eventName==='play'?A.passMissionPlay:
      eventName==='win'?A.passMissionWin:
      eventName==='ranked'?A.passMissionRanked:
      eventName==='card'?A.passMissionCard:
      eventName==='legendary_card'?A.passMissionLegendary:
      eventName==='capture'?A.passMissionCapture:
      eventName==='streak'?A.passMissionStreak:
      eventName==='quick_win'?A.passMissionQuick:A.passMissionStar;
  }

  function passSpecialSource(id){
    return id==='sp_instagram'?A.passMissionInstagram:id==='sp_tiktok'?A.passMissionTiktok:A.passMissionYoutube;
  }

  function passTaskIcon(src){return '<img class="luno-pm-task-art" src="'+src+'" alt="">';}

  function polishPassMissionRow(row,mission){
    if(!row||!mission)return;
    row.classList.add('is-luno-pm-row','pm-diff-'+mission.diff);
    var diff=row.querySelector('.pm-diff');if(diff)diff.removeAttribute('style');
    var icon=row.querySelector(':scope > .luno-pm-task-icon');
    if(!icon){icon=document.createElement('div');icon.className='luno-pm-task-icon';row.insertBefore(icon,row.firstChild);}
    icon.innerHTML=passTaskIcon(passMissionSource(mission.ev));
    var meta=row.querySelector('.pm-row-meta');
    if(meta){
      meta.innerHTML='<span class="luno-pm-progress">'+Math.min(mission.prog||0,mission.target)+' / '+mission.target+'</span>'+
        '<span class="luno-pm-points">+'+mission.pts+passTaskIcon(A.passMissionStar)+'</span>';
    }
    var lock=row.querySelector('.pm-claim-lock');
    if(lock)lock.innerHTML='<span class="luno-pm-lock"><i></i></span>';
  }

  function polishPassMissionsDom(){
    var body=document.getElementById('ovBody');
    var wrap=body&&body.querySelector('.pm-wrap');
    if(!wrap)return;
    body.classList.add('is-luno-pass-missions');wrap.classList.add('is-luno-pm-wrap');
    var heroIcon=wrap.querySelector('.pm-hero-ic');if(heroIcon)heroIcon.innerHTML=passTaskIcon(A.passMissionStar);
    var english=(window.LUNO_LANG||'tr')==='en';
    var heroTitle=wrap.querySelector('.pm-hero-title');if(heroTitle)heroTitle.textContent=english?'COLLECT LUNO STARS':'LUNO YILDIZI TOPLA';
    var heroSub=wrap.querySelector('.pm-hero-sub');if(heroSub)heroSub.textContent=english?'Complete missions and raise your Pass level':'G\u00f6revleri tamamla, Pass seviyeni y\u00fckselt';

    var sections=wrap.querySelectorAll('.pm-sec');
    var sectionArt=[A.passMissionDaily,A.passMissionWeekly,A.passMissionSpecial];
    var sectionLabels=english?['DAILY MISSIONS','WEEKLY MISSIONS','SPECIAL MISSIONS']:['G\u00dcNL\u00dcK G\u00d6REVLER','HAFTALIK G\u00d6REVLER','\u00d6ZEL G\u00d6REVLER'];
    sections.forEach(function(section,index){
      var head=section.querySelector('.pm-sec-head');
      if(head)head.innerHTML='<img class="luno-pm-section-art" src="'+sectionArt[index]+'" alt=""><span>'+sectionLabels[index]+'</span>';
    });

    var pm=(typeof PLAYER!=='undefined'&&PLAYER.passMissions)?PLAYER.passMissions:{daily:[],weekly:[],specialDone:{}};
    [pm.daily||[],pm.weekly||[]].forEach(function(list,sectionIndex){
      if(!sections[sectionIndex])return;
      sections[sectionIndex].querySelectorAll('.pm-row').forEach(function(row,index){polishPassMissionRow(row,list[index]);});
    });

    if(sections[2]){
      var specialDone=pm.specialDone||{};
      var available=(typeof SPECIAL_PASS_MISSIONS!=='undefined'?SPECIAL_PASS_MISSIONS:[]).filter(function(item){return !specialDone[item.id];});
      sections[2].querySelectorAll('.pm-special').forEach(function(row,index){
        var item=available[index];if(!item)return;
        row.classList.add('is-luno-pm-row','is-luno-pm-special');
        var old=row.querySelector('.pm-sp-ic');if(old)old.remove();
        var icon=row.querySelector(':scope > .luno-pm-task-icon');
        if(!icon){icon=document.createElement('div');icon.className='luno-pm-task-icon';row.insertBefore(icon,row.firstChild);}
        icon.innerHTML=passTaskIcon(passSpecialSource(item.id));
        var meta=row.querySelector('.pm-row-meta');if(meta)meta.innerHTML='<span class="luno-pm-single">'+(english?'One time':'Tek seferlik')+'</span><span class="luno-pm-gems">+'+item.gems+'<img src="'+A.statusGem+'" alt=""></span>';
      });
    }
  }

  function patchPassMissionsExperience(){
    if(typeof window.openPassMissions!=='function'||window.openPassMissions.__lunoPassMissionsV8)return;
    var originalOpenPassMissions=window.openPassMissions;
    window.openPassMissions=function(){var result=originalOpenPassMissions.apply(this,arguments);polishPassMissionsDom();setTimeout(polishPassMissionsDom,0);return result;};
    window.openPassMissions.__lunoPassMissionsV8=true;
  }

  function lunoDomImage(src,className){
    var image=document.createElement('img');
    image.className=className;
    image.src=src;
    image.alt='';
    return image;
  }

  function setLunoImage(node,src,className){
    if(!node||!src)return;
    var current=node.querySelector('img.'+className);
    if(current)return;
    node.innerHTML='';
    node.appendChild(lunoDomImage(src,className));
  }

  function polishTrophyMeta(node){
    if(!node||node.querySelector('.luno-friend-trophy-art'))return;
    var label=(node.textContent||'').replace(/\u{1F3C6}/gu,'').trim();
    node.innerHTML='';
    node.appendChild(lunoDomImage(A.statusTrophy,'luno-friend-trophy-art'));
    var text=document.createElement('span');
    text.textContent=label;
    node.appendChild(text);
  }

  function polishFriendEmpty(empty,requestsActive){
    if(!empty||empty.dataset.lunoEmpty==='1')return;
    var raw=(empty.textContent||'').trim();
    if(raw.indexOf('Yükleme hatası')>=0)return;
    var isRequests=requestsActive||raw.indexOf('istek')>=0;
    var title=isRequests?'Henüz istek yok':'Henüz arkadaşın yok';
    var sub=isRequests?'Yeni arkadaşlık istekleri burada görünecek':'Arama kutusundan kullanıcı adını bul ve ilk arkadaşını ekle.';
    empty.innerHTML='';
    empty.appendChild(lunoDomImage(isRequests?A.friendsRequestsEmpty:A.friendsEmpty,'luno-friend-empty-art'));
    var titleNode=document.createElement('div');titleNode.className='luno-friend-empty-title';titleNode.textContent=title;
    var subNode=document.createElement('div');subNode.className='luno-friend-empty-sub';subNode.textContent=sub;
    empty.appendChild(titleNode);empty.appendChild(subNode);
    empty.dataset.lunoEmpty='1';
  }

  function polishFriendsDom(){
    var wrap=document.querySelector('#ovBody .fh-wrap');
    if(!wrap)return;
    wrap.classList.add('is-luno-friends');
    setLunoImage(wrap.querySelector('.fh-search-icon'),A.friendsSearch,'luno-friend-search-art');

    var tabs=[
      [wrap.querySelector('#fhTabFriends .fh-tab-ic'),A.friendsTab],
      [wrap.querySelector('#fhTabRequests .fh-tab-ic'),A.friendsRequestsTab],
      [wrap.querySelector('#fhTabRank .fh-tab-ic'),A.friendsRankingTab]
    ];
    tabs.forEach(function(item){setLunoImage(item[0],item[1],'luno-friend-tab-art');});

    var requestsActive=!!wrap.querySelector('#fhTabRequests.fh-tab-active');
    wrap.querySelectorAll('.fh-empty').forEach(function(empty){polishFriendEmpty(empty,requestsActive);});

    wrap.querySelectorAll('.fh-trophy,.fh-req-meta,.rk-pod-trophies,.rk-row-trophies').forEach(polishTrophyMeta);
    wrap.querySelectorAll('.rk-rt-ic').forEach(function(node){
      setLunoImage(node,A.statusTrophy,'luno-friend-trophy-art');
    });
    var rankingTitle=wrap.querySelector('.rk-podium-title');
    if(rankingTitle&&!rankingTitle.querySelector('.luno-friend-ranking-head-art')){
      rankingTitle.innerHTML='';
      rankingTitle.appendChild(lunoDomImage(A.friendsRankingTab,'luno-friend-ranking-head-art'));
      var rankingText=document.createElement('span');rankingText.textContent='ARKADAŞ SIRALAMASI';rankingTitle.appendChild(rankingText);
    }

    var actionMap=[
      ['.fh-action-dm',A.friendsActionMessage],['.fh-action-invite',A.friendsActionBattle],
      ['.fh-action-remove',A.friendsActionRemove],['.fh-action-add',A.friendsActionAdd],
      ['.fh-req-accept',A.friendsActionAccept],['.fh-req-reject',A.friendsActionReject]
    ];
    actionMap.forEach(function(item){
      wrap.querySelectorAll(item[0]).forEach(function(button){setLunoImage(button,item[1],'luno-friend-action-art');});
    });

    var content=wrap.querySelector('#fhContent');
    var results=wrap.querySelector('#fhSearchResults');
    if(!wrap.__lunoFriendObserver){
      var queued=false;
      var observer=new MutationObserver(function(){
        if(queued)return;queued=true;
        requestAnimationFrame(function(){queued=false;polishFriendsDom();});
      });
      if(content)observer.observe(content,{childList:true,subtree:true});
      if(results)observer.observe(results,{childList:true,subtree:true});
      wrap.__lunoFriendObserver=observer;
    }
  }

  function patchFriendsExperience(){
    if(typeof window.openFriendsHub==='function'&&!window.openFriendsHub.__lunoFriendsPolish){
      var originalOpenFriends=window.openFriendsHub;
      window.openFriendsHub=function(){var result=originalOpenFriends.apply(this,arguments);polishFriendsDom();setTimeout(polishFriendsDom,0);return result;};
      window.openFriendsHub.__lunoFriendsPolish=true;
    }
    if(typeof window.fhSwitchTab==='function'&&!window.fhSwitchTab.__lunoFriendsPolish){
      var originalFriendTab=window.fhSwitchTab;
      window.fhSwitchTab=function(){var result=originalFriendTab.apply(this,arguments);polishFriendsDom();setTimeout(polishFriendsDom,0);return result;};
      window.fhSwitchTab.__lunoFriendsPolish=true;
    }
  }

  function polishMissionsDom(){
    var wrap=document.querySelector('#ovBody .ms-wrap');
    if(!wrap)return;
    wrap.classList.add('is-luno-missions');
    setLunoImage(wrap.querySelector('.ms-hd-icon'),A.missionsHero,'luno-mission-hero-art');
    var tabArt={daily:A.missionsDailyTab,weekly:A.missionsWeeklyTab,special:A.missionsSpecialTab};
    wrap.querySelectorAll('.ms-tab').forEach(function(tab){
      setLunoImage(tab.querySelector('.ms-tab-ic'),tabArt[tab.getAttribute('data-tab')],'luno-mission-tab-art');
    });

    var list=(typeof MISSIONS!=='undefined'&&MISSIONS[_missionTab])?MISSIONS[_missionTab]:[];
    wrap.querySelectorAll('.ms-card').forEach(function(card,index){
      var mission=list[index];
      if(!mission)return;
      card.dataset.missionId=mission.id;
      setLunoImage(card.querySelector('.ms-icon'),A.missionTasks[mission.id]||A.missionsHero,'luno-mission-task-art');
      card.querySelectorAll('.ms-rew-img').forEach(function(image){
        image.src=mission.reward&&mission.reward.type==='gem'?A.statusGem:A.statusGold;
        image.classList.add('luno-mission-reward-art');
      });
    });
  }

  function patchMissionsExperience(){
    if(typeof window.msSwitchTab==='function'&&!window.msSwitchTab.__lunoMissionsPolish){
      var originalMissionTab=window.msSwitchTab;
      window.msSwitchTab=function(){var result=originalMissionTab.apply(this,arguments);polishMissionsDom();setTimeout(polishMissionsDom,0);return result;};
      window.msSwitchTab.__lunoMissionsPolish=true;
    }
    if(typeof window.openMissions==='function'&&!window.openMissions.__lunoMissionsPolish){
      var originalOpenMissions=window.openMissions;
      window.openMissions=function(){var result=originalOpenMissions.apply(this,arguments);polishMissionsDom();setTimeout(polishMissionsDom,0);return result;};
      window.openMissions.__lunoMissionsPolish=true;
    }
  }

  function rankMetricSource(){
    return (typeof _rankMode!=='undefined'&&_rankMode==='collection')?A.profileCollection:A.statusTrophy;
  }

  function polishRankMetric(node){
    if(!node)return;
    var mode=(typeof _rankMode!=='undefined'&&_rankMode==='collection')?'collection':'trophies';
    if(node.dataset.lunoRankMetric===mode)return;
    var label=(node.textContent||'').replace(/\u{1F3C6}|\u{1F48E}/gu,'').trim();
    node.innerHTML='';
    node.appendChild(lunoDomImage(rankMetricSource(),'luno-rank-metric-art'));
    var value=document.createElement('span');value.className='luno-rank-metric-value';value.textContent=label;
    node.appendChild(value);
    node.dataset.lunoRankMetric=mode;
  }

  function polishRankingDom(){
    var body=document.getElementById('ovBody');
    var tabs=body&&body.querySelector('.rk-tabs');
    if(!body||!tabs)return;
    body.classList.add('is-luno-ranking');
    body.dataset.lunoRankMode=(typeof _rankMode!=='undefined')?_rankMode:'trophies';

    var tabNodes=tabs.querySelectorAll('.rk-tab');
    [[tabNodes[0],A.statusTrophy,'KUPA'],[tabNodes[1],A.profileCollection,'KOLEKSİYON']].forEach(function(item){
      if(!item[0]||item[0].querySelector('.luno-rank-tab-art'))return;
      item[0].innerHTML='';
      item[0].appendChild(lunoDomImage(item[1],'luno-rank-tab-art'));
      var text=document.createElement('span');text.textContent=item[2];item[0].appendChild(text);
    });

    var title=body.querySelector('.rk-podium-title');
    if(title&&!title.querySelector('.luno-rank-title-star')){
      title.innerHTML='';
      title.appendChild(lunoDomImage(A.rankingStarGold,'luno-rank-title-star'));
      var titleText=document.createElement('span');titleText.textContent='EN İYİLER';title.appendChild(titleText);
      title.appendChild(lunoDomImage(A.rankingStarGold,'luno-rank-title-star'));
    }

    var crown=body.querySelector('.rk-crown');
    if(crown)setLunoImage(crown,A.rankingCrown,'luno-rank-crown-art');
    [[body.querySelector('.rk-medal-1'),A.rankingStarGold],[body.querySelector('.rk-medal-2'),A.rankingStarSilver],[body.querySelector('.rk-medal-3'),A.rankingStarBronze]].forEach(function(item){
      if(item[0])setLunoImage(item[0],item[1],'luno-rank-medal-art');
    });
    [[body.querySelector('.rk-base-1'),A.rankingPodiumGold],[body.querySelector('.rk-base-2'),A.rankingPodiumSilver],[body.querySelector('.rk-base-3'),A.rankingPodiumBronze]].forEach(function(item){
      if(item[0])item[0].style.setProperty('--luno-rank-base','url("'+item[1]+'")');
    });
    body.querySelectorAll('.rk-row-avatar').forEach(function(avatar){
      var token=(avatar.textContent||'').trim();
      if(A.avatarIcons[token]&&!avatar.querySelector('.luno-avimg'))avatar.innerHTML=typeof window.avHtml==='function'?window.avHtml(token):profileImage(A.avatarIcons[token],'luno-avimg');
    });
    body.querySelectorAll('.rk-pod-trophies,.rk-row-trophies').forEach(polishRankMetric);

    var podium=body.querySelector('.rk-podium-bg');
    if(podium)podium.style.setProperty('--luno-rank-backdrop','url("'+A.rankingBackdrop+'")');
    var container=body.querySelector('#rkContainer');
    if(container&&!container.__lunoRankObserver){
      var queued=false;
      var observer=new MutationObserver(function(){
        if(queued)return;queued=true;
        requestAnimationFrame(function(){queued=false;polishRankingDom();});
      });
      observer.observe(container,{childList:true,subtree:true});
      container.__lunoRankObserver=observer;
    }
  }

  function patchRankingExperience(){
    if(typeof window.openRanking==='function'&&!window.openRanking.__lunoRankingPolish){
      var originalOpenRanking=window.openRanking;
      window.openRanking=function(){var result=originalOpenRanking.apply(this,arguments);polishRankingDom();setTimeout(polishRankingDom,0);return result;};
      window.openRanking.__lunoRankingPolish=true;
    }
    if(typeof window.switchRankMode==='function'&&!window.switchRankMode.__lunoRankingPolish){
      var originalSwitchRank=window.switchRankMode;
      window.switchRankMode=function(){var result=originalSwitchRank.apply(this,arguments);polishRankingDom();setTimeout(polishRankingDom,0);return result;};
      window.switchRankMode.__lunoRankingPolish=true;
    }
  }

  function guideSection(icon,title,body){
    return '<section class="gd-sec"><img class="luno-guide-icon" src="'+icon+'" alt=""><div class="luno-guide-copy"><h3 class="gd-h">'+title+'</h3><div class="gd-p">'+body+'</div></div></section>';
  }

  function buildLunoGuideHtml(){
    return '<div class="luno-guide-wrap">'+
      guideSection(A.guidePurpose,'MAÇIN HEDEFİ','Rakibin şahını <b>mat et</b>. Rakip teslim olursa veya süresi biterse de maçı kazanırsın. Kendi şahını tehdit altında bırakan hiçbir hamleye izin verilmez.')+
      guideSection(A.guideTurn,'TURUN İKİ ADIMI','Önce <b>kart aşaması</b> gelir: yeterli manan varsa bir kart oyna veya kart kullanmadan geç. Ardından <b>hamle aşamasında</b> bir satranç taşı oynat. Bazı kartlar o turun hamle hakkını özellikle değiştirebilir.')+
      guideSection(A.guidePieces,'TAŞLAR VE YASAL HAMLE','Piyon ileri gider ve çapraz alır; at L biçiminde, fil çapraz, kale düz, vezir her yönde, şah bir kare ilerler. Rok, terfi ve en passant klasik satranç kurallarına göre çalışır.')+
      guideSection(A.guideMana,'MANA YÖNETİMİ','İlk turunda <b>1 mana</b> ile başlarsın; sonraki her turunun başında <b>+1 mana</b> gelir ve sayaç en fazla <b>10</b> olur. Kartın sol üstündeki değer maliyetidir. Güçlü kart için biriktirmek bazen hemen oynamaktan daha değerlidir.')+
      guideSection(A.guideCards,'KARTLAR NASIL ÇALIŞIR','Kartlar satranç konumuna geçici etkiler ekler: taş dondurabilir, kare kurabilir, görüş açabilir veya yeni tehdit yaratabilir. Bir turda en fazla <b>bir kart</b> oynanır; hedefi geçersiz olan kart kullanılamaz.')+
      guideSection(A.guideLevel,'KART SEVİYESİ','Tuzak, Radar, Direniş, Sefer ve Kalkan aileleri geliştirilebilir. Açtığın üst seviyeler alt seviyeleri silmez; maça göre daha ucuz bir seviye seçerek mana tasarrufu yapabilirsin.')+
      guideSection(A.guideDeck,'AKTİF DESTE','Aktif destende <b>6 kart yuvası</b> bulunur. Koleksiyonundan altı kart seç; maç içinde bu deste elin olarak kullanılır. Kartlar koleksiyonundan eksilmez, oynanabilmeleri mana ve hedef kurallarına bağlıdır.')+
      guideSection(A.guideBattle,'SAVAŞ MODLARI','<b>Luno Eğitmenleri</b> ödülsüz pratik sunar. <b>Sıralı Maç</b> kupa ve sezon ilerlemesi içindir. <b>Arkadaşla Oyna</b> davet üzerinden özel karşılaşma başlatır.')+
      guideSection(A.guideSeason,'KUPA, ARENA VE SEZON','Kupa yalnızca sıralı sonuçlarla değişir; güçlü rakibi yenmek daha fazla değer kazandırabilir. Kupa eşiklerini geçtikçe yeni arenalar açılır. Sezon süresi ve ödül yolu Luno Pass ekranındaki sayaçtan takip edilir.')+
      guideSection(A.guideEconomy,'ALTIN, ELMAS VE ÖDÜLLER','<b>Altın</b> geliştirme ve oyun içi satın alımlarda kullanılır. <b>Elmas</b> daha nadir teklifler ve premium içerikler içindir. Görev, sandık, sezon yolu ve mağaza paketlerinin ödülleri birbirinden farklıdır; satın almadan önce içerik satırını kontrol et.')+
      guideSection(A.guidePass,'LUNO PASS','Luno Pass <b>30 seviyelik</b> bir sezon yoludur. Ücretsiz şerit herkese açıktır; Premium şerit ek ödüller ve sezon avantajları verir. Kazandığın Pass ilerlemesini ödül satırından tek tek toplarsın.')+
      guideSection(A.guideMissions,'GÖREVLER','Günlük, haftalık ve özel görevler farklı sayaçlara sahiptir. Şart tamamlandığında görev kartındaki <b>AL</b> düğmesine basmadan ödül hesaba eklenmez. Yenilenme sayacını kaçırmadan tamamlananları topla.')+
      guideSection(A.guideCostumes,'KOSTÜMLER','Kostümler taşların tahta üzerindeki görünümünü değiştirir; satranç hareketlerini veya kart gücünü değiştirmez. Set seçerken bütün taşların aynı temada ve karelere rahat oturduğunu önizlemeden kontrol et.')+
      guideSection(A.guideFriends,'ARKADAŞLAR VE SOHBET','Kullanıcı adıyla arkadaş ara; gelen isteği kabul et veya reddet. Arkadaş satırından özel mesaj gönderebilir, savaşa davet edebilir ya da arkadaşlıktan çıkarabilirsin.')+
      guideSection(A.guideProfile,'PROFİL VE KOLEKSİYON PUANI','Profil; kupa, galibiyet, oran, seri, lig ve başarımlarını gösterir. <b>Koleksiyon puanı</b> sahip olduğun nadir kozmetiklerin değerinden oluşur; ücretsiz klasik parçalar puanı şişirmez.')+
      guideSection(A.guideTips,'KISA TAKTİKLER','Şah güvenliğini karttan önce düşün. Erken rok yap, merkez karelerini kontrol et ve rakibin mana sayacını izle. Sis, Radar ve gizli tuzaklar bilgi savaşıdır; pahalı kartı yalnızca net bir konum üstünlüğü üretiyorsa kullan.')+
    '</div>';
  }

  function installGuideContent(){
    if(typeof OV==='undefined'||!OV.guide)return;
    OV.guide.t='LUNO REHBERİ';
    OV.guide.html=buildLunoGuideHtml();
  }

  function polishGuideDom(){
    var body=document.getElementById('ovBody');
    if(body&&body.querySelector('.luno-guide-wrap'))body.classList.add('is-luno-guide');
  }

  function installCountryFlagImages(){
    if(typeof window.flagEmoji!=='function'||window.flagEmoji.__lunoFlagArt)return;
    var flagArt=function(iso){
      iso=String(iso||'TR').toLowerCase();
      if(!/^[a-z]{2}$/.test(iso))iso='tr';
      return '<img class="luno-country-flag" src="'+BASE+'flags-v7/'+iso+'.svg" alt="'+iso.toUpperCase()+'">';
    };
    flagArt.__lunoFlagArt=true;
    window.flagEmoji=flagArt;
  }

  function polishProfileEditDom(){
    var body=document.getElementById('ovBody');
    var wrap=body&&body.querySelector('.pe-wrap');
    if(!body||!wrap)return;
    body.classList.add('is-luno-profile-edit');
    setLunoImage(wrap.querySelector('.pe-photo-upload .pe-photo-ic'),A.profileGallery,'luno-profile-edit-action-art');
    setLunoImage(wrap.querySelector('.pe-photo-remove .pe-photo-ic'),A.profilePhotoRemove,'luno-profile-edit-action-art');
    var changeButtons=wrap.querySelectorAll('button');
    changeButtons.forEach(function(button){if((button.textContent||'').trim()==='DEĞİŞTİR')button.classList.add('luno-profile-name-change');});
    var countryLabel=Array.from(wrap.querySelectorAll('.pe-label')).find(function(label){return (label.textContent||'').trim()==='ÜLKE';});
    if(countryLabel&&!countryLabel.querySelector('.luno-profile-country-art'))countryLabel.prepend(lunoDomImage(A.profileCountry,'luno-profile-country-art'));
    var avatarDefs=[
      ['av_pawn','Piyon'],['av_knight','At'],['av_bishop','Fil'],['av_rook','Kale'],
      ['av_queen','Vezir'],['av_king','Şah'],['av_robot','Robot'],['av_robotcrown','Robot Kral'],
      ['av_crown','Taç'],['av_lightning','Şimşek'],['av_fire','Ateş']
    ];
    wrap.querySelectorAll('.pe-avatar-opt').forEach(function(option,index){
      var def=avatarDefs[index];
      if(!def)return;
      option.dataset.avatarIcon=def[0];
      option.setAttribute('aria-label',def[1]);
      option.title=def[1];
      if(!option.querySelector('.luno-avatar-option-name')){
        var label=document.createElement('span');
        label.className='luno-avatar-option-name';
        label.textContent=def[1];
        option.appendChild(label);
      }
      option.classList.toggle('pe-a-sel',window.PLAYER&&PLAYER.profile&&PLAYER.profile.avatarEmoji===def[0]);
    });
    var save=wrap.querySelector('.pe-save');
    if(save){var saveIcon=save.querySelector('span');if(saveIcon)setLunoImage(saveIcon,A.profileSave,'luno-profile-save-art');}
  }

  function patchGuideAndProfileEditExperience(){
    installGuideContent();
    installCountryFlagImages();
    installAvatarArt();
    if(typeof window.openOverlay==='function'&&!window.openOverlay.__lunoGuidePolish){
      var originalOpenOverlay=window.openOverlay;
      window.openOverlay=function(){installGuideContent();var result=originalOpenOverlay.apply(this,arguments);polishGuideDom();setTimeout(polishGuideDom,0);return result;};
      window.openOverlay.__lunoGuidePolish=true;
    }
    if(typeof window.editProfile==='function'&&!window.editProfile.__lunoProfileEditPolish){
      var originalEditProfile=window.editProfile;
      window.editProfile=function(){installCountryFlagImages();var result=originalEditProfile.apply(this,arguments);polishProfileEditDom();setTimeout(polishProfileEditDom,0);return result;};
      window.editProfile.__lunoProfileEditPolish=true;
    }
    if(typeof window.selectProfileAvatar==='function'&&!window.selectProfileAvatar.__lunoAvatarV9){
      var originalSelectAvatar=window.selectProfileAvatar;
      window.selectProfileAvatar=function(icon){
        var result=originalSelectAvatar.apply(this,arguments);
        document.querySelectorAll('.pe-avatar-opt').forEach(function(option){
          option.classList.toggle('pe-a-sel',option.dataset.avatarIcon===icon);
        });
        return result;
      };
      window.selectProfileAvatar.__lunoAvatarV9=true;
    }
  }

  function installMainMenuLuno(){
    if(window.LUNO_MENU_MOTION_OWNER)return;
    window.LUNO_MENU_MOTION_OWNER='image-art-v10';
    try{if(typeof window.lunoStopLegacyMenuMotion==='function')window.lunoStopLegacyMenuMotion();}catch(e){}
    var poses={
      idle:A.menuLunoIdle,
      wave:A.menuLunoWave,
      talk:A.menuLunoTalk,
      point:A.menuLunoPoint,
      blink:A.menuLunoBlink
    };
    var messages=[
      'Ho&#351; geldin, H&uuml;k&uuml;mdar! &#9819;',
      'Bug&uuml;n arenada bir ma&ccedil; yapal&#305;m m&#305;?',
      'Mana bar&#305;n&#305; izle, do&#287;ru an&#305; bekle.',
      'G&ouml;revlerde yeni &ouml;d&uuml;ller olabilir.',
      'Tahtan haz&#305;r. Stratejini g&ouml;relim!',
      'Luno Pass yolunda ilerlemeyi unutma.',
      '&#350;ah&#305;n&#305; koru, sonra sald&#305;r!'
    ];
    var poseCache={};
    Object.keys(poses).forEach(function(name){
      var image=new Image();
      image.decoding='async';
      image.src=poses[name];
      poseCache[name]=image;
    });
    var messageIndex=0;
    var poseIndex=0;
    var settleTimer=0;
    var messageTimer=0;
    var blinkTimer=0;
    var ambientTimer=0;

    function menuIsActive(){
      var menu=document.getElementById('menu');
      return !document.hidden&&menu&&menu.classList.contains('active');
    }
    function setPose(name){
      var mascot=document.getElementById('mnLunoImg');
      if(!mascot||!poses[name])return;
      if(poseCache[name]&&!poseCache[name].complete)return;
      prepareImage(mascot,true);
      mascot.src=poses[name];
      mascot.dataset.menuPose=name;
    }
    function scheduleBlink(){
      clearTimeout(blinkTimer);
      blinkTimer=0;
      if(!menuIsActive()||window.lunoGraphicsMode==='low')return;
      blinkTimer=setTimeout(function(){
        var mascot=document.getElementById('mnLunoImg');
        var live=document.getElementById('mnLunoLive');
        if(menuIsActive()&&mascot&&live&&!live.classList.contains('is-talking')&&!live.classList.contains('is-waving')&&!live.classList.contains('is-pointing')){
          setPose('blink');
          setTimeout(function(){
            var current=document.getElementById('mnLunoLive');
            if(current&&!current.classList.contains('is-talking')&&!current.classList.contains('is-waving')&&!current.classList.contains('is-pointing'))setPose('idle');
          },145);
        }
        scheduleBlink();
      },3600+Math.floor(Math.random()*2200));
    }
    function scheduleTalk(){
      clearTimeout(ambientTimer);
      ambientTimer=0;
      if(!menuIsActive())return;
      ambientTimer=setTimeout(function(){
        if(menuIsActive())window.mnLunoTalk(false);
      },7600+Math.floor(Math.random()*1800));
    }
    function stopMotion(){
      clearTimeout(settleTimer);clearTimeout(messageTimer);clearTimeout(blinkTimer);clearTimeout(ambientTimer);
      settleTimer=0;messageTimer=0;blinkTimer=0;ambientTimer=0;
    }
    function syncMotion(){
      if(window.LUNO_MENU_MOTION_OWNER!=='image-art-v10'){
        stopMotion();
        return;
      }
      if(!menuIsActive()){
        stopMotion();
        return;
      }
      setPose('idle');
      scheduleBlink();
      scheduleTalk();
    }
    window.lunoStopMenuLunoMotion=stopMotion;
    window.mnLunoTalk=function(user){
      if(!menuIsActive()&&!user)return;
      var live=document.getElementById('mnLunoLive');
      var bubble=document.getElementById('mnLunoBubble');
      if(!live||!bubble)return;

      clearTimeout(settleTimer);
      clearTimeout(messageTimer);
      clearTimeout(ambientTimer);
      ambientTimer=0;
      live.classList.remove('is-talking','is-waving','is-pointing');

      var pose=user?'wave':(poseIndex++%2?'point':'talk');
      setPose(pose);
      live.classList.add(pose==='wave'?'is-waving':(pose==='point'?'is-pointing':'is-talking'));
      bubble.style.opacity='0';

      messageTimer=setTimeout(function(){
        messageIndex=(messageIndex+1)%messages.length;
        bubble.innerHTML=messages[messageIndex];
        bubble.style.opacity='1';
        live.classList.add('bubble-pop');
        setTimeout(function(){live.classList.remove('bubble-pop');},360);
      },150);

      settleTimer=setTimeout(function(){
        setPose(user?'talk':'idle');
        live.classList.remove('is-waving','is-pointing');
        live.classList.add('is-talking');
        settleTimer=setTimeout(function(){
          setPose('idle');
          live.classList.remove('is-talking');
          scheduleTalk();
        },user?650:350);
      },user?480:850);

      try{if(user&&typeof sndUiClick==='function')sndUiClick();}catch(e){}
    };
    window.addEventListener('luno:screen-change',syncMotion);
    window.addEventListener('luno:graphics-mode',syncMotion);
    document.addEventListener('visibilitychange',syncMotion,{passive:true});
    window.addEventListener('pagehide',stopMotion,{once:true});
    syncMotion();
  }

  var collectionGroupArt={
    none:A.collectionCards,
    tuzak:BASE+'card-trap1-v10-mobile.webp',
    radar:BASE+'card-radar1-v10-mobile.webp',
    direnis:BASE+'card-resist1-v10-mobile.webp',
    sefer:BASE+'card-deploy1-v10-mobile.webp',
    kalkan:BASE+'card-shield1-v10-mobile.webp'
  };

  function setCollectionMode(mode){
    var body=document.getElementById('ovBody');
    if(!body)return null;
    body.classList.remove('is-luno-collection-hub','is-luno-deck-editor','is-luno-card-collection');
    if(mode)body.classList.add(mode);
    return body;
  }

  function cardKeyFromArt(node){
    if(!node||!window.CARD_IMG)return '';
    var source=(node.style.backgroundImage||'').replace(/\\/g,'/');
    var keys=Object.keys(CARD_IMG);
    for(var i=0;i<keys.length;i++){
      var path=String(CARD_IMG[keys[i]]||'').replace(/\\/g,'/');
      if(path&&source.indexOf(path)>=0)return keys[i];
    }
    return '';
  }

  function polishCardMinis(scope){
    if(!scope)return;
    scope.querySelectorAll('.cardmini').forEach(function(card){
      var art=card.querySelector('.kc-cimg');
      var key=cardKeyFromArt(art);
      if(key)card.dataset.cardKey=key;
      var name=card.querySelector('.ds-name');
      if(name){
        card.setAttribute('aria-label',name.textContent.trim());
        name.setAttribute('title',name.textContent.trim());
      }
      var mana=card.querySelector('.cmana');
      if(mana&&!mana.querySelector('.luno-card-mana-art')){
        var amount=(mana.textContent||'0').trim();
        mana.innerHTML='<img class="luno-card-mana-art" src="'+A.mana+'" alt=""><span>'+amount+'</span>';
      }
      var selected=card.querySelector('.pool-check');
      if(selected){
        selected.innerHTML='<img class="luno-card-selected-art" src="'+A.cardSelected+'" alt="Seçili">';
        selected.setAttribute('aria-label','Destede');
      }
    });
  }

  function addCollectionHeadingArt(scope,selector){
    if(!scope)return;
    var labelToGroup={
      'TEMEL KARTLAR':'none',
      'TUZAK':'tuzak',
      'RADAR':'radar',
      'DİRENİŞ':'direnis',
      'SEFER':'sefer',
      'KALKAN':'kalkan'
    };
    scope.querySelectorAll(selector).forEach(function(head){
      var labelNode=head.querySelector('.kc-sh-label');
      var label=(labelNode?labelNode.textContent:head.textContent).trim().toLocaleUpperCase('tr-TR');
      var group=labelToGroup[label]||'none';
      head.dataset.cardGroup=group;
      if(!head.querySelector('.luno-card-family-art')){
        var img=document.createElement('img');
        img.className='luno-card-family-art';
        img.src=collectionGroupArt[group];
        img.alt='';
        head.insertBefore(img,head.firstChild);
      }
    });
  }

  function polishCollectionHubDom(){
    var body=setCollectionMode('is-luno-collection-hub');
    if(!body)return;
    var wrap=body.querySelector('.ch-wrap');
    if(!wrap)return;
    wrap.querySelectorAll('.ch-card').forEach(function(card,index){
      card.dataset.collectionKind=['deck','cards','costumes','emojis'][index]||'item';
      var image=card.querySelector('.ch-icimg');
      if(image)image.alt='';
    });
  }

  function polishDeckDom(){
    var body=setCollectionMode('is-luno-deck-editor');
    if(!body)return;
    var badge=body.querySelector('.deck-arena-badge');
    if(badge&&!badge.dataset.lunoV10){
      var arenaName=(badge.querySelector('.dab-name')||{}).textContent||'';
      var trophyText=(badge.querySelector('.dab-trophy')||{}).textContent||'0';
      var trophyValue=(trophyText.match(/[\d.]+/)||['0'])[0];
      badge.innerHTML='<img class="luno-deck-badge-art" src="'+A.collectionDeck+'" alt="">'+
        '<div class="luno-deck-badge-copy"><span>AKTİF ARENA</span><b>'+arenaName+'</b></div>'+
        '<div class="dab-trophy"><img src="'+A.trophy+'" alt=""><strong>'+trophyValue+'</strong></div>';
      badge.dataset.lunoV10='1';
    }
    var hint=body.querySelector('.deck-hint');
    if(hint){
      var deck=window.PLAYER&&PLAYER.deck?PLAYER.deck:[];
      var sum=0;
      deck.forEach(function(key){sum+=(window.CARDS&&CARDS[key]&&CARDS[key].mana)||0;});
      var average=deck.length?(sum/deck.length).toFixed(1):'0.0';
      hint.innerHTML='<img src="'+A.mana+'" alt=""><span><b>6 KARTLIK DESTE</b><small>ORT. MANA '+average+'</small></span>';
    }
    var title=body.querySelector('.deck-pool-title');
    if(title&&!title.querySelector('img'))title.innerHTML='<img src="'+A.collectionCards+'" alt=""><span>KART HAVUZU</span>';
    body.querySelectorAll('.pool-group-head').forEach(function(head){
      var label=head.textContent.trim().toLocaleUpperCase('tr-TR');
      var group=label==='TEMEL KARTLAR'?'none':(label==='TUZAK'?'tuzak':(label==='RADAR'?'radar':(label==='DİRENİŞ'?'direnis':(label==='SEFER'?'sefer':'kalkan'))));
      head.dataset.cardGroup=group;
      if(!head.querySelector('img'))head.innerHTML='<img class="luno-card-family-art" src="'+collectionGroupArt[group]+'" alt=""><span>'+head.textContent+'</span>';
    });
    polishCardMinis(body);
  }

  function polishCardCollectionDom(){
    var body=setCollectionMode('is-luno-card-collection');
    if(!body)return;
    var progress=body.querySelector('.kc-progress-pill');
    if(progress&&!progress.dataset.lunoV10){
      var value=(progress.querySelector('.kc-pp-val')||{}).textContent||'0 / 29';
      progress.innerHTML='<img class="luno-card-progress-art" src="'+A.collectionCards+'" alt="">'+
        '<div class="luno-card-progress-copy"><div class="kc-pp-val">'+value+'</div><div class="kc-pp-lbl">KART AÇILDI</div></div>';
      progress.dataset.lunoV10='1';
    }
    addCollectionHeadingArt(body,'.kc-section-head');
    var banner=body.querySelector('.kc-upg-banner');
    if(banner){
      var old=banner.querySelector('.kc-upg-ic');
      if(old)old.innerHTML='<img class="luno-card-upgrade-art" src="'+A.cardUpgrade+'" alt="">';
    }
    polishCardMinis(body);
  }

  function polishCardActionDom(key){
    var box=document.querySelector('#cardActMenu .cam-box,#cardActionOv .cam-box');
    if(!box)return;
    box.classList.add('is-luno-card-detail-v10');
    var card=window.CARDS&&CARDS[key];
    var cost=box.querySelector('.cam-cost');
    if(cost&&card){
      var notes=[];
      if(card.up)notes.push('GÜÇLENDİRİLEBİLİR');
      if(card.hidden)notes.push('GİZLİ');
      cost.innerHTML='<img src="'+A.mana+'" alt=""><b>'+(card.mana||0)+' MANA</b>'+(notes.length?'<span>'+notes.join(' · ')+'</span>':'');
    }
    var detailButton=box.querySelector('.cam-detail');
    if(detailButton&&!detailButton.querySelector('img'))detailButton.innerHTML='<img class="luno-card-guide-art" src="'+A.guide+'" alt=""><span>ÖZELLİKLER · NASIL OYNANIR</span>';
    var close=box.querySelector('.cam-close');
    if(close){close.textContent='×';close.setAttribute('aria-label','Kapat');close.title='Kapat';}
  }

  function patchCollectionExperience(){
    setCardArt();
    var hub=window.openCollectionHub;
    if(typeof hub==='function'&&!hub.__lunoV10){
      window.openCollectionHub=function(){var result=hub.apply(this,arguments);polishCollectionHubDom();return result;};
      window.openCollectionHub.__lunoV10=true;
    }
    var deck=window.openDeckEditor;
    if(typeof deck==='function'&&!deck.__lunoV10){
      window.openDeckEditor=function(){var result=deck.apply(this,arguments);polishDeckDom();setTimeout(polishDeckDom,0);return result;};
      window.openDeckEditor.__lunoV10=true;
    }
    var render=window.renderDeckPanel;
    if(typeof render==='function'&&!render.__lunoV10){
      window.renderDeckPanel=function(){var result=render.apply(this,arguments);polishDeckDom();return result;};
      window.renderDeckPanel.__lunoV10=true;
    }
    var cards=window.openCardCollection;
    if(typeof cards==='function'&&!cards.__lunoV10){
      window.openCardCollection=function(){var result=cards.apply(this,arguments);polishCardCollectionDom();setTimeout(polishCardCollectionDom,0);return result;};
      window.openCardCollection.__lunoV10=true;
    }
    var action=window.showCardActionMenu;
    if(typeof action==='function'&&!action.__lunoV10){
      window.showCardActionMenu=function(key){var result=action.apply(this,arguments);polishCardActionDom(key);setTimeout(function(){polishCardActionDom(key);},0);return result;};
      window.showCardActionMenu.__lunoV10=true;
    }
  }

  function applyResultArt(){
    var glyph=document.getElementById('resGlyph');
    var title=document.getElementById('resTitle');
    if(!glyph||!title)return;
    var text=(title.textContent||'').toLocaleUpperCase('tr-TR');
    var won=text.indexOf('ZAFER')>=0||text.indexOf('KAZANDI')>=0||text.indexOf('VICTORY')>=0||text.indexOf('WON')>=0;
    var lost=text.indexOf('YENİLGİ')>=0||text.indexOf('DEFEAT')>=0||text.indexOf('LOST')>=0;
    var src=won?A.resultVictory:(lost?A.resultDefeat:A.resultDraw);
    glyph.innerHTML='<img class="luno-result-icon" src="'+src+'" alt="">';
  }

  function patchEndGame(){
    var original=window.endGame;
    if(typeof original!=='function'||original.__lunoArtSafe)return;
    window.endGame=function(){
      var out=original.apply(this,arguments);
      setTimeout(applyResultArt,950);
      return out;
    };
    window.endGame.__lunoArtSafe=true;
  }

  var screenCss=document.createElement('style');
  screenCss.id='luno-rank-guide-profile-v7';
  screenCss.textContent=[
    '.luno-country-flag{display:block;width:24px;height:18px;object-fit:cover;border:1px solid rgba(255,255,255,.36);border-radius:3px;box-shadow:0 1px 3px rgba(0,0,0,.35);}',
    '.pe-prev-flag .luno-country-flag,.mp-av-flag .luno-country-flag{width:30px;height:22px;border:0;border-radius:2px;box-shadow:none;}.pf2-pill-ic .luno-country-flag{width:22px;height:16px;}',
    '#ovBody.is-luno-ranking{padding-bottom:18px!important;}#ovBody.is-luno-ranking .rk-tabs{display:grid!important;grid-template-columns:repeat(2,minmax(0,1fr))!important;gap:7px!important;margin:0 0 10px!important;}',
    '#ovBody.is-luno-ranking .rk-tab{display:grid!important;grid-template-columns:44px minmax(0,1fr)!important;align-items:center!important;justify-items:start!important;gap:5px!important;min-height:62px!important;padding:6px 12px!important;border:1px solid rgba(126,111,171,.52)!important;border-radius:8px!important;background:linear-gradient(145deg,#28204a,#153b49)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.09),0 3px 8px rgba(0,0,0,.28)!important;font-family:Cinzel,Georgia,serif!important;font-size:10px!important;line-height:14px!important;font-weight:900!important;letter-spacing:0!important;color:#ddd2e7!important;text-shadow:0 1px 2px rgba(0,0,0,.6)!important;}',
    '#ovBody.is-luno-ranking .rk-tab-on{border-color:rgba(246,207,91,.72)!important;background:linear-gradient(145deg,#5b4027,#3a2856 60%,#174f58)!important;color:#ffe284!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.13),0 4px 10px rgba(0,0,0,.31),0 0 10px rgba(240,198,77,.15)!important;}#ovBody.is-luno-ranking .luno-rank-tab-art{display:block;width:44px;height:44px;object-fit:contain;}',
    '#ovBody.is-luno-ranking .rk-myrank{display:grid!important;grid-template-columns:minmax(0,1fr) auto!important;align-items:center!important;min-height:54px!important;margin:0 0 10px!important;padding:7px 12px!important;border:1px solid rgba(92,213,201,.45)!important;border-radius:8px!important;background:linear-gradient(145deg,#174855,#35264e 72%)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.09),0 3px 8px rgba(0,0,0,.28)!important;}',
    '#ovBody.is-luno-ranking .rk-myrank-label{font-family:Cinzel,Georgia,serif!important;font-size:9px!important;line-height:12px!important;font-weight:900!important;letter-spacing:0!important;color:#77ded2!important;}#ovBody.is-luno-ranking .rk-myrank-val{padding:5px 8px!important;border:1px solid rgba(245,207,91,.46)!important;border-radius:6px!important;background:#2b2146!important;background-image:none!important;background-clip:border-box!important;-webkit-background-clip:border-box!important;-webkit-text-fill-color:#ffe187!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:16px!important;line-height:20px!important;font-weight:900!important;letter-spacing:0!important;color:#ffe187!important;text-shadow:0 1px 2px rgba(0,0,0,.62)!important;}',
    '#ovBody.is-luno-ranking .rk-podium-bg{position:relative!important;min-height:278px!important;margin:0 0 13px!important;padding:8px 7px 0!important;border:1px solid rgba(246,211,116,.58)!important;border-radius:8px!important;background-color:#18152c!important;background-image:linear-gradient(180deg,rgba(10,10,26,.06),rgba(10,8,27,.18)),var(--luno-rank-backdrop)!important;background-position:center!important;background-size:cover!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.12),0 5px 13px rgba(0,0,0,.34)!important;overflow:hidden!important;}#ovBody.is-luno-ranking .rk-podium-stars{display:none!important;}',
    '#ovBody.is-luno-ranking .rk-podium-title{display:flex!important;align-items:center!important;justify-content:center!important;gap:7px!important;min-height:34px!important;margin:0 0 5px!important;padding:2px 8px!important;border-radius:6px!important;background:rgba(20,24,39,.72)!important;font-family:Cinzel,Georgia,serif!important;font-size:11px!important;line-height:15px!important;font-weight:900!important;letter-spacing:0!important;color:#fff0c5!important;text-shadow:0 2px 3px rgba(0,0,0,.7)!important;}#ovBody.is-luno-ranking .luno-rank-title-star{display:block;width:27px;height:27px;object-fit:contain;}',
    '#ovBody.is-luno-ranking .rk-podium{display:grid!important;grid-template-columns:repeat(3,minmax(0,1fr))!important;align-items:end!important;gap:3px!important;min-height:226px!important;padding:0 1px!important;}#ovBody.is-luno-ranking .rk-pod-col{min-width:0!important;}#ovBody.is-luno-ranking .rk-pod-avatar{width:52px!important;height:52px!important;margin-bottom:5px!important;border:1px solid rgba(255,255,255,.32)!important;border-radius:8px!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.18),0 4px 10px rgba(0,0,0,.48)!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;}#ovBody.is-luno-ranking .rk-avatar-1{width:61px!important;height:61px!important;}',
    '#ovBody.is-luno-ranking .rk-crown{display:flex!important;width:66px!important;height:45px!important;align-items:center!important;justify-content:center!important;margin:0 auto -1px!important;font-size:0!important;filter:none!important;animation:none!important;}#ovBody.is-luno-ranking .luno-rank-crown-art{display:block;width:66px;height:66px;object-fit:contain;}',
    '#ovBody.is-luno-ranking .rk-pod-medal{display:flex!important;width:28px!important;height:28px!important;align-items:center!important;justify-content:center!important;right:-7px!important;bottom:-6px!important;border:0!important;border-radius:50%!important;background:#172f3d!important;box-shadow:0 2px 5px rgba(0,0,0,.5)!important;}#ovBody.is-luno-ranking .rk-medal-1{width:31px!important;height:31px!important;}#ovBody.is-luno-ranking .luno-rank-medal-art{display:block;width:31px;height:31px;object-fit:contain;}',
    '#ovBody.is-luno-ranking .rk-pod-name{max-width:100%!important;margin:0 0 2px!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:10px!important;line-height:13px!important;font-weight:900!important;letter-spacing:0!important;color:#fff1df!important;text-transform:none!important;}#ovBody.is-luno-ranking .rk-name-1{font-size:11px!important;color:#ffe181!important;}',
    '#ovBody.is-luno-ranking .rk-pod-trophies,#ovBody.is-luno-ranking .rk-row-trophies{display:flex!important;align-items:center!important;justify-content:center!important;gap:4px!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-weight:900!important;letter-spacing:0!important;color:#ffe18a!important;white-space:nowrap!important;}#ovBody.is-luno-ranking .rk-pod-trophies{min-height:19px!important;margin-bottom:2px!important;font-size:9px!important;}#ovBody.is-luno-ranking[data-luno-rank-mode="collection"] .rk-pod-trophies,#ovBody.is-luno-ranking[data-luno-rank-mode="collection"] .rk-row-trophies{color:#8be3d5!important;}',
    '#ovBody.is-luno-ranking .luno-rank-metric-art{display:block;width:18px;height:18px;object-fit:contain;flex:0 0 18px;}#ovBody.is-luno-ranking[data-luno-rank-mode="collection"] .luno-rank-metric-art{width:22px;height:22px;flex-basis:22px;}#ovBody.is-luno-ranking .luno-rank-metric-value{display:block;}',
    '#ovBody.is-luno-ranking .rk-pod-base{display:flex!important;width:112%!important;align-items:center!important;justify-content:center!important;margin:0 -6%!important;padding:0 0 4px!important;border:0!important;border-radius:0!important;background:var(--luno-rank-base) center bottom/100% 100% no-repeat!important;box-shadow:none!important;overflow:visible!important;}#ovBody.is-luno-ranking .rk-pod-base::before{display:none!important;}#ovBody.is-luno-ranking .rk-base-1{height:69px!important;}#ovBody.is-luno-ranking .rk-base-2{height:55px!important;}#ovBody.is-luno-ranking .rk-base-3{height:47px!important;}',
    '#ovBody.is-luno-ranking .rk-pod-rank{font-family:Cinzel,Georgia,serif!important;font-size:22px!important;line-height:28px!important;font-weight:900!important;letter-spacing:0!important;color:#2a2142!important;text-shadow:0 1px 0 rgba(255,255,255,.65)!important;}#ovBody.is-luno-ranking .rk-base-1 .rk-pod-rank{font-size:27px!important;color:#3a2516!important;}',
    '#ovBody.is-luno-ranking .rk-list-title{display:flex!important;min-height:25px!important;align-items:center!important;justify-content:center!important;margin:0 0 7px!important;font-family:Cinzel,Georgia,serif!important;font-size:9px!important;line-height:13px!important;font-weight:900!important;letter-spacing:0!important;color:#ddd1e7!important;}#ovBody.is-luno-ranking .rk-list{display:flex!important;flex-direction:column!important;gap:6px!important;}',
    '#ovBody.is-luno-ranking .rk-row{display:grid!important;grid-template-columns:30px 38px minmax(0,1fr) auto!important;align-items:center!important;gap:7px!important;min-height:62px!important;padding:6px 8px!important;border:1px solid rgba(91,203,194,.3)!important;border-radius:8px!important;background:linear-gradient(145deg,#173d4b,#292047 78%)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.07),0 3px 7px rgba(0,0,0,.25)!important;}#ovBody.is-luno-ranking .rk-row-me{border-color:rgba(246,204,86,.65)!important;background:linear-gradient(145deg,#4c3b2a,#39234b 74%)!important;}',
    '#ovBody.is-luno-ranking .rk-row-rank{display:flex!important;width:30px!important;height:28px!important;align-items:center!important;justify-content:center!important;border:1px solid rgba(255,255,255,.13)!important;border-radius:6px!important;background:#201a38!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:10px!important;line-height:13px!important;font-weight:900!important;letter-spacing:0!important;color:#d9cede!important;}#ovBody.is-luno-ranking .rk-row-avatar{display:flex!important;width:38px!important;height:38px!important;align-items:center!important;justify-content:center!important;border:1px solid rgba(255,255,255,.18)!important;border-radius:7px!important;font-size:17px!important;box-shadow:0 2px 5px rgba(0,0,0,.35)!important;}',
    '#ovBody.is-luno-ranking .rk-row-info{min-width:0!important;}#ovBody.is-luno-ranking .rk-row-name{margin:0 0 2px!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:11.5px!important;line-height:15px!important;font-weight:900!important;letter-spacing:0!important;color:#fff0dc!important;text-transform:none!important;white-space:nowrap!important;overflow:hidden!important;text-overflow:ellipsis!important;}#ovBody.is-luno-ranking .rk-row-arena{font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:7.5px!important;line-height:10px!important;font-weight:700!important;letter-spacing:0!important;color:#aeb3c6!important;text-transform:uppercase!important;white-space:nowrap!important;overflow:hidden!important;text-overflow:ellipsis!important;}#ovBody.is-luno-ranking .rk-row-trophies{font-size:10.5px!important;}',
    '#ovBody.is-luno-guide .luno-guide-wrap{display:flex;flex-direction:column;gap:8px;width:100%;padding:1px 0 16px;}#ovBody.is-luno-guide .gd-sec{display:grid!important;grid-template-columns:58px minmax(0,1fr)!important;align-items:start!important;gap:8px!important;min-height:78px!important;margin:0!important;padding:8px 10px 9px 6px!important;border:1px solid rgba(93,204,195,.31)!important;border-radius:8px!important;background:linear-gradient(145deg,#173d49,#292044 78%)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.07),0 3px 7px rgba(0,0,0,.24)!important;}#ovBody.is-luno-guide .gd-sec:nth-child(3n+2){border-color:rgba(238,194,83,.34)!important;background:linear-gradient(145deg,#4c3828,#302044 78%)!important;}#ovBody.is-luno-guide .gd-sec:nth-child(3n){border-color:rgba(222,111,126,.31)!important;background:linear-gradient(145deg,#56313d,#243248 78%)!important;}',
    '#ovBody.is-luno-guide .luno-guide-icon{display:block;width:56px;height:56px;object-fit:contain;filter:drop-shadow(0 3px 4px rgba(0,0,0,.38));}#ovBody.is-luno-guide .luno-guide-copy{min-width:0;padding-top:2px;}#ovBody.is-luno-guide .gd-h{margin:0 0 4px!important;font-family:Cinzel,Georgia,serif!important;font-size:10.5px!important;line-height:14px!important;font-weight:900!important;letter-spacing:0!important;color:#ffe183!important;text-shadow:0 1px 2px rgba(0,0,0,.6)!important;}#ovBody.is-luno-guide .gd-p{margin:0!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:10.5px!important;line-height:15px!important;font-weight:600!important;letter-spacing:0!important;color:#e5dce8!important;}#ovBody.is-luno-guide .gd-p b{font-weight:900!important;color:#8ee0d4!important;}',
    '#ovBody.is-luno-profile-edit .pe-wrap{display:flex!important;flex-direction:column!important;gap:0!important;width:100%!important;padding:1px 0 18px!important;}#ovBody.is-luno-profile-edit .pe-preview{padding:14px 12px 13px!important;margin:0 0 13px!important;border:1px solid rgba(244,204,87,.58)!important;border-radius:8px!important;background:linear-gradient(145deg,#174551,#39244e 70%,#5a3541)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.11),0 5px 11px rgba(0,0,0,.3)!important;}#ovBody.is-luno-profile-edit .pe-prev-avatar{width:82px!important;height:82px!important;margin-bottom:8px!important;border:2px solid #e5bd55!important;box-shadow:inset 0 2px 7px rgba(0,0,0,.38),0 4px 9px rgba(0,0,0,.38)!important;animation:none!important;}#ovBody.is-luno-profile-edit .pe-prev-name{margin:0 0 2px!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:17px!important;line-height:22px!important;font-weight:900!important;letter-spacing:0!important;color:#fff0da!important;}#ovBody.is-luno-profile-edit .pe-prev-country{font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:9px!important;line-height:12px!important;font-weight:800!important;letter-spacing:0!important;color:#8edfd4!important;text-transform:uppercase!important;}',
    '#ovBody.is-luno-profile-edit .pe-field{margin:0!important;padding:10px 1px 12px!important;border-bottom:1px solid rgba(114,96,154,.22)!important;}#ovBody.is-luno-profile-edit .pe-label{display:flex!important;align-items:center!important;gap:6px!important;margin:0 0 7px!important;font-family:Cinzel,Georgia,serif!important;font-size:9px!important;line-height:12px!important;font-weight:900!important;letter-spacing:0!important;color:#ffe189!important;text-shadow:0 1px 2px rgba(0,0,0,.5)!important;}#ovBody.is-luno-profile-edit .luno-profile-country-art{display:block;width:25px;height:25px;object-fit:contain;}',
    '#ovBody.is-luno-profile-edit .pe-photo-options{display:flex!important;flex-direction:column!important;gap:7px!important;}#ovBody.is-luno-profile-edit .pe-photo-btn{display:grid!important;grid-template-columns:52px minmax(0,1fr)!important;align-items:center!important;gap:8px!important;min-height:62px!important;padding:5px 9px 5px 5px!important;border:1px solid rgba(93,214,200,.46)!important;border-radius:8px!important;background:linear-gradient(145deg,#174651,#2c2148)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.08),0 3px 7px rgba(0,0,0,.25)!important;}#ovBody.is-luno-profile-edit .pe-photo-remove{border-color:rgba(230,101,116,.45)!important;background:linear-gradient(145deg,#59313d,#29203f)!important;}#ovBody.is-luno-profile-edit .pe-photo-ic{display:flex!important;width:52px!important;height:52px!important;align-items:center!important;justify-content:center!important;border:0!important;border-radius:0!important;background:transparent!important;font-size:0!important;}#ovBody.is-luno-profile-edit .luno-profile-edit-action-art{display:block;width:52px;height:52px;object-fit:contain;}#ovBody.is-luno-profile-edit .pe-photo-title{font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:12px!important;line-height:16px!important;font-weight:900!important;letter-spacing:0!important;color:#fff0dc!important;text-transform:none!important;}#ovBody.is-luno-profile-edit .pe-photo-sub{margin-top:2px!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:9px!important;line-height:12px!important;font-weight:600!important;color:#c9c1d3!important;text-transform:none!important;}',
    '#ovBody.is-luno-profile-edit .pe-input{min-height:47px!important;padding:10px 12px!important;border:1px solid rgba(102,200,193,.36)!important;border-radius:8px!important;background:linear-gradient(145deg,#172f42,#292044)!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:13px!important;line-height:18px!important;font-weight:700!important;letter-spacing:0!important;color:#fff0dc!important;box-shadow:inset 0 1px 3px rgba(0,0,0,.28)!important;}#ovBody.is-luno-profile-edit .pe-textarea{min-height:86px!important;line-height:19px!important;}#ovBody.is-luno-profile-edit .pe-bio-counter{margin-top:4px!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:9px!important;line-height:12px!important;letter-spacing:0!important;color:#bdb4c9!important;}#ovBody.is-luno-profile-edit .luno-profile-name-change{min-height:31px!important;padding:5px 10px!important;border:1px solid rgba(246,208,93,.58)!important;border-radius:7px!important;background:linear-gradient(180deg,#e6c25b,#a96d25)!important;font-family:Cinzel,Georgia,serif!important;font-size:8px!important;line-height:11px!important;font-weight:900!important;letter-spacing:0!important;color:#2b1935!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.3),0 2px 5px rgba(0,0,0,.3)!important;}',
    '#ovBody.is-luno-profile-edit .pe-bioframe-grid{display:grid!important;grid-template-columns:repeat(3,minmax(0,1fr))!important;gap:6px!important;margin-top:0!important;}#ovBody.is-luno-profile-edit .pe-bf-opt{min-width:0!important;min-height:73px!important;padding:6px 4px!important;border:1px solid rgba(109,193,186,.28)!important;border-radius:8px!important;background:linear-gradient(145deg,#173442,#29203f)!important;opacity:1!important;}#ovBody.is-luno-profile-edit .pe-bf-locked{filter:saturate(.68) brightness(.78)!important;}#ovBody.is-luno-profile-edit .pe-bf-sel{border-color:rgba(247,206,83,.72)!important;background:linear-gradient(145deg,#4b3b2b,#342246)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.1),0 0 8px rgba(240,199,72,.17)!important;}#ovBody.is-luno-profile-edit .pe-bf-prev{height:31px!important;border-radius:6px!important;}#ovBody.is-luno-profile-edit .pe-bf-name{font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:7.5px!important;line-height:10px!important;font-weight:800!important;letter-spacing:0!important;color:#e9dfe7!important;text-align:center!important;}#ovBody.is-luno-profile-edit .pe-bf-active,#ovBody.is-luno-profile-edit .pe-bf-lock{font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:6.5px!important;line-height:9px!important;letter-spacing:0!important;}',
    '#ovBody.is-luno-profile-edit .pe-country-grid{display:grid!important;grid-template-columns:repeat(3,minmax(0,1fr))!important;gap:5px!important;max-height:254px!important;padding:5px!important;border:1px solid rgba(100,205,195,.27)!important;border-radius:8px!important;background:#11152d!important;}#ovBody.is-luno-profile-edit .pe-country{display:grid!important;grid-template-columns:27px minmax(0,1fr)!important;align-items:center!important;gap:5px!important;min-width:0!important;min-height:42px!important;padding:5px!important;border:1px solid rgba(112,98,153,.43)!important;border-radius:7px!important;background:linear-gradient(145deg,#252044,#153743)!important;}#ovBody.is-luno-profile-edit .pe-c-sel{border-color:rgba(247,207,88,.78)!important;background:linear-gradient(145deg,#5a4129,#34234a)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.1),0 0 8px rgba(242,198,74,.2)!important;}#ovBody.is-luno-profile-edit .pe-c-flag{display:flex!important;width:27px!important;height:22px!important;align-items:center!important;justify-content:center!important;font-size:0!important;}#ovBody.is-luno-profile-edit .pe-c-flag .luno-country-flag{width:27px;height:20px;}#ovBody.is-luno-profile-edit .pe-c-name{font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:7.5px!important;line-height:10px!important;font-weight:800!important;letter-spacing:0!important;color:#eee2e8!important;white-space:normal!important;overflow:visible!important;text-overflow:clip!important;text-transform:none!important;}',
    '#ovBody.is-luno-profile-edit .pe-avatar-hint{margin:-3px 0 7px!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:8.5px!important;line-height:11px!important;font-weight:600!important;letter-spacing:0!important;color:#aaa4b8!important;font-style:normal!important;}#ovBody.is-luno-profile-edit .pe-avatar-grid{gap:5px!important;}#ovBody.is-luno-profile-edit .pe-avatar-opt{border:1px solid rgba(105,91,150,.48)!important;border-radius:7px!important;background:linear-gradient(145deg,#252044,#153643)!important;}#ovBody.is-luno-profile-edit .pe-a-sel{border-color:rgba(246,205,86,.8)!important;background:linear-gradient(145deg,#5a4027,#38244b)!important;box-shadow:0 0 8px rgba(240,198,75,.22)!important;transform:none!important;}#ovBody.is-luno-profile-edit .pe-color-grid{gap:7px!important;}#ovBody.is-luno-profile-edit .pe-color{border-width:2px!important;}#ovBody.is-luno-profile-edit .pe-col-sel{transform:none!important;box-shadow:0 0 0 2px #fff,0 0 9px rgba(255,255,255,.45)!important;}',
    '#ovBody.is-luno-profile-edit .pe-frame-grid{display:grid!important;grid-template-columns:repeat(4,minmax(0,1fr))!important;gap:6px!important;}#ovBody.is-luno-profile-edit .pe-frame-opt{min-width:0!important;min-height:91px!important;padding:6px 3px!important;border:1px solid rgba(110,95,153,.43)!important;border-radius:8px!important;background:linear-gradient(145deg,#252044,#15323f)!important;opacity:1!important;}#ovBody.is-luno-profile-edit .pe-frame-locked{filter:saturate(.62) brightness(.72)!important;}#ovBody.is-luno-profile-edit .pe-frame-name{font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:7px!important;line-height:9px!important;font-weight:800!important;letter-spacing:0!important;color:#e5dbe5!important;text-align:center!important;word-break:break-word!important;}#ovBody.is-luno-profile-edit .pe-frame-lock,#ovBody.is-luno-profile-edit .pe-frame-active,#ovBody.is-luno-profile-edit .pe-frame-owned{font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:6.3px!important;line-height:8px!important;letter-spacing:0!important;text-align:center!important;}',
    '#ovBody.is-luno-profile-edit .pe-save{display:flex!important;min-height:54px!important;align-items:center!important;justify-content:center!important;gap:7px!important;margin:12px 0 0!important;padding:6px 14px!important;border:1px solid rgba(255,239,165,.75)!important;border-radius:8px!important;background:linear-gradient(180deg,#efd266,#b47626)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.34),0 4px 9px rgba(0,0,0,.32)!important;font-family:Cinzel,Georgia,serif!important;font-size:11px!important;line-height:15px!important;font-weight:900!important;letter-spacing:0!important;color:#2b1934!important;}#ovBody.is-luno-profile-edit .pe-save>span{display:flex!important;width:40px!important;height:40px!important;align-items:center!important;justify-content:center!important;font-size:0!important;}#ovBody.is-luno-profile-edit .luno-profile-save-art{display:block;width:40px;height:40px;object-fit:contain;}',
    '@media(max-width:360px){#ovBody.is-luno-ranking .rk-tab{grid-template-columns:39px minmax(0,1fr)!important;padding:5px 8px!important;font-size:9px!important}#ovBody.is-luno-ranking .luno-rank-tab-art{width:39px;height:39px}#ovBody.is-luno-ranking .rk-podium-bg{min-height:272px!important}#ovBody.is-luno-ranking .rk-row{grid-template-columns:28px 36px minmax(0,1fr) auto!important;gap:5px!important;padding-left:6px!important;padding-right:6px!important}#ovBody.is-luno-ranking .rk-row-avatar{width:36px!important;height:36px!important}#ovBody.is-luno-guide .gd-sec{grid-template-columns:52px minmax(0,1fr)!important;padding-left:5px!important;padding-right:8px!important}#ovBody.is-luno-guide .luno-guide-icon{width:50px;height:50px}#ovBody.is-luno-profile-edit .pe-country-grid{grid-template-columns:repeat(2,minmax(0,1fr))!important}#ovBody.is-luno-profile-edit .pe-frame-grid{grid-template-columns:repeat(3,minmax(0,1fr))!important}}'
  ].join('');
  document.head.appendChild(screenCss);

  var css=document.createElement('style');
  css.id='luno-image2-safe-css';
  css.textContent=[
    '.card-art,.card-tile img,.cc-card img,.deck-card img,.dc-card img{object-fit:contain!important;}',
    '.cb-eimg,.emoji-img,.ic-emoji-img{object-fit:contain!important;}',
    '.mn-topbar{gap:4px!important;padding-left:6px!important;padding-right:6px!important;}',
    '.mn-topbar .mn-profile-pill{max-width:34vw!important;padding-right:5px!important;}',
    '.mn-topbar .mn-pname{max-width:76px!important;font-size:12px!important;}',
    '.mn-topbar .mn-cur-group{gap:2px!important;min-width:0!important;}',
    '.mn-topbar .mn-cur{gap:1px!important;padding:2px 4px!important;font-size:8.5px!important;}',
    '.mn-topbar .cur-plus{width:16px!important;height:16px!important;font-size:12px!important;margin-left:1px!important;}',
    '.mn-topbar .mn-gear{width:28px!important;height:28px!important;flex-basis:28px!important;}',
    '.mn-bottomnav .mn-navitem,.mn-bottomnav .mn-navitem.mn-navitem-center{height:54px!important;min-width:0!important;padding:1px 0!important;justify-content:center!important;overflow:visible!important;}',
    '.mn-bottomnav .nv-ico{display:block!important;width:39px!important;height:39px!important;line-height:39px!important;margin:0 auto!important;flex:0 0 39px!important;}',
    '.mn-bottomnav .luno-navimg,.mn-bottomnav .mn-navitem-center .luno-navimg{display:block!important;width:39px!important;height:39px!important;max-width:39px!important;object-fit:contain!important;margin:0 auto!important;border-radius:0!important;filter:drop-shadow(0 2px 4px rgba(0,0,0,.62))!important;}',
    '.mn-bottomnav .nv-lbl{display:block!important;max-width:100%!important;padding:0 2px!important;font-family:Cinzel,Georgia,serif!important;font-size:8px!important;line-height:11px!important;font-weight:900!important;letter-spacing:0!important;color:#f1e9ff!important;white-space:nowrap!important;overflow:hidden!important;text-overflow:ellipsis!important;text-shadow:0 1px 0 #160b32,0 0 5px rgba(116,226,213,.25)!important;}',
    '.mn-bottomnav .mn-navitem.active .nv-lbl{color:#ffd860!important;}',
    '#menu .mn-passrow{height:66px!important;gap:4px!important;padding:3px 7px 5px!important;align-items:stretch!important;background:linear-gradient(180deg,rgba(20,10,48,.96),rgba(12,7,31,.98))!important;border-top:1px solid rgba(255,223,132,.16)!important;border-bottom:1px solid rgba(111,219,207,.16)!important;}',
    '#menu .mn-quick{flex:5 1 0!important;gap:4px!important;min-width:0!important;align-items:stretch!important;}',
    '#menu .mn-luno-pass,#menu .mn-quick .mn-qbtn{height:58px!important;min-width:0!important;padding:2px 2px 1px!important;border-radius:8px!important;border:1px solid rgba(236,215,255,.34)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.14),0 2px 5px rgba(0,0,0,.46)!important;display:flex!important;flex-direction:column!important;align-items:center!important;justify-content:center!important;overflow:visible!important;position:relative!important;}',
    '#menu .mn-luno-pass{flex:1 1 0!important;background:linear-gradient(155deg,#50318c,#26164e)!important;border-color:rgba(255,213,92,.58)!important;}',
    '#menu .mn-qbtn-friends{background:linear-gradient(155deg,#245f69,#193455)!important;}',
    '#menu #qbGorevler{background:linear-gradient(155deg,#624b31,#38264b)!important;}',
    '#menu #qbSiralama{background:linear-gradient(155deg,#244d75,#292357)!important;}',
    '#menu #qbRehber{background:linear-gradient(155deg,#28645f,#243650)!important;}',
    '#menu .mn-qbtn-settings{background:linear-gradient(155deg,#51416e,#28203f)!important;}',
    '#menu .mn-luno-pass:active,#menu .mn-quick .mn-qbtn:active{transform:translateY(1px) scale(.96)!important;filter:brightness(.92)!important;}',
    '#menu .mn-luno-pass .lp-shine,#menu .mn-luno-pass .lp-info,#menu .mn-luno-pass .lp-reward{display:none!important;}',
    '#menu .mn-luno-pass .lp-icon{width:39px!important;height:39px!important;max-width:39px!important;margin:0!important;flex:0 0 39px!important;}',
    '#menu .mn-luno-pass .luno-passimg,#menu .mn-quick .luno-qbimg{display:block!important;width:39px!important;height:39px!important;max-width:39px!important;object-fit:contain!important;object-position:center!important;border-radius:0!important;margin:0 auto!important;filter:drop-shadow(0 2px 3px rgba(0,0,0,.52))!important;}',
    '#menu .mn-luno-pass::before,#menu .mn-quick .mn-qbtn::before{display:none!important;content:none!important;}',
    '#menu .mn-luno-pass::after,#menu .mn-quick .mn-qbtn::after{display:block!important;content:attr(data-label)!important;width:100%!important;height:11px!important;font-family:Cinzel,Georgia,serif!important;font-size:7px!important;line-height:11px!important;font-weight:900!important;letter-spacing:0!important;color:#fff5d8!important;text-align:center!important;white-space:nowrap!important;overflow:hidden!important;text-overflow:ellipsis!important;text-shadow:0 1px 1px rgba(0,0,0,.9)!important;}',
    '#menu .mn-quick .notif-badge{top:-4px!important;right:-4px!important;z-index:5!important;}',
    '#menu .mn-luno-live{bottom:8.5%!important;z-index:7!important;}',
    '#menu .mn-luno-img{height:clamp(112px,16dvh,132px)!important;width:auto!important;object-fit:contain!important;filter:drop-shadow(0 8px 11px rgba(8,4,24,.48))!important;transition:transform 1.25s ease-in-out,opacity .16s ease!important;}',
    '#menu .mn-luno-bubble{max-width:228px!important;margin-bottom:7px!important;padding:7px 12px!important;border-radius:8px!important;background:rgba(18,10,38,.94)!important;border:1px solid rgba(255,215,105,.72)!important;color:#fff7df!important;font-family:Georgia,serif!important;font-size:10.5px!important;font-weight:700!important;line-height:1.35!important;box-shadow:0 4px 12px rgba(0,0,0,.44),inset 0 1px 0 rgba(255,255,255,.08)!important;}',
    '#menu .mn-luno-live.bubble-pop .mn-luno-bubble{animation:lunoMenuBubblePop .34s ease-out!important;}',
    '#menu .mn-luno-live.is-waving .mn-luno-bubble{border-color:rgba(111,219,207,.8)!important;}',
    '#menu .mn-arena-pill{min-height:46px!important;margin:-13px 12px 6px!important;padding:6px 9px!important;gap:7px!important;border-radius:8px!important;background:linear-gradient(105deg,rgba(34,22,67,.98),rgba(28,48,70,.98))!important;border:1px solid rgba(239,207,112,.52)!important;box-shadow:0 5px 13px rgba(0,0,0,.5),inset 0 1px 0 rgba(255,255,255,.08)!important;}',
    '#menu .ap-title{font-family:Cinzel,Georgia,serif!important;font-size:10px!important;line-height:1.15!important;font-weight:900!important;letter-spacing:0!important;color:#fff3cf!important;max-width:88px!important;}',
    '#menu .ap-progress{gap:5px!important;min-width:0!important;}',
    '#menu .ap-crown{display:flex!important;width:22px!important;height:22px!important;align-items:center!important;justify-content:center!important;flex:0 0 22px!important;}',
    '#menu .luno-arena-icon{width:22px!important;height:22px!important;object-fit:contain!important;filter:drop-shadow(0 1px 2px rgba(0,0,0,.55))!important;}',
    '#menu .ap-bar{height:9px!important;padding:1px!important;border-radius:6px!important;background:#100a27!important;border:1px solid rgba(255,255,255,.14)!important;box-shadow:inset 0 1px 3px rgba(0,0,0,.75)!important;}',
    '#menu .ap-fill{position:relative!important;height:100%!important;border-radius:4px!important;background:linear-gradient(90deg,#6fd0c3 0%,#8aa6ef 50%,#f1c85d 100%)!important;box-shadow:0 0 5px rgba(111,208,195,.45)!important;overflow:hidden!important;}',
    '#menu .ap-fill::after{content:""!important;position:absolute!important;inset:0!important;background:linear-gradient(180deg,rgba(255,255,255,.42),transparent 55%)!important;}',
    '#menu .ap-pts{font-family:Cinzel,Georgia,serif!important;font-size:8px!important;font-weight:900!important;letter-spacing:0!important;color:#f6f0ff!important;white-space:nowrap!important;}',
    '#menu .ap-arrow{width:25px!important;height:25px!important;flex:0 0 25px!important;border-radius:7px!important;background:linear-gradient(145deg,#cfa641,#866322)!important;border:1px solid rgba(255,239,176,.66)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.28)!important;font-size:13px!important;}',
    '#menu .mn-topbar{min-height:58px!important;gap:4px!important;padding:calc(6px + env(safe-area-inset-top,0px)) 6px 6px!important;background:linear-gradient(180deg,rgba(37,20,76,.98),rgba(22,13,49,.96))!important;border-bottom:1px solid rgba(111,219,207,.16)!important;}',
    '#menu .mn-profile-pill{height:46px!important;box-sizing:border-box!important;flex:0 1 136px!important;max-width:36vw!important;gap:5px!important;padding:2px 7px 2px 2px!important;border-radius:8px!important;background:linear-gradient(140deg,rgba(69,39,116,.98),rgba(30,22,62,.98))!important;border:1px solid rgba(239,207,112,.5)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.12),0 3px 8px rgba(0,0,0,.42)!important;}',
    '#menu .mn-avatar-wrap{width:40px!important;height:40px!important;flex:0 0 40px!important;}',
    '#menu .mn-avatar{width:40px!important;height:40px!important;border-radius:8px!important;border:1px solid rgba(255,221,118,.62)!important;background:radial-gradient(circle at 50% 35%,#59407f,#25173f)!important;overflow:hidden!important;}',
    '#menu .mn-avatar span{display:flex!important;width:100%!important;height:100%!important;align-items:center!important;justify-content:center!important;}',
    '#menu .luno-profile-status-icon{display:block!important;width:38px!important;height:38px!important;object-fit:contain!important;filter:drop-shadow(0 2px 3px rgba(0,0,0,.5))!important;}',
    '#menu .mn-level{bottom:-3px!important;min-width:19px!important;box-sizing:border-box!important;padding:1px 5px!important;border-radius:5px!important;border:1px solid #180d34!important;font-size:8px!important;line-height:12px!important;background:linear-gradient(145deg,#8f55db,#59309c)!important;}',
    '#menu .mn-pinfo{min-width:0!important;gap:2px!important;}',
    '#menu .mn-pname{max-width:82px!important;font-family:Cinzel,Georgia,serif!important;font-size:11.5px!important;line-height:13px!important;font-weight:900!important;letter-spacing:0!important;}',
    '#menu .mn-club{max-width:82px!important;overflow:hidden!important;text-overflow:ellipsis!important;font-size:8px!important;line-height:10px!important;color:#d7c9ee!important;}',
    '#menu .mn-cur-group{gap:3px!important;min-width:0!important;justify-content:flex-end!important;}',
    '#menu .mn-cur{min-height:31px!important;box-sizing:border-box!important;gap:3px!important;padding:3px 5px!important;border-radius:8px!important;border:1px solid rgba(151,121,205,.43)!important;background:linear-gradient(150deg,rgba(28,18,55,.98),rgba(13,10,31,.98))!important;font-family:Cinzel,Georgia,serif!important;font-size:9px!important;line-height:18px!important;font-weight:900!important;letter-spacing:0!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.08),0 2px 6px rgba(0,0,0,.42)!important;}',
    '#menu .cur-ic{display:flex!important;width:18px!important;height:18px!important;align-items:center!important;justify-content:center!important;flex:0 0 18px!important;}',
    '#menu .luno-curimg{display:block!important;width:18px!important;height:18px!important;object-fit:contain!important;filter:drop-shadow(0 1px 2px rgba(0,0,0,.52))!important;}',
    '#menu .cur-val{min-width:15px!important;text-align:center!important;}',
    '#menu .cur-plus{width:18px!important;height:18px!important;flex:0 0 18px!important;margin-left:0!important;border-radius:50%!important;border:1px solid rgba(218,186,255,.48)!important;background:linear-gradient(145deg,#6a3ca0,#35205f)!important;color:#fff2ce!important;}',
    '#menu .mn-gear{width:34px!important;height:34px!important;flex:0 0 34px!important;border-radius:8px!important;border:1px solid rgba(239,207,112,.45)!important;background:linear-gradient(145deg,#4a326e,#24183e)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.1),0 2px 6px rgba(0,0,0,.4)!important;}',
    '#menu .mn-gear .luno-chatimg{display:block!important;width:27px!important;height:27px!important;object-fit:contain!important;filter:drop-shadow(0 1px 2px rgba(0,0,0,.48))!important;}',
    '#menu .mn-passrow{height:70px!important;padding:3px 7px 5px!important;}',
    '#menu .mn-luno-pass,#menu .mn-quick .mn-qbtn{height:62px!important;box-sizing:border-box!important;display:grid!important;grid-template-rows:44px 12px!important;grid-template-columns:1fr!important;align-items:center!important;justify-items:center!important;padding:2px 2px 2px!important;}',
    '#menu .mn-luno-pass .lp-icon{width:44px!important;height:44px!important;max-width:44px!important;flex:0 0 44px!important;}',
    '#menu .mn-luno-pass .luno-passimg,#menu .mn-quick .luno-qbimg{width:44px!important;height:44px!important;max-width:44px!important;}',
    '#menu .mn-luno-pass::after,#menu .mn-quick .mn-qbtn::after{height:12px!important;font-size:7px!important;line-height:12px!important;align-self:end!important;}',
    '#menu .mn-arena-pill.is-enhanced{display:grid!important;grid-template-columns:38px minmax(0,1fr) 30px!important;align-items:center!important;min-height:58px!important;margin:-12px 10px 7px!important;padding:6px 8px!important;gap:8px!important;border-radius:8px!important;background:linear-gradient(110deg,rgba(54,34,91,.99),rgba(28,51,69,.99))!important;border:1px solid rgba(240,205,102,.64)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.11),0 5px 14px rgba(0,0,0,.52)!important;}',
    '#menu .mn-arena-pill.is-enhanced .ap-crown{grid-column:1!important;width:38px!important;height:38px!important;flex:0 0 38px!important;border-radius:8px!important;background:radial-gradient(circle at 50% 35%,rgba(132,82,183,.46),rgba(20,15,45,.72))!important;border:1px solid rgba(239,207,112,.42)!important;}',
    '#menu .mn-arena-pill.is-enhanced .luno-arena-icon{width:34px!important;height:34px!important;}',
    '#menu .ap-main{grid-column:2!important;min-width:0!important;display:grid!important;grid-template-columns:minmax(0,1fr) auto!important;grid-template-rows:9px 15px 14px!important;column-gap:6px!important;align-items:center!important;}',
    '#menu .ap-kicker{grid-column:1/3!important;grid-row:1!important;font-family:Cinzel,Georgia,serif!important;font-size:6.5px!important;line-height:9px!important;font-weight:900!important;letter-spacing:0!important;color:#83d9d0!important;}',
    '#menu .ap-main .ap-title{grid-column:1/3!important;grid-row:2!important;max-width:none!important;font-family:Cinzel,Georgia,serif!important;font-size:11.5px!important;line-height:15px!important;font-weight:900!important;letter-spacing:0!important;color:#fff3cf!important;white-space:nowrap!important;overflow:hidden!important;text-overflow:ellipsis!important;}',
    '#menu .ap-main .ap-progress{grid-column:1/3!important;grid-row:3!important;display:grid!important;grid-template-columns:minmax(0,1fr) auto!important;gap:6px!important;min-width:0!important;}',
    '#menu .ap-main .ap-bar{grid-column:1!important;height:10px!important;padding:1px!important;border-radius:6px!important;}',
    '#menu .ap-main .ap-pts{grid-column:2!important;min-width:50px!important;padding:1px 5px!important;border-radius:5px!important;background:rgba(13,9,32,.72)!important;border:1px solid rgba(255,255,255,.12)!important;font-size:7.5px!important;line-height:10px!important;text-align:center!important;}',
    '#menu .mn-arena-pill.is-enhanced .ap-arrow{grid-column:3!important;width:30px!important;height:34px!important;flex:0 0 30px!important;border-radius:8px!important;font-size:16px!important;}',
    '#menu .mn-bottomnav{left:6px!important;right:6px!important;bottom:calc(6px + env(safe-area-inset-bottom,0px))!important;height:68px!important;box-sizing:border-box!important;padding:5px 5px 6px!important;gap:4px!important;border:1px solid rgba(239,207,112,.42)!important;border-radius:8px!important;background:linear-gradient(180deg,rgba(30,18,64,.98),rgba(12,8,31,.99))!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.09),0 -4px 14px rgba(0,0,0,.56)!important;overflow:visible!important;}',
    '#menu .mn-bottomnav .mn-navitem,#menu .mn-bottomnav .mn-navitem.mn-navitem-center{height:56px!important;min-height:56px!important;display:grid!important;grid-template-rows:41px 12px!important;grid-template-columns:1fr!important;align-items:center!important;justify-items:center!important;padding:1px 0 2px!important;overflow:visible!important;}',
    '#menu .mn-bottomnav .nv-ico{width:41px!important;height:41px!important;line-height:41px!important;flex:0 0 41px!important;}',
    '#menu .mn-bottomnav .luno-navimg,#menu .mn-bottomnav .mn-navitem-center .luno-navimg{width:41px!important;height:41px!important;max-width:41px!important;}',
    '#menu .mn-bottomnav .nv-ico{position:absolute!important;left:50%!important;top:1px!important;transform:translateX(-50%)!important;}',
    '#menu .mn-bottomnav .nv-lbl{display:block!important;visibility:visible!important;opacity:1!important;position:absolute!important;left:0!important;right:0!important;bottom:1px!important;z-index:5!important;width:100%!important;height:13px!important;max-width:none!important;overflow:visible!important;text-overflow:clip!important;font-size:8.5px!important;line-height:13px!important;text-align:center!important;color:#f3eaff!important;}',
    '#menu .mn-bottomnav .mn-navitem.active::before{display:block!important;content:""!important;position:absolute!important;top:-5px!important;left:50%!important;width:22px!important;height:2px!important;transform:translateX(-50%)!important;border-radius:2px!important;background:#ffd66a!important;box-shadow:0 0 7px rgba(255,214,106,.75)!important;}',
    '#menu .menu-scroll{padding-bottom:calc(88px + env(safe-area-inset-bottom,0px))!important;}',
    '#menu .mn-luno-pass .lp-icon{position:absolute!important;left:50%!important;top:2px!important;transform:translateX(-50%)!important;}',
    '#menu .mn-luno-pass::after{position:absolute!important;left:2px!important;right:2px!important;bottom:3px!important;width:auto!important;height:11px!important;line-height:11px!important;align-self:auto!important;}',
    '#menu .mn-arena-pill.is-enhanced{grid-template-columns:74px minmax(0,1fr) 32px!important;min-height:64px!important;margin:-12px 9px 7px!important;padding:8px 10px!important;gap:6px!important;border:0!important;border-radius:0!important;background-color:transparent!important;background-image:url("assets/luno-art/menu-arena-frame-v3.png")!important;background-repeat:no-repeat!important;background-position:center!important;background-size:100% 100%!important;box-shadow:none!important;}',
    '#menu .mn-arena-pill.is-enhanced .ap-crown{width:44px!important;height:44px!important;justify-self:center!important;border:0!important;background:transparent!important;}',
    '#menu .mn-arena-pill.is-enhanced .luno-arena-icon{width:42px!important;height:42px!important;}',
    '#menu .mn-arena-pill.is-enhanced .ap-main{grid-template-rows:10px 17px 15px!important;padding:0 3px!important;}',
    '#menu .mn-arena-pill.is-enhanced .ap-kicker{font-size:6.5px!important;line-height:10px!important;color:#78d7d0!important;}',
    '#menu .mn-arena-pill.is-enhanced .ap-title{font-size:11px!important;line-height:17px!important;color:#fff4d4!important;}',
    '#menu .mn-arena-pill.is-enhanced .ap-pts{min-width:48px!important;font-size:7px!important;line-height:10px!important;padding:1px 4px!important;}',
    '#menu .mn-arena-pill.is-enhanced .ap-arrow{width:28px!important;height:36px!important;opacity:0!important;pointer-events:auto!important;}',
    '#nvMagaza{position:relative!important;overflow:visible!important;}',
    '.luno-shop-badge{position:absolute;top:-4px;right:5px;z-index:20;width:17px;height:17px;align-items:center;justify-content:center;border:2px solid #1a0c35;border-radius:50%;background:#ed3d55;color:#fff;font:900 9px/1 Arial,sans-serif;box-shadow:0 2px 6px rgba(0,0,0,.5);}',
    '#ovBody .shx-wrap{box-sizing:border-box!important;padding:8px 16px 30px!important;color:#f7efff!important;background:linear-gradient(180deg,rgba(20,10,44,.2),rgba(9,6,25,.08))!important;}',
    '#ovBody .shx-topcur{display:flex!important;justify-content:flex-end!important;gap:8px!important;margin:0 0 9px!important;}',
    '#ovBody .shx-pill{display:grid!important;grid-template-columns:24px minmax(28px,auto) 20px!important;align-items:center!important;gap:4px!important;min-width:104px!important;height:38px!important;box-sizing:border-box!important;padding:4px 6px!important;border:1px solid rgba(239,207,112,.48)!important;border-radius:8px!important;background:linear-gradient(150deg,#291951,#120c2d)!important;color:#fff6dd!important;font-family:Cinzel,Georgia,serif!important;font-size:10px!important;font-weight:900!important;letter-spacing:0!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.1),0 3px 8px rgba(0,0,0,.38)!important;}',
    '#ovBody .shx-pill-art{display:block!important;width:24px!important;height:24px!important;object-fit:contain!important;}',
    '#ovBody .shx-pill-plus{display:flex!important;width:19px!important;height:19px!important;align-items:center!important;justify-content:center!important;margin:0!important;border:1px solid rgba(229,205,255,.42)!important;border-radius:50%!important;background:#603997!important;color:#fff2d4!important;font:900 13px/1 Arial,sans-serif!important;}',
    '#ovBody .shx-premium{display:grid!important;grid-template-columns:84px minmax(0,1fr) 68px!important;align-items:center!important;gap:8px!important;min-height:102px!important;box-sizing:border-box!important;margin:0 0 17px!important;padding:7px 9px!important;border:1px solid rgba(255,218,112,.7)!important;border-radius:8px!important;background:linear-gradient(125deg,#41236e 0%,#211744 56%,#164450 100%)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.13),0 5px 14px rgba(0,0,0,.45)!important;color:#fff6df!important;overflow:hidden!important;}',
    '#ovBody .shx-premium-art{display:block!important;width:82px!important;height:82px!important;object-fit:contain!important;filter:drop-shadow(0 3px 5px rgba(0,0,0,.42))!important;}',
    '#ovBody .shx-premium-mid{min-width:0!important;}',
    '#ovBody .shx-premium-kicker{font-family:Cinzel,Georgia,serif!important;font-size:6.5px!important;line-height:9px!important;font-weight:900!important;color:#7ad7cf!important;}',
    '#ovBody .shx-premium-title{margin:1px 0 4px!important;font-family:Cinzel,Georgia,serif!important;font-size:14px!important;line-height:17px!important;font-weight:900!important;letter-spacing:0!important;color:#ffe5a0!important;white-space:nowrap!important;}',
    '#ovBody .shx-premium-feats{display:flex!important;flex-wrap:wrap!important;gap:2px 8px!important;color:#ded4ed!important;font-family:Georgia,serif!important;font-size:7px!important;line-height:10px!important;}',
    '#ovBody .shx-premium-btn{display:flex!important;width:66px!important;height:36px!important;align-items:center!important;justify-content:center!important;box-sizing:border-box!important;border:1px solid rgba(255,232,158,.58)!important;border-radius:7px!important;background:linear-gradient(145deg,#d6a939,#8a6120)!important;color:#190d2d!important;font-family:Cinzel,Georgia,serif!important;font-size:8.5px!important;font-weight:900!important;letter-spacing:0!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.3),0 3px 7px rgba(0,0,0,.35)!important;}',
    '#ovBody .shx-sec{display:flex!important;align-items:center!important;gap:7px!important;min-height:28px!important;margin:12px 1px 7px!important;color:#ffe274!important;font-family:Cinzel,Georgia,serif!important;font-size:11px!important;line-height:16px!important;font-weight:900!important;letter-spacing:0!important;}',
    '#ovBody .shx-hdr-ic{width:24px!important;height:24px!important;object-fit:contain!important;}',
    '#ovBody .shx-slot-mark{display:flex!important;width:22px!important;height:22px!important;align-items:center!important;justify-content:center!important;border:1px solid rgba(128,218,207,.38)!important;border-radius:6px!important;background:#1e3650!important;color:#ffe4a1!important;font-size:15px!important;}',
    '#ovBody .shx-offer-grid{display:grid!important;grid-template-columns:repeat(2,minmax(0,1fr))!important;gap:9px!important;}',
    '#ovBody .shx-ocard{position:relative!important;display:flex!important;flex-direction:column!important;min-width:0!important;min-height:180px!important;box-sizing:border-box!important;padding:10px!important;border:1px solid rgba(145,109,204,.6)!important;border-radius:8px!important;background:linear-gradient(155deg,#30205b,#171034)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.08),0 4px 10px rgba(0,0,0,.38)!important;overflow:hidden!important;}',
    '#ovBody .shx-ocard.is-starter{border-color:rgba(99,211,199,.56)!important;background:linear-gradient(155deg,#203d51,#1b153d)!important;}',
    '#ovBody .shx-ocard.is-expert{border-color:rgba(240,194,91,.62)!important;}',
    '#ovBody .shx-ocard-name{padding-right:31px!important;font-family:Cinzel,Georgia,serif!important;font-size:10px!important;line-height:13px!important;font-weight:900!important;letter-spacing:0!important;color:#fff1ce!important;white-space:nowrap!important;overflow:hidden!important;text-overflow:ellipsis!important;}',
    '#ovBody .shx-ocard-badge{top:7px!important;right:7px!important;padding:3px 5px!important;border-radius:5px!important;background:#e74b63!important;font-size:7px!important;line-height:10px!important;}',
    '#ovBody .shx-ocard-top{display:grid!important;grid-template-columns:88px minmax(0,1fr)!important;align-items:center!important;gap:7px!important;min-height:94px!important;}',
    '#ovBody .shx-ocard-art{display:block!important;width:88px!important;height:88px!important;object-fit:contain!important;filter:drop-shadow(0 3px 5px rgba(0,0,0,.45))!important;}',
    '#ovBody .shx-ocard-items{display:flex!important;flex-direction:column!important;gap:3px!important;min-width:0!important;color:#ddd1ec!important;font-family:Georgia,serif!important;font-size:7.5px!important;line-height:11px!important;}',
    '#ovBody .shx-ocard-items span{white-space:normal!important;}',
    '#ovBody .shx-ocard-price{display:flex!important;align-items:baseline!important;gap:7px!important;margin-top:auto!important;}',
    '#ovBody .shx-ocard-new{font-family:Cinzel,Georgia,serif!important;font-size:16px!important;line-height:20px!important;font-weight:900!important;color:#ffdc62!important;}',
    '#ovBody .shx-ocard-old{font-size:8px!important;color:#897d9c!important;}',
    '#ovBody .shx-chest-row{display:grid!important;grid-template-columns:repeat(4,minmax(0,1fr))!important;gap:7px!important;overflow:visible!important;}',
    '#ovBody .shx-chest-row .shx-card{display:grid!important;grid-template-rows:78px 29px 25px!important;align-items:center!important;justify-items:center!important;min-width:0!important;width:auto!important;min-height:140px!important;box-sizing:border-box!important;padding:5px!important;border:1px solid rgba(137,105,192,.5)!important;border-radius:8px!important;background:linear-gradient(165deg,#2a1b4d,#130d2c)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.08),0 3px 8px rgba(0,0,0,.33)!important;}',
    '#ovBody .shx-chest-row .shx-art{display:block!important;width:76px!important;height:76px!important;object-fit:contain!important;filter:drop-shadow(0 3px 4px rgba(0,0,0,.46))!important;}',
    '#ovBody .shx-chest-row .shx-card-name{align-self:center!important;color:#f2e8fb!important;font-family:Georgia,serif!important;font-size:8.5px!important;line-height:11px!important;font-weight:700!important;text-align:center!important;}',
    '#ovBody .shx-chest-row .shx-card-price{display:flex!important;align-items:center!important;justify-content:center!important;width:100%!important;height:23px!important;box-sizing:border-box!important;padding:2px!important;border-radius:6px!important;background:rgba(8,6,24,.66)!important;font-family:Cinzel,Georgia,serif!important;font-size:9px!important;line-height:14px!important;font-weight:900!important;}',
    '#ovBody .shx-costume-slots{display:flex!important;gap:8px!important;overflow-x:auto!important;padding:1px 1px 5px!important;}',
    '#ovBody .shx-costume-slot{position:relative!important;display:flex!important;width:101px!important;height:126px!important;flex:0 0 101px!important;align-items:center!important;justify-content:center!important;box-sizing:border-box!important;border:1px solid rgba(128,213,204,.4)!important;border-radius:8px!important;background:radial-gradient(ellipse at 50% 38%,rgba(73,99,122,.38),transparent 48%),linear-gradient(165deg,#29204b,#12102c)!important;box-shadow:inset 0 0 0 3px rgba(8,7,24,.28),inset 0 1px 0 rgba(255,255,255,.08),0 3px 8px rgba(0,0,0,.32)!important;overflow:hidden!important;}',
    '#ovBody .shx-costume-slot::before{content:""!important;position:absolute!important;left:12px!important;right:12px!important;top:12px!important;bottom:18px!important;border:1px solid rgba(226,207,255,.14)!important;border-radius:6px 6px 18px 18px!important;background:linear-gradient(180deg,rgba(255,255,255,.025),rgba(5,5,20,.25))!important;}',
    '#ovBody .shx-slot-crown{position:absolute!important;top:18px!important;color:rgba(255,222,126,.34)!important;font-size:14px!important;}',
    '#ovBody .shx-slot-piece{position:relative!important;z-index:1!important;color:rgba(224,213,240,.2)!important;font-size:45px!important;text-shadow:0 3px 7px rgba(0,0,0,.5)!important;}',
    '#ovBody .shx-slot-base{position:absolute!important;left:22px!important;right:22px!important;bottom:17px!important;height:7px!important;border-radius:50%!important;background:rgba(104,215,203,.13)!important;box-shadow:0 0 8px rgba(104,215,203,.15)!important;}',
    '#ovBody .shx-curwrap{display:grid!important;grid-template-columns:1fr!important;gap:12px!important;margin-top:12px!important;}',
    '#ovBody .shx-curcol-h{display:flex!important;align-items:center!important;min-height:24px!important;margin:0 0 5px!important;color:#ffe078!important;font-family:Cinzel,Georgia,serif!important;font-size:10px!important;line-height:14px!important;font-weight:900!important;letter-spacing:0!important;}',
    '#ovBody .shx-cur3{display:grid!important;grid-template-columns:repeat(3,minmax(0,1fr))!important;gap:8px!important;}',
    '#ovBody .shx-cur-card{display:grid!important;grid-template-rows:84px 18px 14px!important;align-items:center!important;justify-items:center!important;min-width:0!important;width:auto!important;min-height:126px!important;box-sizing:border-box!important;padding:5px 6px!important;border:1px solid rgba(137,105,192,.48)!important;border-radius:8px!important;background:linear-gradient(160deg,#2b1c4f,#120d2b)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.07),0 3px 8px rgba(0,0,0,.3)!important;overflow:hidden!important;}',
    '#ovBody .shx-cur-g{border-color:rgba(235,188,75,.45)!important;background:linear-gradient(160deg,#3a2b25,#19112d)!important;}',
    '#ovBody .shx-cur-m{border-color:rgba(91,192,220,.5)!important;background:linear-gradient(160deg,#173852,#15122f)!important;}',
    '#ovBody .shx-art-sm{display:block!important;width:82px!important;height:82px!important;object-fit:contain!important;filter:drop-shadow(0 3px 4px rgba(0,0,0,.42))!important;}',
    '#ovBody .shx-cur-amt{font-family:Cinzel,Georgia,serif!important;font-size:10px!important;line-height:14px!important;font-weight:900!important;color:#fff2d2!important;}',
    '#ovBody .shx-cur-fiat{font-family:Georgia,serif!important;font-size:7.5px!important;line-height:10px!important;color:#aa9dbc!important;}',
    '#ovBody .shx-daily.is-shop-last{display:grid!important;grid-template-columns:88px minmax(0,1fr) 86px!important;align-items:center!important;gap:10px!important;min-height:112px!important;box-sizing:border-box!important;margin:18px 0 0!important;padding:9px 10px!important;border:1px solid rgba(101,207,195,.56)!important;border-radius:8px!important;background:linear-gradient(130deg,#203f51,#241744 68%,#3d245d)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.1),0 4px 11px rgba(0,0,0,.38)!important;}',
    '#ovBody .shx-daily-art{display:block!important;width:86px!important;height:86px!important;object-fit:contain!important;filter:drop-shadow(0 3px 5px rgba(0,0,0,.4))!important;}',
    '#ovBody .shx-daily-info{min-width:0!important;}',
    '#ovBody .shx-daily-title{font-family:Cinzel,Georgia,serif!important;font-size:12px!important;line-height:16px!important;font-weight:900!important;letter-spacing:0!important;color:#ffe8a3!important;}',
    '#ovBody .shx-daily-sub{margin-top:3px!important;color:#dcd1ea!important;font-family:Georgia,serif!important;font-size:8.5px!important;line-height:12px!important;}',
    '#ovBody .shx-daily-day{display:inline-flex!important;margin-top:6px!important;padding:2px 6px!important;border:1px solid rgba(255,218,112,.42)!important;border-radius:5px!important;background:rgba(10,8,28,.46)!important;color:#fff0c0!important;font-family:Cinzel,Georgia,serif!important;font-size:7px!important;line-height:10px!important;font-weight:900!important;}',
    '#ovBody .shx-btn{min-width:76px!important;height:36px!important;box-sizing:border-box!important;padding:0 10px!important;border:1px solid rgba(255,236,165,.62)!important;border-radius:7px!important;background:linear-gradient(145deg,#f0c549,#ad7c27)!important;color:#21102f!important;font-family:Cinzel,Georgia,serif!important;font-size:9px!important;font-weight:900!important;letter-spacing:0!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.36),0 3px 7px rgba(0,0,0,.34)!important;}',
    '#ovBody .shx-btn-off{background:#34284b!important;color:#9d92ad!important;border-color:rgba(255,255,255,.14)!important;box-shadow:none!important;}',
    '#menu .mn-arena-pill.is-enhanced .ap-crown{display:block!important;visibility:hidden!important;}',
    '#ovBody .shx-premium{background:linear-gradient(125deg,#58328d 0%,#2f2060 52%,#17606b 100%)!important;border-color:rgba(255,223,125,.84)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.2),0 6px 16px rgba(0,0,0,.5),0 0 14px rgba(68,190,184,.12)!important;}',
    '#ovBody .shx-premium-btn{width:70px!important;height:40px!important;border-color:#ffe7a0!important;background:linear-gradient(145deg,#ffe16d,#d59b2f 58%,#a86d1d)!important;color:#241236!important;font-size:9.5px!important;box-shadow:inset 0 2px 0 rgba(255,255,255,.42),0 4px 9px rgba(0,0,0,.42),0 0 10px rgba(255,205,74,.24)!important;}',
    '#ovBody .shx-premium-title{font-size:15px!important;line-height:18px!important;}',
    '#ovBody .shx-premium-feats{font-size:8px!important;line-height:11px!important;color:#f0e7fa!important;}',
    '#ovBody .shx-ocard{background:linear-gradient(155deg,#3a286c,#211441)!important;border-color:rgba(173,132,232,.76)!important;}',
    '#ovBody .shx-ocard.is-starter{background:linear-gradient(155deg,#275b6a,#22204f)!important;border-color:rgba(101,231,216,.72)!important;}',
    '#ovBody .shx-ocard.is-expert{background:linear-gradient(155deg,#4b2868,#281746)!important;border-color:rgba(255,205,91,.8)!important;}',
    '#ovBody .shx-ocard-name{font-size:10.8px!important;line-height:14px!important;}',
    '#ovBody .shx-ocard-items{font-size:8.4px!important;line-height:12px!important;color:#f1e8fa!important;}',
    '#ovBody .shx-ocard-new{font-size:18px!important;line-height:22px!important;}',
    '#ovBody .shx-ocard-old{font-size:9px!important;color:#b2a5c3!important;}',
    '#ovBody .shx-ocard-items .luic,#ovBody .shx-card-price .luic,#ovBody .shx-curcol-h .luic,#ovBody .shx-daily-sub .luic{width:14px!important;height:14px!important;object-fit:contain!important;vertical-align:-3px!important;}',
    '#ovBody .shx-chest-row .shx-card{background:linear-gradient(165deg,#3a2864,#1b1238)!important;border-color:rgba(170,129,223,.68)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.14),0 4px 10px rgba(0,0,0,.38),0 0 9px rgba(120,80,195,.12)!important;}',
    '#ovBody .shx-chest-row .shx-card-name{font-size:9.4px!important;line-height:12px!important;color:#fff8ee!important;}',
    '#ovBody .shx-chest-row .shx-card-price{font-size:10px!important;background:rgba(12,7,31,.82)!important;color:#ffe06a!important;}',
    '#ovBody .shx-costume-slot{background:radial-gradient(ellipse at 50% 38%,rgba(74,190,183,.34),transparent 46%),linear-gradient(165deg,#3a3168,#181337)!important;border-color:rgba(110,224,211,.62)!important;box-shadow:inset 0 0 0 3px rgba(8,7,24,.24),inset 0 1px 0 rgba(255,255,255,.15),0 4px 10px rgba(0,0,0,.38),0 0 10px rgba(74,190,183,.1)!important;}',
    '#ovBody .shx-slot-piece{color:rgba(235,224,255,.34)!important;}',
    '#ovBody .shx-cur-card{background:linear-gradient(160deg,#3a2868,#1b123b)!important;border-color:rgba(164,123,221,.68)!important;}',
    '#ovBody .shx-cur-g{background:linear-gradient(160deg,#513b29,#211538)!important;border-color:rgba(246,191,61,.7)!important;}',
    '#ovBody .shx-cur-m{background:linear-gradient(160deg,#1e5270,#17163f)!important;border-color:rgba(72,201,232,.72)!important;}',
    '#ovBody .shx-cur-amt{font-size:11px!important;line-height:15px!important;color:#fff8e3!important;}',
    '#ovBody .shx-cur-fiat{font-size:9px!important;line-height:12px!important;color:#c4b8d4!important;}',
    '#ovBody .shx-daily.is-shop-last{background:linear-gradient(130deg,#286579,#352060 65%,#57307b)!important;border-color:rgba(106,229,214,.76)!important;}',
    '#ovBody .shx-daily-title{font-size:13px!important;line-height:17px!important;}',
    '#ovBody .shx-daily-sub{font-size:9.5px!important;line-height:13px!important;color:#f1e7f8!important;}',
    '#ovBody .shx-sec,#ovBody .shx-curcol-h{color:#ffe67f!important;text-shadow:0 1px 2px rgba(0,0,0,.72),0 0 8px rgba(255,205,64,.14)!important;}',
    '#ovBody .pf2-wrap.is-luno-profile{display:flex!important;width:100%!important;max-width:100%!important;min-width:0!important;flex-direction:column!important;gap:11px!important;box-sizing:border-box!important;padding:5px 12px 22px!important;color:#f8f2ff!important;font-family:Georgia,serif!important;letter-spacing:0!important;overflow:hidden!important;}',
    '#ovBody .pf2-wrap.is-luno-profile>*{width:100%!important;max-width:100%!important;min-width:0!important;}',
    '#ovBody .is-luno-profile *{box-sizing:border-box!important;letter-spacing:0!important;}',
    '#ovBody .is-luno-profile .pf2-card{position:relative!important;min-height:238px!important;padding:18px 14px 15px!important;border:1px solid rgba(255,220,119,.62)!important;border-radius:8px!important;background:radial-gradient(circle at 50% 17%,rgba(88,211,199,.17),transparent 32%),linear-gradient(155deg,#3f236c 0%,#251545 56%,#133c4b 100%)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.16),0 8px 20px rgba(7,3,23,.42)!important;overflow:hidden!important;}',
    '#ovBody .is-luno-profile .pf2-card-glow{background:radial-gradient(circle,rgba(244,204,94,.19),transparent 66%)!important;opacity:1!important;}',
    '#ovBody .is-luno-profile .pf2-edit{top:10px!important;right:10px!important;width:34px!important;height:34px!important;border:1px solid rgba(128,225,213,.55)!important;border-radius:7px!important;background:#173f50!important;color:#fff0bd!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.15)!important;}',
    '#ovBody .is-luno-profile .pf2-avatar{width:104px!important;height:104px!important;border:3px solid #f2c95d!important;box-shadow:0 0 0 4px rgba(44,203,186,.23),0 7px 16px rgba(0,0,0,.4)!important;background-color:#261542!important;}',
    '#ovBody .is-luno-profile .pf2-name{margin-top:8px!important;font-family:Cinzel,Georgia,serif!important;font-size:18px!important;line-height:23px!important;font-weight:900!important;color:#fff5d5!important;background:none!important;-webkit-text-fill-color:#fff5d5!important;text-shadow:0 2px 3px rgba(0,0,0,.72)!important;}#ovBody .is-luno-profile .pf2-name-prem{background:linear-gradient(180deg,#fff7d7,#ffd65b 62%,#c98c23)!important;-webkit-background-clip:text!important;background-clip:text!important;-webkit-text-fill-color:transparent!important;}',
    '#ovBody .is-luno-profile .pf2-nstar{color:#6ee0d1!important;font-size:8px!important;}',
    '#ovBody .is-luno-profile .pf2-badges{display:flex!important;flex-wrap:wrap!important;justify-content:center!important;gap:6px!important;margin-top:7px!important;}',
    '#ovBody .is-luno-profile .pf2-pill{display:flex!important;align-items:center!important;min-height:30px!important;padding:3px 9px 3px 5px!important;border:1px solid rgba(234,204,119,.42)!important;border-radius:7px!important;background:rgba(13,30,52,.78)!important;font-family:Cinzel,Georgia,serif!important;font-size:8.5px!important;line-height:12px!important;font-weight:900!important;color:#f8edcf!important;}',
    '#ovBody .is-luno-profile .pf2-pill-ic{display:flex!important;width:25px!important;height:25px!important;align-items:center!important;justify-content:center!important;margin-right:4px!important;flex:0 0 25px!important;}',
    '#ovBody .luno-profile-country-art{display:block!important;width:25px!important;height:25px!important;object-fit:contain!important;}',
    '#ovBody .luno-profile-empty-rank,#ovBody .luno-profile-empty-season{border:1px dashed rgba(240,207,118,.36)!important;border-radius:6px!important;background:linear-gradient(145deg,rgba(76,53,112,.42),rgba(19,55,68,.46))!important;box-shadow:inset 0 1px 4px rgba(0,0,0,.32)!important;}',
    '#ovBody .is-luno-profile .pf2-levelrow{display:grid!important;grid-template-columns:51px minmax(0,1fr)!important;align-items:center!important;gap:9px!important;margin:11px auto 0!important;max-width:330px!important;}',
    '#ovBody .is-luno-profile .pf2-lvlbadge{width:51px!important;height:51px!important;}',
    '#ovBody .is-luno-profile .pf2-xp-track{height:13px!important;border:1px solid rgba(237,210,123,.38)!important;border-radius:5px!important;background:#100b26!important;overflow:hidden!important;}',
    '#ovBody .is-luno-profile .pf2-xp-fill{background:linear-gradient(90deg,#25b7aa,#76e5ce 55%,#ffd968)!important;box-shadow:0 0 9px rgba(70,224,202,.55)!important;}',
    '#ovBody .is-luno-profile .pf2-xp-lbl{margin-top:3px!important;font-family:Cinzel,Georgia,serif!important;font-size:9px!important;line-height:12px!important;color:#e9ddf4!important;}',
    '#ovBody .is-luno-profile .pf2-prem-banner{min-height:48px!important;padding:9px 12px!important;border:1px solid rgba(255,214,91,.6)!important;border-radius:8px!important;background:linear-gradient(125deg,#52307b,#1c5360)!important;font-family:Cinzel,Georgia,serif!important;font-size:10px!important;line-height:15px!important;color:#fff1bc!important;}',
    '#ovBody .is-luno-profile .pf2-about{margin:0!important;padding:12px!important;border:1px solid rgba(92,218,204,.5)!important;border-radius:8px!important;background:linear-gradient(145deg,#174b57,#292051 72%)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.1),0 5px 12px rgba(0,0,0,.3)!important;}',
    '#ovBody .is-luno-profile .pf2-about-head,#ovBody .is-luno-profile .pf2-ms-head{display:flex!important;align-items:center!important;gap:8px!important;min-height:38px!important;font-family:Cinzel,Georgia,serif!important;font-size:12px!important;line-height:16px!important;font-weight:900!important;color:#ffe184!important;}',
    '#ovBody .luno-profile-head-art{display:block!important;width:42px!important;height:42px!important;object-fit:contain!important;filter:drop-shadow(0 3px 5px rgba(0,0,0,.42))!important;}',
    '#ovBody .is-luno-profile .pf2-about-text{padding:7px 9px!important;border-left:2px solid rgba(255,216,105,.52)!important;font-size:11px!important;line-height:17px!important;color:#f5ecfa!important;}',
    '#ovBody .is-luno-profile .pf2-stats{display:grid!important;width:100%!important;min-width:0!important;grid-template-columns:repeat(4,minmax(0,1fr))!important;gap:7px!important;margin:0!important;}',
    '#ovBody .is-luno-profile .pf2-stat{display:grid!important;grid-template-rows:58px 23px 16px!important;align-items:center!important;justify-items:center!important;min-width:0!important;min-height:112px!important;padding:7px 3px!important;border:1px solid rgba(235,211,148,.34)!important;border-radius:8px!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.12),0 4px 10px rgba(0,0,0,.33)!important;overflow:hidden!important;}',
    '#ovBody .is-luno-profile .pf2-s-gold{background:linear-gradient(155deg,#584421,#2d1f3f)!important;}#ovBody .is-luno-profile .pf2-s-green{background:linear-gradient(155deg,#176051,#1e2949)!important;}#ovBody .is-luno-profile .pf2-s-blue{background:linear-gradient(155deg,#1d5870,#28224f)!important;}#ovBody .is-luno-profile .pf2-s-red{background:linear-gradient(155deg,#713947,#342044)!important;}',
    '#ovBody .is-luno-profile .pf2-stat-ic{width:58px!important;height:58px!important;margin:0!important;}',
    '#ovBody .luno-profile-stat-art{display:block!important;width:58px!important;height:58px!important;object-fit:contain!important;filter:drop-shadow(0 3px 5px rgba(0,0,0,.42))!important;}',
    '#ovBody .is-luno-profile .pf2-stat-val{font-family:Cinzel,Georgia,serif!important;font-size:17px!important;line-height:22px!important;font-weight:900!important;color:#fff5db!important;}',
    '#ovBody .is-luno-profile .pf2-stat-lbl{max-width:100%!important;font-family:Cinzel,Georgia,serif!important;font-size:7.5px!important;line-height:11px!important;font-weight:900!important;color:#e8dbef!important;white-space:nowrap!important;overflow:hidden!important;text-overflow:ellipsis!important;}',
    '#ovBody .is-luno-profile .pf2-ms{margin:0!important;padding:11px 12px 13px!important;border:1px solid rgba(138,110,194,.58)!important;border-radius:8px!important;background:linear-gradient(150deg,#2f2058,#132f48)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.1),0 5px 12px rgba(0,0,0,.3)!important;}',
    '#ovBody .is-luno-profile .pf2-ms-ic{display:flex!important;width:42px!important;height:42px!important;align-items:center!important;justify-content:center!important;margin:0!important;}',
    '#ovBody .luno-profile-section-art{display:block!important;width:42px!important;height:42px!important;object-fit:contain!important;}',
    '#ovBody .is-luno-profile .pf2-ms-divider{margin:2px 0 8px!important;color:#65d8ca!important;}',
    '#ovBody .is-luno-profile .pf2-ms-row{display:grid!important;width:100%!important;min-width:0!important;grid-template-columns:repeat(5,minmax(0,1fr))!important;gap:5px!important;overflow:hidden!important;}',
    '#ovBody .is-luno-profile .pf2-ms-item{min-width:0!important;padding:8px 2px!important;border:1px solid rgba(231,214,255,.15)!important;border-radius:6px!important;background:rgba(7,12,31,.36)!important;}',
    '#ovBody .is-luno-profile .pf2-ms-val{font-size:16px!important;line-height:21px!important;font-weight:900!important;}',
    '#ovBody .is-luno-profile .pf2-ms-lbl{font-family:Cinzel,Georgia,serif!important;font-size:6.8px!important;line-height:10px!important;font-weight:900!important;color:#ded3e8!important;}',
    '#ovBody .is-luno-profile .pf2-streaks{display:grid!important;grid-template-columns:repeat(2,minmax(0,1fr))!important;gap:8px!important;margin:0!important;}',
    '#ovBody .is-luno-profile .pf2-strk{position:relative!important;display:flex!important;flex-direction:column!important;align-items:center!important;min-height:164px!important;padding:9px 7px!important;border:1px solid rgba(236,207,130,.38)!important;border-radius:8px!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.12),0 5px 12px rgba(0,0,0,.31)!important;overflow:hidden!important;}',
    '#ovBody .is-luno-profile .pf2-strk-login{background:linear-gradient(150deg,#733743,#342049 62%,#164b55)!important;}#ovBody .is-luno-profile .pf2-strk-prem,#ovBody .is-luno-profile .pf2-strk-noprem{background:linear-gradient(150deg,#4e2f76,#213f58)!important;}',
    '#ovBody .is-luno-profile .pf2-strk-ic{width:78px!important;height:78px!important;margin:0!important;}',
    '#ovBody .luno-profile-streak-art{display:block!important;width:78px!important;height:78px!important;object-fit:contain!important;filter:drop-shadow(0 4px 6px rgba(0,0,0,.42))!important;}',
    '#ovBody .is-luno-profile .pf2-strk-val{margin:0!important;font-family:Cinzel,Georgia,serif!important;font-size:22px!important;line-height:26px!important;font-weight:900!important;color:#ffe082!important;}',
    '#ovBody .is-luno-profile .pf2-strk-lbl{font-family:Cinzel,Georgia,serif!important;font-size:8.5px!important;line-height:12px!important;font-weight:900!important;color:#fff1de!important;text-align:center!important;}',
    '#ovBody .is-luno-profile .pf2-strk-sub{margin-top:3px!important;font-size:8px!important;line-height:11px!important;color:#d9d0e3!important;text-align:center!important;}',
    '#ovBody .is-luno-profile .pf2-bottom{display:grid!important;grid-template-columns:repeat(2,minmax(0,1fr))!important;gap:8px!important;margin:0!important;}',
    '#ovBody .is-luno-profile .pf2-bcard{display:grid!important;grid-template-columns:58px minmax(0,1fr)!important;align-items:center!important;min-height:78px!important;padding:8px!important;border:1px solid rgba(115,211,200,.4)!important;border-radius:8px!important;background:linear-gradient(145deg,#1c4b58,#29204f)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.09),0 4px 10px rgba(0,0,0,.28)!important;}',
    '#ovBody .is-luno-profile .pf2-bcard:nth-child(3){grid-column:1/-1!important;background:linear-gradient(145deg,#49306f,#164c58)!important;border-color:rgba(245,205,91,.5)!important;}',
    '#ovBody .is-luno-profile .pf2-bic{display:flex!important;width:54px!important;height:54px!important;align-items:center!important;justify-content:center!important;margin:0!important;}',
    '#ovBody .luno-profile-bottom-art{display:block!important;width:54px!important;height:54px!important;object-fit:contain!important;}',
    '#ovBody .is-luno-profile .pf2-btitle{font-family:Cinzel,Georgia,serif!important;font-size:7.5px!important;line-height:11px!important;font-weight:900!important;color:#d9cae4!important;}',
    '#ovBody .is-luno-profile .pf2-bval{margin-top:3px!important;font-family:Cinzel,Georgia,serif!important;font-size:11px!important;line-height:15px!important;font-weight:900!important;color:#fff0c0!important;white-space:normal!important;}',
    '#ovBody .is-luno-profile .luno-achievement-section{padding:0!important;border:0!important;background:transparent!important;box-shadow:none!important;}',
    '#ovBody .is-luno-profile .luno-achievement-section>.pf2-ms-head{min-height:54px!important;padding:6px 10px!important;border:1px solid rgba(245,208,105,.46)!important;border-radius:8px!important;background:linear-gradient(145deg,#48306c,#174b58)!important;}',
    '#ovBody .is-luno-profile .luno-achievement-section>.pf2-ms-divider{display:none!important;}',
    '#ovBody .is-luno-profile .mp-ach-list{display:flex!important;flex-direction:column!important;gap:7px!important;margin-top:8px!important;}#ovBody .is-luno-profile .mp-ach-more-wrap{flex-direction:column!important;gap:7px!important;margin-top:7px!important;}#ovBody .is-luno-profile .mp-ach-more-wrap[style*="display:none"]{display:none!important;}#ovBody .is-luno-profile .mp-ach-more-wrap:not([style*="display:none"]){display:flex!important;}',
    '#ovBody .is-luno-profile .mp-ach{position:relative!important;display:grid!important;grid-template-columns:64px minmax(0,1fr) auto!important;align-items:center!important;gap:8px!important;min-height:98px!important;padding:8px 8px 8px 5px!important;border:1px solid color-mix(in srgb,var(--ar) 58%,#2b214d)!important;border-radius:8px!important;background:linear-gradient(145deg,color-mix(in srgb,var(--ar) 22%,#2a1b4e),#142d43 80%)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.09),0 3px 8px rgba(0,0,0,.3)!important;overflow:hidden!important;}',
    '#ovBody .is-luno-profile .mp-ach-icon{position:relative!important;display:flex!important;width:64px!important;height:64px!important;align-items:center!important;justify-content:center!important;border:0!important;background:transparent!important;font-size:0!important;}',
    '#ovBody .luno-achievement-art{display:block!important;width:64px!important;height:64px!important;object-fit:contain!important;filter:drop-shadow(0 3px 5px rgba(0,0,0,.42))!important;}',
    '#ovBody .is-luno-profile .mp-ach-off .luno-achievement-art{filter:grayscale(.72) saturate(.55) brightness(.7) drop-shadow(0 3px 4px rgba(0,0,0,.45))!important;opacity:.72!important;}',
    '#ovBody .is-luno-profile .mp-ach-off{opacity:1!important;filter:none!important;}#ovBody .is-luno-profile .mp-ach-off .mp-ach-name{color:#d5cbe0!important;text-shadow:none!important;}#ovBody .is-luno-profile .mp-ach-off .mp-ach-desc,#ovBody .is-luno-profile .mp-ach-off .mp-ach-cnt{color:#aaa0b8!important;}',
    '#ovBody .is-luno-profile .mp-ach-off .mp-ach-icon::after{content:""!important;position:absolute!important;right:0!important;bottom:0!important;width:17px!important;height:17px!important;border:1px solid rgba(255,225,153,.5)!important;border-radius:50%!important;background:#261a3f!important;box-shadow:inset 0 0 0 4px #261a3f!important;}',
    '#ovBody .is-luno-profile .mp-ach-name{font-family:Cinzel,Georgia,serif!important;font-size:10px!important;line-height:14px!important;font-weight:900!important;color:#fff1c7!important;}',
    '#ovBody .is-luno-profile .mp-ach-desc{margin-top:2px!important;font-size:8.5px!important;line-height:12px!important;color:#ddd3e8!important;}',
    '#ovBody .is-luno-profile .mp-ach-progress{margin-top:5px!important;gap:5px!important;}#ovBody .is-luno-profile .mp-ach-bar{height:7px!important;border-radius:4px!important;background:#0b1228!important;}#ovBody .is-luno-profile .mp-ach-fill{border-radius:4px!important;background:linear-gradient(90deg,#2bc2b1,#f1ca5b)!important;}#ovBody .is-luno-profile .mp-ach-cnt{font-size:8px!important;color:#f7eac7!important;}',
    '#ovBody .is-luno-profile .mp-ach-reward{font-size:8px!important;line-height:11px!important;color:#ffe083!important;}#ovBody .is-luno-profile .mp-ach-claim{min-width:36px!important;height:32px!important;border-radius:7px!important;background:linear-gradient(180deg,#f7d86c,#b87b1e)!important;color:#271539!important;font-family:Cinzel,Georgia,serif!important;font-size:9px!important;font-weight:900!important;}#ovBody .is-luno-profile .mp-ach-check{color:#70e0c9!important;font-size:19px!important;}',
    '#ovBody .is-luno-profile .mp-ach-more-btn{width:100%!important;min-height:42px!important;margin-top:8px!important;border:1px solid rgba(100,221,207,.48)!important;border-radius:8px!important;background:linear-gradient(145deg,#1e5360,#34255c)!important;color:#fff0c6!important;font-family:Cinzel,Georgia,serif!important;font-size:9px!important;line-height:13px!important;font-weight:900!important;}',
    '#ovBody .is-luno-profile .mp-history-btn,#ovBody .is-luno-profile .mp-signout{display:flex!important;align-items:center!important;gap:9px!important;width:100%!important;min-height:64px!important;margin:0!important;padding:7px 12px!important;border-radius:8px!important;font-family:Cinzel,Georgia,serif!important;font-size:11px!important;line-height:15px!important;font-weight:900!important;}',
    '#ovBody .is-luno-profile .mp-history-btn{border:1px solid rgba(105,221,208,.55)!important;background:linear-gradient(145deg,#1c5360,#37245e)!important;color:#fff0c8!important;}#ovBody .is-luno-profile .mp-signout{justify-content:center!important;border:1px solid rgba(236,111,124,.5)!important;background:linear-gradient(145deg,#652e45,#34203f)!important;color:#ffdce1!important;}',
    '#ovBody .is-luno-profile .mp-hist-ic,#ovBody .is-luno-profile .mp-signout>span:first-child{display:flex!important;width:50px!important;height:50px!important;align-items:center!important;justify-content:center!important;flex:0 0 50px!important;}',
    '#ovBody .luno-profile-action-art{display:block!important;width:50px!important;height:50px!important;object-fit:contain!important;}',
    '#ovBody .is-luno-pass{display:flex!important;flex-direction:column!important;gap:10px!important;width:100%!important;min-width:0!important;padding:2px 0 16px!important;color:#f8f1ff!important;}',
    '#ovBody .is-luno-pass .lpx-banner{margin:0!important;padding:10px!important;border:1px solid rgba(241,211,119,.58)!important;border-radius:8px!important;background:linear-gradient(145deg,#164d56 0%,#302254 58%,#563044 100%)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.13),0 6px 14px rgba(0,0,0,.36)!important;overflow:hidden!important;}',
    '#ovBody .is-luno-pass .lpx-banner-bg,#ovBody .is-luno-pass .lpx-banner-stars,#ovBody .is-luno-pass .lpx-up-bg{display:none!important;}',
    '#ovBody .is-luno-pass .luno-pass-season-head{display:grid!important;grid-template-columns:72px minmax(0,1fr)!important;align-items:center!important;gap:9px!important;min-height:72px!important;margin-bottom:8px!important;}',
    '#ovBody .is-luno-pass .luno-pass-season-art{display:block!important;width:72px!important;height:72px!important;object-fit:contain!important;filter:drop-shadow(0 4px 6px rgba(0,0,0,.42))!important;}',
    '#ovBody .is-luno-pass .luno-pass-season-copy{min-width:0!important;}',
    '#ovBody .is-luno-pass .lpx-season-tag{margin:0 0 3px!important;font-family:Cinzel,Georgia,serif!important;font-size:8.5px!important;line-height:12px!important;font-weight:900!important;letter-spacing:0!important;color:#86e2d5!important;text-transform:uppercase!important;text-shadow:0 1px 2px rgba(0,0,0,.7)!important;}',
    '#ovBody .is-luno-pass .lpx-season-name{margin:0!important;background:none!important;-webkit-text-fill-color:initial!important;animation:none!important;font-family:Cinzel,Georgia,serif!important;font-size:19px!important;line-height:24px!important;font-weight:900!important;letter-spacing:0!important;color:#ffe181!important;text-shadow:0 2px 3px rgba(0,0,0,.62)!important;}',
    '#ovBody .is-luno-pass .lpx-banner-row{display:grid!important;grid-template-columns:58px minmax(0,1fr) 68px!important;align-items:center!important;gap:8px!important;}',
    '#ovBody .is-luno-pass .lpx-level-box{display:flex!important;flex-direction:column!important;align-items:center!important;justify-content:center!important;width:58px!important;height:58px!important;padding:0!important;border:0!important;border-radius:0!important;background:transparent url("assets/luno-art/pass-level-frame-v5.png") center/contain no-repeat!important;box-shadow:none!important;}',
    '#ovBody .is-luno-pass .lpx-lvl-num{font-family:Cinzel,Georgia,serif!important;font-size:19px!important;line-height:20px!important;font-weight:900!important;letter-spacing:0!important;color:#fff4d2!important;text-shadow:0 2px 3px #130827!important;}',
    '#ovBody .is-luno-pass .lpx-lvl-lbl{margin:0!important;font-family:Cinzel,Georgia,serif!important;font-size:5.8px!important;line-height:8px!important;font-weight:900!important;letter-spacing:0!important;color:#89e2d5!important;}',
    '#ovBody .is-luno-pass .lpx-xp-block{min-width:0!important;}',
    '#ovBody .is-luno-pass .lpx-xp-text{margin:0 0 5px!important;font-family:Cinzel,Georgia,serif!important;font-size:9px!important;line-height:12px!important;font-weight:900!important;letter-spacing:0!important;color:#fff2cf!important;}',
    '#ovBody .is-luno-pass .lpx-xp-bar{height:11px!important;border:1px solid rgba(240,218,163,.35)!important;border-radius:5px!important;background:#0b1729!important;box-shadow:inset 0 2px 4px rgba(0,0,0,.54)!important;}',
    '#ovBody .is-luno-pass .lpx-xp-fill{border-radius:4px!important;background:linear-gradient(90deg,#31bfb0,#83e5cf 55%,#ffd660)!important;box-shadow:0 0 8px rgba(83,222,204,.45)!important;}',
    '#ovBody .is-luno-pass .lpx-xp-next{margin-top:4px!important;font-family:system-ui,sans-serif!important;font-size:7.5px!important;line-height:10px!important;font-style:normal!important;color:#d8cfe5!important;white-space:normal!important;}',
    '#ovBody .is-luno-pass .lpx-ends{display:flex!important;flex-direction:column!important;align-items:center!important;justify-content:center!important;min-width:68px!important;min-height:48px!important;padding:5px 3px!important;border:1px solid rgba(239,171,112,.54)!important;border-radius:7px!important;background:linear-gradient(150deg,#6c3442,#26334d)!important;}',
    '#ovBody .is-luno-pass .lpx-ends-val{font-family:Cinzel,Georgia,serif!important;font-size:10.5px!important;line-height:14px!important;font-weight:900!important;letter-spacing:0!important;color:#ffd49b!important;text-shadow:0 1px 2px rgba(0,0,0,.6)!important;white-space:nowrap!important;}',
    '#ovBody .is-luno-pass .lpx-ends-lbl{margin:0!important;font-family:Cinzel,Georgia,serif!important;font-size:6px!important;line-height:8px!important;font-weight:900!important;letter-spacing:0!important;color:#f1e5ed!important;}',
    '#ovBody .is-luno-pass .luno-pass-missions{display:grid!important;grid-template-columns:66px minmax(0,1fr) 24px!important;align-items:center!important;gap:8px!important;min-height:78px!important;margin:0!important;padding:5px 9px 5px 5px!important;border:1px solid rgba(96,221,205,.55)!important;border-radius:8px!important;background:linear-gradient(145deg,#1c5860,#34265e 72%)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.11),0 4px 10px rgba(0,0,0,.3)!important;cursor:pointer!important;overflow:hidden!important;}',
    '#ovBody .is-luno-pass .luno-pass-missions:active{transform:translateY(1px) scale(.99)!important;}',
    '#ovBody .is-luno-pass .luno-pass-missions-art{display:block!important;width:66px!important;height:66px!important;object-fit:contain!important;filter:drop-shadow(0 3px 5px rgba(0,0,0,.38))!important;}',
    '#ovBody .is-luno-pass .luno-pass-missions-copy{min-width:0!important;}',
    '#ovBody .is-luno-pass .luno-pass-missions-title{font-family:Cinzel,Georgia,serif!important;font-size:12px!important;line-height:16px!important;font-weight:900!important;letter-spacing:0!important;color:#fff0bd!important;}',
    '#ovBody .is-luno-pass .luno-pass-missions-sub{margin-top:2px!important;font-family:system-ui,sans-serif!important;font-size:9px!important;line-height:12px!important;color:#e2d9eb!important;}',
    '#ovBody .is-luno-pass .luno-pass-arrow{font-family:Arial,sans-serif!important;font-size:27px!important;line-height:27px!important;font-weight:700!important;color:#ffe078!important;text-align:center!important;}',
    '#ovBody .is-luno-pass .lpx-upgrade{min-height:90px!important;margin:0!important;padding:6px 8px!important;border:1px solid rgba(250,212,95,.68)!important;border-radius:8px!important;background:linear-gradient(145deg,#623a31,#3b2756 60%,#17525a)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.12),0 5px 12px rgba(0,0,0,.33)!important;}',
    '#ovBody .is-luno-pass .lpx-up-content{display:grid!important;grid-template-columns:82px minmax(0,1fr) 72px!important;align-items:center!important;gap:6px!important;}',
    '#ovBody .is-luno-pass .lpx-up-crown{display:flex!important;width:82px!important;height:76px!important;align-items:center!important;justify-content:center!important;font-size:0!important;animation:none!important;filter:none!important;}',
    '#ovBody .is-luno-pass .luno-pass-premium-art{display:block!important;width:82px!important;height:76px!important;object-fit:contain!important;filter:drop-shadow(0 3px 5px rgba(0,0,0,.4))!important;}',
    '#ovBody .is-luno-pass .lpx-up-text{min-width:0!important;}',
    '#ovBody .is-luno-pass .lpx-up-title{margin:0 0 3px!important;font-family:Cinzel,Georgia,serif!important;font-size:12px!important;line-height:16px!important;font-weight:900!important;letter-spacing:0!important;color:#ffe17c!important;text-shadow:0 1px 2px rgba(0,0,0,.6)!important;}',
    '#ovBody .is-luno-pass .lpx-up-desc{font-family:system-ui,sans-serif!important;font-size:8px!important;line-height:11px!important;color:#f2dfe2!important;}',
    '#ovBody .is-luno-pass .lpx-up-price{display:flex!important;flex-direction:column!important;align-items:stretch!important;justify-content:center!important;min-width:0!important;text-align:center!important;}',
    '#ovBody .is-luno-pass .lpx-up-val{display:flex!important;align-items:center!important;justify-content:center!important;gap:3px!important;margin:0 0 5px!important;font-family:Cinzel,Georgia,serif!important;font-size:11px!important;line-height:15px!important;font-weight:900!important;color:#fff5db!important;}',
    '#ovBody .is-luno-pass .luno-pass-price-gem{display:block!important;width:18px!important;height:18px!important;object-fit:contain!important;}',
    '#ovBody .is-luno-pass .lpx-up-btn{display:flex!important;align-items:center!important;justify-content:center!important;min-height:29px!important;padding:4px 3px!important;border:1px solid rgba(255,240,169,.68)!important;border-radius:7px!important;background:linear-gradient(180deg,#f7da6f,#bb7f24)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.38),0 2px 5px rgba(0,0,0,.4)!important;font-family:Cinzel,Georgia,serif!important;font-size:7px!important;line-height:9px!important;font-weight:900!important;letter-spacing:0!important;color:#271539!important;white-space:nowrap!important;}',
    '#ovBody .is-luno-pass .lpx-tracks-header{display:grid!important;grid-template-columns:minmax(0,1fr) 44px minmax(0,1fr)!important;gap:5px!important;min-height:60px!important;margin:0!important;padding:4px 0!important;border:0!important;}',
    '#ovBody .is-luno-pass .lpx-th-free,#ovBody .is-luno-pass .lpx-th-prem{display:grid!important;grid-template-columns:42px minmax(0,1fr)!important;align-items:center!important;justify-content:stretch!important;gap:5px!important;min-width:0!important;padding:3px 7px!important;border:1px solid rgba(255,255,255,.2)!important;border-radius:8px!important;font-family:Cinzel,Georgia,serif!important;font-size:8.5px!important;line-height:12px!important;font-weight:900!important;letter-spacing:0!important;text-shadow:0 1px 2px rgba(0,0,0,.62)!important;}',
    '#ovBody .is-luno-pass .lpx-th-free{background:linear-gradient(145deg,#1c626a,#263253)!important;border-color:rgba(102,225,211,.46)!important;color:#e9ffff!important;}#ovBody .is-luno-pass .lpx-th-prem{background:linear-gradient(145deg,#5a354e,#39265e)!important;border-color:rgba(247,209,93,.55)!important;color:#ffe184!important;}',
    '#ovBody .is-luno-pass .luno-pass-track-art{display:block!important;width:42px!important;height:42px!important;object-fit:contain!important;}',
    '#ovBody .is-luno-pass .lpx-th-lvl{align-self:center!important;font-family:Cinzel,Georgia,serif!important;font-size:9px!important;line-height:12px!important;font-weight:900!important;letter-spacing:0!important;color:#d9cce8!important;text-align:center!important;}',
    '#ovBody .is-luno-pass .lpx-th-active{position:absolute!important;right:3px!important;bottom:2px!important;margin:0!important;padding:1px 3px!important;border-radius:3px!important;background:#58d7c2!important;font-size:5.5px!important;line-height:8px!important;letter-spacing:0!important;color:#102b35!important;}#ovBody .is-luno-pass .lpx-th-prem{position:relative!important;}',
    '#ovBody .is-luno-pass .lpx-track{display:flex!important;flex-direction:column!important;gap:7px!important;}',
    '#ovBody .is-luno-pass .lpx-row{display:grid!important;grid-template-columns:minmax(0,1fr) 44px minmax(0,1fr)!important;align-items:center!important;gap:5px!important;}',
    '#ovBody .is-luno-pass .lpx-cell{display:grid!important;grid-template-rows:52px minmax(22px,auto)!important;align-items:center!important;justify-items:center!important;min-width:0!important;min-height:88px!important;padding:5px 4px 6px!important;border:1px solid rgba(130,113,176,.55)!important;border-radius:8px!important;background:linear-gradient(150deg,#28214e,#132e43)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.09),0 3px 8px rgba(0,0,0,.3)!important;overflow:visible!important;opacity:1!important;}',
    '#ovBody .is-luno-pass .lpx-cell-free{border-color:rgba(95,216,204,.44)!important;background:linear-gradient(150deg,#1c505b,#252146)!important;}#ovBody .is-luno-pass .lpx-cell-prem{border-color:rgba(234,193,85,.44)!important;background:linear-gradient(150deg,#533443,#2d214d)!important;}',
    '#ovBody .is-luno-pass .lpx-cell-locked{filter:saturate(.72) brightness(.8)!important;}#ovBody .is-luno-pass .lpx-cell-claimed{filter:saturate(.62)!important;opacity:.65!important;}#ovBody .is-luno-pass .lpx-cell-claim{border-color:var(--rc)!important;animation:lpx-cell-glow 1.8s ease-in-out infinite!important;}',
    '#ovBody .is-luno-pass .lpx-cell-icon{display:flex!important;align-items:center!important;justify-content:center!important;width:100%!important;height:52px!important;margin:0!important;font-size:0!important;filter:none!important;}',
    '#ovBody .is-luno-pass .luno-pass-reward-art{display:block!important;width:52px!important;height:52px!important;object-fit:contain!important;filter:drop-shadow(0 3px 4px rgba(0,0,0,.42))!important;}#ovBody .is-luno-pass .lpx-cell[data-reward-type="gold"] .luno-pass-reward-art,#ovBody .is-luno-pass .lpx-cell[data-reward-type="gem"] .luno-pass-reward-art{width:46px!important;height:46px!important;}',
    '#ovBody .is-luno-pass .luno-pass-art-pending .lpx-cell-icon{height:38px!important;}#ovBody .is-luno-pass .luno-pass-art-pending{grid-template-rows:38px minmax(32px,auto)!important;}',
    '#ovBody .is-luno-pass .lpx-cell-name{display:flex!important;align-items:center!important;justify-content:center!important;width:100%!important;max-width:100%!important;min-height:22px!important;padding:0 2px!important;font-family:Cinzel,Georgia,serif!important;font-size:8.2px!important;line-height:11px!important;font-weight:900!important;letter-spacing:0!important;color:#fff1dc!important;text-align:center!important;overflow:visible!important;text-shadow:0 1px 2px rgba(0,0,0,.65)!important;}',
    '#ovBody .is-luno-pass .lpx-level-pill{position:relative!important;display:flex!important;align-items:center!important;justify-content:center!important;width:44px!important;height:44px!important;margin:0!important;border:0!important;border-radius:0!important;background:var(--luno-level-frame) center/contain no-repeat!important;box-shadow:none!important;font-family:Cinzel,Georgia,serif!important;font-size:12px!important;line-height:16px!important;font-weight:900!important;letter-spacing:0!important;color:#fff2cb!important;text-shadow:0 2px 3px #16082a!important;}',
    '#ovBody .is-luno-pass .lpx-row-unlocked .lpx-level-pill,#ovBody .is-luno-pass .lpx-row-current .lpx-level-pill{border:0!important;background:var(--luno-level-frame) center/contain no-repeat!important;color:#fff2cb!important;}#ovBody .is-luno-pass .lpx-row-current .lpx-level-pill{animation:lpx-now-pulse 1.8s ease-in-out infinite!important;filter:drop-shadow(0 0 7px rgba(255,216,96,.62))!important;}',
    '#ovBody .is-luno-pass .lpx-now{top:0!important;right:0!important;width:8px!important;height:8px!important;border:1px solid #24133d!important;background:#69dfcc!important;box-shadow:0 0 6px rgba(105,223,204,.7)!important;}',
    '#ovBody .is-luno-pass .lpx-cell-lock{position:absolute!important;top:5px!important;right:5px!important;width:17px!important;height:20px!important;font-size:0!important;opacity:.9!important;}',
    '#ovBody .is-luno-pass .luno-pass-lock-body{position:absolute!important;left:1px!important;bottom:0!important;width:15px!important;height:13px!important;border:1px solid rgba(255,233,168,.65)!important;border-radius:3px!important;background:linear-gradient(180deg,#cfa94f,#775333)!important;box-shadow:0 1px 3px rgba(0,0,0,.5)!important;}#ovBody .is-luno-pass .luno-pass-lock-shackle{position:absolute!important;left:3px!important;top:-8px!important;width:7px!important;height:8px!important;border:2px solid #d7b969!important;border-bottom:0!important;border-radius:7px 7px 0 0!important;}#ovBody .is-luno-pass .luno-pass-lock-key{position:absolute!important;left:6px!important;top:4px!important;width:3px!important;height:4px!important;border-radius:50% 50% 1px 1px!important;background:#39263d!important;}',
    '#ovBody .is-luno-pass .lpx-cell-tap{top:4px!important;right:4px!important;padding:2px 5px!important;border-radius:4px!important;font-family:Cinzel,Georgia,serif!important;font-size:6.5px!important;line-height:9px!important;letter-spacing:0!important;}#ovBody .is-luno-pass .lpx-cell-check{top:4px!important;right:5px!important;font-size:14px!important;}',
    '#ovBody .is-luno-pass .lpx-row-big .lpx-cell{min-height:96px!important;padding:5px 4px 6px!important;}#ovBody .is-luno-pass .lpx-row-final{margin-top:2px!important;}#ovBody .is-luno-pass .lpx-row-final .lpx-cell{border-color:rgba(247,210,95,.58)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.12),0 0 12px rgba(246,205,85,.22)!important;}',
    '#ovBody .is-luno-friends{display:flex!important;flex-direction:column!important;gap:10px!important;width:100%!important;min-width:0!important;padding:2px 0 16px!important;}',
    '#ovBody .is-luno-friends .fh-search-box{display:grid!important;grid-template-columns:42px minmax(0,1fr) 30px!important;align-items:center!important;gap:5px!important;min-height:58px!important;margin:0!important;padding:5px 7px!important;border:1px solid rgba(86,219,205,.58)!important;border-radius:8px!important;background:linear-gradient(145deg,#174c58,#2e2452)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.11),0 4px 10px rgba(0,0,0,.3)!important;}',
    '#ovBody .is-luno-friends .fh-search-box:focus-within{border-color:rgba(255,216,102,.72)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.12),0 0 12px rgba(77,215,200,.28)!important;}',
    '#ovBody .is-luno-friends .fh-search-icon{display:flex!important;width:42px!important;height:42px!important;align-items:center!important;justify-content:center!important;font-size:0!important;filter:none!important;}',
    '#ovBody .is-luno-friends .luno-friend-search-art{display:block!important;width:42px!important;height:42px!important;object-fit:contain!important;}',
    '#ovBody .is-luno-friends .fh-search-input{width:100%!important;min-width:0!important;padding:7px 3px!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:11px!important;line-height:15px!important;font-weight:700!important;letter-spacing:0!important;color:#fff3df!important;text-transform:none!important;}',
    '#ovBody .is-luno-friends .fh-search-input::placeholder{font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:10px!important;font-style:normal!important;color:#bdb1cc!important;}',
    '#ovBody .is-luno-friends .fh-search-clear{display:flex!important;width:28px!important;height:28px!important;align-items:center!important;justify-content:center!important;padding:0!important;border:1px solid rgba(240,220,255,.28)!important;border-radius:50%!important;background:#40335f!important;font-family:Arial,sans-serif!important;font-size:11px!important;color:#eee4f4!important;}',
    '#ovBody .is-luno-friends .fh-results{margin:0!important;padding:0!important;}',
    '#ovBody .is-luno-friends .fh-tabs{display:grid!important;grid-template-columns:repeat(3,minmax(0,1fr))!important;gap:5px!important;width:100%!important;min-width:0!important;margin:0!important;overflow:visible!important;}',
    '#ovBody .is-luno-friends .fh-tab{position:relative!important;display:grid!important;grid-template-columns:27px minmax(0,1fr)!important;align-items:center!important;justify-content:stretch!important;gap:3px!important;min-width:0!important;min-height:52px!important;padding:4px 5px!important;border:1px solid rgba(135,115,179,.5)!important;border-radius:8px!important;background:linear-gradient(145deg,#282148,#173d4d)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.08),0 3px 7px rgba(0,0,0,.25)!important;font-family:Cinzel,Georgia,serif!important;font-size:8px!important;line-height:11px!important;font-weight:900!important;letter-spacing:0!important;color:#e5dbea!important;overflow:hidden!important;text-shadow:0 1px 2px rgba(0,0,0,.6)!important;}',
    '#ovBody .is-luno-friends .fh-tab>span:nth-child(2){min-width:0!important;white-space:nowrap!important;overflow:hidden!important;text-overflow:ellipsis!important;}',
    '#ovBody .is-luno-friends .fh-tab-ic{display:flex!important;width:27px!important;height:34px!important;align-items:center!important;justify-content:center!important;font-size:0!important;}',
    '#ovBody .is-luno-friends .luno-friend-tab-art{display:block!important;width:34px!important;height:34px!important;max-width:none!important;object-fit:contain!important;}',
    '#ovBody .is-luno-friends .fh-tab-cnt{position:absolute!important;z-index:2!important;top:3px!important;right:3px!important;display:flex!important;min-width:16px!important;height:16px!important;align-items:center!important;justify-content:center!important;margin:0!important;padding:0 3px!important;border:1px solid rgba(255,255,255,.08)!important;border-radius:5px!important;background:#15142d!important;font-family:Cinzel,Georgia,serif!important;font-size:7px!important;line-height:9px!important;font-weight:900!important;color:#e8dff1!important;opacity:1!important;box-shadow:0 1px 3px rgba(0,0,0,.35)!important;}',
    '#ovBody .is-luno-friends #fhTabFriends.fh-tab-active{border-color:rgba(84,222,207,.72)!important;background:linear-gradient(145deg,#1c6268,#33265a)!important;color:#fff2c9!important;}#ovBody .is-luno-friends #fhTabRequests.fh-tab-active{border-color:rgba(239,134,133,.72)!important;background:linear-gradient(145deg,#713843,#34265b)!important;color:#fff0dc!important;}#ovBody .is-luno-friends #fhTabRank.fh-tab-active{border-color:rgba(247,209,92,.72)!important;background:linear-gradient(145deg,#634925,#34265a)!important;color:#ffe081!important;}',
    '#ovBody .is-luno-friends .fh-tab-cnt-alert{background:#d44d62!important;color:#fff!important;animation:fhAlertPulse 2.2s ease-in-out infinite!important;}',
    '#ovBody .is-luno-friends .fh-content{width:100%!important;min-width:0!important;}',
    '#ovBody .is-luno-friends .fh-section-label{display:flex!important;align-items:center!important;min-height:24px!important;margin:0 3px 6px!important;font-family:Cinzel,Georgia,serif!important;font-size:9px!important;line-height:12px!important;font-weight:900!important;letter-spacing:0!important;color:#72decf!important;}',
    '#ovBody .is-luno-friends .fh-list,#ovBody .is-luno-friends .fh-reqs-list{display:flex!important;flex-direction:column!important;gap:7px!important;margin:0!important;padding:0!important;}',
    '#ovBody .is-luno-friends .fh-row{display:grid!important;grid-template-columns:48px minmax(0,1fr) auto!important;align-items:center!important;gap:7px!important;min-width:0!important;min-height:66px!important;padding:7px!important;border:1px solid rgba(112,202,194,.34)!important;border-radius:8px!important;background:linear-gradient(145deg,#193e4d,#2b204d 76%)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.08),0 3px 8px rgba(0,0,0,.28)!important;}',
    '#ovBody .is-luno-friends .fh-row:hover{transform:none!important;border-color:rgba(244,208,103,.55)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.1),0 4px 10px rgba(0,0,0,.31)!important;}',
    '#ovBody .is-luno-friends .fh-av{display:flex!important;width:48px!important;height:48px!important;align-items:center!important;justify-content:center!important;border:1px solid rgba(255,255,255,.2)!important;border-radius:8px!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:19px!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.16),0 3px 6px rgba(0,0,0,.35)!important;}',
    '#ovBody .is-luno-friends .fh-info{min-width:0!important;}',
    '#ovBody .is-luno-friends .fh-name{max-width:100%!important;margin:0 0 3px!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:12.5px!important;line-height:16px!important;font-weight:800!important;letter-spacing:0!important;color:#fff2dc!important;text-transform:none!important;white-space:nowrap!important;overflow:hidden!important;text-overflow:ellipsis!important;}',
    '#ovBody .is-luno-friends .fh-meta{display:flex!important;align-items:center!important;gap:6px!important;min-width:0!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:8.5px!important;line-height:11px!important;font-weight:700!important;color:#cfc5d8!important;flex-wrap:nowrap!important;}',
    '#ovBody .is-luno-friends .fh-trophy,#ovBody .is-luno-friends .fh-req-meta,#ovBody .is-luno-friends .rk-pod-trophies,#ovBody .is-luno-friends .rk-row-trophies{display:inline-flex!important;align-items:center!important;justify-content:center!important;gap:3px!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-weight:800!important;letter-spacing:0!important;color:#ffe18b!important;white-space:nowrap!important;}',
    '#ovBody .is-luno-friends .luno-friend-trophy-art{display:block!important;width:16px!important;height:16px!important;object-fit:contain!important;flex:0 0 16px!important;}',
    '#ovBody .is-luno-friends .rk-rt-ic{display:flex!important;width:17px!important;height:17px!important;align-items:center!important;justify-content:center!important;font-size:0!important;}#ovBody .is-luno-friends .rk-rt-ic .luno-friend-trophy-art{width:16px!important;height:16px!important;}',
    '#ovBody .is-luno-friends .fh-arena{min-width:0!important;font-size:8px!important;line-height:11px!important;letter-spacing:0!important;white-space:nowrap!important;overflow:hidden!important;text-overflow:ellipsis!important;}',
    '#ovBody .is-luno-friends .fh-actions{display:flex!important;align-items:center!important;gap:2px!important;flex:0 0 auto!important;}',
    '#ovBody .is-luno-friends .fh-action-btn{display:flex!important;width:31px!important;height:31px!important;align-items:center!important;justify-content:center!important;padding:1px!important;border:1px solid rgba(236,218,255,.3)!important;border-radius:7px!important;background:linear-gradient(145deg,#2f2851,#193b4b)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.12),0 2px 5px rgba(0,0,0,.32)!important;font-size:0!important;}',
    '#ovBody .is-luno-friends .fh-action-dm{border-color:rgba(72,218,210,.5)!important;background:linear-gradient(145deg,#195d67,#273157)!important;}#ovBody .is-luno-friends .fh-action-invite{border-color:rgba(245,207,91,.58)!important;background:linear-gradient(145deg,#65471f,#38264f)!important;}#ovBody .is-luno-friends .fh-action-remove{border-color:rgba(239,104,116,.5)!important;background:linear-gradient(145deg,#67313f,#34233f)!important;}',
    '#ovBody .is-luno-friends .luno-friend-action-art{display:block!important;width:27px!important;height:27px!important;object-fit:contain!important;filter:drop-shadow(0 2px 2px rgba(0,0,0,.3))!important;}',
    '#ovBody .is-luno-friends .fh-req-row{display:grid!important;grid-template-columns:50px minmax(0,1fr) auto!important;align-items:center!important;gap:8px!important;min-height:70px!important;padding:8px!important;border:1px solid rgba(232,195,105,.4)!important;border-radius:8px!important;background:linear-gradient(145deg,#3f284f,#174753)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.09),0 3px 8px rgba(0,0,0,.29)!important;}',
    '#ovBody .is-luno-friends .fh-req-avatar{display:flex!important;width:50px!important;height:50px!important;align-items:center!important;justify-content:center!important;border:1px solid rgba(255,225,152,.42)!important;border-radius:8px!important;background:linear-gradient(145deg,#653b6d,#1d5760)!important;font-size:21px!important;}',
    '#ovBody .is-luno-friends .fh-req-name{font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:12.5px!important;line-height:16px!important;font-weight:800!important;letter-spacing:0!important;color:#fff0dc!important;text-transform:none!important;}',
    '#ovBody .is-luno-friends .fh-req-meta{justify-content:flex-start!important;margin-top:2px!important;font-size:9px!important;line-height:12px!important;}',
    '#ovBody .is-luno-friends .fh-req-actions{display:flex!important;gap:5px!important;}#ovBody .is-luno-friends .fh-req-btn{display:flex!important;width:39px!important;height:39px!important;align-items:center!important;justify-content:center!important;padding:2px!important;border:1px solid rgba(255,255,255,.28)!important;border-radius:8px!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.18),0 2px 5px rgba(0,0,0,.34)!important;font-size:0!important;}#ovBody .is-luno-friends .fh-req-accept{background:linear-gradient(145deg,#187861,#25465a)!important;border-color:rgba(91,228,193,.62)!important;}#ovBody .is-luno-friends .fh-req-reject{background:linear-gradient(145deg,#853845,#3a293f)!important;border-color:rgba(240,111,123,.62)!important;}',
    '#ovBody .is-luno-friends .fh-req-btn .luno-friend-action-art{width:34px!important;height:34px!important;}',
    '#ovBody .is-luno-friends .fh-empty{display:flex!important;flex-direction:column!important;align-items:center!important;justify-content:flex-start!important;min-height:300px!important;padding:18px 15px!important;border:0!important;background:transparent!important;font-style:normal!important;text-align:center!important;}',
    '#ovBody .is-luno-friends .luno-friend-empty-art{display:block!important;width:126px!important;height:126px!important;object-fit:contain!important;margin:0 auto 4px!important;filter:drop-shadow(0 5px 7px rgba(0,0,0,.38))!important;}',
    '#ovBody .is-luno-friends .luno-friend-empty-title{font-family:Cinzel,Georgia,serif!important;font-size:14px!important;line-height:19px!important;font-weight:900!important;letter-spacing:0!important;color:#fff0c5!important;text-shadow:0 2px 3px rgba(0,0,0,.58)!important;}',
    '#ovBody .is-luno-friends .luno-friend-empty-sub{max-width:280px!important;margin-top:5px!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:10.5px!important;line-height:15px!important;font-weight:600!important;color:#cfc5da!important;}',
    '#ovBody .is-luno-friends .rk-podium-bg{margin:0!important;padding:8px 8px 0!important;border:1px solid rgba(246,208,95,.52)!important;border-radius:8px!important;background:linear-gradient(145deg,#183f4e,#392454 72%)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.09),0 4px 10px rgba(0,0,0,.3)!important;}#ovBody .is-luno-friends .rk-podium-stars{display:none!important;}',
    '#ovBody .is-luno-friends .rk-podium-title{display:flex!important;align-items:center!important;justify-content:center!important;gap:7px!important;margin:0!important;font-family:Cinzel,Georgia,serif!important;font-size:11px!important;line-height:15px!important;font-weight:900!important;letter-spacing:0!important;color:#ffe181!important;}#ovBody .is-luno-friends .luno-friend-ranking-head-art{display:block!important;width:42px!important;height:42px!important;object-fit:contain!important;}',
    '#ovBody .is-luno-friends .rk-list-title{position:relative!important;z-index:2!important;clear:both!important;display:flex!important;min-height:18px!important;align-items:center!important;justify-content:center!important;margin:13px 0 8px!important;padding-top:1px!important;font-family:Cinzel,Georgia,serif!important;font-size:8.5px!important;line-height:13px!important;font-weight:900!important;letter-spacing:0!important;color:#e5d9ec!important;overflow:visible!important;text-shadow:0 1px 2px rgba(0,0,0,.58)!important;}#ovBody .is-luno-friends .rk-row{border:1px solid rgba(96,207,197,.3)!important;border-radius:8px!important;background:linear-gradient(145deg,#193e4d,#2c204b)!important;}#ovBody .is-luno-friends .rk-row-name{font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:11.5px!important;font-weight:800!important;letter-spacing:0!important;color:#fff0dc!important;}',
    '#ovBody .is-luno-missions{display:flex!important;flex-direction:column!important;gap:10px!important;width:100%!important;min-width:0!important;padding:2px 0 16px!important;}',
    '#ovBody .is-luno-missions .ms-header{display:grid!important;grid-template-columns:72px minmax(0,1fr) 78px!important;align-items:center!important;gap:7px!important;min-height:88px!important;margin:0!important;padding:6px 8px 6px 4px!important;border:1px solid rgba(244,205,91,.6)!important;border-radius:8px!important;background:linear-gradient(145deg,#174d56,#3b2757 68%,#653743)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.12),0 5px 12px rgba(0,0,0,.33)!important;}',
    '#ovBody .is-luno-missions .ms-hd-icon{display:flex!important;width:72px!important;height:72px!important;align-items:center!important;justify-content:center!important;font-size:0!important;filter:none!important;}',
    '#ovBody .is-luno-missions .luno-mission-hero-art{display:block!important;width:72px!important;height:72px!important;object-fit:contain!important;filter:drop-shadow(0 3px 5px rgba(0,0,0,.38))!important;}',
    '#ovBody .is-luno-missions .ms-hd-text{min-width:0!important;}#ovBody .is-luno-missions .ms-hd-title{margin:0!important;font-family:Cinzel,Georgia,serif!important;font-size:12px!important;line-height:16px!important;font-weight:900!important;letter-spacing:0!important;color:#ffe082!important;text-shadow:0 2px 3px rgba(0,0,0,.55)!important;}#ovBody .is-luno-missions .ms-hd-sub{margin-top:3px!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:9px!important;line-height:12px!important;font-weight:600!important;color:#eee1eb!important;}',
    '#ovBody .is-luno-missions .ms-hd-timer{display:flex!important;flex-direction:column!important;align-items:center!important;justify-content:center!important;min-width:78px!important;min-height:51px!important;padding:5px 3px!important;border:1px solid rgba(108,224,208,.46)!important;border-radius:7px!important;background:linear-gradient(145deg,#123947,#302545)!important;}#ovBody .is-luno-missions .ms-timer-val{font-family:Cinzel,Georgia,serif!important;font-size:11px!important;line-height:15px!important;font-weight:900!important;letter-spacing:0!important;color:#fff0c4!important;text-shadow:0 1px 2px rgba(0,0,0,.58)!important;}#ovBody .is-luno-missions .ms-timer-lbl{margin:1px 0 0!important;font-family:Cinzel,Georgia,serif!important;font-size:5.8px!important;line-height:8px!important;font-weight:900!important;letter-spacing:0!important;color:#83ddd1!important;}',
    '#ovBody .is-luno-missions .ms-tabs{display:grid!important;grid-template-columns:repeat(3,minmax(0,1fr))!important;gap:6px!important;width:100%!important;margin:0!important;}#ovBody .is-luno-missions .ms-tab{display:grid!important;grid-template-rows:50px 15px 14px!important;align-items:center!important;justify-items:center!important;min-width:0!important;min-height:87px!important;padding:4px 3px!important;border:1px solid rgba(129,111,173,.45)!important;border-radius:8px!important;background:linear-gradient(145deg,#29204b,#153e4b)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.08),0 3px 7px rgba(0,0,0,.25)!important;}#ovBody .is-luno-missions .ms-tab-active{border-color:rgba(246,206,92,.68)!important;background:linear-gradient(145deg,#623f29,#3c2955 62%,#18505a)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.11),0 3px 8px rgba(0,0,0,.29)!important;}',
    '#ovBody .is-luno-missions .ms-tab-ic{display:flex!important;width:52px!important;height:50px!important;align-items:center!important;justify-content:center!important;margin:0!important;font-size:0!important;filter:none!important;}#ovBody .is-luno-missions .luno-mission-tab-art{display:block!important;width:52px!important;height:52px!important;object-fit:contain!important;}#ovBody .is-luno-missions .ms-tab-name{font-family:Cinzel,Georgia,serif!important;font-size:9px!important;line-height:12px!important;font-weight:900!important;letter-spacing:0!important;color:#fff0d2!important;text-shadow:0 1px 2px rgba(0,0,0,.58)!important;}#ovBody .is-luno-missions .ms-tab-cnt{display:flex!important;min-width:25px!important;height:14px!important;align-items:center!important;justify-content:center!important;margin:0!important;padding:0 4px!important;border-radius:4px!important;background:#14152c!important;font-family:Cinzel,Georgia,serif!important;font-size:6.5px!important;line-height:9px!important;font-weight:900!important;letter-spacing:0!important;color:#dcd2e8!important;}',
    '#ovBody .is-luno-missions .ms-content{display:flex!important;flex-direction:column!important;gap:7px!important;width:100%!important;min-width:0!important;}#ovBody .is-luno-missions .ms-card{display:grid!important;grid-template-columns:68px minmax(0,1fr) 68px!important;align-items:center!important;gap:7px!important;min-width:0!important;min-height:91px!important;padding:7px!important;border:1px solid rgba(101,207,197,.34)!important;border-radius:8px!important;background:linear-gradient(145deg,#173f4d,#2b204b 76%)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.08),0 3px 8px rgba(0,0,0,.28)!important;overflow:hidden!important;opacity:1!important;}#ovBody .is-luno-missions .ms-card-bg{display:none!important;}#ovBody .is-luno-missions .ms-complete{border-color:rgba(246,208,93,.72)!important;background:linear-gradient(145deg,#3c4938,#3c274f)!important;animation:ms-complete-glow 2.2s ease-in-out infinite!important;}#ovBody .is-luno-missions .ms-claimed{border-color:rgba(89,211,180,.44)!important;filter:saturate(.7)!important;opacity:.72!important;}',
    '#ovBody .is-luno-missions .ms-icon{display:flex!important;width:68px!important;height:68px!important;align-items:center!important;justify-content:center!important;border:0!important;border-radius:0!important;background:transparent!important;box-shadow:none!important;font-size:0!important;}#ovBody .is-luno-missions .luno-mission-task-art{display:block!important;width:68px!important;height:68px!important;object-fit:contain!important;filter:drop-shadow(0 3px 5px rgba(0,0,0,.38))!important;}',
    '#ovBody .is-luno-missions .ms-info{min-width:0!important;}#ovBody .is-luno-missions .ms-name{margin:0 0 2px!important;font-family:Cinzel,Georgia,serif!important;font-size:10.5px!important;line-height:14px!important;font-weight:900!important;letter-spacing:0!important;color:#fff1d3!important;text-shadow:0 1px 2px rgba(0,0,0,.58)!important;white-space:normal!important;overflow:visible!important;}#ovBody .is-luno-missions .ms-desc{font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:8.8px!important;line-height:12px!important;font-weight:600!important;color:#d7cddb!important;white-space:normal!important;}#ovBody .is-luno-missions .ms-bar-wrap{display:grid!important;grid-template-columns:minmax(0,1fr) auto!important;align-items:center!important;gap:5px!important;margin-top:6px!important;}#ovBody .is-luno-missions .ms-bar{height:7px!important;margin:0!important;border:1px solid rgba(255,255,255,.1)!important;border-radius:4px!important;background:#0c1727!important;}#ovBody .is-luno-missions .ms-bar-fill{border-radius:3px!important;background:linear-gradient(90deg,#37bfaf,#f2ca59)!important;}#ovBody .is-luno-missions .ms-cnt{font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:8px!important;line-height:10px!important;font-weight:800!important;color:#e9deed!important;}',
    '#ovBody .is-luno-missions .ms-btn{display:flex!important;width:68px!important;min-width:68px!important;height:41px!important;align-items:center!important;justify-content:center!important;gap:3px!important;padding:3px!important;border:1px solid rgba(255,255,255,.25)!important;border-radius:7px!important;font-family:Cinzel,Georgia,serif!important;font-size:8px!important;line-height:11px!important;font-weight:900!important;letter-spacing:0!important;white-space:nowrap!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.17),0 2px 5px rgba(0,0,0,.34)!important;}#ovBody .is-luno-missions .ms-btn-locked{background:linear-gradient(145deg,#302a4d,#1b3543)!important;color:#fff0d1!important;}#ovBody .is-luno-missions .ms-btn-claim{border-color:rgba(255,235,157,.7)!important;background:linear-gradient(180deg,#f5d66a,#b87922)!important;color:#271538!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.35),0 3px 7px rgba(0,0,0,.36),0 0 9px rgba(241,200,76,.28)!important;}#ovBody .is-luno-missions .ms-btn-claimed{border-color:rgba(94,216,184,.45)!important;background:linear-gradient(145deg,#205c56,#27354b)!important;color:#8ce4d0!important;}',
    '#ovBody .is-luno-missions .ms-bc-ic{display:flex!important;width:21px!important;height:21px!important;align-items:center!important;justify-content:center!important;font-size:0!important;}#ovBody .is-luno-missions .ms-rew-img,#ovBody .is-luno-missions .luno-mission-reward-art{display:block!important;width:21px!important;height:21px!important;object-fit:contain!important;}',
    '#ovBody .is-luno-missions .ms-empty{min-height:180px!important;padding:40px 18px!important;border:1px dashed rgba(102,208,198,.3)!important;border-radius:8px!important;font-family:Cinzel,Georgia,serif!important;font-size:11px!important;line-height:16px!important;color:#d7cce2!important;text-align:center!important;}',
    '@keyframes lunoMenuBubblePop{0%{transform:translateY(3px) scale(.97);opacity:.45}100%{transform:translateY(0) scale(1);opacity:1}}',
    '.luno-result-icon{display:block;width:86px;height:86px;object-fit:contain;margin:0 auto;}',
    'img[src*="piece-ottoman-"]{object-fit:contain!important;object-position:center bottom!important;}',
    '@media(max-width:360px){#menu .mn-profile-pill{max-width:31vw!important;flex-basis:112px!important}#menu .mn-club{display:none!important}#menu .mn-pname{max-width:58px!important;font-size:10.5px!important}#menu .mn-cur{padding:3px 4px!important;font-size:8px!important}#menu .cur-plus{display:none!important}#menu .mn-passrow{gap:3px!important;padding-left:5px!important;padding-right:5px!important}#menu .mn-quick{gap:3px!important}#menu .mn-luno-pass .luno-passimg,#menu .mn-quick .luno-qbimg{width:42px!important;height:42px!important}#menu .mn-luno-pass::after,#menu .mn-quick .mn-qbtn::after{font-size:6.5px!important}#menu .mn-bottomnav .nv-lbl{font-size:7.5px!important}#menu .mn-arena-pill.is-enhanced{grid-template-columns:61px minmax(0,1fr) 27px!important;gap:4px!important;padding-left:8px!important;padding-right:8px!important}#menu .mn-arena-pill.is-enhanced .ap-crown{width:38px!important;height:38px!important}#menu .mn-arena-pill.is-enhanced .luno-arena-icon{width:36px!important;height:36px!important}#menu .ap-main .ap-pts{min-width:40px!important;padding-left:2px!important;padding-right:2px!important}#ovBody .shx-wrap{padding-left:11px!important;padding-right:11px!important}#ovBody .shx-premium{grid-template-columns:72px minmax(0,1fr) 58px!important;gap:5px!important}#ovBody .shx-premium-art{width:70px!important;height:70px!important}#ovBody .shx-premium-title{font-size:11px!important}#ovBody .shx-premium-btn{width:56px!important;font-size:7px!important}#ovBody .shx-ocard-top{grid-template-columns:72px minmax(0,1fr)!important}#ovBody .shx-ocard-art{width:72px!important;height:72px!important}#ovBody .shx-chest-row{gap:4px!important}#ovBody .shx-chest-row .shx-art{width:66px!important;height:66px!important}#ovBody .shx-chest-row .shx-card{grid-template-rows:68px 30px 24px!important;padding:3px!important}#ovBody .shx-daily.is-shop-last{grid-template-columns:74px minmax(0,1fr) 72px!important;gap:6px!important}#ovBody .shx-daily-art{width:72px!important;height:72px!important}#ovBody .shx-btn{min-width:66px!important;padding:0 6px!important}}',
    '@media(prefers-reduced-motion:reduce){#menu .mn-luno-img,#menu .mn-luno-bubble{transition:none!important;animation:none!important}}'
  ].join('');
  document.head.appendChild(css);

  var settingsPassCss=document.createElement('style');
  settingsPassCss.id='luno-settings-pass-v8';
  settingsPassCss.textContent=[
    '#ovBody.is-luno-ranking .rk-podium-bg{background-size:calc(100% - 16px) 100%!important;background-position:center top!important;background-repeat:no-repeat!important;}#ovBody.is-luno-ranking .rk-podium{grid-template-columns:repeat(3,minmax(0,1fr))!important;gap:3px!important;}#ovBody.is-luno-ranking .rk-pod-base{width:108%!important;margin-left:-4%!important;margin-right:-4%!important;}',
    '#ovBody.is-luno-settings{padding:10px 14px 24px!important;background-image:linear-gradient(180deg,rgba(14,45,53,.16),rgba(50,28,70,.12) 45%,rgba(91,44,52,.09))!important;}#ovBody .is-luno-settings-wrap{display:flex!important;flex-direction:column!important;gap:5px!important;width:100%!important;padding:0 0 12px!important;}',
    '#ovBody .is-luno-settings-wrap .set-section-title{display:flex!important;align-items:center!important;gap:7px!important;min-height:28px!important;margin:7px 3px 2px!important;font-family:Cinzel,Georgia,serif!important;font-size:9.5px!important;line-height:13px!important;font-weight:900!important;letter-spacing:0!important;color:#f0d27a!important;text-shadow:0 1px 2px rgba(0,0,0,.65)!important;}#ovBody .luno-settings-section-art{display:block!important;width:27px!important;height:27px!important;object-fit:contain!important;filter:drop-shadow(0 2px 3px rgba(0,0,0,.32))!important;}',
    '#ovBody .is-luno-settings-wrap .set-list{display:flex!important;flex-direction:column!important;gap:5px!important;margin:0!important;padding:6px!important;border:1px solid rgba(107,205,194,.34)!important;border-radius:8px!important;background:linear-gradient(145deg,#123b47,#292044 74%)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.07),0 4px 10px rgba(0,0,0,.28)!important;}#ovBody .is-luno-settings-wrap .luno-settings-group-2{border-color:rgba(233,139,121,.34)!important;background:linear-gradient(145deg,#4b293e,#26334c 75%)!important;}#ovBody .is-luno-settings-wrap .luno-settings-group-3{border-color:rgba(112,191,206,.35)!important;background:linear-gradient(145deg,#183f4d,#322344 75%)!important;}#ovBody .is-luno-settings-wrap .luno-settings-group-4{border-color:rgba(241,194,86,.36)!important;background:linear-gradient(145deg,#4d3928,#283048 76%)!important;}#ovBody .is-luno-settings-wrap .luno-settings-group-5{border-color:rgba(104,206,193,.35)!important;background:linear-gradient(145deg,#16434a,#29213e 78%)!important;}',
    '#ovBody .luno-language-list{display:grid!important;grid-template-columns:repeat(2,minmax(0,1fr))!important;gap:7px!important;padding:6px!important;}#ovBody .luno-language-card{position:relative!important;display:grid!important;grid-template-columns:54px minmax(0,1fr) 17px!important;align-items:center!important;gap:3px!important;min-width:0!important;min-height:70px!important;padding:6px 7px!important;border:1px solid rgba(146,132,180,.5)!important;border-radius:7px!important;background:linear-gradient(145deg,#292341,#153947)!important;color:#d9cfdf!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.07)!important;overflow:hidden!important;}#ovBody .luno-language-card.is-active{border-color:rgba(248,210,92,.76)!important;background:linear-gradient(145deg,#5d4529,#28354b 68%,#174b52)!important;color:#ffe68d!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.12),0 0 10px rgba(239,198,76,.17)!important;}#ovBody .luno-language-art{display:block!important;width:54px!important;height:54px!important;object-fit:contain!important;}#ovBody .luno-language-copy{display:flex!important;min-width:0!important;flex-direction:column!important;gap:2px!important;font-family:Cinzel,Georgia,serif!important;letter-spacing:0!important;}#ovBody .luno-language-copy b{font-size:10px!important;line-height:13px!important;font-weight:900!important;white-space:nowrap!important;}#ovBody .luno-language-copy small{font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:7px!important;line-height:9px!important;font-weight:800!important;color:#8bd9cf!important;}#ovBody .luno-language-check{display:none!important;width:16px!important;height:16px!important;align-items:center!important;justify-content:center!important;border-radius:50%!important;background:#e7c654!important;color:#263142!important;font-family:Arial,sans-serif!important;font-size:10px!important;font-weight:900!important;}#ovBody .luno-language-card.is-active .luno-language-check{display:flex!important;}',
    '#ovBody .is-luno-settings-wrap .set-row{display:grid!important;grid-template-columns:52px minmax(0,1fr) auto!important;align-items:center!important;gap:8px!important;min-width:0!important;min-height:65px!important;padding:6px 9px 6px 5px!important;border:1px solid rgba(255,255,255,.06)!important;border-radius:7px!important;background:linear-gradient(145deg,rgba(27,54,68,.88),rgba(43,31,69,.92))!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.05),0 2px 5px rgba(0,0,0,.2)!important;transition:transform .14s ease,border-color .14s ease!important;}#ovBody .is-luno-settings-wrap .set-row:hover{border-color:rgba(239,205,104,.42)!important;background:linear-gradient(145deg,#214f59,#39294f)!important;}#ovBody .is-luno-settings-wrap .set-row:active{transform:scale(.985)!important;}#ovBody .is-luno-settings-wrap .set-row[data-luno-setting="9"]{border-color:rgba(233,105,117,.25)!important;background:linear-gradient(145deg,#522e3b,#2d2944)!important;}',
    '#ovBody .is-luno-settings-wrap .set-row-icon{display:flex!important;width:52px!important;height:52px!important;align-items:center!important;justify-content:center!important;filter:none!important;}#ovBody .luno-settings-row-art{display:block!important;width:52px!important;height:52px!important;object-fit:contain!important;filter:drop-shadow(0 2px 3px rgba(0,0,0,.35))!important;}#ovBody .is-luno-settings-wrap .set-row-info{min-width:0!important;}#ovBody .is-luno-settings-wrap .set-row-title{margin:0!important;font-family:Cinzel,Georgia,serif!important;font-size:10.5px!important;line-height:14px!important;font-weight:900!important;letter-spacing:0!important;color:#fff0d4!important;text-shadow:0 1px 2px rgba(0,0,0,.55)!important;white-space:normal!important;}#ovBody .is-luno-settings-wrap .set-row-sub{margin:2px 0 0!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:8.5px!important;line-height:11px!important;font-weight:600!important;letter-spacing:0!important;color:#cfc8d7!important;white-space:normal!important;}#ovBody .is-luno-settings-wrap .set-row[data-luno-setting="9"] .set-row-title{color:#ff9a9f!important;}',
    '#ovBody .is-luno-settings-wrap .set-row-arrow{display:flex!important;width:28px!important;height:28px!important;align-items:center!important;justify-content:center!important;border:1px solid rgba(255,255,255,.11)!important;border-radius:6px!important;background:#1b2639!important;font-family:Arial,sans-serif!important;font-size:21px!important;line-height:21px!important;font-weight:700!important;color:#e9d68f!important;}#ovBody .is-luno-settings-wrap .set-toggle{position:relative!important;width:46px!important;height:25px!important;border:1px solid rgba(139,191,194,.42)!important;border-radius:13px!important;background:#172b3a!important;box-shadow:inset 0 2px 4px rgba(0,0,0,.35)!important;}#ovBody .is-luno-settings-wrap .set-toggle-knob{position:absolute!important;top:2px!important;left:2px!important;width:19px!important;height:19px!important;border-radius:50%!important;background:linear-gradient(145deg,#d9d3ca,#8f9aa0)!important;box-shadow:0 2px 4px rgba(0,0,0,.38)!important;}#ovBody .is-luno-settings-wrap .set-toggle-on{border-color:rgba(252,217,102,.72)!important;background:linear-gradient(90deg,#2d8e81,#c5942a)!important;box-shadow:inset 0 1px 2px rgba(0,0,0,.24),0 0 8px rgba(74,202,182,.18)!important;}#ovBody .is-luno-settings-wrap .set-toggle-on .set-toggle-knob{left:23px!important;background:linear-gradient(145deg,#fff8d7,#f1c84f)!important;}',
    '#ovBody.is-luno-pass-missions{padding:10px 16px 24px!important;background-image:linear-gradient(180deg,rgba(18,62,66,.13),rgba(58,34,71,.12) 48%,rgba(87,50,34,.08))!important;}#ovBody .is-luno-pm-wrap{display:flex!important;flex-direction:column!important;gap:8px!important;width:100%!important;padding:0 0 14px!important;}#ovBody .is-luno-pm-wrap .pm-hero{display:grid!important;grid-template-columns:66px minmax(0,1fr) auto!important;align-items:center!important;gap:8px!important;min-height:88px!important;margin:0!important;padding:8px 10px 8px 6px!important;border:1px solid rgba(244,208,97,.62)!important;border-radius:8px!important;background:linear-gradient(145deg,#174b53,#3c2851 68%,#5a3c2d)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.11),0 5px 12px rgba(0,0,0,.32)!important;}#ovBody .is-luno-pm-wrap .pm-hero-ic{display:flex!important;width:66px!important;height:66px!important;align-items:center!important;justify-content:center!important;font-size:0!important;filter:none!important;}#ovBody .is-luno-pm-wrap .pm-hero-ic .luno-pm-task-art{width:66px!important;height:66px!important;}#ovBody .is-luno-pm-wrap .pm-hero-info{min-width:0!important;}#ovBody .is-luno-pm-wrap .pm-hero-title{font-family:Cinzel,Georgia,serif!important;font-size:11.5px!important;line-height:15px!important;font-weight:900!important;letter-spacing:0!important;color:#ffe28a!important;text-shadow:0 2px 3px rgba(0,0,0,.58)!important;}#ovBody .is-luno-pm-wrap .pm-hero-sub{margin-top:3px!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:8.7px!important;line-height:12px!important;font-weight:600!important;color:#eee1e6!important;}#ovBody .is-luno-pm-wrap .pm-hero-badge{display:flex!important;min-width:61px!important;height:26px!important;align-items:center!important;justify-content:center!important;padding:0 7px!important;border:1px solid rgba(255,255,255,.17)!important;border-radius:6px!important;font-family:Cinzel,Georgia,serif!important;font-size:7px!important;line-height:9px!important;font-weight:900!important;letter-spacing:0!important;}#ovBody .is-luno-pm-wrap .pm-free{background:#2b3950!important;color:#d8cfdf!important;}#ovBody .is-luno-pm-wrap .pm-prem{background:linear-gradient(145deg,#f0d060,#b78227)!important;color:#30223c!important;}',
    '#ovBody .is-luno-pm-wrap .pm-lockinfo{min-height:38px!important;margin:0!important;padding:9px 10px!important;border:1px dashed rgba(245,207,96,.48)!important;border-radius:7px!important;background:linear-gradient(145deg,rgba(83,61,38,.7),rgba(44,35,67,.8))!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:9.5px!important;line-height:13px!important;font-weight:700!important;color:#f2ddb0!important;text-align:center!important;}#ovBody .is-luno-pm-wrap .pm-sec{display:flex!important;flex-direction:column!important;gap:6px!important;margin:0!important;}#ovBody .is-luno-pm-wrap .pm-sec-head{display:flex!important;min-height:39px!important;align-items:center!important;gap:7px!important;margin:1px 3px 0!important;font-family:Cinzel,Georgia,serif!important;font-size:10px!important;line-height:13px!important;font-weight:900!important;letter-spacing:0!important;color:#eadced!important;text-shadow:0 1px 2px rgba(0,0,0,.55)!important;}#ovBody .luno-pm-section-art{display:block!important;width:38px!important;height:38px!important;object-fit:contain!important;filter:drop-shadow(0 2px 3px rgba(0,0,0,.32))!important;}',
    '#ovBody .is-luno-pm-wrap .pm-row{display:grid!important;grid-template-columns:56px 36px minmax(0,1fr) 46px!important;align-items:center!important;gap:6px!important;min-width:0!important;min-height:79px!important;margin:0!important;padding:7px 7px 7px 5px!important;border:1px solid rgba(103,204,194,.32)!important;border-radius:8px!important;background:linear-gradient(145deg,#173f4b,#2d2148 76%)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.07),0 3px 7px rgba(0,0,0,.25)!important;opacity:1!important;}#ovBody .is-luno-pm-wrap .pm-row.pm-diff-mid{border-color:rgba(235,197,86,.34)!important;background:linear-gradient(145deg,#4d3c29,#2e254a 77%)!important;}#ovBody .is-luno-pm-wrap .pm-row.pm-diff-hard{border-color:rgba(231,111,120,.36)!important;background:linear-gradient(145deg,#4b293b,#282846 78%)!important;}#ovBody .is-luno-pm-wrap .pm-row.pm-locked{filter:saturate(.68)!important;opacity:.72!important;}#ovBody .luno-pm-task-icon{display:flex!important;width:56px!important;height:56px!important;align-items:center!important;justify-content:center!important;}#ovBody .luno-pm-task-art{display:block!important;width:54px!important;height:54px!important;object-fit:contain!important;filter:drop-shadow(0 2px 3px rgba(0,0,0,.34))!important;}',
    '#ovBody .is-luno-pm-wrap .pm-diff{display:flex!important;width:36px!important;min-width:36px!important;height:22px!important;align-items:center!important;justify-content:center!important;padding:0!important;border:1px solid rgba(255,255,255,.16)!important;border-radius:5px!important;font-family:Cinzel,Georgia,serif!important;font-size:6.3px!important;line-height:8px!important;font-weight:900!important;letter-spacing:0!important;color:#17323a!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.22),0 2px 3px rgba(0,0,0,.22)!important;}#ovBody .pm-diff-easy .pm-diff{background:#6bd7bd!important;}#ovBody .pm-diff-mid .pm-diff{background:#f0ce62!important;color:#47341c!important;}#ovBody .pm-diff-hard .pm-diff{background:#e5757d!important;color:#451f29!important;}#ovBody .is-luno-pm-wrap .pm-row-main{min-width:0!important;}#ovBody .is-luno-pm-wrap .pm-row-text{margin:0 0 5px!important;font-family:Cinzel,Georgia,serif!important;font-size:9.5px!important;line-height:13px!important;font-weight:900!important;letter-spacing:0!important;color:#fff0d7!important;text-shadow:0 1px 2px rgba(0,0,0,.52)!important;white-space:normal!important;}#ovBody .is-luno-pm-wrap .pm-bar{height:7px!important;margin:0 0 5px!important;border:1px solid rgba(255,255,255,.08)!important;border-radius:4px!important;background:#10192b!important;}#ovBody .is-luno-pm-wrap .pm-bar-fill{height:100%!important;border-radius:3px!important;}',
    '#ovBody .is-luno-pm-wrap .pm-row-meta{display:flex!important;align-items:center!important;justify-content:space-between!important;gap:5px!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:7.8px!important;line-height:10px!important;font-weight:700!important;color:#cfc7d6!important;}#ovBody .luno-pm-points,#ovBody .luno-pm-gems{display:inline-flex!important;align-items:center!important;gap:2px!important;color:#ffe085!important;font-weight:900!important;white-space:nowrap!important;}#ovBody .luno-pm-points .luno-pm-task-art{width:18px!important;height:18px!important;filter:none!important;}#ovBody .luno-pm-gems img{display:block!important;width:18px!important;height:18px!important;object-fit:contain!important;}#ovBody .luno-pm-single{color:#b9b2c8!important;}#ovBody .is-luno-pm-wrap .pm-claim{display:flex!important;width:46px!important;min-width:46px!important;height:38px!important;align-items:center!important;justify-content:center!important;padding:0!important;border:1px solid rgba(255,255,255,.16)!important;border-radius:7px!important;font-family:Cinzel,Georgia,serif!important;font-size:8px!important;line-height:11px!important;font-weight:900!important;letter-spacing:0!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.12),0 2px 5px rgba(0,0,0,.28)!important;}#ovBody .is-luno-pm-wrap .pm-claim-on{border-color:rgba(255,232,143,.7)!important;background:linear-gradient(180deg,#f2d35d,#b47b23)!important;color:#2c2036!important;}#ovBody .is-luno-pm-wrap .pm-claim-off{background:#282844!important;color:#b9b0c7!important;}#ovBody .is-luno-pm-wrap .pm-claimed{background:#1d5c52!important;color:#79e0c4!important;}#ovBody .is-luno-pm-wrap .pm-claim-lock{background:#22283f!important;color:#d7c589!important;}#ovBody .luno-pm-lock{position:relative!important;display:block!important;width:18px!important;height:15px!important;border:2px solid #d8bd70!important;border-radius:4px!important;background:#564432!important;}#ovBody .luno-pm-lock i{position:absolute!important;left:3px!important;top:-10px!important;width:8px!important;height:9px!important;border:2px solid #d8bd70!important;border-bottom:0!important;border-radius:7px 7px 0 0!important;}#ovBody .luno-pm-lock:after{content:""!important;position:absolute!important;left:6px!important;top:4px!important;width:3px!important;height:5px!important;border-radius:2px!important;background:#f7df91!important;}',
    '#ovBody .is-luno-pm-wrap .is-luno-pm-special{grid-template-columns:56px minmax(0,1fr) 46px!important;border-color:rgba(239,196,84,.38)!important;background:linear-gradient(145deg,#4c3b29,#243d48 54%,#35254b)!important;}#ovBody .is-luno-pm-wrap .pm-claim-sp{border-color:rgba(93,226,185,.62)!important;background:linear-gradient(180deg,#55d6ad,#23866f)!important;color:#102a2d!important;}@media(max-width:360px){#ovBody.is-luno-settings{padding-left:12px!important;padding-right:12px!important}#ovBody .luno-language-card{grid-template-columns:50px minmax(0,1fr) 15px!important;padding-left:4px!important;padding-right:5px!important}#ovBody .luno-language-art{width:50px!important;height:50px!important}#ovBody.is-luno-pass-missions{padding-left:12px!important;padding-right:12px!important}#ovBody .is-luno-pm-wrap .pm-row{grid-template-columns:50px 34px minmax(0,1fr) 43px!important;gap:5px!important;padding-left:4px!important;padding-right:5px!important}#ovBody .luno-pm-task-icon{width:50px!important;height:50px!important}#ovBody .luno-pm-task-art{width:49px!important;height:49px!important}#ovBody .is-luno-pm-wrap .pm-diff{width:34px!important;min-width:34px!important;font-size:5.8px!important}#ovBody .is-luno-pm-wrap .pm-claim{width:43px!important;min-width:43px!important}#ovBody .is-luno-pm-wrap .is-luno-pm-special{grid-template-columns:50px minmax(0,1fr) 43px!important}}'
  ].join('');
  document.head.appendChild(settingsPassCss);

  var v9Css=document.createElement('style');
  v9Css.id='luno-avatar-level-ranking-v9';
  v9Css.textContent=[
    '#menu .mn-arena-pill.is-enhanced{box-sizing:border-box!important;display:grid!important;grid-template-columns:58px minmax(0,1fr) 31px!important;align-items:center!important;gap:7px!important;width:auto!important;min-height:72px!important;margin:-10px 10px 8px!important;padding:6px 8px 6px 5px!important;border:1px solid rgba(244,205,91,.62)!important;border-radius:8px!important;background:linear-gradient(145deg,#154653 0%,#30234d 56%,#5d3545 100%)!important;background-image:none!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.13),0 5px 12px rgba(0,0,0,.38),0 0 10px rgba(74,205,192,.12)!important;overflow:hidden!important;}',
    '#menu .mn-arena-pill.is-enhanced .ap-crown{display:flex!important;visibility:visible!important;width:58px!important;height:58px!important;align-items:center!important;justify-content:center!important;margin:0!important;font-size:0!important;opacity:1!important;}',
    '#menu .mn-arena-pill.is-enhanced .luno-arena-crest{display:block!important;width:58px!important;height:58px!important;object-fit:contain!important;filter:drop-shadow(0 3px 4px rgba(0,0,0,.4))!important;}',
    '#menu .mn-arena-pill.is-enhanced .ap-main{display:grid!important;grid-template-rows:11px 18px 21px!important;align-content:center!important;gap:2px!important;min-width:0!important;height:58px!important;padding:0!important;}',
    '#menu .mn-arena-pill.is-enhanced .ap-kicker{min-width:0!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:7.5px!important;line-height:10px!important;font-weight:800!important;letter-spacing:0!important;color:#72d9cf!important;text-transform:uppercase!important;white-space:nowrap!important;overflow:hidden!important;text-overflow:ellipsis!important;}',
    '#menu .mn-arena-pill.is-enhanced .ap-title{min-width:0!important;margin:0!important;font-family:Cinzel,Georgia,serif!important;font-size:11px!important;line-height:16px!important;font-weight:900!important;letter-spacing:0!important;color:#fff0c7!important;text-shadow:0 2px 3px rgba(0,0,0,.62)!important;white-space:nowrap!important;overflow:hidden!important;text-overflow:ellipsis!important;}',
    '#menu .mn-arena-pill.is-enhanced.has-long-arena .ap-title{font-size:9.5px!important;}',
    '#menu .mn-arena-pill.is-enhanced .ap-progress{display:grid!important;grid-template-columns:minmax(44px,1fr) auto!important;align-items:center!important;gap:6px!important;min-width:0!important;width:100%!important;height:21px!important;min-height:21px!important;margin:0!important;overflow:visible!important;}',
    '#menu .mn-arena-pill.is-enhanced .ap-bar{box-sizing:border-box!important;width:100%!important;min-width:0!important;height:9px!important;border:1px solid rgba(235,219,255,.24)!important;border-radius:5px!important;background:#100f28!important;box-shadow:inset 0 2px 3px rgba(0,0,0,.55)!important;overflow:hidden!important;}',
    '#menu .mn-arena-pill.is-enhanced .ap-fill{height:100%!important;border-radius:4px!important;background:linear-gradient(90deg,#4bd6c5,#8fd9bf 52%,#f2d46b)!important;box-shadow:0 0 7px rgba(85,220,202,.42)!important;}',
    '#menu .mn-arena-pill.is-enhanced .ap-pts{box-sizing:border-box!important;display:flex!important;min-width:67px!important;height:17px!important;align-items:center!important;justify-content:center!important;padding:1px 5px!important;border:1px solid rgba(245,207,91,.37)!important;border-radius:5px!important;background:#211a39!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:8.8px!important;line-height:12px!important;font-weight:900!important;letter-spacing:0!important;color:#ffe28a!important;text-shadow:0 1px 2px rgba(0,0,0,.7)!important;white-space:nowrap!important;overflow:hidden!important;}',
    '#menu .mn-arena-pill.is-enhanced.has-long-points .ap-pts{min-width:76px!important;padding-left:3px!important;padding-right:3px!important;font-size:7.7px!important;}',
    '#menu .mn-arena-pill.is-enhanced .ap-arrow{display:flex!important;visibility:visible!important;width:31px!important;height:36px!important;align-items:center!important;justify-content:center!important;padding:0!important;border:1px solid rgba(255,239,170,.55)!important;border-radius:7px!important;background:linear-gradient(180deg,#e1bd55,#95611d)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.35),0 3px 6px rgba(0,0,0,.38)!important;font-family:Arial,sans-serif!important;font-size:20px!important;line-height:20px!important;font-weight:800!important;color:#2a1734!important;opacity:1!important;}',
    '@media(max-width:360px){#menu .mn-arena-pill.is-enhanced{grid-template-columns:54px minmax(0,1fr) 29px!important;gap:5px!important;margin-left:8px!important;margin-right:8px!important;padding-left:4px!important;padding-right:6px!important}#menu .mn-arena-pill.is-enhanced .ap-crown,#menu .mn-arena-pill.is-enhanced .luno-arena-crest{width:54px!important;height:54px!important}#menu .mn-arena-pill.is-enhanced .ap-pts{min-width:62px!important;font-size:8px!important}#menu .mn-arena-pill.is-enhanced.has-long-points .ap-pts{min-width:70px!important;font-size:7.2px!important}}',

    '#ovBody.is-luno-ranking .rk-podium-bg{min-height:284px!important;padding:8px 7px 0!important;background-image:linear-gradient(180deg,rgba(9,12,27,.08),rgba(7,10,23,.16)),var(--luno-rank-backdrop)!important;background-size:100% 100%!important;background-position:center top!important;background-repeat:no-repeat!important;}',
    '#ovBody.is-luno-ranking .rk-podium-title{min-height:31px!important;margin:0 0 4px!important;background:rgba(20,20,39,.78)!important;}',
    '#ovBody.is-luno-ranking .rk-podium{grid-template-columns:repeat(3,minmax(0,1fr))!important;gap:5px!important;min-height:241px!important;padding:0 2px!important;}',
    '#ovBody.is-luno-ranking .rk-pod-col{box-sizing:border-box!important;min-width:0!important;overflow:visible!important;}',
    '#ovBody.is-luno-ranking .rk-pod-name{box-sizing:border-box!important;display:block!important;width:calc(100% - 8px)!important;max-width:calc(100% - 8px)!important;height:18px!important;margin:0 4px 3px!important;padding:2px 4px!important;border:1px solid rgba(255,255,255,.12)!important;border-radius:5px!important;background:rgba(18,21,38,.84)!important;font-size:9.5px!important;line-height:12px!important;text-align:center!important;white-space:nowrap!important;overflow:hidden!important;text-overflow:ellipsis!important;}',
    '#ovBody.is-luno-ranking .rk-name-1{font-size:10px!important;color:#ffe181!important;}',
    '#ovBody.is-luno-ranking .rk-pod-trophies{box-sizing:border-box!important;width:auto!important;min-width:58px!important;height:21px!important;margin:0 0 3px!important;padding:1px 5px!important;border:1px solid rgba(239,204,102,.24)!important;border-radius:5px!important;background:rgba(13,18,31,.88)!important;font-size:8.5px!important;line-height:12px!important;}',
    '#ovBody.is-luno-ranking .luno-rank-metric-art{width:16px!important;height:16px!important;flex-basis:16px!important;}',
    '#ovBody.is-luno-ranking[data-luno-rank-mode="collection"] .luno-rank-metric-art{width:18px!important;height:18px!important;flex-basis:18px!important;}',
    '#ovBody.is-luno-ranking .rk-pod-base{box-sizing:border-box!important;width:100%!important;margin-left:0!important;margin-right:0!important;}',
    '#ovBody.is-luno-ranking .rk-row-trophies{min-width:64px!important;justify-content:flex-end!important;}',
    '@media(max-width:360px){#ovBody.is-luno-ranking .rk-podium-bg{min-height:282px!important}#ovBody.is-luno-ranking .rk-podium{gap:3px!important;padding-left:1px!important;padding-right:1px!important}#ovBody.is-luno-ranking .rk-pod-name{width:calc(100% - 4px)!important;max-width:calc(100% - 4px)!important;margin-left:2px!important;margin-right:2px!important;padding-left:2px!important;padding-right:2px!important;font-size:8.5px!important}#ovBody.is-luno-ranking .rk-pod-trophies{min-width:54px!important;padding-left:3px!important;padding-right:3px!important;font-size:7.8px!important}}',

    '#ovBody.is-luno-profile-edit .pe-avatar-grid{display:grid!important;grid-template-columns:repeat(4,minmax(0,1fr))!important;gap:7px!important;width:100%!important;}',
    '#ovBody.is-luno-profile-edit .pe-avatar-opt{box-sizing:border-box!important;display:grid!important;grid-template-rows:56px 14px!important;align-items:center!important;justify-items:center!important;gap:2px!important;min-width:0!important;min-height:82px!important;padding:5px 3px!important;border:1px solid rgba(91,204,194,.32)!important;border-radius:8px!important;background:linear-gradient(145deg,#193e4a,#2a2148 76%)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.08),0 3px 7px rgba(0,0,0,.25)!important;font-size:0!important;overflow:hidden!important;}',
    '#ovBody.is-luno-profile-edit .pe-avatar-opt.pe-a-sel{border-color:#f0cd62!important;background:linear-gradient(145deg,#5d4326,#3a2856 64%,#17515a)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.14),0 0 10px rgba(239,202,90,.28)!important;}',
    '#ovBody.is-luno-profile-edit .pe-avatar-opt .luno-avimg{display:block!important;width:56px!important;height:56px!important;object-fit:contain!important;filter:drop-shadow(0 3px 4px rgba(0,0,0,.38))!important;}',
    '#ovBody.is-luno-profile-edit .luno-avatar-option-name{display:block!important;width:100%!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:8px!important;line-height:11px!important;font-weight:800!important;letter-spacing:0!important;color:#e9dfea!important;text-align:center!important;white-space:nowrap!important;overflow:hidden!important;text-overflow:ellipsis!important;}',
    '#ovBody.is-luno-profile-edit .pe-a-sel .luno-avatar-option-name{color:#ffe283!important;}',
    '#ovBody.is-luno-profile-edit .pe-prev-avatar .luno-avimg{width:66px!important;height:66px!important;object-fit:contain!important;}',
    '.pf2-avatar .luno-avimg{width:76px!important;height:76px!important;object-fit:contain!important;}.rk-pod-avatar .luno-avimg{width:48px!important;height:48px!important;object-fit:contain!important;}.rk-avatar-1 .luno-avimg{width:57px!important;height:57px!important;object-fit:contain!important;}.rk-row-avatar .luno-avimg,.fh-av .luno-avimg{width:34px!important;height:34px!important;object-fit:contain!important;}',

    '#ovBody .is-luno-profile .pf2-levelrow{grid-template-columns:74px minmax(0,1fr)!important;gap:10px!important;}#ovBody .is-luno-profile .pf2-lvlbadge{position:relative!important;flex:0 0 74px!important;width:74px!important;height:74px!important;overflow:visible!important;}#ovBody .is-luno-profile .pf2-lvlbadge .pf2-lvlimg{display:block!important;width:74px!important;height:74px!important;object-fit:contain!important;filter:drop-shadow(0 3px 5px rgba(0,0,0,.42))!important;}.luno-profile-level-number{position:absolute!important;left:50%!important;bottom:2px!important;display:flex!important;min-width:30px!important;height:20px!important;align-items:center!important;justify-content:center!important;transform:translateX(-50%)!important;padding:0 6px!important;border:1px solid rgba(255,239,171,.7)!important;border-radius:6px!important;background:#251a3d!important;font-family:Cinzel,Georgia,serif!important;font-size:11px!important;line-height:14px!important;font-weight:900!important;letter-spacing:0!important;color:#ffe384!important;box-shadow:0 2px 5px rgba(0,0,0,.45)!important;}',
    '.luno-level-overlay{position:fixed;inset:0;z-index:99600;display:flex;align-items:center;justify-content:center;padding:22px;background:rgba(8,7,20,.88);opacity:0;transition:opacity .25s ease;}.luno-level-overlay.show{opacity:1;}.luno-level-card{box-sizing:border-box;position:relative;width:100%;max-width:330px;padding:18px 18px 17px;border:1px solid rgba(245,208,95,.66);border-radius:12px;background:linear-gradient(155deg,#174653 0%,#33234f 58%,#5a3544 100%);box-shadow:inset 0 1px 0 rgba(255,255,255,.14),0 16px 38px rgba(0,0,0,.58);text-align:center;overflow:hidden;transform:translateY(9px) scale(.98);transition:transform .25s ease;}.luno-level-overlay.show .luno-level-card{transform:translateY(0) scale(1);}',
    '.luno-level-badge{position:relative;width:132px;height:132px;margin:0 auto 5px;}.luno-level-badge img{display:block;width:132px;height:132px;object-fit:contain;filter:drop-shadow(0 5px 8px rgba(0,0,0,.44));}.luno-level-badge>span{position:absolute;left:50%;bottom:5px;display:flex;min-width:39px;height:25px;align-items:center;justify-content:center;transform:translateX(-50%);padding:0 7px;border:1px solid rgba(255,239,170,.75);border-radius:7px;background:#24183a;font-family:Cinzel,Georgia,serif;font-size:14px;line-height:18px;font-weight:900;letter-spacing:0;color:#ffe383;box-shadow:0 3px 7px rgba(0,0,0,.48);}',
    '.luno-level-kicker{margin:1px 0 2px;font-family:"Trebuchet MS",system-ui,sans-serif;font-size:8px;line-height:11px;font-weight:900;letter-spacing:0;color:#6fe0d1;}.luno-level-title{font-family:Cinzel,Georgia,serif;font-size:19px;line-height:24px;font-weight:900;letter-spacing:0;color:#fff0bd;text-shadow:0 2px 3px rgba(0,0,0,.62);}.luno-level-subtitle{max-width:250px;margin:3px auto 11px;font-family:"Trebuchet MS",system-ui,sans-serif;font-size:11px;line-height:15px;font-weight:700;letter-spacing:0;color:#dcd3e3;}',
    '.luno-level-reward{box-sizing:border-box;display:grid;grid-template-columns:48px minmax(0,1fr);align-items:center;gap:9px;min-height:62px;margin:0 0 10px;padding:7px 11px;border:1px solid rgba(97,214,202,.38);border-radius:8px;background:rgba(16,31,45,.66);text-align:left;}.luno-level-reward img{display:block;width:46px;height:46px;object-fit:contain;}.luno-level-reward div{display:flex;flex-direction:column;min-width:0;}.luno-level-reward strong{font-family:Cinzel,Georgia,serif;font-size:17px;line-height:21px;font-weight:900;letter-spacing:0;color:#ffe17f;}.luno-level-reward span{font-family:"Trebuchet MS",system-ui,sans-serif;font-size:9.5px;line-height:13px;font-weight:700;letter-spacing:0;color:#d7ccdc;}.luno-level-note{margin:-1px 3px 11px;font-family:"Trebuchet MS",system-ui,sans-serif;font-size:9.5px;line-height:14px;font-weight:600;letter-spacing:0;color:#cfc4d8;}.luno-level-note b{color:#ffe183;}',
    '.luno-level-confirm{box-sizing:border-box;width:100%;min-height:48px;padding:8px 14px;border:1px solid rgba(255,244,183,.74);border-radius:8px;background:linear-gradient(180deg,#f2d568,#b77922);box-shadow:inset 0 1px 0 rgba(255,255,255,.37),0 4px 8px rgba(0,0,0,.36);font-family:Cinzel,Georgia,serif;font-size:13px;line-height:17px;font-weight:900;letter-spacing:0;color:#261632;cursor:pointer;}.luno-level-confirm:active{transform:scale(.98);}.luno-level-sparkles{position:absolute;inset:0;pointer-events:none;}.luno-level-sparkles i{position:absolute;width:4px;height:4px;border-radius:50%;background:#ffe277;box-shadow:0 0 7px rgba(255,218,100,.65);}.luno-level-sparkles i:nth-child(1){left:13%;top:18%}.luno-level-sparkles i:nth-child(2){right:14%;top:23%}.luno-level-sparkles i:nth-child(3){left:20%;top:46%}.luno-level-sparkles i:nth-child(4){right:19%;top:45%}',

    '#ovBody .shx-card-price.shx-gold,#ovBody .shx-card-price.shx-gem{display:flex!important;min-height:34px!important;align-items:center!important;justify-content:center!important;gap:5px!important;padding:4px 5px!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:11px!important;line-height:14px!important;font-weight:900!important;letter-spacing:0!important;white-space:nowrap!important;}#ovBody .luno-shop-price-art{display:block!important;width:22px!important;height:22px!important;object-fit:contain!important;flex:0 0 22px!important;}',
    '#ovBody .shx-cur-amt{display:flex!important;min-height:26px!important;align-items:center!important;justify-content:center!important;gap:5px!important;font-family:Cinzel,Georgia,serif!important;font-size:14px!important;line-height:18px!important;font-weight:900!important;letter-spacing:0!important;color:#fff0d4!important;}#ovBody .luno-shop-pack-currency-art{display:block!important;width:25px!important;height:25px!important;object-fit:contain!important;flex:0 0 25px!important;}#ovBody .shx-cur-fiat{margin-top:2px!important;font-size:9.5px!important;line-height:13px!important;}',
    '#ovBody .shx-curcol-h{display:flex!important;align-items:center!important;gap:6px!important;font-family:Cinzel,Georgia,serif!important;font-size:10px!important;line-height:14px!important;font-weight:900!important;letter-spacing:0!important;}#ovBody .luno-shop-heading-currency-art{display:block!important;width:22px!important;height:22px!important;object-fit:contain!important;flex:0 0 22px!important;}#ovBody .shx-daily-sub{display:flex!important;align-items:center!important;gap:5px!important;}#ovBody .luno-shop-daily-currency-art{display:block!important;width:20px!important;height:20px!important;object-fit:contain!important;flex:0 0 20px!important;}',
    '@media(prefers-reduced-motion:reduce){.luno-level-overlay,.luno-level-card{transition:none!important}}'
  ].join('');
  document.head.appendChild(v9Css);

  var collectionV10Css=document.createElement('style');
  collectionV10Css.id='luno-collection-cards-v10';
  collectionV10Css.textContent=[
    '#menu .mn-luno-live.is-luno-v10{bottom:9.2%!important;isolation:isolate!important;filter:none!important;}',
    '#menu .mn-luno-live.is-luno-v10::after{content:""!important;position:absolute!important;left:50%!important;bottom:-1px!important;z-index:-1!important;width:104px!important;height:17px!important;transform:translateX(-50%)!important;border-radius:50%!important;background:radial-gradient(ellipse at center,rgba(78,214,199,.25) 0%,rgba(237,194,79,.13) 42%,transparent 72%)!important;filter:blur(2px)!important;pointer-events:none!important;}',
    '#menu .mn-luno-live.is-luno-v10 .mn-luno-img{display:block!important;width:154px!important;height:154px!important;max-width:42vw!important;object-fit:contain!important;object-position:center bottom!important;filter:drop-shadow(0 9px 11px rgba(7,5,20,.5))!important;will-change:transform!important;animation:lunoMenuBreathV10 3.2s ease-in-out infinite!important;transition:opacity .14s ease,filter .2s ease!important;}',
    '#menu .mn-luno-live.is-luno-v10.is-waving .mn-luno-img{animation:lunoMenuWaveV10 .52s ease-in-out 2!important;}',
    '#menu .mn-luno-live.is-luno-v10.is-talking .mn-luno-img{animation:lunoMenuTalkV10 .42s ease-in-out 2!important;}',
    '#menu .mn-luno-live.is-luno-v10.is-pointing .mn-luno-img{animation:lunoMenuPointV10 .7s ease-out 1!important;}',
    '#menu .mn-luno-live.is-luno-v10 .mn-luno-bubble{box-sizing:border-box!important;position:relative!important;width:228px!important;max-width:62vw!important;min-height:38px!important;margin:0 auto 4px!important;padding:12px 14px 8px!important;border:1px solid rgba(244,207,104,.82)!important;border-radius:8px!important;background:linear-gradient(145deg,rgba(44,28,68,.98),rgba(18,38,49,.98) 70%)!important;color:#fff3d2!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:10.5px!important;line-height:14px!important;font-weight:750!important;letter-spacing:0!important;text-align:center!important;text-wrap:balance!important;text-shadow:0 1px 2px rgba(0,0,0,.72)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.14),0 5px 13px rgba(0,0,0,.44),0 0 0 2px rgba(83,209,196,.07)!important;}',
    '#menu .mn-luno-live.is-luno-v10 .mn-luno-bubble::before{content:attr(data-speaker)!important;position:absolute!important;left:12px!important;top:-8px!important;display:flex!important;height:15px!important;align-items:center!important;padding:0 7px!important;border:1px solid rgba(255,239,174,.72)!important;border-radius:5px!important;background:linear-gradient(180deg,#e7c65c,#9d6820)!important;color:#21162f!important;font-family:Cinzel,Georgia,serif!important;font-size:7px!important;line-height:10px!important;font-weight:900!important;letter-spacing:0!important;text-shadow:none!important;box-shadow:0 2px 5px rgba(0,0,0,.34)!important;}',
    '#menu .mn-luno-live.is-luno-v10 .mn-luno-bubble::after{content:""!important;position:absolute!important;left:50%!important;bottom:-6px!important;width:10px!important;height:10px!important;transform:translateX(-50%) rotate(45deg)!important;border-right:1px solid rgba(244,207,104,.82)!important;border-bottom:1px solid rgba(244,207,104,.82)!important;background:#1b2938!important;}',
    '#menu .mn-luno-live.is-luno-v10.is-waving .mn-luno-bubble{border-color:rgba(91,219,205,.88)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.15),0 5px 13px rgba(0,0,0,.44),0 0 11px rgba(72,203,191,.16)!important;}',
    '@keyframes lunoMenuBreathV10{0%,100%{transform:translateY(0) scale(1)}50%{transform:translateY(-3px) scale(1.01)}}',
    '@keyframes lunoMenuWaveV10{0%,100%{transform:translateY(0) rotate(0)}35%{transform:translateY(-3px) rotate(-2deg)}70%{transform:translateY(-1px) rotate(1.5deg)}}',
    '@keyframes lunoMenuTalkV10{0%,100%{transform:translateY(0) scale(1)}50%{transform:translateY(-2px) scale(1.025,.985)}}',
    '@keyframes lunoMenuPointV10{0%{transform:translateX(-3px) scale(.99)}55%{transform:translateX(2px) scale(1.02)}100%{transform:translateX(0) scale(1)}}',

    '#ovBody.is-luno-collection-hub{padding:10px 12px 24px!important;background:linear-gradient(180deg,#111d2e 0%,#231a3b 50%,#161b2b 100%)!important;}',
    '#ovBody.is-luno-collection-hub .ch-wrap{display:grid!important;grid-template-columns:1fr!important;gap:9px!important;padding:2px 0 16px!important;}',
    '#ovBody.is-luno-collection-hub .ch-card{box-sizing:border-box!important;display:grid!important;grid-template-columns:78px minmax(0,1fr) 22px!important;align-items:center!important;gap:9px!important;min-height:96px!important;margin:0!important;padding:7px 9px 7px 5px!important;border:1px solid rgba(238,205,111,.38)!important;border-radius:8px!important;background:linear-gradient(145deg,#183e48,#302348 66%,#4d3040)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.11),0 4px 10px rgba(0,0,0,.3)!important;overflow:hidden!important;}',
    '#ovBody.is-luno-collection-hub .ch-card[data-collection-kind="cards"]{background:linear-gradient(145deg,#2d254b,#173f47 68%,#58402e)!important;}',
    '#ovBody.is-luno-collection-hub .ch-card[data-collection-kind="costumes"]{background:linear-gradient(145deg,#49313e,#243a4b 68%,#254c49)!important;}',
    '#ovBody.is-luno-collection-hub .ch-card[data-collection-kind="emojis"]{background:linear-gradient(145deg,#1d4050,#39284c 68%,#533348)!important;}',
    '#ovBody.is-luno-collection-hub .ch-card:active{transform:scale(.985)!important;}',
    '#ovBody.is-luno-collection-hub .ch-ic{width:78px!important;height:78px!important;}',
    '#ovBody.is-luno-collection-hub .ch-icimg{display:block!important;width:76px!important;height:76px!important;object-fit:contain!important;filter:drop-shadow(0 4px 5px rgba(0,0,0,.4))!important;}',
    '#ovBody.is-luno-collection-hub .ch-info{min-width:0!important;}',
    '#ovBody.is-luno-collection-hub .ch-name{font-family:Cinzel,Georgia,serif!important;font-size:14px!important;line-height:18px!important;font-weight:900!important;letter-spacing:0!important;color:#fff0c2!important;text-shadow:0 2px 3px rgba(0,0,0,.56)!important;white-space:normal!important;}',
    '#ovBody.is-luno-collection-hub .ch-sub{margin-top:3px!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:10.5px!important;line-height:14px!important;font-weight:700!important;letter-spacing:0!important;color:#d9d0df!important;white-space:normal!important;}',
    '#ovBody.is-luno-collection-hub .ch-arrow{font-family:Arial,sans-serif!important;font-size:23px!important;line-height:23px!important;font-weight:700!important;color:#f0cf70!important;text-shadow:0 1px 3px rgba(0,0,0,.5)!important;}',

    '#ovBody.is-luno-deck-editor,#ovBody.is-luno-card-collection{box-sizing:border-box!important;padding:10px 12px 30px!important;background:linear-gradient(180deg,#101d2b 0%,#211936 46%,#151a29 100%)!important;}',
    '#ovBody.is-luno-deck-editor .deck-arena-badge{box-sizing:border-box!important;display:grid!important;grid-template-columns:52px minmax(0,1fr) auto!important;align-items:center!important;gap:8px!important;min-height:66px!important;margin:0 0 8px!important;padding:5px 8px 5px 4px!important;border:1px solid rgba(237,203,105,.5)!important;border-radius:8px!important;background:linear-gradient(145deg,#16434a,#302249 64%,#51343f)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.12),0 4px 10px rgba(0,0,0,.34)!important;}',
    '#ovBody.is-luno-deck-editor .luno-deck-badge-art{display:block!important;width:52px!important;height:52px!important;object-fit:contain!important;}',
    '#ovBody.is-luno-deck-editor .luno-deck-badge-copy{display:flex!important;min-width:0!important;flex-direction:column!important;gap:1px!important;}',
    '#ovBody.is-luno-deck-editor .luno-deck-badge-copy span{font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:7px!important;line-height:10px!important;font-weight:900!important;color:#64d7cb!important;}',
    '#ovBody.is-luno-deck-editor .luno-deck-badge-copy b{font-family:Cinzel,Georgia,serif!important;font-size:11px!important;line-height:15px!important;font-weight:900!important;letter-spacing:0!important;color:#fff0c3!important;white-space:nowrap!important;overflow:hidden!important;text-overflow:ellipsis!important;}',
    '#ovBody.is-luno-deck-editor .dab-trophy{display:flex!important;min-width:55px!important;height:29px!important;align-items:center!important;justify-content:center!important;gap:3px!important;padding:1px 5px!important;border:1px solid rgba(240,207,107,.36)!important;border-radius:7px!important;background:#201b35!important;color:#ffe28b!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:10px!important;line-height:13px!important;font-weight:900!important;}',
    '#ovBody.is-luno-deck-editor .dab-trophy img{display:block!important;width:20px!important;height:20px!important;object-fit:contain!important;}',
    '#ovBody.is-luno-deck-editor .deck-hint{box-sizing:border-box!important;display:flex!important;min-height:42px!important;align-items:center!important;justify-content:center!important;gap:7px!important;margin:0 0 9px!important;padding:5px 9px!important;border:1px solid rgba(77,207,194,.28)!important;border-radius:8px!important;background:rgba(13,35,44,.72)!important;}',
    '#ovBody.is-luno-deck-editor .deck-hint>img{display:block!important;width:29px!important;height:29px!important;object-fit:contain!important;}',
    '#ovBody.is-luno-deck-editor .deck-hint>span{display:flex!important;min-width:0!important;flex-direction:column!important;gap:1px!important;}',
    '#ovBody.is-luno-deck-editor .deck-hint b{font-family:Cinzel,Georgia,serif!important;font-size:9px!important;line-height:12px!important;font-weight:900!important;color:#f4e8cf!important;letter-spacing:0!important;}',
    '#ovBody.is-luno-deck-editor .deck-hint small{font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:8px!important;line-height:11px!important;font-weight:800!important;color:#6cd7ce!important;}',
    '#ovBody.is-luno-deck-editor .deck-slots{display:grid!important;grid-template-columns:repeat(3,minmax(0,1fr))!important;gap:9px!important;margin:0 0 13px!important;}',
    '#ovBody.is-luno-deck-editor .deck-pool-title{box-sizing:border-box!important;display:flex!important;height:39px!important;align-items:center!important;gap:7px!important;margin:1px 0 3px!important;padding:3px 6px!important;border-bottom:1px solid rgba(237,203,105,.3)!important;font-family:Cinzel,Georgia,serif!important;font-size:11px!important;line-height:14px!important;font-weight:900!important;letter-spacing:0!important;color:#fff0c2!important;}',
    '#ovBody.is-luno-deck-editor .deck-pool-title img{display:block!important;width:34px!important;height:34px!important;object-fit:contain!important;}',
    '#ovBody.is-luno-deck-editor .pool-group{display:grid!important;grid-template-columns:repeat(3,minmax(0,1fr))!important;gap:9px!important;margin-bottom:5px!important;}',
    '#ovBody.is-luno-deck-editor .pool-group-head{box-sizing:border-box!important;display:flex!important;min-height:38px!important;align-items:center!important;gap:7px!important;margin:10px 0 5px!important;padding:3px 4px!important;border-top:1px solid rgba(91,211,199,.22)!important;color:#e9ddf0!important;font-family:Cinzel,Georgia,serif!important;font-size:10px!important;line-height:13px!important;font-weight:900!important;letter-spacing:0!important;}',
    '#ovBody .luno-card-family-art{display:block!important;width:32px!important;height:32px!important;object-fit:contain!important;flex:0 0 32px!important;filter:drop-shadow(0 2px 3px rgba(0,0,0,.4))!important;}',

    '#ovBody.is-luno-card-collection .kc-progress-pill{box-sizing:border-box!important;display:grid!important;grid-template-columns:62px minmax(0,1fr)!important;align-items:center!important;gap:10px!important;width:100%!important;min-height:70px!important;margin:0 0 10px!important;padding:4px 14px 4px 7px!important;border:1px solid rgba(238,204,103,.52)!important;border-radius:8px!important;background:linear-gradient(145deg,#163e49,#312349 66%,#53373d)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.12),0 4px 10px rgba(0,0,0,.34)!important;text-align:left!important;}',
    '#ovBody.is-luno-card-collection .luno-card-progress-art{display:block!important;width:62px!important;height:62px!important;object-fit:contain!important;}',
    '#ovBody.is-luno-card-collection .luno-card-progress-copy{display:flex!important;min-width:0!important;flex-direction:column!important;align-items:flex-start!important;gap:1px!important;}',
    '#ovBody.is-luno-card-collection .kc-pp-val{font-family:Cinzel,Georgia,serif!important;font-size:20px!important;line-height:24px!important;font-weight:900!important;letter-spacing:0!important;color:#ffe17e!important;text-shadow:0 2px 3px rgba(0,0,0,.55)!important;}',
    '#ovBody.is-luno-card-collection .kc-pp-lbl{font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:8px!important;line-height:11px!important;font-weight:900!important;letter-spacing:0!important;color:#78ddd3!important;}',
    '#ovBody.is-luno-card-collection .kc-section-head{box-sizing:border-box!important;display:grid!important;grid-template-columns:32px minmax(0,1fr) auto!important;align-items:center!important;gap:7px!important;min-height:40px!important;margin:10px 0 6px!important;padding:3px 5px!important;border-top:1px solid rgba(91,211,199,.24)!important;border-bottom:1px solid rgba(238,204,103,.18)!important;background:linear-gradient(90deg,rgba(32,71,75,.38),rgba(49,32,67,.22),transparent)!important;}',
    '#ovBody.is-luno-card-collection .kc-sh-label{font-family:Cinzel,Georgia,serif!important;font-size:10px!important;line-height:13px!important;font-weight:900!important;letter-spacing:0!important;color:#f5e8d1!important;}',
    '#ovBody.is-luno-card-collection .kc-sh-count{display:flex!important;min-width:34px!important;height:21px!important;align-items:center!important;justify-content:center!important;padding:0 5px!important;border:1px solid rgba(238,204,103,.34)!important;border-radius:6px!important;background:#201a34!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:8.5px!important;line-height:11px!important;font-weight:900!important;color:#ffe080!important;}',
    '#ovBody.is-luno-card-collection .kc-grid{display:grid!important;grid-template-columns:repeat(3,minmax(0,1fr))!important;gap:9px!important;margin:0 0 7px!important;}',
    '#ovBody.is-luno-card-collection .kc-upg-banner{box-sizing:border-box!important;display:grid!important;grid-template-columns:48px minmax(0,1fr)!important;align-items:center!important;gap:8px!important;min-height:60px!important;margin:16px 0 7px!important;padding:5px 9px 5px 5px!important;border:1px solid rgba(238,204,103,.42)!important;border-radius:8px!important;background:linear-gradient(145deg,#49353a,#153e47 58%,#31234a)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.1),0 4px 9px rgba(0,0,0,.27)!important;}',
    '#ovBody.is-luno-card-collection .kc-upg-ic{display:flex!important;width:48px!important;height:48px!important;align-items:center!important;justify-content:center!important;}',
    '#ovBody.is-luno-card-collection .luno-card-upgrade-art{display:block!important;width:47px!important;height:47px!important;object-fit:contain!important;}',
    '#ovBody.is-luno-card-collection .kc-upg-txt{display:flex!important;min-width:0!important;flex-direction:column!important;gap:2px!important;}',
    '#ovBody.is-luno-card-collection .kc-upg-txt b{font-family:Cinzel,Georgia,serif!important;font-size:10px!important;line-height:13px!important;font-weight:900!important;letter-spacing:0!important;color:#ffe38b!important;}',
    '#ovBody.is-luno-card-collection .kc-upg-txt span{font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:8.5px!important;line-height:12px!important;font-weight:700!important;letter-spacing:0!important;color:#d9d1df!important;}',

    '#ovBody.is-luno-deck-editor .cardmini,#ovBody.is-luno-card-collection .cardmini{box-sizing:border-box!important;position:relative!important;isolation:isolate!important;width:100%!important;aspect-ratio:3/4!important;min-width:0!important;border:1px solid rgba(235,206,116,.52)!important;border-radius:8px!important;background:linear-gradient(155deg,#243849,#251b3d 63%,#412b3a)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.11),0 4px 8px rgba(0,0,0,.36)!important;overflow:hidden!important;}',
    '#ovBody.is-luno-deck-editor .cardmini[data-rar="rare"],#ovBody.is-luno-card-collection .cardmini[data-rar="rare"]{border-color:rgba(83,213,194,.66)!important;background:linear-gradient(155deg,#17454b,#28203e 67%,#3b3542)!important;}',
    '#ovBody.is-luno-deck-editor .cardmini[data-rar="legendary"],#ovBody.is-luno-card-collection .cardmini[data-rar="legendary"]{border-color:rgba(231,193,91,.72)!important;background:linear-gradient(155deg,#4d333c,#292043 61%,#17434a)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.13),0 4px 9px rgba(0,0,0,.4),0 0 8px rgba(223,181,75,.12)!important;}',
    '#ovBody.is-luno-deck-editor .cardmini[data-rar="mythic"],#ovBody.is-luno-card-collection .cardmini[data-rar="mythic"]{border-color:rgba(112,223,209,.78)!important;background:linear-gradient(155deg,#174852,#4a303f 58%,#302146)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.15),0 4px 9px rgba(0,0,0,.4),0 0 9px rgba(93,217,202,.15)!important;}',
    '#ovBody.is-luno-deck-editor .cardmini::before,#ovBody.is-luno-card-collection .cardmini::before{content:""!important;position:absolute!important;inset:5px 5px 28px!important;z-index:-1!important;border:1px solid rgba(114,201,193,.2)!important;border-radius:6px!important;background:linear-gradient(180deg,rgba(12,21,37,.76),rgba(22,20,43,.9))!important;box-shadow:inset 0 0 9px rgba(0,0,0,.32)!important;}',
    '#ovBody.is-luno-deck-editor .cardmini .kc-cimg,#ovBody.is-luno-card-collection .cardmini .kc-cimg{position:absolute!important;inset:8px 7px 31px!important;z-index:1!important;background-size:contain!important;background-position:center!important;background-repeat:no-repeat!important;filter:drop-shadow(0 3px 3px rgba(0,0,0,.42))!important;}',
    '#ovBody.is-luno-deck-editor .cardmini .ds-name,#ovBody.is-luno-card-collection .cardmini .ds-name{box-sizing:border-box!important;position:absolute!important;left:0!important;right:0!important;bottom:0!important;z-index:5!important;display:flex!important;height:29px!important;align-items:center!important;justify-content:center!important;padding:2px 4px!important;border-top:1px solid rgba(238,204,103,.23)!important;background:linear-gradient(180deg,rgba(26,23,43,.96),rgba(13,17,29,.99))!important;color:#fff0d2!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:9.5px!important;line-height:11px!important;font-weight:900!important;letter-spacing:0!important;text-align:center!important;white-space:normal!important;overflow:hidden!important;text-overflow:clip!important;text-shadow:0 1px 2px rgba(0,0,0,.75)!important;}',
    '#ovBody.is-luno-deck-editor .cardmini .cmana,#ovBody.is-luno-card-collection .cardmini .cmana{box-sizing:border-box!important;position:absolute!important;left:4px!important;top:4px!important;z-index:7!important;display:flex!important;min-width:32px!important;height:25px!important;align-items:center!important;justify-content:center!important;gap:1px!important;padding:1px 4px 1px 1px!important;border:1px solid rgba(255,234,163,.58)!important;border-radius:7px!important;background:linear-gradient(180deg,#17485d,#20234b)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.16),0 2px 5px rgba(0,0,0,.45)!important;color:#fff4d2!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:10px!important;line-height:12px!important;font-weight:900!important;}',
    '#ovBody .luno-card-mana-art{display:block!important;width:20px!important;height:20px!important;object-fit:contain!important;flex:0 0 20px!important;}',
    '#ovBody.is-luno-deck-editor .cardmini .csub,#ovBody.is-luno-card-collection .cardmini .csub{box-sizing:border-box!important;position:absolute!important;right:4px!important;top:4px!important;z-index:7!important;display:flex!important;min-width:28px!important;height:21px!important;align-items:center!important;justify-content:center!important;padding:1px 4px!important;border:1px solid rgba(255,241,184,.55)!important;border-radius:6px!important;background:linear-gradient(180deg,#e6c65c,#9d6820)!important;color:#251630!important;font-family:Cinzel,Georgia,serif!important;font-size:7.5px!important;line-height:10px!important;font-weight:900!important;letter-spacing:0!important;}',
    '#ovBody.is-luno-deck-editor .cardmini .pool-check,#ovBody.is-luno-card-collection .cardmini .pool-check{position:absolute!important;right:4px!important;bottom:31px!important;z-index:8!important;display:block!important;width:27px!important;height:27px!important;color:transparent!important;font-size:0!important;}',
    '#ovBody .luno-card-selected-art{display:block!important;width:27px!important;height:27px!important;object-fit:contain!important;filter:drop-shadow(0 2px 3px rgba(0,0,0,.5))!important;}',
    '#ovBody.is-luno-deck-editor .deck-slot:not(.filled){border:1px dashed rgba(104,210,197,.42)!important;background:linear-gradient(155deg,rgba(22,57,66,.65),rgba(37,27,58,.78))!important;box-shadow:inset 0 0 14px rgba(0,0,0,.28)!important;}',
    '#ovBody.is-luno-deck-editor .deck-slot .ds-plus{display:flex!important;width:34px!important;height:34px!important;align-items:center!important;justify-content:center!important;border:1px solid rgba(238,205,112,.44)!important;border-radius:50%!important;background:#25203c!important;color:#75d9d0!important;font-family:Arial,sans-serif!important;font-size:24px!important;line-height:24px!important;font-weight:500!important;}',
    '#ovBody.is-luno-card-collection .kc-card.kc-locked{filter:grayscale(.76) brightness(.64)!important;}',
    '#ovBody.is-luno-card-collection .kc-card .kc-locked-icon{position:absolute!important;left:50%!important;top:45%!important;z-index:6!important;transform:translate(-50%,-50%)!important;margin:0!important;font-size:19px!important;filter:drop-shadow(0 2px 3px rgba(0,0,0,.62))!important;}',
    '#ovBody.is-luno-card-collection .kc-card .kc-where{box-sizing:border-box!important;position:absolute!important;left:4px!important;right:4px!important;bottom:31px!important;z-index:6!important;min-height:16px!important;padding:2px 3px!important;border-radius:5px!important;background:rgba(24,19,39,.9)!important;color:#ffe080!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;font-size:7px!important;line-height:10px!important;font-weight:900!important;letter-spacing:0!important;text-align:center!important;white-space:normal!important;}',

    '#cardActMenu .cam-box.is-luno-card-detail-v10,#cardActionOv .cam-box.is-luno-card-detail-v10{box-sizing:border-box!important;border:1px solid rgba(238,204,103,.6)!important;border-radius:10px!important;background:linear-gradient(155deg,#163f48,#312248 57%,#51343e)!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.13),0 15px 35px rgba(0,0,0,.58)!important;}',
    '#cardActMenu .is-luno-card-detail-v10 .cam-img,#cardActionOv .is-luno-card-detail-v10 .cam-img{border:1px solid rgba(238,204,103,.48)!important;border-radius:8px!important;background:linear-gradient(160deg,#121f31,#241a3b)!important;}',
    '#cardActMenu .is-luno-card-detail-v10 .cam-img,#cardActionOv .is-luno-card-detail-v10 .cam-img{width:108px!important;height:134px!important;margin-bottom:8px!important;}',
    '#cardActMenu .is-luno-card-detail-v10 .cam-img img,#cardActionOv .is-luno-card-detail-v10 .cam-img img{box-sizing:border-box!important;object-fit:contain!important;padding:6px!important;border-radius:8px!important;filter:drop-shadow(0 5px 5px rgba(0,0,0,.4))!important;}',
    '#cardActMenu .is-luno-card-detail-v10 .cam-cost,#cardActionOv .is-luno-card-detail-v10 .cam-cost{display:flex!important;min-height:31px!important;align-items:center!important;justify-content:center!important;gap:5px!important;margin:5px 0!important;padding:3px 7px!important;border:1px solid rgba(94,211,200,.28)!important;border-radius:7px!important;background:rgba(15,35,45,.68)!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;letter-spacing:0!important;}',
    '#cardActMenu .is-luno-card-detail-v10 .cam-cost img,#cardActionOv .is-luno-card-detail-v10 .cam-cost img{display:block!important;width:25px!important;height:25px!important;object-fit:contain!important;}',
    '#cardActMenu .is-luno-card-detail-v10 .cam-cost b,#cardActionOv .is-luno-card-detail-v10 .cam-cost b{font-size:10px!important;line-height:13px!important;color:#fff0cd!important;}',
    '#cardActMenu .is-luno-card-detail-v10 .cam-cost span,#cardActionOv .is-luno-card-detail-v10 .cam-cost span{font-size:7px!important;line-height:10px!important;font-weight:900!important;color:#71d9cf!important;}',
    '#cardActMenu .is-luno-card-detail-v10 .cam-name,#cardActionOv .is-luno-card-detail-v10 .cam-name{font-family:Cinzel,Georgia,serif!important;letter-spacing:0!important;color:#fff0c5!important;}',
    '#cardActMenu .is-luno-card-detail-v10 .cam-desc,#cardActionOv .is-luno-card-detail-v10 .cam-desc{font-family:"Trebuchet MS",system-ui,sans-serif!important;letter-spacing:0!important;line-height:1.45!important;color:#e3dbe5!important;}',
    '#cardActMenu .is-luno-card-detail-v10 .cam-btn,#cardActMenu .is-luno-card-detail-v10 .cam-close,#cardActionOv .is-luno-card-detail-v10 .cam-btn,#cardActionOv .is-luno-card-detail-v10 .cam-close{border-radius:8px!important;font-family:"Trebuchet MS",system-ui,sans-serif!important;letter-spacing:0!important;}',
    '#cardActMenu .is-luno-card-detail-v10 .cam-detail,#cardActionOv .is-luno-card-detail-v10 .cam-detail{display:flex!important;min-height:43px!important;align-items:center!important;justify-content:center!important;gap:7px!important;padding:5px 10px!important;}',
    '#cardActMenu .is-luno-card-detail-v10 .luno-card-guide-art,#cardActionOv .is-luno-card-detail-v10 .luno-card-guide-art{display:block!important;width:27px!important;height:27px!important;object-fit:contain!important;flex:0 0 27px!important;}',
    '#cardActMenu .is-luno-card-detail-v10 .cam-close,#cardActionOv .is-luno-card-detail-v10 .cam-close{position:absolute!important;right:8px!important;top:8px!important;z-index:8!important;display:flex!important;width:31px!important;height:31px!important;align-items:center!important;justify-content:center!important;padding:0!important;border:1px solid rgba(255,226,151,.38)!important;border-radius:50%!important;background:rgba(22,22,42,.88)!important;color:#fff0c7!important;font-family:Arial,sans-serif!important;font-size:22px!important;line-height:22px!important;font-weight:400!important;box-shadow:0 2px 5px rgba(0,0,0,.42)!important;}',

    '@media(max-width:360px){#menu .mn-luno-live.is-luno-v10 .mn-luno-img{width:146px!important;height:146px!important;max-width:44vw!important}#menu .mn-luno-live.is-luno-v10 .mn-luno-bubble{width:216px!important;max-width:60vw!important;font-size:10px!important;line-height:13px!important}#ovBody.is-luno-collection-hub{padding-left:10px!important;padding-right:10px!important}#ovBody.is-luno-collection-hub .ch-card{grid-template-columns:72px minmax(0,1fr) 20px!important;min-height:90px!important}#ovBody.is-luno-collection-hub .ch-ic,#ovBody.is-luno-collection-hub .ch-icimg{width:70px!important;height:70px!important}#ovBody.is-luno-deck-editor,#ovBody.is-luno-card-collection{padding-left:10px!important;padding-right:10px!important}#ovBody.is-luno-deck-editor .deck-slots,#ovBody.is-luno-deck-editor .pool-group,#ovBody.is-luno-card-collection .kc-grid{gap:7px!important}#ovBody.is-luno-deck-editor .cardmini .ds-name,#ovBody.is-luno-card-collection .cardmini .ds-name{font-size:9px!important;line-height:10.5px!important;padding-left:3px!important;padding-right:3px!important}}',
    '@media(prefers-reduced-motion:reduce){#menu .mn-luno-live.is-luno-v10 .mn-luno-img{animation:none!important;transition:none!important}}'
  ].join('');
  document.head.appendChild(collectionV10Css);

  setCardArt();
  setEmojiArt();
  setOttomanPieces();
  installAvatarArt();
  patchLevelExperience();
  patchEndGame();
  patchTopbarProfile();
  patchArenaBarUpdates();
  installMainMenuLuno();
  patchCostumeExperience();
  patchShopExperience();
  patchProfileExperience();
  patchPassExperience();
  patchPassMissionsExperience();
  patchSettingsExperience();
  patchFriendsExperience();
  patchMissionsExperience();
  patchRankingExperience();
  patchGuideAndProfileEditExperience();
  patchCollectionExperience();
  if(document.readyState==='loading'){
    document.addEventListener('DOMContentLoaded',function(){
      setCardArt();setEmojiArt();setOttomanPieces();installAvatarArt();patchLevelExperience();patchArenaBarUpdates();applyStaticSlots();applyMainMenuArt();patchEndGame();patchCostumeExperience();patchShopExperience();patchProfileExperience();patchPassExperience();patchPassMissionsExperience();patchSettingsExperience();patchFriendsExperience();patchMissionsExperience();patchRankingExperience();patchGuideAndProfileEditExperience();patchCollectionExperience();updateShopDailyBadge();
      setTimeout(applyMainMenuArt,560);
    },{once:true});
  }else{
    applyStaticSlots();
    applyMainMenuArt();
    setTimeout(applyMainMenuArt,560);
  }

})();
