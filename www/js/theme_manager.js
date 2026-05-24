// ============================================================
// Başlık: Tema Yöneticisi (Açık/Koyu Tema)
// Dosya: www/js/theme_manager.js
// Açıklama: MERGEN Bilge için açık/koyu tema durumunu yöneten istemci
//           modülü. Tema durumu <html data-theme="..."> üzerinden uygulanır.
//           Tercih localStorage'daki "mergen_settings" objesi içinde "theme"
//           alanına yazılır. JS devre dışıysa veya değer yoksa varsayılan
//           koyu tema korunur. Tüm bileşenler temadan haberdar olabilsin
//           diye "mergen:themechange" özel olayı yayınlanır.
// ============================================================

(function () {
  'use strict';

  var THEMES = ['dark', 'light'];
  var DEFAULT_THEME = 'dark';
  var SETTINGS_KEY = 'mergen_settings';
  var THEME_KEY_LEGACY = 'mergen_theme';

  function isValidTheme(value) {
    return typeof value === 'string' && THEMES.indexOf(value) !== -1;
  }

  function readSettingsObject() {
    try {
      var raw = window.localStorage.getItem(SETTINGS_KEY);
      if (!raw) {
        return null;
      }
      var parsed = JSON.parse(raw);
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        return parsed;
      }
    } catch (e) {
      // localStorage erişimi yoksa veya JSON bozuksa sessizce geç
    }
    return null;
  }

  function writeSettingsObject(obj) {
    try {
      window.localStorage.setItem(SETTINGS_KEY, JSON.stringify(obj));
      return true;
    } catch (e) {
      return false;
    }
  }

  function readStoredTheme() {
    // 1) Birincil kaynak: mergen_settings.theme
    var settings = readSettingsObject();
    if (settings && isValidTheme(settings.theme)) {
      return settings.theme;
    }

    // 2) Eski/yedek anahtar
    try {
      var legacy = window.localStorage.getItem(THEME_KEY_LEGACY);
      if (isValidTheme(legacy)) {
        return legacy;
      }
    } catch (e) {
      // localStorage erişimi yoksa sessizce geç
    }

    return null;
  }

  function persistTheme(theme) {
    if (!isValidTheme(theme)) {
      return;
    }

    var settings = readSettingsObject() || {};
    settings.theme = theme;
    writeSettingsObject(settings);

    try {
      window.localStorage.setItem(THEME_KEY_LEGACY, theme);
    } catch (e) {
      // sessiz geç
    }
  }

  function applyThemeAttribute(theme) {
    if (!isValidTheme(theme)) {
      theme = DEFAULT_THEME;
    }

    var html = document.documentElement;
    if (!html) {
      return DEFAULT_THEME;
    }

    html.setAttribute('data-theme', theme);
    html.classList.remove('theme-dark', 'theme-light');
    html.classList.add('theme-' + theme);
    return theme;
  }

  function dispatchThemeChange(theme) {
    try {
      var event = new CustomEvent('mergen:themechange', {
        detail: { theme: theme }
      });
      window.dispatchEvent(event);
    } catch (e) {
      // Bazı eski tarayıcılarda CustomEvent ctor desteklenmeyebilir;
      // tema yine de uygulanmış olur, sessiz geçilir.
    }
  }

  function applyTheme(theme, options) {
    options = options || {};
    var resolved = applyThemeAttribute(isValidTheme(theme) ? theme : DEFAULT_THEME);

    if (options.persist !== false) {
      persistTheme(resolved);
    }

    if (options.notifyServer !== false &&
        window.Shiny &&
        typeof window.Shiny.setInputValue === 'function') {
      try {
        window.Shiny.setInputValue('mergen_theme_changed', {
          theme: resolved,
          ts: Date.now()
        }, { priority: 'event' });
      } catch (e) {
        // Shiny henüz bağlı değilse sorun değil; tema yine uygulanmış olur
      }
    }

    if (options.animate !== false) {
      document.documentElement.classList.add('theme-anim');
      window.setTimeout(function () {
        document.documentElement.classList.remove('theme-anim');
      }, 380);
    }

    dispatchThemeChange(resolved);
    return resolved;
  }

  function toggleTheme(options) {
    var current = window.MergenTheme.get();
    var next = current === 'light' ? 'dark' : 'light';
    return applyTheme(next, options);
  }

  function init() {
    // Erken uygulamada okunan değer
    var stored = readStoredTheme();
    var initial = isValidTheme(stored) ? stored : DEFAULT_THEME;
    applyThemeAttribute(initial);
    return initial;
  }

  // Erken init (FOUC azaltmak için)
  var startupTheme = init();

  // Public API
  window.MergenTheme = {
    DEFAULT: DEFAULT_THEME,
    get: function () {
      var html = document.documentElement;
      var attr = html ? html.getAttribute('data-theme') : null;
      return isValidTheme(attr) ? attr : DEFAULT_THEME;
    },
    set: function (theme, options) {
      return applyTheme(theme, options);
    },
    toggle: function (options) {
      return toggleTheme(options);
    },
    isLight: function () {
      return window.MergenTheme.get() === 'light';
    },
    isDark: function () {
      return window.MergenTheme.get() === 'dark';
    }
  };

  // ============================================================
  // Genel ayar (settings) persist handler'ları
  // ============================================================
  // R tarafı session$sendCustomMessage("saveSettings"/"loadSettings"/
  // "clearSettings", ...) çağrılarını localStorage senkronizasyonu için
  // burada güvenli ve idempotent biçimde sağlıyoruz. Eğer ileride başka
  // bir modül de aynı isimde handler kayıt ederse Shiny uyarı verebilir;
  // yine de istemci tarafı tema/araç arka planı zaten kendi başına çalışır.
  function registerSettingsBridge() {
    if (!window.Shiny || typeof window.Shiny.addCustomMessageHandler !== 'function') {
      return;
    }
    if (window.__mergenSettingsBridgeRegistered) {
      return;
    }
    window.__mergenSettingsBridgeRegistered = true;

    try {
      window.Shiny.addCustomMessageHandler('setMergenTheme', function (data) {
        if (!data || !data.theme) return;
        if (data.theme === 'dark' || data.theme === 'light') {
          window.MergenTheme.set(data.theme, { persist: true });
        }
      });
    } catch (e) { /* önceden kayıtlıysa yoksay */ }

    try {
      window.Shiny.addCustomMessageHandler('saveSettings', function (data) {
        try {
          if (!data || typeof data !== 'object') return;
          var current = {};
          var raw = window.localStorage.getItem(SETTINGS_KEY);
          if (raw) {
            try {
              var parsed = JSON.parse(raw);
              if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
                current = parsed;
              }
            } catch (eParse) { /* bozuksa baştan başla */ }
          }
          Object.keys(data).forEach(function (k) {
            current[k] = data[k];
          });
          window.localStorage.setItem(SETTINGS_KEY, JSON.stringify(current));
        } catch (e) { /* sessiz geç */ }
      });
    } catch (e) { /* önceden kayıtlıysa yoksay */ }

    try {
      window.Shiny.addCustomMessageHandler('loadSettings', function () {
        var loaded = null;
        try {
          var raw = window.localStorage.getItem(SETTINGS_KEY);
          if (raw) {
            loaded = JSON.parse(raw);
          }
        } catch (e) {
          loaded = null;
        }
        if (loaded && typeof loaded === 'object' && !Array.isArray(loaded)) {
          try {
            window.Shiny.setInputValue('loaded_settings', loaded, {
              priority: 'event'
            });
          } catch (e2) { /* sessiz geç */ }
        }
      });
    } catch (e) { /* önceden kayıtlıysa yoksay */ }

    try {
      window.Shiny.addCustomMessageHandler('clearSettings', function () {
        try {
          // Tüm ayarları sıfırlamak yerine yalnızca uygulama tercihlerini
          // sıfırlıyoruz; tema gibi tercih edilen değerleri de varsayılana
          // döndürürüz. Diğer localStorage anahtarlarına dokunmuyoruz.
          var preserve = {};
          var raw = window.localStorage.getItem(SETTINGS_KEY);
          if (raw) {
            try {
              var parsed = JSON.parse(raw);
              if (parsed && typeof parsed === 'object') {
                // İsteğe bağlı: tema bilgisini koruma yerine sıfırlama
                // istendiğinde "dark" yazıyoruz.
                preserve.theme = 'dark';
              }
            } catch (e3) { /* sessiz geç */ }
          }
          window.localStorage.setItem(SETTINGS_KEY, JSON.stringify(preserve));
        } catch (e) { /* sessiz geç */ }
      });
    } catch (e) { /* önceden kayıtlıysa yoksay */ }
  }

  // Yeniden Shiny bağlandığında sunucuya mevcut tema bilgisini gönder
  document.addEventListener('shiny:connected', function () {
    if (window.Shiny && typeof window.Shiny.setInputValue === 'function') {
      try {
        window.Shiny.setInputValue('mergen_theme_initial', {
          theme: window.MergenTheme.get(),
          ts: Date.now()
        }, { priority: 'event' });
      } catch (e) {
        // sessiz geç
      }
    }
    registerSettingsBridge();
  });

  // Bazı durumlarda Shiny zaten bağlıdır; bu yüzden Shiny global'i hazırsa
  // hemen kayıt eder, aksi halde DOM hazır olunca dener.
  if (window.Shiny && typeof window.Shiny.addCustomMessageHandler === 'function') {
    registerSettingsBridge();
  } else {
    document.addEventListener('DOMContentLoaded', function () {
      registerSettingsBridge();
    });
  }

  // Sayfa hazır olduğunda kenar çubuğundaki tema anahtarını bağla
  document.addEventListener('DOMContentLoaded', function () {
    bindThemeToggleButton();
    syncThemeToggleVisuals(window.MergenTheme.get());
  });

  // Şiny tekrar bağlandığında veya sidebar yeniden çizildiğinde butonu yeniden bağla
  document.addEventListener('shiny:value', function (event) {
    if (event && event.name === 'sidebar_user_panel') {
      window.setTimeout(function () {
        bindThemeToggleButton();
        syncThemeToggleVisuals(window.MergenTheme.get());
      }, 30);
    }
  });

  window.addEventListener('mergen:themechange', function (event) {
    var t = (event && event.detail && event.detail.theme) || window.MergenTheme.get();
    syncThemeToggleVisuals(t);
  });

  function bindThemeToggleButton() {
    var buttons = document.querySelectorAll('[data-mergen-theme-toggle]');
    if (!buttons || buttons.length === 0) {
      return;
    }

    buttons.forEach(function (btn) {
      if (btn.getAttribute('data-mergen-theme-bound') === 'true') {
        return;
      }
      btn.setAttribute('data-mergen-theme-bound', 'true');

      btn.addEventListener('click', function (ev) {
        ev.preventDefault();
        window.MergenTheme.toggle();
      });

      btn.addEventListener('keydown', function (ev) {
        if (ev.key === 'Enter' || ev.key === ' ') {
          ev.preventDefault();
          window.MergenTheme.toggle();
        }
      });
    });
  }

  function syncThemeToggleVisuals(theme) {
    var isLight = theme === 'light';
    var buttons = document.querySelectorAll('[data-mergen-theme-toggle]');
    if (!buttons || buttons.length === 0) {
      return;
    }

    buttons.forEach(function (btn) {
      btn.setAttribute('aria-pressed', isLight ? 'true' : 'false');
      btn.setAttribute('aria-label',
        isLight ? 'Koyu temaya geç' : 'Açık temaya geç');
      btn.setAttribute('title',
        isLight ? 'Koyu temaya geç' : 'Açık temaya geç');

      var thumb = btn.querySelector('.theme-switch-thumb');
      if (thumb) {
        thumb.setAttribute('data-active', isLight ? 'light' : 'dark');
      }

      var sunIcon = btn.querySelector('.theme-switch-sun');
      var moonIcon = btn.querySelector('.theme-switch-moon');
      if (sunIcon && moonIcon) {
        // Anahtar görseli aktif simgeyi vurgular
        sunIcon.classList.toggle('is-active', isLight);
        moonIcon.classList.toggle('is-active', !isLight);
      }

      var label = btn.querySelector('.theme-switch-label');
      if (label) {
        label.textContent = isLight ? 'Açık tema' : 'Koyu tema';
      }
    });
  }
})();
