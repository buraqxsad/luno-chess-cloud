'use strict';

const MISSION_CATALOG={
  daily:{
    d1:{counter:'d1',target:1,reward:{gold:150}},
    d2:{counter:'d2',target:3,reward:{gold:200}},
    d3:{counter:'d3',target:5,reward:{gold:100}},
    d4:{counter:'d4',target:1,reward:{gold:250}},
    d_cap:{counter:'d_cap',target:8,reward:{gold:180}},
    d_capture:{counter:'d_capture',target:3,reward:{gold:180}},
    d_draw:{counter:'d_draw',target:1,reward:{gold:180}},
    d_checks:{counter:'d_checks',target:2,reward:{gold:200}},
    d_legend:{counter:'d_legend',target:1,reward:{gold:220}},
    dc_freeze:{counter:'cu_freeze',target:3,reward:{gold:180},card:'freeze'},
    dc_barb:{counter:'cu_barbarian',target:2,reward:{gold:160},card:'barbarian'},
    dc_pois:{counter:'cu_poison_q',target:2,reward:{gold:170},card:'poison_q'},
    dc_block:{counter:'cu_card_block',target:2,reward:{gold:160},card:'card_block'},
    dc_glue:{counter:'cu_glue',target:2,reward:{gold:160},card:'glue'},
    dc_angry:{counter:'cu2_angry',target:2,reward:{gold:170},anyOf:['angry_n','angry_b']},
    dc_arch:{counter:'cu_archer',target:2,reward:{gold:170},card:'archer'},
    dc_trapf:{counter:'cf_trap',target:3,reward:{gold:180}},
    dc_radarf:{counter:'cf_radar',target:2,reward:{gold:120}},
    dc_resf:{counter:'cf_resist',target:3,reward:{gold:150}},
    dc_shf:{counter:'cf_shield',target:2,reward:{gold:150}},
    dc_fog:{counter:'cu_fog',target:2,reward:{gold:150},card:'fog'}
  },
  weekly:{
    w1:{counter:'w1',target:10,reward:{gold:1000}},
    w2:{counter:'w2',target:5,reward:{gold:400}},
    w3:{counter:'w3',target:25,reward:{gold:600}},
    w4:{counter:'w4',target:5,reward:{gold:600}},
    w_capture:{counter:'w_capture',target:20,reward:{gold:700}},
    w_draw:{counter:'w_draw',target:3,reward:{gold:500}},
    w_checks:{counter:'w_checks',target:8,reward:{gold:700}},
    w_promote:{counter:'w_promote',target:1,reward:{gold:700}},
    w_cards:{counter:'w_cards',target:30,reward:{gold:800}},
    wc_freeze:{counter:'cu_freeze',target:8,reward:{gold:500},card:'freeze'},
    wc_barb:{counter:'cu_barbarian',target:6,reward:{gold:450},card:'barbarian'},
    wc_trapf:{counter:'cf_trap',target:10,reward:{gold:500}},
    wc_deployf:{counter:'cf_deploy',target:3,reward:{gold:500}},
    wc_plague:{counter:'cu_plague',target:3,reward:{gold:450},card:'plague'},
    wc_ghost:{counter:'cu_ghosts',target:3,reward:{gold:450},card:'ghosts'},
    wc_imm:{counter:'cu_immunity',target:3,reward:{gold:400},card:'immunity'},
    wc_med:{counter:'cu_medium',target:4,reward:{gold:400},card:'medium'}
  },
  special:{
    s1:{counter:'arenaReached',target:1,reward:{gems:30}}
  }
};

