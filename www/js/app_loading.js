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
  // noktalarının tipik tamamlanma sırasına göredir; en yavaş olan
  // (karakter medyası) sona yakın konumlandırılır ki çubuk pürüzsüz aksın.
  var STAGES = [
    { key: "boot", label: "Başlatılıyor", pct: 6 },
    { key: "connect", label: "Bağlantı kuruluyor", pct: 18 },
    { key: "auth_ready", label: "Kimlik doğrulandı", pct: 32 },
    { key: "saved_chats_preview_ready", label: "Son konuşmalar hazırlanıyor", pct: 46 },
    { key: "file_index_ready", label: "Dosyalar hazırlanıyor", pct: 60 },
    { key: "welcome_client_ready", label: "Görsel bileşenler başlatılıyor", pct: 74 },
    { key: "character_media_ready", label: "Asistan medyası hazırlanıyor", pct: 91 },
    { key: "ready", label: "Hazır", pct: 99 }
  ];

  var stageIndex = -1;
  var finished = false;
  var fadeStarted = false;
  var ssoActive = false;
  var skipIntro = false;

  // İlerleme durumu: displayPct her zaman targetPct'e doğru ilerler ve
  // asla azalmaz. targetPct yalnızca aşamalarla veya finish() ile artar.
  var displayPct = 0;
  var targetPct = 0;
  var rafId = null;

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
      if (rafId === null && displayPct < targetPct) {
        rafId = window.requestAnimationFrame(progressFrame);
      }
    }
  }

  function setStage(key) {
    var idx = -1;
    for (var i = 0; i < STAGES.length; i++) {
      if (STAGES[i].key === key) {
        idx = i;
        break;
      }
    }
    // Bilinmeyen veya geriye dönük aşamalar yok sayılır (monoton ilerleme).
    if (idx < 0 || idx <= stageIndex || finished) return;
    stageIndex = idx;
    setTarget(STAGES[idx].pct);
    if (statusText) {
      statusText.classList.add("alo-status-fade");
      window.setTimeout(function () {
        statusText.textContent = STAGES[idx].label;
        statusText.classList.remove("alo-status-fade");
      }, 200);
    }
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

      setStage(msg.key);

      if (msg.ready === true) {
        setStage("ready");
        window.setTimeout(finish, 260);
      }
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
    // Giriş atlandıysa derin uzay intro müziği karşılama ekranına devretmeden
    // burada yumuşakça durdurulur (uygulama arka plan müziğine geçiş).
    if (skipIntro) {
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

  // Karşılama ekranı sinematik arka plan videolarını önceden yükle (tarayıcı
  // önbelleği ısıtılır; karşılama ekranı görseli gecikmesiz başlar). Eksik
  // dosyalar sessizce yok sayılır. Karakter persona videoları ayrı dosya
  // www/js/app_loading_media.js tarafından önceden yüklenir.
  function preloadWelcomeMedia() {
    var holder = document.createElement("div");
    holder.className = "alo-preload";
    holder.style.cssText =
      "position:absolute;width:0;height:0;overflow:hidden;opacity:0;pointer-events:none;";

    for (var i = 1; i <= 6; i++) {
      (function (index) {
        window.setTimeout(function () {
          if (finished) return;
          var video = document.createElement("video");
          video.preload = "auto";
          video.muted = true;
          video.playsInline = true;
          video.addEventListener("error", function () {
            if (video.parentNode) video.parentNode.removeChild(video);
          });
          video.src = "videos/cinematic/video" + index + ".mp4";
          holder.appendChild(video);
        }, index * 240);
      })(i);
    }

    overlay.appendChild(holder);
  }

  function boot() {
    if (isSsoPreAuthRedirectPass()) {
      holdForSsoPreAuthRedirect();
      return;
    }

    setStage("boot");
    installBootReadinessHandler();

    if (window.MergenLoadingCodestream) {
      var stream = overlay.querySelector(".alo-codestream");
      if (stream) {
        window.MergenLoadingCodestream.start(stream);
      }
    }

    window.setTimeout(preloadWelcomeMedia, 650);
    detectSso();
  }

  // Dış denetim yüzeyi
  window.MergenAppLoading = { finish: finish, setStage: setStage };

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

  // Güvenlik zaman aşımı: hiçbir kontrol noktası tamamlanmazsa 22 sn sonra
  // ekranı yine de kapat (boot kontrol noktaları normalde çok daha hızlı
  // tamamlanır; bu yalnızca son çare backstop'tur).
  window.setTimeout(function () {
    finish();
  }, 22000);
})();