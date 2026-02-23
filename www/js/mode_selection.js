// www/js/mode_selection.js
// Dosya Yolu: www/js/mode_selection.js
// Açıklama: Kullanıcı deneyim modu seçim yönetimi. Giriş ekranı modalı
// ve Ayarlar sayfası mod kartları arasındaki senkronizasyonu sağlar.

(function() {
  'use strict';

  // Mod tanımları
  var MODE_DEFINITIONS = {
    odak: {
      id: 'odak',
      title: 'Odak',
      icon: 'fas fa-bolt',
      description: 'Hız ve verimlilik. Ekstra özellikler devre dışı kalır, ' +
        'yanıtlar doğrudan gelir. Hızlı karar almak ve işini kısa sürede ' +
        'bitirmek isteyenler için.',
      settings: {
        enable_tts_audio: false,
        enable_followups: false,
        enable_background_music: false
      }
    },
    denge: {
      id: 'denge',
      title: 'Denge',
      icon: 'fas fa-compass',
      description: 'Konfor ve işlevsellik bir arada. Takip soruları ve arka ' +
        'plan müziği aktif olur. Günlük kullanımda hem üretken hem rahat ' +
        'bir deneyim sunar.',
      settings: {
        enable_tts_audio: false,
        enable_followups: true,
        enable_background_music: true
      }
    },
    kesif: {
      id: 'kesif',
      title: 'Tam Donanım',
      icon: 'fas fa-rocket',
      description: 'Tüm özellikler aktif. Sesli yanıtlar, takip soruları ' +
        've müzik dahil. Uygulamanın sunduğu her aracı deneyimlemek ' +
        'isteyenler için.',
      settings: {
        enable_tts_audio: true,
        enable_followups: true,
        enable_background_music: true
      }
    }
  };

  // Yazma animasyonu değişkenleri (her kart için ayrı)
  var _typingTimers = {};

  // Doğal ritimli yazma animasyonu
  // Noktalama işaretlerinde duraklama, değişken hız, karakter sayısı farkı
  function typeText(element, text, cardId) {
    // Önceki animasyonu iptal et
    if (_typingTimers[cardId]) {
      clearTimeout(_typingTimers[cardId]);
      _typingTimers[cardId] = null;
    }

    var index = 0;
    element.innerHTML = '<span class="typing-cursor"></span>';

    function typeNextChunk() {
      if (index >= text.length) {
        // Yazma tamamlandı, imleci kısa süre sonra kaldır
        var cursor = element.querySelector('.typing-cursor');
        if (cursor) {
          setTimeout(function() { if (cursor.parentNode) cursor.remove(); }, 1500);
        }
        _typingTimers[cardId] = null;
        return;
      }

      // Bir sonraki karakter
      var currentChar = text[index];

      // Kaç karakter eklenecek (1-3 arası değişken)
      var charsToAdd = 1;
      if (currentChar !== '.' && currentChar !== ',' && currentChar !== '!' &&
          currentChar !== '?' && currentChar !== ';') {
        charsToAdd = Math.floor(Math.random() * 3) + 1;
        charsToAdd = Math.min(charsToAdd, text.length - index);
      }

      var chunk = text.substring(index, index + charsToAdd);

      // İmleci kaldır, metin ekle, imleci tekrar ekle
      var cursor = element.querySelector('.typing-cursor');
      if (cursor) cursor.remove();
      element.innerHTML += chunk;
      element.innerHTML += '<span class="typing-cursor"></span>';

      index += charsToAdd;

      // Sonraki adım için gecikme hesapla (doğal ritim)
      var delay;
      var lastAddedChar = chunk[chunk.length - 1];

      if (lastAddedChar === '.' || lastAddedChar === '!' || lastAddedChar === '?') {
        // Cümle sonu: uzun duraklama
        delay = 180 + Math.random() * 120;
      } else if (lastAddedChar === ',') {
        // Virgül: orta duraklama
        delay = 100 + Math.random() * 80;
      } else if (lastAddedChar === ' ') {
        // Boşluk: kısa duraklama
        delay = 30 + Math.random() * 40;
      } else {
        // Normal karakter: temel hız + rastgele varyasyon
        delay = 14 + Math.random() * 28;
      }

      _typingTimers[cardId] = setTimeout(typeNextChunk, delay);
    }

    typeNextChunk();
  }

  // ============================================================
  // MODAL İŞLEMLERİ
  // ============================================================
  function openModeModal() {
    var overlay = document.getElementById('mode-modal-overlay');
    if (!overlay) return;
    overlay.classList.add('active');

    // Açıklama animasyonlarını kademeli olarak başlat
    // Her kart arasında belirgin gecikme (700ms) ve açılış gecikmesi (400ms)
    setTimeout(function() {
      var cards = overlay.querySelectorAll('.mode-card');
      cards.forEach(function(card, i) {
        var desc = card.querySelector('.mode-card-desc');
        var mode = card.getAttribute('data-mode');
        if (desc && MODE_DEFINITIONS[mode]) {
          // Her kart 700ms arayla başlar (belirgin kademeli efekt)
          setTimeout(function() {
            typeText(desc, MODE_DEFINITIONS[mode].description, 'modal_' + mode);
          }, i * 700);
        }
      });
    }, 400);
  }

  function closeModeModal() {
    var overlay = document.getElementById('mode-modal-overlay');
    if (overlay) {
      overlay.classList.remove('active');
    }
    // Yazma animasyonlarını durdur
    Object.keys(_typingTimers).forEach(function(key) {
      if (key.indexOf('modal_') === 0 && _typingTimers[key]) {
        clearTimeout(_typingTimers[key]);
        _typingTimers[key] = null;
      }
    });
  }

  // Mod seçimi ve uygulama (modal üzerinden)
  function selectModeFromModal(mode) {
    if (!MODE_DEFINITIONS[mode]) return;

    // Modalı kapat
    closeModeModal();

    // Mod ayarlarını Shiny'ye gönder
    if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
      Shiny.setInputValue('selected_experience_mode', {
        mode: mode,
        source: 'welcome',
        timestamp: Date.now()
      }, { priority: 'event' });
    }

    // localStorage'a kaydet
    try {
      var raw = localStorage.getItem('mergen_settings');
      var settings = raw ? JSON.parse(raw) : {};
      settings.experience_mode = mode;
      localStorage.setItem('mergen_settings', JSON.stringify(settings));
    } catch(e) {}

    // Giriş ekranını kapat ve uygulamaya geç
    dismissDeepSpace();
  }

  // Mod seçimi (Ayarlar sayfasından)
  function selectModeFromSettings(mode) {
    if (!MODE_DEFINITIONS[mode]) return;

    // Ayarlar sayfasındaki butonları güncelle
    var container = document.querySelector('.settings-mode-container');
    if (container) {
      container.querySelectorAll('.mode-card').forEach(function(card) {
        card.classList.toggle('selected', card.getAttribute('data-mode') === mode);
      });
    }

    // Shiny'ye mod değişikliğini bildir (Ayarlar sayfasından)
    if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
      Shiny.setInputValue('settings_module-experience_mode_changed', {
        mode: mode,
        source: 'settings',
        timestamp: Date.now()
      }, { priority: 'event' });
    }
  }

  // Giriş ekranını kapat
  function dismissDeepSpace() {
    var container = document.getElementById('deep-space-container');
    if (!container) return;

    container.classList.add('fade-out');
    setTimeout(function() {
      // Three.js sahnesini temizle
      if (window.DeepSpaceIntro && window.DeepSpaceIntro.destroy) {
        window.DeepSpaceIntro.destroy();
      }
      if (container.parentNode) {
        container.parentNode.removeChild(container);
      }
      // Sidebar ve header'ı tekrar göster
      document.body.classList.remove('deep-space-active');
      // Uygulamayı hazır olarak işaretle
      document.body.classList.add('app-ready');
    }, 1200);
  }

  // ============================================================
  // AYARLAR SAYFASI MOD KARTLARI İÇİN YAZMA ANİMASYONU
  // ============================================================
  function initSettingsModeCards() {
    var container = document.querySelector('.settings-mode-container');
    if (!container || container.dataset.modeInitialized) return;
    container.dataset.modeInitialized = 'true';

    var cards = container.querySelectorAll('.mode-card');
    cards.forEach(function(card, i) {
      var mode = card.getAttribute('data-mode');
      var desc = card.querySelector('.mode-card-desc');

      // Açıklama yazma animasyonu (kademeli başlat)
      if (desc && MODE_DEFINITIONS[mode]) {
        setTimeout(function() {
          typeText(desc, MODE_DEFINITIONS[mode].description, 'settings_' + mode);
        }, i * 500);
      }

      // Tıklama olayı
      card.addEventListener('click', function() {
        selectModeFromSettings(mode);
      });
    });
  }

  // ============================================================
  // SHINY MESAJ HANDLERLARI
  // ============================================================
  $(document).ready(function() {

    // İlk yüklemede derin uzay konteyneri varsa sidebar/header'ı gizle
    var dsContainer = document.getElementById('deep-space-container');
    if (dsContainer) {
      document.body.classList.add('deep-space-active');
    }

    // Giriş ekranını başlat
    Shiny.addCustomMessageHandler('initDeepSpace', function(data) {
      var container = document.getElementById('deep-space-canvas');
      if (container && window.DeepSpaceIntro) {
        window.DeepSpaceIntro.init('deep-space-canvas', {
          texturePath: data.texturePath || 'lib/threejs/textures/'
        });
      }
    });

    // Giriş ekranını kapat
    Shiny.addCustomMessageHandler('dismissDeepSpace', function(data) {
      dismissDeepSpace();
    });

    // Mod seçim modalını aç
    Shiny.addCustomMessageHandler('openModeModal', function(data) {
      openModeModal();
    });

    // Ayarlar sayfasındaki mod seçimini güncelle
    Shiny.addCustomMessageHandler('updateSettingsMode', function(data) {
      if (!data || !data.mode) return;
      var container = document.querySelector('.settings-mode-container');
      if (container) {
        container.querySelectorAll('.mode-card').forEach(function(card) {
          card.classList.toggle('selected', card.getAttribute('data-mode') === data.mode);
        });
        // Yazma animasyonunu yeniden başlat
        var selectedCard = container.querySelector('.mode-card[data-mode="' + data.mode + '"]');
        if (selectedCard) {
          var desc = selectedCard.querySelector('.mode-card-desc');
          if (desc && MODE_DEFINITIONS[data.mode]) {
            typeText(desc, MODE_DEFINITIONS[data.mode].description, 'settings_' + data.mode);
          }
        }
      }
    });

    // Giriş ekranını atla onay kutusu değişikliği
    $(document).on('change', '#skip-intro-checkbox', function() {
      var checked = $(this).prop('checked');
      if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
        Shiny.setInputValue('skip_intro_changed', {
          skip: checked,
          source: 'welcome',
          timestamp: Date.now()
        }, { priority: 'event' });
      }
      // localStorage'a da kaydet
      try {
        var raw = localStorage.getItem('mergen_settings');
        var settings = raw ? JSON.parse(raw) : {};
        settings.skip_intro = checked;
        localStorage.setItem('mergen_settings', JSON.stringify(settings));
      } catch(e) {}
    });

    // Keşfet butonu tıklaması
    $(document).on('click', '#explore-btn', function() {
      openModeModal();
    });

    // Modal dış alana tıklayınca kapat
    $(document).on('click', '#mode-modal-overlay', function(e) {
      if (e.target === this) {
        closeModeModal();
      }
    });

    // Modal kapatma butonu
    $(document).on('click', '.mode-modal-close', function() {
      closeModeModal();
    });

    // Modal içi mod kartı tıklaması
    $(document).on('click', '#mode-modal-overlay .mode-card', function() {
      var mode = $(this).attr('data-mode');
      if (mode) {
        // Seçim görsel geri bildirimi
        $(this).closest('.mode-cards-container').find('.mode-card').removeClass('selected');
        $(this).addClass('selected');

        // Küçük bir gecikme ile uygula (animasyonun görünmesi için)
        setTimeout(function() {
          selectModeFromModal(mode);
        }, 400);
      }
    });

    // ESC tuşu ile modalı kapat
    $(document).on('keydown', function(e) {
      if (e.key === 'Escape') {
        closeModeModal();
      }
    });

    // Ayarlar sekmesine geçişte mod kartlarını başlat
    $(document).on('click', '[data-value="settings"]', function() {
      setTimeout(initSettingsModeCards, 400);
    });

    // Shiny bağlantısında da başlat (sayfa yenilendiğinde Ayarlar açık olabilir)
    $(document).on('shiny:connected', function() {
      setTimeout(initSettingsModeCards, 800);
    });
  });

  // Global erişim
  window.ModeSelection = {
    openModal: openModeModal,
    closeModal: closeModeModal,
    selectFromModal: selectModeFromModal,
    selectFromSettings: selectModeFromSettings,
    dismissDeepSpace: dismissDeepSpace,
    initSettingsCards: initSettingsModeCards,
    definitions: MODE_DEFINITIONS
  };

})();