// www/js/app_loading.js
// Dosya Yolu: www/js/app_loading.js
// Açıklama: Açılış yükleme ekranı denetleyicisi. Gerçek boot olaylarını
//   (SSO, Shiny bağlantısı, oturum) kontrol noktası olarak izler, yedigen
//   ilerleme halkasını 0'dan 100'e MONOTON ve saat yönünde doldurur,
//   yüzde göstergesini günceller, akan kod katmanını başlatır ve karşılama
//   ekranı varlıklarını önceden yükler.
//   Bu dosya R/module_app_loading.R tarafından satır içine gömülür; bu
//   nedenle harici varlıklar yüklenmeden önce çalışır.

(function () {
  "use strict";

  var overlay = document.getElementById("app-loading-overlay");
  if (!overlay) return;

  // Aşamalar: her anahtar gerçek bir boot kontrol noktasıdır. Yüzdeler
  // yalnızca artar; ilerleme asla geri gitmez.
  var STAGES = [
    { key: "boot", label: "Başlatılıyor", pct: 5 },
    { key: "connect", label: "Bağlantı kuruluyor", pct: 18 },
    { key: "auth_ready", label: "Kimlik doğrulandı", pct: 32 },
    { key: "saved_chats_preview_ready", label: "Son konuşmalar hazırlanıyor", pct: 48 },
    { key: "file_index_ready", label: "Dosyalar hazırlanıyor", pct: 62 },
    { key: "character_media_ready", label: "Asistan medyası hazırlanıyor", pct: 76 },
    { key: "welcome_shell_ready", label: "Ana Söyleşi hazırlanıyor", pct: 88 },
    { key: "welcome_client_ready", label: "Görsel bileşenler başlatılıyor", pct: 96 },
    { key: "ready", label: "Hazır", pct: 99 }
  ];

  var stageIndex = -1;
  var finished = false;
  var fadeStarted = false;
  var shinyReady = false;
  var ssoActive = false;
  var ssoResolved = false;
  var skipIntro = false;
  var appReadyAt = 0;

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
  // 100 -> boş, 0 -> tam çevre. Başlangıç değeri SVG'de satır içi gelir.
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
  
  function installBootReadinessHandler() {
    if (!window.Shiny || !Shiny.addCustomMessageHandler) {
	  window.setTimeout(installBootReadinessHandler, 50);
	  return;
    }

    if (window.__mergenBootReadinessHandlerInstalled) return;
    window.__mergenBootReadinessHandlerInstalled = true;

    Shiny.addCustomMessageHandler("bootReadinessCheckpoint", function(msg) {
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
  }

  // Boot tamamlanma koşullarını değerlendir
  function evaluate() {
    if (finished) return;
    if (!shinyReady || !ssoResolved) return;
    setStage("workspace");

    if (skipIntro) {
      // Giriş ekranı yok: karşılama ekranı gerçekten görünene kadar bekle
      var welcomeRoot = document.querySelector(".modern-welcome-root");
      if (welcomeRoot && welcomeRoot.offsetParent !== null) {
        setStage("ready");
        window.setTimeout(finish, 520);
        return;
      }
      var body = document.body;
      if (body && body.classList.contains("app-ready")) {
        if (!appReadyAt) {
          appReadyAt = Date.now();
        } else if (Date.now() - appReadyAt > 2600) {
          setStage("ready");
          window.setTimeout(finish, 280);
        }
      }
    } else {
      // Derin uzay giriş ekranına devredilecek
      setStage("ready");
      window.setTimeout(finish, 560);
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