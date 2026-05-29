/* ==============================================================================
 * Dosya Yolu: www/js/tools_model_lock.js
 * Açıklama:   Merkezi araç kilidi yöneticisi: herhangi bir araç (Görsel
 *             Uzmanı, Dosya Özetleme, Proje ve Kaynak Analizi, Excel Analizi,
 *             Kod Uzmanı, Süreç, Uygulama Uzmanı) aktifken sohbet ekranındaki
 *             "Model Değiştir" düğmesini ve Yapılandırma sayfasındaki "Model
 *             Seçimi" dropdown'ını tematik şekilde devre dışı bırakır, hover
 *             tooltip'i ile sebebi açıklar.
 *
 *             Bu yönetici, ayrı araç JS dosyalarının (analysis_tools.js,
 *             summarization_tools.js, image_tools.js, excel_coding_deep_thinking.js)
 *             birbirinden bağımsız aldığı "kilitle/aç" kararlarını DOM
 *             durumuna bakarak tek bir noktada birleştirir.
 * ============================================================================== */

(function() {
  "use strict";

  // Sunucu tarafından ilan edilen aktif araç kilidi etiketi. Süreç Yönetimi ve
  // Uygulama Uzmanı gibi sohbet kontrol paneli OLMAYAN araçlarda kilit sinyali
  // DOM tespiti yerine sunucudan (server-authoritative) gelir.
  var serverLockLabel = null;

  // Aktif araçları DOM üzerinden tespit eder; her aracın kendi kontrol paneli
  // gizli/aktif olarak işaretlenir.
  function detectActiveTools() {
    var pairs = [
      { id: "image_chat_controls",    label: "Görsel Uzmanı" },
      { id: "summary_chat_controls",  label: "Dosya Özetleme" },
      { id: "analysis_chat_controls", label: "Proje ve Kaynak Analizi" },
      { id: "excel_chat_controls",    label: "Excel Analizi" },
      { id: "coding_chat_controls",   label: "Kod Uzmanı" }
    ];
    var active = [];
    for (var i = 0; i < pairs.length; i++) {
      var el = document.getElementById(pairs[i].id);
      if (el && !el.classList.contains("hidden")) {
        active.push(pairs[i].label);
      }
    }
    return active;
  }

  function applyChatModelLock(activeLabels) {
    var wrapper = document.querySelector(".model-selector-wrapper");
    if (!wrapper) return;

    if (activeLabels.length === 0) {
      wrapper.classList.remove("tool-mode-locked", "model-selector-locked");
      wrapper.style.opacity = "1";
      wrapper.style.pointerEvents = "auto";
      wrapper.removeAttribute("data-tool-lock-tooltip");
      wrapper.setAttribute("title", "Model Değiştir");
      return;
    }

    var reason = activeLabels[0] + " aracı aktif iken model değiştirilemez. Bu araç yalnızca kendi özel modeli ile çalışır.";
    wrapper.classList.add("tool-mode-locked", "model-selector-locked");
    wrapper.style.opacity = "0.55";
    wrapper.style.pointerEvents = "none";
    wrapper.setAttribute("title", reason);
    wrapper.setAttribute("data-tool-lock-tooltip", reason);
  }

  function applySettingsModelLock(activeLabels) {
    // Yapılandırma sayfasındaki Model Seçimi dropdown'u namespace prefiksli.
    var select = document.getElementById("settings_yapilandirma_module-model_selection");
    if (!select) return;

    // Komşu container (setting-item) üzerinden görsel kilit uygulanır;
    // dropdown'un kendi disabled durumu da ayarlanır.
    var container = select.closest(".setting-item") || select.parentElement;

    if (activeLabels.length === 0) {
      select.disabled = false;
      if (container) {
        container.classList.remove("tool-mode-locked");
        container.removeAttribute("data-tool-lock-tooltip");
        container.removeAttribute("title");
      }
      return;
    }

    var reason = activeLabels[0] + " aracı aktif iken model değiştirilemez. Aracı kapatmak için Yapılandırma'da ilgili aracın seçim kutusunu kaldırın.";
    select.disabled = true;
    if (container) {
      container.classList.add("tool-mode-locked");
      container.setAttribute("title", reason);
      container.setAttribute("data-tool-lock-tooltip", reason);
    }
  }

  // refresh() durumu DOM'a yazar. Bu yazma işlemi `.input-actions` alt
  // ağacında class değişimi olarak görünebilir ve MutationObserver tekrar
  // tetikleyebilir. Yeniden giriş bayrağı ile geri besleme döngüsünü kırarız.
  var refreshing = false;
  function refresh() {
    if (refreshing) return;
    refreshing = true;
    try {
      var active = detectActiveTools();
      // Panelsiz araçların (Süreç/Uygulama) sunucudan gelen kilit etiketini
      // DOM tespitiyle birleştir; ikisinden biri aktifse kilit uygulanır.
      if (serverLockLabel && active.indexOf(serverLockLabel) === -1) {
        active = [serverLockLabel].concat(active);
      }
      applyChatModelLock(active);
      applySettingsModelLock(active);
    } finally {
      // Mutationların sıralanması için bir sonraki microtask'a bırak
      setTimeout(function() { refreshing = false; }, 0);
    }
  }

  // Sunucu, panelsiz araçlar (Süreç/Uygulama) için kilit etiketini bildirir.
  // Boş/null etiket kilidi serbest bırakır.
  function setServerLock(label) {
    serverLockLabel = (typeof label === "string" && label.length) ? label : null;
    refresh();
  }

  // Diğer tool JS dosyaları toggle*Mode handler'ları içerisinden çağırabilir.
  window.MergenToolModelLock = {
    refresh: refresh,
    detect: detectActiveTools,
    setServerLock: setServerLock
  };

  // Sunucu otoriter kilit mesajı: Süreç/Uygulama gibi panelsiz araçlar aktif
  // olduğunda model seçimi kilitlenir. active=FALSE kilidi serbest bırakır.
  if (window.Shiny && typeof Shiny.addCustomMessageHandler === "function") {
    Shiny.addCustomMessageHandler("setToolModelLock", function(data) {
      if (!data || !data.active) {
        setServerLock(null);
      } else {
        setServerLock(data.label || "Bu araç");
      }
    });
  }

  // DOM değişimleri (sohbet sekmesi yeniden render edilebilir) için defensiv
  // gözlemci: input-actions blokunda hidden sınıfının değişmesi takip edilir.
  function bindObserver() {
    var actions = document.querySelector(".input-actions");
    if (!actions || actions.dataset.toolLockObserver === "1") return;
    actions.dataset.toolLockObserver = "1";

    var observer = new MutationObserver(function() {
      refresh();
    });

    observer.observe(actions, {
      attributes: true,
      attributeFilter: ["class"],
      subtree: true
    });
  }

  function safeStart() {
    try {
      bindObserver();
      refresh();
    } catch (e) {
      // Yüklemeyi engelleyecek şekilde hata fırlatma; sadece konsola yaz.
      if (window.console && console.warn) {
        console.warn("[TOOL_MODEL_LOCK] safeStart hatası:", e);
      }
    }
  }

  document.addEventListener("DOMContentLoaded", safeStart);

  // Shiny bağlandıktan sonra ilk render gecikmeli olabilir, gözlemciyi yeniden bağla.
  // jQuery yüklü değilse sessizce atla.
  if (window.jQuery) {
    window.jQuery(document).on("shiny:connected.toolModelLock shiny:sessioninitialized.toolModelLock", function() {
      setTimeout(safeStart, 80);
    });
  }

  console.log("[TOOL_MODEL_LOCK] Yüklendi");
})();
