// www/js/music_manager.js
// Arka plan müzik yönetim sistemi

const MusicManager = {
  state: {
    enabled: false,
    volume: 0.3,
    currentTrack: null,
    currentAudio: null,
    playlist: [],
    playlistType: 'genel',
    isTransitioning: false,
    normalVolume: 0.3,
    reducedVolume: 0.08
  },

  config: {
    musicBasePath: 'music/',
    fadeTime: 1500,
    crossfadeTime: 2000
  },

  init: function(settings) {
	this.state.enabled = settings.enabled || false;
	this.state.volume = settings.volume || 0.3;
	this.state.normalVolume = this.state.volume;
	this.state.reducedVolume = 0;

	if (this.state.enabled) {
      this.loadPlaylist('genel');
    }

    console.log('[MUSIC] Manager başlatıldı:', this.state.enabled ? 'AÇIK' : 'KAPALI');
  },

	loadPlaylist: function(type, character) {
	  this.state.playlistType = type;
	  Shiny.setInputValue('get_music_playlist', {
		type: type,
		character: character,
		nonce: Math.random()
	  });
	  console.log('[MUSIC] Playlist sunucudan isteniyor:', type, character || '');
	},

  playNext: function() {
    if (!this.state.enabled || this.state.playlist.length === 0) return;

    const randomIndex = Math.floor(Math.random() * this.state.playlist.length);
    const track = this.state.playlist[randomIndex];

    this.playTrack(track);
  },

  playTrack: function(src) {
    if (this.state.isTransitioning) return;

    const oldAudio = this.state.currentAudio;
    const newAudio = new Audio(src);
    
    newAudio.volume = 0;
    newAudio.preload = 'auto';

    newAudio.addEventListener('canplaythrough', () => {
      this.state.isTransitioning = true;

      if (oldAudio) {
        this.fadeOut(oldAudio, () => {
          oldAudio.pause();
          oldAudio.src = '';
        });
      }

      this.fadeIn(newAudio, this.state.normalVolume, () => {
        this.state.isTransitioning = false;
      });

      newAudio.play().catch(e => console.warn('[MUSIC] Oynatma hatası:', e));

      this.state.currentAudio = newAudio;
      this.state.currentTrack = src;

      newAudio.addEventListener('ended', () => this.playNext());
      
      console.log('[MUSIC] Oynatılıyor:', src.split('/').pop());
    }, { once: true });

    newAudio.load();
  },

  fadeIn: function(audio, targetVolume, callback) {
    const step = targetVolume / 30;
    const interval = this.config.fadeTime / 30;

    const fade = setInterval(() => {
      if (audio.volume < targetVolume - step) {
        audio.volume = Math.min(audio.volume + step, targetVolume);
      } else {
        audio.volume = targetVolume;
        clearInterval(fade);
        if (callback) callback();
      }
    }, interval);
  },

  fadeOut: function(audio, callback) {
    const step = audio.volume / 30;
    const interval = this.config.fadeTime / 30;

    const fade = setInterval(() => {
      if (audio.volume > step) {
        audio.volume = Math.max(audio.volume - step, 0);
      } else {
        audio.volume = 0;
        clearInterval(fade);
        if (callback) callback();
      }
    }, interval);
  },

  setVolume: function(volume) {
    this.state.normalVolume = volume;
    this.state.reducedVolume = 0;

    if (this.state.currentAudio) {
      this.fadeToVolume(this.state.currentAudio, volume, 500);
    }
  },

  fadeToVolume: function(audio, targetVolume, duration) {
    const startVolume = audio.volume;
    const diff = targetVolume - startVolume;
    const steps = 20;
    const stepTime = duration / steps;
    const stepSize = diff / steps;

    let currentStep = 0;
    const interval = setInterval(() => {
      if (currentStep < steps) {
        audio.volume = Math.max(0, Math.min(1, startVolume + (stepSize * currentStep)));
        currentStep++;
      } else {
        audio.volume = targetVolume;
        clearInterval(interval);
      }
    }, stepTime);
  },

  duck: function() {
    if (this.state.currentAudio) {
      this.fadeToVolume(this.state.currentAudio, this.state.reducedVolume, 400);
    }
  },

	unduck: function() {
	  if (this.state.currentAudio) {
		this.fadeToVolume(this.state.currentAudio, this.state.normalVolume, 600);
	  }
	},

	reset: function() {
	  if (this.state.currentAudio) {
		this.state.currentAudio.pause();
		this.state.currentAudio.src = '';
		this.state.currentAudio = null;
	  }
	  this.state.currentTrack = null;
	  this.state.playlist = [];
	},

  toggle: function(enabled) {
    // Aynı duruma tekrar geçişi engelle (yarış durumu koruması)
    if (this.state.enabled === enabled) {
      console.log('[MUSIC] toggle: Zaten', enabled ? 'AÇIK' : 'KAPALI', '- atlanıyor');
      return;
    }
    this.state.enabled = enabled;

    if (enabled) {
      // Önce mevcut sesi temizle (üst üste çalmayı engelle)
      if (this.state.currentAudio) {
        this.state.currentAudio.pause();
        this.state.currentAudio.src = '';
        this.state.currentAudio = null;
      }
      this.state.currentTrack = null;
      this.state.playlist = [];
      this.state.isTransitioning = false;
      this.loadPlaylist('genel');
    } else {
      // Playlist yükleme isteğini de iptal et
      this.state.playlist = [];
      this.state.isTransitioning = false;
      if (this.state.currentAudio) {
        var audioToStop = this.state.currentAudio;
        this.state.currentAudio = null;
        this.state.currentTrack = null;
        this.fadeOut(audioToStop, function() {
          audioToStop.pause();
          audioToStop.src = '';
        });
      }
    }
  },

	switchContext: function(type, character) {
	  if (!this.state.enabled) return;

	  const newType = type === 'karakter' ? 'karakter' : 'genel';

	  if (this.state.playlistType !== newType || (newType === 'karakter' && character) || !this.state.currentAudio) {
		console.log('[MUSIC] Bağlam değişimi:', newType, character || '');

		var audioToFade = this.state.currentAudio;
		this.state.currentAudio = null;
		this.state.currentTrack = null;
		this.state.playlist = [];

		if (audioToFade) {
		  this.fadeOut(audioToFade, function() {
			audioToFade.pause();
			audioToFade.src = '';
		  });
		}

		this.loadPlaylist(newType, character);
	  }
	}
};

