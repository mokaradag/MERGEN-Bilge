// www/js/settings_model_info.js
// Dosya Yolu: www/js/settings_model_info.js
// Açıklama: Yapılandırma sayfasındaki "Model Ayarları" kartında model seçimi
//           yapıldığında bilgi panelini güncelleyen, yazma animasyonu, bağlam
//           boyutu rozeti ve düşünme yeteneği ikonunu yöneten betik.

(function() {
  'use strict';

  // Yazma efekti değişkenleri
  var _modelTypingTimer = null;
  var _modelTypingIndex = 0;
  var _modelTypingText = '';

  // Son seçilen model (gereksiz animasyonları önlemek için)
  var _lastSelectedModel = null;

  // NS ön eki (Shiny modül ad alanı)
  var NS_PREFIX = 'settings_yapilandirma_module-';

  /**
   * Yazma efekti ile açıklama göster
   * @param {HTMLElement} element - Hedef eleman
   * @param {string} text - Yazılacak metin
   */
  function typeModelDescription(element, text) {
    // Önceki animasyonu iptal et
    if (_modelTypingTimer) {
      clearInterval(_modelTypingTimer);
      _modelTypingTimer = null;
    }

    _modelTypingText = text;
    _modelTypingIndex = 0;
    element.innerHTML = '<span class="typing-cursor"></span>';

    _modelTypingTimer = setInterval(function() {
      if (_modelTypingIndex < _modelTypingText.length) {
        // Her adımda 2-3 karakter ekle (hızlı ve akıcı yazma)
        var charsToAdd = Math.min(3, _modelTypingText.length - _modelTypingIndex);
        var chunk = _modelTypingText.substring(_modelTypingIndex, _modelTypingIndex + charsToAdd);

        // İmleci kaldır, metin ekle, imleci geri koy
        var cursorEl = element.querySelector('.typing-cursor');
        if (cursorEl) cursorEl.remove();
        element.innerHTML += chunk;
        element.innerHTML += '<span class="typing-cursor"></span>';

        _modelTypingIndex += charsToAdd;
      } else {
        clearInterval(_modelTypingTimer);
        _modelTypingTimer = null;
        // Animasyon bittikten sonra imleci kaldır
        var cursorEl = element.querySelector('.typing-cursor');
        if (cursorEl) {
          setTimeout(function() { if (cursorEl.parentNode) cursorEl.remove(); }, 1200);
        }
      }
    }, 18);
  }

  /**
   * Model bilgi panelini güncelle
   * @param {string} modelId - Seçilen modelin teknik kimliği
   * @param {object} meta - Model meta verisi
   * @param {boolean} animate - Animasyon uygulansın mı
   */
  function updateModelInfoPanel(modelId, meta, animate) {
    var panel = document.getElementById(NS_PREFIX + 'model_info_panel');
    if (!panel || !meta) return;

    var descEl = panel.querySelector('.model-info-description');
    var contextEl = panel.querySelector('.context-value');
    var contextBadge = panel.querySelector('.context-badge');
    var thinkingBadge = panel.querySelector('.thinking-badge');

    // Açıklama
    if (descEl && meta.description) {
      if (animate) {
        typeModelDescription(descEl, meta.description);
      } else {
        descEl.textContent = meta.description;
      }
    }

    // Bağlam boyutu
    if (contextEl) {
      contextEl.textContent = meta.context_size || '-';
    }
    // Bağlam rozeti tooltip
    if (contextBadge) {
      contextBadge.setAttribute('title', 'Ba\u011Flam penceresi: ' + (meta.context_size || '-') + ' token');
    }

    // Düşünme yeteneği
    if (thinkingBadge) {
      thinkingBadge.classList.remove('thinking-active', 'thinking-inactive');
      if (meta.thinking) {
        thinkingBadge.classList.add('thinking-active');
        thinkingBadge.setAttribute('title', 'Bu model geli\u015Fmi\u015F ak\u0131l y\u00FCr\u00FCtme (thinking) yetene\u011Fine sahip');
      } else {
        thinkingBadge.classList.add('thinking-inactive');
        thinkingBadge.setAttribute('title', 'Bu model d\u00FC\u015F\u00FCnme (thinking) yetene\u011Fini desteklemiyor');
      }
    }

    // Animasyon sınıfı (yalnızca model değiştiğinde)
    if (animate) {
      panel.classList.remove('animate-in');
      void panel.offsetWidth;
      panel.classList.add('animate-in');
    }
  }

  /**
   * Dropdown seçeneklerine emoji ikonlar ekle
   * @param {HTMLSelectElement} select - Hedef select elemanı
   * @param {object} allMeta - Tüm modellerin meta verisi
   */
  function addDropdownIcons(select, allMeta) {
    if (!select || !allMeta) return;
    var options = select.querySelectorAll('option');
    options.forEach(function(opt) {
      var modelId = opt.value;
      var meta = allMeta[modelId];
      if (!meta || !meta.icon) return;
      // İkon zaten eklenmişse tekrar ekleme
      var text = opt.textContent;
      if (text.indexOf(meta.icon) !== -1) return;
      // Emoji ikonu başa ekle
      opt.textContent = meta.icon + ' ' + text;
    });
  }

  /**
   * Meta veriyi data attribute'dan oku
   */
  function getModelMeta() {
    var panel = document.getElementById(NS_PREFIX + 'model_info_panel');
    if (!panel) return null;
    var raw = panel.getAttribute('data-model-meta');
    if (!raw) return null;
    try {
      return JSON.parse(raw);
    } catch (e) {
      return null;
    }
  }

  /**
   * Model seçimi değişikliğini dinle ve paneli güncelle
   */
  function bindModelSelectionChange() {
    var selectId = NS_PREFIX + 'model_selection';
    var selectEl = document.getElementById(selectId);
    if (!selectEl) return;

    var allMeta = getModelMeta();
    if (!allMeta) return;

    // Dropdown'a ikonları ekle
    addDropdownIcons(selectEl, allMeta);

    // Mevcut seçimi göster (animasyonsuz)
    var currentModel = selectEl.value;
    if (currentModel && allMeta[currentModel]) {
      _lastSelectedModel = currentModel;
      updateModelInfoPanel(currentModel, allMeta[currentModel], false);
    }

    // Değişiklik dinleyicisi - yalnızca model gerçekten değiştiğinde animasyon yap
    $(selectEl).on('change', function() {
      var selectedModel = this.value;
      if (!selectedModel || !allMeta[selectedModel]) return;

      // Aynı model tekrar seçildiyse animasyon yapma
      if (selectedModel === _lastSelectedModel) return;

      _lastSelectedModel = selectedModel;
      updateModelInfoPanel(selectedModel, allMeta[selectedModel], true);
    });
  }

  /**
   * Shiny'den gelen updateSelectInput güncellemelerini dinle
   * (Ana Söyleşi sayfasından model değiştirildiğinde)
   */
  function observeShinyUpdates() {
    $(document).on('shiny:updateinput', function(event) {
      if (event.name && event.name.indexOf('model_selection') !== -1) {
        setTimeout(function() {
          var selectEl = document.getElementById(NS_PREFIX + 'model_selection');
          if (!selectEl) return;
          var allMeta = getModelMeta();
          if (!allMeta) return;

          // İkonları yeniden ekle (updateSelectInput seçenekleri sıfırlar)
          addDropdownIcons(selectEl, allMeta);

          var selectedModel = selectEl.value;
          if (!selectedModel || !allMeta[selectedModel]) return;

          // Aynı modelse animasyon yapma
          var shouldAnimate = (selectedModel !== _lastSelectedModel);
          _lastSelectedModel = selectedModel;
          updateModelInfoPanel(selectedModel, allMeta[selectedModel], shouldAnimate);
        }, 100);
      }
    });
  }

  /**
   * Başlatma
   */
  function initModelInfo() {
    var panel = document.getElementById(NS_PREFIX + 'model_info_panel');
    if (!panel || panel.dataset.initialized) return;
    panel.dataset.initialized = 'true';

    bindModelSelectionChange();
    observeShinyUpdates();
  }

  // DOM hazır olduğunda başlat
  document.addEventListener('DOMContentLoaded', function() {
    $(document).on('shiny:connected', function() {
      setTimeout(initModelInfo, 600);
    });
  });

  // Sekme değişikliğinde yeniden başlat (Yapılandırma sekmesine geçiş)
  $(document).on('click', '[data-value="settings_yapilandirma"]', function() {
    setTimeout(function() {
      var panel = document.getElementById(NS_PREFIX + 'model_info_panel');
      if (panel && !panel.dataset.initialized) {
        initModelInfo();
      }
    }, 400);
  });
})();
