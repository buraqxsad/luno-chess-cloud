(function(){
  'use strict';

  var fallback={versionName:'1.5.7',versionCode:12,packageName:'com.luno.chess',channel:'release'};

  function normalize(info){
    info=info||{};
    var versionName=String(info.version||info.versionName||fallback.versionName).trim();
    var versionCode=Number(info.build||info.versionCode||fallback.versionCode);
    return Object.freeze({
      versionName:/^\d+\.\d+\.\d+$/.test(versionName)?versionName:fallback.versionName,
      versionCode:Number.isSafeInteger(versionCode)&&versionCode>0?versionCode:fallback.versionCode,
      packageName:String(info.id||info.packageName||fallback.packageName),
      channel:fallback.channel
    });
  }
  function publish(info){
    var config=normalize(info);
    window.LUNO_BUILD_CONFIG=config;
    window.LUNO_BUILD='v'+config.versionName+' \u00b7 YAPIM '+config.versionCode;
    window.lunoBuildLabel=function(prefix){return (prefix===false?'':'S\u00fcr\u00fcm ') + config.versionName+' \u00b7 Yap\u0131m '+config.versionCode;};
    try{window.dispatchEvent(new CustomEvent('luno:build-info',{detail:config}));}catch(error){}
    return config;
  }

  publish(fallback);
  try{
    var appPlugin=window.Capacitor&&Capacitor.Plugins&&Capacitor.Plugins.App;
    if(appPlugin&&typeof appPlugin.getInfo==='function'){
      Promise.resolve(appPlugin.getInfo()).then(publish).catch(function(){});
    }
  }catch(error){}
})();
