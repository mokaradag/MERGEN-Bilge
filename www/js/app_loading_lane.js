// www/js/app_loading_lane.js
// Dosya Yolu: www/js/app_loading_lane.js
// Açıklama: Başlangıç deneyimi şeridi (startup lane) istemci çözümleyicisi ve
//   ilk açılış şerit seçicisi. R/helpers_startup_lane.R içindeki saf sunucu
//   yardımcılarının istemci eşleniğidir; iki taraf aynı sözleşmeyi paylaşır.
//
//   Şeritler:
//     - fast_lane : Hızlı Başlangıç. Derin uzay girişi, sinematik/persona
//                   medya ön yüklemesi ve açılış müziği atlanır; kullanıcı
//                   doğrudan Ana Söyleşi'ye iner. Özellik SİLİNMEZ; yalnızca
//                   açılış yükü ertelenir.
//     - rich_lane : Zengin Deneyim. Mevcut sinematik açılış korunur.
//
//   Çözümleme önceliği:
//     1) localStorage mergen_settings.startup_lane (kullanıcı tercihi)
//     2) window.__mergenStartupLaneEnvDefault (MERGEN_STARTUP_LANE dağıtım
//        varsayılanı; R/module_app_loading.R gömer)
//     3) ask_once -> ilk açılış şerit seçicisi gösterilir
//
//   Seçici; video, Three.js veya persona medyası GEREKTİRMEZ. Yalnızca koyu
//   temalı, CSS mikro-animasyonlu iki karttan oluşur ve seçim anında
//   localStorage'a yazılır (bir sonraki açılışta tekrar sorulmaz).
//
//   Bu dosya R/module_app_loading.R tarafından açılış katmanına satır içi
//   gömülür (app_loading.js'ten ÖNCE) ve bilinçli olarak normal UI varlık
//   manifestine eklenmez.

