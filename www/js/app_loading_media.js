// www/js/app_loading_media.js
// Dosya Yolu: www/js/app_loading_media.js
// Açıklama: Açılış yükleme ekranı sırasında TÜM karakter (persona) intro
//   videolarını önceden yükleyen katman. Amaç: kullanıcı yükleme
//   animasyonunu izlerken karakter videolarının tarayıcı önbelleğine
//   ısıtılması; böylece deep-space sahnesine geçildiğinde ve Bütünleşik
//   mod karakter adımına gelindiğinde varsayılan persona (emre) dahil
//   tüm persona intro videoları gecikmesiz oynar.
//
//   Akış:
//     1. Shiny bağlandığında "explore_request_all_char_videos" gönderilir.
//     2. Server "loadExploreAllCharVideos" ile tüm persona video URL'lerini
//        döner (R/module_startup_screen.R içindeki mevcut observer).
//     3. Her personanın TÜM intro videoları gizli <video preload="auto">
//        ile tamponlanır (varsayılan persona 'emre' önce sıraya alınır).
//        Oynatma sırasında intro listesinden rastgele biri seçildiği için
//        tek bir video değil, intro listesinin tamamı ısıtılır.
//     4. Tüm videolar hazır olunca (ya da emniyet zaman aşımında)
//        "character_media_preload_ready" gönderilir; bu da boot kontrol
//        noktası "character_media_ready" olarak işaretlenir.
//
//   Bu dosya R/module_app_loading.R tarafından açılış katmanına satır içi
//   gömülür; bilinçli olarak normal UI varlık manifestine eklenmez.

