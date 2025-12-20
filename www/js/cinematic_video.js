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

        this.elements.video.muted = false;
        this.elements.video.volume = 1.0;
        
        // Event Listeners
        this.elements.video.addEventListener('ended', () => this.handleVideoEnd());
        this.elements.video.addEventListener('error', (e) => this.handleVideoError(e));
        
        // Page visibility handling
        document.addEventListener('visibilitychange', () => {
            if (document.hidden) this.pauseIfPlaying();
        });

        // Tab switching handling (Stop if leaving Settings, Play if entering)
        $(document).on('shown.bs.tab', 'a[data-toggle="tab"]', (e) => {
            if (this.isSettingsTabActive()) {
                if (this.state.data && !this.state.isPlaying) {
                    // Resume cycle or play intro if just entering
                     if (!this.state.timer && !this.state.isPlaying) {
                        this.playSequence('intro');
                     }
                }
            } else {
                this.stopEverything();
            }
        });

        console.log('[VIDEO] CinematicVideoManager initialized.');
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
            console.warn(`[VIDEO] No video category found for: ${type}`);
            return null;
        }
        
        let videos = this.state.data.videos[type];
        
        // FIX: Handle case where single file is returned as string instead of array
        if (!Array.isArray(videos)) {
            // If it's a string (path), wrap it in an array
            if (typeof videos === 'string' && videos.length > 0) {
                videos = [videos];
            } else {
                // Empty or invalid
                console.warn(`[VIDEO] Video list for '${type}' is empty or invalid.`);
                return null;
            }
        }
        
        if (videos.length === 0) return null;
        
        const selected = videos[Math.floor(Math.random() * videos.length)];
        console.log(`[VIDEO] Selected '${type}' video:`, selected);
        return selected;
    },

    loadCharacter: function(data) {
        console.log('[VIDEO] Loading Character:', data.character);
        
        // 1. Stop any current playback immediately
        this.stopEverything();
        
        // 2. Update State
        this.state.data = data;
        this.state.currentChar = data.character;
        
        // 3. Update Image
        if (data.image) {
            this.elements.image.src = data.image;
        }
        
        // 4. Start Intro immediately
        this.playSequence('intro');
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

        // Apply CSS class to container to handle transitions (Image fades out, Video fades in)
        this.elements.container.classList.add('video-playing');
        
        this.elements.video.src = src;
        this.state.isPlaying = true;
        
        const playPromise = this.elements.video.play();
        if (playPromise) {
            playPromise.catch(error => {
                console.error('[VIDEO] Playback failed:', error);
                this.handleVideoError(error);
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

    handleVideoEnd: function() {
        console.log('[VIDEO] Video ended. Type:', this.state.lastVideoType);
        
        // 1. Show the static image
        this.showImage();
        
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