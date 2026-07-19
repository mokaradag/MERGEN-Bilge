// www/js/space_intro_music.js
// Dosya Yolu: www/js/space_intro_music.js
// Açıklama: Uzay giriş ekranı arka plan müzik yöneticisi.
// Uygulama yüklendiğinde otomatik başlar, mod seçildikten sonra durur.
// Karakter videoları sırasında ses kısılır (duck/unduck).
// Parçalar www/music/intro/ klasöründen rastgele seçilir.

(function() {
  'use strict';

// Medya tanılama logu: üretimde sessiz; localStorage.MERGEN_DEBUG_MEDIA = "1"
// ile açılır. Beklenen medya oynatma uyarıları/hataları da aynı kapıya bağlıdır.
var mergenMediaDbg = window.__mergenMediaDbg = window.__mergenMediaDbg || function() {
  try {
    if (window.localStorage && localStorage.getItem('MERGEN_DEBUG_MEDIA') === '1' && window.console) {
      console.log.apply(console, arguments);
    }
  } catch (e) {}
};
var mergenMediaWarn = window.__mergenMediaWarn = window.__mergenMediaWarn || function() {
  try {
    if (window.localStorage && localStorage.getItem('MERGEN_DEBUG_MEDIA') === '1' && window.console) {
      console.warn.apply(console, arguments);
    }
  } catch (e) {}
};
var mergenMediaError = window.__mergenMediaError = window.__mergenMediaError || function() {
  try {
    if (window.localStorage && localStorage.getItem('MERGEN_DEBUG_MEDIA') === '1' && window.console) {
      console.error.apply(console, arguments);
    }
  } catch (e) {}
};

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
    _failedTrackUrls: {},
    _consecutiveTrackErrors: 0,
    _maxConsecutiveTrackErrors: 5,
    _errorRetryDelay: 500,

    // Sunucudan playlist al ve çalmaya başla
    init: function(data) {
      if (this._stopped) return;

      var files = data && data.files ? data.files : [];
      if (data && typeof data.volume === 'number') {
        this._volume = data.volume;
      }

      this._playlist = files;
      this._failedTrackUrls = {};
      this._consecutiveTrackErrors = 0;
      mergenMediaDbg('[SPACE-MUSIC] Playlist alındı:', files.length, 'parça');

      if (files.length > 0 && !this._active) {
        this._active = true;
        // Gecikme olmadan hemen başlat
        this._playRandom();
      }
    },

    // Rastgele parça seç ve çal
    _playRandom: function() {
      if (!this._active || this._stopped || this._playlist.length === 0) return;

      var self = this;
      var available = this._playlist.filter(function(src) {
        return !self._failedTrackUrls[src];
      });

      if (available.length === 0) {
        mergenMediaWarn('[SPACE-MUSIC] Intro playlist içindeki tüm parçalar hatalı; döngü durduruldu.');
        this._active = false;
        this._stopAudio();
        return;
      }

      var idx = Math.floor(Math.random() * available.length);
      var src = available[idx];
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
          mergenMediaWarn('[SPACE-MUSIC] Oynatma hatası:', e.message || e);
        });

        mergenMediaDbg('[SPACE-MUSIC] Çalınıyor:', decodeURIComponent(src.split('/').pop()));
      }, { once: true });

      audio.addEventListener('ended', function() {
        if (self._audio !== audio || self._stopped) return;
        // Sonraki rastgele parçaya geç
        self._playRandom();
      }, { once: true });

      audio.addEventListener('error', function() {
        if (self._intentionalStop || self._audio !== audio) return;

        self._failedTrackUrls[src] = true;
        self._consecutiveTrackErrors++;

        mergenMediaWarn(
          '[SPACE-MUSIC] Yükleme hatası, sonraki parçaya geçiliyor',
          '| Ardışık hata:',
          self._consecutiveTrackErrors
        );

        if (self._consecutiveTrackErrors >= self._maxConsecutiveTrackErrors) {
          mergenMediaWarn('[SPACE-MUSIC] Çok fazla intro ses hatası; sonsuz döngü engellendi.');
          self._active = false;
          self._stopAudio();
          return;
        }

        setTimeout(function() {
          if (self._audio !== audio || self._stopped) return;
          self._playRandom();
        }, self._errorRetryDelay);
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
    fadeOutAndStop: function(callback) {
      if (this._stopped) {
        if (typeof callback === 'function') callback();
        return;
      }

      this._stopped = true;
      this._active = false;

      var audio = this._audio;
      this._audio = null;

      var finish = function() {
        if (typeof callback === 'function') callback();
      };

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
          finish();
        }, 2100);
      } else {
        finish();
      }

      mergenMediaDbg('[SPACE-MUSIC] Kalıcı durdurma (mod seçildi)');
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

  // HTML'deki gömülü veri ve Shiny mesaj dinleyicisi
  $(document).ready(function() {
    // Giriş animasyonu kapalı olsa bile (skip_intro) derin uzay intro
    // müziği yükleme ekranı boyunca çalmaya devam eder. Yalnızca görsel
    // derin uzay sahnesi atlanır; müzik atlanmaz. Karşılama ekranına
    // geçişte www/js/app_loading.js, SpaceIntroMusic.fadeOutAndStop()
    // çağırarak müziği uygulama arka plan müziğine yumuşakça devreder.
    // Bu yüzden burada artık skip_intro için _stopped ayarlanmaz.

    // Önce HTML'de gömülü müzik verisini kontrol et (sunucu mesajını beklemeden hemen başlat)
    var embeddedData = document.getElementById('intro-music-data');
    if (embeddedData) {
      try {
        var data = JSON.parse(embeddedData.textContent);
        if (data && data.files && data.files.length > 0) {
          mergenMediaDbg('[SPACE-MUSIC] Gömülü veri bulundu, hemen başlatılıyor');
          SpaceIntroMusic.init(data);
        }
      } catch(e) {
        mergenMediaWarn('[SPACE-MUSIC] Gömülü veri ayrıştırma hatası:', e);
      }
    }

    if (typeof Shiny !== 'undefined') {
      // Sunucudan intro müzik playlist'ini al (yedek veya güncelleme olarak)
      Shiny.addCustomMessageHandler('initSpaceIntroMusic', function(data) {
        SpaceIntroMusic.init(data);
      });
    }
  });

})();