(function () {
  "use strict";

  var requested = false;
  var signaled = false;
  var installAttempts = 0;
  var requestAttempts = 0;

  // Boot kontrol noktasını yalnızca bir kez işaretle.
  function signalReady(reason) {
    if (signaled) return;
    signaled = true;
    try {
      if (window.Shiny && Shiny.setInputValue) {
        Shiny.setInputValue(
          "character_media_preload_ready",
          { ts: Date.now(), reason: reason || "ok" },
          { priority: "event" }
        );
      }
    } catch (e) {}
  }

  // intro alanı dizi ya da tekil string olabilir (jsonlite auto_unbox).
  // Personanın TÜM intro video URL'lerini döndürür.
  function collectIntroUrls(charData) {
    if (!charData || !charData.videos) return [];
    var intro = charData.videos.intro;
    if (!intro) return [];
    if (typeof intro === "string") {
      return intro ? [intro] : [];
    }
    if (Array.isArray(intro)) {
      var out = [];
      for (var i = 0; i < intro.length; i++) {
        if (typeof intro[i] === "string" && intro[i]) {
          out.push(intro[i]);
        }
      }
      return out;
    }
    return [];
  }

  // Gizli ön yükleme tutucusunu döndür (gerekirse oluştur).
  function preloadHolder() {
    var holder = document.getElementById("mergen-char-media-preload");
    if (!holder) {
      holder = document.createElement("div");
      holder.id = "mergen-char-media-preload";
      holder.style.cssText =
        "position:absolute;width:0;height:0;overflow:hidden;opacity:0;pointer-events:none;";
      document.body.appendChild(holder);
    }
    return holder;
  }

  // Tek bir intro videosunu gerçek <video> ile tamponla. onReady tam
  // tampon (canplaythrough), ilk kare + kısa bekleme, hata ya da emniyet
  // zaman aşımında en fazla bir kez çağrılır. Video DOM'da kalır; böylece
  // arka planda tamponlanmaya devam eder ve önbellek sıcak kalır.
  function warmVideo(url, onReady) {
    if (!url) {
      onReady();
      return;
    }

    var done = false;
    function finishOnce() {
      if (done) return;
      done = true;
      onReady();
    }

    var video = document.createElement("video");
    video.preload = "auto";
    video.muted = true;
    video.playsInline = true;
    video.style.cssText = "width:0;height:0;opacity:0;";
    video.addEventListener("canplaythrough", finishOnce);
    video.addEventListener("loadeddata", function () {
      window.setTimeout(finishOnce, 1800);
    });
    video.addEventListener("error", finishOnce);
    // Video başına emniyet zaman aşımı (yavaş ağ).
    window.setTimeout(finishOnce, 7500);
    video.src = url;
    preloadHolder().appendChild(video);
  }

  function handleCharacterVideos(data) {
    var chars = data && data.characters ? data.characters : [];
    if (!Array.isArray(chars)) {
      chars = chars ? [chars] : [];
    }
    if (chars.length === 0) {
      signalReady("no-characters");
      return;
    }

    // Tüm persona intro URL'lerini topla; varsayılan persona 'emre' öne.
    var urls = [];
    function addUrls(list) {
      for (var n = 0; n < list.length; n++) {
        if (urls.indexOf(list[n]) === -1) {
          urls.push(list[n]);
        }
      }
    }
    for (var i = 0; i < chars.length; i++) {
      var c = chars[i];
      if (c && (c.character === "emre" || c.id === "emre")) {
        addUrls(collectIntroUrls(c));
      }
    }
    for (var j = 0; j < chars.length; j++) {
      var c2 = chars[j];
      if (c2 && c2.character !== "emre" && c2.id !== "emre") {
        addUrls(collectIntroUrls(c2));
      }
    }

    if (urls.length === 0) {
      signalReady("no-videos");
      return;
    }

    // Tüm videolar tamponlanınca kontrol noktasını işaretle.
    var pending = urls.length;
    function oneReady() {
      pending -= 1;
      if (pending <= 0) {
        signalReady("all-warm");
      }
    }
    for (var k = 0; k < urls.length; k++) {
      warmVideo(urls[k], oneReady);
    }
  }

  function requestCharacterVideos() {
    if (requested) return;
    if (!window.Shiny || !Shiny.setInputValue) {
      requestAttempts += 1;
      if (requestAttempts < 120) {
        window.setTimeout(requestCharacterVideos, 60);
      }
      return;
    }
    requested = true;
    try {
      Shiny.setInputValue(
        "explore_request_all_char_videos",
        { ts: Date.now(), nonce: Math.random() },
        { priority: "event" }
      );
    } catch (e) {}
    // Veri/medya hiç gelmezse boot ekranı takılmasın: emniyet zaman aşımı.
    window.setTimeout(function () {
      signalReady("request-timeout");
    }, 11000);
  }

  function installHandler() {
    if (!window.Shiny || !Shiny.addCustomMessageHandler) {
      installAttempts += 1;
      if (installAttempts < 200) {
        window.setTimeout(installHandler, 50);
      }
      return;
    }
    if (window.__mergenCharMediaHandlerInstalled) return;
    window.__mergenCharMediaHandlerInstalled = true;
    Shiny.addCustomMessageHandler("loadExploreAllCharVideos", handleCharacterVideos);
  }

  installHandler();

  // Talep, ilk Shiny flush turundan SONRA gönderilmelidir. Server tarafındaki
  // observeEvent(input$explore_request_all_char_videos, ignoreInit = TRUE)
  // ilk turda input'u NULL görmeli; aksi halde değer ilk flush'ta gelir,
  // ignoreInit atlar ve observer hiç tetiklenmez. shiny:sessioninitialized
  // ilk flush tamamlandıktan sonra tetiklendiği için güvenlidir.
  document.addEventListener("shiny:sessioninitialized", function () {
    requestCharacterVideos();
  });

  // Betik geç yüklenip oturum zaten kurulduysa kısa gecikmeyle talep et
  // (yine ilk flush sonrası olması için).
  if (window.Shiny && Shiny.shinyapp && Shiny.shinyapp.$socket) {
    window.setTimeout(requestCharacterVideos, 400);
  }
})();