$(document).ready(function() {
  Shiny.addCustomMessageHandler('initMusicManager', function(settings) {
    MusicManager.init(settings);
  });

  Shiny.addCustomMessageHandler('toggleMusic', function(enabled) {
    MusicManager.toggle(enabled);
  });

  Shiny.addCustomMessageHandler('setMusicVolume', function(volume) {
    MusicManager.setVolume(volume);
  });

  Shiny.addCustomMessageHandler('switchMusicContext', function(data) {
    MusicManager.switchContext(data.type, data.character);
  });

  Shiny.addCustomMessageHandler('setMusicPlaylist', function(data) {
    // Müzik kapalıysa gelen playlist'i yoksay (gecikmeli yanıt koruması)
    if (!MusicManager.state.enabled) {
      console.log('[MUSIC] Müzik kapalı, gelen playlist yoksayıldı');
      return;
    }
    if (data.files && data.files.length > 0) {
      MusicManager.state.playlist = data.files;
      MusicManager.state.playlistType = data.type;
      console.log('[MUSIC] Playlist sunucudan alındı:', data.type, data.files.length, 'şarkı');

      if (!MusicManager.state.currentAudio && MusicManager.state.enabled) {
        MusicManager.playNext();
      }
    } else {
      console.warn('[MUSIC] Sunucudan boş playlist döndü.');
    }
  });

  document.addEventListener('play', function(e) {
    if (e.target && e.target.tagName === 'AUDIO' && !e.target.src.includes('/music/')) {
      MusicManager.duck();
    }
  }, true);

  document.addEventListener('pause', function(e) {
    if (e.target && e.target.tagName === 'AUDIO' && !e.target.src.includes('/music/')) {
      setTimeout(() => MusicManager.unduck(), 300);
    }
  }, true);

  $(document).on('shown.bs.tab', function() {
    const activeTab = $('.sidebar-menu li.active a').attr('data-value');
    
    if (activeTab === 'chat' || activeTab === 'tab-chat') {
      const hasMessages = $('#chat_content_container .message-bubble').length > 0;
      if (hasMessages) {
        const character = $('[data-character].active').attr('data-character') || 'mergen';
        MusicManager.switchContext('karakter', character);
      } else {
        MusicManager.switchContext('genel');
      }
    } else {
      MusicManager.switchContext('genel');
    }
  });
});