const ACHIEVEMENT_CATALOG={
  first_win:{statKey:'wins',target:1,reward:{gold:100}},
  first_card:{statKey:'cardsPlayed',target:1,reward:{gold:50}},
  win_10:{statKey:'wins',target:10,reward:{gold:300}},
  win_50:{statKey:'wins',target:50,reward:{gold:1500}},
  win_100:{statKey:'wins',target:100,reward:{gold:3000,gems:15}},
  win_500:{statKey:'wins',target:500,reward:{gold:20000,gems:40}},
  streak_3:{statKey:'bestStreak',target:3,reward:{gold:200}},
  streak_5:{statKey:'bestStreak',target:5,reward:{gold:800}},
  streak_10:{statKey:'bestStreak',target:10,reward:{gold:3000,gems:10}},
  arena_3:{statKey:'arenaIdx',target:3,reward:{gold:500}},
  arena_5:{statKey:'arenaIdx',target:5,reward:{gold:1500}},
  arena_7:{statKey:'arenaIdx',target:7,reward:{gold:4000,gems:15}},
  arena_8:{statKey:'arenaIdx',target:8,reward:{gold:10000,gems:30}},
  arena_9:{statKey:'arenaIdx',target:9,reward:{gold:25000,gems:75}},
  draw_10:{statKey:'draws',target:10,reward:{gold:400}},
  captures_100:{statKey:'captures',target:100,reward:{gold:700}},
  checks_50:{statKey:'checks',target:50,reward:{gold:900}},
  promotions_5:{statKey:'promotions',target:5,reward:{gold:900,gems:5}},
  cards_100:{statKey:'cardsPlayed',target:100,reward:{gold:500}},
  cards_500:{statKey:'cardsPlayed',target:500,reward:{gold:3000,gems:10}},
  skin_3:{statKey:'ownedSkinsCount',target:3,reward:{gold:600}},
  skin_all:{statKey:'ownedSkinsCount',target:8,reward:{gold:12000,gems:30}},
  friends_5:{statKey:'friendsCount',target:5,reward:{gold:300}},
  chests_10:{statKey:'chestsOpened',target:10,reward:{gold:800}},
  games_50:{statKey:'gamesPlayed',target:50,reward:{gold:400}},
  games_200:{statKey:'gamesPlayed',target:200,reward:{gold:2000}},
  login_7:{statKey:'loginStreak',target:7,reward:{gold:300}},
  login_30:{statKey:'loginStreak',target:30,reward:{gold:4000,gems:15}},
  level_10:{statKey:'level',target:10,reward:{gold:500}},
  level_25:{statKey:'level',target:25,reward:{gold:2000}},
  daily_7:{statKey:'dailyStreak',target:7,reward:{gold:1000}},
  premium_member:{statKey:'isPremium',target:1,reward:{gold:1000,gems:25}},
  premium_30:{statKey:'premiumDays',target:30,reward:{gold:5000,gems:100}}
};

// Copy is part of the server contract so a newly rotated item can never reach
// the client as an unnamed "secret" mission or achievement.
const MISSION_COPY={
  d1:['İlk zafer','Bir sıralı maç kazan.'],
  d2:['Zafer zamanı','3 maç tamamla.'],
  d3:['Kart ustası','5 kart kullan.'],
  d4:['Hızlı zafer','30 hamleden kısa bir maç kazan.'],
  d_cap:['Avcı piyon','8 taş ele geçir.'],
  d_capture:['Keskin hamle','3 rakip taşı ele geçir.'],
  d_draw:['Centilmen oyun','Bir maçı beraberlikle tamamla.'],
  d_checks:['Şah tehdidi','Rakip şahı 2 kez şah altında bırak.'],
  d_legend:['Efsanevi taktik','Bir efsanevi kart kullan.'],
  dc_freeze:['Buz gibi plan','Dondurma kartını 3 kez kullan.'],
  dc_barb:['Barbar hücumu','Barbar Piyon kartını 2 kez kullan.'],
  dc_pois:['Zehirli hamle','Zehirli Vezir kartını 2 kez kullan.'],
  dc_block:['Sessiz savunma','Kart Engelleme kartını 2 kez kullan.'],
  dc_glue:['Yapışkan plan','Tutkal Piyon kartını 2 kez kullan.'],
  dc_angry:['Öfkeli kanat','Öfkeli At veya Fil kartını 2 kez kullan.'],
  dc_arch:['Uzak nişan','Okçu Piyon kartını 2 kez kullan.'],
  dc_trapf:['Tuzak ustası','3 tuzak kartı kullan.'],
  dc_radarf:['İz sürücü','2 radar kartı kullan.'],
  dc_resf:['Dirençli duruş','3 direniş kartı kullan.'],
  dc_shf:['Kalkan duvarı','2 kalkan kartı kullan.'],
  dc_fog:['Sis perdesi','Sis Perdesi kartını 2 kez kullan.'],
  w1:['Haftalık hedef','10 maç kazan.'],
  w2:['Efsane avı','5 efsanevi kart kullan.'],
  w3:['Tahta temizliği','25 rakip taşı ele geçir.'],
  w4:['Seriyi koru','5 maçlık galibiyet serisi yap.'],
  w_capture:['Büyük av','20 rakip taşı ele geçir.'],
  w_draw:['Dengeli oyuncu','3 maçı beraberlikle tamamla.'],
  w_checks:['Şah avcısı','8 kez şah tehdidi oluştur.'],
  w_promote:['Terfi zamanı','Bir piyonu terfi ettir.'],
  w_cards:['Kart yağmuru','30 kart kullan.'],
  wc_freeze:['Donmuş tahta','Dondurma kartını 8 kez kullan.'],
  wc_barb:['Barbar ordusu','Barbar Piyon kartını 6 kez kullan.'],
  wc_trapf:['Haftalık tuzak','10 tuzak kartı kullan.'],
  wc_deployf:['Sefer emri','3 konuşlandırma kartı kullan.'],
  wc_plague:['Kara strateji','Kara Veba kartını 3 kez kullan.'],
  wc_ghost:['Hayalet filosu','Şahin Hayaletleri kartını 3 kez kullan.'],
  wc_imm:['Bağışıklık duvarı','Bağışıklık kartını 3 kez kullan.'],
  wc_med:['Şifacı hamle','Medyum kartını 4 kez kullan.'],
  s1:['Arena yolcusu','İlk arenanı aç.']
};

