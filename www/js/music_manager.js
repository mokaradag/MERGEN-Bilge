// www/js/music_manager.js
// Arka plan müzik yönetim sistemi - Tek ses kaynağı mimarisi
// Akış: Ana Tema (bir kez, sadece ilk başlatmada) → Karakter Müziği (rastgele döngü)

const MusicManager = {
  // Tek global durum
  state: {
    enabled: false,          // Müzik açık mı
    character: 'emre',       // Aktif persona (varsayılan: emre)
    phase: 'idle',           // 'idle' | 'theme' | 'character' | 'waiting_character'
    normalVolume: 0.3,
    isDucked: false,
    _sttActive: false        // STT kayıt modunda mı (tam sessizlik için)
  },

  // Tek ses elemanı - yarış durumunu önler
  _audio: null,
  _fadeInterval: null,
  // Sunucudan gelen çalma listeleri
  _themePlaylist: [],
  _characterPlaylist: [],

  // Hatalı parça koruması: aynı bozuk URL sonsuz denenmesin
  _failedTrackUrls: {},
  _consecutiveTrackErrors: 0,

  // Bekleyen istek sayacı (gecikmeli yanıtları yönetir)
  _pendingRequestId: 0,
  // Bekleyen istek tipi: 'tema' | 'karakter' | null
  _pendingRequestType: null,
  // Ana tema daha önce çalındı mı (oturum boyunca bir kez)
  _themePlayedOnce: false,
  // Kasıtlı durdurma bayrağı (hata olaylarını bastırmak için)
  _intentionalStop: false,

  config: {
    fadeTime: 1500,
    crossfadeTime: 1200,      // Karakter geçişi için çapraz solma süresi
    duckedVolumeRatio: 0.15,  // Kısılmış ses seviyesi oranı (normalVolume * bu oran)

    // Kritik güvenlik: hatalı playlist tarayıcıyı kilitlemesin
    maxConsecutiveTrackErrors: 5,
    errorRetryDelay: 500
  },

  // ─── BAŞLATMA ───
  init: function(settings) {
    this.state.enabled = settings.enabled || false;
    this.state.normalVolume = settings.volume || 0.3;
    this.state.character = settings.character || 'emre';

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
	this._failedTrackUrls = {};
	this._consecutiveTrackErrors = 0;

    // Ana tema daha önce çalındıysa doğrudan karakter müziğine geç
    if (this._themePlayedOnce) {
      console.log('[MUSIC] Ana tema zaten çalındı, doğrudan karakter müziğine geçiliyor');
      this._requestPlaylist('karakter');
    } else {
      // İlk kez: sunucudan tema playlist'ini iste
      this._requestPlaylist('tema');
    }
  },

  // ─── SADECE KARAKTER MÜZİĞİNİ BAŞLAT (tema olmadan) ───
	_startCharacterMusic: function() {
	  this._characterPlaylist = [];
	  this._failedTrackUrls = {};
	  this._consecutiveTrackErrors = 0;
	  this.state.phase = 'waiting_character';
	  this._requestPlaylist('karakter');
	},

  // ─── SUNUCUDAN PLAYLIST İSTE ───
	_requestPlaylist: function(type) {
	  this._pendingRequestId++;
	  this._pendingRequestType = type;

	  var requestId = this._pendingRequestId;

	  Shiny.setInputValue('get_music_playlist', {
		type: type,
		character: this.state.character,
		requestId: requestId,
		nonce: Math.random()
	  }, { priority: 'event' });

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

	// Güncel yanıt geldiyse bekleyen istek tipini temizle
	if (!data.requestId || data.requestId === this._pendingRequestId) {
	  this._pendingRequestType = null;
	}

	var files = data.files || [];
	var type = data.type || 'tema';

    console.log('[MUSIC] Playlist alındı:', type, '|', files.length, 'parça');

    if (type === 'tema') {
      this._themePlaylist = files;
      // Tema varsa çalmaya başla, yoksa doğrudan karakter müziğine geç
      if (files.length > 0 && this.state.phase === 'idle') {
        this.state.phase = 'theme';
        this._themePlayedOnce = true;
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

	  var available = playlist.filter(function(src) {
		return !MusicManager._failedTrackUrls[src];
	  });

	  if (available.length === 0) {
		console.error('[MUSIC] Playlist içindeki tüm parçalar hatalı görünüyor. Sonsuz deneme engellendi.');
		this._stopAudio();
		this.state.phase = 'waiting_character';
		return;
	  }

	  var index = Math.floor(Math.random() * available.length);
	  var src = available[index];
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
        try { audio.pause(); audio.src = ''; } catch(e) {}
        return;
      }

      // Kısılmış durumdaysa düşük ses seviyesinde başlat, değilse normal seviyeye çık
      var targetVol = self.state.isDucked
        ? Math.max(0.02, self.state.normalVolume * self.config.duckedVolumeRatio)
        : self.state.normalVolume;
      self._fadeToVolume(audio, targetVol, self.config.fadeTime);
      audio.play().catch(function(e) {
        if (self._intentionalStop) return;
        if (e.name === 'AbortError') return;
        console.warn('[MUSIC] Oynatma hatası:', e.message || e);
      });

      var playingFileName = src.split('/').pop();
      try {
        playingFileName = decodeURIComponent(playingFileName);
      } catch (decodeErr) {
        // Bozuk yüzde-encoding varsa oynatma logu müziği bozmasın
      }
      console.log('[MUSIC] Oynatılıyor [' + self.state.phase + ']:', playingFileName);
    }, { once: true });

    audio.addEventListener('ended', function() {
      // Bu audio hâlâ aktif mi kontrol et
      if (self._audio !== audio) return;

      self._handleTrackEnded();
    }, { once: true });

	audio.addEventListener('error', function(e) {
	  // Kasıtlı durdurma sırasında hata olaylarını bastır
	  if (self._intentionalStop) return;

	  // Artık aktif değilse yoksay
	  if (self._audio !== audio) return;

	  self._failedTrackUrls[src] = true;
	  self._consecutiveTrackErrors++;

	  var fileName = src.split('/').pop();
	  try {
		fileName = decodeURIComponent(fileName);
	  } catch (decodeErr) {
		// Bozuk yüzde-encoding varsa log bile çökmesin
	  }

	  console.warn(
		'[MUSIC] Ses yükleme hatası:',
		fileName,
		'| Ardışık hata:',
		self._consecutiveTrackErrors,
		'| URL:',
		src
	  );

	  if (self._consecutiveTrackErrors >= self.config.maxConsecutiveTrackErrors) {
		console.error('[MUSIC] Çok fazla ardışık ses hatası. Tarayıcı kilitlenmesini önlemek için müzik döngüsü durduruldu.');
		self._stopAudio();
		self.state.phase = 'waiting_character';
		return;
	  }

	  setTimeout(function() {
		if (!self.state.enabled) return;
		if (self._audio !== audio) return;
		self._handleTrackEnded();
	  }, self.config.errorRetryDelay);
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
    this._intentionalStop = true;

    // Fade interval'ı temizle
    if (this._fadeInterval) {
      clearInterval(this._fadeInterval);
      this._fadeInterval = null;
    }

    if (this._audio) {
      try {
        this._audio.pause();
        this._audio.removeAttribute('src');
        this._audio.load(); // Kaynağı temizle (hata olayı tetiklemeden)
      } catch(e) { /* yoksay */ }
      this._audio = null;
    }

    // Kısa gecikmeyle bayrağı sıfırla
    var self = this;
    setTimeout(function() { self._intentionalStop = false; }, 100);
  },

  // ─── YUMUŞAK GEÇİŞLE DURDUR (fade out → callback) ───
  _fadeOutAndStop: function(callback) {
    var audioToFade = this._audio;
    if (!audioToFade) {
      if (callback) callback();
      return;
    }

    // Mevcut audio referansını hemen kaldır (yeni parça ile çakışma önlenir)
    this._audio = null;

    var self = this;
    this._fadeToVolume(audioToFade, 0, this.config.crossfadeTime);
    setTimeout(function() {
      self._intentionalStop = true;
      try {
        audioToFade.pause();
        audioToFade.removeAttribute('src');
        audioToFade.load();
      } catch(e) {}
      setTimeout(function() { self._intentionalStop = false; }, 100);
      if (callback) callback();
    }, self.config.crossfadeTime + 50);
  },

  // ─── SES SEVİYESİ GEÇİŞİ ───
  _fadeToVolume: function(audio, targetVolume, duration) {
    // Önceki fade işlemini temizle
    if (this._fadeInterval) {
      clearInterval(this._fadeInterval);
      this._fadeInterval = null;
    }

    if (!audio) return;

    var startVolume = audio.volume;
    var diff = targetVolume - startVolume;
    if (Math.abs(diff) < 0.01) {
      try { audio.volume = Math.max(0, Math.min(1, targetVolume)); } catch(e) {}
      return;
    }

    var steps = 20;
    var stepTime = (duration || 500) / steps;
    var stepSize = diff / steps;
    var currentStep = 0;
    var self = this;

    // setInterval'da self kullanarak this bağlam sorununu önle
    this._fadeInterval = setInterval(function() {
      currentStep++;
      if (currentStep >= steps) {
        try { audio.volume = Math.max(0, Math.min(1, targetVolume)); } catch(e) {}
        clearInterval(self._fadeInterval);
        self._fadeInterval = null;
        return;
      }
      try {
        audio.volume = Math.max(0, Math.min(1, startVolume + (stepSize * currentStep)));
      } catch(e) {
        clearInterval(self._fadeInterval);
        self._fadeInterval = null;
      }
    }, stepTime);
  },

  // ─── AÇIK API ───

  // Müziği aç/kapat (sadece "Ayarları Kaydet" butonundan çağrılmalı)
  toggle: function(enabled, character) {
    console.log('[MUSIC] toggle:', enabled ? 'AÇIK' : 'KAPALI', '| Karakter:', character || this.state.character);

    var characterChanged = character && character !== this.state.character;
    if (character) {
      this.state.character = character;
    }

	// Aynı duruma tekrar geçiş
	if (this.state.enabled === enabled) {
	  // Müzik açık ve karakter değiştiyse yumuşak geçişle yeni karakter müziğine geç
	  if (enabled && characterChanged && (this.state.phase === 'character' || this.state.phase === 'waiting_character')) {
		this._characterPlaylist = [];
		var self = this;
		this._fadeOutAndStop(function() {
		  self.state.phase = 'waiting_character';
		  self._requestPlaylist('karakter');
		});
		return;
	  }

	  if (enabled) {
		// Kritik koruma:
		// Ana tema playlist'i henüz beklenirken ikinci toggleMusic(TRUE)
		// gelirse karakter müziğine erken geçme.
		var anaTemaBekleniyor =
		  this.state.phase === 'idle' &&
		  !this._themePlayedOnce &&
		  this._pendingRequestType === 'tema';

		if (anaTemaBekleniyor) {
		  console.log('[MUSIC] Ana tema playlist yanıtı bekleniyor; karakter müziğine erken geçiş engellendi');
		  return;
		}

		// Müzik açık ama ana tema henüz hiç çalınmadıysa yeniden tema iste.
		if (this.state.phase === 'idle' && !this._themePlayedOnce) {
		  console.log('[MUSIC] Ana tema akışı yeniden besleniyor');
		  this._requestPlaylist('tema');
		  return;
		}

		// Ana tema daha önce çalındıysa veya karakter fazındaysak karakter müziğini besle.
		var karakterMuzigiYenidenBaslatilsin =
		  this._themePlayedOnce &&
		  (
			!this._audio ||
			this.state.phase === 'waiting_character' ||
			(
			  this.state.phase === 'character' &&
			  this._characterPlaylist.length === 0
			)
		  );

		if (karakterMuzigiYenidenBaslatilsin) {
		  console.log('[MUSIC] Aynı açık duruma geçildi, karakter müziği akışı yeniden başlatılıyor');
		  this._startCharacterMusic();
		}
	  }

	  return;
	}

    this.state.enabled = enabled;

    if (enabled) {
      this._startFromBeginning();
    } else {
      // Yumuşak geçişle durdur
      var audioToStop = this._audio;
      this._audio = null;
	  this.state.phase = 'idle';
	  this._themePlaylist = [];
	  this._characterPlaylist = [];
	  this._pendingRequestId++;
	  this._pendingRequestType = null;

      if (audioToStop) {
        var self = this;
        this._fadeToVolume(audioToStop, 0, 800);
        setTimeout(function() {
          self._intentionalStop = true;
          try {
            audioToStop.pause();
            audioToStop.removeAttribute('src');
            audioToStop.load();
          } catch(e) {}
          setTimeout(function() { self._intentionalStop = false; }, 100);
        }, 900);
      }
    }
  },

  // Karakter değişikliği (sadece "Ayarları Kaydet" sonrası çağrılır)
  setCharacter: function(character) {
    if (!character || character === this.state.character) return;
    console.log('[MUSIC] Karakter değişti:', this.state.character, '->', character);
    this.state.character = character;

    if (!this.state.enabled) return;

    // Karakter müziği çalıyorsa veya bekliyorsa yumuşak geçişle yeni karakter playlist'ine geç
    if (this.state.phase === 'character' || this.state.phase === 'waiting_character') {
      this._characterPlaylist = [];
      var self = this;
      this._fadeOutAndStop(function() {
        self.state.phase = 'waiting_character';
        self._requestPlaylist('karakter');
      });
    }
    // Tema çalıyorsa tema bittikten sonra yeni karakter müziği gelecek
  },

  // Ses seviyesini ayarla
  setVolume: function(volume) {
    this.state.normalVolume = volume;

    if (window.MergenAudioLifecycle &&
        typeof window.MergenAudioLifecycle.applyMusicDuckState === 'function') {
      window.MergenAudioLifecycle.applyMusicDuckState();
      return;
    }

    if (this._audio && !this.state.isDucked) {
      this._fadeToVolume(this._audio, volume, 500);
    }
  },

  // Karakter videosu/TTS/AI Uzman sırasında sesi sahiplik bazlı kıs
  duck: function(owner) {
    if (window.MergenAudioLifecycle &&
        typeof window.MergenAudioLifecycle.duck === 'function') {
      window.MergenAudioLifecycle.duck(owner || 'external_audio');
      return;
    }

    if (this.state.isDucked) return;
    this.state.isDucked = true;
    if (this._audio) {
      var duckedVolume = Math.max(0.02, this.state.normalVolume * this.config.duckedVolumeRatio);
      this._fadeToVolume(this._audio, duckedVolume, 600);
    }
  },

  // Sahip bırakıldığında yalnızca başka sahip kalmadıysa sesi geri getir
  unduck: function(owner) {
    if (window.MergenAudioLifecycle &&
        typeof window.MergenAudioLifecycle.release === 'function') {
      window.MergenAudioLifecycle.release(owner || 'external_audio');
      return;
    }

    if (this.state._sttActive) return;
    if (window.AIExpertManager && window.AIExpertManager.state.isSpeaking) return;
    if (!this.state.isDucked) return;
    this.state.isDucked = false;
    if (this._audio) {
      this._fadeToVolume(this._audio, this.state.normalVolume, 800);
    }
  },

  // STT kaydı sırasında sesi tamamen sıfırla - mikrofon parazitini önler
  duckForSTT: function() {
    if (window.MergenAudioLifecycle &&
        typeof window.MergenAudioLifecycle.duck === 'function') {
      window.MergenAudioLifecycle.duck('stt');
      return;
    }

    if (this.state._sttActive) return;
    this.state._sttActive = true;
    this.state.isDucked = true;
    if (this._audio) {
      this._fadeToVolume(this._audio, 0, 600);
    }
  },

  // STT kaydı bitince yalnızca STT sahipliğini bırak
  unduckAfterSTT: function() {
    if (window.MergenAudioLifecycle &&
        typeof window.MergenAudioLifecycle.release === 'function') {
      window.MergenAudioLifecycle.release('stt');
      return;
    }

    this.state._sttActive = false;
    this.state.isDucked = false;
    if (this._audio) {
      this._fadeToVolume(this._audio, this.state.normalVolume, 800);
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

  // Diğer ses kaynakları (TTS) çalınca müziği kıs
  // NOT: Video için CinematicVideoManager zaten duck/unduck çağırıyor
  document.addEventListener('play', function(e) {
    if (e.target && e.target.tagName === 'AUDIO' && !e.target.src.includes('/music/')) {
      var owner = window.MergenAudioLifecycle
        ? window.MergenAudioLifecycle.getAudioOwner(e.target)
        : 'external_audio';
      MusicManager.duck(owner);
    }
  }, true);

  document.addEventListener('pause', function(e) {
    if (e.target && e.target.tagName === 'AUDIO' && !e.target.src.includes('/music/')) {
      var owner = window.MergenAudioLifecycle
        ? window.MergenAudioLifecycle.getAudioOwner(e.target)
        : 'external_audio';

      setTimeout(function() {
        MusicManager.unduck(owner);
      }, 300);
    }
  }, true);
});