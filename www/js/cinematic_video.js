/* www/js/cinematic_video.js */

const CinematicVideoManager = {
    state: {
        currentChar: null,
        data: null,
        timer: null,
        isPlaying: false,
        lastVideoType: null,
        videoLoadAttempts: 0
    },
    elements: {
        video: null,
        image: null,
        container: null
    },
    config: {
        imageDisplayDuration: 4000, // Duration to show image between loops (ms)
        maxLoadAttempts: 3
    },

    init: function(config) {
        this.elements.video = document.getElementById(config.videoElementId);
        this.elements.image = document.getElementById(config.imageElementId);
        // Find the container (parent of the video element)
        this.elements.container = this.elements.video ? this.elements.video.parentElement : null;

        if (!this.elements.video || !this.elements.image || !this.elements.container) {
            console.error('[VIDEO] Critical elements missing in DOM.');
            return;
        }
		
        this.elements.image.onerror = () => {
            console.warn('[VIDEO] Image failed to load. Hiding element to prevent broken icon.');
            this.elements.image.style.opacity = '0';
            this.elements.video.poster = "";
        };
        
        this.elements.image.onload = () => {
            this.elements.image.style.opacity = '1';
        };

        // Tarayıcı otomatik oynatma politikası: ilk başta sessiz başlat,
        // kullanıcı etkileşiminden sonra sesi aç
        this.elements.video.muted = true;
        this.elements.video.volume = 1.0;

        // Kullanıcı etkileşimi sonrası sesi aç
        var self = this;
        var unmuteOnInteraction = function() {
            if (self.elements.video) {
                self.elements.video.muted = false;
                console.log('[VIDEO] Kullanıcı etkileşimi algılandı, ses açıldı');
            }
            document.removeEventListener('click', unmuteOnInteraction);
            document.removeEventListener('keydown', unmuteOnInteraction);
        };
        document.addEventListener('click', unmuteOnInteraction, { once: true });
        document.addEventListener('keydown', unmuteOnInteraction, { once: true });
        
        // Event Listeners
        this.elements.video.addEventListener('ended', () => this.handleVideoEnd());
        this.elements.video.addEventListener('error', (e) => this.handleVideoError(e));
        
        // Sayfa görünürlük değişikliği: sekme gizlenince duraklat, görününce devam et
        document.addEventListener('visibilitychange', () => {
            if (document.hidden) {
                this.pauseIfPlaying();
            } else {
                this.resumeIfPaused();
            }
        });

		// Sekme değişimini izle
		$(document).on('shown.bs.tab', 'a[data-toggle="tab"]', (e) => {
			const nowOnSettings = this.isSettingsTabActive();
			
			if (nowOnSettings) {
				if (this.state.data) {
					console.log('[VIDEO] Ayarlar sekmesine girildi, intro başlatılıyor');
					this.playSequence('intro');
				}
			} else {
				console.log('[VIDEO] Ayarlar sekmesinden çıkıldı, tüm oynatma durduruluyor');
				this.stopEverything();
			}
		});

        console.log('[VIDEO] CinematicVideoManager initialized.');

        // Bekleyen karakter yüklemesi varsa şimdi işle
        if (this._pendingLoad) {
            var pending = this._pendingLoad;
            this._pendingLoad = null;
            console.log('[VIDEO] Bekleyen karakter yüklemesi işleniyor:', pending.data.character);
            this.loadCharacter({ data: pending.data, trigger: pending.trigger });
        }
    },

    isSettingsTabActive: function() {
        // Check if the active sidebar item points to settings
        const activeTab = document.querySelector('.sidebar-menu li.active a');
        if (!activeTab) return false;
        
        const dataValue = activeTab.getAttribute('data-value');
        const href = activeTab.getAttribute('href');
        
        return dataValue === 'settings' || 
               dataValue === 'tab_settings' || 
               href === '#shiny-tab-settings';
    },

	getRandomVideo: function(type) {
		if (!this.state.data?.videos?.[type]) {
			console.warn(`[VIDEO] '${type}' kategorisi bulunamadı`);
			return null;
		}
		
		let videos = this.state.data.videos[type];
		
		// Boş veya geçersiz kontrolü
		if (!videos || (Array.isArray(videos) && videos.length === 0)) {
			console.warn(`[VIDEO] '${type}' için video listesi boş`);
			return null;
		}
		
		// Tek string ise diziye dönüştür
		if (typeof videos === 'string' && videos.length > 0) {
			videos = [videos];
		}
		
		// Hâlâ array değilse hata
		if (!Array.isArray(videos)) {
			console.error(`[VIDEO] '${type}' geçersiz format:`, typeof videos);
			return null;
		}
		
		// Rastgele seç
		const selected = videos[Math.floor(Math.random() * videos.length)];
		console.log(`[VIDEO] '${type}' seçildi:`, selected);
		return selected;
	},

	loadCharacter: function(message) {
		const data = message.data || message;
		const trigger = message.trigger || 'auto';

		console.log('[VIDEO] Karakter yükleniyor:', data.character, 'trigger:', trigger);

		// DOM elemanları henüz hazır değilse veriyi sakla ve bekle
		if (!this.elements.video || !this.elements.image) {
			console.warn('[VIDEO] DOM elemanları henüz hazır değil, veri saklanıyor ve bekleniyor');
			this.state.data = data;
			this.state.currentChar = data.character;
			this._pendingLoad = { data: data, trigger: trigger };
			return;
		}

		this.stopEverything();

		this.state.data = data;
		this.state.currentChar = data.character;

		if (data.image) {
			this.elements.image.src = data.image;
			this.elements.video.poster = data.image;
			console.log('[VIDEO] Resim ve poster yüklendi:', data.image);
		}

		const playIntro = () => {
			if (this.isSettingsTabActive()) {
				console.log('[VIDEO] Intro oynatılıyor, trigger:', trigger);
				this.playSequence('intro');
			}
		};

		if (trigger === 'click') {
			playIntro();
		} else {
			setTimeout(playIntro, 100);
		}
	},

    playSequence: function(type) {
        if (!this.isSettingsTabActive()) {
            console.log('[VIDEO] Not on Settings tab, aborting play.');
            return;
        }

        this.clearTimer();
        const videoSrc = this.getRandomVideo(type);
        
        if (!videoSrc) {
            console.warn(`[VIDEO] No videos for '${type}', falling back to image loop.`);
            this.showImage();
            // Even if no video, we schedule next loop to keep the cycle alive
            this.scheduleNextLoop(); 
            return;
        }

        this.state.lastVideoType = type;
        this.showVideo(videoSrc);
    },

	showVideo: function(src) {
        if (!this.elements.video) return;

        console.log('[VIDEO] Video gösteriliyor:', src);

        this.elements.container.classList.add('video-playing');

		this.elements.video.src = src;
		this.elements.video.load();
		this.state.isPlaying = true;

		if (window.MusicManager) {
		  window.MusicManager.duck();
		}

        var self = this;
        const playPromise = this.elements.video.play();
        if (playPromise) {
            playPromise.catch(error => {
                // Otomatik oynatma engellendiyse, sessiz olarak tekrar dene
                if (error.name === 'NotAllowedError' && !self.elements.video.muted) {
                    console.warn('[VIDEO] Sesli oynatma engellendi, sessiz deneniyor');
                    self.elements.video.muted = true;
                    self.elements.video.play().catch(function(e2) {
                        console.error('[VIDEO] Sessiz oynatma da başarısız:', e2);
                        self.handleVideoError(e2);
                    });
                    return;
                }
                console.error('[VIDEO] Oynatma başarısız:', error);
                self.handleVideoError(error);
            });
        }
    },

    showImage: function() {
        if (!this.elements.container) return;

        console.log('[VIDEO] Showing Image');
        
        // Remove CSS class to revert to default state (Image visible, Video hidden)
        this.elements.container.classList.remove('video-playing');
        
        this.pauseVideo();
        this.state.isPlaying = false;
    },

    pauseVideo: function() {
        if (this.elements.video && !this.elements.video.paused) {
            this.elements.video.pause();
        }
    },

    pauseIfPlaying: function() {
        if (this.state.isPlaying) {
            this.pauseVideo();
        }
    },

    // Sayfa tekrar görünür olduğunda videoyu devam ettir
    resumeIfPaused: function() {
        if (!this.isSettingsTabActive()) return;
        if (this.state.isPlaying && this.elements.video && this.elements.video.paused) {
            var playPromise = this.elements.video.play();
            if (playPromise) {
                playPromise.catch(function(error) {
                    console.warn('[VIDEO] Devam ettirme başarısız:', error);
                });
            }
        }
    },

    handleVideoEnd: function() {
		console.log('[VIDEO] Video ended. Type:', this.state.lastVideoType);

		this.showImage();

		if (window.MusicManager) {
		  window.MusicManager.unduck();
		}
        
        // 2. Decide what to do next
        // Logic: Intro -> Loop, Select -> Loop, Loop -> Loop
        if (this.isSettingsTabActive()) {
            this.scheduleNextLoop();
        }
    },

    scheduleNextLoop: function() {
        this.clearTimer();
        
        console.log(`[VIDEO] Scheduling next loop in ${this.config.imageDisplayDuration}ms`);
        this.state.timer = setTimeout(() => {
            if (this.isSettingsTabActive()) {
                // Always go to 'loop' bucket after the wait
                this.playSequence('loop');
            }
        }, this.config.imageDisplayDuration);
    },

    handleVideoError: function(error) {
        console.error('[VIDEO] Error:', error);
        // Fallback to image
        this.showImage();
        // Try to continue cycle
        this.scheduleNextLoop();
    },

    playSelectSequence: function() {
        console.log('[VIDEO] Selection triggered.');
        // "Ayarları Kaydet" clicked -> Play 'select' video
        this.playSequence('select');
    },

    stopEverything: function() {
        this.clearTimer();
        this.pauseVideo();
        this.showImage();
        this.state.isPlaying = false;
        this.state.lastVideoType = null;
    },

    clearTimer: function() {
        if (this.state.timer) {
            clearTimeout(this.state.timer);
            this.state.timer = null;
        }
    }
};

Shiny.addCustomMessageHandler('updateCharacterVideo', function(data) {
    CinematicVideoManager.loadCharacter(data);
});

Shiny.addCustomMessageHandler('triggerVideoSelection', function(message) {
    CinematicVideoManager.playSelectSequence();
});