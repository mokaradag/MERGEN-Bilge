/* ============================================================
 * Dosya: www/js/api_key_choice_modal.js
 * Açıklama: API Anahtarı Seçim Modalı için küçük istemci tarafı yardımcıları.
 *
 *           ÖNEMLİ: Modalın KRİTİK davranışları (anahtar girişi, merkezleme,
 *           arka plan bulanıklığı, animasyonlar, video) tamamen R/CSS/HTML ile
 *           çalışır ve bu dosyaya BAĞIMLI DEĞİLDİR. Bu dosya yalnızca
 *           "Bu ekranı bir daha gösterme" kolaylık tercihini yönetir:
 *             1) Tercihi kullanıcı etiketine özgü ayrı localStorage anahtarında
 *                saklar (eski mergen_settings kayıtları temizlenir),
 *             2) Modal içindeki onay kutusu ve Yapılandırma anahtarını eşitler,
 *             3) Tercihi etiketiyle sunucuya bildirir (R modalı tekrar
 *                göstermesin diye); modal kutusu seçim yapılana dek bekler.
 *
 *           Tercih yalnızca hassas OLMAYAN bir bayraktır
 *           (api_key_onboarding_suppressed): "1" = seçim ekranı bastırıldı,
 *           "default" = bastırıldı ve kurum anahtarı seçildi (kayıtlı kişisel
 *           anahtarın önüne geçer). Hiçbir API anahtarı (kişisel veya
 *           varsayılan) bu dosyada okunmaz, saklanmaz veya loglanmaz.
 *           Zamanlamaya dayanmamak için olay delegasyonu kullanılır.
 *           CDN/uzak kaynak yoktur; tamamen yereldir.
 * ============================================================ */

