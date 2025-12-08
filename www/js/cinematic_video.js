/* www/js/cinematic_video.js */

// Global State for Cinematic Video System
const CinematicVideoManager = {
    state: 'idle', // idle, playing_intro, playing_loop, playing_select
    playlist: null,
    elements: null,
    currentLoopIndex: 0,
    loopTimer: null,
    observer: null,
    
    init: function(data) {
        this.clearTimers();
        
        // Clean up previous observer if exists
        if (this.observer) {
            this.observer.disconnect();
            this.observer = null;
        }
        
        this.elements = {
            video: document.getElementById(data.videoElementId),
            overlay: document.getElementById(data.overlayId),
            container: document.getElementById(data.containerId)
        };
        
        if (!this.elements.video || !this.elements.overlay) return;

        this.playlist = data.playlist;
        
        // Accent color setup
        if (data.accentColor && this.elements.overlay) {
            this.elements.overlay.style.setProperty('--video-accent-color', data.accentColor);
        }
        
        // Ensure overlay is visible
        this.elements.overlay.style.display = 'flex';
        requestAnimationFrame(() => {
             this.elements.overlay.classList.add('is-active');
        });
        
        // Setup events
        this.setupVideoEvents();
        this.setupVisibilityObserver();
        
        // DÜZELTME: Mod 'intro' ise hemen oynatmaya başla
        if (data.mode === 'intro') {
            console.log("Playing intro for:", data.mode);
            this.playCategory('intro');
        }
    },
    
    setupVisibilityObserver: function() {
        const self = this;
        this.observer = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (!entry.isIntersecting) {
                    // Page Hidden: clear loop timers
                    self.clearTimers();
                } else {
                    // Page Visible: if state was loop and no video is playing, restart loop
                    if (self.state === 'playing_loop' && self.elements.video.paused) {
                        self.playCategory('loop');
                    }
                }
            });
        }, { threshold: 0.1 });
        
        if (this.elements.video) {
            this.observer.observe(this.elements.video);
        }
    },
    
    setupVideoEvents: function() {
        const vid = this.elements.video;
        const newVid = vid.cloneNode(true);
        vid.parentNode.replaceChild(newVid, vid);
        this.elements.video = newVid;
        
        if (this.observer) {
            this.observer.observe(newVid);
        }
        
        const self = this;
        
        // Event: Video Ends
        this.elements.video.addEventListener('ended', function() {
            self.handleVideoEnd();
        });
        
        // Event: Can Play (Cinematic Fade In)
        this.elements.video.addEventListener('canplay', function() {
            self.elements.video.play().then(() => {
                // Video hazır, fade-in yap
                self.elements.overlay.classList.add('is-playing');
                self.elements.overlay.classList.remove('is-ended');
                self.elements.video.classList.remove('video-fade-out');
            }).catch(e => console.warn("Auto-play prevented", e));
        });
        
        this.elements.video.addEventListener('error', function() {
            console.error("Video load error, skipping...");
            self.handleVideoEnd(); 
        });
    },
    
    playCategory: function(category) {
        if (!this.playlist || !this.playlist[category]) return;
        
        // If element hidden, don't start
        if (!this.isElementVisible(this.elements.video)) return;
        
        this.state = 'playing_' + category;
        
        const files = Array.isArray(this.playlist[category]) ? this.playlist[category] : [this.playlist[category]];
        if (files.length === 0) return;
        
        // Random selection
        const selectedSrc = files[Math.floor(Math.random() * files.length)];
        
        this.transitionToVideo(selectedSrc);
    },
    
    transitionToVideo: function(src) {
        const vid = this.elements.video;
        if (!vid) return;

        // 1. Cinematic Fade Out: Video opacity -> 0. 
        // Arkadaki resim (Mergen_resim_original.png vb.) görünür hale gelir.
        vid.classList.add('video-fade-out');
        
        // 2. Wait for transition (1.2s CSS transition matches)
        setTimeout(() => {
            if (this.isElementVisible(vid)) {
                vid.src = src; 
                // src değişince 'canplay' tetiklenecek -> play() -> fade-in
            }
        }, 1200); 
    },
    
    handleVideoEnd: function() {
        if (!this.isElementVisible(this.elements.video)) return;
        
        if (this.state === 'playing_intro') {
            // Intro bitti -> Loop'a geç
            this.playCategory('loop');
        } 
        else if (this.state === 'playing_select') {
             // Selection bitti -> Loop'a dön veya dur (İsteğe bağlı, Loop daha canlı hissettirir)
            this.playCategory('loop');
        } 
        else if (this.state === 'playing_loop') {
            // Loop bitti -> Fade out yap, bekle, yeni loop
            this.elements.video.classList.add('video-fade-out'); // Resim görünür
            
            const waitTime = Math.random() * 3000 + 2000; // 2-5 sn resim göster
            this.loopTimer = setTimeout(() => {
                this.playCategory('loop');
            }, waitTime);
        }
    },
    
    isElementVisible: function(el) {
        if (!el) return false;
        return (el.offsetParent !== null);
    },
    
    triggerSelection: function() {
        this.clearTimers();
        this.playCategory('select');
    },
    
    clearTimers: function() {
        if (this.loopTimer) clearTimeout(this.loopTimer);
    }
};

$(document).ready(function() {
    Shiny.addCustomMessageHandler('initCharacterVideoSystem', function(data) {
        CinematicVideoManager.init(data);
    });

    Shiny.addCustomMessageHandler('triggerVideoSelection', function(data) {
        CinematicVideoManager.triggerSelection();
    });
});