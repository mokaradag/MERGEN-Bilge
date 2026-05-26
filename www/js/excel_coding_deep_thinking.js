/* ==============================================================================
 * Dosya Yolu: www/js/excel_coding_deep_thinking.js
 * Açıklama:   Excel Analizi ve Kod Uzmanı araçları için sohbet içi "Derin
 *             Düşünme" düğmesi ve seviye (Düşük/Yüksek) dropdown yönetimi.
 *             analysis_tools.js'teki kalıbı izler; merkezi model seçim kilidi
 *             (tools_model_lock.js) ile koordineli çalışır.
 * ============================================================================== */

(function() {
  "use strict";

  // Excel ve Kod araçları için ortak yardımcı: belirli toggle/dropdown çiftini günceller.
  function setToolDeepThinkingState(toolKey, active) {
    var toggleId = toolKey === "excel"
      ? "chat_excel_deep_thinking_toggle"
      : "chat_coding_deep_thinking_toggle";
    var selectId = toolKey === "excel"
      ? "chat_excel_deep_level"
      : "chat_coding_deep_level";

    var btn = document.getElementById(toggleId);
    if (!btn) return;

    if (active) {
      btn.classList.add("active");
      btn.setAttribute(
        "title",
        "Derin Düşünme: Aktif - Alternatif düşünen model kullanılacak"
      );
    } else {
      btn.classList.remove("active");
      btn.setAttribute(
        "title",
        toolKey === "excel"
          ? "Derin Düşünme: Pasif - Excel için temel düşünen modeli kullan"
          : "Derin Düşünme: Pasif - Kod için temel düşünen modeli kullan"
      );
    }

    var levelSelect = document.getElementById(selectId);
    if (levelSelect) {
      levelSelect.disabled = !active;
      levelSelect.style.opacity = active ? "1" : "0.4";
    }
  }

  window.setExcelDeepThinkingState = function(active) {
    setToolDeepThinkingState("excel", active);
  };
  window.setCodingDeepThinkingState = function(active) {
    setToolDeepThinkingState("coding", active);
  };

  // Sohbet ekranındaki Excel/Kod kontrol panellerini göster/gizle.
  window.toggleExcelControls = function(show) {
    var controls = document.getElementById("excel_chat_controls");
    if (!controls) return;
    if (show) {
      controls.classList.remove("hidden");
    } else {
      controls.classList.add("hidden");
    }
  };
  window.toggleCodingControls = function(show) {
    var controls = document.getElementById("coding_chat_controls");
    if (!controls) return;
    if (show) {
      controls.classList.remove("hidden");
    } else {
      controls.classList.add("hidden");
    }
  };

  // DOM dinleyicileri: butonlar ve seviye dropdown'ları
  function bindToolDeepThinking(toolKey) {
    var toggleId = toolKey === "excel"
      ? "chat_excel_deep_thinking_toggle"
      : "chat_coding_deep_thinking_toggle";
    var selectId = toolKey === "excel"
      ? "chat_excel_deep_level"
      : "chat_coding_deep_level";
    var inputBaseName = toolKey === "excel" ? "chat_excel" : "chat_coding";

    var btn = document.getElementById(toggleId);
    if (btn) {
      btn.addEventListener("click", function() {
        var newState = !this.classList.contains("active");
        setToolDeepThinkingState(toolKey, newState);

        if (window.Shiny) {
          Shiny.setInputValue(
            inputBaseName + "_deep_thinking",
            newState,
            { priority: "event" }
          );
        }
      });
    }

    var sel = document.getElementById(selectId);
    if (sel) {
      sel.addEventListener("change", function() {
        if (window.Shiny) {
          Shiny.setInputValue(
            inputBaseName + "_deep_level",
            this.value,
            { priority: "event" }
          );
        }
      });
    }
  }

  document.addEventListener("DOMContentLoaded", function() {
    bindToolDeepThinking("excel");
    bindToolDeepThinking("coding");
  });

  // Shiny mesaj işleyicileri: araç modlarını aç/kapat (server-side tetikli)
  if (window.Shiny) {
    Shiny.addCustomMessageHandler("toggleExcelMode", function(data) {
      window.toggleExcelControls(data && data.active);
      // Yapılandırma sayfasındaki dropdown ve sohbet ekranındaki Model Değiştir
      // kilidi merkezi yöneticiye (tools_model_lock.js) bırakılır.
      if (window.MergenToolModelLock && typeof window.MergenToolModelLock.refresh === "function") {
        window.MergenToolModelLock.refresh();
      }
    });

    Shiny.addCustomMessageHandler("toggleCodingMode", function(data) {
      window.toggleCodingControls(data && data.active);
      if (window.MergenToolModelLock && typeof window.MergenToolModelLock.refresh === "function") {
        window.MergenToolModelLock.refresh();
      }
    });

    // Yapılandırma sayfasından sohbete senkronize (gerektiğinde)
    Shiny.addCustomMessageHandler("syncExcelDeepThinkingToChat", function(data) {
      if (!data) return;
      var levelSel = document.getElementById("chat_excel_deep_level");
      if (levelSel && data.level) {
        levelSel.value = data.level;
      }
      window.setExcelDeepThinkingState(!!data.deep_thinking);
    });

    Shiny.addCustomMessageHandler("syncCodingDeepThinkingToChat", function(data) {
      if (!data) return;
      var levelSel = document.getElementById("chat_coding_deep_level");
      if (levelSel && data.level) {
        levelSel.value = data.level;
      }
      window.setCodingDeepThinkingState(!!data.deep_thinking);
    });
  }

  console.log("[EXCEL_CODING_DEEP_THINKING] Yüklendi");
})();
