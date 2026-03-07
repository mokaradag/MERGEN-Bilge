// www/js/space_intro_music.js
// Dosya Yolu: www/js/space_intro_music.js
// Açıklama: Uzay giriş ekranı arka plan müzik yöneticisi.
// Uygulama yüklendiğinde otomatik başlar, mod seçildikten sonra durur.
// Karakter videoları sırasında ses kısılır (duck/unduck).
// Parçalar www/music/intro/ klasöründen rastgele seçilir.

(function() {
  'use strict';

  var SpaceIntroMusic = {
    _audio: null,
    _playlist: [],         // Sunucudan gelen parça listesi
    _active: false,        // Müzik aktif mi
    _stopped: false,       // Kalıcı durdurma (mod seçildikten sonra)
    _isDucked: false,
    _fadeRafId: null,       // requestAnimationFrame kimliği
    _volume: 0.25,         // Varsayılan ses seviyesi
    _duckedRatio: 0.12,    // Kısılan ses oranı
    _fadeTime: 1500,       // Solma süresi (ms)
    _intentionalStop: false,

    // Sunucudan playlist al ve çalmaya başla
    init: function(data) {
      if (this._stopped) return;

      var files = data && data.files ? data.files : [];
      if (data && typeof data.volume === 'number') {
        this._volume = data.volume;
      }

      this._playlist = files;
      console.log('[SPACE-MUSIC] Playlist alındı:', files.length, 'parça');

      if (files.length > 0 && !this._active) {
        this._active = true;
        // Gecikme olmadan hemen başlat
        this._playRandom();
      }
    },

    // Rastgele parça seç ve çal
    _playRandom: function() {
      if (!this._active || this._stopped || this._playlist.length === 0) return;

      var idx = Math.floor(Math.random() * this._playlist.length);
      var src = this._playlist[idx];
      this._playTrack(src);
    },

    // Tek parça çal
    _playTrack: function(src) {
      this._stopAudio();
      if (this._stopped) return;

      var self = this;
      var audio = new Audio(src);
      audio.volume = 0;
      audio.preload = 'auto';
      this._audio = audio;

      audio.addEventListener('canplaythrough', function() {
        if (self._audio !== audio || self._stopped) {
          try { audio.pause(); audio.src = ''; } catch(e) {}
          return;
        }

        var targetVol = self._isDucked
          ? Math.max(0.01, self._volume * self._duckedRatio)
          : self._volume;
        self._fadeTo(audio, targetVol, self._fadeTime);
        audio.play().catch(function(e) {
          if (self._intentionalStop || e.name === 'AbortError') return;
          console.warn('[SPACE-MUSIC] Oynatma hatası:', e.message || e);
        });

        console.log('[SPACE-MUSIC] Çalınıyor:', decodeURIComponent(src.split('/').pop()));
      }, { once: true });

      audio.addEventListener('ended', function() {
        if (self._audio !== audio || self._stopped) return;
        // Sonraki rastgele parçaya geç
        self._playRandom();
      }, { once: true });

      audio.addEventListener('error', function() {
        if (self._intentionalStop || self._audio !== audio) return;
        console.warn('[SPACE-MUSIC] Yükleme hatası, sonraki parçaya geçiliyor');
        self._playRandom();
      }, { once: true });

      audio.load();
    },

    // Sesi durdur (dâhilî)
    _stopAudio: function() {
      this._intentionalStop = true;
      if (this._fadeRafId) {
        cancelAnimationFrame(this._fadeRafId);
        this._fadeRafId = null;
      }
      if (this._audio) {
        try {
          this._audio.pause();
          this._audio.removeAttribute('src');
          this._audio.load();
        } catch(e) {}
        this._audio = null;
      }
      var self = this;
      setTimeout(function() { self._intentionalStop = false; }, 100);
    },

    // Ses seviyesi geçişi - requestAnimationFrame ile pürüzsüz
    _fadeTo: function(audio, target, duration) {
      if (this._fadeRafId) {
        cancelAnimationFrame(this._fadeRafId);
        this._fadeRafId = null;
      }
      if (!audio) return;

      var start = audio.volume;
      var diff = target - start;
      if (Math.abs(diff) < 0.005) {
        try { audio.volume = Math.max(0, Math.min(1, target)); } catch(e) {}
        return;
      }

      var startTime = performance.now();
      var fadeDuration = duration || 500;
      var self = this;

      function step(now) {
        var elapsed = now - startTime;
        var progress = Math.min(elapsed / fadeDuration, 1);
        // Yumuşak eğri (easeInOutQuad)
        var eased = progress < 0.5
          ? 2 * progress * progress
          : 1 - Math.pow(-2 * progress + 2, 2) / 2;

        try {
          audio.volume = Math.max(0, Math.min(1, start + diff * eased));
        } catch(e) {
          self._fadeRafId = null;
          return;
        }

        if (progress < 1) {
          self._fadeRafId = requestAnimationFrame(step);
        } else {
          self._fadeRafId = null;
        }
      }

      this._fadeRafId = requestAnimationFrame(step);
    },

    // --- AÇIK API ---

    // Müziği tamamen durdur (mod seçildikten sonra, geri dönüşü yok)
    fadeOutAndStop: function() {
      if (this._stopped) return;
      this._stopped = true;
      this._active = false;

      var audio = this._audio;
      this._audio = null;

      if (audio) {
        var self = this;
        this._fadeTo(audio, 0, 2000);
        setTimeout(function() {
          self._intentionalStop = true;
          try {
            audio.pause();
            audio.removeAttribute('src');
            audio.load();
          } catch(e) {}
          setTimeout(function() { self._intentionalStop = false; }, 100);
        }, 2100);
      }
      console.log('[SPACE-MUSIC] Kalıcı durdurma (mod seçildi)');
    },

    // Karakter videosu sırasında sesi kıs
    duck: function() {
      if (this._isDucked || this._stopped) return;
      this._isDucked = true;
      if (this._audio) {
        var ducked = Math.max(0.01, this._volume * this._duckedRatio);
        this._fadeTo(this._audio, ducked, 600);
      }
    },

    // Karakter videosu bitince sesi geri getir
    unduck: function() {
      if (!this._isDucked || this._stopped) return;
      this._isDucked = false;
      if (this._audio) {
        this._fadeTo(this._audio, this._volume, 800);
      }
    },

    // Aktif mi?
    isActive: function() {
      return this._active && !this._stopped;
    }
  };

  // Global erişim
  window.SpaceIntroMusic = SpaceIntroMusic;

  // Shiny mesaj dinleyicisi
  $(document).ready(function() {
    if (typeof Shiny !== 'undefined') {
      // Sunucudan intro müzik playlist'ini al
      Shiny.addCustomMessageHandler('initSpaceIntroMusic', function(data) {
        SpaceIntroMusic.init(data);
      });
    }
  });

})();
