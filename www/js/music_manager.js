// www/js/music_manager.js
// Arka plan müzik yönetim sistemi - Tek ses kaynağı mimarisi
// Akış: Ana Tema (bir kez) → Karakter Müziği (rastgele döngü)

const MusicManager = {
  // Tek global durum
  state: {
    enabled: false,          // Müzik açık mı
    character: 'mergen',     // Aktif karakter
    phase: 'idle',           // 'idle' | 'theme' | 'character'
    normalVolume: 0.3,
    isDucked: false
  },

  // Tek ses elemanı - yarış durumunu önler
  _audio: null,
  _fadeInterval: null,
  // Sunucudan gelen çalma listeleri
  _themePlaylist: [],
  _characterPlaylist: [],
  // Bekleyen istek sayacı (gecikmeli yanıtları yönetir)
  _pendingRequestId: 0,

  config: {
    fadeTime: 1500
  },

  // ─── BAŞLATMA ───
  init: function(settings) {
    this.state.enabled = settings.enabled || false;
    this.state.normalVolume = settings.volume || 0.3;
    this.state.character = settings.character || 'mergen';

    console.log('[MUSIC] Başlatıldı:', this.state.enabled ? 'AÇIK' : 'KAPALI',
                '| Karakter:', this.state.character);

    if (this.state.enabled) {
      this._startFromBeginning();
    }
  },

  // ─── ANA KONTROL: BAŞLAT (Tema → Karakter akışı) ───
  _startFromBeginning: function() {
    // Önce her şeyi temizle
    this._stopAudio();
    this.state.phase = 'idle';
    this._themePlaylist = [];
    this._characterPlaylist = [];

    // Sunucudan tema playlist'ini iste
    this._requestPlaylist('tema');
  },

  // ─── SUNUCUDAN PLAYLIST İSTE ───
  _requestPlaylist: function(type) {
    this._pendingRequestId++;
    var requestId = this._pendingRequestId;

    Shiny.setInputValue('get_music_playlist', {
      type: type,
      character: this.state.character,
      requestId: requestId,
      nonce: Math.random()
    });
    console.log('[MUSIC] Playlist isteniyor:', type, '| Karakter:', this.state.character, '| ID:', requestId);
  },

  // ─── SUNUCUDAN GELEN PLAYLIST'İ İŞLE ───
  receivePlaylist: function(data) {
    // Müzik kapalıysa yoksay
    if (!this.state.enabled) {
      console.log('[MUSIC] Müzik kapalı, gelen playlist yoksayıldı');
      return;
    }

    // Eski/gecikmeli yanıtları yoksay
    if (data.requestId && data.requestId < this._pendingRequestId) {
      console.log('[MUSIC] Eski playlist yanıtı yoksayıldı (ID:', data.requestId, '< güncel:', this._pendingRequestId, ')');
      return;
    }

    var files = data.files || [];
    var type = data.type || 'tema';

    console.log('[MUSIC] Playlist alındı:', type, '|', files.length, 'parça');

    if (type === 'tema') {
      this._themePlaylist = files;
      // Tema varsa çalmaya başla, yoksa doğrudan karakter müziğine geç
      if (files.length > 0 && this.state.phase === 'idle') {
        this.state.phase = 'theme';
        this._playRandomFrom(this._themePlaylist);
      } else {
        // Tema yok, karakter playlist'ini iste
        this._requestPlaylist('karakter');
      }
    } else if (type === 'karakter') {
      this._characterPlaylist = files;
      // Eğer tema bitmiş veya hiç yoksa karakter müziğini başlat
      if (this.state.phase === 'idle' || this.state.phase === 'waiting_character') {
        this.state.phase = 'character';
        this._playRandomFrom(this._characterPlaylist);
      }
    }
  },

  // ─── RASTGELE PARÇA ÇAL ───
  _playRandomFrom: function(playlist) {
    if (!this.state.enabled || !playlist || playlist.length === 0) {
      console.warn('[MUSIC] Çalınacak parça yok');
      return;
    }

    var index = Math.floor(Math.random() * playlist.length);
    var src = playlist[index];
    this._playTrack(src);
  },

  // ─── TEK PARÇA ÇAL (Tek Audio nesnesi) ───
  _playTrack: function(src) {
    // Mevcut sesi tamamen durdur
    this._stopAudio();

    if (!this.state.enabled) return;

    var self = this;
    var audio = new Audio(src);
    audio.volume = 0;
    audio.preload = 'auto';
    this._audio = audio;

    audio.addEventListener('canplaythrough', function() {
      // Bu audio hâlâ aktif mi kontrol et (yarış koruması)
      if (self._audio !== audio) {
        audio.pause();
        audio.src = '';
        return;
      }

      var targetVol = self.state.isDucked ? 0 : self.state.normalVolume;
      self._fadeToVolume(audio, targetVol, self.config.fadeTime);
      audio.play().catch(function(e) {
        console.warn('[MUSIC] Oynatma hatası:', e);
      });

      console.log('[MUSIC] Oynatılıyor [' + self.state.phase + ']:', src.split('/').pop());
    }, { once: true });

    audio.addEventListener('ended', function() {
      // Bu audio hâlâ aktif mi kontrol et
      if (self._audio !== audio) return;

      self._handleTrackEnded();
    }, { once: true });

    audio.addEventListener('error', function(e) {
      console.warn('[MUSIC] Ses hatası:', e);
      if (self._audio !== audio) return;
      self._handleTrackEnded();
    }, { once: true });

    audio.load();
  },

  // ─── PARÇA BİTTİĞİNDE ───
  _handleTrackEnded: function() {
    if (!this.state.enabled) return;

    if (this.state.phase === 'theme') {
      // Ana tema bitti → karakter müziğine geç
      console.log('[MUSIC] Ana tema bitti, karakter müziğine geçiliyor');
      this.state.phase = 'waiting_character';

      if (this._characterPlaylist.length > 0) {
        // Zaten yüklüyse direkt çal
        this.state.phase = 'character';
        this._playRandomFrom(this._characterPlaylist);
      } else {
        // Sunucudan iste
        this._requestPlaylist('karakter');
      }
    } else if (this.state.phase === 'character') {
      // Karakter müziği bitti → bir sonraki rastgele parçayı çal
      this._playRandomFrom(this._characterPlaylist);
    }
  },

  // ─── SESİ DURDUR ───
  _stopAudio: function() {
    // Fade interval'ı temizle
    if (this._fadeInterval) {
      clearInterval(this._fadeInterval);
      this._fadeInterval = null;
    }

    if (this._audio) {
      try {
        this._audio.pause();
        this._audio.src = '';
      } catch(e) { /* yoksay */ }
      this._audio = null;
    }
  },

  // ─── SES SEVİYESİ GEÇİŞİ ───
  _fadeToVolume: function(audio, targetVolume, duration) {
    if (this._fadeInterval) {
      clearInterval(this._fadeInterval);
      this._fadeInterval = null;
    }

    if (!audio) return;

    var startVolume = audio.volume;
    var diff = targetVolume - startVolume;
    if (Math.abs(diff) < 0.01) {
      audio.volume = targetVolume;
      return;
    }

    var steps = 20;
    var stepTime = (duration || 500) / steps;
    var stepSize = diff / steps;
    var currentStep = 0;

    this._fadeInterval = setInterval(function() {
      currentStep++;
      if (currentStep >= steps) {
        try { audio.volume = Math.max(0, Math.min(1, targetVolume)); } catch(e) {}
        clearInterval(this._fadeInterval);
        this._fadeInterval = null;
        return;
      }
      try {
        audio.volume = Math.max(0, Math.min(1, startVolume + (stepSize * currentStep)));
      } catch(e) {
        clearInterval(this._fadeInterval);
        this._fadeInterval = null;
      }
    }.bind(this), stepTime);
  },

  // ─── AÇIK API ───

  // Müziği aç/kapat (sadece "Ayarları Kaydet" butonundan çağrılmalı)
  toggle: function(enabled, character) {
    console.log('[MUSIC] toggle:', enabled ? 'AÇIK' : 'KAPALI', '| Karakter:', character || this.state.character);

    if (character) {
      this.state.character = character;
    }

    // Aynı duruma tekrar geçişi engelle
    if (this.state.enabled === enabled) {
      // Karakter değiştiyse playlist'i yenile
      if (enabled && character && this.state.phase === 'character') {
        this._characterPlaylist = [];
        this._requestPlaylist('karakter');
      }
      return;
    }

    this.state.enabled = enabled;

    if (enabled) {
      this._startFromBeginning();
    } else {
      // Fade out ile durdur
      var audioToStop = this._audio;
      this._audio = null;
      this.state.phase = 'idle';
      this._themePlaylist = [];
      this._characterPlaylist = [];
      this._pendingRequestId++;

      if (audioToStop) {
        this._fadeToVolume(audioToStop, 0, 800);
        setTimeout(function() {
          try {
            audioToStop.pause();
            audioToStop.src = '';
          } catch(e) {}
        }, 900);
      }
    }
  },

  // Karakter değişikliği (sadece "Ayarları Kaydet" sonrası çağrılır)
  setCharacter: function(character) {
    if (!character || character === this.state.character) return;
    console.log('[MUSIC] Karakter değişti:', this.state.character, '→', character);
    this.state.character = character;

    if (!this.state.enabled) return;

    // Karakter müziği çalıyorsa yeni karakter playlist'ine geç
    if (this.state.phase === 'character') {
      this._characterPlaylist = [];
      this._stopAudio();
      this._requestPlaylist('karakter');
    }
    // Tema çalıyorsa tema bittikten sonra yeni karakter müziği gelecek
  },

  // Ses seviyesini ayarla
  setVolume: function(volume) {
    this.state.normalVolume = volume;
    if (this._audio && !this.state.isDucked) {
      this._fadeToVolume(this._audio, volume, 500);
    }
  },

  // TTS/video sırasında sesi kıs
  duck: function() {
    if (this.state.isDucked) return;
    this.state.isDucked = true;
    if (this._audio) {
      this._fadeToVolume(this._audio, 0, 400);
    }
  },

  // TTS/video bitince sesi geri getir
  unduck: function() {
    if (!this.state.isDucked) return;
    this.state.isDucked = false;
    if (this._audio) {
      this._fadeToVolume(this._audio, this.state.normalVolume, 600);
    }
  }
};

