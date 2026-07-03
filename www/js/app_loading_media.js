// www/js/app_loading_media.js
// Dosya Yolu: www/js/app_loading_media.js
// Açıklama: Açılış yükleme ekranı sırasında karşılama arka plan videolarını ve
//   TÜM personaların intro videolarını tarayıcı HTTP önbelleğine TAM olarak
//   ısıtan tek yetkili medya ön yükleyici. Daha önce bu sorumluluk hem bu
//   dosyada (yalnızca metadata) hem de www/js/explore_media_preload.js içinde
//   (tam tampon) ayrı ayrı vardı; iki ayrı Shiny mesaj işleyicisi aynı
//   "loadExploreAllCharVideos" adını kaydettiği için hangisinin kazanacağı
//   yükleme sırasına bağlı bir yarış durumuydu. Bu dosya artık tek yetkili
//   ön yükleyicidir; explore_media_preload.js kaldırılmıştır.
//
//   Strateji (kullanıcı isteği: "%100 = her şey hazır"):
//     - Videolar SERİ (sıralı) biçimde, her seferinde bir tane ısıtılır;
//       böylece açılış müziğiyle decoder/disk I/O çakışması en aza iner.
//     - Her video için "canplaythrough" beklenir (kesintisiz oynatılabilir);
//       ardından gizli <video> elemanı KALDIRILIR. İndirilen baytlar tarayıcı
//       HTTP önbelleğinde kalır, ancak bellekte canlı bir decoder bırakılmaz.
//       Böylece gerçek oynatma anında (karşılama arka planı veya Bütünleşik
//       karakter adımı) video önbellekten anında başlar.
//     - İlerleme, app_loading.js'deki ilerleme çubuğuna GERÇEK olarak yansıtılır
//       (window.MergenAppLoading.reportMediaProgress). Sahte/yapay animasyon yok.
//     - character_media_ready kontrol noktası YALNIZCA tüm bilinen videolar
//       tamponlandıktan sonra bildirilir; böylece %100, medyanın gerçekten
//       hazır olduğu an demektir.
//
//   Bu dosya R/module_app_loading.R tarafından açılış katmanına satır içi
//   gömülür; bilinçli olarak normal UI varlık manifestine eklenmez.

