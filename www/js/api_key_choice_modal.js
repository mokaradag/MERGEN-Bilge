/* ============================================================
 * Dosya: www/js/api_key_choice_modal.js
 * Açıklama: API Anahtarı Seçim Modalı için küçük istemci tarafı
 *           geliştirmeleri. Sorumlulukları:
 *             1) Modal açıldığında birincil eyleme odaklanma,
 *             2) "Anahtarımı Gireyim" çekmecesini açma/kapama + odak,
 *             3) Yerel arka plan videosunu sessize alıp oynatma (azaltılmış
 *                harekette durdurma),
 *             4) Modal dışı bölgeyi bulanıklaştırma (backdrop blur),
 *             5) "Bu ekranı bir daha gösterme" tercihini ve Yapılandırma
 *                anahtarını yönetme.
 *
 *           Tercih, mergen_settings localStorage nesnesi içindeki
 *           "api_key_onboarding_suppressed" bayrağında tutulur. Bu yalnızca
 *           hassas OLMAYAN bir bayraktır; hiçbir API anahtarı (kişisel veya
 *           varsayılan) bu dosyada okunmaz, saklanmaz veya loglanmaz.
 *           CDN / uzak kaynak yoktur; tamamen yereldir.
 * ============================================================ */

(function () {
  "use strict";

  // mergen_settings nesnesi içindeki bastırma bayrağı anahtarı.
  var SUPPRESS_KEY = "api_key_onboarding_suppressed";
  var SETTINGS_LS = "mergen_settings";

  // localStorage erişimi bazı kurumsal/gizli oturum profillerinde kapalı
  // olabilir; sessizce güvenli geri düşüş uygula.
  function readSettings() {
    try {
      return JSON.parse(window.localStorage.getItem(SETTINGS_LS) || "{}") || {};
    } catch (e) {
      return {};
    }
  }

  // Mevcut mergen_settings nesnesini KORUYARAK tek bir anahtarı yaz (merge).
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

  function getModalRoot() {
    return document.querySelector(".api-key-choice-modal-root");
  }

  function focusElement(el) {
    if (!el || typeof el.focus !== "function") {
      return;
    }
    try {
      el.focus({ preventScroll: true });
    } catch (e) {
      el.focus();
    }
  }

  function prefersReducedMotion() {
    try {
      return (
        window.matchMedia &&
        window.matchMedia("(prefers-reduced-motion: reduce)").matches
      );
    } catch (e) {
      return false;
    }
  }

  // Yerel arka plan videosu: sessize al ve oynatmayı dene. Azaltılmış hareket
  // tercihinde durdur; dosya yoksa/oynatma reddedilirse poster + gradyan kalır.
  function setupVideo(root) {
    var video = root.querySelector(".akc-video");
    if (!video) {
      return;
    }
    try {
      video.muted = true;
    } catch (e) {
      /* yoksay */
    }
    if (prefersReducedMotion()) {
      try {
        video.pause();
      } catch (e) {
        /* yoksay */
      }
      return;
    }
    var playing = video.play && video.play();
    if (playing && typeof playing.catch === "function") {
      playing.catch(function () {
        /* autoplay reddi: poster/gradyan görünür kalır */
      });
    }
  }

  // "Anahtarımı Gireyim" çekmecesini aç/kapa ve açılınca alana odaklan.
  function wireRevealToggles(root) {
    var toggles = root.querySelectorAll(".akc-reveal-toggle");
    Array.prototype.forEach.call(toggles, function (toggle) {
      if (toggle.getAttribute("data-akc-bound") === "1") {
        return;
      }
      toggle.setAttribute("data-akc-bound", "1");
      toggle.addEventListener("click", function () {
        var card = toggle.closest(".akc-card");
        if (!card) {
          return;
        }
        var opened = card.classList.toggle("akc-entry-open");
        toggle.setAttribute("aria-expanded", opened ? "true" : "false");
        if (opened) {
          var input = card.querySelector(".akc-key-entry input");
          if (input) {
            setTimeout(function () {
              focusElement(input);
            }, 200);
          }
        }
      });
    });
  }

  // Modal içindeki "Bu ekranı bir daha gösterme" kutusu. Değiştikçe tercih
  // hemen localStorage'a (mergen_settings) yazılır; anahtar değeri tutulmaz.
  function wireDontShow(root) {
    var box = root.querySelector(".akc-dontshow-input");
    if (!box || box.getAttribute("data-akc-bound") === "1") {
      return;
    }
    box.setAttribute("data-akc-bound", "1");
    box.checked = isSuppressed();
    box.addEventListener("change", function () {
      writeSettingKey(SUPPRESS_KEY, !!box.checked);
    });
  }

  // Modal dışı bölgeyi bulanıklaştır (yalnızca bu modal açıkken).
  function enableBackdropBlur() {
    try {
      document.body.classList.add("akc-blur-backdrop");
    } catch (e) {
      /* yoksay */
    }
    if (window.jQuery) {
      try {
        window.jQuery("#shiny-modal").one("hidden.bs.modal", function () {
          try {
            document.body.classList.remove("akc-blur-backdrop");
          } catch (e) {
            /* yoksay */
          }
        });
      } catch (e) {
        /* yoksay */
      }
    }
  }

  function focusFirstAction(root) {
    var target = root.querySelector(
      ".akc-btn--primary, .akc-btn--corporate, a.akc-btn, .akc-btn"
    );
    focusElement(target);
  }

  // Yapılandırma sayfasındaki "API anahtarı seçim ekranını göster" anahtarını
  // localStorage ile görsel olarak eşitle. Bu kontrol tamamen istemci
  // tarafında yönetilir; sunucu bu Shiny input'unu okumaz.
  function syncSettingsToggle() {
    var toggles = document.querySelectorAll(
      'input[type="checkbox"][id$="show_api_key_onboarding"]'
    );
    Array.prototype.forEach.call(toggles, function (el) {
      el.checked = !isSuppressed(); // "göster" = bastırılmamış
    });
  }

  if (window.Shiny && typeof Shiny.addCustomMessageHandler === "function") {
    // Modal gösterildiğinde sunucudan gelen güvenli başlatma mesajı.
    Shiny.addCustomMessageHandler("mergenApiKeyChoiceInit", function () {
      // Modal DOM'a eklendikten sonra geliştirmeleri bağla.
      setTimeout(function () {
        var root = getModalRoot();
        if (!root) {
          return;
        }
        setupVideo(root);
        wireRevealToggles(root);
        wireDontShow(root);
        enableBackdropBlur();
        focusFirstAction(root);
      }, 40);
    });

    // Sunucu, oturum başında bastırma bayrağını ister. Yanıt yalnızca bir
    // boolean'dır; anahtar içermez.
    Shiny.addCustomMessageHandler(
      "mergenApiKeyChoiceReportPref",
      function (message) {
        if (!message || !message.inputId) {
          return;
        }
        if (window.Shiny && typeof Shiny.setInputValue === "function") {
          Shiny.setInputValue(message.inputId, isSuppressed(), {
            priority: "event"
          });
        }
      }
    );
  }

  // Yapılandırma anahtarının değişimini delegasyonla yakala ve localStorage'a
  // yaz. id, modül ad alanı (ns) ön eki taşıyabilir; sonek ile eşleştirilir.
  document.addEventListener(
    "change",
    function (e) {
      var el = e.target;
      if (!el || el.type !== "checkbox" || !el.id) {
        return;
      }
      if (!/show_api_key_onboarding$/.test(el.id)) {
        return;
      }
      // "göster" kapalıysa onboarding bastırılır.
      writeSettingKey(SUPPRESS_KEY, !el.checked);
    },
    true
  );

  // Sayfa bağlandığında/hazır olduğunda Yapılandırma anahtarını eşitle.
  document.addEventListener("shiny:connected", function () {
    setTimeout(syncSettingsToggle, 120);
  });
  document.addEventListener("DOMContentLoaded", function () {
    setTimeout(syncSettingsToggle, 200);
  });

  // Küçük, isim alanlı kontrol yüzeyi (test/araç erişimi için).
  window.MergenApiKeyChoice = {
    settingsKey: SUPPRESS_KEY,
    isSuppressed: isSuppressed,
    suppress: function () {
      writeSettingKey(SUPPRESS_KEY, true);
    },
    allow: function () {
      writeSettingKey(SUPPRESS_KEY, false);
    }
  };
})();
