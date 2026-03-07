// www/js/explore_character_video.js
// Dosya Yolu: www/js/explore_character_video.js
// Açıklama: Giriş ekranı Bütünleşik mod karakter seçim adımında video oynatma yönetimi.
// Kişiselleştirme sayfasındaki CinematicVideoManager yaklaşımını tekrarlar,
// ancak bağımsız bir örnek (instance) olarak çalışır.
// Kullanıcı bu noktaya gelene kadar zaten tıklama yapmış olduğundan ses açıktır.

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
    _selectVideoEndCallback: null, // Seçim videosu bitiş geri çağırması

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

      // Video verisi yüklendiğinde resmi gizle (siyah ekranı önle)
      this._videoEl.addEventListener('playing', function() {
        // Video gerçekten başladığında resmi gizle
        if (self._imageEl && self._isPlaying) {
          self._imageEl.style.opacity = '0';
          setTimeout(function() {
            if (self._isPlaying && self._imageEl) {
              self._imageEl.style.display = 'none';
              self._imageEl.style.opacity = '1';
            }
          }, 300);
        }
      });
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
        this._imageEl.style.opacity = '1';
      }

      // Video elemanını hazırla ama henüz gösterme
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

      var self = this;

      // Resmi henüz gizleme - video 'playing' olayında gizlenecek
      // Bu sayede siyah ekran görünmez
      this._videoEl.style.display = 'block';
      this._videoEl.src = src;
      // Kullanıcı bu noktaya gelene kadar zaten tıklama yapmış (Keşfet + Bütünleşik)
      // Bu nedenle ses doğrudan açık olmalı
      this._videoEl.muted = false;
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
            // Tarayıcı engellediyse sessiz modda tekrar dene
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

      // Seçim videosu geri çağırması varsa çalıştır
      if (this._selectVideoEndCallback) {
        var cb = this._selectVideoEndCallback;
        this._selectVideoEndCallback = null;
        cb();
        return; // Seçim videosu bittikten sonra döngüye geçme
      }

      // Müzik unduck
      if (window.SpaceIntroMusic && window.SpaceIntroMusic.unduck) {
        window.SpaceIntroMusic.unduck();
      }
      if (window.MusicManager && window.MusicManager.unduck) {
        window.MusicManager.unduck();
      }

      // Resmi göster
      if (this._imageEl) {
        this._imageEl.style.display = 'block';
        this._imageEl.style.opacity = '1';
      }
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
    // SEÇİM VİDEOSU OYNAT (bitişte geri çağırma desteği)
    // ============================================================
    playSelectSequence: function(onComplete) {
      if (!this._data || !this._data.videos) {
        if (onComplete) onComplete();
        return;
      }
      var selectVideos = this._data.videos.select;
      if (!selectVideos || selectVideos.length === 0) {
        if (onComplete) onComplete();
        return;
      }

      this._seqId++;
      this.stopEverything();

      // Bitiş geri çağırmasını kaydet
      this._selectVideoEndCallback = onComplete || null;

      var src = selectVideos[Math.floor(Math.random() * selectVideos.length)];
      this._showVideo(src);
    },

    // ============================================================
    // HER ŞEYİ DURDUR
    // ============================================================
    stopEverything: function() {
      this._selectVideoEndCallback = null;
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
        this._imageEl.style.opacity = '1';
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