(function () {
  "use strict";

  // Karşılama ekranı sinematik arka plan videoları. www/js/welcome_video_player.js
  // içindeki VIDEO_URLS ile aynı liste olmalıdır; bu sayede karşılama arka planı
  // %100'de önbellekten anında oynar.
  var WELCOME_BG_URLS = [
    "videos/cinematic/video1.mp4",
    "videos/cinematic/video2.mp4",
    "videos/cinematic/video3.mp4",
    "videos/cinematic/video4.mp4",
    "videos/cinematic/video5.mp4",
    "videos/cinematic/video6.mp4",
    "videos/cinematic/video7.mp4",
    "videos/cinematic/video8.mp4",
    "videos/cinematic/video9.mp4",
    "videos/cinematic/video10.mp4"
  ];

  var requested = false;
  var signaled = false;
  var charDataReceived = false;
  var installAttempts = 0;
  var requestAttempts = 0;

  // Seri tampon kuyruğu durumu
  var knownSet = {};       // url -> true (kuyruğa eklendi)
  var queue = [];          // bekleyen url'ler
  var bufferedCount = 0;   // tamamlanan url sayısı
  var totalKnown = 0;      // bilinen toplam url
  var draining = false;
  var holder = null;

  function preloadHolder() {
    if (!holder || !document.body.contains(holder)) {
      holder = document.getElementById("mergen-char-media-preload");
      if (!holder) {
        holder = document.createElement("div");
        holder.id = "mergen-char-media-preload";
        holder.style.cssText =
          "position:absolute;width:0;height:0;overflow:hidden;opacity:0;pointer-events:none;";
        document.body.appendChild(holder);
      }
    }
    return holder;
  }

  // İlerleme çubuğuna gerçek medya ilerlemesini bildir (0..1). Karakter listesi
  // henüz gelmeden yalnızca arka plan videoları sayıldığında bandın tamamını
  // doldurup yanıltıcı erken %100 oluşturmamak için fraksiyon sınırlandırılır.
  // done/total sayaçları da iletilir; açılış ekranı uzun medya aşamasını
  // "4 / 12" biçiminde gerçek alt-ilerleme metniyle gösterir.
  function reportProgress() {
    var denom = totalKnown > 0 ? totalKnown : 1;
    var frac = bufferedCount / denom;
    if (!charDataReceived) {
      frac = Math.min(frac, 1) * 0.4;
    } else if (frac > 1) {
      frac = 1;
    }
    try {
      if (window.MergenAppLoading &&
          typeof window.MergenAppLoading.reportMediaProgress === "function") {
        window.MergenAppLoading.reportMediaProgress(frac, bufferedCount, totalKnown);
      }
    } catch (e) {}
  }

  // Boot kontrol noktasını yalnızca bir kez işaretle.
  function signalReady(reason) {
    if (signaled) return;
    signaled = true;
    reportProgress();
    try {
      if (window.Shiny && Shiny.setInputValue) {
        Shiny.setInputValue(
          "character_media_preload_ready",
          {
            ts: Date.now(),
            reason: reason || "ok",
            buffered: bufferedCount,
            total: totalKnown
          },
          { priority: "event" }
        );
      }
    } catch (e) {}
  }

  // Tek bir videoyu HTTP önbelleğine TAM olarak ısıt. canplaythrough = kesintisiz
  // oynatılabilecek kadar tamponlandı. İş bittiğinde gizli <video> kaldırılır:
  // indirilen baytlar tarayıcı önbelleğinde kalır, canlı decoder serbest bırakılır.
  function bufferUrl(url, onDone) {
    if (!url) {
      onDone();
      return;
    }

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
      onDone();
    }

    video.preload = "auto";
    video.muted = true;
    video.playsInline = true;
    video.setAttribute("aria-hidden", "true");
    video.style.cssText = "width:0;height:0;opacity:0;pointer-events:none;";

    video.addEventListener("canplaythrough", finishOnce, { once: true });
    video.addEventListener("error", finishOnce, { once: true });
    // Eksik/yavaş tek bir dosya tüm açılışı kilitlemesin: video başına emniyet.
    timeoutId = window.setTimeout(finishOnce, 15000);

    video.src = url;
    preloadHolder().appendChild(video);
    try {
      video.load();
    } catch (e) {}
  }

  function maybeSignalReady() {
    if (signaled) return;
    // Hazır bildirimi yalnızca karakter verisi alındıktan VE kuyruk tamamen
    // boşaldıktan sonra yapılır. Böylece %100, tüm medyanın hazır olduğu andır.
    if (charDataReceived && queue.length === 0 && !draining) {
      signalReady("buffered");
    }
  }

  function drain() {
    if (draining) return;
    if (queue.length === 0) {
      maybeSignalReady();
      return;
    }
    draining = true;
    var url = queue.shift();
    bufferUrl(url, function () {
      bufferedCount += 1;
      reportProgress();
      draining = false;
      // Seri ve düşük baskılı tut: açılış müziği/derin uzay sahnesiyle decoder
      // ve disk I/O çakışmasını azaltmak için kısa bir aralık bırak.
      window.setTimeout(drain, 80);
    });
  }

  function enqueue(urls) {
    if (!urls || !urls.length) return;
    for (var i = 0; i < urls.length; i++) {
      var u = urls[i];
      if (u && knownSet[u] !== true) {
        knownSet[u] = true;
        queue.push(u);
        totalKnown += 1;
      }
    }
    reportProgress();
    drain();
  }

  // intro alanı dizi ya da tekil string olabilir (jsonlite auto_unbox).
  // Personanın TÜM intro video URL'lerini döndürür. (loop/select talep anında
  // akışla yüklenir; kullanıcının seçtiği persona ilk olarak burada hazırlanır.)
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

  function handleCharacterVideos(data) {
    charDataReceived = true;

    var chars = data && data.characters ? data.characters : [];
    if (!Array.isArray(chars)) {
      chars = chars ? [chars] : [];
    }

    // Varsayılan persona (emre) intro'su önce, diğerleri sonra kuyruğa alınır:
    // en olası ilk deneyim önce hazır olur. Tümü %100'den önce tamponlanır.
    var primary = [];
    var secondary = [];
    for (var i = 0; i < chars.length; i++) {
      var c = chars[i];
      var urls = collectIntroUrls(c);
      if (c && (c.character === "emre" || c.id === "emre")) {
        primary = primary.concat(urls);
      } else {
        secondary = secondary.concat(urls);
      }
    }

    enqueue(primary);
    enqueue(secondary);
    maybeSignalReady();
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

    // Karakter verisi hiç gelmezse boot ekranı takılmasın: arka plan videoları
    // yine de tamponlanır ve emniyet süresi sonunda hazır bildirilir.
    window.setTimeout(function () {
      if (!charDataReceived) {
        charDataReceived = true;
        reportProgress();
        maybeSignalReady();
      }
    }, 12000);
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

  // Şerit çözümüne göre başlat: Hızlı Başlangıç'ta ön yükleme tamamen
  // ertelenir ve character_media_ready anında (fast_lane_deferred) bildirilir;
  // zengin şeritte mevcut sıralı tam-tampon davranışı birebir çalışır.
  function startForLane(lane) {
    if (lane === "fast_lane") {
      charDataReceived = true;
      signalReady("fast_lane_deferred");
      return;
    }

    // Bilinen karşılama arka plan videolarını sunucu yanıtını beklemeden hemen
    // ısıtmaya başla. (Karakter intro URL'leri yalnızca sunucudan gelebildiği
    // için onlar loadExploreAllCharVideos yanıtında kuyruğa eklenir.)
    enqueue(WELCOME_BG_URLS);

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
  }

  installHandler();

  if (window.MergenStartupLane &&
      typeof window.MergenStartupLane.whenResolved === "function") {
    // Şerit henüz seçilmediyse (ilk açılış seçicisi) ön yükleme bekletilir;
    // seçim de gerçek açılış kararıdır. Seçimden sonra ilgili yol başlar.
    window.MergenStartupLane.whenResolved(startForLane);
  } else {
    // Şerit API'si yoksa (savunmacı geriye dönük uyum) zengin davranış sürer.
    startForLane("rich_lane");
  }
})();