// Global erişim
window.MusicManager = MusicManager;

// ─── SHINY MESAJ İŞLEYİCİLERİ ───
$(document).ready(function() {
  Shiny.addCustomMessageHandler('initMusicManager', function(settings) {
    MusicManager.init(settings);
  });

  // Müziği aç/kapat (sadece ayar kaydedildiğinde çağrılır)
  Shiny.addCustomMessageHandler('toggleMusic', function(data) {
    if (typeof data === 'boolean') {
      MusicManager.toggle(data);
    } else {
      MusicManager.toggle(data.enabled, data.character);
    }
  });

  Shiny.addCustomMessageHandler('setMusicVolume', function(volume) {
    MusicManager.setVolume(volume);
  });

  // Karakter değişikliği (ayar kaydedildiğinde)
  Shiny.addCustomMessageHandler('setMusicCharacter', function(data) {
    MusicManager.setCharacter(data.character);
  });

  // Sunucudan playlist yanıtı
  Shiny.addCustomMessageHandler('setMusicPlaylist', function(data) {
    MusicManager.receivePlaylist(data);
  });

  // Diğer ses kaynakları (TTS, video) çalınca müziği kıs
  document.addEventListener('play', function(e) {
    if (e.target && e.target.tagName === 'AUDIO' && !e.target.src.includes('/music/')) {
      MusicManager.duck();
    }
  }, true);

  document.addEventListener('pause', function(e) {
    if (e.target && e.target.tagName === 'AUDIO' && !e.target.src.includes('/music/')) {
      setTimeout(function() { MusicManager.unduck(); }, 300);
    }
  }, true);
});