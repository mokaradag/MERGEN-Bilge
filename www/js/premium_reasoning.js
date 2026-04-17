/* =============================================================
 * premium_reasoning.js
 * Düşünen (thinking=TRUE) modeller için canlı "Düşünce Akışı"
 * paneli. Sunucudan gelen reasoning_delta parçalarını gerçek
 * zamanlı olarak aktarır; yanıt akışı başladığında panel
 * asistan balonunun içine taşınır, yanıt tamamlandığında
 * daraltılabilir <details> arşivine devredilir.
 * ============================================================= */

(function () {
  "use strict";

  if (window.PremiumReasoning && window.PremiumReasoning.__initialized) {
    return;
  }

  // --- Dahili durum makinesi ---
  // idle | preparing | live | streaming | completed | interrupted | error
  var state = "idle";
  var msgId = null;
  var model = "";
  var reasoningBuffer = "";
  var startedAt = null;
  var firstReasoningAt = null;
  var timerId = null;
  var shellTimeoutId = null;

  // Kullanıcı panel içinde veya dış sohbet akışında yukarı kaydırırsa
  // otomatik alta kaydırma devre dışı bırakılır.
  var userScrolledReasoningUp = false;
  var panelScrollHandlerAttached = false;

  // Pasif başlangıç metinleri yalnızca ilk gerçek reasoning parçası gelene
  // kadar kısa süre gösterilir; "sahte rotasyon" yerine tek satırlık durum.
  var BOOT_SUBTITLE = "Çözüm hazırlanıyor";
  var LIVE_SUBTITLE = "Canlı düşünce akışı";
  var STREAM_SUBTITLE = "Yanıt oluşturuluyor";
  var DONE_SUBTITLE = "Tamamlandı";
  var INTERRUPT_SUBTITLE = "Durduruldu";
  var ERROR_SUBTITLE = "Hata oluştu";

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

  function getHost() {
    return document.getElementById("typing-animation-wrapper");
  }

  function getActivePanel() {
    // Öncelik: asistan balonuna taşınmış panel; yoksa ön-kabuktaki panel.
    if (msgId) {
      var bubblePanel = document.querySelector(
        '#message_wrapper_' + cssEscape(msgId) + ' .reasoning-panel.rp-live'
      );
      if (bubblePanel) return bubblePanel;
    }
    var host = getHost();
    if (host) return host.querySelector(".reasoning-panel.rp-live");
    return null;
  }

  function cssEscape(s) {
    if (window.CSS && window.CSS.escape) return window.CSS.escape(s);
    return String(s).replace(/[^a-zA-Z0-9_-]/g, "\\$&");
  }

  function buildPanelHtml(opts) {
    var modelLabel = escapeHtml(opts.model || "");
    var subtitle = escapeHtml(opts.subtitle || BOOT_SUBTITLE);
    var modelRow = modelLabel
      ? '<span class="rp-model">' + modelLabel + "</span>"
      : "";
    return (
      '<div class="reasoning-panel rp-live" data-state="live">' +
        '<div class="rp-header">' +
          '<div class="rp-title-wrap">' +
            '<span class="rp-pulse"></span>' +
            '<span class="rp-title">Düşünce Akışı</span>' +
            '<span class="rp-subtitle" data-role="subtitle">' + subtitle + "</span>" +
          "</div>" +
          '<div class="rp-actions">' +
            modelRow +
            '<span class="rp-timer" data-role="timer">00:00</span>' +
            '<button class="rp-toggle" data-role="toggle" type="button" ' +
              'aria-expanded="true" title="Paneli daralt / aç">' +
              '<span class="rp-caret" aria-hidden="true"></span>' +
            "</button>" +
          "</div>" +
        "</div>" +
        '<div class="rp-body" data-role="body">' +
          '<pre class="rp-stream" data-role="stream"></pre>' +
        "</div>" +
      "</div>"
    );
  }

  function attachPanelBehaviors(panel) {
    if (!panel) return;
    var toggle = panel.querySelector('[data-role="toggle"]');
    if (toggle && !toggle.__prcBound) {
      toggle.__prcBound = true;
      toggle.addEventListener("click", function (ev) {
        ev.preventDefault();
        var collapsed = panel.classList.toggle("rp-collapsed");
        toggle.setAttribute("aria-expanded", collapsed ? "false" : "true");
      });
    }
    var body = panel.querySelector('[data-role="body"]');
    if (body && !body.__prcScrollBound) {
      body.__prcScrollBound = true;
      body.addEventListener("scroll", function () {
        var near =
          body.scrollHeight - body.scrollTop - body.clientHeight < 16;
        userScrolledReasoningUp = !near;
      });
    }
  }

  function setSubtitle(text) {
    var panel = getActivePanel();
    if (!panel) return;
    var el = panel.querySelector('[data-role="subtitle"]');
    if (el) el.textContent = text;
  }

  function setPanelState(value) {
    var panel = getActivePanel();
    if (!panel) return;
    panel.setAttribute("data-state", value);
  }

  function renderBufferIntoPanel(panel) {
    if (!panel) return;
    var stream = panel.querySelector('[data-role="stream"]');
    if (!stream) return;
    stream.textContent = reasoningBuffer;
    autoScrollPanel(panel);
  }

  function autoScrollPanel(panel) {
    if (!panel) return;
    var body = panel.querySelector('[data-role="body"]');
    if (!body) return;
    if (userScrolledReasoningUp) return;
    body.scrollTop = body.scrollHeight;
  }

  function autoScrollOuter() {
    // Dış sohbet; kullanıcı yukarı kaymamışsa yumuşakça alta ilerlet.
    if (typeof window.smartScrollToBottom === "function") {
      if (window.isNearBottom !== false) {
        window.smartScrollToBottom(false);
      }
    }
  }

  function tickTimer() {
    var anchor = firstReasoningAt || startedAt;
    if (!anchor) return;
    var panel = getActivePanel();
    if (!panel) return;
    var el = panel.querySelector('[data-role="timer"]');
    if (el) el.textContent = fmtTime(Date.now() - anchor);
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

  function ensurePrePanel() {
    // Ön-kabuk (assistant balonu henüz yok) için #typing-animation-wrapper
    // içine paneli enjekte eder.
    var host = getHost();
    if (!host) {
      // Kısa bir süre daha dener.
      if (shellTimeoutId) clearTimeout(shellTimeoutId);
      shellTimeoutId = setTimeout(ensurePrePanel, 40);
      return null;
    }
    host.classList.add("rp-host");

    var existing = host.querySelector(".reasoning-panel.rp-live");
    if (existing) return existing;

    host.innerHTML = buildPanelHtml({
      model: model,
      subtitle: BOOT_SUBTITLE
    });
    var panel = host.querySelector(".reasoning-panel.rp-live");
    attachPanelBehaviors(panel);
    renderBufferIntoPanel(panel);
    return panel;
  }

  function start(config) {
    cleanup(true);
    state = "preparing";
    msgId = null;
    reasoningBuffer = "";
    firstReasoningAt = null;
    userScrolledReasoningUp = false;
    model = (config && config.model) || "";
    startedAt = Date.now();

    // Paneli hemen göster: gerçek içerik gelene kadar tek satırlık sakin
    // bir "Çözüm hazırlanıyor" alt başlığı taşır.
    ensurePrePanel();
    startTimer();
  }

  function onReasoningDelta(payload) {
    if (!payload) return;
    var text = (payload.delta != null) ? String(payload.delta) : "";
    if (!text) return;

    if (!firstReasoningAt) firstReasoningAt = Date.now();

    reasoningBuffer += text;

    if (state === "preparing") {
      state = "live";
      setSubtitle(LIVE_SUBTITLE);
    }

    var panel = getActivePanel() || ensurePrePanel();
    if (panel) {
      var stream = panel.querySelector('[data-role="stream"]');
      if (stream) {
        // Küçük performans iyileştirmesi: sadece yeni metni ekle.
        stream.appendChild(document.createTextNode(text));
      }
      autoScrollPanel(panel);
    }

    autoScrollOuter();
  }

  function migrateToBubble(targetId) {
    if (!targetId) return null;
    msgId = targetId;
    var wrapper = document.getElementById("message_wrapper_" + targetId);
    if (!wrapper) return null;

    var aiRoot = wrapper.querySelector(".ai-message") || wrapper.querySelector(".message-bubble");
    if (!aiRoot) return null;

    // Balonun içinde zaten panel varsa onu kullan; yoksa yeni panel yarat.
    var existing = aiRoot.querySelector(".reasoning-panel.rp-live");
    var panel;
    if (existing) {
      panel = existing;
    } else {
      var temp = document.createElement("div");
      temp.innerHTML = buildPanelHtml({
        model: model,
        subtitle: STREAM_SUBTITLE
      });
      panel = temp.firstChild;
      // Yanıt içeriğinden ÖNCE yerleştir.
      var contentDiv = aiRoot.querySelector(".message-content") || null;
      if (contentDiv) {
        aiRoot.insertBefore(panel, contentDiv);
      } else {
        aiRoot.appendChild(panel);
      }
    }

    attachPanelBehaviors(panel);
    renderBufferIntoPanel(panel);

    // Ön-kabuktaki kopyayı temizle.
    var host = getHost();
    if (host) {
      var shellPanel = host.querySelector(".reasoning-panel.rp-live");
      if (shellPanel && shellPanel !== panel) {
        shellPanel.remove();
      }
      // Kabuk boşaldığında host stilini geri al.
      host.classList.remove("rp-host");
    }

    return panel;
  }

  function onStreamStart(payload) {
    var id = payload && payload.id ? payload.id : null;
    // Düşünen model değilse bu handler zaten anlamsız; panel yoksa sessizce çık.
    if (state === "idle") return;

    // Yanıt akışı başladı: paneli balonun içine taşı ve durumu güncelle.
    var panel = migrateToBubble(id);
    if (!panel) {
      // Balon henüz gelmediyse çok kısa bir süre bekleyip yeniden dene.
      setTimeout(function () { migrateToBubble(id); }, 30);
    }
    state = "streaming";
    setPanelState("streaming");
    setSubtitle(STREAM_SUBTITLE);
  }

  function onResetChatState() {
    // Normal tamamlanma, durdurma ve hata yollarının tamamında çağrılır.
    stopTimer();

    var panel = getActivePanel();
    if (!panel) {
      // Hiç panel yoksa sessizce temizle.
      cleanup(false);
      state = "idle";
      return;
    }

    if (state === "streaming" || state === "live" || state === "preparing") {
      if (state === "streaming") {
        markCompleted(panel);
      } else {
        markInterrupted(panel);
      }
    }

    // Canlı paneli kaldırma: kullanıcı tamamlanmış düşünce akışına sonradan
    // bakabilmeli. Panel, "completed"/"interrupted" durumunda kalır,
    // daraltılabilir başlığıyla asistan balonunun içinde görünür kalır.
    // Kalıcı DB arşivi ayrı bir sütunda (MB_Messages.ReasoningContent) saklanır
    // ve geçmişten yüklenen mesajlar için arka planda <details> olarak üretilir.
    state = "idle";
    // Gelecek mesajlar için yalnızca zamanlayıcı/ön-kabuk temizliği yap;
    // mevcut panel DOM'u olduğu gibi bırakılır.
    if (shellTimeoutId) {
      clearTimeout(shellTimeoutId);
      shellTimeoutId = null;
    }
    var h = getHost();
    if (h) h.classList.remove("rp-host");
    reasoningBuffer = "";
    firstReasoningAt = null;
    startedAt = null;
    userScrolledReasoningUp = false;
    panelScrollHandlerAttached = false;
  }

  function markCompleted(panel) {
    panel.setAttribute("data-state", "completed");
    setSubtitle(DONE_SUBTITLE);
    panel.classList.add("rp-completed");
  }

  function markInterrupted(panel) {
    panel.setAttribute("data-state", "interrupted");
    setSubtitle(INTERRUPT_SUBTITLE);
    panel.classList.add("rp-interrupted");
  }

  function markError(panel, msg) {
    panel.setAttribute("data-state", "error");
    setSubtitle(msg || ERROR_SUBTITLE);
    panel.classList.add("rp-error");
  }

  function fadeOutAndRemove(panel) {
    if (!panel) return;
    panel.classList.add("rp-fading");
    setTimeout(function () {
      if (panel && panel.parentNode) {
        panel.parentNode.removeChild(panel);
      }
      // Ön-kabukta bırakılmış host stilini temizle.
      var h = getHost();
      if (h) h.classList.remove("rp-host");
    }, 320);
  }

  function onError(payload) {
    stopTimer();
    var panel = getActivePanel();
    if (!panel) {
      cleanup(false);
      state = "idle";
      return;
    }
    markError(panel, (payload && payload.message) || ERROR_SUBTITLE);
    state = "error";
  }

  function cleanup(keepBuffer) {
    stopTimer();
    if (shellTimeoutId) {
      clearTimeout(shellTimeoutId);
      shellTimeoutId = null;
    }
    if (!keepBuffer) {
      reasoningBuffer = "";
      firstReasoningAt = null;
      startedAt = null;
      userScrolledReasoningUp = false;
      panelScrollHandlerAttached = false;
    }
    // Ön-kabuk stilini her temizlemede geri al.
    var h = getHost();
    if (h) h.classList.remove("rp-host");
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
    onReasoningDelta: onReasoningDelta,
    onError: onError,
    isActive: isActive,
    getState: getState
  };

  function registerHandlers() {
    if (typeof Shiny === "undefined" || !Shiny.addCustomMessageHandler) {
      setTimeout(registerHandlers, 40);
      return;
    }
    Shiny.addCustomMessageHandler("premiumReasoningStart", function (config) {
      try { start(config || {}); } catch (e) { console && console.warn && console.warn("[PRC] start", e); }
    });
    Shiny.addCustomMessageHandler("premiumReasoningStreamStart", function (payload) {
      try { onStreamStart(payload || {}); } catch (e) { console && console.warn && console.warn("[PRC] streamStart", e); }
    });
    Shiny.addCustomMessageHandler("streamingReasoningDelta", function (payload) {
      try { onReasoningDelta(payload || {}); } catch (e) { console && console.warn && console.warn("[PRC] reasoningDelta", e); }
    });
    Shiny.addCustomMessageHandler("premiumReasoningError", function (payload) {
      try { onError(payload || {}); } catch (e) { console && console.warn && console.warn("[PRC] error", e); }
    });
  }
  registerHandlers();

  if (typeof $ !== "undefined") {
    $(document).on("shiny:disconnected", function () {
      cleanup(false);
      state = "idle";
    });

    // Kullanıcı elle yukarı kaydırdıysa dış alan auto-scroll'ı da duraksat.
    // window.isNearBottom zaten utils.js içinde güncelleniyor; ek çaba yok.

    // Geçmişten açılan mesajlarda <details class="reasoning-block">
    // tıklanabilir olsun diye ekstra davranış: erişilebilirlik odak halkası.
    $(document).on("click", "details.reasoning-block > summary", function () {
      // <details> native davranışını tetiklemeye bırak; ek iş gerekmez.
    });
  }
})();
