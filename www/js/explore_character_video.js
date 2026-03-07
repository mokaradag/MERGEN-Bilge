// www/js/explore_character_video.js
// Dosya Yolu: www/js/explore_character_video.js
// Açıklama: Giriş ekranı Bütünleşik mod karakter seçim adımında video oynatma yönetimi.
// Kişiselleştirme sayfasındaki CinematicVideoManager yaklaşımını tekrarlar,
// ancak bağımsız bir örnek (instance) olarak çalışır.

(function() {
  'use strict';

  // Bağımsız video yönetici örneği (explore modalı için)
  var ExploreCharVideo = {
    _data: null,           // Mevcut karakter video verileri
    _currentChar: null,    // Mevcut karakter ID
    _videoEl: null,        // Video DOM elemanı
    _imageEl: null,        // Statik resim DOM elemanı
    _timer: null,          // Döngü zamanlayıcısı
    _isPlaying: false,     // Video oynatılıyor mu
    _seqId: 0,             // Yarış durumu koruma sayacı
    _initialized: false,   // Başlatılma durumu
    _unmuted: false,       // Ses açıldı mı

    // Sabit yapılandırma
    IMAGE_DISPLAY_DURATION: 4000,

    // ============================================================
    // BAŞLATMA
    // ============================================================
    init: function() {
      this._videoEl = document.getElementById('explore-char-video');
      this._imageEl = document.getElementById('cinematic-char-preview-img');

      if (!this._videoEl || !this._imageEl) return;

      this._initialized = true;

      // Video bitiş olayı
      var self = this;
      this._videoEl.addEventListener('ended', function() {
        self._handleVideoEnd();
      });

      // Kullanıcı etkileşiminde sesi aç
      var unmuteHandler = function() {
        if (self._videoEl && self._unmuted === false) {
          self._videoEl.muted = false;
          self._unmuted = true;
        }
        document.removeEventListener('click', unmuteHandler);
        document.removeEventListener('keydown', unmuteHandler);
      };
      document.addEventListener('click', unmuteHandler);
      document.addEventListener('keydown', unmuteHandler);
    },

    // ============================================================
    // KARAKTERİ YÜKLE VE VİDEO BAŞLAT
    // ============================================================
    loadCharacter: function(charId, videoData) {
      if (!this._initialized) this.init();
      if (!this._initialized) return;

      this._seqId++;
      this.stopEverything();

      this._currentChar = charId;
      this._data = videoData;

      // Statik resmi göster
      if (this._imageEl && videoData && videoData.image) {
        this._imageEl.src = videoData.image;
        this._imageEl.style.display = 'block';
      }

      // Video elemanını gizle
      if (this._videoEl) {
        this._videoEl.style.display = 'none';
        this._videoEl.removeAttribute('src');
      }

      // Intro videosu var mı kontrol et
      if (videoData && videoData.videos && videoData.videos.intro && videoData.videos.intro.length > 0) {
        var self = this;
        setTimeout(function() {
          self._playSequence('intro');
        }, 300);
      }
    },

    // ============================================================
    // VİDEO SEKANSİ OYNAT
    // ============================================================
    _playSequence: function(type) {
      if (!this._data || !this._data.videos) return;

      var videos = this._data.videos[type];
      if (!videos || videos.length === 0) return;

      // Rastgele video seç
      var src = videos[Math.floor(Math.random() * videos.length)];
      this._showVideo(src);
    },

    _showVideo: function(src) {
      if (!this._videoEl) return;

      var seqId = this._seqId;
      var self = this;

      // Resmi gizle, videoyu göster
      if (this._imageEl) this._imageEl.style.display = 'none';
      this._videoEl.style.display = 'block';
      this._videoEl.src = src;
      this._videoEl.muted = !this._unmuted;
      this._isPlaying = true;

      // Müzik ducking
      if (window.SpaceIntroMusic && window.SpaceIntroMusic.duck) {
        window.SpaceIntroMusic.duck();
      }
      if (window.MusicManager && window.MusicManager.duck) {
        window.MusicManager.duck();
      }

      var playPromise = this._videoEl.play();
      if (playPromise && playPromise.catch) {
        playPromise.catch(function(err) {
          if (err.name === 'AbortError') return; // Beklenen durum
          if (err.name === 'NotAllowedError') {
            // Sessiz modda tekrar dene
            if (self._videoEl) {
              self._videoEl.muted = true;
              self._videoEl.play().catch(function() {});
            }
          }
        });
      }
    },

    // ============================================================
    // VİDEO BİTTİĞİNDE
    // ============================================================
    _handleVideoEnd: function() {
      this._isPlaying = false;

      // Müzik unduck
      if (window.SpaceIntroMusic && window.SpaceIntroMusic.unduck) {
        window.SpaceIntroMusic.unduck();
      }
      if (window.MusicManager && window.MusicManager.unduck) {
        window.MusicManager.unduck();
      }

      // Resmi göster
      if (this._imageEl) this._imageEl.style.display = 'block';
      if (this._videoEl) this._videoEl.style.display = 'none';

      // Bekleme süresi sonrası loop videosu oynat
      var self = this;
      var seqId = this._seqId;
      this._timer = setTimeout(function() {
        if (self._seqId !== seqId) return; // Yarış durumu kontrolü
        self._playSequence('loop');
      }, this.IMAGE_DISPLAY_DURATION);
    },

    // ============================================================
    // SEÇİM VİDEOSU OYNAT
    // ============================================================
    playSelectSequence: function() {
      if (!this._data || !this._data.videos) return;
      var selectVideos = this._data.videos.select;
      if (!selectVideos || selectVideos.length === 0) return;

      this._seqId++;
      this.stopEverything();

      var src = selectVideos[Math.floor(Math.random() * selectVideos.length)];
      this._showVideo(src);
    },

    // ============================================================
    // HER ŞEYİ DURDUR
    // ============================================================
    stopEverything: function() {
      if (this._timer) {
        clearTimeout(this._timer);
        this._timer = null;
      }
      if (this._videoEl) {
        this._videoEl.pause();
        this._videoEl.style.display = 'none';
      }
      if (this._imageEl) {
        this._imageEl.style.display = 'block';
      }
      this._isPlaying = false;

      // Müzik unduck
      if (window.SpaceIntroMusic && window.SpaceIntroMusic.unduck) {
        window.SpaceIntroMusic.unduck();
      }
      if (window.MusicManager && window.MusicManager.unduck) {
        window.MusicManager.unduck();
      }
    }
  };

  // Global erişim
  window.ExploreCharVideo = ExploreCharVideo;

})();