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
  function closeFromCharStep() {
    // Video oynatmayı durdur
    if (window.ExploreCharVideo) {
      window.ExploreCharVideo.stopEverything();
    }

    // Önce 1. adıma dön (durumu sıfırla)
    _currentStep = 1;
    var charStep = document.getElementById('cinematic-character-step');
    if (charStep) charStep.classList.remove('active');

    var cardsGrid = document.querySelector('.cinematic-cards-grid');
    var modalHeader = document.querySelector('.cinematic-modal-header');
    if (cardsGrid) cardsGrid.classList.remove('hidden-step');
    if (modalHeader) modalHeader.classList.remove('hidden-step');

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
    var img = document.getElementById('cinematic-char-preview-img');
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
        var metricEl = document.createElement('div');
        metricEl.className = 'cinematic-char-metric';
        metricEl.innerHTML =
          '<span class="cinematic-char-metric-label">' + metric.label + '</span>' +
          '<div class="cinematic-char-metric-bar">' +
            '<div class="cinematic-char-metric-fill"></div>' +
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
    function onVideoComplete() {
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

      // Modalı kapat
      if (window.CinematicExplore) {
        window.CinematicExplore.closeModal();
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
    closeFromCharStep: closeFromCharStep
  };

})();