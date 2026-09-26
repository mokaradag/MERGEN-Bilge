// www/js/explore_character_step.js
// Dosya Yolu: www/js/explore_character_step.js
// Açıklama: Bütünleşik mod karakter seçim adımı etkileşim mantığı.
// Mod seçim modalında 2. adım olarak karakter seçimini yönetir.
// Video oynatma, yazma efekti ve Kişiselleştirme sayfasıyla tutarlı deneyim sağlar.

(function() {
  'use strict';

  // Seçili persona kimliği (varsayılan: emre)
  var _selectedCharId = 'emre';

  // Karakter verileri (R tarafından doldurulacak)
  var _charactersData = null;

  // Karakter video verileri (R tarafından doldurulacak)
  var _characterVideoData = {};

  // Tarayıcı önbelleğine alınan video dosyası URL'leri (tekrar prefetch önlenir)
  var _prefetchedVideoUrls = {};

  // Adım durumu
  var _currentStep = 1;

  // Çift tıklama koruma kilidi
  var _confirmInProgress = false;

  // Seçim nesli: iptal edilen (geri/kapat/Esc) seçim dizisinin geç gelen
  // tamamlanma çağrısı seçimi uygulamaz.
  var _selectionGeneration = 0;

  
  // (Kaldırıldı: Eski 8 saniyelik ek bekleme gereksiz gecikmeye neden oluyordu)

  // ============================================================
  // KARAKTER VERİSİNİ YÜKLE
  // ============================================================
  function loadCharactersData(data) {
    _charactersData = data;
  }

  // ============================================================
  // KARAKTER VİDEO VERİSİNİ YÜKLE
  // ============================================================
  function loadCharacterVideoData(data) {
    if (data && data.character) {
      _characterVideoData[data.character] = data;
      prefetchCharacterIntroVideo(data);
    }
  }

  // Giriş videosu dosyasını tarayıcı önbelleğine al. Böylece karakter adımı
  // açıldığında video sunucu round-trip'i ve dosya indirme beklemesi olmadan
  // anında oynar (Bütünleşik mod gecikmesi giderilir).
  function prefetchCharacterIntroVideo(data) {
    try {
      var intro = (data && data.videos) ? data.videos.intro : null;
      var url = (intro && intro.length) ? intro[0] : null;
      if (!url || _prefetchedVideoUrls[url]) return;
      _prefetchedVideoUrls[url] = true;
      var link = document.createElement('link');
      link.rel = 'prefetch';
      link.as = 'video';
      link.href = url;
      document.head.appendChild(link);
    } catch (e) {
      // Ön yükleme başarısızlığı sessiz geçilir (kritik değil)
    }
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

    // Tüm karakter video verilerini ön yükle (geçişlerdeki gecikmeyi azaltır)
    preloadAllCharacterVideos();
  }

  // ============================================================
  // TÜM KARAKTER VİDEOLARINI ÖN YÜKLE
  // ============================================================
  // Karakter adımı açıldığında, henüz önbelleğe alınmamış
  // karakterlerin video verilerini sunucudan ister. Böylece
  // kullanıcı farklı karaktere geçtiğinde gecikme yaşanmaz.
  function preloadAllCharacterVideos() {
    if (!_charactersData || typeof Shiny === 'undefined' || !Shiny.setInputValue) return;

    var delay = 0;
    _charactersData.forEach(function(ch) {
      // Halihazırda seçili karakter selectCharacterInModal tarafından zaten istendi
      if (ch.id === _selectedCharId) return;
      if (!_characterVideoData[ch.id]) {
        setTimeout(function() {
          Shiny.setInputValue('explore_request_char_video', {
            character: ch.id,
            timestamp: Date.now()
          }, { priority: 'event' });
        }, delay);
        delay += 80; // Ardışık isteklerin çakışmasını önlemek için küçük aralık
      }
    });
  }

  // ============================================================
  // 1. ADIMA GERİ DÖN
  // ============================================================
  function showModeStep() {
    _currentStep = 1;
    cancelPendingSelection();

    // Video oynatmayı durdur
    if (window.ExploreCharVideo) {
      window.ExploreCharVideo.stopEverything();
    }

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
  // MODALI KAPAT (2. ADIMDAN)
  // ============================================================
  // Süren seçim dizisini iptal eder: onay kilidi bırakılır, geç tamamlanma yok sayılır.
  function cancelPendingSelection() {
    _selectionGeneration += 1;
    _confirmInProgress = false;
  }

  // 2. adım durumunu modalı kapatmadan temizler (video, DOM, adım göstergesi,
  // onay kilidi). Genel kapatma yolları (Esc, arka plan) da bunu çağırır.
  function resetCharStep() {
    cancelPendingSelection();
    if (window.ExploreCharVideo) {
      window.ExploreCharVideo.stopEverything();
    }

    _currentStep = 1;
    var charStep = document.getElementById('cinematic-character-step');
    if (charStep) charStep.classList.remove('active');

    var cardsGrid = document.querySelector('.cinematic-cards-grid');
    var modalHeader = document.querySelector('.cinematic-modal-header');
    if (cardsGrid) cardsGrid.classList.remove('hidden-step');
    if (modalHeader) modalHeader.classList.remove('hidden-step');
    updateStepIndicator(1);
  }

  function closeFromCharStep() {
    resetCharStep();

    // Modalı kapat
    if (window.CinematicExplore) {
      window.CinematicExplore.closeModal();
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

    // Görseli güncelle (geçiş animasyonuyla)
    // Hareket azaltma tercihinde portre gizlenip gecikmeyle gösterilmez.
    var azHareket = !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
    var img = document.getElementById('cinematic-char-preview-img');
    if (img) {
      if (animate !== false && !azHareket) {
        img.style.opacity = '0';
        setTimeout(function() {
          img.src = charData.image;
          img.style.opacity = '1';
        }, 250);
      } else {
        img.src = charData.image;
      }
    }

    // Video verisi yükle ve video başlat
    if (window.ExploreCharVideo) {
      var videoData = _characterVideoData[charId];
      if (videoData) {
        window.ExploreCharVideo.loadCharacter(charId, videoData);
      } else {
        // Video verisi henüz gelmemişse, Shiny'den iste
        if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
          Shiny.setInputValue('explore_request_char_video', {
            character: charId,
            timestamp: Date.now()
          }, { priority: 'event' });
        }
      }
    }

    // Persona aksanı tek CSS değişkeniyle verilir (isim çizgisi, metrikler,
    // seçili düğme); metinler daktilo efekti olmadan doğrudan yazılır.
    // Aksanı olmayan personada önceki persona rengi kalmaz; varsayılan geçerli olur.
    var charStepEl = document.getElementById('cinematic-character-step');
    if (charStepEl && charData.accent) {
      charStepEl.style.setProperty('--char-accent', charData.accent);
    } else if (charStepEl) {
      charStepEl.style.removeProperty('--char-accent');
    }
    var displayName = document.querySelector('.cinematic-char-info .cinematic-char-display-name');
    var subtitleEl = document.querySelector('.cinematic-char-info .cinematic-char-subtitle-text');
    if (displayName) {
      displayName.textContent = charData.display_name;
    }
    if (subtitleEl) {
      subtitleEl.textContent = charData.style_tr || charData.subtitle || '';
    }

    var loreEl = document.querySelector('.cinematic-char-lore');
    if (loreEl) {
      loreEl.textContent = charData.lore_tr || '';
    }

    // Metrikleri güncelle (animasyonlu)
    var metricsContainer = document.querySelector('.cinematic-char-metrics');
    if (metricsContainer && charData.profile_metrics) {
      metricsContainer.innerHTML = '';
      charData.profile_metrics.forEach(function(metric, idx) {
        // Öğeler textContent ile kurulur; metrik metni HTML olarak yorumlanmaz.
        var metricEl = document.createElement('div');
        metricEl.className = 'cinematic-char-metric';
        var labelEl = document.createElement('span');
        labelEl.className = 'cinematic-char-metric-label';
        labelEl.textContent = metric.label;
        var barEl = document.createElement('div');
        barEl.className = 'cinematic-char-metric-bar';
        var fill = document.createElement('div');
        fill.className = 'cinematic-char-metric-fill';
        barEl.appendChild(fill);
        var valueEl = document.createElement('span');
        valueEl.className = 'cinematic-char-metric-value';
        valueEl.textContent = metric.value;
        metricEl.appendChild(labelEl);
        metricEl.appendChild(barEl);
        metricEl.appendChild(valueEl);
        metricsContainer.appendChild(metricEl);

        // Çubuk animasyonu (yalnız sayısal yüzde uygulanır)
        var yuzde = Math.max(0, Math.min(100, Number(metric.value) || 0));
        setTimeout(function() {
          fill.style.width = yuzde + '%';
        }, 100 + idx * 80);
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
  }

  // ============================================================
  // KARAKTER ONAYLANDIĞINDA
  // ============================================================
  function confirmCharacterSelection() {
    if (!_selectedCharId || _confirmInProgress) return;
    _confirmInProgress = true;

    // Seçili karakter ID'sini yakala (kapanış sırasında erişim için)
    var selectedChar = _selectedCharId;

    // localStorage'a hemen kaydet
    try {
      var raw = localStorage.getItem('mergen_settings');
      var settings = raw ? JSON.parse(raw) : {};
      settings.experience_mode = 'kesif';
      settings.selected_character = selectedChar;
      localStorage.setItem('mergen_settings', JSON.stringify(settings));
    } catch(e) {}

    // Karşılama konuşmasını seçim videosu oynarken ön hazırla
    if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
      Shiny.setInputValue('explore_preheat_initial_greeting', {
        mode: 'kesif',
        character: selectedChar,
        source: 'welcome_character_step',
        timestamp: Date.now()
      }, { priority: 'event' });
    }

    // Seçim videosu bittiğinde geçiş yapacak fonksiyon
    // Not: Shiny bildirimi, giriş ekranı kapandıktan sonra gönderilir.
    // Bu sayede müzik ancak geçiş tamamlandığında başlar (yarış durumu önlenir).
    var nesil = _selectionGeneration;
    function onVideoComplete() {
      // Kullanıcı bu arada geri döndü ya da modalı kapattıysa seçim uygulanmaz.
      if (nesil !== _selectionGeneration) return;
      // Adımı hemen sıfırla: geç gelen ön yükleme yanıtlarının
      // loadCharacter çağırmasını engeller (_currentStep === 2 koruması)
      _currentStep = 1;

      // Video oynatmayı durdur
      if (window.ExploreCharVideo) {
        window.ExploreCharVideo.stopEverything();
      }

      // Karakter adımı DOM durumunu temizle (2. adım → 1. adım sıfırlaması)
      var charStep = document.getElementById('cinematic-character-step');
      if (charStep) charStep.classList.remove('active');
      var cardsGrid = document.querySelector('.cinematic-cards-grid');
      var modalHeader = document.querySelector('.cinematic-modal-header');
      if (cardsGrid) cardsGrid.classList.remove('hidden-step');
      if (modalHeader) modalHeader.classList.remove('hidden-step');

      updateStepIndicator(1);

      // Modalı kapat (başarılı seçim: odak ana uygulamaya taşınır)
      if (window.CinematicExplore) {
        window.CinematicExplore.closeModal(true);
      }

		// Giriş ekranını kapat; Shiny mod seçimini audio callback'ine bağımlı bırakma.
		// Callback yalnızca yedek olarak aynı tek-seferlik bildirimi yeniden dener.
		setTimeout(function() {
		  var selectionSent = false;

		  var sendSelectionToShiny = function() {
			if (selectionSent) return;
			selectionSent = true;

			if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
			  Shiny.setInputValue('selected_experience_mode', {
				mode: 'kesif',
				character: selectedChar,
				source: 'welcome_character_step',
				timestamp: Date.now()
			  }, { priority: 'event' });
			}

			// Kilidi serbest bırak
			_confirmInProgress = false;
		  };

		  // Kritik: Ayarları hemen Shiny'ye gönder.
		  // Aksi halde intro audio callback yarışı, Kişiselleştirme sayfasını Odak'ta bırakabilir.
		  sendSelectionToShiny();

		  if (window.CinematicExplore) {
			window.CinematicExplore.dismissDeepSpace(sendSelectionToShiny);
		  } else {
			sendSelectionToShiny();
		  }
		}, 200);
    }

    // Seçim videosunu oynat ve bittiğinde geçiş yap
    if (window.ExploreCharVideo) {
      window.ExploreCharVideo.playSelectSequence(onVideoComplete);
    } else {
      // Video yöneticisi yoksa kısa gecikme ile doğrudan geçiş yap
      setTimeout(onVideoComplete, 300);
    }
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

    // Kapatma butonu (2. adımdaki X ikonu)
    $(document).on('click', '.cinematic-char-close-btn', function() {
      closeFromCharStep();
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

      // Video verilerini yükle (her karakter için ayrı ayrı gelebilir)
      Shiny.addCustomMessageHandler('loadExploreCharVideo', function(data) {
        loadCharacterVideoData(data);
        // Seçim videosu oynarken karakter yeniden yükleme yapma
        // (geç gelen ön yükleme yanıtı, seçim videosu geri çağırmasını silmesin)
        if (window.ExploreCharVideo && window.ExploreCharVideo.isSelectActive && window.ExploreCharVideo.isSelectActive()) {
          return;
        }
        // Eğer şu an bu karakter seçiliyse videoyu başlat
        if (data && data.character === _selectedCharId && _currentStep === 2 && window.ExploreCharVideo) {
          window.ExploreCharVideo.loadCharacter(data.character, data);
        }
      });
    }
  });

  // Global erişim
  window.CinematicCharacterStep = {
    showCharacterStep: showCharacterStep,
    showModeStep: showModeStep,
    loadCharactersData: loadCharactersData,
    loadCharacterVideoData: loadCharacterVideoData,
    confirmSelection: confirmCharacterSelection,
    closeFromCharStep: closeFromCharStep,
    reset: resetCharStep,
    isActive: function() { return _currentStep === 2; }
  };

})();