// www/js/mode_selection.js
// Dosya Yolu: www/js/mode_selection.js
// Açıklama: Ayarlar sayfasındaki deneyim modu seçim kartlarını yönetir.
// Giriş ekranı modalı artık explore_cinematic.js tarafından yönetilir.
// Bu dosya yalnızca ayarlar sayfası mod kartlarını içerir.

(function() {
  'use strict';

  // Mod tanımları (ayarlar sayfası için)
  var MODE_DEFINITIONS = {
    odak: {
      id: 'odak',
      title: 'Odak',
      description: 'Hız ve verimlilik. Ekstra özellikler devre dışı kalır, ' +
        'yanıtlar doğrudan gelir. Hızlı karar almak ve işini kısa sürede ' +
        'bitirmek isteyenler için.'
    },
    denge: {
      id: 'denge',
      title: 'Denge',
      description: 'Konfor ve işlevsellik bir arada. Takip soruları ve arka ' +
        'plan müziği aktif olur. Günlük kullanımda hem üretken hem rahat ' +
        'bir deneyim sunar.'
    },
    kesif: {
      id: 'kesif',
      title: 'Tam Donanım',
      description: 'Tüm özellikler aktif. Sesli yanıtlar, takip soruları ' +
        've müzik dahil. Uygulamanın sunduğu her aracı deneyimlemek ' +
        'isteyenler için.'
    }
  };

  // Yazma animasyonu zamanlayıcıları
  var _typingTimers = {};

  // Doğal ritimli yazma animasyonu (ayarlar sayfası kartları için)
  function typeText(element, text, cardId) {
    if (_typingTimers[cardId]) {
      clearTimeout(_typingTimers[cardId]);
      _typingTimers[cardId] = null;
    }

    var index = 0;
    element.innerHTML = '<span class="typing-cursor"></span>';

    function typeNextChunk() {
      if (index >= text.length) {
        var cursor = element.querySelector('.typing-cursor');
        if (cursor) {
          setTimeout(function() { if (cursor.parentNode) cursor.remove(); }, 1500);
        }
        _typingTimers[cardId] = null;
        return;
      }

      var currentChar = text[index];
      var charsToAdd = 1;
      if (currentChar !== '.' && currentChar !== ',' && currentChar !== '!' &&
          currentChar !== '?' && currentChar !== ';') {
        charsToAdd = Math.floor(Math.random() * 3) + 1;
        charsToAdd = Math.min(charsToAdd, text.length - index);
      }

      var chunk = text.substring(index, index + charsToAdd);
      var cursor = element.querySelector('.typing-cursor');
      if (cursor) cursor.remove();
      element.innerHTML += chunk;
      element.innerHTML += '<span class="typing-cursor"></span>';

      index += charsToAdd;

      var delay;
      var lastAddedChar = chunk[chunk.length - 1];
      if (lastAddedChar === '.' || lastAddedChar === '!' || lastAddedChar === '?') {
        delay = 180 + Math.random() * 120;
      } else if (lastAddedChar === ',') {
        delay = 100 + Math.random() * 80;
      } else if (lastAddedChar === ' ') {
        delay = 30 + Math.random() * 40;
      } else {
        delay = 14 + Math.random() * 28;
      }

      _typingTimers[cardId] = setTimeout(typeNextChunk, delay);
    }

    typeNextChunk();
  }

  // Ayarlar sayfasından mod seçimi
  function selectModeFromSettings(mode) {
    if (!MODE_DEFINITIONS[mode]) return;

    var container = document.querySelector('.settings-mode-container');
    if (container) {
      container.querySelectorAll('.mode-card').forEach(function(card) {
        card.classList.toggle('selected', card.getAttribute('data-mode') === mode);
      });
    }

    if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
      Shiny.setInputValue('settings_module-experience_mode_changed', {
        mode: mode,
        source: 'settings',
        timestamp: Date.now()
      }, { priority: 'event' });
    }
  }

  // Ayarlar sayfası mod kartlarını başlat
  function initSettingsModeCards() {
    var container = document.querySelector('.settings-mode-container');
    if (!container || container.dataset.modeInitialized) return;
    container.dataset.modeInitialized = 'true';

    var cards = container.querySelectorAll('.mode-card');
    cards.forEach(function(card, i) {
      var mode = card.getAttribute('data-mode');
      var desc = card.querySelector('.mode-card-desc');

      if (desc && MODE_DEFINITIONS[mode]) {
        setTimeout(function() {
          typeText(desc, MODE_DEFINITIONS[mode].description, 'settings_' + mode);
        }, i * 500);
      }

      card.addEventListener('click', function() {
        selectModeFromSettings(mode);
      });
    });
  }

  // ============================================================
  // OLAY DİNLEYİCİLERİ (YALNIZCA AYARLAR SAYFASI)
  // ============================================================
  $(document).ready(function() {

    // İlk yüklemede derin uzay konteyneri varsa sidebar/header'ı gizle
    var dsContainer = document.getElementById('deep-space-container');
    if (dsContainer) {
      document.body.classList.add('deep-space-active');
    }

    // Ayarlar sekmesine geçişte mod kartlarını başlat
    $(document).on('click', '[data-value="settings"]', function() {
      setTimeout(initSettingsModeCards, 400);
    });

    // Shiny bağlantısında da başlat
    $(document).on('shiny:connected', function() {
      setTimeout(initSettingsModeCards, 800);
    });
  });

  // Global erişim
  window.ModeSelection = {
    selectFromSettings: selectModeFromSettings,
    initSettingsCards: initSettingsModeCards,
    definitions: MODE_DEFINITIONS
  };

})();
