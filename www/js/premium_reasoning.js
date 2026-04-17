/* =============================================================
 * premium_reasoning.js
 * Düşünen (thinking=TRUE) modeller için premium akıl yürütme kartı.
 * Var olan #typing-animation-wrapper barındırıcı olarak kullanılır;
 * böylece mevcut removeUI("#typing-animation-wrapper") çağrılarıyla
 * hiçbir çakışma yaşanmaz ve kart doğal biçimde temizlenir.
 * ============================================================= */

(function () {
  "use strict";

  if (window.PremiumReasoning && window.PremiumReasoning.__initialized) {
    return;
  }

  // Durum makinesi: idle | preparing | thinking | streaming | interrupted | error
  var state = "idle";
  var model = "";
  var startedAt = null;
  var shownAt = null;
  var phaseIdx = 0;
  var timerId = null;
  var phaseId = null;
  var hostRetryId = null;

  // Akış süresi kısa olsa bile kartın en az bu kadar süre görünür kalmasını sağlar.
  var MIN_VISIBLE_MS = 1200;

  // Akışa erken geçildiğinde kartı bekletip sonra sakince devreye alır.
  var pendingStreamTransitionId = null;

  // Kullanıcının gözüne batmasın diye çok kısa yanıtlar için kartı hiç gösterme eşiği.
  var FLICKER_GUARD_MS = 420;
  var renderDelayId = null;

  var PHASES = [
    "İstek analiz ediliyor",
    "Bağlam değerlendiriliyor",
    "Uygun yaklaşım belirleniyor",
    "Yanıt taslağı oluşturuluyor",
    "Son doğrulamalar yapılıyor"
  ];

  function fmt2(n) {
    n = Math.max(0, Math.floor(n));
    return n < 10 ? "0" + n : "" + n;
  }

  function fmtTime(ms) {
    var total = Math.floor(ms / 1000);
    var m = Math.floor(total / 60);
    var s = total % 60;
    return fmt2(m) + ":" + fmt2(s);
  }

  function escapeHtml(s) {
    if (s === null || s === undefined) return "";
    return String(s).replace(/[&<>"']/g, function (c) {
      return {
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        "\"": "&quot;",
        "'": "&#39;"
      }[c];
    });
  }

  function getHost() {
    return document.getElementById("typing-animation-wrapper");
  }

  function getCard() {
    var host = getHost();
    if (!host) return null;
    return host.querySelector(".premium-reasoning-card");
  }

  function buildCardHtml(opts) {
    var modelLabel = escapeHtml(opts.model || "");
    var modelRow = modelLabel
      ? '<div class="prc-model">' + modelLabel + "</div>"
      : "";
    return (
      '<div class="premium-reasoning-card" data-state="thinking" role="status" aria-live="polite">' +
        '<div class="prc-header">' +
          '<div class="prc-badge" data-role="badge">' +
            '<span class="prc-badge-dot"></span>' +
            '<span class="prc-badge-text">Düşünen Model</span>' +
          "</div>" +
          '<div class="prc-timer" data-role="timer">Geçen süre 00:00</div>' +
        "</div>" +
        '<div class="prc-body">' +
          '<div class="prc-title" data-role="title">Akıl Yürütme Modu</div>' +
          '<div class="prc-phase" data-role="phase">' + escapeHtml(PHASES[0]) + "</div>" +
          modelRow +
        "</div>" +
        '<div class="prc-wave"><div class="prc-wave-line"></div></div>' +
      "</div>"
    );
  }

  function setRole(role, text) {
    var host = getHost();
    if (!host) return;
    var el = host.querySelector('[data-role="' + role + '"]');
    if (el) el.textContent = text;
  }

  function setBadgeText(text) {
    var host = getHost();
    if (!host) return;
    var el = host.querySelector(".prc-badge-text");
    if (el) el.textContent = text;
  }

  function setCardState(value) {
    var card = getCard();
    if (!card) return;
    card.setAttribute("data-state", value);
  }

  function tickTimer() {
    if (!shownAt) return;
    setRole("timer", "Geçen süre " + fmtTime(Date.now() - shownAt));
  }

  function startTimer() {
    stopTimer();
    tickTimer();
    timerId = setInterval(tickTimer, 500);
  }

  function stopTimer() {
    if (timerId) {
      clearInterval(timerId);
      timerId = null;
    }
  }

  function startPhaseRotation() {
    stopPhaseRotation();
    phaseId = setInterval(function () {
      var host = getHost();
      if (!host) return;
      var el = host.querySelector('[data-role="phase"]');
      if (!el) return;
      el.classList.add("prc-phase-fading");
      setTimeout(function () {
        phaseIdx = (phaseIdx + 1) % PHASES.length;
        el.textContent = PHASES[phaseIdx];
        el.classList.remove("prc-phase-fading");
      }, 200);
    }, 2600);
  }

  function stopPhaseRotation() {
    if (phaseId) {
      clearInterval(phaseId);
      phaseId = null;
    }
  }

  function cancelPending() {
    if (renderDelayId) {
      clearTimeout(renderDelayId);
      renderDelayId = null;
    }
    if (hostRetryId) {
      clearInterval(hostRetryId);
      hostRetryId = null;
    }
    if (pendingStreamTransitionId) {
      clearTimeout(pendingStreamTransitionId);
      pendingStreamTransitionId = null;
    }
  }

  function cleanupAll() {
    stopTimer();
    stopPhaseRotation();
    cancelPending();
  }

  function renderIntoHost() {
    var host = getHost();
    if (!host) {
      // Barındırıcı henüz gelmediyse kısa süre izle.
      var attempts = 0;
      if (hostRetryId) clearInterval(hostRetryId);
      hostRetryId = setInterval(function () {
        attempts += 1;
        var h = getHost();
        if (h) {
          clearInterval(hostRetryId);
          hostRetryId = null;
          injectCard(h);
        } else if (attempts > 30) {
          clearInterval(hostRetryId);
          hostRetryId = null;
        }
      }, 40);
      return;
    }
    injectCard(host);
  }

  function injectCard(host) {
    host.classList.add("prc-host");
    host.innerHTML = buildCardHtml({ model: model });
    state = "thinking";
    shownAt = Date.now();
    phaseIdx = 0;
    startTimer();
    startPhaseRotation();
  }

  function start(config) {
    // Yeni istek: eski durumu temiz şekilde kapat.
    cleanupAll();
    state = "preparing";
    model = (config && config.model) || "";
    startedAt = Date.now();

    // Kısa yanıtlarda kartın yanıp sönmemesi için küçük bir gecikmeyle aç.
    if (renderDelayId) clearTimeout(renderDelayId);
    renderDelayId = setTimeout(function () {
      renderDelayId = null;
      if (state !== "preparing") return;
      renderIntoHost();
    }, FLICKER_GUARD_MS);
  }

  function transitionToStreaming() {
    var card = getCard();
    if (!card) {
      state = "streaming";
      return;
    }
    state = "streaming";
    setCardState("streaming");
    setBadgeText("Akış");
    setRole("title", "Yanıt oluşturuluyor");
    setRole("phase", "Sonuç aktarılıyor");
    stopPhaseRotation();
    // Zamanlayıcı kısa süre görünür kalsın; wrapper birazdan Shiny
    // tarafından kaldırılacak ve kart doğal biçimde yok olacak.
  }

  function onStreamStart() {
    // Kartın gösterim zamanı çok kısaysa yine de kısa bir süre görünür kalsın.
    if (state === "preparing") {
      // Kart daha hiç görünmemiş - karmaşaya yol açmadan geçişi planla.
      cancelPending();
      if (!shownAt) {
        // Hiç gösterilmeden akışa geçiliyor; kartı hiç açmadan geç.
        state = "streaming";
        return;
      }
    }

    if (state === "interrupted" || state === "error") {
      return;
    }

    var elapsed = shownAt ? Date.now() - shownAt : 0;
    if (elapsed < MIN_VISIBLE_MS) {
      // Minimum görünür süre dolana kadar geçişi ertele.
      if (pendingStreamTransitionId) clearTimeout(pendingStreamTransitionId);
      pendingStreamTransitionId = setTimeout(function () {
        pendingStreamTransitionId = null;
        transitionToStreaming();
      }, MIN_VISIBLE_MS - elapsed);
      return;
    }

    transitionToStreaming();
  }

  function onResetChatState() {
    // Bu çağrı hem normal tamamlanma hem de durdurma/hata sonrası gelir.
    // Kart duruma göre uygun görsele geçer.
    cancelPending();

    var card = getCard();
    if (!card) {
      // Kart görünmeden tamamlandı; yalnızca durum sıfırla.
      state = "idle";
      cleanupAll();
      return;
    }

    if (state === "preparing" || state === "thinking") {
      // Akış hiç başlamadı; kullanıcı durdurdu veya erken hata oldu.
      state = "interrupted";
      setCardState("interrupted");
      setBadgeText("Durduruldu");
      setRole("title", "Düşünme durduruldu");
      setRole("phase", "Yanıt kullanıcı tarafından kesildi");
      stopTimer();
      stopPhaseRotation();
      // #typing-animation-wrapper removeUI ile kaldırılacağı için
      // bu durum kısa süre görünür kalır; sonra doğal olarak temizlenir.
    } else if (state === "streaming") {
      // Normal tamamlanma: kart kapanırken hafifçe solsun.
      card.classList.add("prc-fading");
      state = "idle";
      cleanupAll();
    } else {
      cleanupAll();
      state = "idle";
    }
  }

  function onError(payload) {
    cancelPending();
    var card = getCard();
    if (!card) {
      state = "idle";
      cleanupAll();
      return;
    }
    state = "error";
    setCardState("error");
    setBadgeText("Hata");
    setRole("title", "Düşünme süreci tamamlanamadı");
    var msg = (payload && payload.message) || "Yanıt oluşturulurken bir sorun oluştu. İsterseniz yeniden deneyebilirsiniz.";
    setRole("phase", msg);
    stopTimer();
    stopPhaseRotation();
  }

  function isActive() {
    return state !== "idle";
  }

  function getState() {
    return state;
  }

  window.PremiumReasoning = {
    __initialized: true,
    start: start,
    onStreamStart: onStreamStart,
    onResetChatState: onResetChatState,
    onError: onError,
    isActive: isActive,
    getState: getState
  };

  // Shiny özel mesaj kancaları
  function registerHandlers() {
    if (typeof Shiny === "undefined" || !Shiny.addCustomMessageHandler) {
      setTimeout(registerHandlers, 40);
      return;
    }
    Shiny.addCustomMessageHandler("premiumReasoningStart", function (config) {
      try { start(config || {}); } catch (e) { console && console.warn && console.warn("[PRC] start", e); }
    });
    Shiny.addCustomMessageHandler("premiumReasoningStreamStart", function () {
      try { onStreamStart(); } catch (e) { console && console.warn && console.warn("[PRC] streamStart", e); }
    });
    Shiny.addCustomMessageHandler("premiumReasoningError", function (payload) {
      try { onError(payload || {}); } catch (e) { console && console.warn && console.warn("[PRC] error", e); }
    });
  }
  registerHandlers();

  // Sayfa görünürlüğü değişirse zamanlayıcıları koru; timer DOM üzerinde çalıştığı
  // için ek özel işlem gerekmez.

  // Bağlantı kopunca durumu temizle.
  if (typeof $ !== "undefined") {
    $(document).on("shiny:disconnected", function () {
      cleanupAll();
      state = "idle";
    });
  }
})();
