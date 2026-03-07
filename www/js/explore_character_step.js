// www/js/explore_character_step.js
// Dosya Yolu: www/js/explore_character_step.js
// Aciklama: Butunlesik mod karakter secim adimi etkilesim mantigi.
// Mod secim modalinda 2. adim olarak karakter secimini yonetir.

(function() {
  'use strict';

  // Secili karakter ID
  var _selectedCharId = 'mergen';

  // Karakter verileri (R tarafindan doldurulacak)
  var _charactersData = null;

  // Adim durumu
  var _currentStep = 1;

  // ============================================================
  // KARAKTER VERISINI YUKLE
  // ============================================================
  function loadCharactersData(data) {
    _charactersData = data;
  }

  // ============================================================
  // 2. ADIMA GEC (KARAKTER SECIMI)
  // ============================================================
  function showCharacterStep() {
    _currentStep = 2;

    // 1. adim icerigini gizle
    var cardsGrid = document.querySelector('.cinematic-cards-grid');
    var modalHeader = document.querySelector('.cinematic-modal-header');
    if (cardsGrid) cardsGrid.classList.add('hidden-step');
    if (modalHeader) modalHeader.classList.add('hidden-step');

    // Adim gostergesini guncelle
    updateStepIndicator(2);

    // 2. adim icerigini goster
    var charStep = document.getElementById('cinematic-character-step');
    if (charStep) {
      charStep.classList.add('active');
      // Varsayilan karakteri goster
      selectCharacterInModal(_selectedCharId, false);
    }
  }

  // ============================================================
  // 1. ADIMA GER DON
  // ============================================================
  function showModeStep() {
    _currentStep = 1;

    // 2. adim icerigini gizle
    var charStep = document.getElementById('cinematic-character-step');
    if (charStep) charStep.classList.remove('active');

    // 1. adim icerigini goster
    var cardsGrid = document.querySelector('.cinematic-cards-grid');
    var modalHeader = document.querySelector('.cinematic-modal-header');
    if (cardsGrid) cardsGrid.classList.remove('hidden-step');
    if (modalHeader) modalHeader.classList.remove('hidden-step');

    // Adim gostergesini guncelle
    updateStepIndicator(1);

    // Mod secim durumunu sifirla (tekrar secilebilsin)
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
  // ADIM GOSTERGE CUBUGUNU GUNCELLE
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
  // MODALDA KARAKTER SEC
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

    // Butonlari guncelle
    var buttons = document.querySelectorAll('.cinematic-char-btn');
    buttons.forEach(function(btn) {
      btn.classList.toggle('active', btn.getAttribute('data-character') === charId);
    });

    // Gorseli guncelle
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

    // Isim yerlesimini guncelle
    var displayName = document.querySelector('.cinematic-char-display-name');
    var subtitleEl = document.querySelector('.cinematic-char-subtitle');
    if (displayName) displayName.textContent = charData.display_name;
    if (subtitleEl) subtitleEl.textContent = charData.subtitle;

    // Hikaye metnini guncelle
    var loreEl = document.querySelector('.cinematic-char-lore');
    if (loreEl) {
      loreEl.textContent = charData.lore_tr;
    }

    // Metrikleri guncelle (animasyonlu)
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

        // Cubuk animasyonu
        var fill = metricEl.querySelector('.cinematic-char-metric-fill');
        if (fill) {
          setTimeout(function() {
            fill.style.width = metric.value + '%';
          }, 100 + idx * 80);
        }
      });
    }

    // Imza hareketlerini guncelle
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

    // Sec butonunun rengini guncelle
    var selectBtn = document.querySelector('.cinematic-char-select-btn');
    if (selectBtn && charData.accent) {
      selectBtn.style.background = 'linear-gradient(135deg, ' + charData.accent + ' 0%, rgba(52, 211, 153, 0.4) 100%)';
      selectBtn.style.boxShadow = '0 4px 24px ' + charData.accent + '33';
    }
  }

  // ============================================================
  // KARAKTER ONAYLANDIGINDA
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

    // Modali kapat
    if (window.CinematicExplore) {
      window.CinematicExplore.closeModal();
    }

    // Giris ekranini kapat
    setTimeout(function() {
      if (window.CinematicExplore) {
        window.CinematicExplore.dismissDeepSpace();
      }
    }, 200);

    // Durumu sifirla
    _currentStep = 1;
  }

  // ============================================================
  // OLAY DINLEYICILERI
  // ============================================================
  $(document).ready(function() {

    // Karakter butonlarina tiklama
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

    // Sec ve basla butonu
    $(document).on('click', '.cinematic-char-select-btn', function() {
      confirmCharacterSelection();
    });

    // Shiny mesaj dinleyicisi: karakter verilerini yukle
    if (typeof Shiny !== 'undefined') {
      Shiny.addCustomMessageHandler('loadCinematicCharacters', function(data) {
        if (data && data.characters) {
          loadCharactersData(data.characters);
        }
      });
    }
  });

  // Global erisim
  window.CinematicCharacterStep = {
    showCharacterStep: showCharacterStep,
    showModeStep: showModeStep,
    loadCharactersData: loadCharactersData,
    confirmSelection: confirmCharacterSelection
  };

})();