const ACHIEVEMENT_COPY={
  first_win:['İlk Zafer','İlk maçını kazan.'],first_card:['Kart Ustası','İlk kartını kullan.'],
  win_10:['Acemi Savaşçı','10 maç kazan.'],win_50:['Tahta Ustası','50 maç kazan.'],win_100:['Şampiyon','100 maç kazan.'],win_500:['Luno Efsanesi','500 maç kazan.'],
  streak_3:['Sıcak Eller','3 maç üst üste kazan.'],streak_5:['Durmak Yok','5 maçlık seri yap.'],streak_10:['Kesintisiz Taht','10 maçlık seri yap.'],
  arena_3:['Hükümdar','3. arenaya ulaş.'],arena_5:['İmparator','5. arenaya ulaş.'],arena_7:['Luno Kraliyeti','Luno Kraliyeti arenasına ulaş.'],arena_8:['Luno Legend','Luno Legend arenasına ulaş.'],arena_9:['Luno Mythic','Luno Mythic arenasına ulaş.'],
  draw_10:['Denge Ustası','10 beraberlik tamamla.'],captures_100:['Tahta Temizleyici','100 taş ele geçir.'],checks_50:['Şah Ustası','50 şah tehdidi oluştur.'],promotions_5:['Terfi Ustası','5 piyonu terfi ettir.'],
  cards_100:['Kart Koleksiyoncusu','100 kart kullan.'],cards_500:['Kart Stratejisti','500 kart kullan.'],skin_3:['Stil Sahibi','3 taş görünümü edin.'],skin_all:['Koleksiyoncu','8 taş görünümünü tamamla.'],
  friends_5:['Tahta Dostları','5 arkadaş edin.'],chests_10:['Sandık Avcısı','10 sandık aç.'],games_50:['Maraton','Toplam 50 maç oyna.'],games_200:['Tahtanın Sesi','Toplam 200 maç oyna.'],
  login_7:['Sadık Oyuncu','7 günlük giriş serisi yap.'],login_30:['Luno Müdavimi','30 günlük giriş serisi yap.'],level_10:['Yükselen Yıldız','10. seviyeye ulaş.'],level_25:['Usta Oyuncu','25. seviyeye ulaş.'],
  daily_7:['Her Gün Tahtada','7 günlük ödül serisi yap.'],premium_member:['Kraliyet Üyesi','Premium üyeliği aç.'],premium_30:['Premium Elçisi','30 gün Premium kal.']
};

