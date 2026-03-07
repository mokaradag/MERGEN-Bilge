// www/js/explore_character_step.js
// Dosya Yolu: www/js/explore_character_step.js
// Açıklama: Bütünleşik mod karakter seçim adımı etkileşim mantığı.
// Mod seçim modalında 2. adım olarak karakter seçimini yönetir.

(function() {
  'use strict';

  // Seçili karakter ID
  var _selectedCharId = 'mergen';

  // Karakter verileri (R tarafından doldurulacak)
  var _charactersData = null;

  // Adım durumu
  var _currentStep = 1;

  // ============================================================
  // KARAKTER VERİSİNİ YÜKLE
  // ============================================================
  function loadCharactersData(data) {
    _charactersData = data;
  }

  // ============================================================
  // 2. ADIMA GEÇ (KARAKTER SEÇİMİ)
  // ============================================================
  function showCharacterStep() {
    _currentStep = 2;

    // 1. adım içeriğini gizle
    var cardsGrid = document.querySelector('.cinematic-cards-grid');
    var modalHeader = document.querySelector('.cinematic-modal-header');
    if (cardsGrid) cardsGrid.classList.add('hidden-step');
    if (modalHeader) modalHeader.classList.add('hidden-step');

    // Adım göstergesini güncelle
    updateStepIndicator(2);

    // 2. adım içeriğini göster
    var charStep = document.getElementById('cinematic-character-step');
    if (charStep) {
      charStep.classList.add('active');
      // Varsayılan karakteri göster
      selectCharacterInModal(_selectedCharId, false);
    }
  }

  // ============================================================
  // 1. ADIMA GERİ DÖN
  // ============================================================
  function showModeStep() {
    _currentStep = 1;

    // 2. adım içeriğini gizle
    var charStep = document.getElementById('cinematic-character-step');
    if (charStep) charStep.classList.remove('active');

    // 1. adım içeriğini göster
    var cardsGrid = document.querySelector('.cinematic-cards-grid');
    var modalHeader = document.querySelector('.cinematic-modal-header');
    if (cardsGrid) cardsGrid.classList.remove('hidden-step');
    if (modalHeader) modalHeader.classList.remove('hidden-step');

    // Adım göstergesini güncelle
    updateStepIndicator(1);

    // Mod seçim durumunu sıfırla (tekrar seçilebilsin)
    if (window.CinematicExplore) {
      var overlay = document.getElementById('mode-modal-overlay');
      if (overlay) {
        overlay.classList.remove('mode-selected');
        var allCards = overlay.querySelectorAll('.cinematic-mode-card');
        allCards.forEach(function(card) {
          card.classList.remove('selected', 'other-selected');
        });
      }
    }
  }

  // ============================================================
  // ADIM GÖSTERGE ÇUBUĞUNU GÜNCELLE
  // ============================================================
  function updateStepIndicator(step) {
    var indicator = document.querySelector('.cinematic-step-indicator');
    if (!indicator) return;

    indicator.classList.add('visible');

    var dots = indicator.querySelectorAll('.cinematic-step-dot');
    var line = indicator.querySelector('.cinematic-step-line');

    if (dots.length >= 2) {
      dots[0].classList.toggle('active', step === 1);
      dots[0].classList.toggle('completed', step > 1);
      dots[1].classList.toggle('active', step === 2);
      dots[1].classList.remove('completed');
    }
    if (line) {
      line.classList.toggle('completed', step > 1);
    }
  }

  // ============================================================
  // MODALDA KARAKTER SEÇ
  // ============================================================
  function selectCharacterInModal(charId, animate) {
    if (!_charactersData) return;

    _selectedCharId = charId;

    // Karakteri bul
    var charData = null;
    for (var i = 0; i < _charactersData.length; i++) {
      if (_charactersData[i].id === charId) {
        charData = _charactersData[i];
        break;
      }
    }
    if (!charData) return;

    // Butonları güncelle
    var buttons = document.querySelectorAll('.cinematic-char-btn');
    buttons.forEach(function(btn) {
      btn.classList.toggle('active', btn.getAttribute('data-character') === charId);
    });

    // Görseli güncelle
    var imgWrapper = document.querySelector('.cinematic-char-image-wrapper');
    if (imgWrapper) {
      var img = imgWrapper.querySelector('img');
      if (img) {
        if (animate !== false) {
          img.style.opacity = '0';
          setTimeout(function() {
            img.src = charData.image;
            img.style.opacity = '1';
          }, 250);
        } else {
          img.src = charData.image;
        }
      }
    }

    // İsim yerleşimini güncelle
    var displayName = document.querySelector('.cinematic-char-display-name');
    var subtitleEl = document.querySelector('.cinematic-char-subtitle');
    if (displayName) displayName.textContent = charData.display_name;
    if (subtitleEl) subtitleEl.textContent = charData.subtitle;

    // Hikaye metnini güncelle
    var loreEl = document.querySelector('.cinematic-char-lore');
    if (loreEl) {
      loreEl.textContent = charData.lore_tr;
    }

    // Metrikleri güncelle (animasyonlu)
    var metricsContainer = document.querySelector('.cinematic-char-metrics');
    if (metricsContainer && charData.profile_metrics) {
      metricsContainer.innerHTML = '';
      charData.profile_metrics.forEach(function(metric, idx) {
        var metricEl = document.createElement('div');
        metricEl.className = 'cinematic-char-metric';
        metricEl.innerHTML =
          '<span class="cinematic-char-metric-label">' + metric.label + '</span>' +
          '<div class="cinematic-char-metric-bar">' +
            '<div class="cinematic-char-metric-fill" style="background: ' + charData.accent + ';"></div>' +
          '</div>' +
          '<span class="cinematic-char-metric-value">' + metric.value + '</span>';
        metricsContainer.appendChild(metricEl);

        // Çubuk animasyonu
        var fill = metricEl.querySelector('.cinematic-char-metric-fill');
        if (fill) {
          setTimeout(function() {
            fill.style.width = metric.value + '%';
          }, 100 + idx * 80);
        }
      });
    }

    // İmza hareketlerini güncelle
    var sigContainer = document.querySelector('.cinematic-char-signatures');
    if (sigContainer && charData.signature_moves) {
      sigContainer.innerHTML = '';
      charData.signature_moves.forEach(function(move) {
        var tag = document.createElement('span');
        tag.className = 'cinematic-char-signature-tag';
        tag.textContent = move;
        sigContainer.appendChild(tag);
      });
    }

    // Seç butonunun rengini güncelle
    var selectBtn = document.querySelector('.cinematic-char-select-btn');
    if (selectBtn && charData.accent) {
      selectBtn.style.background = 'linear-gradient(135deg, ' + charData.accent + ' 0%, rgba(52, 211, 153, 0.4) 100%)';
      selectBtn.style.boxShadow = '0 4px 24px ' + charData.accent + '33';
    }
  }

  // ============================================================
  // KARAKTER ONAYLANDIĞINDA
  // ============================================================
  function confirmCharacterSelection() {
    if (!_selectedCharId) return;

    // Shiny'ye bildir: karakter + mod birlikte
    if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
      Shiny.setInputValue('selected_experience_mode', {
        mode: 'kesif',
        character: _selectedCharId,
        source: 'welcome_character_step',
        timestamp: Date.now()
      }, { priority: 'event' });
    }

    // localStorage'a kaydet
    try {
      var raw = localStorage.getItem('mergen_settings');
      var settings = raw ? JSON.parse(raw) : {};
      settings.experience_mode = 'kesif';
      settings.selected_character = _selectedCharId;
      localStorage.setItem('mergen_settings', JSON.stringify(settings));
    } catch(e) {}

    // Modalı kapat
    if (window.CinematicExplore) {
      window.CinematicExplore.closeModal();
    }

    // Giriş ekranını kapat
    setTimeout(function() {
      if (window.CinematicExplore) {
        window.CinematicExplore.dismissDeepSpace();
      }
    }, 200);

    // Durumu sıfırla
    _currentStep = 1;
  }

  // ============================================================
  // OLAY DİNLEYİCİLERİ
  // ============================================================
  $(document).ready(function() {

    // Karakter butonlarına tıklama
    $(document).on('click', '.cinematic-char-btn', function() {
      var charId = $(this).attr('data-character');
      if (charId) {
        selectCharacterInModal(charId, true);
      }
    });

    // Geri butonu
    $(document).on('click', '.cinematic-char-back-btn', function() {
      showModeStep();
    });

    // Seç ve başla butonu
    $(document).on('click', '.cinematic-char-select-btn', function() {
      confirmCharacterSelection();
    });

    // Shiny mesaj dinleyicisi: karakter verilerini yükle
    if (typeof Shiny !== 'undefined') {
      Shiny.addCustomMessageHandler('loadCinematicCharacters', function(data) {
        if (data && data.characters) {
          loadCharactersData(data.characters);
        }
      });
    }
  });

  // Global erişim
  window.CinematicCharacterStep = {
    showCharacterStep: showCharacterStep,
    showModeStep: showModeStep,
    loadCharactersData: loadCharactersData,
    confirmSelection: confirmCharacterSelection
  };

})();