(function(){
  'use strict';

  var guestPromise=null;
  var requestSequence=0;
  var googleResumeUid='';
  var appCheckTokenPromise=null;
  var appCheckCachedToken='';
  var appCheckCachedAt=0;
  var appCheckBackoffUntil=0;
  var appCheckLastFailure='';
  var legalConsentPrompt=null;
  var diagnosticBuffer=[];
  var DEFAULT_API_BASE='https://europe-west1-luno-chess.cloudfunctions.net/lunoApi';
  // Production never downgrades an API call to Firebase Auth-only. A missing
  // or invalid App Check token must fail closed at the Functions boundary.
  var AUTH_FALLBACK_PATHS={};
  window.LUNO_SECURE_API_BASE=window.LUNO_SECURE_API_BASE||DEFAULT_API_BASE;

  function diagnostic(action,state,details){
    var entry={at:new Date().toISOString(),action:String(action||'UNKNOWN'),state:String(state||'unknown')};
    details=details&&typeof details==='object'?details:{};
    Object.keys(details).forEach(function(key){
      var value=details[key];
      if(value===undefined||value===null||key==='token'||key==='appCheckToken'||key==='authorization')return;
      entry[key]=typeof value==='string'?value.slice(0,180):value;
    });
    diagnosticBuffer.push(entry);
    if(diagnosticBuffer.length>80)diagnosticBuffer.shift();
    window.LUNO_NETWORK_DIAGNOSTICS=diagnosticBuffer;
    try{console.info('[LUNO_NET]',JSON.stringify(entry));}catch(e){}
  }
  function operationName(path){return String(path||'').replace(/^\/+/, '').replace(/([a-z])([A-Z])/g,'$1_$2').replace(/\W+/g,'_').toUpperCase()||'UNKNOWN';}
  function errorCode(error){return String(error&&error.code||error&&error.message||error||'unknown');}
  function delay(milliseconds){return new Promise(function(resolve){setTimeout(resolve,milliseconds);});}

  function auth(){
    try{return window.firebase&&firebase.auth?firebase.auth():null;}catch(e){return null;}
  }
  function currentUser(){var instance=auth();return instance?instance.currentUser:null;}
  function safeText(value){
    return String(value==null?'':value).replace(/[&<>"']/g,function(character){
      return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[character];
    });
  }
  function userHasGoogle(user){
    var providers=user&&user.providerData||[];
    for(var i=0;i<providers.length;i++)if(providers[i]&&providers[i].providerId==='google.com')return true;
    return false;
  }
  function announce(message,type){
    if(typeof window.toast==='function')window.toast(message,type||'');
    else console.log(message);
  }
  function removeGate(){var gate=document.getElementById('lunoGuestGate');if(gate)gate.remove();}
  function withTimeout(promise,milliseconds){
    return new Promise(function(resolve,reject){
      var timer=setTimeout(function(){reject({code:'auth/timeout',message:'Güvenli hesap servisi zaman aşımına uğradı'});},milliseconds);
      promise.then(function(value){clearTimeout(timer);resolve(value);},function(error){clearTimeout(timer);reject(error);});
    });
  }
  function withAppCheckDeadline(promise,milliseconds){
    return new Promise(function(resolve,reject){
      var settled=false;
      var timer=setTimeout(function(){
        if(settled)return;settled=true;reject({code:'app-check-soft-timeout',message:'App Check token timed out'});
      },milliseconds);
      promise.then(function(value){if(settled)return;settled=true;clearTimeout(timer);resolve(value);},function(error){if(settled)return;settled=true;clearTimeout(timer);reject(error);});
    });
  }

  function ensureGuestSession(){
    var instance=auth();
    if(!instance)return Promise.reject({code:'auth/service-unavailable',message:'Firebase Authentication başlatılamadı'});
    if(instance.currentUser){removeGate();return Promise.resolve(instance.currentUser);}
    if(guestPromise)return guestPromise;
    if(typeof window.setLoaderText==='function')window.setLoaderText('Misafir hesabın hazırlanıyor...',84);
    guestPromise=withTimeout(instance.signInAnonymously(),20000).then(function(result){
      var user=result&&result.user||instance.currentUser;
      if(!user||!user.uid)throw {code:'auth/invalid-guest',message:'Misafir UID alınamadı'};
      removeGate();
      try{window.dispatchEvent(new CustomEvent('luno:guest-ready',{detail:{uid:user.uid}}));}catch(e){}
      guestPromise=null;
      return user;
    },function(error){guestPromise=null;throw error;});
    return guestPromise;
  }

  function friendlyGuestError(error){
    var code=String(error&&error.code||error&&error.message||error||'');
    if(code.indexOf('operation-not-allowed')>=0||code.indexOf('admin-restricted-operation')>=0||code.indexOf('ADMIN_ONLY_OPERATION')>=0)return 'Misafir hesap servisi henüz etkin değil. Firebase Anonymous Authentication ayarını kontrol et.';
    if(code.indexOf('network')>=0||code.indexOf('timeout')>=0)return 'İnternet bağlantısı kurulamadı. Bağlantını kontrol edip tekrar dene.';
    if(code.indexOf('app-check')>=0||code.indexOf('App Check')>=0)return 'Uygulama güvenlik doğrulaması tamamlanamadı. Uygulamayı kapatıp yeniden açarak tekrar dene.';
    if(code.indexOf('route-not-found')>=0||code.indexOf('http-404')>=0)return 'Oyuncu hesabı servisine ulaşılamadı. Biraz sonra tekrar dene.';
    return 'Güvenli oyuncu hesabı oluşturulamadı. İlerlemen korunmadan oyuna devam edilmeyecek.';
  }
  function showGuestBootError(error){
    try{if(typeof window.hideAppLoader==='function')window.hideAppLoader();}catch(e){}
    removeGate();
    if(typeof window.lunoStartOfflineGuest==='function'){
      window.lunoStartOfflineGuest(error);
      return;
    }
    announce(friendlyGuestError(error),'warn');
  }

  function showGoogleConflict(details){
    details=details||{};
    var existing=document.getElementById('lunoAccountConflict');if(existing)existing.remove();
    var gate=document.createElement('div');
    gate.id='lunoAccountConflict';gate.className='luno-account-gate';
    gate.setAttribute('role','dialog');gate.setAttribute('aria-modal','true');
    var blockedReason=details.hasActiveRankedMatch?'Aktif sıralı maçın tamamlanmadan hesap değiştirilemez.':
      details.hasPurchaseEntitlement?'Bu misafir hesapta satın alma bulunduğu için doğrudan geçiş kapalı.':
      details.hasProtectedProgress?'Bu misafir hesapta ilerleme bulunduğu için doğrudan geçiş kapalı.':'';
    var cloudEnabled=details.switchAllowed===true&&typeof details.onCloud==='function';
    gate.innerHTML='<div class="luno-account-panel luno-account-panel-wide">'+
      '<img class="luno-account-mascot" src="assets/luno-art/luno-mascot.png" alt="Luno">'+
      '<div class="luno-account-kicker">HESAP ÇAKIŞMASI</div>'+
      '<h2>Bu Google hesabında bir Luno profili var</h2>'+
      '<p>Otomatik birleştirme yapılmadı. Mevcut misafir ilerlemen ve UID kimliğin değiştirilmedi.</p>'+
      '<button type="button" class="luno-account-primary" id="lunoKeepGuest">MİSAFİRLE DEVAM ET</button>'+
      '<button type="button" class="luno-account-secondary" id="lunoUseCloud" '+(cloudEnabled?'':'disabled aria-disabled="true"')+'>MEVCUT BULUT HESABIMLA DEVAM ET</button>'+
      '<button type="button" class="luno-account-secondary" id="lunoConflictSupport">DESTEK İLE BİRLEŞTİR</button>'+
      '<div class="luno-account-foot" id="lunoConflictFoot">'+safeText(blockedReason||(details.supportCode?'Destek kodun: '+details.supportCode:'İki hesabın ekonomi verileri kendiliğinden birleştirilmez.'))+'</div>'+
    '</div>';
    document.body.appendChild(gate);
    document.getElementById('lunoKeepGuest').onclick=function(){gate.remove();if(typeof details.onCancel==='function')details.onCancel();};
    document.getElementById('lunoUseCloud').onclick=function(){
      if(!cloudEnabled){announce(blockedReason||'Güvenli hesap geçişi şu anda kullanılamıyor.');return;}
      details.onCloud();
    };
    document.getElementById('lunoConflictSupport').onclick=function(){
      var foot=document.getElementById('lunoConflictFoot');
      var code=details.supportCode||'hazırlanıyor';
      if(foot)foot.textContent='Destek kodun: '+code+'. Misafir hesabın bu kayıtla korunuyor.';
      announce('Destek kodun: '+code,'neon');
    };
  }

  function newRequestId(user,label){
    var random='';
    try{if(window.crypto&&typeof window.crypto.randomUUID==='function')random=window.crypto.randomUUID();}catch(e){}
    if(!random)random=Date.now().toString(36)+'-'+(++requestSequence).toString(36)+'-'+Math.random().toString(36).slice(2,10);
    return String(label||'op')+'-'+String(user&&user.uid||'guest').slice(0,32)+'-'+random;
  }
  function nativeAppCheckPlugin(){
    try{return window.Capacitor&&Capacitor.Plugins&&Capacitor.Plugins.LunoAppCheck||null;}catch(e){return null;}
  }
  function waitForNativeAppCheckPlugin(timeoutMs){
    var started=Date.now(),timeout=Math.max(0,Number(timeoutMs)||0);
    return new Promise(function(resolve,reject){
      function probe(){
        var plugin=nativeAppCheckPlugin();
        if(plugin&&typeof plugin.getToken==='function'){resolve(plugin);return;}
        if(Date.now()-started>=timeout){reject(new Error('app-check-bridge-unavailable'));return;}
        setTimeout(probe,100);
      }
      probe();
    });
  }
  function getAppCheckToken(forceRefresh){
    if(forceRefresh){appCheckCachedToken='';appCheckCachedAt=0;}
    if(!forceRefresh&&appCheckCachedToken&&Date.now()-appCheckCachedAt<45*60*1000)return Promise.resolve(appCheckCachedToken);
    if(appCheckTokenPromise)return appCheckTokenPromise;
    var started=Date.now();
    var immediatePlugin=nativeAppCheckPlugin();
    diagnostic('APP_CHECK','bridge_wait',{forceRefresh:forceRefresh===true});
    var bridgePromise=immediatePlugin&&typeof immediatePlugin.getToken==='function'?Promise.resolve(immediatePlugin):waitForNativeAppCheckPlugin(2000);
    appCheckTokenPromise=bridgePromise.then(function(plugin){
      diagnostic('APP_CHECK','token_request',{bridge:'ready',forceRefresh:forceRefresh===true});
      return withAppCheckDeadline(Promise.resolve(plugin.getToken({forceRefresh:forceRefresh===true})),8000);
    }).then(function(result){
      var token=result&&result.token;
      if(!token)throw new Error('app-check-empty-token');
      appCheckCachedToken=token;appCheckCachedAt=Date.now();
      diagnostic('APP_CHECK','ready',{latencyMs:Date.now()-started});
      appCheckTokenPromise=null;
      return token;
    }).catch(function(error){
      diagnostic('APP_CHECK','failed',{code:errorCode(error),latencyMs:Date.now()-started});
      appCheckTokenPromise=null;throw error;
    });
    return appCheckTokenPromise;
  }
  function getAppCheckCredential(path,forceRefresh){
    return getAppCheckToken(forceRefresh).then(function(token){
      appCheckBackoffUntil=0;appCheckLastFailure='';
      return {token:token,mode:'verified'};
    }).catch(function(error){
      appCheckLastFailure=errorCode(error);appCheckBackoffUntil=Date.now()+30000;
      diagnostic('APP_CHECK','failed',{path:path,code:appCheckLastFailure,backoffMs:30000});
      throw error;
    });
  }
  function secureApi(path,payload,stableRequestId){
    var base=String(window.LUNO_SECURE_API_BASE||'').replace(/\/$/,'');
    if(!base)return Promise.reject(new Error('secure-api-not-configured'));
    var initialUser=currentUser();
    if(!initialUser||!initialUser.uid)return ensureGuestSession().then(function(){return secureApi(path,payload,stableRequestId);});
    var requestId=stableRequestId||newRequestId(initialUser,path.replace(/\W+/g,'_'));
    var action=operationName(path),started=Date.now(),attemptCount=0;
    var retries={auth:1,appCheck:2,network:2};
    diagnostic(action,'request_start',{requestId:requestId,uid:String(initialUser.uid).slice(0,10),region:'europe-west1'});
    function attempt(forceAuth,forceAppCheck){
      attemptCount++;
      var user=currentUser();
      if(!user||!user.uid)return ensureGuestSession().then(function(){return attempt(true,forceAppCheck);});
      var idTokenPromise=forceAuth===true?user.getIdToken(true):user.getIdToken(false);
      diagnostic(action,'credentials',{requestId:requestId,attempt:attemptCount,appCheck:forceAppCheck?'refresh':'cached'});
      return Promise.all([idTokenPromise,getAppCheckCredential(path,forceAppCheck===true)]).then(function(tokens){
        var token=tokens[0],appCheckCredential=tokens[1],appCheckToken=appCheckCredential.token;
        var controller=typeof AbortController==='function'?new AbortController():null;
        var timer=controller?setTimeout(function(){controller.abort();},20000):null;
        var headers={'Authorization':'Bearer '+token,'Content-Type':'application/json','X-Luno-Request-Id':requestId};
        if(appCheckToken)headers['X-Firebase-AppCheck']=appCheckToken;
        diagnostic(action,'attestation',{requestId:requestId,attempt:attemptCount,mode:appCheckCredential.mode,reason:appCheckCredential.reason||''});
        return fetch(base+path,{
          method:'POST',
          headers:headers,
          body:JSON.stringify(payload||{}),
          signal:controller?controller.signal:undefined
        }).then(function(response){if(timer)clearTimeout(timer);return response;},function(error){if(timer)clearTimeout(timer);throw error;});
      }).then(function(response){
        return response.json().catch(function(){return {};}).then(function(body){
          if(response.ok&&body.ok!==false){
            diagnostic(action,'success',{requestId:requestId,status:response.status,latencyMs:Date.now()-started,attempts:attemptCount,schema:body&&typeof body==='object'?'object':typeof body});
            return body;
          }
          var code=String(body.error||('http-'+response.status));
          if(retries.appCheck>0&&(code.indexOf('app-check')>=0||code.indexOf('invalid-app')>=0)){
            var appDelay=(4-retries.appCheck)*700;retries.appCheck--;
            diagnostic(action,'retry_app_check',{requestId:requestId,code:code,delayMs:appDelay});
            return delay(appDelay).then(function(){return attempt(false,true);});
          }
          if(retries.auth>0&&(code.indexOf('auth')>=0||code.indexOf('token')>=0)){retries.auth--;return attempt(true,false);}
          throw new Error(code);
        });
      }).catch(function(error){
        var code=errorCode(error);
        if(retries.appCheck>0&&(code.indexOf('app-check')>=0||code.indexOf('App Check')>=0)){
          var appDelay=(4-retries.appCheck)*700;retries.appCheck--;
          diagnostic(action,'retry_app_check',{requestId:requestId,code:code,delayMs:appDelay});
          return delay(appDelay).then(function(){return attempt(false,true);});
        }
        if(retries.auth>0&&(code.indexOf('auth')>=0||code.indexOf('token')>=0)){retries.auth--;return attempt(true,false);}
        if(retries.network>0&&(code.indexOf('network')>=0||code.indexOf('timeout')>=0||code.indexOf('AbortError')>=0||code.indexOf('Failed to fetch')>=0)){
          retries.network--;
          diagnostic(action,'retry_network',{requestId:requestId,code:code,retriesLeft:retries.network});
          return delay(650).then(function(){return attempt(false,false);});
        }
        diagnostic(action,'failed',{requestId:requestId,code:code,latencyMs:Date.now()-started,attempts:attemptCount});
        throw error;
      });
    }
    return attempt(false,false);
  }

  function currentLegalConsent(){
    var value=window.LUNO_LEGAL_CONSENT;
    return value&&typeof value==='object'?value:null;
  }
  function closeLegalConsentPrompt(gate){
    if(gate&&gate.parentNode)gate.parentNode.removeChild(gate);
    legalConsentPrompt=null;
  }
  function showLegalConsentPrompt(){
    if(legalConsentPrompt)return legalConsentPrompt;
    legalConsentPrompt=new Promise(function(resolve,reject){
      var existing=document.getElementById('lunoLegalConsent');if(existing)existing.remove();
      var gate=document.createElement('div');gate.id='lunoLegalConsent';gate.className='luno-account-gate luno-legal-gate';
      gate.setAttribute('role','dialog');gate.setAttribute('aria-modal','true');gate.setAttribute('aria-labelledby','lunoLegalTitle');
      gate.innerHTML='<div class="luno-account-panel luno-legal-panel">'+
        '<img class="luno-account-mascot" src="assets/luno-art/menu-luno-idle-v10-mobile.webp" alt="Luno">'+
        '<div class="luno-account-kicker">LUNO TOPLULU&#286;U</div>'+
        '<h2 id="lunoLegalTitle">Mesajla&#351;maya ba&#351;lamadan &#246;nce</h2>'+
        '<p>Oyuncular&#305;n g&#252;venli&#287;i i&#231;in g&#252;ncel ko&#351;ullar&#305; okuyup kabul etmelisin. Oyunun di&#287;er b&#246;l&#252;mlerini kullanmaya devam edebilirsin.</p>'+
        '<div class="luno-legal-links"><a href="terms.html" target="_blank" rel="noopener">KULLANIM &#350;ARTLARI</a><a href="privacy.html" target="_blank" rel="noopener">G&#304;ZL&#304;L&#304;K POL&#304;T&#304;KASI</a></div>'+
        '<button type="button" class="luno-legal-check" id="lunoLegalCheck" role="checkbox" aria-checked="false"><span class="luno-legal-checkmark" aria-hidden="true">&#10003;</span><span>Her iki metni okudum ve kabul ediyorum.</span></button>'+
        '<div class="luno-legal-status" id="lunoLegalStatus" aria-live="polite"></div>'+
        '<button type="button" class="luno-account-primary" id="lunoLegalAccept" disabled>KABUL ET</button>'+
        '<button type="button" class="luno-account-secondary" id="lunoLegalLater">&#350;&#304;MD&#304; DE&#286;&#304;L</button>'+
      '</div>';
      document.body.appendChild(gate);
      var check=document.getElementById('lunoLegalCheck'),accept=document.getElementById('lunoLegalAccept');
      var later=document.getElementById('lunoLegalLater'),status=document.getElementById('lunoLegalStatus'),checked=false;
      check.onclick=function(){
        checked=!checked;check.classList.toggle('is-checked',checked);check.setAttribute('aria-checked',checked?'true':'false');accept.disabled=!checked;
      };
      later.onclick=function(){
        closeLegalConsentPrompt(gate);reject(new Error('legal-consent-cancelled'));
      };
      accept.onclick=function(){
        if(!checked||accept.disabled)return;
        accept.disabled=true;check.disabled=true;later.disabled=true;status.textContent='Onay g\u00fcvenli bi\u00e7imde kaydediliyor...';
        secureApi('/acceptLegalTerms',{}).then(function(result){
          applyAuthoritativeState(result&&result.state);
          var consent=currentLegalConsent();
          if(!consent||consent.accepted!==true)throw new Error('legal-consent-write-failed');
          closeLegalConsentPrompt(gate);resolve(consent);
        }).catch(function(){
          check.disabled=false;later.disabled=false;accept.disabled=!checked;
          status.textContent='Onay kaydedilemedi. Ba\u011flant\u0131n\u0131 kontrol edip yeniden dene.';
        });
      };
      setTimeout(function(){try{check.focus();}catch(e){}},0);
    });
    return legalConsentPrompt;
  }
  function ensureLegalConsent(){
    var consent=currentLegalConsent();
    var ready=consent?Promise.resolve(consent):refreshAuthoritativeState().then(function(){return currentLegalConsent();});
    return ready.then(function(value){return value&&value.accepted===true?value:showLegalConsentPrompt();});
  }
  function sendDirectMessageSecure(payload){
    return ensureLegalConsent().then(function(){return secureApi('/sendDirectMessage',payload);}).catch(function(error){
      if(String(error&&error.message||error).indexOf('legal-consent-required')<0)throw error;
      window.LUNO_LEGAL_CONSENT={accepted:false};
      return showLegalConsentPrompt().then(function(){return secureApi('/sendDirectMessage',payload);});
    });
  }

  function prepareGoogleLinkSecure(){
    var user=currentUser();
    if(!user||!user.uid)return Promise.reject(new Error('auth-required'));
    var id=newRequestId(user,'google-link-prepare');
    return secureApi('/prepareGoogleLink',{},id);
  }
  function completeGoogleLinkSecure(attemptId){
    var user=currentUser();
    if(!user||!user.uid)return Promise.reject(new Error('auth-required'));
    var payload=attemptId?{attemptId:attemptId}:{};
    var id='google-link-complete-'+user.uid.slice(0,32)+'-'+(attemptId||'resume');
    return secureApi('/completeGoogleLink',payload,id).then(function(result){
      applyAuthoritativeState(result&&result.state);
      try{window.dispatchEvent(new CustomEvent('luno:account-updated',{detail:{uid:user.uid,googleLinked:true}}));}catch(e){}
      return result;
    });
  }
  function recordGoogleLinkConflictSecure(attemptId,reason){
    var user=currentUser();
    if(!user||!user.uid)return Promise.reject(new Error('auth-required'));
    var payload={reason:reason||'credential-already-in-use'};
    if(attemptId)payload.attemptId=attemptId;
    var id='google-link-conflict-'+user.uid.slice(0,32)+'-'+(attemptId||newRequestId(user,'fallback'));
    return secureApi('/recordGoogleLinkConflict',payload,id);
  }
  function resumeGoogleLinkSecure(user){
    if(!user||!user.uid||!userHasGoogle(user)||googleResumeUid===user.uid)return Promise.resolve(null);
    googleResumeUid=user.uid;
    return completeGoogleLinkSecure('').catch(function(error){
      googleResumeUid='';
      setTimeout(function(){var latest=currentUser();if(latest&&latest.uid===user.uid)resumeGoogleLinkSecure(latest);},10000);
      throw error;
    });
  }

  function reserveUsernameSecure(username,uid,callback){
    var user=currentUser();
    if(!user||!user.uid||user.uid!==uid){callback(false,'service-unavailable');return;}
    secureApi('/createGuestPlayer',{username:username}).then(function(result){
      callback(result&&result.ok===true,result&&result.ok===true?'reserved':'service-unavailable');
    }).catch(function(error){
      var code=String(error&&error.message||error);
      callback(false,code.indexOf('username-taken')>=0?'taken':'service-unavailable');
    });
  }

  var usernameChangeBusy=false;
  function usernameChangeReason(error){
    var code=String(error&&error.message||error||'');
    if(code.indexOf('username-taken')>=0)return 'taken';
    if(code.indexOf('username-not-allowed')>=0||code.indexOf('invalid-username')>=0)return 'not-allowed';
    if(code.indexOf('insufficient-balance')>=0)return 'insufficient-balance';
    return 'service-unavailable';
  }
  function openUsernameChangeSecure(){
    var user=currentUser(),player=window.PLAYER||{},profile=player.profile||{};
    if(!user||!user.uid){announce('Güvenli hesap bağlantısı hazır değil.','warn');return;}
    if(typeof window.askUsername!=='function'){announce('Kullanıcı adı ekranı açılamadı.','warn');return;}
    var current=String(profile.username||profile.name||'').normalize('NFKC').trim().toLowerCase();
    var changes=Math.max(0,Number(player.usernameChanges||profile.usernameChanges)||0);
    var cost=changes===0?0:5000;
    if(cost>0&&Number(player.gold||0)<cost){announce('Bu değişiklik için 5.000 altın gerekiyor.','warn');return;}
    var subtitle=cost===0?'İlk değişiklik ücretsiz. Yeni adın bütün Luno profilinde güncellenir.':'Değişiklik ücreti: 5.000 altın. Ücret yalnız sunucu onaylarsa düşer.';
    window.askUsername(user.uid,current,function(username){
      try{if(typeof window.updateTopbarName==='function')window.updateTopbarName();}catch(e){}
      try{if(typeof window.updateCurrencyDisplay==='function')window.updateCurrencyDisplay();}catch(e){}
      try{if(typeof window.sndTrophyGain==='function')window.sndTrophyGain();}catch(e){}
      announce('Kullanıcı adın @'+username+' olarak değişti!','neon');
      try{if(typeof window.editProfile==='function')window.editProfile();}catch(e){}
    },subtitle,function(username,uid,callback){
      if(username===current){callback(false,'same');return;}
      if(usernameChangeBusy){callback(false,'service-unavailable');return;}
      usernameChangeBusy=true;
      secureApi('/changeUsername',{username:username}).then(function(result){
        applyAuthoritativeState(result&&result.state);
        usernameChangeBusy=false;
        callback(result&&result.ok===true,result&&result.ok===true?'changed':'service-unavailable');
      }).catch(function(error){
        usernameChangeBusy=false;
        refreshAuthoritativeState().catch(function(){});
        callback(false,usernameChangeReason(error));
      });
    });
  }

  var preferenceSync=null;
  function syncSafePreferences(profile,preferences){
    if(preferenceSync)return preferenceSync;
    preferenceSync=secureApi('/updateProfile',profile||{}).then(function(){
      return secureApi('/updatePreferences',preferences||{});
    }).then(function(result){
      applyAuthoritativeState(result&&result.state);
      preferenceSync=null;return result;
    },function(error){preferenceSync=null;refreshAuthoritativeState().catch(function(){});throw error;});
    return preferenceSync;
  }

  function applyAuthoritativeState(state){
    if(!state||!window.PLAYER)return false;
    var player=window.PLAYER,inventory=state.inventory||{};
    player.gold=Number(state.gold)||0;
    player.gems=Number(state.gems)||0;
    player.trophies=Number(state.trophies)||0;
    player.arenaIdx=Number(state.arenaIdx)||0;
    if(!player.profile)player.profile={};
    player.profile.xp=Number(state.xp)||0;
    player.profile.lvl=Math.max(1,Number(state.lvl)||1);
    if(state.profile){
      player.profile.name=state.profile.name||state.profile.username||player.profile.name||'';
      player.profile.username=state.profile.username||state.profile.name||player.profile.name||'';
      player.profile.usernameChanges=Math.max(0,Number(state.profile.usernameChanges)||0);
      player.profile.usernameChangedAt=Math.max(0,Number(state.profile.usernameChangedAt)||0);
      player.usernameChanges=player.profile.usernameChanges;
      player.profile.country=state.profile.country||'TR';
      player.profile.avatar=state.profile.avatar||'#e8b840';
      player.profile.avatarEmoji=state.profile.avatarEmoji||'&#9818;';
      player.profile.bio=state.profile.bio||'';
      player.profile.frame=state.profile.frame||'none';
      player.profile.bioFrame=state.profile.bioFrame||'default';
      player.dmFriendsOnly=state.profile.dmFriendsOnly===true;
    }
    if(Array.isArray(state.deck))player.deck=state.deck.slice();
    if(Array.isArray(state.emojiLoadout))player.emojiLoadout=state.emojiLoadout.slice();
    if(state.unlockedCards)player.unlockedCards=state.unlockedCards;
    if(state.cardLevel)player.cardLevel=state.cardLevel;
    player.ownedSkins=Array.isArray(inventory.ownedSkins)?inventory.ownedSkins.slice():['classic'];
    player.ownedEmojis=Array.isArray(inventory.ownedEmojis)?inventory.ownedEmojis.slice():[];
    player.ownedFrames=Array.isArray(inventory.ownedFrames)?inventory.ownedFrames.slice():['none'];
    player.ownedBioFrames=Array.isArray(inventory.ownedBioFrames)?inventory.ownedBioFrames.slice():['default'];
    player.ownedCostumes=Array.isArray(inventory.ownedCostumes)?inventory.ownedCostumes.slice():[];
    player.ownedSets=Array.isArray(inventory.ownedSets)?inventory.ownedSets.slice():['std'];
    player.activeCostumes=inventory.activeCostumes||{};
    player.activeSkin=inventory.activeSkin||'classic';
    player.activePieceSet=inventory.activePieceSet||'std';
    player.bioFrameShards=inventory.bioFrameShards||{};
    player.frameShards=inventory.frameShards||{};
    player.skinPieces=inventory.skinPieces||{};
    player.emojiPieces=inventory.emojiPieces||{};
    player.lastDailyReward=Number(inventory.lastDailyReward)||0;
    player.dailyStreak=Number(inventory.dailyStreak)||0;
    if(state.missions)player.missions=state.missions;
    if(state.passMissions)player.passMissions=state.passMissions;
    if(state.season)player.season=state.season;
    if(state.achievementsClaimed)player.achievementsClaimed=state.achievementsClaimed;
    if(state.stats)player.stats=state.stats;
    if(state.passState&&window.PASS_STATE){
      PASS_STATE.seasonKey=state.passState.seasonKey||'';
      PASS_STATE.seasonStartedAt=Number(state.passState.seasonStartedAt)||0;
      PASS_STATE.season=Number(state.passState.season)||1;
      PASS_STATE.level=Number(state.passState.level)||0;
      PASS_STATE.xp=Number(state.passState.xp)||0;
      PASS_STATE.premium=state.passState.premium===true;
      PASS_STATE.claimed=state.passState.claimed||{free:{},premium:{}};
    }
    window.LUNO_SERVER_ECONOMY=state.economy||null;
    window.LUNO_SERVER_REWARDS=state.rewards||null;
    window.LUNO_LEGAL_CONSENT=state.legalConsent&&typeof state.legalConsent==='object'?state.legalConsent:null;
    try{if(typeof window.updateCurrencyDisplay==='function')window.updateCurrencyDisplay();}catch(e){}
    try{if(typeof window.refreshMenuUI==='function')window.refreshMenuUI();}catch(e){}
    try{if(typeof window.updatePassMissBadge==='function')window.updatePassMissBadge();}catch(e){}
    return true;
  }

  var stateRefreshPromise=null;
  function refreshAuthoritativeState(){
    if(stateRefreshPromise)return stateRefreshPromise;
    stateRefreshPromise=secureApi('/getPlayerState',{}).then(function(result){
      applyAuthoritativeState(result&&result.state);
      stateRefreshPromise=null;
      return result&&result.state;
    },function(error){stateRefreshPromise=null;throw error;});
    return stateRefreshPromise;
  }

  var dailyClaimPromise=null;
  function canClaimDailyRewardSecure(){
    var economy=window.LUNO_SERVER_ECONOMY;
    return economy&&economy.daily?economy.daily.canClaim===true:true;
  }
  function showSecureDailyReward(result){
    var reward=result&&result.reward||{},state=result&&result.state||{},economy=state.economy||{};
    var streak=Math.max(1,Number(economy.daily&&economy.daily.streak)||1);
    var day=((streak-1)%7)+1;
    var label=day===7?'G&Uuml;N 7 - MEGA':'G&Uuml;N '+day;
    var gold=Number(reward.gold)||0,gems=Number(reward.gems)||0;
    if(typeof window.showMatchOverlay!=='function')return;
    var html='<div class="mm-actions-wrap">'+
      '<div class="mm-proposal" style="background:linear-gradient(165deg,rgba(80,60,160,.6),rgba(40,20,80,.85));border-color:rgba(227,180,73,.7)">'+
        '<div class="mm-prop-icon">&#127873;</div><div class="mm-prop-title">'+label+'</div>'+
        '<div class="mm-prop-name">G&Uuml;NL&Uuml;K &Ouml;D&Uuml;L</div><div class="mm-prop-desc" style="font-size:14px">'+
          '<span style="color:#e3b449;font-weight:800">&#129689; +'+gold.toLocaleString('tr-TR')+' Alt&#305;n</span>'+
          (gems>0?'<br><span style="color:#80c8ff;font-weight:800">&#128142; +'+gems+' Elmas</span>':'')+
          '<br><br><span style="font-size:11px;font-style:italic;color:rgba(220,200,255,.7)">7 g&uuml;nl&uuml;k seri: '+streak+'/7</span>'+
        '</div></div><button class="mm-action-close" onclick="closeMatchMenu();if(document.querySelector(\'#overlay.show\'))openShop();">HAR&#304;KA!</button></div>';
    window.showMatchOverlay(html);
  }
  function claimDailyRewardSecure(){
    if(dailyClaimPromise)return dailyClaimPromise;
    try{if(typeof window.sndUiClick==='function')window.sndUiClick();}catch(e){}
    dailyClaimPromise=secureApi('/claimDailyReward',{}).then(function(result){
      applyAuthoritativeState(result&&result.state);
      if(!result||result.granted!==true){announce('Bug\u00fcn\u00fcn \u00f6d\u00fcl\u00fcn\u00fc zaten ald\u0131n.');return result;}
      try{if(typeof window.sndTrophyGain==='function')window.sndTrophyGain();}catch(e){}
      showSecureDailyReward(result);
      return result;
    }).catch(function(error){
      refreshAuthoritativeState().catch(function(){});
      announce('\u00d6d\u00fcl servisine ba\u011flan\u0131lamad\u0131. Bakiyen de\u011fi\u015ftirilmedi.');
      return null;
    }).finally(function(){dailyClaimPromise=null;});
    return dailyClaimPromise;
  }

  var rewardClaimLocks={};
  function rewardSummary(reward){
    var parts=[];
    if(reward&&reward.gold)parts.push('+'+Number(reward.gold).toLocaleString('tr-TR')+' alt\u0131n');
    if(reward&&reward.gems)parts.push('+'+Number(reward.gems).toLocaleString('tr-TR')+' elmas');
    return parts.join(' ve ');
  }
  function secureRewardClaim(key,path,payload,onSuccess){
    if(rewardClaimLocks[key])return rewardClaimLocks[key];
    rewardClaimLocks[key]=secureApi(path,payload).then(function(result){
      applyAuthoritativeState(result&&result.state);
      if(result&&result.granted===true){
        try{if(typeof window.sndTrophyGain==='function')window.sndTrophyGain();}catch(e){}
        announce((rewardSummary(result.reward)||'\u00d6d\u00fcl')+' hesab\u0131na eklendi.','neon');
      }else announce('\u00d6d\u00fcl daha \u00f6nce al\u0131nd\u0131.');
      if(onSuccess)onSuccess(result);
      return result;
    }).catch(function(error){
      var code=String(error&&error.message||error);
      if(code.indexOf('not-complete')>=0||code.indexOf('locked')>=0)announce('Bu \u00f6d\u00fcl hen\u00fcz haz\u0131r de\u011fil.');
      else if(code.indexOf('premium-required')>=0)announce('Bu \u00f6d\u00fcl i\u00e7in Premium Pass gerekiyor.');
      else if(code.indexOf('not-configured')>=0)announce('Bu \u00f6d\u00fcl sunucu katalo\u011funa haz\u0131rlan\u0131yor.');
      else announce('\u00d6d\u00fcl i\u015flemi tamamlanamad\u0131. Bakiyen de\u011fi\u015ftirilmedi.');
      refreshAuthoritativeState().catch(function(){});
      return null;
    }).finally(function(){delete rewardClaimLocks[key];});
    return rewardClaimLocks[key];
  }
  function claimMissionRewardSecure(category,missionId){
    return secureRewardClaim('mission:'+category+':'+missionId,'/claimMissionReward',{category:category,missionId:missionId},function(){
      try{if(typeof window.openMissions==='function')window.openMissions();}catch(e){}
    });
  }
  function claimAchievementRewardSecure(achievementId){
    return secureRewardClaim('achievement:'+achievementId,'/claimAchievementReward',{achievementId:achievementId},function(){
      try{if(typeof window.openAchievements==='function')window.openAchievements();}catch(e){}
    });
  }
  function claimPassRewardSecure(level,track){
    return secureRewardClaim('pass:'+track+':'+level,'/claimPassReward',{level:Number(level),track:track},function(){
      try{if(typeof window.openLunoPass==='function')window.openLunoPass();}catch(e){}
    });
  }
  function claimSeasonRewardSecure(){
    return secureRewardClaim('season','/claimSeasonReward',{},function(){
      try{if(typeof window.openSeasonScreen==='function')window.openSeasonScreen();}catch(e){}
    });
  }
  function claimOnboardingRewardSecure(){
    return secureRewardClaim('onboarding:v1','/claimOnboardingReward',{},function(result){
      if(result&&result.granted===true)setTimeout(function(){announce('İlk zafer bonusu: +500 altın!','neon');},350);
    });
  }
  function claimSocialVisitRewardSecure(missionId){
    var mission=null,list=window.SPECIAL_PASS_MISSIONS||[];
    for(var index=0;index<list.length;index++)if(list[index]&&list[index].id===missionId){mission=list[index];break;}
    if(!mission){announce('Bu ziyaret ödülü bulunamadı.','warn');return null;}
    try{window.open(mission.url,'_blank','noopener');}catch(e){}
    return secureRewardClaim('social:'+missionId,'/claimSocialVisitReward',{missionId:missionId},function(){
      try{if(typeof window.updatePassMissBadge==='function')window.updatePassMissBadge();if(typeof window.openPassMissions==='function')window.openPassMissions();}catch(e){}
    });
  }

  var softPurchaseLocks={},chestLocks={},upgradeLocks={};
  function findItem(list,id){
    if(!Array.isArray(list))return null;
    for(var i=0;i<list.length;i++)if(list[i]&&list[i].id===id)return list[i];
    return null;
  }
  function confirmLunoPurchase(info,action){
    if(typeof window.lunoReleaseConfirm==='function')window.lunoReleaseConfirm(info,action);
    else action();
  }
  function purchaseError(error){
    var code=String(error&&error.message||error);
    if(code.indexOf('insufficient-balance')>=0)announce('Sunucu bakiyen bu i\u015flem i\u00e7in yeterli de\u011fil.');
    else if(code.indexOf('already-owned')>=0)announce('Bu \u00f6\u011fe zaten hesab\u0131nda.','neon');
    else if(code.indexOf('arena-locked')>=0)announce('Bu y\u00fckseltme i\u00e7in gereken arenaya hen\u00fcz ula\u015fmad\u0131n.');
    else if(code.indexOf('card-locked')>=0||code.indexOf('upgrade-sequence')>=0)announce('Kart y\u00fckseltme s\u0131ras\u0131 ge\u00e7ersiz.');
    else if(code.indexOf('rate-limited')>=0)announce('\u00c7ok h\u0131zl\u0131 i\u015flem yap\u0131ld\u0131. Biraz bekleyip tekrar dene.');
    else announce('G\u00fcvenli sat\u0131n alma tamamlanamad\u0131. Bakiyen de\u011fi\u015ftirilmedi.');
    refreshAuthoritativeState().catch(function(){});
  }
  function purchaseSoftItemSecure(itemId,onSuccess){
    if(softPurchaseLocks[itemId])return softPurchaseLocks[itemId];
    softPurchaseLocks[itemId]=secureApi('/purchaseSoftItem',{itemId:itemId}).then(function(result){
      applyAuthoritativeState(result&&result.state);
      try{if(typeof window.sndTrophyGain==='function')window.sndTrophyGain();}catch(e){}
      announce(result&&result.purchased===true?'Sat\u0131n alma hesab\u0131na eklendi.':'\u00d6\u011fe zaten hesab\u0131nda.','neon');
      if(onSuccess)onSuccess(result);
      return result;
    }).catch(function(error){purchaseError(error);return null;}).finally(function(){delete softPurchaseLocks[itemId];});
    return softPurchaseLocks[itemId];
  }
  function refreshShop(){try{if(document.querySelector('#overlay.show')&&typeof window.openShop==='function')window.openShop();}catch(e){}}
  function buySkinSecure(id){
    var item=findItem(window.PAWN_SKINS,id);if(!item)return;
    if((PLAYER.ownedSkins||[]).indexOf(id)>=0){announce('Bu skin zaten sende.');return;}
    var price=typeof window.skinPrice==='function'?skinPrice(item.rarity):{cur:'gold',amt:0};
    confirmLunoPurchase({asset:item.img||'assets/luno-art/luno-mascot.png',kicker:'SKIN ONAYI',title:item.name,message:'Skin koleksiyonuna kal\u0131c\u0131 olarak eklenecek.',price:Number(price.amt).toLocaleString('tr-TR')+' '+(price.cur==='gem'?'ELMAS':'ALTIN'),ok:'SATIN AL'},function(){purchaseSoftItemSecure('skin:'+id,refreshShop);});
  }
  function buyEmojiSecure(id){
    var item=findItem(window.EMOJI_LIST,id);if(!item)return;
    if((PLAYER.ownedEmojis||[]).indexOf(id)>=0){announce('Bu emoji zaten sende.');return;}
    var prices={common:500,rare:1500,legendary:4000,mythic:10000},price=prices[item.rarity]||1000;
    confirmLunoPurchase({asset:item.anim||item.img||'assets/luno-art/luno-mascot.png',kicker:'EMOJ\u0130 ONAYI',title:item.name,message:'Emoji koleksiyonuna kal\u0131c\u0131 olarak eklenecek.',price:price.toLocaleString('tr-TR')+' ALTIN',ok:'SATIN AL'},function(){purchaseSoftItemSecure('emoji:'+id,refreshShop);});
  }
  function buyCostumeSecure(id){
    var found=typeof window.findCostume==='function'?findCostume(id):null;if(!found)return;
    if(typeof window.isCostumeOwned==='function'&&isCostumeOwned(id)){if(typeof window.selectCostume==='function')selectCostume(found.set.type,id);return;}
    var amount=Number(found.item.gem||found.item.gold||0),currency=found.item.gem?'ELMAS':'ALTIN';
    confirmLunoPurchase({asset:'assets/luno-art/luno-mascot.png',kicker:'TA\u015e KOST\u00dcM\u00dc',title:found.item.name,message:'Kost\u00fcm koleksiyonuna eklenecek ve ilgili ta\u015fa giydirilecek.',price:amount.toLocaleString('tr-TR')+' '+currency,ok:'SATIN AL'},function(){purchaseSoftItemSecure('costume:'+id,function(){try{if(typeof window.openCostumes==='function')window.openCostumes();}catch(e){}});});
  }
  function buyCostumePackSecure(){
    confirmLunoPurchase({asset:'assets/luno-art/luno-mascot.png',kicker:'TAM KOLEKS\u0130YON',title:'T\u00fcm Ta\u015f Kost\u00fcmleri',message:'Sat\u0131n al\u0131nabilir t\u00fcm tekli ta\u015f kost\u00fcmleri hesab\u0131na kal\u0131c\u0131 eklenir.',price:'900 ELMAS',ok:'PAKET\u0130 AL'},function(){purchaseSoftItemSecure('costume_pack:all',function(){try{if(typeof window.openCostumes==='function')window.openCostumes();}catch(e){}});});
  }
  function pieceSetPurchase(id,name,price,currency,asset){
    confirmLunoPurchase({asset:asset||'assets/luno-art/luno-mascot.png',kicker:'TA\u015e SET\u0130',title:name,message:'Alt\u0131 ta\u015fl\u0131 tam set hesab\u0131na eklenecek ve ma\u00e7 tahtas\u0131nda etkinle\u015fecek.',price:Number(price).toLocaleString('tr-TR')+' '+currency,ok:'SATIN AL & G\u0130YD\u0130R'},function(){purchaseSoftItemSecure('piece_set:'+id,function(){try{if(document.querySelector('.cos-wrap'))openCostumes();else refreshShop();}catch(e){}});});
  }
  function buyOrEquipPieceSetSecure(id){
    var owned=(PLAYER.ownedSets||[]).indexOf(id)>=0;
    if(owned){PLAYER.activePieceSet=PLAYER.activePieceSet===id?'std':id;if(typeof window.saveUserProfile==='function')saveUserProfile();announce(PLAYER.activePieceSet===id?'Ta\u015f seti giyildi.':'Standart sete d\u00f6n\u00fcld\u00fc.','neon');try{if(document.querySelector('.cos-wrap'))openCostumes();else refreshShop();}catch(e){}return;}
    var item=typeof window.packInfo==='function'?packInfo(id):null;if(!item)return;
    var asset=window.PIECE_IMG&&PIECE_IMG[id]&&PIECE_IMG[id].W&&PIECE_IMG[id].W.K;
    pieceSetPurchase(id,item.name,item.gem,'ELMAS',asset);
  }
  function buyOrEquipOttomanSecure(){
    if((PLAYER.ownedSets||[]).indexOf('ottoman')>=0){PLAYER.activePieceSet=PLAYER.activePieceSet==='ottoman'?'std':'ottoman';if(typeof window.saveUserProfile==='function')saveUserProfile();announce(PLAYER.activePieceSet==='ottoman'?'Ottoman seti giyildi.':'Standart sete d\u00f6n\u00fcld\u00fc.','neon');try{if(document.querySelector('.cos-wrap'))openCostumes();else refreshShop();}catch(e){}return;}
    var asset=window.PIECE_IMG&&PIECE_IMG.ottoman&&PIECE_IMG.ottoman.W&&PIECE_IMG.ottoman.W.K;
    pieceSetPurchase('ottoman','Ottoman Seti',1000,'ALTIN',asset);
  }
  function buyPassSecure(){
    if(window.PASS_STATE&&PASS_STATE.premium){announce('Premium Pass zaten aktif.','neon');try{if(typeof window.closeMatchMenu==='function')closeMatchMenu();}catch(e){}return;}
    purchaseSoftItemSecure('pass:premium',function(){try{if(typeof window.closeMatchMenu==='function')closeMatchMenu();if(typeof window.openLunoPass==='function')openLunoPass();}catch(e){}});
  }
  function buyFrameSecure(id){
    var item=findItem(window.FRAME_DEFS,id);if(!item)return;
    confirmLunoPurchase({asset:'assets/luno-art/luno-mascot.png',kicker:'AVATAR \u00c7ER\u00c7EVES\u0130',title:item.name,message:'\u00c7er\u00e7eve hesab\u0131na eklenecek ve profilinde etkinle\u015fecek.',price:Number(item.price||0).toLocaleString('tr-TR')+' '+(item.cur==='gem'?'ELMAS':'ALTIN'),ok:'SATIN AL'},function(){purchaseSoftItemSecure('frame:'+id,function(){try{if(typeof window.editProfile==='function')editProfile();}catch(e){}});});
  }
  function selectProfileFrameSecure(id){
    var item=findItem(window.FRAME_DEFS,id);if(!item)return;
    if((PLAYER.ownedFrames||[]).indexOf(id)>=0||item.premiumOnly&&typeof window.isMyPremium==='function'&&isMyPremium()){
      PLAYER.profile=PLAYER.profile||{};PLAYER.profile.frame=id;
      if(typeof window.saveUserProfile==='function')saveUserProfile();
      try{if(typeof window.editProfile==='function')editProfile();if(typeof window.applyFramePreview==='function')applyFramePreview(id);}catch(e){}
      return;
    }
    if(item.shards){announce(item.name+': sand\u0131klardan par\u00e7a topla.');return;}
    buyFrameSecure(id);
  }
  function selectBioFrameSecure(id){
    var item=typeof window.getBioFrame==='function'?getBioFrame(id):null;if(!item)return;
    if(typeof window.isBioFrameOwned==='function'&&isBioFrameOwned(id)){PLAYER.profile=PLAYER.profile||{};PLAYER.profile.bioFrame=id;if(typeof window.saveUserProfile==='function')saveUserProfile();try{if(typeof window.editProfile==='function')editProfile();}catch(e){}return;}
    if(item.premiumOnly||item.shards){announce(item.premiumOnly?'Bu \u00e7er\u00e7eve Premium \u00fcyelere \u00f6zel.':'Bu \u00e7er\u00e7eve sand\u0131k par\u00e7alar\u0131yla a\u00e7\u0131l\u0131r.');return;}
    confirmLunoPurchase({asset:'assets/luno-art/luno-mascot.png',kicker:'B\u0130YO \u00c7ER\u00c7EVES\u0130',title:item.name,message:'\u00c7er\u00e7eve hesab\u0131na eklenecek ve biyografinde etkinle\u015fecek.',price:Number(item.price||0).toLocaleString('tr-TR')+' '+(item.cur==='gem'?'ELMAS':'ALTIN'),ok:'SATIN AL'},function(){purchaseSoftItemSecure('bio_frame:'+id,function(){try{if(typeof window.editProfile==='function')editProfile();}catch(e){}});});
  }
  function enrichChestRewards(rewards){
    return (rewards||[]).map(function(reward){
      var local=null;
      if(reward.type==='skin')local=findItem(window.PAWN_SKINS,reward.id);
      else if(reward.type==='emoji')local=findItem(window.EMOJI_LIST,reward.id);
      else if(reward.type==='frame_shard')local=findItem(window.FRAME_DEFS,reward.id);
      else if(reward.type==='bioframe_shard'&&typeof window.getBioFrame==='function')local=getBioFrame(reward.id);
      else if(reward.type==='card'&&window.CARDS)local=CARDS[reward.id];
      return Object.assign({},local||{},reward);
    });
  }
  function openChestSecure(chestId){
    var chest=findItem(window.CHESTS,chestId);if(!chest||chestLocks[chestId])return;
    var gem=chest.price&&chest.price.gem!=null,price=gem?chest.price.gem:chest.price.gold;
    confirmLunoPurchase({asset:'assets/luno-art/shop-chest-'+chestId+'-v3.png',kicker:'SANDIK ONAYI',title:chest.name,message:'Sand\u0131k sonucu g\u00fcvenli sunucuda \u00fcretilecek ve hesab\u0131na tek i\u015flemde eklenecek.',price:Number(price).toLocaleString('tr-TR')+' '+(gem?'ELMAS':'ALTIN'),ok:'SANDI\u011eI A\u00c7'},function(){
      var user=currentUser();if(!user){announce('G\u00fcvenli hesap oturumu haz\u0131r de\u011fil.');return;}
      var storageKey='lunoPendingChest:'+chestId,requestId='';
      try{requestId=sessionStorage.getItem(storageKey)||'';}catch(e){}
      if(!requestId){requestId=newRequestId(user,'chest_'+chestId);try{sessionStorage.setItem(storageKey,requestId);}catch(e){}}
      chestLocks[chestId]=secureApi('/openChest',{chestId:chestId},requestId).then(function(result){
        try{sessionStorage.removeItem(storageKey);}catch(e){}
        applyAuthoritativeState(result&&result.state);
        var rewards=enrichChestRewards(result&&result.rewards);
        if(typeof window.showChestOpenAnimation==='function')showChestOpenAnimation(chest,rewards);
        else announce('Sand\u0131k \u00f6d\u00fclleri hesab\u0131na eklendi.','neon');
        return result;
      }).catch(function(error){
        var code=String(error&&error.message||error);
        if(code.indexOf('insufficient-balance')>=0||code.indexOf('unknown-chest')>=0){try{sessionStorage.removeItem(storageKey);}catch(e){}}
        purchaseError(error);return null;
      }).finally(function(){delete chestLocks[chestId];});
    });
  }
  function upgradeCardSecure(family){
    var current=Math.max(1,Number(PLAYER.cardLevel&&PLAYER.cardLevel[family])||1),target=current+1,key=family+':'+target;
    if(target>3){announce('Kart zaten maksimum seviyede.');return;}
    if(upgradeLocks[key])return upgradeLocks[key];
    upgradeLocks[key]=secureApi('/upgradeCard',{family:family,targetLevel:target}).then(function(result){
      applyAuthoritativeState(result&&result.state);announce('Kart SV'+target+' seviyesine y\u00fckseltildi.','neon');
      try{if(typeof window.closeCardActionMenu==='function')closeCardActionMenu();if(typeof window.renderDeckPanel==='function')renderDeckPanel();}catch(e){}
      return result;
    }).catch(function(error){purchaseError(error);return null;}).finally(function(){delete upgradeLocks[key];});
    return upgradeLocks[key];
  }

  function requestSecureDeletion(){
    var user=currentUser();
    if(!user){announce('Güvenli hesap oturumu henüz hazır değil.');return;}
    function reauthenticateGoogle(){
      if(!userHasGoogle(user))return Promise.reject(new Error('reauth-required'));
      var nativePlatform=false;
      try{nativePlatform=!!(window.Capacitor&&typeof Capacitor.isNativePlatform==='function'&&Capacitor.isNativePlatform());}catch(e){}
      if(nativePlatform&&Capacitor.Plugins&&Capacitor.Plugins.GoogleAuth){
        var google=Capacitor.Plugins.GoogleAuth;
        var clientId='955253747543-3n1mocbscmemfqu6miliv5kujdrhn5u8.apps.googleusercontent.com';
        return Promise.resolve(google.initialize?google.initialize({clientId:clientId,scopes:['profile','email'],grantOfflineAccess:false}):null)
          .catch(function(){})
          .then(function(){return google.signIn();})
          .then(function(result){
            var idToken=result&&result.authentication&&result.authentication.idToken;
            if(!idToken)throw new Error('google-id-token-missing');
            return user.reauthenticateWithCredential(firebase.auth.GoogleAuthProvider.credential(idToken));
          });
      }
      var provider=new firebase.auth.GoogleAuthProvider();
      provider.setCustomParameters({prompt:'select_account'});
      return user.reauthenticateWithPopup(provider);
    }
    function deleteAfterAuthentication(allowReauthentication){
      announce('Silme işlemi güvenli sunucuda başlatılıyor.','neon');
      return secureApi('/deleteAccount',{confirm:true}).then(function(){
        try{localStorage.clear();sessionStorage.clear();}catch(e){}
        announce('Hesabın ve bağlı özel verilerin silindi.','neon');
        setTimeout(function(){location.reload();},900);
      }).catch(function(error){
        var code=String(error&&error.message||error);
        if(allowReauthentication&&code.indexOf('reauth-required')>=0){
          announce('Hesabını yeniden doğrulaman gerekiyor.','neon');
          return reauthenticateGoogle().then(function(){return deleteAfterAuthentication(false);});
        }
        var missing=code.indexOf('secure-api-not-configured')>=0;
        announce(missing?'Hesap silme sunucusu henüz yayın yapılandırmasına bağlanmadı. Hiçbir veri silinmedi.':'Hesap silme tamamlanamadı. Hiçbir veri yarım silinmedi.');
        throw error;
      });
    }
    var confirmAction=function(){
      deleteAfterAuthentication(true).catch(function(){});
    };
    if(typeof window.lunoReleaseConfirm==='function'){
      window.lunoReleaseConfirm({
        asset:'assets/luno-art/luno-mascot.png',
        kicker:'HESAP GÜVENLİĞİ',
        title:'Hesabın kalıcı olarak silinsin mi?',
        message:'Profil, koleksiyon, sosyal bağlantılar ve özel oyun verileri silinir. Yasal olarak tutulması gereken satın alma kayıtları anonimleştirilebilir. Bu işlem geri alınamaz.',
        ok:'KALICI OLARAK SİL'
      },confirmAction);
    }else confirmAction();
  }

  function iconMarkup(kind){
    if(kind==='luno')return '<img class="set-icimg" src="assets/luno-art/luno-app-icon-192-v23.png" alt="">';
    if(kind==='google')return '<span class="luno-google-mark" aria-hidden="true">G</span>';
    if(typeof window.setUi==='function')return window.setUi(kind==='delete'?'set_exit':'set_edit');
    return '';
  }
  function makeRow(id,kind,title,subtitle,action,className){
    var row=document.createElement('div');
    row.id=id;row.className='set-row '+(className||'');
    row.setAttribute('role','button');row.setAttribute('tabindex','0');
    row.innerHTML='<div class="set-row-icon">'+iconMarkup(kind)+'</div><div class="set-row-info">'+
      '<div class="set-row-title">'+safeText(title)+'</div><div class="set-row-sub">'+safeText(subtitle)+'</div></div>'+
      '<div class="set-row-arrow">&#10095;</div>';
    if(action){row.onclick=action;row.onkeydown=function(event){if(event.key==='Enter'||event.key===' '){event.preventDefault();action();}};}
    return row;
  }
  function patchAccountSettings(){
    var wrap=document.querySelector('#overlay.show .set-wrap');if(!wrap)return;
    var titles=wrap.querySelectorAll('.set-section-title'),title=null,list=null;
    for(var i=0;i<titles.length;i++)if((titles[i].textContent||'').toUpperCase().indexOf('HESAP')>=0){title=titles[i];list=title.nextElementSibling;break;}
    if(!title||!list)return;
    title.textContent='HESAP VE GÜVENLİK';
    var user=currentUser(),linked=userHasGoogle(user),uid=user&&user.uid||'hazırlanıyor';

    var oldRows=list.querySelectorAll('.set-row');
    for(var j=0;j<oldRows.length;j++){
      var rowTitle=oldRows[j].querySelector('.set-row-title');
      if(rowTitle&&/ÇIKIŞ YAP|HESABIMI SİL/.test(rowTitle.textContent||''))oldRows[j].remove();
    }
    var previous=document.getElementById('lunoAccountSecurityRows');if(previous)previous.remove();
    var box=document.createElement('div');box.id='lunoAccountSecurityRows';box.className='luno-account-settings';
    var status=makeRow('lunoAccountStatus','luno',linked?'GOOGLE’A BAĞLI':'MİSAFİR HESAP','Destek kimliği: '+uid.slice(0,12),'',linked?'luno-account-linked':'');
    status.removeAttribute('role');status.removeAttribute('tabindex');status.querySelector('.set-row-arrow').textContent=linked?'KORUNUYOR':'YEREL CİHAZ';
    box.appendChild(status);
    if(!linked)box.appendChild(makeRow('lunoGoogleLink','google','GOOGLE’A BAĞLA','İlerlemeni koru ve başka cihazlarda devam et',function(){window.googleAuth();},'luno-account-cta'));
    box.appendChild(makeRow('lunoPrivacy','recover','VERİ VE GİZLİLİK','Toplanan veriler ve saklama tercihleri',function(){window.open('privacy.html','_blank');}));
    box.appendChild(makeRow('lunoTerms','recover','KULLANIM ŞARTLARI','Oyun ve hesap kullanım koşulları',function(){window.open('terms.html','_blank');}));
    box.appendChild(makeRow('lunoBlockedPlayers','recover','ENGELLENEN OYUNCULAR','Engellediğin hesapları görüntüle ve yönet',function(){if(typeof window.lunoOpenBlockedPlayers==='function')window.lunoOpenBlockedPlayers();}));
    box.appendChild(makeRow('lunoSecureDelete','delete','HESABIMI SİL','Hesabı ve bağlı özel verileri kalıcı olarak sil',requestSecureDeletion,'set-row-danger'));
    list.insertBefore(box,list.firstChild);
  }

  function installSettingsPatch(){
    if(typeof window.openSettings!=='function'||window.openSettings.__lunoProductionAuth)return;
    var previous=window.openSettings;
    var wrapped=function(){
      var result=previous.apply(this,arguments);
      requestAnimationFrame(function(){requestAnimationFrame(patchAccountSettings);});
      return result;
    };
    wrapped.__lunoProductionAuth=true;wrapped.__lunoOriginal=previous;window.openSettings=wrapped;
  }
  function installSecureRanked(){
    if(window.startMatchmaking&&window.startMatchmaking.__lunoSecureRanked)return;
    var previous={
      sendAction:window.sendActionToServer,sendMove:window.sendMoveToServer,
      startTimer:window.startGameTimer,stopTimer:window.stopGameTimer,
      endGame:window.endGame,endGameAbs:window.endGameAbs,resign:window.resign,
      cleanupOnline:window.cleanupOnline,openMatchMenu:window.openMatchMenu,
      proposeDraw:window.proposeDraw,proposeCancel:window.proposeCancel,cancelProposal:window.cancelProposal,
      acceptProposal:window.acceptProposal,rejectProposal:window.rejectProposal,
      show:window.show,openMatchModes:window.openMatchModes,acceptBot:window.acceptBot,
      openChat:window.openChatPanel,sendChat:window.sendChatMessage,sendEmoji:window.sendEmoji
    };
    var ranked={
      active:false,starting:false,completed:false,completing:false,matchId:'',view:null,
      queueRef:null,queueListener:null,queueRefresh:null,queueBusy:false,
      ownerRef:null,ownerListener:null,ownerUid:'',
      viewRef:null,viewListener:null,heartbeat:null,clockTimer:null,clockBase:null,
      messageRef:null,messageListener:null,seenMessages:{},lastMessageAt:0,
      actionChain:Promise.resolve(),lastOfferKey:'',ownOffer:'',lastEventSequence:-1,resultView:null
    };
    window.LUNO_RANKED_RUNTIME=ranked;

    function clearIntervalField(name){if(ranked[name]){clearInterval(ranked[name]);ranked[name]=null;}}
    function setMatchmakingText(text,color){var node=document.getElementById('mmStatus');if(node){node.textContent=text;if(color)node.style.color=color;}}
    function stopRankedQueueLocal(){
      ranked.queueBusy=false;clearIntervalField('queueRefresh');
      if(ranked.queueRef&&ranked.queueListener){try{ranked.queueRef.off('value',ranked.queueListener);}catch(e){}}
      ranked.queueRef=null;ranked.queueListener=null;
      if(typeof window.MM!=='undefined'&&MM){
        MM.searching=false;
        if(MM.checkInterval){clearInterval(MM.checkInterval);MM.checkInterval=null;}
        if(MM.timerInterval){clearInterval(MM.timerInterval);MM.timerInterval=null;}
        if(MM.timeoutId){clearTimeout(MM.timeoutId);MM.timeoutId=null;}
        MM.myQueueRef=null;MM.matchListener=null;
      }
    }
    function detachRankedLive(){
      if(ranked.viewRef&&ranked.viewListener){try{ranked.viewRef.off('value',ranked.viewListener);}catch(e){}}
      ranked.viewRef=null;ranked.viewListener=null;
      if(ranked.messageRef&&ranked.messageListener){try{ranked.messageRef.off('value',ranked.messageListener);}catch(e){}}
      ranked.messageRef=null;ranked.messageListener=null;
      clearIntervalField('heartbeat');clearIntervalField('clockTimer');
      try{if(typeof window.hideDisconnectBanner==='function')hideDisconnectBanner();}catch(e){}
    }
    function clearRankedRuntime(){
      stopRankedQueueLocal();detachRankedLive();
      ranked.active=false;ranked.starting=false;ranked.completed=false;ranked.completing=false;
      ranked.matchId='';ranked.view=null;ranked.clockBase=null;ranked.lastOfferKey='';ranked.ownOffer='';ranked.resultView=null;ranked.seenMessages={};ranked.lastMessageAt=0;
      try{localStorage.removeItem('lunoActiveRanked');}catch(e){}
      try{
        if(window.ONLINE){ONLINE.roomCode=null;ONLINE.roomRef=null;ONLINE.myColor=null;ONLINE.opponentInfo=null;ONLINE.isHost=false;ONLINE.connected=false;}
      }catch(e){}
    }
    function rankedErrorText(error){
      var code=String(error&&error.message||error||'');
      if(code.indexOf('chat-rate-limited')>=0)return '\u00c7ok h\u0131zl\u0131! Biraz yava\u015fla.';
      if(code.indexOf('emoji-not-owned')>=0)return 'Bu emoji koleksiyonunda a\u00e7\u0131k de\u011fil.';
      if(code.indexOf('invalid-deck')>=0)return 'Sıralı maç için destende 6 geçerli kart olmalı.';
      if(code.indexOf('stale-sequence')>=0)return 'Maç durumu yenilendi.';
      if(code.indexOf('not-your-turn')>=0)return 'Şu an rakibin sırası.';
      if(code.indexOf('insufficient-mana')>=0)return 'Bu kart için yeterli manan yok.';
      if(code.indexOf('invalid-card-target')>=0)return 'Kart hedefi geçerli değil.';
      if(code.indexOf('match-finished')>=0)return 'Maç sonucu doğrulanıyor.';
      if(code.indexOf('rate-limit')>=0)return 'Çok hızlı işlem yapıldı. Bir an bekle.';
      return 'Bağlantı yenileniyor. Hamlen korunuyor.';
    }
    function normalizeBoard(value){
      var board=[],i;for(i=0;i<64;i++)board[i]=null;
      if(Array.isArray(value)){for(i=0;i<64;i++)if(value[i])board[i]=JSON.parse(JSON.stringify(value[i]));}
      else if(value&&typeof value==='object')for(var key in value){i=Number(key);if(i>=0&&i<64&&value[key])board[i]=JSON.parse(JSON.stringify(value[key]));}
      return board;
    }
    function normalizeEffects(value,type){
      var output={},source=value||{};
      for(var key in source){
        var item=source[key];
        if(item&&typeof item==='object'){
          item=JSON.parse(JSON.stringify(item));
          if(type==='trap'){if(item.lvl==null)item.lvl=item.level||1;if(item.dur==null)item.dur=item.duration||0;}
          if(type==='shield'&&item.dur==null)item.dur=item.duration||0;
        }
        output[key]=item;
      }
      return output;
    }
    function patchRankedTags(view){
      var opponent=view&&view.opponent||{},own=view&&view.player||{};
      var modeLabel=view&&view.mode==='friendly'?'Arkada\u015f Ma\u00e7\u0131':'S\u0131ral\u0131 Ma\u00e7';
      try{
        var enemyName=document.getElementById('tagEnemyName');if(enemyName)enemyName.textContent=opponent.name||'Rakip';
        var enemySub=document.getElementById('tagEnemySub');if(enemySub)enemySub.innerHTML=modeLabel+' &middot; '+Number(opponent.trophies||0)+' &#127942;';
        var enemyFlag=document.getElementById('tagEnemyFlag');if(enemyFlag&&typeof window.flagEmoji==='function')enemyFlag.innerHTML=flagEmoji(opponent.country||'TR');
        var enemyAvatar=document.getElementById('tagEnemyAvatar'),photo=typeof window.safePhotoURL==='function'?safePhotoURL(opponent.photoURL):'';
        if(enemyAvatar)enemyAvatar.style.background=photo?'url('+photo+') center/cover no-repeat':String(opponent.avatar||'#3a2850');
        var enemyIcon=document.getElementById('tagEnemyIcon');if(enemyIcon){
          var avatarKey=String(opponent.avatarEmoji||'');
          if(!photo&&avatarKey.indexOf('av_')===0&&window.AVATAR_IMGS&&AVATAR_IMGS[avatarKey]){
            enemyIcon.innerHTML='<img class="luno-v16-avatar-art" src="'+AVATAR_IMGS[avatarKey]+'" alt="">';
          }else{
            enemyIcon.innerHTML=typeof window.safeEmoji==='function'?safeEmoji(avatarKey||'&#9818;'):(avatarKey||'&#9818;');
          }
          enemyIcon.style.display=photo?'none':'';
        }
        var ownName=document.getElementById('tagYouName');if(ownName)ownName.textContent=own.name||'LunoPlayer';
        var ownSub=document.getElementById('tagYouSub');if(ownSub)ownSub.innerHTML=modeLabel+' &middot; '+Number(own.trophies||0)+' &#127942;';
      }catch(e){}
    }
    function clockTick(){
      if(!ranked.active||!ranked.clockBase||!window.G||G.over)return;
      var base=ranked.clockBase,clock=base.clock||{},serverNow=Number(base.serverNow||Date.now())+(Date.now()-base.receivedAt);
      var white=Math.max(0,Number(clock.W||0)),black=Math.max(0,Number(clock.B||0));
      if(clock.activeColor&&clock.startedAt){var elapsed=Math.max(0,serverNow-Number(clock.startedAt));if(clock.activeColor==='W')white=Math.max(0,white-elapsed);else black=Math.max(0,black-elapsed);}
      G.timeW=white/1000;G.timeB=black/1000;
      try{if(typeof window.updateTimerDisplay==='function')updateTimerDisplay();}catch(e){}
    }
    function startRankedClock(){clearIntervalField('clockTimer');clockTick();ranked.clockTimer=setInterval(clockTick,1000);}
    function resultReason(reason,won){
      var map={checkmate:'Şah mat',timeout:won?'Rakibin süresi doldu':'Süren doldu',resignation:won?'Rakip maçtan çekildi':'Maçtan çekildin','disconnect-forfeit':won?'Rakip geri bağlanamadı':'Bağlantı süresi doldu','draw-agreement':'Beraberlik kabul edildi',stalemate:'Pat','fifty-move-rule':'50 hamle kuralı','threefold-repetition':'Üç kez tekrar','insufficient-material':'Yetersiz materyal','both-disconnected':'İki oyuncunun bağlantısı kesildi','effect-lock':'Tahta kilitlendi','mutual-cancellation':'Maç karşılıklı iptal edildi'};
      return map[reason]||'';
    }
    function renderRankedResult(view){
      ranked.completed=true;ranked.completing=false;ranked.resultView=view;detachRankedLive();
      try{localStorage.removeItem('lunoActiveRanked');}catch(e){}
      try{
        var bubbles=document.querySelectorAll('#chatBubbleMe,#chatBubbleOp');for(var bi=0;bi<bubbles.length;bi++)bubbles[bi].remove();
        if(typeof window.hideEmojiBubble==='function'){hideEmojiBubble('enemy');hideEmojiBubble('you');}
        if(typeof window.closeEmojiPicker==='function')closeEmojiPicker();
      }catch(e){}
      if(window.G){G.over=true;G.phase='ended';G.timerOn=false;G._serverRanked=true;G._endTriggered=true;}
      if(window.ONLINE)ONLINE.connected=false;
      var result=view.result||{},cancelled=result.type==='cancelled',draw=result.winner==='draw',won=!draw&&!cancelled&&result.winner===view.viewerColor,friendly=view.mode==='friendly';
      var settlement=view.settlement||{},delta=Number(settlement.trophyDelta||0),gold=Number(settlement.gold||0)+Number(settlement.levelGold||0),xp=Number(settlement.xp||0);
      try{if(previous.show)previous.show('result');else if(typeof window.show==='function')window.show('result');}catch(e){}
      var glyph=document.getElementById('resGlyph'),title=document.getElementById('resTitle'),sub=document.getElementById('resSub'),reward=document.getElementById('resTrophy');
      if(cancelled){if(glyph)glyph.innerHTML=typeof window.resMasc==='function'?resMasc('m_draw','&#10006;'):'&#10006;';if(title)title.textContent='MAÇ İPTAL';}
      else if(draw){if(glyph)glyph.innerHTML=typeof window.resMasc==='function'?resMasc('m_draw','&#10070;'):'&#10070;';if(title)title.textContent='BERABERE';}
      else if(won){if(glyph)glyph.innerHTML=typeof window.resMasc==='function'?resMasc('m_victory','&#9818;'):'&#9818;';if(title)title.textContent='ZAFER';try{if(typeof window.launchConfetti==='function')launchConfetti();if(typeof window.haptic==='function')haptic([20,40,20,40,60]);}catch(e){}}
      else{if(glyph)glyph.innerHTML=typeof window.resMasc==='function'?resMasc('m_defeat','&#9760;'):'&#9760;';if(title)title.textContent='YENİLGİ';try{if(typeof window.haptic==='function')haptic([80]);}catch(e){}}
      if(sub)sub.textContent=resultReason(result.reason,won);
      if(reward){
        if(friendly)reward.innerHTML='Dostluk ma\u00e7\u0131 &middot; Kupa ve \u00f6d\u00fcller de\u011fi\u015fmedi';
        else if(cancelled)reward.innerHTML='Kupa ve ödüller değişmedi';
        else reward.innerHTML=(delta>0?'+':'')+delta+' &#127942;'+(gold?' &middot; +'+gold+' &#129689;':'')+(xp?' &middot; +'+xp+' XP':'');
        reward.className='rtrophy '+(delta>0?'up':delta<0?'down':'');
      }
    }
    function completeRanked(view){
      if(ranked.completing||ranked.completed)return;
      ranked.completing=true;if(window.G){G.over=true;G.phase='ended';G.timerOn=false;}
      clearIntervalField('heartbeat');clearIntervalField('clockTimer');
      secureApi('/getRankedMatch',{matchId:ranked.matchId}).then(function(result){
        if(result.state)applyAuthoritativeState(result.state);
        var finalView=result.view||view;ranked.view=finalView;renderRankedResult(finalView);
      }).catch(function(){renderRankedResult(view);});
    }
    function showConnectionState(view){
      var state=view&&view.connection&&view.connection.opponent&&view.connection.opponent.state;
      try{
        if(state==='TEMP_DISCONNECTED'){
          if(typeof window.showDisconnectBanner==='function')showDisconnectBanner();
          var sub=document.querySelector('#disconnectBanner .db-sub'),until=Number(view.connection.opponent.graceUntil||0),seconds=Math.max(0,Math.ceil((until-Number(view.serverNow||Date.now()))/1000));
          if(sub)sub.textContent=seconds+' saniye boyunca bekleniyor...';
        }else if(typeof window.hideDisconnectBanner==='function')hideDisconnectBanner();
      }catch(e){}
    }
    function handleRankedOffers(view){
      var offer=view.drawOffer?{type:'draw',data:view.drawOffer}:view.cancelOffer?{type:'cancel',data:view.cancelOffer}:null;
      if(offer&&!offer.data.bySelf){
        var key=offer.type+'-'+offer.data.offeredAt;
        if(ranked.lastOfferKey!==key){ranked.lastOfferKey=key;ranked.ownOffer='';try{if(typeof window.showProposalReceived==='function')showProposalReceived({type:offer.type,by:view.viewerColor==='W'?'B':'W',ts:offer.data.offeredAt});}catch(e){}}
      }
      var event=view.lastEvent;
      if(event&&Number(event.sequence)>ranked.lastEventSequence){
        ranked.lastEventSequence=Number(event.sequence);
        if(event.by!==view.viewerColor&&(event.type==='reject_draw'||event.type==='reject_cancel')){try{if(typeof window.closeMatchMenu==='function')closeMatchMenu();}catch(e){}announce('Rakip teklifini reddetti.');}
      }
    }
    function applyRankedView(view){
      if(!view||!ranked.active||view.matchId!==ranked.matchId||!window.G)return;
      ranked.view=view;ranked.clockBase={clock:view.clock||{},serverNow:Number(view.serverNow||Date.now()),receivedAt:Date.now()};
      try{window.ANIM_BUSY=false;if(window._animSafetyTimer){clearTimeout(_animSafetyTimer);window._animSafetyTimer=null;}}catch(e){}
      G.board=normalizeBoard(view.board);G.turn=view.turn||'W';G.phase=view.phase||'card';G.moveCount=Number(view.moveCount||0);G.halfMove=Number(view.halfMove||0);G.epTarget=Number.isInteger(Number(view.epTarget))?Number(view.epTarget):-1;
      G.hand=Array.isArray(view.hand)?view.hand.slice():[];G.aiHand=Array.isArray(view.opponentHand)?view.opponentHand.slice():[];
      if(!view.opponentHand)for(var i=0;i<Number(view.opponentHandCount||0);i++)G.aiHand.push('__hidden__');
      G.mana={W:view.mana&&view.mana.W!=null?Number(view.mana.W):0,B:view.mana&&view.mana.B!=null?Number(view.mana.B):0};
      G.cardUsed=view.cardUsed===true;G.cardBlock=Object.assign({W:0,B:0},view.cardBlock||{});G.lastCard=Object.assign({W:null,B:null},view.lastCard||{});
      G.traps=normalizeEffects(view.traps,'trap');G.blocks=normalizeEffects(view.blocks);G.pits=normalizeEffects(view.pits);G.shields=normalizeEffects(view.shields,'shield');G.fog=Object.assign({W:0,B:0},view.fog||{});G.captures=Object.assign({W:[],B:[]},view.captures||{});
      G.sel=null;G.armed=null;G.pendingPromo=null;G.gluePending=null;G._serverRanked=true;G.over=!!view.result;G._endTriggered=!!view.result;
      if(view.lastEvent&&view.lastEvent.type==='move')G.last={from:Number(view.lastEvent.from),to:Number(view.lastEvent.to)};
      try{window._handSig=null;if(typeof window.renderAll==='function')renderAll();patchRankedTags(view);clockTick();}catch(e){}
      showConnectionState(view);handleRankedOffers(view);
      if(view.result)completeRanked(view);
    }
    function fetchRankedMatch(matchId){
      return secureApi('/getRankedMatch',matchId?{matchId:matchId}:{}).then(function(result){if(result.state)applyAuthoritativeState(result.state);return result;});
    }
    function heartbeatRanked(){
      if(!ranked.active||!ranked.matchId||ranked.completed)return;
      secureApi('/heartbeatRankedMatch',{matchId:ranked.matchId}).then(function(result){if(result.view)applyRankedView(result.view);}).catch(function(){
        try{if(typeof window.showDisconnectBanner==='function')showDisconnectBanner();var title=document.querySelector('#disconnectBanner .db-title');if(title)title.textContent='BAĞLANTI YENİDEN KURULUYOR';}catch(e){}
      });
    }
    function subscribeRankedView(){
      if(!window.FB_DB||!ranked.matchId)return;
      ranked.viewRef=FB_DB.ref('rankedMatchViews/'+currentUser().uid+'/'+ranked.matchId);
      ranked.viewListener=ranked.viewRef.on('value',function(snapshot){var view=snapshot.val();if(view)applyRankedView(view);});
    }
    function rankedEmoji(id){
      var list=window.EMOJI_LIST||[];
      for(var i=0;i<list.length;i++)if(list[i]&&list[i].id===id)return list[i];
      return null;
    }
    function showRankedMessage(message){
      if(!message||message.matchId!==ranked.matchId||!message.messageId||ranked.seenMessages[message.messageId])return;
      ranked.seenMessages[message.messageId]=true;
      var user=currentUser(),mine=!!(user&&message.fromUid===user.uid);
      try{
        if(message.kind==='emoji'){
          var emoji=rankedEmoji(message.id);if(emoji&&typeof window.showEmojiBubble==='function')showEmojiBubble(mine?'you':'enemy',emoji);
        }else if(typeof window.showChatBubble==='function')showChatBubble(message.id,message.tab,mine);
      }catch(e){}
    }
    function subscribeRankedMessages(){
      var user=currentUser();if(!window.FB_DB||!user||!ranked.matchId)return;
      ranked.messageRef=FB_DB.ref('rankedMessages/'+user.uid+'/'+ranked.matchId);
      ranked.messageListener=ranked.messageRef.on('value',function(snapshot){showRankedMessage(snapshot.val());});
    }
    function sendRankedSocial(payload){
      if(!ranked.active||!ranked.matchId)return Promise.reject(new Error('ranked-match-not-active'));
      if(Date.now()-ranked.lastMessageAt<1500){announce('\u00c7ok h\u0131zl\u0131! Biraz yava\u015fla.');return Promise.reject(new Error('chat-rate-limited'));}
      ranked.lastMessageAt=Date.now();payload=Object.assign({},payload,{matchId:ranked.matchId});
      return secureApi('/sendRankedMessage',payload).then(function(result){if(result&&result.message)showRankedMessage(result.message);return result;}).catch(function(error){announce(rankedErrorText(error),'warn');throw error;});
    }
    function startRankedMatch(view){
      if(!view||!view.matchId||ranked.starting||ranked.completed)return;
      if(ranked.active&&ranked.matchId===view.matchId){applyRankedView(view);return;}
      try{if(typeof window.lunoFriendlyMatchStarted==='function')lunoFriendlyMatchStarted();}catch(e){}
      ranked.starting=true;stopRankedQueueLocal();
      try{if(previous.stopTimer)previous.stopTimer();}catch(e){}
      ranked.active=true;ranked.matchId=view.matchId;ranked.view=view;ranked.actionChain=Promise.resolve();ranked.lastEventSequence=-1;ranked.seenMessages={};ranked.lastMessageAt=0;
      ONLINE.roomCode=view.matchId;ONLINE.roomRef=null;ONLINE.myColor=view.viewerColor;ONLINE.isHost=view.viewerColor==='W';ONLINE.connected=true;
      ONLINE.opponentInfo={uid:view.opponent&&view.opponent.uid||'',name:view.opponent&&view.opponent.name||'Rakip',avatar:view.opponent&&view.opponent.avatarEmoji||'&#9818;',country:view.opponent&&view.opponent.country||'TR',trophies:Number(view.opponent&&view.opponent.trophies||0),skin:view.opponent&&view.opponent.activeSkin||'classic',pieceSet:view.opponent&&view.opponent.activePieceSet||'std',costumes:view.opponent&&view.opponent.activeCostumes||{},photoURL:view.opponent&&view.opponent.photoURL||null};
      try{localStorage.setItem('lunoActiveRanked',JSON.stringify({matchId:view.matchId,savedAt:Date.now()}));}catch(e){}
      try{window.startMatch('online');}catch(error){ranked.starting=false;ranked.active=false;announce('Maç ekranı açılamadı.','warn');return;}
      if(!window.G){ranked.starting=false;ranked.active=false;return;}
      G._serverRanked=true;applyRankedView(view);subscribeRankedView();subscribeRankedMessages();startRankedClock();heartbeatRanked();clearIntervalField('heartbeat');ranked.heartbeat=setInterval(heartbeatRanked,10000);
      ranked.starting=false;setMatchmakingText('Rakip bulundu!','#80ff80');announce(view.mode==='friendly'?'ARKADA\u015e MA\u00c7I':'SIRALI MA\u00c7','neon');
    }
    function handleMatched(matchId,view){
      if(!matchId||ranked.starting||ranked.active)return;
      stopRankedQueueLocal();setMatchmakingText('Rakip bulundu! Maç başlıyor...','#80ff80');
      (view?Promise.resolve({view:view}):fetchRankedMatch(matchId)).then(function(result){if(result&&result.view)startRankedMatch(result.view);}).catch(function(){announce('Maç bağlantısı kurulamadı. Tekrar deneniyor.','warn');setTimeout(resumeRanked,1500);});
    }
    function ensureOwnerMatchFeed(){
      var user=currentUser();if(!user||!window.FB_DB)return;
      if(ranked.ownerRef&&ranked.ownerUid===user.uid)return;
      if(ranked.ownerRef&&ranked.ownerListener){try{ranked.ownerRef.off('value',ranked.ownerListener);}catch(e){}}
      ranked.ownerUid=user.uid;ranked.ownerRef=FB_DB.ref('rankedPlayers/'+user.uid);
      ranked.ownerListener=ranked.ownerRef.on('value',function(snapshot){
        var pointer=snapshot.val();if(pointer&&pointer.status==='active'&&pointer.matchId)handleMatched(pointer.matchId);
      });
    }
    function enqueueRankedOnce(){
      if(ranked.queueBusy||ranked.active||!currentUser())return;ranked.queueBusy=true;
      secureApi('/enqueueRanked',{}).then(function(result){ranked.queueBusy=false;if(result.status==='matched')handleMatched(result.matchId,result.view);}).catch(function(error){ranked.queueBusy=false;setMatchmakingText(rankedErrorText(error),'#ff9090');});
    }
    function beginRankedQueue(){
      var user=currentUser();if(!user||!window.FB_DB){announce('Güvenli oyuncu oturumu hazır değil.','warn');return;}
      stopRankedQueueLocal();ranked.completed=false;ranked.resultView=null;
      if(typeof window.MM!=='undefined'&&MM){MM.searching=true;MM.startTime=Date.now();MM.botOffered=false;MM.timerInterval=setInterval(function(){if(typeof window.updateMmTimer==='function')updateMmTimer();},500);}
      ranked.queueRef=FB_DB.ref('rankedPlayers/'+user.uid);
      ranked.queueListener=ranked.queueRef.on('value',function(snapshot){var pointer=snapshot.val();if(pointer&&pointer.status==='active'&&pointer.matchId)handleMatched(pointer.matchId);});
      enqueueRankedOnce();ranked.queueRefresh=setInterval(enqueueRankedOnce,15500);
    }
    function startMatchmakingSecure(){
      if(ranked.active)return;
      setMatchmakingText('Güvenli eşleştirme hazırlanıyor...');
      ensureGuestSession().then(refreshAuthoritativeState).then(beginRankedQueue).catch(function(error){
        var code=String(error&&error.message||error||'');
        setMatchmakingText('Güvenli bağlantı yenileniyor...','#ffd47a');
        setTimeout(function(){
          if(ranked.active||ranked.queueBusy)return;
          ensureGuestSession().then(refreshAuthoritativeState).then(beginRankedQueue).catch(function(finalError){
            var finalCode=String(finalError&&finalError.message||finalError||code);
            setMatchmakingText('Bağlantı kurulamadı','#ff9090');
            if(finalCode.indexOf('app-check')>=0||finalCode.indexOf('App Check')>=0)announce('Oyun güvenlik doğrulaması tamamlanamadı. Play test sürümünü güncelleyip tekrar dene.','warn');
            else announce('İnternet bağlantını kontrol edip tekrar dene.','warn');
          });
        },900);
      });
    }
    startMatchmakingSecure.__lunoSecureRanked=true;
    window.startMatchmaking=startMatchmakingSecure;
    window.cleanupMatchmaking=stopRankedQueueLocal;
    window.cancelMatchmaking=function(){
      try{if(typeof window.sndUiClick==='function')sndUiClick();}catch(e){}
      stopRankedQueueLocal();try{if(typeof window.closeOverlay==='function')closeOverlay();}catch(e){}
      if(!currentUser())return;
      secureApi('/cancelRankedQueue',{}).catch(function(error){if(String(error&&error.message||error).indexOf('match-already-active')>=0)resumeRanked();});
    };
    window.acceptBot=function(){
      stopRankedQueueLocal();
      secureApi('/cancelRankedQueue',{}).then(function(){try{if(typeof window.closeOverlay==='function')closeOverlay();}catch(e){}setTimeout(function(){window.startMatch('ranked');},250);}).catch(function(){resumeRanked();});
    };
    function rankedAction(data){
      if(!ranked.active||!ranked.matchId)return Promise.reject(new Error('ranked-match-not-active'));
      var payload=Object.assign({},data||{});payload.matchId=ranked.matchId;payload.actionId=payload.actionId||newRequestId(currentUser(),'ranked-'+payload.type);
      ranked.actionChain=ranked.actionChain.catch(function(){}).then(function(){
        payload.expectedSequence=Number(ranked.view&&ranked.view.sequence||0);
        return secureApi('/submitMatchAction',payload).then(function(result){if(result.state)applyAuthoritativeState(result.state);if(result.view)applyRankedView(result.view);return result;});
      }).catch(function(error){
        announce(rankedErrorText(error),String(error&&error.message||error).indexOf('stale-sequence')>=0?'':'warn');
        return fetchRankedMatch(ranked.matchId).then(function(result){if(result.view)applyRankedView(result.view);return result;},function(){throw error;});
      });
      return ranked.actionChain;
    }
    window.sendActionToServer=function(action){
      if(!ranked.active)return previous.sendAction&&previous.sendAction.apply(this,arguments);
      action=action||{};var payload={type:action.type};
      if(action.type==='move'){payload.from=Number(action.from);payload.to=Number(action.to);payload.promotion=action.promotion||action.promo||'Q';}
      if(action.type==='card'){
        payload.cardKey=String(action.cardKey||'');
        if(action.glueA!=null){payload.target=Number(action.glueA);payload.secondaryTarget=Number(action.glueB);}
        else if(action.target!=null)payload.target=Number(action.target);
      }
      rankedAction(payload).catch(function(){});
    };
    window.sendMoveToServer=function(from,to,promotion){if(ranked.active){rankedAction({type:'move',from:Number(from),to:Number(to),promotion:promotion||'Q'}).catch(function(){});return;}if(previous.sendMove)return previous.sendMove.apply(this,arguments);};
    window.startGameTimer=function(){if(ranked.active){startRankedClock();return;}if(previous.startTimer)return previous.startTimer.apply(this,arguments);};
    window.stopGameTimer=function(){if(ranked.active){clearIntervalField('clockTimer');return;}if(previous.stopTimer)return previous.stopTimer.apply(this,arguments);};
    window.endGame=function(won,reason){if(ranked.active){if(window.G&&!ranked.completed){G.over=false;G._endTriggered=false;}heartbeatRanked();return;}if(previous.endGame)return previous.endGame.apply(this,arguments);};
    window.endGameAbs=function(whiteWon,reason){if(ranked.active){heartbeatRanked();return;}if(previous.endGameAbs)return previous.endGameAbs.apply(this,arguments);};
    window.resign=function(){
      if(!ranked.active){if(previous.resign)return previous.resign.apply(this,arguments);return;}
      if(!window.G||G._resignTriggered)return;G._resignTriggered=true;G.phase='ending';
      rankedAction({type:'resign'}).catch(function(){if(window.G){G._resignTriggered=false;G.phase=ranked.view&&ranked.view.phase||'card';}});
    };
    function showOfferWaiting(type){
      var label=type==='draw'?'BERABERLİK TEKLİFİ':'İPTAL TEKLİFİ';
      var html='<div class="mm-actions-wrap"><div class="mm-waiting"><div class="mm-wait-spinner"></div><div class="mm-wait-title">'+label+' GÖNDERİLDİ</div><div class="mm-wait-desc">Rakibin cevabı bekleniyor...</div></div><button class="mm-action-close" onclick="cancelProposal();closeMatchMenu();">TEKLİFİ GERİ ÇEK</button></div>';
      try{if(typeof window.showMatchOverlay==='function')showMatchOverlay(html);}catch(e){}
    }
    window.proposeDraw=function(){if(!ranked.active){if(previous.proposeDraw)return previous.proposeDraw.apply(this,arguments);return;}ranked.ownOffer='draw';showOfferWaiting('draw');rankedAction({type:'offer_draw'}).catch(function(){});};
    window.proposeCancel=function(){if(!ranked.active){if(previous.proposeCancel)return previous.proposeCancel.apply(this,arguments);return;}if(window.G&&G.moveCount>=3){announce('3 hamleden sonra maç iptal edilemez.');return;}ranked.ownOffer='cancel';showOfferWaiting('cancel');rankedAction({type:'offer_cancel'}).catch(function(){});};
    window.cancelProposal=function(){if(!ranked.active){if(previous.cancelProposal)return previous.cancelProposal.apply(this,arguments);return;}var type=ranked.ownOffer;ranked.ownOffer='';if(type)rankedAction({type:type==='draw'?'cancel_draw':'cancel_cancel'}).catch(function(){});};
    window.acceptProposal=function(type){if(!ranked.active){if(previous.acceptProposal)return previous.acceptProposal.apply(this,arguments);return;}try{if(typeof window.closeMatchMenu==='function')closeMatchMenu();}catch(e){}rankedAction({type:type==='draw'?'accept_draw':'accept_cancel'}).catch(function(){});};
    window.rejectProposal=function(){if(!ranked.active){if(previous.rejectProposal)return previous.rejectProposal.apply(this,arguments);return;}var type=ranked.view&&ranked.view.drawOffer?'draw':'cancel';try{if(typeof window.closeMatchMenu==='function')closeMatchMenu();}catch(e){}rankedAction({type:type==='draw'?'reject_draw':'reject_cancel'}).catch(function(){});};
    if(previous.openChat)window.openChatPanel=function(){
      if(!ranked.active)return previous.openChat.apply(this,arguments);
      if(!window.G||G.over)return;
      var room=ONLINE.roomRef,connected=ONLINE.connected,result;
      try{ONLINE.roomRef=room||{secureRanked:true};ONLINE.connected=true;result=previous.openChat.apply(this,arguments);}
      finally{ONLINE.roomRef=room;ONLINE.connected=connected;}
      return result;
    };
    window.sendChatMessage=function(id,tab){
      if(!ranked.active){if(previous.sendChat)return previous.sendChat.apply(this,arguments);return;}
      id=String(id||'');tab=String(tab||'');var items=window.CHAT_PRESETS&&CHAT_PRESETS[tab]||[],valid=false;
      for(var i=0;i<items.length;i++)if(items[i]&&items[i].id===id){valid=true;break;}
      if(!valid){announce('Mesaj kullan\u0131lam\u0131yor.');return;}
      try{if(typeof window.sndUiClick==='function')sndUiClick();}catch(e){}
      sendRankedSocial({kind:tab==='emojis'?'emoji':'preset',id:id,tab:tab}).then(function(){try{if(typeof window.closeMatchMenu==='function')closeMatchMenu();}catch(e){}}).catch(function(){});
    };
    window.sendEmoji=function(emoji){
      if(!ranked.active){if(previous.sendEmoji)return previous.sendEmoji.apply(this,arguments);return;}
      var id=String(emoji&&emoji.id||''),owned=window.PLAYER&&Array.isArray(PLAYER.ownedEmojis)?PLAYER.ownedEmojis:[];
      if(!id||owned.indexOf(id)<0){announce('Bu emoji koleksiyonunda a\u00e7\u0131k de\u011fil.');return;}
      try{if(typeof window.sndUiClick==='function')sndUiClick();if(typeof window.closeEmojiPicker==='function')closeEmojiPicker();}catch(e){}
      sendRankedSocial({kind:'emoji',id:id,tab:'emojis'}).catch(function(){});
    };
    if(previous.openMatchMenu)window.openMatchMenu=function(){var result=previous.openMatchMenu.apply(this,arguments);if(ranked.active)setTimeout(function(){var share=document.querySelector('#matchMenuOverlay .mm-action-share');if(share)share.remove();},0);return result;};
    window.cleanupOnline=function(){if(ranked.active||ranked.completed){clearRankedRuntime();return;}if(previous.cleanupOnline)return previous.cleanupOnline.apply(this,arguments);};
    if(previous.show){
      var rankedShow=function(screenId){
        if(ranked.active&&!ranked.completed&&screenId!=='game'&&screenId!=='result'){announce('Devam eden maçın var.','warn');return previous.show.call(this,'game');}
        if(ranked.completed&&screenId!=='result')clearRankedRuntime();
        return previous.show.apply(this,arguments);
      };
      rankedShow.__lunoRankedGuard=true;
      rankedShow.__lunoOriginal=previous.show;
      window.show=rankedShow;
    }
    if(previous.openMatchModes)window.openMatchModes=function(){if(ranked.completed)clearRankedRuntime();return previous.openMatchModes.apply(this,arguments);};
    function resumeRanked(){
      if(ranked.active||ranked.starting||!currentUser())return;
      fetchRankedMatch('').then(function(result){if(result&&result.matchId&&result.view&&(result.status==='active'||result.view.result))startRankedMatch(result.view);}).catch(function(){});
    }
    window.lunoResumeRankedMatch=resumeRanked;window.lunoRankedAction=rankedAction;window.lunoStartServerMatch=startRankedMatch;
    window.addEventListener('visibilitychange',function(){if(!document.hidden&&ranked.active)heartbeatRanked();});
    window.addEventListener('online',function(){if(ranked.active)heartbeatRanked();});
    window.addEventListener('luno:guest-ready',function(){setTimeout(function(){ensureOwnerMatchFeed();resumeRanked();},500);});
    setTimeout(function(){ensureOwnerMatchFeed();resumeRanked();},800);
  }
  function installSecureSocial(){
    var lastMessageAt=0,readTimers={},searchTimer=null,searchVersion=0;
    var reportOptions=[
      {id:'harassment',label:'Taciz veya zorbalık'},
      {id:'threats',label:'Tehdit'},
      {id:'hate',label:'Nefret söylemi'},
      {id:'sexual_content',label:'Cinsel içerik'},
      {id:'spam',label:'Spam'},
      {id:'scam',label:'Dolandırıcılık'},
      {id:'cheating',label:'Hile'},
      {id:'abuse',label:'Diğer kötüye kullanım'},
      {id:'other',label:'Diğer'}
    ];
    function refreshFriends(){
      if(typeof window.loadFriends==='function')loadFriends(function(){if(typeof window.openFriendsHub==='function')openFriendsHub();});
    }
    function confirmSocial(options,action){
      if(typeof window.lunoReleaseConfirm==='function')window.lunoReleaseConfirm(options,action);
      else if(window.confirm(options.title||'Emin misin?'))action();
    }
    function closeModerationPicker(){var picker=document.getElementById('lunoModerationPicker');if(picker)picker.remove();}
    function moderationPicker(title,onSelect){
      closeModerationPicker();
      var picker=document.createElement('div');picker.id='lunoModerationPicker';picker.className='luno-mod-backdrop';
      picker.setAttribute('role','dialog');picker.setAttribute('aria-modal','true');picker.setAttribute('aria-label',title);
      var panel=document.createElement('div');panel.className='luno-mod-panel';
      panel.innerHTML='<img class="luno-mod-luno" src="assets/luno-art/luno-mascot.png" alt="">'+
        '<div class="luno-mod-kicker">GÜVENLİ TOPLULUK</div><div class="luno-mod-title">'+safeText(title)+'</div>'+
        '<div class="luno-mod-copy">En uygun nedeni seç. Bildirimin gizli tutulur ve inceleme kuyruğuna gönderilir.</div>';
      var list=document.createElement('div');list.className='luno-mod-reasons';
      reportOptions.forEach(function(option){
        var button=document.createElement('button');button.type='button';button.className='luno-mod-reason';button.textContent=option.label;
        button.onclick=function(){closeModerationPicker();onSelect(option.id);};list.appendChild(button);
      });
      var cancel=document.createElement('button');cancel.type='button';cancel.className='luno-mod-cancel';cancel.textContent='VAZGEÇ';cancel.onclick=closeModerationPicker;
      panel.appendChild(list);panel.appendChild(cancel);picker.appendChild(panel);picker.onclick=function(event){if(event.target===picker)closeModerationPicker();};
      document.body.appendChild(picker);
    }
    function reportUser(uid,name){
      if(!uid)return;
      moderationPicker((name||'Oyuncu')+' bildirilsin mi?',function(reason){
        secureApi('/reportUser',{targetUid:uid,reason:reason,details:''}).then(function(){announce('Bildirimin güvenli biçimde alındı.','neon');}).catch(function(){announce('Bildirim gönderilemedi. Lütfen biraz sonra tekrar dene.');});
      });
    }
    function reportMessage(uid,messageId){
      if(!uid||!messageId)return;
      moderationPicker('Bu mesajı bildir',function(reason){
        secureApi('/reportMessage',{targetUid:uid,messageId:messageId,reason:reason}).then(function(){announce('Mesaj bildirildi.','neon');}).catch(function(){announce('Mesaj bildirilemedi.');});
      });
    }
    function blockUser(uid,name){
      if(!uid)return;
      confirmSocial({asset:'assets/luno-art/luno-mascot.png',kicker:'GÜVENLİ TOPLULUK',title:(name||'Bu oyuncu')+' engellensin mi?',message:'Arkadaşlık, mesaj ve maç daveti bağlantınız kaldırılır. Oyuncu sana yeniden ulaşamaz.',ok:'OYUNCUYU ENGELLE'},function(){
        secureApi('/blockUser',{targetUid:uid}).then(function(){
          try{if(window._dmState&&_dmState.uid===uid&&typeof window.closeDM==='function')closeDM();}catch(e){}
          try{if(typeof window.closeOverlay==='function')closeOverlay();}catch(e){}
          announce('Oyuncu engellendi.','neon');refreshFriends();
        }).catch(function(){announce('Oyuncu engellenemedi.');});
      });
    }
    function unblockUser(uid){
      return secureApi('/unblockUser',{targetUid:uid}).then(function(){announce('Engel kaldırıldı.','neon');openBlockedPlayers();}).catch(function(){announce('Engel kaldırılamadı.');});
    }
    function openBlockedPlayers(){
      var title=document.getElementById('ovTitle'),body=document.getElementById('ovBody'),overlay=document.getElementById('overlay');
      if(!title||!body||!overlay)return;
      title.textContent='ENGELLENEN OYUNCULAR';body.innerHTML='<div class="rk-loading"><div class="rk-load-spinner"></div><div class="rk-load-text">Yükleniyor...</div></div>';
      overlay.classList.add('show');document.body.classList.add('fpage-open');
      secureApi('/listBlockedUsers',{}).then(function(result){
        var players=result&&Array.isArray(result.results)?result.results:[];
        if(!players.length){body.innerHTML='<div class="luno-block-empty"><img src="assets/luno-art/luno-mascot.png" alt="Luno"><strong>Engellenen oyuncu yok</strong><span>Burada yalnız senin engellediğin hesaplar görünür.</span></div>';return;}
        var wrap=document.createElement('div');wrap.className='luno-block-list';
        players.forEach(function(player){
          var row=document.createElement('div');row.className='luno-block-row';
          var avatar=document.createElement('div');avatar.className='luno-block-avatar';avatar.textContent=String(player.name||'?').charAt(0).toUpperCase();
          var info=document.createElement('div');info.className='luno-block-info';
          var strong=document.createElement('strong');strong.textContent=player.name||'Oyuncu';
          var meta=document.createElement('span');meta.textContent=player.playerCode||('@'+(player.username||'oyuncu'));
          var button=document.createElement('button');button.type='button';button.className='luno-block-unblock';button.textContent='ENGELİ KALDIR';button.onclick=function(){button.disabled=true;unblockUser(player.uid);};
          info.appendChild(strong);info.appendChild(meta);row.appendChild(avatar);row.appendChild(info);row.appendChild(button);wrap.appendChild(row);
        });
        body.innerHTML='';body.appendChild(wrap);
      }).catch(function(){body.innerHTML='<div class="luno-block-empty"><strong>Liste açılamadı</strong><span>Bağlantını kontrol edip yeniden dene.</span></div>';});
    }
    window.addFriendByUid=function(uid){
      if(!uid){announce('Oyuncu bulunamadı.');return;}
      try{if(typeof window.sndUiClick==='function')sndUiClick();}catch(e){}
      try{if(typeof window._markAddBtnSent==='function')_markAddBtnSent(uid);}catch(e){}
      secureApi('/sendFriendRequest',{targetUid:uid}).then(function(result){
        if(result.status==='accepted'){announce('Arkadaş eklendi.','neon');refreshFriends();}
        else if(result.status==='friends')announce('Bu oyuncu zaten arkadaşın.','neon');
        else announce('Arkadaşlık isteği gönderildi.','neon');
      }).catch(function(){
        try{if(typeof window._resetAddBtn==='function')_resetAddBtn(uid);}catch(e){}
        announce('Arkadaşlık isteği gönderilemedi.');
      });
    };
    window.addFriendByUid.__lunoSecureSocial=true;
    window.acceptFriendRequest=function(fromUid){
      secureApi('/respondFriendRequest',{fromUid:fromUid,accept:true}).then(function(){announce('Arkadaş eklendi.','neon');refreshFriends();}).catch(function(){announce('Arkadaşlık isteği kabul edilemedi.');});
    };
    window.rejectFriendRequest=function(fromUid){
      secureApi('/respondFriendRequest',{fromUid:fromUid,accept:false}).then(function(){announce('İstek reddedildi.');if(typeof window.openFriendsHub==='function')openFriendsHub();}).catch(function(){announce('İstek reddedilemedi.');});
    };
    var originalRemoveFriend=typeof window.removeFriend==='function'?window.removeFriend:null;
    window.removeFriend=function(uid,name){
      var execute=function(){secureApi('/removeFriend',{targetUid:uid}).then(function(){announce('Arkadaş silindi.');refreshFriends();}).catch(function(){announce('Arkadaş silinemedi.');});};
      if(typeof window.lunoReleaseConfirm==='function'){
        window.lunoReleaseConfirm({asset:'assets/luno-art/luno-mascot.png',kicker:'ARKADAŞLAR',title:(name||'Bu oyuncu')+' silinsin mi?',message:'Oyuncu arkadaş listenden kaldırılacak.',ok:'ARKADAŞLIKTAN ÇIKAR'},execute);
      }else if(!originalRemoveFriend||window.confirm((name||'Bu oyuncu')+' arkadaş listenden silinsin mi?'))execute();
    };
    var originalOpenDM=typeof window.openDM==='function'?window.openDM:null;
    function patchDmControls(){
      var head=document.querySelector('#dmPanel .dm-head');if(!head||head.querySelector('.luno-dm-tools'))return;
      var tools=document.createElement('div');tools.className='luno-dm-tools';
      var mute=document.createElement('button');mute.type='button';mute.className='luno-dm-tool';
      function updateMute(){var muted=!!(window._dmState&&_dmState.muted);mute.textContent=muted?'SESİ AÇ':'SESSİZ';mute.setAttribute('aria-pressed',muted?'true':'false');}
      updateMute();mute.onclick=function(){
        var state=window._dmState||{},next=!state.muted;mute.disabled=true;
        secureApi('/setConversationMuted',{targetUid:state.uid,muted:next}).then(function(){state.muted=next;mute.disabled=false;updateMute();announce(next?'Sohbet sessize alındı.':'Sohbetin sesi açıldı.','neon');}).catch(function(){mute.disabled=false;announce('Sohbet ayarı değiştirilemedi.');});
      };
      var block=document.createElement('button');block.type='button';block.className='luno-dm-tool luno-dm-tool-danger';block.textContent='ENGELLE';block.onclick=function(){var state=window._dmState||{};blockUser(state.uid,state.name);};
      tools.appendChild(mute);tools.appendChild(block);head.appendChild(tools);
    }
    if(originalOpenDM)window.openDM=function(uid,name){
      secureApi('/openDirectMessage',{targetUid:uid}).then(function(result){
        originalOpenDM(uid,name);if(window._dmState)_dmState.muted=result&&result.muted===true;setTimeout(patchDmControls,0);
      }).catch(function(error){
        announce(String(error&&error.message||error).indexOf('friends-only')>=0?'Bu oyuncu yalnız arkadaşlarından mesaj kabul ediyor.':'Sohbet güvenli biçimde açılamadı.');
      });
    };
    var originalRenderDM=typeof window.renderDM==='function'?window.renderDM:null;
    if(originalRenderDM)window.renderDM=function(){
      var result=originalRenderDM.apply(this,arguments),state=window._dmState||{},data=state.msgs||{},keys=Object.keys(data);
      keys.sort(function(a,b){return Number(data[a]&&data[a].ts||0)-Number(data[b]&&data[b].ts||0);});
      var bubbles=document.querySelectorAll('#dmMsgs .dm-bubble'),me=window.ONLINE&&ONLINE.myPlayerId||'';
      for(var i=0;i<bubbles.length&&i<keys.length;i++){
        var message=data[keys[i]]||{};bubbles[i].setAttribute('data-message-id',keys[i]);
        if(message.from!==me&&!bubbles[i].querySelector('.luno-dm-report')){
          var report=document.createElement('button');report.type='button';report.className='luno-dm-report';report.textContent='BİLDİR';report.setAttribute('aria-label','Mesajı bildir');
          (function(targetUid,messageId){report.onclick=function(event){event.stopPropagation();reportMessage(targetUid,messageId);};})(state.uid,keys[i]);
          bubbles[i].appendChild(report);
        }
      }
      patchDmControls();return result;
    };
    window.sendDM=function(){
      var input=document.getElementById('dmInput');if(!input)return;
      var value=(input.value||'').trim(),target=window._dmState&&_dmState.uid;
      if(!value||!target)return;
      if(Date.now()-lastMessageAt<1200){announce('Çok hızlı! Biraz yavaşla.');return;}
      input.disabled=true;
      sendDirectMessageSecure({targetUid:target,text:value.slice(0,500)}).then(function(){
        lastMessageAt=Date.now();input.value='';input.disabled=false;input.focus();
      }).catch(function(error){
        input.disabled=false;if(!input.value)input.value=value;
        if(String(error&&error.message||error).indexOf('legal-consent-cancelled')>=0)announce('Mesaj gönderilmedi.');
        else announce('Mesaj gönderilemedi.');
      });
    };
    function scheduleRead(uid){
      if(!uid)return;if(readTimers[uid])clearTimeout(readTimers[uid]);
      readTimers[uid]=setTimeout(function(){delete readTimers[uid];secureApi('/markDirectMessageRead',{targetUid:uid}).catch(function(){});},500);
    }
    window.markDMRead=function(){scheduleRead(window._dmState&&_dmState.uid);};
    window.markDMInboxRead=function(uid){scheduleRead(uid);};
    var originalShowPlayerProfile=typeof window.showPlayerProfile==='function'?window.showPlayerProfile:null;
    if(originalShowPlayerProfile)window.showPlayerProfile=function(playerId,isFriend){
      var result=originalShowPlayerProfile.apply(this,arguments),me=currentUser();
      if(!playerId||(me&&playerId===me.uid))return result;
      setTimeout(function(){
        var actions=document.querySelector('#overlay.show .pp-actions');if(!actions||actions.querySelector('.luno-profile-safety'))return;
        var box=document.createElement('div');box.className='luno-profile-safety';
        var report=document.createElement('button');report.type='button';report.className='pp-btn luno-profile-report';report.textContent='OYUNCUYU BİLDİR';report.onclick=function(){reportUser(playerId,'Bu oyuncu');};
        var block=document.createElement('button');block.type='button';block.className='pp-btn luno-profile-block';block.textContent='OYUNCUYU ENGELLE';block.onclick=function(){blockUser(playerId,'Bu oyuncu');};
        box.appendChild(report);box.appendChild(block);actions.appendChild(box);
      },0);
      return result;
    };
    function renderSearchResults(query,result){
      var resultsEl=document.getElementById('fhSearchResults');if(!resultsEl)return;
      var raw=result&&Array.isArray(result.results)?result.results:[],matches=raw.map(function(player){
        var arenaIdx=Math.max(0,Number(player.arenaIdx)||0),arenas=window.ARENAS||[];
        return {id:player.uid,name:player.name||player.username||'Oyuncu',username:player.username||'',playerCode:player.playerCode||'',trophies:Number(player.trophies)||0,avatar:typeof window.safeColor==='function'?safeColor(player.avatar):'#6d4bb5',avatarEmoji:typeof window.safeEmoji==='function'?safeEmoji(player.avatarEmoji||'&#9818;'):'&#9818;',photoURL:typeof window.safePhotoURL==='function'?safePhotoURL(player.photoURL)||null:null,country:player.country||'TR',arenaIdx:arenaIdx,arena:arenas[arenaIdx]?arenas[arenaIdx].name:'Piyon Vadisi',isPremium:player.isPremium===true,dmFriendsOnly:player.dmFriendsOnly===true};
      });
      window.SEARCH_RESULTS=matches;
      if(!matches.length){resultsEl.innerHTML='<div class="fh-search-empty"><div class="fh-se-icon">&#128270;</div><div class="fh-se-text">&quot;'+safeText(query)+'&quot; için sonuç yok</div><div class="fh-se-sub">Tam kullanıcı adını veya LUNO kodunu kontrol et</div></div>';return;}
      var friendIds={};if(Array.isArray(window.FRIENDS))for(var i=0;i<FRIENDS.length;i++)friendIds[FRIENDS[i].id]=true;
      var html='<div class="fh-section-label">ARAMA SONUÇLARI ('+matches.length+')</div><div class="fh-list">';
      for(var j=0;j<matches.length;j++)html+=typeof window.renderFriendRow==='function'?renderFriendRow(matches[j],!!friendIds[matches[j].id]):'';
      resultsEl.innerHTML=html+'</div>';
    }
    window.searchPlayers=function(query){
      query=String(query||'').normalize('NFKC').trim().toLowerCase();
      var resultsEl=document.getElementById('fhSearchResults'),contentEl=document.getElementById('fhContent');if(!resultsEl||!contentEl)return;
      searchVersion++;var version=searchVersion;if(searchTimer){clearTimeout(searchTimer);searchTimer=null;}
      if(!query){resultsEl.style.display='none';contentEl.style.display='block';return;}
      resultsEl.style.display='block';contentEl.style.display='none';
      if(query.length<3){resultsEl.innerHTML='<div class="fh-search-empty"><div class="fh-se-icon">&#9432;</div><div class="fh-se-text">En az 3 karakter gir</div></div>';return;}
      resultsEl.innerHTML='<div class="rk-loading"><div class="rk-load-spinner"></div><div class="rk-load-text">Güvenli arama yapılıyor...</div></div>';
      searchTimer=setTimeout(function(){
        searchTimer=null;secureApi('/searchPlayers',{query:query}).then(function(result){if(version===searchVersion)renderSearchResults(query,result);}).catch(function(error){
          if(version!==searchVersion)return;var invalid=String(error&&error.message||error).indexOf('invalid-query')>=0;
          resultsEl.innerHTML='<div class="fh-search-empty"><div class="fh-se-text" style="color:#ffb0b0">'+(invalid?'Yalnız kullanıcı adı veya tam LUNO kodu kullan.':'Arama şu anda tamamlanamadı.')+'</div></div>';
        });
      },280);
    };
    window.searchAndAddFriend=function(query){
      query=String(query||'').normalize('NFKC').trim().toLowerCase();
      if(query.length<3){announce('En az 3 karakter gir.');return;}
      secureApi('/searchPlayers',{query:query}).then(function(result){
        var results=result&&Array.isArray(result.results)?result.results:[],found=null;
        for(var i=0;i<results.length;i++)if(String(results[i].username||'').toLowerCase()===query||String(results[i].playerCode||'').toLowerCase()===query){found=results[i];break;}
        if(!found&&results.length===1)found=results[0];
        if(!found){announce('Oyuncu bulunamadı.');return;}
        window.addFriendByUid(found.uid);
      }).catch(function(){announce('Oyuncu araması tamamlanamadı.');});
    };
    var friendlyInviteTarget='',friendlyRoomCodeValue='',friendlyRoomPoll=null;
    function stopFriendlyRoomPoll(){if(friendlyRoomPoll){clearInterval(friendlyRoomPoll);friendlyRoomPoll=null;}}
    function dismissFriendlyWaiting(){
      var wait=document.getElementById('inviteWaitOv');if(wait){if(wait._t)clearTimeout(wait._t);wait.remove();}
      friendlyInviteTarget='';friendlyRoomCodeValue='';stopFriendlyRoomPoll();
    }
    function friendlyErrorText(error){
      var code=String(error&&error.message||error||'');
      if(code.indexOf('friend-required')>=0)return 'Bu oyuncu art\u0131k arkada\u015f listende de\u011fil.';
      if(code.indexOf('opponent-busy')>=0)return 'Arkada\u015f\u0131n \u015fu anda ba\u015fka bir ma\u00e7ta.';
      if(code.indexOf('match-already-active')>=0)return 'Devam eden ma\u00e7\u0131n\u0131 bitirmelisin.';
      if(code.indexOf('invite-rate-limited')>=0)return 'Davet zaten g\u00f6nderildi; biraz bekle.';
      if(code.indexOf('invite-expired')>=0)return 'Bu davetin s\u00fcresi doldu.';
      if(code.indexOf('room-not-found')>=0||code.indexOf('room-expired')>=0)return 'Oda bulunamad\u0131 veya s\u00fcresi doldu.';
      if(code.indexOf('room-full')>=0)return 'Odaya ba\u015fka bir oyuncu kat\u0131ld\u0131.';
      if(code.indexOf('user-blocked')>=0)return 'Bu oyuncuyla etkile\u015fim kapal\u0131.';
      return 'G\u00fcvenli ma\u00e7 ba\u011flant\u0131s\u0131 kurulamad\u0131.';
    }
    function launchFriendlyView(result){
      if(!result||!result.view||typeof window.lunoStartServerMatch!=='function')throw new Error('friendly-view-missing');
      dismissFriendlyWaiting();
      try{if(typeof window.closeOverlay==='function')closeOverlay();}catch(e){}
      window.lunoStartServerMatch(result.view);
    }
    function pollFriendlyMatch(){
      stopFriendlyRoomPoll();friendlyRoomPoll=setInterval(function(){
        secureApi('/getRankedMatch',{}).then(function(result){if(result&&result.status==='active'&&result.view)launchFriendlyView(result);}).catch(function(){});
      },2500);
    }
    window.sendMatchInvite=function(toUid,toName){
      if(!toUid){announce('Arkada\u015f bulunamad\u0131.');return;}
      try{if(typeof window.sndUiClick==='function')sndUiClick();}catch(e){}
      secureApi('/sendMatchInvite',{targetUid:toUid,durationMinutes:Number(window.LUNO_FRIEND_DURATION_MINUTES)||5}).then(function(){
        friendlyInviteTarget=toUid;
        try{if(window._pendingInvites)_pendingInvites[toUid]=Date.now();window._lastInviteTo=toUid;}catch(e){}
        if(typeof window.showInviteWaiting==='function')showInviteWaiting(toName||'Arkada\u015f\u0131n');
      }).catch(function(error){announce(friendlyErrorText(error),'warn');});
    };
    window.closeInviteWaiting=function(){
      var target=friendlyInviteTarget;dismissFriendlyWaiting();
      try{if(window._pendingInvites&&target)delete _pendingInvites[target];window._lastInviteTo=null;}catch(e){}
      if(target)secureApi('/cancelMatchInvite',{targetUid:target}).catch(function(){});
    };
    window.acceptMatchInvite=function(fromUid){
      if(!fromUid)return;
      try{if(typeof window.sndUiClick==='function')sndUiClick();}catch(e){}
      secureApi('/respondMatchInvite',{fromUid:fromUid,accept:true}).then(launchFriendlyView).catch(function(error){announce(friendlyErrorText(error),'warn');});
    };
    window.rejectMatchInvite=function(fromUid){
      if(!fromUid)return;
      try{if(typeof window.sndUiClick==='function')sndUiClick();}catch(e){}
      secureApi('/respondMatchInvite',{fromUid:fromUid,accept:false}).then(function(){announce('Davet reddedildi.');}).catch(function(error){announce(friendlyErrorText(error),'warn');});
    };
    window.onlineCreateRoom=function(){
      try{if(typeof window.sndUiClick==='function')sndUiClick();}catch(e){}
      secureApi('/createFriendlyRoom',{durationMinutes:Number(window.LUNO_FRIEND_DURATION_MINUTES)||5}).then(function(result){
        friendlyRoomCodeValue=result.roomCode;
        if(window.ONLINE){ONLINE.roomCode=result.roomCode;ONLINE.roomRef=null;ONLINE.myColor='W';ONLINE.isHost=true;ONLINE.connected=false;}
        if(typeof window.showWaitingRoom==='function')showWaitingRoom(result.roomCode);
        pollFriendlyMatch();
      }).catch(function(error){announce(friendlyErrorText(error),'warn');});
    };
    window.cancelRoom=function(){
      var code=friendlyRoomCodeValue||window.ONLINE&&ONLINE.roomCode||'';dismissFriendlyWaiting();
      try{if(typeof window.closeOverlay==='function')closeOverlay();}catch(e){}
      if(window.ONLINE){ONLINE.roomCode=null;ONLINE.roomRef=null;ONLINE.connected=false;}
      if(code)secureApi('/cancelFriendlyRoom',{roomCode:code}).catch(function(){});
      announce('Oda iptal edildi.');
    };
    function joinFriendlyCode(code){
      code=String(code||'').normalize('NFKC').trim().toUpperCase();
      if(!/^[A-Z0-9]{6}$/.test(code)){announce('6 haneli ge\u00e7erli oda kodu gir.','warn');return;}
      try{if(typeof window.sndUiClick==='function')sndUiClick();}catch(e){}
      secureApi('/joinFriendlyRoom',{roomCode:code}).then(launchFriendlyView).catch(function(error){announce(friendlyErrorText(error),'warn');});
    }
    window.onlineJoinRoom=function(){var input=document.getElementById('olJoinCode');if(input)joinFriendlyCode(input.value);};
    window.joinRoomByCode=joinFriendlyCode;
    window.createOnlineRoomWithCode=function(){window.onlineCreateRoom();};
    window.listenForGuestJoin=function(){pollFriendlyMatch();};
    window.checkActiveMatch=function(){try{localStorage.removeItem('lunoActiveRoom');}catch(e){}if(typeof window.lunoResumeRankedMatch==='function')lunoResumeRankedMatch();};
    window.acceptReconnect=function(){if(typeof window.closeMatchMenu==='function')closeMatchMenu();if(typeof window.lunoResumeRankedMatch==='function')lunoResumeRankedMatch();};
    window.lunoFriendlyMatchStarted=dismissFriendlyWaiting;
    try{localStorage.removeItem('lunoActiveRoom');}catch(e){}
    window.sendWelcomeDM=function(){};
    window.lunoReportUser=reportUser;window.lunoReportMessage=reportMessage;window.lunoBlockUser=blockUser;
    window.lunoUnblockUser=unblockUser;window.lunoOpenBlockedPlayers=openBlockedPlayers;
  }
  function injectStyles(){
    if(document.getElementById('lunoProductionAuthStyles'))return;
    var style=document.createElement('style');style.id='lunoProductionAuthStyles';
    style.textContent='.luno-account-gate{position:fixed;inset:0;z-index:120000;display:grid;place-items:center;padding:calc(22px + env(safe-area-inset-top)) 20px calc(22px + env(safe-area-inset-bottom));background:rgba(7,5,24,.96);backdrop-filter:blur(8px)}'+
      '.luno-account-panel{width:min(100%,360px);max-height:calc(100dvh - 44px);overflow:auto;text-align:center;padding:24px 20px 20px;border:1px solid rgba(239,190,72,.55);border-radius:8px;background:#211540;box-shadow:0 24px 70px rgba(0,0,0,.62),inset 0 1px rgba(255,255,255,.08);color:#f7f1ff}'+
      '.luno-account-panel-wide{width:min(100%,390px)}.luno-account-mascot{display:block;width:82px;height:82px;object-fit:contain;margin:0 auto 8px;filter:drop-shadow(0 8px 10px rgba(0,0,0,.32))}'+
      '.luno-account-kicker{font:800 10px Cinzel,serif;color:#eebe48;margin:4px 0 7px}.luno-account-panel h2{font:800 18px/1.25 Cinzel,serif;margin:0 0 9px;color:#fff4d1}.luno-account-panel p{font:500 13px/1.55 Spectral,serif;color:#d9ceed;margin:0 0 17px}'+
      '.luno-account-primary,.luno-account-secondary{width:100%;min-height:46px;border-radius:7px;font:800 12px Cinzel,serif;cursor:pointer;margin-top:8px}.luno-account-primary{border:1px solid #ffe28a;background:#d8a52e;color:#1b102f;box-shadow:0 5px 0 #8b6415}.luno-account-secondary{border:1px solid rgba(194,166,235,.45);background:#35245e;color:#f7f1ff}.luno-account-primary:disabled,.luno-account-secondary:disabled{opacity:.48;cursor:not-allowed;box-shadow:none}'+
      '.luno-account-foot{font:500 10px/1.45 Spectral,serif;color:#a99cbe;margin-top:15px}.luno-account-settings{display:contents}.luno-account-settings .set-row{margin-bottom:6px}.luno-google-mark{display:grid;place-items:center;width:38px;height:38px;border-radius:50%;background:#fff;color:#3769d7;font:900 20px Arial,sans-serif}.luno-account-cta{border:1px solid rgba(239,190,72,.55);background:#3b2767}.luno-account-linked{border:1px solid rgba(91,211,145,.45)}.luno-account-linked .set-row-arrow{font-size:9px;color:#7de3a6}.luno-account-settings .set-row-arrow{max-width:86px;text-align:right;font:800 9px Cinzel,serif}.luno-account-settings .set-row-sub{overflow-wrap:anywhere}'+
      '.luno-legal-panel{width:min(100%,390px)}.luno-legal-panel .luno-account-mascot{width:92px;height:92px;margin-bottom:5px}.luno-legal-links{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin:2px 0 12px}.luno-legal-links a{display:grid;place-items:center;min-height:42px;padding:7px;border:1px solid rgba(239,190,72,.46);border-radius:7px;background:#302052;color:#ffe59a;font:800 9px/1.3 Cinzel,serif;text-decoration:none}.luno-legal-check{display:flex;align-items:center;gap:10px;width:100%;min-height:52px;padding:10px 11px;border:1px solid rgba(194,166,235,.4);border-radius:7px;background:#2a1b49;color:#e9e0f4;text-align:left;font:600 12px/1.35 Spectral,serif}.luno-legal-checkmark{display:grid;place-items:center;width:24px;height:24px;flex:0 0 24px;border:2px solid #8f7aaa;border-radius:5px;color:transparent;background:#171025;font:900 14px Arial,sans-serif}.luno-legal-check.is-checked{border-color:rgba(239,190,72,.7);background:#382553}.luno-legal-check.is-checked .luno-legal-checkmark{border-color:#ffe28a;background:#d8a52e;color:#1b102f}.luno-legal-status{min-height:18px;padding-top:6px;color:#ffcf8b;font:600 10px/1.35 Spectral,serif}'+
      '.luno-mod-backdrop{position:fixed;inset:0;z-index:130000;display:grid;place-items:end center;padding:18px 14px calc(18px + env(safe-area-inset-bottom));background:rgba(5,3,16,.86);backdrop-filter:blur(7px)}.luno-mod-panel{width:min(100%,390px);max-height:min(720px,calc(100dvh - 36px));overflow:auto;padding:18px;border:1px solid rgba(239,190,72,.55);border-radius:8px;background:#211540;box-shadow:0 24px 70px rgba(0,0,0,.68);color:#f8f2ff;text-align:center}.luno-mod-luno{width:58px;height:58px;object-fit:contain}.luno-mod-kicker{font:800 9px Cinzel,serif;color:#eebe48;margin-top:3px}.luno-mod-title{font:900 17px/1.3 Cinzel,serif;color:#fff4d1;margin:4px 0}.luno-mod-copy{font:500 12px/1.45 Spectral,serif;color:#cfc4df;margin-bottom:12px}.luno-mod-reasons{display:grid;grid-template-columns:1fr 1fr;gap:7px}.luno-mod-reason,.luno-mod-cancel{min-height:42px;border-radius:7px;font:800 10px/1.25 Cinzel,serif;cursor:pointer}.luno-mod-reason{border:1px solid rgba(194,166,235,.42);background:#38245f;color:#f7f1ff}.luno-mod-cancel{width:100%;margin-top:10px;border:1px solid rgba(255,255,255,.14);background:#171027;color:#cfc4df}'+
      '.luno-profile-safety{display:grid;grid-template-columns:1fr 1fr;gap:8px;width:100%}.luno-profile-safety .pp-btn{margin:0;min-width:0;font-size:9px}.luno-profile-report{background:#33294f!important;color:#e7dbf5!important}.luno-profile-block{background:#4d2032!important;color:#ffd1da!important}.luno-dm-tools{margin-left:auto;display:flex;gap:6px}.luno-dm-tool{min-height:32px;padding:0 9px;border-radius:6px;border:1px solid rgba(194,166,235,.38);background:#342257;color:#efe7fa;font:800 8px Cinzel,serif}.luno-dm-tool-danger{border-color:rgba(238,100,120,.38);background:#4b1f30;color:#ffd0da}.dm-bubble{position:relative}.luno-dm-report{display:block;margin:5px 0 -2px auto;padding:3px 5px;border:0;background:transparent;color:rgba(255,255,255,.56);font:800 7px Cinzel,serif;text-decoration:underline;cursor:pointer}'+
      '.luno-block-list{display:grid;gap:8px;padding:6px 2px 18px}.luno-block-row{display:flex;align-items:center;gap:11px;padding:11px;border:1px solid rgba(194,166,235,.3);border-radius:7px;background:#271944}.luno-block-avatar{display:grid;place-items:center;width:42px;height:42px;flex:0 0 42px;border-radius:50%;background:#5b3c93;color:#fff2c7;font:900 16px Cinzel,serif}.luno-block-info{display:flex;flex:1;min-width:0;flex-direction:column}.luno-block-info strong{overflow:hidden;text-overflow:ellipsis;font:800 12px Cinzel,serif;color:#fff4d1}.luno-block-info span{font:600 9px Spectral,serif;color:#aa9cbe}.luno-block-unblock{min-height:34px;padding:0 9px;border:1px solid rgba(239,190,72,.5);border-radius:6px;background:#4a3470;color:#ffe8a1;font:800 8px Cinzel,serif}.luno-block-empty{display:grid;justify-items:center;gap:7px;padding:48px 18px;text-align:center;color:#cfc4df}.luno-block-empty img{width:74px;height:74px;object-fit:contain}.luno-block-empty strong{font:900 14px Cinzel,serif;color:#fff4d1}.luno-block-empty span{font:500 12px/1.45 Spectral,serif}'+
      '@media(max-width:350px){.luno-mod-reasons{grid-template-columns:1fr}.luno-dm-tool{padding:0 6px;font-size:7px}.luno-block-unblock{max-width:76px;white-space:normal}}';
    document.head.appendChild(style);
  }

  window.lunoEnsureGuestSession=ensureGuestSession;
  window.lunoShowGuestBootError=showGuestBootError;
  window.lunoShowGoogleConflict=showGoogleConflict;
  window.lunoPrepareGoogleLinkSecure=prepareGoogleLinkSecure;
  window.lunoCompleteGoogleLinkSecure=completeGoogleLinkSecure;
  window.lunoRecordGoogleLinkConflictSecure=recordGoogleLinkConflictSecure;
  window.lunoRequestSecureAccountDeletion=requestSecureDeletion;
  window.lunoPatchAccountSettings=patchAccountSettings;
  window.lunoSecureApi=secureApi;
  window.lunoEnsureLegalConsent=ensureLegalConsent;
  window.lunoGetAppCheckToken=getAppCheckToken;
  window.lunoConnectionHealth=function(){
    var user=currentUser();
    return {online:navigator.onLine!==false,authenticated:!!(user&&user.uid),uid:user&&user.uid?String(user.uid).slice(0,10):'',apiBase:String(window.LUNO_SECURE_API_BASE||''),appCheckBridge:!!nativeAppCheckPlugin(),appCheckReady:!!appCheckCachedToken,appCheckBackoffMs:Math.max(0,appCheckBackoffUntil-Date.now()),appCheckLastFailure:appCheckLastFailure,diagnostics:diagnosticBuffer.slice(-12)};
  };
  window.lunoApplyAuthoritativeState=applyAuthoritativeState;
  window.lunoRefreshAuthoritativeState=refreshAuthoritativeState;
  window.lunoClaimDailyRewardSecure=claimDailyRewardSecure;
  window.lunoClaimMissionRewardSecure=claimMissionRewardSecure;
  window.lunoClaimAchievementRewardSecure=claimAchievementRewardSecure;
  window.lunoClaimPassRewardSecure=claimPassRewardSecure;
  window.lunoClaimSeasonRewardSecure=claimSeasonRewardSecure;
  window.lunoClaimOnboardingRewardSecure=claimOnboardingRewardSecure;
  window.lunoClaimSocialVisitRewardSecure=claimSocialVisitRewardSecure;
  window.lunoPurchaseSoftItem=purchaseSoftItemSecure;
  window.lunoOpenChestSecure=openChestSecure;
  window.lunoUpgradeCardSecure=upgradeCardSecure;
  window.lunoReserveUsernameSecure=reserveUsernameSecure;
  window.lunoOpenUsernameChangeSecure=openUsernameChangeSecure;
  window.canClaimDailyReward=canClaimDailyRewardSecure;
  window.claimDailyReward=claimDailyRewardSecure;
  window.claimMission=claimMissionRewardSecure;
  window.claimAchievement=claimAchievementRewardSecure;
  window.claimPassReward=claimPassRewardSecure;
  window.claimSeasonReward=claimSeasonRewardSecure;
  window.claimSpecialPassMission=claimSocialVisitRewardSecure;
  window.buySkin=buySkinSecure;
  window.buyEmojiPack=buyEmojiSecure;
  window.buyCostume=buyCostumeSecure;
  window.buyCostumePack=buyCostumePackSecure;
  window.buyOrEquipPieceSet=buyOrEquipPieceSetSecure;
  window.buyOrEquipOttoman=buyOrEquipOttomanSecure;
  window.confirmBuyPass=buyPassSecure;
  window.buyFrame=buyFrameSecure;
  window.selectProfileFrame=selectProfileFrameSecure;
  window.selectBioFrame=selectBioFrameSecure;
  window.openChest=openChestSecure;
  window.upgradeCard=upgradeCardSecure;
  window.openUsernameChange=openUsernameChangeSecure;
  window.lunoVerifyPurchaseToken=function(payload){return secureApi('/verifyPurchase',payload||{});};
  window.lunoSyncSafePreferences=syncSafePreferences;
  window.reserveUsername=reserveUsernameSecure;

  injectStyles();installSettingsPatch();installSecureSocial();installSecureRanked();
  window.addEventListener('luno:account-updated',function(){requestAnimationFrame(patchAccountSettings);setTimeout(function(){refreshAuthoritativeState().catch(function(){});},250);});
  window.addEventListener('luno:guest-ready',function(){setTimeout(function(){refreshAuthoritativeState().catch(function(){});},1200);});
  setTimeout(function(){
    var instance=auth();
    if(instance&&typeof instance.onAuthStateChanged==='function')instance.onAuthStateChanged(function(user){
      if(userHasGoogle(user))resumeGoogleLinkSecure(user).catch(function(){});
    });
  },0);
})();