const PASS_CURRENCY_REWARDS={
  free:{
    1:{gold:120},2:{gold:140},3:{gold:160},4:{gold:180},5:{gold:200,gems:20},6:{gold:220},7:{gold:240},8:{gold:260},9:{gold:280},10:{gold:300,gems:20},
    11:{gold:320},12:{gold:340},13:{gold:360},14:{gold:380},15:{gold:400,gems:20},16:{gold:420},17:{gold:440},18:{gold:460},19:{gold:480},20:{gold:500,gems:20},
    21:{gold:520},22:{gold:540},23:{gold:560},24:{gold:580},25:{gold:600,gems:20},26:{gold:620},27:{gold:640},28:{gold:660},29:{gold:680},30:{gold:700,gems:20}
  },
  premium:{
    1:{gold:30,gems:18},2:{gold:60,gems:18},3:{gold:90,gems:18},4:{gold:120,gems:18},5:{gold:150,gems:18},6:{gold:180,gems:18},7:{gold:210,gems:18},8:{gold:240,gems:18},9:{gold:270,gems:18},10:{gold:300,gems:18},
    11:{gold:330,gems:18},12:{gold:360,gems:18},13:{gold:390,gems:18},14:{gold:420,gems:18},15:{gold:450,gems:18},16:{gold:480,gems:18},17:{gold:510,gems:18},18:{gold:540,gems:18},19:{gold:570,gems:18},20:{gold:600,gems:18},
    21:{gold:630,gems:18},22:{gold:660,gems:18},23:{gold:690,gems:18},24:{gold:720,gems:18},25:{gold:750,gems:18},26:{gold:780,gems:18},27:{gold:810,gems:18},28:{gold:840,gems:18},29:{gold:870,gems:18},30:{gold:900,gems:18}
  }
};

// Version 1 remains available for purchased/live seasons. New-season pacing
// returns 120 free + 330 premium gems, not a recurring 210-gem currency profit.
const PASS_CURRENCY_REWARDS_V2=Object.freeze({
  free:PASS_CURRENCY_REWARDS.free,
  premium:Object.freeze(Object.fromEntries(Array.from({length:30},(_,index)=>{
    const level=index+1;return [level,Object.freeze({gold:level*30,gems:11})];
  })))
});

// Content rewards are persisted in the server pass state as well as the
// currency reward above. Keeping this catalog beside the currency catalog
// prevents the client-only Pass preview from becoming an unclaimable reward.
const PASS_CONTENT_REWARDS={
  free:{
    4:{kind:'emoji',id:'laugh'},
    8:{kind:'chest',id:'rare'},
    12:{kind:'emoji',id:'trophy'},
    16:{kind:'chest',id:'legendary'},
    20:{kind:'piece_set',id:'ottoman'},
    24:{kind:'emoji',id:'heart'},
    28:{kind:'chest',id:'royal'},
    30:{kind:'piece_set',id:'viking'}
  },
  premium:{
    5:{kind:'chest',id:'rare'},
    10:{kind:'emoji',id:'angry'},
    15:{kind:'piece_set',id:'roma'},
    20:{kind:'chest',id:'legendary'},
    25:{kind:'piece_set',id:'dragon'},
    30:{kind:'piece_set',id:'neon'}
  }
};

const SEASON_REWARDS=[
  {minTrophies:0,tier:'Bronze',reward:{gold:500,gems:10}},
  {minTrophies:600,tier:'Silver',reward:{gold:1500,gems:30}},
  {minTrophies:1000,tier:'Gold',reward:{gold:3000,gems:60}},
  {minTrophies:1500,tier:'Platinum',reward:{gold:6000,gems:120}},
  {minTrophies:2000,tier:'Diamond',reward:{gold:12000,gems:250}},
  {minTrophies:2750,tier:'Master',reward:{gold:25000,gems:500}},
  {minTrophies:3500,tier:'Grandmaster',reward:{gold:50000,gems:1000}},
  {minTrophies:5000,tier:'Luno Mythic',reward:{gold:100000,gems:2000}}
];