(function () {
  "use strict";

  var SETTINGS_KEY = "mergen_settings";
  var LANES = ["fast_lane", "rich_lane"];

  var resolvedLane = null;      // "fast_lane" | "rich_lane" | null (seçim bekliyor)
  var callbacks = [];
  var selectorOpen = false;
  var shinyNotifyTimer = null;

  function normalizeLane(value) {
    if (typeof value !== "string") return null;
    var v = value.toLowerCase().replace(/^\s+|\s+$/g, "");
    if (v === "fast_lane" || v === "fast" || v === "hizli") return "fast_lane";
    if (v === "rich_lane" || v === "rich" || v === "normal" || v === "zengin") return "rich_lane";
    return null;
  }

  function readSettingsObject() {
    try {
      var raw = window.localStorage.getItem(SETTINGS_KEY);
      if (!raw) return null;
      var parsed = JSON.parse(raw);
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        return parsed;
      }
    } catch (e) {}
    return null;
  }

  function readStoredLane() {
    var settings = readSettingsObject();
    if (settings) {
      return normalizeLane(settings.startup_lane);
    }
    return null;
  }

  function persistLane(lane) {
    if (LANES.indexOf(lane) === -1) return;
    try {
      var settings = readSettingsObject() || {};
      settings.startup_lane = lane;
      window.localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings));
    } catch (e) {}
  }

  function envDefaultLane() {
    return normalizeLane(window.__mergenStartupLaneEnvDefault || "");
  }

  // Hızlı şeritte derin uzay girişi de atlanır: mergen-skip-intro sınıfı
  // mevcut CSS/JS atlama davranışını, mergen-fast-lane sınıfı ise şeride özel
  // stilleri (statik karşılama zemini, gizlenen Deneyim Modu kartları vb.)
  // sürer. Zengin şeritte fast-lane sınıfı kaldırılır; skip-intro sınıfına
  // dokunulmaz (o ayrı bir kullanıcı tercihi olarak kalır).
  function applyLaneClasses(lane) {
    var html = document.documentElement;
    if (!html) return;
    if (lane === "fast_lane") {
      html.classList.add("mergen-fast-lane");
      html.classList.add("mergen-skip-intro");
    } else {
      html.classList.remove("mergen-fast-lane");
    }
  }

  function notifyShiny(lane) {
    if (shinyNotifyTimer) {
      window.clearTimeout(shinyNotifyTimer);
      shinyNotifyTimer = null;
    }
    if (window.Shiny && typeof window.Shiny.setInputValue === "function") {
      try {
        window.Shiny.setInputValue("startup_lane_resolved", {
          lane: lane,
          ts: Date.now()
        }, { priority: "event" });
        return;
      } catch (e) {}
    }
    // Shiny henüz hazır değilse kısa aralıklarla yeniden dene.
    shinyNotifyTimer = window.setTimeout(function () {
      notifyShiny(lane);
    }, 120);
  }

  function fireCallbacks(lane) {
    var pending = callbacks;
    callbacks = [];
    for (var i = 0; i < pending.length; i++) {
      try {
        pending[i](lane);
      } catch (e) {}
    }
  }

  function commitLane(lane, opts) {
    opts = opts || {};
    lane = normalizeLane(lane);
    if (!lane) return;

    resolvedLane = lane;
    if (opts.persist === true) {
      persistLane(lane);
    }
    applyLaneClasses(lane);
    if (opts.notifyShiny !== false) {
      notifyShiny(lane);
    }
    fireCallbacks(lane);
  }

  // ------------------------------------------------------------------
  // İlk açılış şerit seçicisi (koyu, iki kart; medya/Three.js yok)
  // ------------------------------------------------------------------
  function selectorEl() {
    return document.getElementById("mergen-lane-select");
  }

  function hideSelector() {
    var el = selectorEl();
    if (el) {
      el.classList.remove("mlane-visible");
      window.setTimeout(function () {
        if (el.parentNode) el.parentNode.removeChild(el);
      }, 420);
    }
    selectorOpen = false;
  }

  function bindSelectorCard(card) {
    if (!card || card.__mlaneBound) return;
    card.__mlaneBound = true;

    function choose() {
      var lane = normalizeLane(card.getAttribute("data-lane"));
      if (!lane) return;
      // Kullanıcı seçimi kalıcıdır: bir sonraki açılışta tekrar sorulmaz.
      commitLane(lane, { persist: true });
      hideSelector();
    }

    card.addEventListener("click", choose);
    card.addEventListener("keydown", function (ev) {
      if (ev && (ev.key === "Enter" || ev.key === " " || ev.key === "Spacebar")) {
        ev.preventDefault();
        choose();
      }
    });
  }

  function showSelector() {
    var el = selectorEl();
    if (!el) {
      // Seçici işaretlemesi yoksa güvenli varsayılan: zengin deneyim
      // (mevcut davranış), kalıcılaştırmadan.
      commitLane("rich_lane", { persist: false });
      return;
    }

    // SSO ön-uç yönlendirmesi başladıysa bu sayfa Keycloak'a sıçramak
    // üzeredir; seçiciyi göstermek anlamsızdır. Şerit çözümü sonraki gerçek
    // açılışta yapılır.
    if (window.__mergenSsoPreflightRedirecting === true) {
      return;
    }

    selectorOpen = true;
    el.removeAttribute("hidden");
    // Görünürlük sınıfı bir sonraki karede eklenir ki giriş geçişi oynasın.
    window.requestAnimationFrame(function () {
      el.classList.add("mlane-visible");
    });

    var cards = el.querySelectorAll(".mlane-card");
    for (var i = 0; i < cards.length; i++) {
      bindSelectorCard(cards[i]);
    }
    // Klavye erişimi: ilk kart odaklanır.
    if (cards.length > 0 && typeof cards[0].focus === "function") {
      window.setTimeout(function () {
        try { cards[0].focus(); } catch (e) {}
      }, 60);
    }
  }

  // ------------------------------------------------------------------
  // Dış API
  // ------------------------------------------------------------------
  window.MergenStartupLane = {
    get: function () {
      return resolvedLane;
    },
    isFast: function () {
      return resolvedLane === "fast_lane";
    },
    needsSelection: function () {
      return resolvedLane === null;
    },
    isSelectorOpen: function () {
      return selectorOpen;
    },
    whenResolved: function (cb) {
      if (typeof cb !== "function") return;
      if (resolvedLane) {
        try { cb(resolvedLane); } catch (e) {}
        return;
      }
      callbacks.push(cb);
    },
    set: function (lane, opts) {
      commitLane(lane, opts || { persist: true });
    }
  };

  // Ayarlar sayfasından şerit değişimi: sınıflar/durum anında uygulanır;
  // kalıcılaştırma saveSettings mesajıyla ayrıca yapılır (çift yazım yok).
  function installApplyLaneHandler() {
    if (!window.Shiny || !window.Shiny.addCustomMessageHandler) {
      window.setTimeout(installApplyLaneHandler, 150);
      return;
    }
    if (window.__mergenApplyStartupLaneInstalled) return;
    window.__mergenApplyStartupLaneInstalled = true;
    window.Shiny.addCustomMessageHandler("applyStartupLane", function (data) {
      if (!data || !data.lane) return;
      commitLane(data.lane, { persist: false, notifyShiny: false });
    });
  }

  // ------------------------------------------------------------------
  // Çözümleme: kayıtlı tercih > ortam varsayılanı > ilk açılış seçicisi
  // ------------------------------------------------------------------
  function resolveOnBoot() {
    var stored = readStoredLane();
    if (stored) {
      commitLane(stored, { persist: false });
      return;
    }

    var envLane = envDefaultLane();
    if (envLane) {
      // Dağıtım varsayılanı kullanıcı tercihi olarak KALICI YAZILMAZ;
      // operatör varsayılanı değiştirirse yeni değer etkili olur.
      commitLane(envLane, { persist: false });
      return;
    }

    showSelector();
  }

  installApplyLaneHandler();

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", resolveOnBoot);
  } else {
    resolveOnBoot();
  }
})();
