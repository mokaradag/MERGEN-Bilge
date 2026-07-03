// www/js/app_loading.js
// Dosya Yolu: www/js/app_loading.js
// Açıklama: Açılış yükleme ekranı denetleyicisi. Gerçek boot olaylarını
//   (Shiny bağlantısı, kimlik doğrulama, oturum kurulumu, dosya/sohbet/medya
//   hazırlığı) kontrol noktası olarak izler, yedigen ilerleme halkasını
//   0'dan 100'e MONOTON ve saat yönünde doldurur, yüzde göstergesini
//   günceller, akan kod katmanını başlatır ve karşılama ekranı varlıklarını
//   önceden yükler.
//
//   Önemli: İlerleme yalnızca server tarafından gönderilen
//   "bootReadinessCheckpoint" mesajlarıyla ilerler ve YALNIZCA tüm zorunlu
//   kontrol noktaları tamamlandığında (ready=true) %100'e ulaşıp kapanır.
//   Böylece ekran erken kapanmaz; deep-space sahnesine geçildiğinde dosyalar,
//   son konuşmalar ve karakter medyası gerçekten hazırdır.
//
//   Bu dosya R/module_app_loading.R tarafından satır içine gömülür; bu
//   nedenle harici varlıklar yüklenmeden önce çalışır.

