// www/js/mode_selection.js
// Dosya Yolu: www/js/mode_selection.js
// Açıklama: Ayarlar sayfasındaki deneyim modu seçim kartlarını yönetir.
// Sinematik modalla aynı deneyimi sağlar: spotlight ışıma, yazma animasyonu,
// fare takibi ve kart seçim geçişleri.
// Giriş ekranı modalı explore_cinematic.js tarafından yönetilir.

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
      title: 'Dinamik',
      description: 'Konfor ve işlevsellik bir arada. Takip soruları ve arka ' +
        'plan müziği aktif olur. Günlük kullanımda hem üretken hem rahat ' +
        'bir deneyim sunar.'
    },
    kesif: {
      id: 'kesif',
      title: 'Bütünleşik',
      description: 'Tüm özellikler aktif. Sesli yanıtlar, takip soruları ' +
        've müzik dahil. Uygulamanın sunduğu her aracı deneyimlemek ' +
        'isteyenler için.'
    }
  };

  // Yazma animasyonu zamanlayıcıları
  var _typingTimers = {};

  // ============================================================
  // YAZMA ANİMASYONU (Doğal ritimli daktilo efekti)
  // ============================================================
  function typeText(element, text, cardId) {
    if (_typingTimers[cardId]) {
      clearTimeout(_typingTimers[cardId]);
      _typingTimers[cardId] = null;
    }

    var index = 0;
    element.innerHTML = '<span class="typing-cursor"></span>';

    function typeNextChar() {
      if (index >= text.length) {
        var cursor = element.querySelector('.typing-cursor');
        if (cursor) {
          setTimeout(function() { if (cursor.parentNode) cursor.remove(); }, 1500);
        }
        _typingTimers[cardId] = null;
        return;
      }

      var currentChar = text.charAt(index);

      // İmleci kaldır, metin ekle, imleci tekrar ekle
      var cursor = element.querySelector('.typing-cursor');
      if (cursor) cursor.remove();

      var textNode = document.createTextNode(currentChar);
      element.appendChild(textNode);

      var newCursor = document.createElement('span');
      newCursor.className = 'typing-cursor';
      element.appendChild(newCursor);

      index++;

      // Dinamik hız (doğal daktilo/klavye efekti)
      var delay = 20 + (Math.random() * 20 - 10);

      if (currentChar === '.' || currentChar === ',' ||
          currentChar === '!' || currentChar === '?') {
        delay += 280;
      } else if (currentChar === ' ') {
        delay += 35;
      } else if (Math.random() > 0.9) {
        delay += 70;
      }

      _typingTimers[cardId] = setTimeout(typeNextChar, delay);
    }

    _typingTimers[cardId] = setTimeout(typeNextChar, 20);
  }

  // Yazma animasyonunu sıfırla
  function resetTypeText(element, cardId) {
    if (_typingTimers[cardId]) {
      clearTimeout(_typingTimers[cardId]);
      _typingTimers[cardId] = null;
    }
    if (element) {
      element.innerHTML = '';
    }
  }

  // ============================================================
  // SPOTLIGHT FARE TAKİBİ (Sinematik kart ışıması)
  // ============================================================
  function handleSettingsCardMouseMove(e) {
    var card = e.currentTarget;
    var rect = card.getBoundingClientRect();
    var x = e.clientX - rect.left;
    var y = e.clientY - rect.top;

    card.style.setProperty('--mouse-x', x + 'px');
    card.style.setProperty('--mouse-y', y + 'px');
  }

  function handleSettingsCardMouseEnter(card) {
    var mode = card.getAttribute('data-mode');
    var desc = card.querySelector('.mode-card-desc');

    // Yazma animasyonunu başlat
    if (desc && MODE_DEFINITIONS[mode]) {
      typeText(desc, MODE_DEFINITIONS[mode].description, 'settings_' + mode);
    }
  }

  function handleSettingsCardMouseLeave(card) {
    var mode = card.getAttribute('data-mode');
    var desc = card.querySelector('.mode-card-desc');

    // Seçili kart değilse yazma animasyonunu durdur
    if (!card.classList.contains('selected')) {
      resetTypeText(desc, 'settings_' + mode);
    }
  }

  // ============================================================
  // MOD SEÇİMİ
  // ============================================================
  function selectModeFromSettings(mode) {
    if (!MODE_DEFINITIONS[mode]) return;

    var container = document.querySelector('.settings-mode-container');
    if (container) {
      container.querySelectorAll('.mode-card').forEach(function(card) {
        var isSelected = card.getAttribute('data-mode') === mode;
        card.classList.toggle('selected', isSelected);

        // Seçili kart için açıklamayı göster
        if (isSelected) {
          var desc = card.querySelector('.mode-card-desc');
          if (desc && desc.textContent.trim() === '') {
            typeText(desc, MODE_DEFINITIONS[mode].description, 'settings_' + mode);
          }
        }
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
    cards.forEach(function(card) {
      var mode = card.getAttribute('data-mode');

      // Seçili kartın açıklamasını ilk yüklemede göster
      if (card.classList.contains('selected')) {
        var desc = card.querySelector('.mode-card-desc');
        if (desc && MODE_DEFINITIONS[mode]) {
          setTimeout(function() {
            typeText(desc, MODE_DEFINITIONS[mode].description, 'settings_' + mode);
          }, 300);
        }
      }

      // Tıklama ile seçim
      card.addEventListener('click', function() {
        selectModeFromSettings(mode);
      });

      // Spotlight fare takibi
      card.addEventListener('mousemove', handleSettingsCardMouseMove);

      // Fare giriş/çıkış olayları
      card.addEventListener('mouseenter', function() {
        handleSettingsCardMouseEnter(card);
      });
      card.addEventListener('mouseleave', function() {
        handleSettingsCardMouseLeave(card);
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
