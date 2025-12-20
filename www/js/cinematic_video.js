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
        imageDisplayDuration: 3000,
        maxLoadAttempts: 3
    },

    init: function(config) {
        this.elements.video = document.getElementById(config.videoElementId);
        this.elements.image = document.getElementById(config.imageElementId);
        this.elements.container = this.elements.video?.parentElement;

        if (!this.elements.video || !this.elements.image) {
            console.error('[VIDEO] Gerekli elementler bulunamadı');
            return;
        }

        this.elements.video.muted = false;
        this.elements.video.volume = 1.0;
        
        this.elements.video.addEventListener('ended', () => this.handleVideoEnd());
        this.elements.video.addEventListener('error', (e) => this.handleVideoError(e));
        this.elements.video.addEventListener('canplay', () => {
            console.log('[VIDEO] Video yüklendi:', this.elements.video.src);
            this.state.videoLoadAttempts = 0;
        });

        document.addEventListener('visibilitychange', () => {
            if (document.hidden) {
                this.pauseIfPlaying();
            }
        });

        $(document).on('shown.bs.tab', 'a[data-toggle="tab"]', (e) => {
            const target = $(e.target).attr('data-value') || $(e.target).attr('href');
            if (target && (target.includes('settings') || target === '#shiny-tab-settings')) {
                if (this.state.data && !this.state.isPlaying) {
                    this.playSequence('intro');
                }
            } else {
                this.stopEverything();
            }
        });

        console.log('[VIDEO] CinematicVideoManager başlatıldı');
    },

    isSettingsTabActive: function() {
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
            console.warn(`[VIDEO] '${type}' türü için video bulunamadı`);
            return null;
        }
        
        const videos = this.state.data.videos[type];
        if (!videos.length) {
            console.warn(`[VIDEO] '${type}' dizisi boş`);
            return null;
        }
        
        const selected = videos[Math.floor(Math.random() * videos.length)];
        console.log(`[VIDEO] Seçilen '${type}' videosu:`, selected);
        return selected;
    },

    loadCharacter: function(data) {
        console.log('[VIDEO] Yeni karakter yükleniyor:', data.character);
        this.stopEverything();
        
        this.state.data = data;
        this.state.currentChar = data.character;
        
        if (data.image) {
            this.elements.image.src = data.image;
        }
        
        this.playSequence('intro');
    },

    playSequence: function(type) {
        if (!this.isSettingsTabActive()) {
            console.log('[VIDEO] Ayarlar sayfası aktif değil, video oynatılmıyor');
            return;
        }

        this.clearTimer();
        const videoSrc = this.getRandomVideo(type);
        
        if (!videoSrc) {
            console.warn(`[VIDEO] '${type}' için video yok, resim gösteriliyor`);
            this.showImage();
            if (type === 'intro' || type === 'select') {
                this.scheduleNextLoop();
            }
            return;
        }

        this.state.lastVideoType = type;
        this.showVideo(videoSrc);
    },

    showVideo: function(src) {
        if (!this.elements.video || !this.elements.image) return;

        console.log('[VIDEO] Video gösteriliyor:', src);
        
        this.elements.image.classList.add('hidden');
        this.elements.video.classList.add('active');
        
        if (this.elements.container) {
            this.elements.container.classList.add('active');
        }
        
        this.elements.video.src = src;
        this.state.isPlaying = true;
        
        const playPromise = this.elements.video.play();
        if (playPromise) {
            playPromise.catch(error => {
                console.error('[VIDEO] Oynatma hatası:', error);
                this.handleVideoError(error);
            });
        }
    },

    showImage: function() {
        if (!this.elements.video || !this.elements.image) return;

        console.log('[VIDEO] Resim gösteriliyor');
        
        this.elements.video.classList.remove('active');
        this.elements.image.classList.remove('hidden');
        
        if (this.elements.container) {
            this.elements.container.classList.remove('active');
        }
        
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

    handleVideoEnd: function() {
        console.log('[VIDEO] Video bitti, tip:', this.state.lastVideoType);
        
        this.showImage();
        
        const shouldLoop = ['intro', 'select', 'loop'].includes(this.state.lastVideoType);
        if (shouldLoop && this.isSettingsTabActive()) {
            this.scheduleNextLoop();
        }
    },

    handleVideoError: function(error) {
        console.error('[VIDEO] Video hatası:', error, 'Kaynak:', this.elements.video?.src);
        
        this.state.videoLoadAttempts++;
        
        if (this.state.videoLoadAttempts < this.config.maxLoadAttempts) {
            console.log(`[VIDEO] Yeniden deneme (${this.state.videoLoadAttempts}/${this.config.maxLoadAttempts})`);
            setTimeout(() => {
                if (this.elements.video?.src) {
                    this.elements.video.load();
                    this.elements.video.play().catch(e => console.error('[VIDEO] Yeniden oynatma başarısız:', e));
                }
            }, 500);
        } else {
            console.error('[VIDEO] Maksimum deneme sayısına ulaşıldı, resme geçiliyor');
            this.showImage();
            this.state.videoLoadAttempts = 0;
        }
    },

    scheduleNextLoop: function() {
        if (!this.isSettingsTabActive()) {
            console.log('[VIDEO] Loop zamanlandı ama sayfa aktif değil');
            return;
        }

        this.clearTimer();
        
        console.log(`[VIDEO] ${this.config.imageDisplayDuration}ms sonra loop oynatılacak`);
        this.state.timer = setTimeout(() => {
            if (this.isSettingsTabActive()) {
                this.playSequence('loop');
            } else {
                console.log('[VIDEO] Timer tetiklendi ama sayfa artık aktif değil');
            }
        }, this.config.imageDisplayDuration);
    },

    playSelectSequence: function() {
        console.log('[VIDEO] Select sequence tetiklendi');
        this.playSequence('select');
    },

    stopEverything: function() {
        console.log('[VIDEO] Her şey durduruluyor');
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
    console.log('[SHINY] updateCharacterVideo mesajı alındı:', data.character);
    CinematicVideoManager.loadCharacter(data);
});

Shiny.addCustomMessageHandler('triggerVideoSelection', function(message) {
    console.log('[SHINY] triggerVideoSelection mesajı alındı');
    CinematicVideoManager.playSelectSequence();
});