// Sezon yolu Pass'ten bağımsızdır: yalnızca o sezonda ulaşılan kupa zirvesi
// ilerlemeyi belirler ve her kademe ayrı ayrı sunucu tarafından alınır.
const SEASON_PATH_REWARDS=Object.freeze([
  Object.freeze({id:'path_1',title:'İlk adım',minTrophies:0,reward:Object.freeze({gold:100})}),
  Object.freeze({id:'path_2',title:'Piyon Vadisi',minTrophies:100,reward:Object.freeze({gold:150})}),
  Object.freeze({id:'path_3',title:'Hükümdarın mührü',minTrophies:300,reward:Object.freeze({gems:5})}),
  Object.freeze({id:'path_4',title:'Gölge geçidi',minTrophies:600,reward:Object.freeze({gold:250})}),
  Object.freeze({id:'path_5',title:'İmparator tacı',minTrophies:1000,reward:Object.freeze({gold:350,gems:5})}),
  Object.freeze({id:'path_6',title:'Usta hamlesi',minTrophies:1500,reward:Object.freeze({gold:500})}),
  Object.freeze({id:'path_7',title:'Kraliyet kapısı',minTrophies:2200,reward:Object.freeze({gold:600,gems:10})}),
  Object.freeze({id:'path_8',title:'Legend yükselişi',minTrophies:3000,reward:Object.freeze({gold:750})}),
  Object.freeze({id:'path_9',title:'Mythic zirve',minTrophies:4000,reward:Object.freeze({gold:1000,gems:15})}),
  Object.freeze({id:'path_10',title:'Luno şampiyonu',minTrophies:5000,reward:Object.freeze({gold:1500,gems:25})})
]);

function softItem(currency,price,kind,id,extra){
  return Object.freeze(Object.assign({currency,price,grant:{kind,id}},extra||{}));
}

const SOFT_ITEM_CATALOG={
  'pass:premium':softItem('gems',450,'pass_premium','premium',{seasonScoped:true}),

  'piece_set:ottoman':softItem('gold',1000,'piece_set','ottoman'),
  'piece_set:roma':softItem('gems',480,'piece_set','roma'),
  'piece_set:brit':softItem('gems',480,'piece_set','brit'),
  'piece_set:viking':softItem('gems',480,'piece_set','viking'),
  'piece_set:tasdevri':softItem('gems',480,'piece_set','tasdevri'),
  'piece_set:samuray':softItem('gems',480,'piece_set','samuray'),
  'piece_set:ice':softItem('gems',720,'piece_set','ice'),
  'piece_set:dragon':softItem('gems',720,'piece_set','dragon'),
  'piece_set:neon':softItem('gems',980,'piece_set','neon'),

  'skin:obsidian':softItem('gold',2000,'skin','obsidian'),
  'skin:jade':softItem('gold',6000,'skin','jade'),
  'skin:ruby':softItem('gold',6000,'skin','ruby'),
  'skin:sapphire':softItem('gold',6000,'skin','sapphire'),
  'skin:amethyst':softItem('gems',350,'skin','amethyst'),
  'skin:dragon':softItem('gems',350,'skin','dragon'),
  'skin:celestial':softItem('gems',900,'skin','celestial'),

  'frame:bronze':softItem('gold',500,'frame','bronze'),
  'frame:silver':softItem('gold',1500,'frame','silver'),
  'frame:gold':softItem('gold',5000,'frame','gold'),
  'frame:arena':softItem('gems',50,'frame','arena'),
  'frame:mythic':softItem('gems',150,'frame','mythic'),
  'frame:inferno':softItem('gems',400,'frame','inferno'),
  'frame:frost':softItem('gems',350,'frame','frost'),
  'frame:royal':softItem('gold',25000,'frame','royal'),

  'bio_frame:emerald':softItem('gold',3000,'bio_frame','emerald'),
  'bio_frame:ruby':softItem('gold',3000,'bio_frame','ruby'),
  'bio_frame:ocean':softItem('gold',3000,'bio_frame','ocean'),
  'bio_frame:royal':softItem('gems',120,'bio_frame','royal'),
  'bio_frame:inferno':softItem('gems',120,'bio_frame','inferno')
};