(function () {
  "use strict";

  var overlay = document.getElementById("app-loading-overlay");
  if (!overlay) return;

  // Aşamalar: her anahtar gerçek bir boot kontrol noktasıdır. Yüzdeler
  // yalnızca artar; ilerleme asla geri gitmez. Sıralama, kontrol
  // noktalarının tipik tamamlanma sırasına göredir. En yavaş ve en maliyetli
  // adım karakter/karşılama medyasının TAM tamponlanmasıdır; bu nedenle
  // file_index_ready (32) ile character_media_ready (96) arasındaki geniş bant
  // gerçek medya tamponlama ilerlemesiyle (reportMediaProgress) sürülür. Böylece
  // çubuk gerçek işi yansıtır; sahte/yapay animasyon yoktur.
  var STAGES = [
    { key: "boot", label: "Başlatılıyor", pct: 5 },
    { key: "connect", label: "Bağlantı kuruluyor", pct: 12 },
    { key: "auth_ready", label: "Kimlik doğrulandı", pct: 20 },
    { key: "saved_chats_preview_ready", label: "Son konuşmalar hazırlanıyor", pct: 26 },
    { key: "file_index_ready", label: "Dosyalar hazırlanıyor", pct: 32 },
    { key: "welcome_client_ready", label: "Görsel bileşenler başlatılıyor", pct: 44 },
    { key: "character_media_ready", label: "Asistan medyası hazırlanıyor", pct: 96 },
    { key: "ready", label: "Hazır", pct: 99 }
  ];

  // Gerçek medya tamponlama bandı: bu iki aşamanın yüzdesi arasında
  // reportMediaProgress(0..1) ile pürüzsüzce dolar.
  function stagePct(key, fallback) {
    for (var i = 0; i < STAGES.length; i++) {
      if (STAGES[i].key === key) return STAGES[i].pct;
    }
    return fallback;
  }

  // Hızlı Başlangıç (fast_lane) yüzde planı: ilerleme yalnızca sohbet
  // kabuğunun hazır olmasını temsil eder. Kayıtlı sohbetler, dosya indeksi
  // ve medya tamponlama bu sözleşmenin parçası değildir (arka planda sürer).
  var FAST_LANE_PCT = {
    boot: 8,
    connect: 26,
    auth_ready: 60,
    saved_chats_preview_ready: 68,
    file_index_ready: 74,
    welcome_client_ready: 92,
    ready: 99
  };

  // Hızlı şeritte açılış katmanının kapanması için gereken kontrol
  // noktaları. R/helpers_startup_lane.R içindeki
  // mergen_fast_lane_required_boot_keys() ile aynı olmalıdır.
  var FAST_LANE_REQUIRED = ["connect", "auth_ready", "welcome_client_ready"];

  var stageIndex = -1;
  var finished = false;
  var fadeStarted = false;
  var ssoActive = false;
  var skipIntro = false;
  var seenKeys = {};
  var lastStageLabel = "Başlatılıyor";

  function laneApi() {
    return window.MergenStartupLane || null;
  }

  function isFastLane() {
    var api = laneApi();
    return !!(api && typeof api.isFast === "function" && api.isFast());
  }

  function laneSelectorOpen() {
    var api = laneApi();
    return !!(api && typeof api.isSelectorOpen === "function" && api.isSelectorOpen());
  }

  // İlerleme durumu: displayPct her zaman targetPct'e doğru ilerler ve
  // asla azalmaz. targetPct yalnızca aşamalarla veya finish() ile artar.
  var displayPct = 0;
  var targetPct = 0;
  var rafId = null;

  // Stall (takılma) izleme: gerçek ilerleme oldukça zaman damgası tazelenir.
  // Emniyet kapanışı artık MUTLAK bir 22 sn değil; "22 sn boyunca HİÇ ilerleme
  // olmazsa" tetiklenen bir gözcüdür. Böylece tüm karakter/karşılama videoları
  // tamponlanırken uzun ama GERÇEK ilerleme erken kapanışla kesilmez.
  var lastProgressTs = Date.now();
  function markProgress() {
    lastProgressTs = Date.now();
  }

  var statusText = overlay.querySelector(".alo-status-text");
  var readoutNum = overlay.querySelector(".alo-readout-num");
  var progressHept = document.getElementById("alo-progress-hept");

  // Giriş animasyonu tercihini oku
  try {
    var raw = localStorage.getItem("mergen_settings");
    if (raw) {
      var parsed = JSON.parse(raw);
      skipIntro = !!(parsed && parsed.skip_intro === true);
    }
  } catch (e) {}
  if (skipIntro) {
    document.documentElement.classList.add("mergen-skip-intro");
  }

  // İlerleme yedigeni pathLength="100" ile ölçeklenir: stroke-dashoffset
  // 100 -> boş, 0 -> tam çevre. Köşeler saat yönünde sıralı olduğundan
  // halka tepeden başlayarak saat yönünde dolar.
  function applyProgress() {
    var p = displayPct < 0 ? 0 : (displayPct > 100 ? 100 : displayPct);
    if (progressHept) {
      progressHept.style.strokeDashoffset = String(100 - p);
    }
    if (readoutNum) {
      readoutNum.textContent = String(Math.round(p));
    }
  }

  // Tek bir requestAnimationFrame karesi: hedefe doğru yumuşak ilerle.
  function progressFrame() {
    var diff = targetPct - displayPct;

    if (diff <= 0.05) {
      displayPct = targetPct;
      applyProgress();
      rafId = null;
      // Ekran ancak yedigen tam %100 dolduktan sonra erimeye başlar.
      if (finished && displayPct >= 99.95 && !fadeStarted) {
        fadeStarted = true;
        window.setTimeout(function () {
          overlay.classList.add("app-loading-hidden");
          window.setTimeout(function () {
            if (overlay) overlay.style.display = "none";
            cleanup();
          }, 760);
        }, 470);
      }
      return;
    }

    // finish() sonrası daha hızlı; ayrıca minimum adım asimptotik takılmayı
    // önler, böylece %100'e kesin olarak ulaşılır.
    var ease = finished ? 0.16 : 0.075;
    var minStep = finished ? 0.65 : 0.14;
    var step = diff * ease;
    if (step < minStep) {
      step = minStep;
    }
    if (step > diff) {
      step = diff;
    }
    displayPct += step;
    if (displayPct > targetPct) {
      displayPct = targetPct;
    }
    applyProgress();
    rafId = window.requestAnimationFrame(progressFrame);
  }

  // Hedefi yalnızca ileri al (monoton garanti) ve gerekiyorsa rAF ilerleme
  // döngüsünü uyandır. Döngü hedefe ulaşınca progressFrame içinde durur.
  function setTarget(pct) {
    if (pct > targetPct) {
      targetPct = pct > 100 ? 100 : pct;
      markProgress();
      if (rafId === null && displayPct < targetPct) {
        rafId = window.requestAnimationFrame(progressFrame);
      }
    }
  }

  // Gerçek medya tamponlama ilerlemesini (0..1) çubuğa yansıt. app_loading_media.js
  // her video HTTP önbelleğine tam ısıtıldıkça bu fonksiyonu çağırır. Hedef
  // yalnızca ileri alındığı için (setTarget monoton) çubuk asla geri gitmez.
  // done/total sayaçları verildiğinde uzun medya aşaması "4 / 12" biçiminde
  // gerçek alt-ilerleme metniyle gösterilir (Zengin Deneyim şeffaflığı).
  function reportMediaProgress(fraction, done, total) {
    if (typeof fraction !== "number" || isNaN(fraction)) return;
    if (fraction < 0) fraction = 0;
    if (fraction > 1) fraction = 1;

    // Hızlı şeritte medya tamponlaması ilerleme sözleşmesinin parçası
    // değildir; çubuk sohbet hazırlık aşamalarıyla sürülür.
    if (isFastLane()) return;

    var bandStart = stagePct("file_index_ready", 32);
    var bandEnd = stagePct("character_media_ready", 96);
    setTarget(bandStart + (bandEnd - bandStart) * fraction);

    // Medya tamponlama sürerken durum etiketini bu adıma sabitle. Bu noktada
    // erken aşama etiketleri (auth/dosya) zaten geçmiş olduğundan titreme olmaz.
    if (statusText && !finished && fraction > 0 && fraction < 1) {
      var label = "Sinematik ve persona medyası hazırlanıyor";
      if (typeof done === "number" && typeof total === "number" &&
          isFinite(done) && isFinite(total) && total > 0) {
        label += " · " + Math.min(done, total) + " / " + total;
      }
      lastStageLabel = label;
      statusText.textContent = label;
    }
  }

  // Hızlı şeritte tüm zorunlu kontrol noktaları görüldüyse katmanı kapat.
  // Sunucu ready bayrağı (zengin sözleşme) beklenmez; medya/galeri/dosya
  // indeksi arka planda sürebilir.
  function maybeFinishFastLane() {
    if (finished || !isFastLane()) return;
    for (var i = 0; i < FAST_LANE_REQUIRED.length; i++) {
      if (seenKeys[FAST_LANE_REQUIRED[i]] !== true) return;
    }
    finish();
  }

  function setStage(key) {
    if (key) {
      seenKeys[key] = true;
    }

    // Hızlı şeritte yalnızca hızlı plan (FAST_LANE_PCT) aşamaları yüzde/etiket
    // ilerletir. Ertelenen medya kontrol noktası (character_media_ready,
    // sunucu 'deferred' işareti) gibi plan dışı anahtarlar kaydedilir ama
    // çubuğu zengin medya bandına (~%96) sıçratamaz ve stageIndex'i sohbet
    // kabuğu aşamalarının önüne geçiremez; hızlı ilerleme sohbet hazırlığını
    // temsil etmeye devam eder.
    if (isFastLane() && typeof FAST_LANE_PCT[key] !== "number") {
      markProgress();
      maybeFinishFastLane();
      return;
    }

    var idx = -1;
    for (var i = 0; i < STAGES.length; i++) {
      if (STAGES[i].key === key) {
        idx = i;
        break;
      }
    }
    // Bilinmeyen veya geriye dönük aşamalar yok sayılır (monoton ilerleme).
    if (idx < 0 || idx <= stageIndex || finished) {
      maybeFinishFastLane();
      return;
    }
    stageIndex = idx;
    // Hızlı şeritte yüzde planı sohbet hazırlığını temsil eder; zengin
    // şeritte mevcut medya-bantlı plan korunur. setTarget monoton olduğu
    // için şerit geç çözülse bile çubuk asla geri gitmez.
    var pct = STAGES[idx].pct;
    if (isFastLane() && typeof FAST_LANE_PCT[key] === "number") {
      pct = FAST_LANE_PCT[key];
    }
    setTarget(pct);
    if (statusText) {
      statusText.classList.add("alo-status-fade");
      window.setTimeout(function () {
        lastStageLabel = STAGES[idx].label;
        statusText.textContent = STAGES[idx].label;
        statusText.classList.remove("alo-status-fade");
      }, 200);
    }
    maybeFinishFastLane();
  }

  // Server tarafı boot kontrol noktası mesajlarını dinle. İlerleme tamamen
  // bu mesajlarla sürülür; ekran ancak ready=true geldiğinde kapanır.
  function installBootReadinessHandler() {
    if (!window.Shiny || !Shiny.addCustomMessageHandler) {
      window.setTimeout(installBootReadinessHandler, 50);
      return;
    }

    if (window.__mergenBootReadinessHandlerInstalled) return;
    window.__mergenBootReadinessHandlerInstalled = true;

    Shiny.addCustomMessageHandler("bootReadinessCheckpoint", function (msg) {
      if (!msg || !msg.key) return;

      // Her gerçek kontrol noktası ilerleme etkinliği sayılır (stall gözcüsü).
      markProgress();

      setStage(msg.key);

      if (msg.ready === true) {
        setStage("ready");
        window.setTimeout(finish, 260);
      }
    });
  }

  // Şerit çözüldüğünde (özellikle seçici üzerinden geç seçimde) hızlı şerit
  // kapanış kontrolü yeniden değerlendirilir; seçim de gerçek ilerlemedir.
  function installLaneResolutionHook() {
    var api = laneApi();
    if (!api || typeof api.whenResolved !== "function") return;
    api.whenResolved(function () {
      markProgress();
      maybeFinishFastLane();
    });
  }

  function cleanup() {
    if (rafId !== null) {
      window.cancelAnimationFrame(rafId);
      rafId = null;
    }
    try {
      if (window.MergenLoadingCodestream) {
        window.MergenLoadingCodestream.stop();
      }
    } catch (e) {}
    var holder = overlay.querySelector(".alo-preload");
    if (holder && holder.parentNode) {
      holder.parentNode.removeChild(holder);
    }
  }

  function finish() {
    if (finished) return;
    finished = true;
    overlay.classList.add("alo-complete");
    if (statusText) {
      statusText.textContent = "Hazır";
    }
    // Giriş atlandıysa (veya Hızlı Başlangıç şeridi aktifse) derin uzay intro
    // müziği karşılama ekranına devretmeden burada yumuşakça durdurulur.
    if (skipIntro || isFastLane()) {
      try {
        if (window.SpaceIntroMusic) {
          window.SpaceIntroMusic.fadeOutAndStop();
        }
      } catch (e) {}
    }
    // İlerleme kesin olarak %100'e sürülür; ekran yalnızca yedigen tamamen
    // dolduktan sonra progressFrame içinden eritilir.
    setTarget(100);
    if (rafId === null && displayPct < targetPct) {
      rafId = window.requestAnimationFrame(progressFrame);
    }
  }

  // SSO etkinse yalnızca kimlik doğrulama HATASINI izle: hata ekranı
  // gösterildiğinde yükleme katmanını kapat ki kullanıcı hatayı görebilsin.
  function startSsoWatch() {
    var ssoTimer = window.setInterval(function () {
      if (finished) {
        window.clearInterval(ssoTimer);
        return;
      }
      var ssoErr = document.getElementById("sso_module-sso_error");
      if (ssoErr && window.getComputedStyle(ssoErr).display !== "none") {
        window.clearInterval(ssoTimer);
        finish();
      }
    }, 200);
  }

  function detectSso() {
    try {
      var cfgEl = document.getElementById("sso_module-sso_config_data");
      if (cfgEl) {
        var cfg = JSON.parse(cfgEl.textContent || "{}");
        ssoActive = !!(cfg && cfg.enabled);
      }
    } catch (e) {}

    if (ssoActive) {
      startSsoWatch();
    }
  }

  function extractSsoTokenFromHashForBoot() {
    var hash = window.location.hash || "";
    if (hash.length < 2) return null;

    var parts = hash.substring(1).split("&");
    for (var i = 0; i < parts.length; i++) {
      var kv = parts[i].split("=");
      if (kv.length >= 2 && decodeURIComponent(kv[0]) === "access_token") {
        return decodeURIComponent(kv.slice(1).join("="));
      }
    }
    return null;
  }

  function getStoredSsoTokenForBoot() {
    try {
      return localStorage.getItem("mergen_bilge_jwt_token");
    } catch (e) {
      return null;
    }
  }

  function isSsoTokenExpiredForBoot(token) {
    try {
      var parts = String(token || "").split(".");
      if (parts.length !== 3) return true;

      var payload = parts[1].replace(/-/g, "+").replace(/_/g, "/");
      while (payload.length % 4 !== 0) {
        payload += "=";
      }

      var decoded = JSON.parse(atob(payload));
      if (!decoded.exp) return false;

      return Math.floor(Date.now() / 1000) >= decoded.exp;
    } catch (e) {
      return true;
    }
  }

  function isSsoPreAuthRedirectPass() {
    // R/module_sso.R içindeki ssoPreflightScriptUI zaten yönlendirme başlattıysa
    // bu sayfa boot ilerlemesini hiç başlatmamalıdır.
    if (window.__mergenSsoPreflightRedirecting === true) {
      return true;
    }

    try {
      var cfgEl = document.getElementById("sso_module-sso_config_data");
      if (!cfgEl) return false;

      var cfg = JSON.parse(cfgEl.textContent || "{}");
      if (!cfg || cfg.enabled !== true) return false;

      var token = extractSsoTokenFromHashForBoot() || getStoredSsoTokenForBoot();
      if (token && !isSsoTokenExpiredForBoot(token)) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  function holdForSsoPreAuthRedirect() {
    // Bu geçiş gerçek uygulama başlangıcı değildir; Keycloak'a giden
    // kimlik doğrulama sıçramasıdır. Bu nedenle yüzde ilerlemesi verilmez.
    if (statusText) {
      statusText.textContent = "Kimlik doğrulama yönlendiriliyor";
    }
    applyProgress();
  }

  // NOT: Karşılama sinematik arka plan videolarının ve tüm persona intro
  // videolarının ön yüklemesi artık tek yetkili medya ön yükleyici olan
  // www/js/app_loading_media.js içinde yapılır (TAM tampon + gerçek ilerleme).
  // Burada ayrıca metadata ısıtması yapılmaz; aksi halde aynı dosyalar için
  // çift indirme/decoder baskısı oluşurdu.

  function boot() {
    if (isSsoPreAuthRedirectPass()) {
      holdForSsoPreAuthRedirect();
      return;
    }

    setStage("boot");
    installBootReadinessHandler();
    installLaneResolutionHook();

    if (window.MergenLoadingCodestream) {
      var stream = overlay.querySelector(".alo-codestream");
      if (stream) {
        window.MergenLoadingCodestream.start(stream);
      }
    }

    detectSso();
  }

  // Uzun süren gerçek aşamalarda ekran "donmuş" görünmesin: 6 sn boyunca
  // yeni kontrol noktası gelmezse mevcut aşama etiketine hareketli üç nokta
  // eklenir. Bu sahte ilerleme DEĞİLDİR; yüzde değişmez, yalnızca aktif
  // çalışma görünür kılınır.
  var waitingDots = 0;
  var waitingTimer = window.setInterval(function () {
    if (finished) {
      window.clearInterval(waitingTimer);
      return;
    }
    if (!statusText || laneSelectorOpen()) return;
    if ((Date.now() - lastProgressTs) <= 6000) return;

    waitingDots = (waitingDots + 1) % 4;
    var dots = new Array(waitingDots + 1).join(".");
    statusText.textContent = lastStageLabel + " · sürüyor" + dots;
  }, 900);

  // Dış denetim yüzeyi (küçük tutulur). reportMediaProgress, app_loading_media.js
  // tarafından gerçek video tamponlama ilerlemesini çubuğa yansıtmak için çağrılır.
  window.MergenAppLoading = {
    finish: finish,
    setStage: setStage,
    reportMediaProgress: reportMediaProgress
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }

  document.addEventListener("shiny:connected", function () {
    setStage("connect");
  });

  document.addEventListener("shiny:disconnected", function () {
    finish();
  });

  // Güvenlik gözcüsü (stall watchdog): ekran, GERÇEK ilerleme oldukça açık
  // kalır. Yalnızca 22 sn boyunca HİÇBİR ilerleme (aşama, kontrol noktası veya
  // medya tamponlama) olmazsa son çare olarak kapatılır. Ayrıca mutlak bir üst
  // sınır (180 sn) hiçbir koşulda sonsuza dek takılı kalınmamasını garanti eder.
  // Bu, "yükleme %100 = her şey gerçekten hazır" hedefiyle uyumludur: tüm
  // karakter/karşılama videoları tamponlanırken uzun ama gerçek ilerleme erken
  // kapanışla kesilmez.
  var STALL_MS = 22000;
  var HARD_CAP_MS = 180000;
  var watchdogStart = Date.now();
  var watchdogTimer = window.setInterval(function () {
    if (finished) {
      window.clearInterval(watchdogTimer);
      return;
    }
    // İlk açılış şerit seçicisi açıkken kullanıcı karar veriyordur; gözcü
    // sayaçları tazelenir ki seçici altında katman kendiliğinden kapanmasın.
    if (laneSelectorOpen()) {
      lastProgressTs = Date.now();
      watchdogStart = Date.now();
      return;
    }
    var now = Date.now();
    if ((now - lastProgressTs) > STALL_MS || (now - watchdogStart) > HARD_CAP_MS) {
      window.clearInterval(watchdogTimer);
      finish();
    }
  }, 1000);
})();