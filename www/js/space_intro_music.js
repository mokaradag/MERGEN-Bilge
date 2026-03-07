// www/js/space_intro_music.js
// Dosya Yolu: www/js/space_intro_music.js
// Aciklama: Uzay giris ekrani arka plan muzik yoneticisi.
// Uygulama yuklendiginde otomatik baslar, mod secildikten sonra durur.
// Karakter videolari sirasinda ses kisilir (duck/unduck).
// Parcalar www/music/intro/ klasorunden rastgele secilir.

(function() {
  'use strict';

  var SpaceIntroMusic = {
    _audio: null,
    _playlist: [],         // Sunucudan gelen parca listesi
    _active: false,        // Muzik aktif mi
    _stopped: false,       // Kalici durdurma (mod secildikten sonra)
    _isDucked: false,
    _fadeInterval: null,
    _volume: 0.25,         // Varsayilan ses seviyesi
    _duckedRatio: 0.12,    // Kisilan ses orani
    _fadeTime: 1500,       // Solma suresi (ms)
    _intentionalStop: false,

    // Sunucudan playlist al ve calmaya basla
    init: function(data) {
      if (this._stopped) return;

      var files = data && data.files ? data.files : [];
      if (data && typeof data.volume === 'number') {
        this._volume = data.volume;
      }

      this._playlist = files;
      console.log('[SPACE-MUSIC] Playlist alindi:', files.length, 'parca');

      if (files.length > 0 && !this._active) {
        this._active = true;
        this._playRandom();
      }
    },

    // Rastgele parca sec ve cal
    _playRandom: function() {
      if (!this._active || this._stopped || this._playlist.length === 0) return;

      var idx = Math.floor(Math.random() * this._playlist.length);
      var src = this._playlist[idx];
      this._playTrack(src);
    },

    // Tek parca cal
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
          console.warn('[SPACE-MUSIC] Oynatma hatasi:', e.message || e);
        });

        console.log('[SPACE-MUSIC] Calinyor:', decodeURIComponent(src.split('/').pop()));
      }, { once: true });

      audio.addEventListener('ended', function() {
        if (self._audio !== audio || self._stopped) return;
        // Sonraki rastgele parcaya gec
        self._playRandom();
      }, { once: true });

      audio.addEventListener('error', function() {
        if (self._intentionalStop || self._audio !== audio) return;
        console.warn('[SPACE-MUSIC] Yukleme hatasi, sonraki parcaya geciliyor');
        self._playRandom();
      }, { once: true });

      audio.load();
    },

    // Sesi durdur (dahili)
    _stopAudio: function() {
      this._intentionalStop = true;
      if (this._fadeInterval) {
        clearInterval(this._fadeInterval);
        this._fadeInterval = null;
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

    // Ses seviyesi gecisi
    _fadeTo: function(audio, target, duration) {
      if (this._fadeInterval) {
        clearInterval(this._fadeInterval);
        this._fadeInterval = null;
      }
      if (!audio) return;

      var start = audio.volume;
      var diff = target - start;
      if (Math.abs(diff) < 0.005) {
        try { audio.volume = Math.max(0, Math.min(1, target)); } catch(e) {}
        return;
      }

      var steps = 25;
      var stepTime = (duration || 500) / steps;
      var stepSize = diff / steps;
      var current = 0;
      var self = this;

      this._fadeInterval = setInterval(function() {
        current++;
        if (current >= steps) {
          try { audio.volume = Math.max(0, Math.min(1, target)); } catch(e) {}
          clearInterval(self._fadeInterval);
          self._fadeInterval = null;
          return;
        }
        try {
          audio.volume = Math.max(0, Math.min(1, start + (stepSize * current)));
        } catch(e) {
          clearInterval(self._fadeInterval);
          self._fadeInterval = null;
        }
      }, stepTime);
    },

    // --- ACIK API ---

    // Muzigi tamamen durdur (mod secildikten sonra, geri donusu yok)
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
      console.log('[SPACE-MUSIC] Kalici durdurma (mod secildi)');
    },

    // Karakter videosu sirasinda sesi kis
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

  // Global erisim
  window.SpaceIntroMusic = SpaceIntroMusic;

  // Shiny mesaj dinleyicisi
  $(document).ready(function() {
    if (typeof Shiny !== 'undefined') {
      // Sunucudan intro muzik playlist'ini al
      Shiny.addCustomMessageHandler('initSpaceIntroMusic', function(data) {
        SpaceIntroMusic.init(data);
      });
    }
  });

})();