const EMOJI_RARITIES={
  smile:'common',heart:'common',laugh:'common',cry:'common',angry:'common',think:'common',
  fire:'rare',star:'rare',thunder:'rare',bomb:'rare',strat:'rare',trophy:'legendary',crown:'legendary',rainbow:'mythic'
};
const EMOJI_PRICES={common:500,rare:1500,legendary:4000,mythic:10000};
Object.keys(EMOJI_RARITIES).forEach(function(id){
  SOFT_ITEM_CATALOG['emoji:'+id]=softItem('gold',EMOJI_PRICES[EMOJI_RARITIES[id]],'emoji',id);
});

const COSTUME_PRICES={
  k_crystal:280,k_commander:280,k_wizard:480,k_gold:480,
  q_crystal:280,q_shadow:280,q_gold:480,
  r_stone:240,r_royal:240,r_ice:400,r_mech:400,
  b_wizard:220,b_emerald:220,b_shadow:360,b_sun:360,
  n_armor:220,n_shadow:220,n_gold:360,n_dragon:360,
  p_soldier:160,p_archer:160,p_apprentice:300,p_gold:300
};
Object.keys(COSTUME_PRICES).forEach(function(id){
  SOFT_ITEM_CATALOG['costume:'+id]=softItem('gems',COSTUME_PRICES[id],'costume',id,{pieceType:id[0].toUpperCase()});
});
SOFT_ITEM_CATALOG['costume_pack:all']=softItem('gems',900,'costume_pack','all');
Object.freeze(SOFT_ITEM_CATALOG);

const CARD_UPGRADE_CATALOG=Object.freeze({
  trap:Object.freeze({2:{price:2500,minArenaIdx:2},3:{price:5000,minArenaIdx:4}}),
  radar:Object.freeze({2:{price:2500,minArenaIdx:2},3:{price:5000,minArenaIdx:4}}),
  resist:Object.freeze({2:{price:2500,minArenaIdx:3},3:{price:5000,minArenaIdx:5}}),
  shield:Object.freeze({2:{price:2500,minArenaIdx:4},3:{price:5000,minArenaIdx:6}}),
  deploy:Object.freeze({2:{price:2500,minArenaIdx:6},3:{price:5000,minArenaIdx:7}})
});

const SKIN_DROP_CATALOG=Object.freeze({
  classic:{name:'Klasik',rarity:'common',target:20},obsidian:{name:'Obsidyen',rarity:'common',target:20},
  jade:{name:'Yesim',rarity:'rare',target:10},ruby:{name:'Yakut',rarity:'rare',target:10},sapphire:{name:'Safir',rarity:'rare',target:10},
  amethyst:{name:'Mor Kuvars',rarity:'legendary',target:5},dragon:{name:'Ejderha',rarity:'legendary',target:5},
  celestial:{name:'Goksel',rarity:'mythic',target:5}
});
const EMOJI_DROP_CATALOG=Object.freeze({
  smile:{name:'Merhaba',rarity:'common',target:20},heart:{name:'Asik',rarity:'common',target:20},laugh:{name:'Sevinen',rarity:'common',target:20},cry:{name:'Aglayan',rarity:'common',target:20},angry:{name:'Sinirli',rarity:'common',target:20},think:{name:'Hamle Dusunen',rarity:'common',target:20},
  fire:{name:'Ofkelenen',rarity:'rare',target:10},star:{name:'Havali',rarity:'rare',target:10},thunder:{name:'Seytani',rarity:'rare',target:10},bomb:{name:'Begenen',rarity:'rare',target:10},strat:{name:'Stratejist',rarity:'rare',target:10},
  trophy:{name:'Kupa Kaldiran',rarity:'legendary',target:5},crown:{name:'Kral',rarity:'legendary',target:5},rainbow:{name:'Ejder Ofkesi',rarity:'mythic',target:5}
});
const FRAME_SHARD_CATALOG=Object.freeze({
  galaxy:{name:'Galaksi',rarity:'legendary',target:10},phoenix:{name:'Anka',rarity:'legendary',target:10},rainbow:{name:'Gokkusagi',rarity:'mythic',target:15}
});
const BIO_FRAME_SHARD_CATALOG=Object.freeze({
  aurora:{name:'Aurora',rarity:'legendary',target:8},galaxy:{name:'Galaksi',rarity:'mythic',target:12}
});
const CARD_UNLOCK_CATALOG=Object.freeze({
  barbarian:{name:'Barbar Piyon',rarity:'common',arenaIdx:0},card_block:{name:'Kart Engelleme',rarity:'common',arenaIdx:0},poison_q:{name:'Zehirli Vezir',rarity:'common',arenaIdx:0},angry_n:{name:'Ofkeli At',rarity:'rare',arenaIdx:0},glue:{name:'Tutkal Piyon',rarity:'common',arenaIdx:0},freeze:{name:'Dondurma',rarity:'common',arenaIdx:0},
  trap1:{name:'Basit Tuzak',rarity:'common',arenaIdx:1},radar1:{name:'Tetikleyici',rarity:'common',arenaIdx:1},resist1:{name:'Direnis Piyon',rarity:'common',arenaIdx:2},fog:{name:'Sis Perdesi',rarity:'rare',arenaIdx:2},
  shield1:{name:'Zirh',rarity:'rare',arenaIdx:3},archer:{name:'Okcu Piyon',rarity:'rare',arenaIdx:3},medium:{name:'Medyum',rarity:'rare',arenaIdx:4},angry_b:{name:'Ofkeli Fil',rarity:'rare',arenaIdx:4},
  deploy1:{name:'Piyade Seferi',rarity:'legendary',arenaIdx:5},plague:{name:'Kara Veba',rarity:'legendary',arenaIdx:5},ghosts:{name:'Sahin Hayaletleri',rarity:'legendary',arenaIdx:6},reinforce:{name:'Er Birlesmesi',rarity:'legendary',arenaIdx:6},immunity:{name:'Bagisiklik',rarity:'mythic',arenaIdx:7}
});

