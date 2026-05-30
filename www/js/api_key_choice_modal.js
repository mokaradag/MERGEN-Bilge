/* ============================================================
 * Dosya: www/js/api_key_choice_modal.js
 * Açıklama: API Anahtarı Seçim Modalı için küçük istemci tarafı yardımcıları.
 *
 *           ÖNEMLİ: Modalın KRİTİK davranışları (anahtar girişi, merkezleme,
 *           arka plan bulanıklığı, animasyonlar, video) tamamen R/CSS/HTML ile
 *           çalışır ve bu dosyaya BAĞIMLI DEĞİLDİR. Bu dosya yalnızca
 *           "Bu ekranı bir daha gösterme" kolaylık tercihini yönetir:
 *             1) Tercihi mergen_settings localStorage bayrağında saklar,
 *             2) Modal içindeki onay kutusu ve Yapılandırma anahtarını eşitler,
 *             3) Tercihi sunucuya bildirir (R modalı tekrar göstermesin diye).
 *
 *           Tercih yalnızca hassas OLMAYAN bir bayraktır
 *           (api_key_onboarding_suppressed). Hiçbir API anahtarı (kişisel veya
 *           varsayılan) bu dosyada okunmaz, saklanmaz veya loglanmaz.
 *           Zamanlamaya dayanmamak için olay delegasyonu kullanılır.
 *           CDN/uzak kaynak yoktur; tamamen yereldir.
 * ============================================================ */

