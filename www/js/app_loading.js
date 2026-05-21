// www/js/app_loading.js
// Dosya Yolu: www/js/app_loading.js
// Açıklama: Açılış yükleme ekranı denetleyicisi. Gerçek boot olaylarını
//   (SSO, Shiny bağlantısı, oturum) izleyerek aşamaları ilerletir,
//   yedigen ilerleme halkasını ve yüzde göstergesini günceller, akan kod
//   katmanını başlatır ve karşılama ekranı varlıklarını önceden yükler.
//   Bu dosya R/module_app_loading.R tarafından satır içine gömülür; bu
//   nedenle harici varlıklar yüklenmeden önce çalışır.

(function () {
  "use strict";

  var overlay = document.getElementById("app-loading-overlay");
  if (!overlay) return;

  // Aşamalar: anahtar -> görünen etiket ve hedef yüzde
  var STAGES = [
    { key: "boot", label: "Başlatılıyor", pct: 12 },
    { key: "connect", label: "Bağlantı kuruluyor", pct: 30 },
    { key: "auth", label: "Kimlik doğrulanıyor", pct: 48 },
    { key: "session", label: "Oturum hazırlanıyor", pct: 66 },
    { key: "workspace", label: "Çalışma alanı hazırlanıyor", pct: 86 },
    { key: "ready", label: "Hazır", pct: 97 }
  ];

  var stageIndex = -1;
  var finished = false;
  var shinyReady = false;
  var ssoActive = false;
  var ssoResolved = false;
  var skipIntro = false;
  var appReadyAt = 0;
  var displayPct = 0;
  var ceilPct = 0;
  var ticker = null;

  var statusText = overlay.querySelector(".alo-status-text");
  var readoutNum = overlay.querySelector(".alo-readout-num");
  var progressHept = document.getElementById("alo-progress-hept");
  var heptLen = 0;

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

  // İlerleme yedigeninin çizgi uzunluğunu hazırla
  if (progressHept) {
    try {
      heptLen = progressHept.getTotalLength();
    } catch (e) {
      heptLen = 0;
    }
    if (!heptLen || !isFinite(heptLen)) {
      heptLen = 486; // r=80 yedigen çevresi için yedek değer
    }
    progressHept.style.strokeDasharray = String(heptLen);
    progressHept.style.strokeDashoffset = String(heptLen);
  }

  function applyProgress() {
    var p = Math.max(0, Math.min(100, displayPct));
    if (progressHept && heptLen) {
      progressHept.style.strokeDashoffset = String(heptLen * (1 - p / 100));
    }
    if (readoutNum) {
      readoutNum.textContent = String(Math.round(p));
    }
  }

  function startTicker() {
    if (ticker) return;
    ticker = window.setInterval(function () {
      var diff = ceilPct - displayPct;
      if (Math.abs(diff) < 0.15) {
        displayPct = ceilPct;
      } else {
        displayPct += diff * (finished ? 0.24 : 0.07);
      }
      applyProgress();
    }, 80);
  }

  function setStage(key) {
    var idx = -1;
    for (var i = 0; i < STAGES.length; i++) {
      if (STAGES[i].key === key) {
        idx = i;
        break;
      }
    }
    if (idx < 0 || idx <= stageIndex || finished) return;
    stageIndex = idx;
    ceilPct = STAGES[idx].pct;
    if (statusText) {
      statusText.classList.add("alo-status-fade");
      window.setTimeout(function () {
        statusText.textContent = STAGES[idx].label;
        statusText.classList.remove("alo-status-fade");
      }, 200);
    }
  }

  function cleanup() {
    if (ticker) {
      window.clearInterval(ticker);
      ticker = null;
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
    ceilPct = 100;
    if (statusText) {
      statusText.textContent = "Hazır";
    }
    // Giriş atlandıysa derin uzay intro müziği için kalıcı durdurma güvenlik ağı
    if (skipIntro) {
      try {
        if (window.SpaceIntroMusic) {
          window.SpaceIntroMusic.fadeOutAndStop();
        }
      } catch (e) {}
    }
    window.setTimeout(function () {
      overlay.classList.add("app-loading-hidden");
      window.setTimeout(function () {
        if (overlay) overlay.style.display = "none";
        cleanup();
      }, 760);
    }, 620);
  }

  function welcomeVisible() {
    var root = document.querySelector(".modern-welcome-root");
    return !!(root && root.offsetParent !== null);
  }

  // Boot tamamlanma koşullarını değerlendir
  function evaluate() {
    if (finished) return;
    if (!shinyReady || !ssoResolved) return;
    setStage("workspace");

    if (skipIntro) {
      // Giriş ekranı yok: karşılama ekranı gerçekten görünene kadar bekle
      if (welcomeVisible()) {
        setStage("ready");
        window.setTimeout(finish, 620);
        return;
      }
      var body = document.body;
      if (body && body.classList.contains("app-ready")) {
        if (!appReadyAt) {
          appReadyAt = Date.now();
        } else if (Date.now() - appReadyAt > 2600) {
          setStage("ready");
          window.setTimeout(finish, 300);
        }
      }
    } else {
      // Derin uzay giriş ekranına devredilecek
      setStage("ready");
      window.setTimeout(finish, 620);
    }
  }

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
        return;
      }
      var ssoOv = document.getElementById("sso_module-sso_overlay");
      if (ssoOv && ssoOv.classList.contains("sso-auth-hidden")) {
        window.clearInterval(ssoTimer);
        ssoResolved = true;
        setStage("session");
        evaluate();
      }
    }, 150);
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
      setStage("auth");
      startSsoWatch();
    } else {
      ssoResolved = true;
    }
    evaluate();
  }

  // Karşılama ekranı sinematik videolarını önceden yükle (tarayıcı önbelleği
  // ısıtılır; yükleme bitince sol video gecikmesiz başlar). Eksik dosyalar
  // sessizce yok sayılır.
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
    startTicker();
    setStage("boot");

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
    setStage(ssoActive ? "auth" : "connect");
  });

  document.addEventListener("shiny:sessioninitialized", function () {
    shinyReady = true;
    if (!ssoActive) setStage("session");
    evaluate();
  });

  document.addEventListener("shiny:disconnected", function () {
    finish();
  });

  var pollTimer = window.setInterval(function () {
    if (finished) {
      window.clearInterval(pollTimer);
      return;
    }
    evaluate();
  }, 140);

  // Güvenlik zaman aşımı: hiçbir koşul gerçekleşmezse 22 sn sonra kapat
  window.setTimeout(function () {
    finish();
  }, 22000);
})();