const CHEST_CATALOG=Object.freeze({
  common:Object.freeze({currency:'gold',price:500,items:5,drops:{gold:{chance:1,min:50,max:150},skin_common:{chance:.5,min:1,max:3},emoji_common:{chance:.5,min:1,max:3},skin_rare:{chance:.08,min:1,max:1},emoji_rare:{chance:.08,min:1,max:1}}}),
  rare:Object.freeze({currency:'gold',price:1500,items:6,drops:{gold:{chance:1,min:150,max:400},skin_common:{chance:.4,min:1,max:3},emoji_common:{chance:.4,min:1,max:3},skin_rare:{chance:.4,min:1,max:2},emoji_rare:{chance:.4,min:1,max:2},skin_legendary:{chance:.08,min:1,max:1},emoji_legendary:{chance:.08,min:1,max:1}}}),
  legendary:Object.freeze({currency:'gold',price:3500,items:7,drops:{gold:{chance:1,min:400,max:1000},skin_common:{chance:.3,min:2,max:4},emoji_common:{chance:.3,min:2,max:4},skin_rare:{chance:.5,min:1,max:3},emoji_rare:{chance:.5,min:1,max:3},skin_legendary:{chance:.4,min:1,max:2},emoji_legendary:{chance:.4,min:1,max:2},skin_mythic:{chance:.05,min:1,max:1},emoji_mythic:{chance:.05,min:1,max:1}}}),
  royal:Object.freeze({currency:'gems',price:380,items:8,drops:{gold:{chance:1,min:1000,max:2500},skin_rare:{chance:.7,min:2,max:4},emoji_rare:{chance:.7,min:2,max:4},skin_legendary:{chance:.8,min:1,max:3},emoji_legendary:{chance:.8,min:1,max:3},skin_mythic:{chance:.3,min:1,max:2},emoji_mythic:{chance:.3,min:1,max:2}}})
});

module.exports={
  ACHIEVEMENT_CATALOG,BIO_FRAME_SHARD_CATALOG,CARD_UNLOCK_CATALOG,CARD_UPGRADE_CATALOG,CHEST_CATALOG,
  COSTUME_PRICES,EMOJI_DROP_CATALOG,FRAME_SHARD_CATALOG,MISSION_CATALOG,PASS_CONTENT_REWARDS,PASS_CURRENCY_REWARDS,PASS_CURRENCY_REWARDS_V2,
  ACHIEVEMENT_COPY,MISSION_COPY,SEASON_PATH_REWARDS,SEASON_REWARDS,SKIN_DROP_CATALOG,SOFT_ITEM_CATALOG
};