(function () {
  "use strict";

  var SUPPRESS_KEY = "api_key_onboarding_suppressed";
  var SETTINGS_LS = "mergen_settings";

  // Shiny custom message handler'ları dosya yüklenirken kaydolur.
  // Handler kayıt hatası veya erken mesaj durumunda kontrol yüzeyi
  // tanımsız kalmamalıdır.
  window.MergenApiKeyChoice = window.MergenApiKeyChoice || {};
  window.MergenApiKeyChoice._inputId = window.MergenApiKeyChoice._inputId || null;

  function readSettings() {
    try {
      return JSON.parse(window.localStorage.getItem(SETTINGS_LS) || "{}") || {};
    } catch (e) {
      return {};
    }
  }

  // Mevcut mergen_settings nesnesini KORUYARAK tek anahtarı yaz (merge).
  function writeSettingKey(key, value) {
    try {
      var s = readSettings();
      s[key] = value;
      window.localStorage.setItem(SETTINGS_LS, JSON.stringify(s));
    } catch (e) {
      /* sessizce yoksay */
    }
  }

  function isSuppressed() {
    return readSettings()[SUPPRESS_KEY] === true;
  }

  // Sunucuya güncel bastırma bayrağını bildir (varsa kayıtlı namespaced id'ye).
  function reportToServer() {
    if (!window.Shiny || typeof Shiny.setInputValue !== "function") {
      return;
    }

    var choice = window.MergenApiKeyChoice || {};
    if (choice._inputId) {
      Shiny.setInputValue(choice._inputId, isSuppressed(), {
        priority: "event"
      });
    }
  }

  // Yapılandırma sayfasındaki "API anahtarı seçim ekranını göster" anahtarını
  // localStorage durumuyla eşitle ("göster" = bastırılmamış). Programatik
  // güncellemede Shiny input değerini de bildiririz; aksi halde tarayıcıda
  // görünen durum ile Shiny'nin son bildiği değer ayrışabilir.
  function setSettingsToggleChecked(el, checked, notifyShiny) {
    if (!el) {
      return;
    }

    if (el.checked !== checked) {
      el.checked = checked;
    }

    if (notifyShiny !== false &&
        window.Shiny &&
        typeof Shiny.setInputValue === "function" &&
        el.id) {
      Shiny.setInputValue(el.id, checked, {
        priority: "event"
      });
    }
  }

  function syncSettingsToggle(scope, notifyShiny) {
    var root = scope && scope.querySelectorAll ? scope : document;
    var toggles = root.querySelectorAll(
      'input[type="checkbox"][id$="show_api_key_onboarding"]'
    );
    Array.prototype.forEach.call(toggles, function (el) {
      setSettingsToggleChecked(el, !isSuppressed(), notifyShiny);
    });
  }

  // Modal içindeki "bu ekranı bir daha gösterme" kutusunu localStorage'dan
  // başlangıç durumuna getir.
  function syncDontShowBox() {
    var box = document.querySelector(".api-key-choice-modal-root .akc-dontshow-input");
    if (box) {
      box.checked = isSuppressed();
    }
  }

  // ---- Olay delegasyonu: zamanlamadan bağımsız, güvenilir ----

  // Tüm checkbox değişikliklerini tek noktadan yakala.
  document.addEventListener(
    "change",
    function (e) {
      var el = e.target;
      if (!el || el.type !== "checkbox") {
        return;
      }

      // Modal içindeki "bir daha gösterme" kutusu.
      if (el.classList && el.classList.contains("akc-dontshow-input")) {
        writeSettingKey(SUPPRESS_KEY, !!el.checked);
        reportToServer();
        syncSettingsToggle();
        return;
      }

      // Yapılandırma sayfasındaki "göster" anahtarı (ns ön ekli olabilir).
      if (el.id && /show_api_key_onboarding$/.test(el.id)) {
        // "göster" kapalıysa onboarding bastırılır.
        writeSettingKey(SUPPRESS_KEY, !el.checked);
        reportToServer();
        return;
      }
    },
    true
  );

  // Yapılandırma anahtarı her bağlandığında/yeniden render edildiğinde doğru
  // görünür duruma çek. Shiny her binding'de bu olayı tetikler.
  document.addEventListener("shiny:bound", function (e) {
    var el = e && e.target;
    if (el && el.id && /show_api_key_onboarding$/.test(el.id)) {
      setSettingsToggleChecked(el, !isSuppressed(), true);
    }
  });

  if (window.Shiny && typeof Shiny.addCustomMessageHandler === "function") {
    // R, oturum başında bastırma bayrağını ister ve namespaced input id'sini
    // verir. Bunu saklayıp güncel bayrağı bildiririz. Bu yol DOM'a dokunmaz,
    // bu nedenle zamanlama açısından güvenilirdir.
    Shiny.addCustomMessageHandler(
      "mergenApiKeyChoiceReportPref",
      function (message) {
        if (!message || !message.inputId) {
          return;
        }
        window.MergenApiKeyChoice = window.MergenApiKeyChoice || {};
        window.MergenApiKeyChoice._inputId = message.inputId;
        reportToServer();
      }
    );

    // Modal gösterildiğinde yalnızca onay kutusu/anahtar görünür durumunu
    // eşitle. Kritik davranış değil; başarısız olsa bile varsayılan görünür
    // durum doğrudur. DOM hazır olana kadar birkaç kez dener.
    Shiny.addCustomMessageHandler("mergenApiKeyChoiceInit", function (message) {
      void message;

      var tries = 0;
      var timer = setInterval(function () {
        tries += 1;
        var root = document.querySelector(".api-key-choice-modal-root");
        if (root) {
          syncDontShowBox();
          syncSettingsToggle();
          clearInterval(timer);
        } else if (tries >= 20) {
          clearInterval(timer);
        }
      }, 80);
    });
  }

  function syncSettingsToggleSoon() {
    setTimeout(function () {
      syncSettingsToggle(document, true);
    }, 0);

    setTimeout(function () {
      syncSettingsToggle(document, true);
    }, 150);
  }

  // Sayfa bağlandığında Yapılandırma anahtarını eşitle.
  document.addEventListener("shiny:connected", syncSettingsToggleSoon);

  // Bu dosya ertelenmiş yüklenebildiği için shiny:connected/shiny:bound
  // olayları daha önce kaçmış olabilir. Yükleme anında da bir kez eşitle.
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", syncSettingsToggleSoon, {
      once: true
    });
  } else {
    syncSettingsToggleSoon();
  }

  // Küçük, isim alanlı kontrol yüzeyi (test/araç erişimi için).
  // Nesneyi yeniden atama; erken gelen _inputId değerini koru.
  window.MergenApiKeyChoice.settingsKey = SUPPRESS_KEY;
  window.MergenApiKeyChoice.isSuppressed = isSuppressed;
  window.MergenApiKeyChoice.suppress = function () {
    writeSettingKey(SUPPRESS_KEY, true);
    reportToServer();
  };
  window.MergenApiKeyChoice.allow = function () {
    writeSettingKey(SUPPRESS_KEY, false);
    reportToServer();
  };
})();