// www/js/app_loading_media.js
// Dosya Yolu: www/js/app_loading_media.js
// Açıklama: Açılış yükleme ekranı sırasında karakter video URL'lerini düşük
//   maliyetli biçimde ön ısıtan katman. Tam video decode/buffer yapılmaz;
//   bunun yerine varsayılan karakter öne alınır, diğer dosyalar metadata ve
//   düşük öncelikli prefetch ipuçlarıyla hazırlanır.
//
//   Amaç: açılış müziği ve WebGL sahnesiyle video decoder yarışını önlemek,
//   tarayıcı RAM kullanımını sınırlamak ve karakter adımındaki ilk oynatma
//   deneyimini korumaktır.
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

  // Video URL'si için düşük maliyetli tarayıcı önbellek ipucu ekle.
  // Bu yöntem video decoder açmaz; ses/müzik tarafıyla yarış oluşturmaz.
  function addVideoHint(url, highPriority) {
    if (!url) return;

    try {
      var existing = document.querySelector(
        'link[data-mergen-char-video-hint="1"][href="' + url.replace(/"/g, '\\"') + '"]'
      );
      if (existing) return;

      var link = document.createElement("link");
      link.rel = highPriority ? "preload" : "prefetch";
      link.as = "video";
      link.href = url;
      link.setAttribute("data-mergen-char-video-hint", "1");
      document.head.appendChild(link);
    } catch (e) {
      // Ön yükleme ipucu desteklenmiyorsa sessiz geçilir.
    }
  }

  // Tek bir intro videosunu düşük maliyetle ısıt.
  // Varsayılan karakter için ilk kareye kadar, diğerlerinde yalnızca metadata
  // seviyesine kadar gidilir. Video elemanı iş bitince kaldırılır; DOM'da
  // kalıcı gizli decoder bırakılmaz.
  function warmVideo(url, onReady, highPriority) {
    if (!url) {
      onReady();
      return;
    }

    addVideoHint(url, highPriority);

    var done = false;
    var video = document.createElement("video");
    var timeoutId = null;

    function cleanup() {
      if (timeoutId) {
        window.clearTimeout(timeoutId);
        timeoutId = null;
      }

      try {
        video.pause();
        video.removeAttribute("src");
        video.load();
      } catch (e) {}

      if (video.parentNode) {
        video.parentNode.removeChild(video);
      }
    }

    function finishOnce() {
      if (done) return;
      done = true;
      cleanup();
      onReady();
    }

    video.preload = highPriority ? "auto" : "metadata";
    video.muted = true;
    video.playsInline = true;
    video.setAttribute("aria-hidden", "true");
    video.style.cssText = "width:0;height:0;opacity:0;pointer-events:none;";

    if (highPriority) {
      video.addEventListener("loadeddata", finishOnce, { once: true });
    } else {
      video.addEventListener("loadedmetadata", finishOnce, { once: true });
    }

    video.addEventListener("error", finishOnce, { once: true });

    // Video başına kısa emniyet zaman aşımı: boot ekranı medya yüzünden uzamasın.
    timeoutId = window.setTimeout(finishOnce, highPriority ? 3500 : 1800);

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

    // Varsayılan persona öne alınır; diğerleri düşük öncelikli hazırlanır.
    // Tüm URL'ler aynı anda video decoder'a verilmez.
    var primaryUrls = [];
    var secondaryUrls = [];

    function addUnique(target, list) {
      for (var n = 0; n < list.length; n++) {
        if (primaryUrls.indexOf(list[n]) === -1 &&
            secondaryUrls.indexOf(list[n]) === -1) {
          target.push(list[n]);
        }
      }
    }

    for (var i = 0; i < chars.length; i++) {
      var c = chars[i];
      if (c && (c.character === "emre" || c.id === "emre")) {
        addUnique(primaryUrls, collectIntroUrls(c));
      }
    }

    for (var j = 0; j < chars.length; j++) {
      var c2 = chars[j];
      if (c2 && c2.character !== "emre" && c2.id !== "emre") {
        addUnique(secondaryUrls, collectIntroUrls(c2));
      }
    }

    var urls = primaryUrls.concat(secondaryUrls);
    if (urls.length === 0) {
      signalReady("no-videos");
      return;
    }

    var pending = urls.length;
    var cursor = 0;
    var highPriorityCount = Math.min(primaryUrls.length, 2);

    function oneReady() {
      pending -= 1;
      if (pending <= 0) {
        signalReady("metadata-warm");
      }
    }

    function warmNext() {
      if (cursor >= urls.length) return;

      var idx = cursor;
      var highPriority = idx < highPriorityCount;
      cursor += 1;

      warmVideo(urls[idx], function() {
        oneReady();

        // Medya ön ısıtmayı seri ve düşük baskılı tut. Bu, açılış müziğinde
        // cızırtı/bozulma oluşturan decoder ve disk I/O çakışmasını engeller.
        window.setTimeout(warmNext, highPriority ? 120 : 220);
      }, highPriority);
    }

    warmNext();
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