(function () {
  "use strict";

  var SUPPRESS_KEY = "api_key_onboarding_suppressed";
  // Bayrak kullanıcıya özgü etiketle AYRI bir localStorage anahtarında tutulur;
  // etiketi sunucu kimlik hazır olunca gönderir. Aynı tarayıcıdaki başka
  // kullanıcı tercihi devralmaz; farklı kullanıcıların sekmeleri ortak nesneyi
  // okuyup yazarak birbirinin kaydını ezmez.
  var SUPPRESS_USER_PREFIX = SUPPRESS_KEY + ".";
  // Eski ortak kayıtlar (tarayıcı geneli bayrak ve kullanıcı haritası).
  var LEGACY_BY_USER_KEY = "api_key_onboarding_suppressed_by_user";
  var SETTINGS_LS = "mergen_settings";

  // Shiny custom message handler'ları dosya yüklenirken kaydolur.
  // Handler kayıt hatası veya erken mesaj durumunda kontrol yüzeyi
  // tanımsız kalmamalıdır.
  window.MergenApiKeyChoice = window.MergenApiKeyChoice || {};
  window.MergenApiKeyChoice._inputId = window.MergenApiKeyChoice._inputId || null;
  window.MergenApiKeyChoice._userTag = window.MergenApiKeyChoice._userTag || "";
  window.MergenApiKeyChoice._dontShowInputId = window.MergenApiKeyChoice._dontShowInputId || null;
  window.MergenApiKeyChoice._modalNonce = window.MergenApiKeyChoice._modalNonce || "";

  function readSettings() {
    try {
      return JSON.parse(window.localStorage.getItem(SETTINGS_LS) || "{}") || {};
    } catch (e) {
      return {};
    }
  }

  function currentUserTag() {
    var tag = (window.MergenApiKeyChoice || {})._userTag;
    return typeof tag === "string" ? tag : "";
  }

  // Kullanıcı etiketi bilinmeden bastırma yoktur (seçim ekranı gösterilir).
  // Etiket verilirse o kullanıcının kaydı okunur (etkin etiket değişmez).
  function readPref(etiket) {
    var tag = typeof etiket === "string" ? etiket : currentUserTag();
    if (!tag) {
      return "";
    }
    try {
      return window.localStorage.getItem(SUPPRESS_USER_PREFIX + tag) || "";
    } catch (e) {
      return "";
    }
  }

  function isSuppressed() {
    var deger = readPref();
    return deger === "1" || deger === "default";
  }

  function rememberedSource(etiket) {
    return readPref(etiket) === "default" ? "default" : "";
  }

  // mergen_settings içindeki eski ortak kayıtlar yalnız varsa kaldırılır.
  function dropLegacyFlags() {
    try {
      var s = readSettings();
      var has = Object.prototype.hasOwnProperty;
      if (has.call(s, SUPPRESS_KEY) || has.call(s, LEGACY_BY_USER_KEY)) {
        delete s[SUPPRESS_KEY];
        delete s[LEGACY_BY_USER_KEY];
        window.localStorage.setItem(SETTINGS_LS, JSON.stringify(s));
      }
    } catch (e) {
      // Eski kayıt kalsa da okunmaz; kullanıcı tercihini etkilemez.
    }
  }

  // Yalnız bu kullanıcının anahtarı yazılır. Yazımın gerçekten kalıcı olduğu
  // geri okunarak doğrulanır (ör. dolu ya da kapalı depolama). Ekranı yeniden
  // açmak hatırlanan kurum seçimini de kaldırır.
  function writePref(deger, etiket) {
    var tag = typeof etiket === "string" ? etiket : currentUserTag();
    if (!tag) {
      return false;
    }
    try {
      if (deger) {
        window.localStorage.setItem(SUPPRESS_USER_PREFIX + tag, deger);
      } else {
        window.localStorage.removeItem(SUPPRESS_USER_PREFIX + tag);
      }
      dropLegacyFlags();
      return readPref(tag) === deger;
    } catch (e) {
      return false;
    }
  }

  function writeSuppressed(value) {
    if (!value) {
      return writePref("");
    }
    return isSuppressed() || writePref("1");
  }

  // "default": kurum seçimi hatırlanır; "personal": kişisel anahtar kaydedildi,
  // hatırlanan kurum seçimi bastırma korunarak kaldırılır; "clear": kullanıcı
  // "bir daha gösterme" işaretini kaldırdı, tercih silinir. Yazım yalnız
  // verilen etiketin kaydına yapılır.
  function writeSource(source, etiket) {
    if (source === "personal") {
      return rememberedSource(etiket) !== "default" || writePref("1", etiket);
    }
    if (source === "clear") {
      return writePref("", etiket);
    }
    return writePref("default", etiket);
  }

  // Sunucuya güncel bastırma bayrağını etiketiyle bildir; sunucu yalnız
  // geçerli kullanıcının etiketini taşıyan yanıtı kabul eder.
  function reportToServer() {
    if (!window.Shiny || typeof Shiny.setInputValue !== "function") {
      return;
    }

    var choice = window.MergenApiKeyChoice || {};
    if (choice._inputId) {
      Shiny.setInputValue(choice._inputId, {
        suppressed: isSuppressed(),
        source: rememberedSource(),
        tag: currentUserTag()
      }, {
        priority: "event"
      });
    }
  }

  // Modal kutusunun bekleyen durumu sunucuya bildirilir; tercih yalnız kurum
  // anahtarı seçilince yazılır. Değer modal jetonu ve kullanıcı etiketiyle
  // gider; sunucu başka modalın ya da kullanıcının işaretini kabul etmez.
  function reportDontShowPending(checked) {
    var choice = window.MergenApiKeyChoice || {};
    if (choice._dontShowInputId && window.Shiny &&
        typeof Shiny.setInputValue === "function") {
      Shiny.setInputValue(choice._dontShowInputId, {
        checked: !!checked,
        tag: currentUserTag(),
        nonce: choice._modalNonce || ""
      }, {
        priority: "event"
      });
    }
  }

  function warnNotSaved() {
    if (typeof window.showToast === "function") {
      window.showToast("Tercihiniz bu tarayıcıda kaydedilemedi.", "warning");
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
  // başlangıç durumuna getir ve bekleyen durumu sunucuya bildir.
  function syncDontShowBox() {
    var box = document.querySelector(".api-key-choice-modal-root .akc-dontshow-input");
    if (box) {
      box.checked = isSuppressed();
      reportDontShowPending(box.checked);
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

      // Modal içindeki "bir daha gösterme" kutusu: işaret beklemede kalır;
      // "Daha Sonra Karar Ver" ile kapatılırsa hiçbir şey yazılmaz.
      if (el.classList && el.classList.contains("akc-dontshow-input")) {
        reportDontShowPending(el.checked);
        return;
      }

      // Yapılandırma sayfasındaki "göster" anahtarı (ns ön ekli olabilir).
      // Kayıt başarısızsa anahtar eski konumuna döner ve kullanıcı uyarılır.
      if (el.id && /show_api_key_onboarding$/.test(el.id)) {
        // "göster" kapalıysa onboarding bastırılır.
        if (!writeSuppressed(!el.checked)) {
          setSettingsToggleChecked(el, !el.checked, true);
          warnNotSaved();
        }
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
        window.MergenApiKeyChoice._userTag =
          typeof message.userTag === "string" ? message.userTag : "";
        window.MergenApiKeyChoice._inputId = message.inputId;
        reportToServer();
        syncSettingsToggle(document, true);
      }
    );

    // Modal gösterildiğinde yalnızca onay kutusu/anahtar görünür durumunu
    // eşitle. Kritik davranış değil; başarısız olsa bile varsayılan görünür
    // durum doğrudur. DOM hazır olana kadar birkaç kez dener.
    Shiny.addCustomMessageHandler("mergenApiKeyChoiceInit", function (message) {
      if (message && typeof message.dontShowInputId === "string") {
        window.MergenApiKeyChoice._dontShowInputId = message.dontShowInputId;
      }
      window.MergenApiKeyChoice._modalNonce =
        message && typeof message.nonce === "string" ? message.nonce : "";
      if (message && typeof message.userTag === "string" && message.userTag) {
        window.MergenApiKeyChoice._userTag = message.userTag;
      }

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

  // Kurum anahtarıyla devam seçildiğinde sunucu onaylar ve tercih o kullanıcı
  // için hatırlanır; seçim ekranı açılmaz (Yapılandırma'dan geri açılır).
  if (window.Shiny && typeof Shiny.addCustomMessageHandler === "function") {
    Shiny.addCustomMessageHandler("mergenApiKeyChoiceRemember", function (message) {
      // Onay, yazımın etiketi ve jetonuyla gider; sunucu başka kullanıcının ya
      // da eski yazımın onayını kabul etmez.
      var sonucBildir = function (ok) {
        if (message && message.resultInputId && window.Shiny &&
            typeof Shiny.setInputValue === "function") {
          Shiny.setInputValue(message.resultInputId, {
            ok: ok,
            tag: typeof message.userTag === "string" ? message.userTag : "",
            nonce: typeof message.nonce === "string" ? message.nonce : "",
            t: Date.now()
          }, {
            priority: "event"
          });
        }
      };
      // Etiketsiz mesaj önceki (başka) kullanıcının etiketine yazmaz.
      if (!message || typeof message.userTag !== "string" || !message.userTag) {
        sonucBildir(false);
        return;
      }
      // Geç gelen mesaj etkin tarayıcı kimliğini değiştirmez; yazım yalnız
      // mesajın etiketine yapılır, eşitleme etiket etkin kullanıcıya aitse yapılır.
      var kaynak = message.source === "personal" || message.source === "clear" ? message.source : "default";
      var kaydedildi = writeSource(kaynak, message.userTag);
      if (message.userTag === currentUserTag()) {
        reportToServer();
        syncSettingsToggle();
      }
      sonucBildir(kaydedildi);
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
    var ok = writeSuppressed(true);
    reportToServer();
    return ok;
  };
  window.MergenApiKeyChoice.allow = function () {
    var ok = writeSuppressed(false);
    reportToServer();
    return ok;
  };
})();