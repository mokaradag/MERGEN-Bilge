// www/js/explore_cinematic.js
// Dosya Yolu: www/js/explore_cinematic.js
// Açıklama: Sinematik Keşfet butonu ve mod seçim modalı etkileşim mantığı.
// Spotlight kart ışıması, yazma animasyonu, kart seçim geçişleri ve
// modal açma/kapama işlemlerini yönetir.

(function() {
  'use strict';

  // Mod tanımları (açıklama metinleri)
  var CINEMATIC_MODES = {
    odak: {
      id: 'odak',
      title: 'Odak',
      description: 'Sistemin tüm gücünü tek bir noktaya yönlendirin. ' +
        'Dikkat dağıtıcı unsurlar kapalıdır; amaç en kısa sürede saf ' +
        'veriye ulaşmaktır. Hız ve verimlilik ön plandadır.',
      settings: {
        enable_tts_audio: false,
        enable_followups: false,
        enable_background_music: false
      }
    },
    denge: {
      id: 'denge',
      title: 'Dinamik',
      description: 'Düşüncelerinizi besleyen bir ortam. Akıllı takip ' +
        'önerileri ve odaklanmayı artıran akustik arka plan ile iş akışınızı ' +
        'derinleştirin. Konfor ve işlevsellik bir arada.',
      settings: {
        enable_tts_audio: false,
        enable_followups: true,
        enable_background_music: true
      }
    },
    kesif: {
      id: 'kesif',
      title: 'Bütünleşik',
      description: 'Sentetik seslendirme, proaktif analizler ve tam duyusal ' +
        'katılım. Sistemin yeteneklerinin doruk noktasında, eksiksiz bir ' +
        'deneyim yaşayın. Tüm özellikler aktif.',
      settings: {
        enable_tts_audio: true,
        enable_followups: true,
        enable_background_music: true
      }
    }
  };

  // Yazma animasyonu zamanlayıcıları
  var _typingTimers = {};

  // Seçili mod (seçim kilidi)
  var _selectedModeId = null;

  // Üzerinde durulan kart
  var _hoveredModeId = null;

  // ============================================================
  // YAZMA ANİMASYONU (Doğal ritimli daktilo efekti)
  // ============================================================
  function typeText(element, text, cardId) {
    // Önceki animasyonu temizle
    if (_typingTimers[cardId]) {
      clearTimeout(_typingTimers[cardId]);
      _typingTimers[cardId] = null;
    }

    var index = 0;
    element.innerHTML = '<span class="typing-cursor"></span>';

    function typeNextChar() {
      if (index >= text.length) {
        // Yazma tamamlandı, imleci kısa süre sonra kaldır
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
        delay += 300; // Noktalama işaretlerinde belirgin duraksama
      } else if (currentChar === ' ') {
        delay += 40; // Boşluklarda hafif duraksama
      } else if (Math.random() > 0.9) {
        delay += 80; // Arada doğal takılmalar
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
  // SPOTLIGHT KART İŞARETÇİ IŞIMASI
  // ============================================================
  function handleCardMouseMove(e) {
    if (_selectedModeId) return;

    var card = e.currentTarget;
    var rect = card.getBoundingClientRect();
    var x = e.clientX - rect.left;
    var y = e.clientY - rect.top;

    card.style.setProperty('--mouse-x', x + 'px');
    card.style.setProperty('--mouse-y', y + 'px');
  }

  function handleCardMouseEnter(card) {
    if (_selectedModeId) return;
    var mode = card.getAttribute('data-mode');
    _hoveredModeId = mode;

    // Yazma animasyonunu başlat
    var desc = card.querySelector('.cinematic-card-desc');
    if (desc && CINEMATIC_MODES[mode]) {
      typeText(desc, CINEMATIC_MODES[mode].description, 'cine_' + mode);
    }
  }

  function handleCardMouseLeave(card) {
    if (_selectedModeId) return;
    var mode = card.getAttribute('data-mode');
    _hoveredModeId = null;

    // Yazma animasyonunu durdur ve temizle
    var desc = card.querySelector('.cinematic-card-desc');
    resetTypeText(desc, 'cine_' + mode);
  }

  // ============================================================
  // MOD SEÇİMİ
  // ============================================================
  function selectMode(card) {
    if (_selectedModeId) return;

    var mode = card.getAttribute('data-mode');

    // Bütünleşik mod seçildiyse karakter seçim adımına yönlendir
    if (mode === 'kesif' && window.CinematicCharacterStep) {
      _selectedModeId = null;

      // Seçilen kartı animasyonla vurgula
      var allCards = document.querySelectorAll('.cinematic-mode-card');
      allCards.forEach(function(c) {
        if (c.getAttribute('data-mode') === mode) {
          c.classList.add('selected');
        } else {
          c.classList.add('other-selected');
        }
      });

      // Kısa gecikme ile 2. adıma geç
      setTimeout(function() {
        // Kart sınıflarını temizle
        allCards.forEach(function(c) {
          c.classList.remove('selected', 'other-selected');
        });
        window.CinematicCharacterStep.showCharacterStep();
      }, 600);
      return;
    }

    _selectedModeId = mode;

    // Seçilen kartı işaretle, diğerlerini soldur
    var overlay = document.getElementById('mode-modal-overlay');
    if (overlay) {
      overlay.classList.add('mode-selected');
    }

    var allCards = document.querySelectorAll('.cinematic-mode-card');
    allCards.forEach(function(c) {
      if (c.getAttribute('data-mode') === mode) {
        c.classList.add('selected');
      } else {
        c.classList.add('other-selected');
      }
    });

    // Kısa gecikme ile modalı kapat ve modu uygula
    setTimeout(function() {
      closeCinematicModal();

      // Modu Shiny'ye bildir
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

      // Giriş ekranını kapat
      dismissDeepSpace();

      // Durumu sıfırla
      _selectedModeId = null;
    }, 800);
  }

  // ============================================================
  // MODAL İŞLEMLERİ
  // ============================================================
  function openCinematicModal() {
    var overlay = document.getElementById('mode-modal-overlay');
    if (!overlay) return;

    // Durumu sıfırla
    _selectedModeId = null;
    _hoveredModeId = null;
    overlay.classList.remove('mode-selected');

    var allCards = overlay.querySelectorAll('.cinematic-mode-card');
    allCards.forEach(function(card) {
      card.classList.remove('selected', 'other-selected');
      var desc = card.querySelector('.cinematic-card-desc');
      if (desc) desc.innerHTML = '';
    });

    overlay.classList.add('active');
  }

  function closeCinematicModal() {
    var overlay = document.getElementById('mode-modal-overlay');
    if (!overlay) return;

    overlay.classList.remove('active');

    // Yazma animasyonlarını durdur
    Object.keys(_typingTimers).forEach(function(key) {
      if (key.indexOf('cine_') === 0 && _typingTimers[key]) {
        clearTimeout(_typingTimers[key]);
        _typingTimers[key] = null;
      }
    });

    // Kart durumlarını sıfırla
    setTimeout(function() {
      overlay.classList.remove('mode-selected');
      var allCards = overlay.querySelectorAll('.cinematic-mode-card');
      allCards.forEach(function(card) {
        card.classList.remove('selected', 'other-selected');
      });
      _selectedModeId = null;
      _hoveredModeId = null;
    }, 700);
  }

  // Giriş ekranını kapat
  function dismissDeepSpace() {
    var container = document.getElementById('deep-space-container');
    if (!container) return;

    container.classList.add('fade-out');
    setTimeout(function() {
      if (window.DeepSpaceIntro && window.DeepSpaceIntro.destroy) {
        window.DeepSpaceIntro.destroy();
      }
      if (container.parentNode) {
        container.parentNode.removeChild(container);
      }
      document.body.classList.remove('deep-space-active');
      document.body.classList.add('app-ready');
    }, 1200);
  }

  // ============================================================
  // OLAY DİNLEYİCİLERİ
  // ============================================================
  $(document).ready(function() {

    // Keşfet butonu tıklaması
    $(document).on('click', '#explore-btn', function(e) {
      e.preventDefault();
      e.stopPropagation();
      openCinematicModal();
    });

    // Modal arka plana tıklama ile kapat
    $(document).on('click', '.cinematic-modal-overlay', function(e) {
      if (e.target === this && !_selectedModeId) {
        closeCinematicModal();
      }
    });

    // Modal kapatma butonu
    $(document).on('click', '.cinematic-modal-close', function() {
      if (!_selectedModeId) {
        closeCinematicModal();
      }
    });

    // ESC tuşu ile kapat
    $(document).on('keydown', function(e) {
      if (e.key === 'Escape' && !_selectedModeId) {
        var overlay = document.getElementById('mode-modal-overlay');
        if (overlay && overlay.classList.contains('active')) {
          closeCinematicModal();
        }
      }
    });

    // Kart fare hareketleri (spotlight efekti)
    $(document).on('mousemove', '.cinematic-mode-card', function(e) {
      handleCardMouseMove(e);
    });

    // Kart fare girişi (yazma animasyonu başlat)
    $(document).on('mouseenter', '.cinematic-mode-card', function() {
      handleCardMouseEnter(this);
    });

    // Kart fare çıkışı (yazma animasyonunu durdur)
    $(document).on('mouseleave', '.cinematic-mode-card', function() {
      handleCardMouseLeave(this);
    });

    // Kart tıklaması (mod seçimi)
    $(document).on('click', '.cinematic-mode-card', function() {
      selectMode(this);
    });

    // Giriş ekranını atla onay kutusu
    $(document).on('change', '#skip-intro-checkbox', function() {
      var checked = $(this).prop('checked');
      if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
        Shiny.setInputValue('skip_intro_changed', {
          skip: checked,
          source: 'welcome',
          timestamp: Date.now()
        }, { priority: 'event' });
      }
      // localStorage'a kaydet
      try {
        var raw = localStorage.getItem('mergen_settings');
        var settings = raw ? JSON.parse(raw) : {};
        settings.skip_intro = checked;
        localStorage.setItem('mergen_settings', JSON.stringify(settings));
      } catch(e) {}
    });

    // Shiny mesaj handler'ları
    if (typeof Shiny !== 'undefined') {
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

      // Modal aç
      Shiny.addCustomMessageHandler('openModeModal', function(data) {
        openCinematicModal();
      });

      // Ayarlar mod kartlarını güncelle
      Shiny.addCustomMessageHandler('updateSettingsMode', function(data) {
        if (!data || !data.mode) return;
        var container = document.querySelector('.settings-mode-container');
        if (container) {
          container.querySelectorAll('.mode-card').forEach(function(card) {
            card.classList.toggle('selected', card.getAttribute('data-mode') === data.mode);
          });
        }
      });
    }
  });

  // Global erişim
  window.CinematicExplore = {
    openModal: openCinematicModal,
    closeModal: closeCinematicModal,
    dismissDeepSpace: dismissDeepSpace,
    definitions: CINEMATIC_MODES
  };

})();