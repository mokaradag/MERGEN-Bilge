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
            muteBtn: document.getElementById(data.muteButtonId),
            container: document.getElementById(data.containerId)
        };
        
        if (!this.elements.video || !this.elements.overlay) return;

        this.playlist = data.playlist;
        
        // Accent color setup
        if (data.accentColor && this.elements.overlay) {
            this.elements.overlay.style.setProperty('--video-accent-color', data.accentColor);
        }
        
        // FIX 1: Force visibility immediately to override inline 'display: none' from R
        this.elements.overlay.style.display = 'flex';
        
        // Add active class for opacity transition (make it visible)
        requestAnimationFrame(() => {
             this.elements.overlay.classList.add('is-active');
        });
        
        // Setup events and visibility tracking
        this.setupVideoEvents();
        this.setupVisibilityObserver();
        
        // Start Sequence: Intro -> Loop
        if (data.mode === 'intro') {
            this.playCategory('intro');
        }
    },
    
    setupVisibilityObserver: function() {
        // FIX 2: Stop looping if settings page is hidden (tab switch)
        const self = this;
        
        // Use IntersectionObserver to detect if the video component is off-screen or hidden
        this.observer = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (!entry.isIntersecting) {
                    // Page Hidden: clear any pending loop timers so no new video starts
                    self.clearTimers();
                }
            });
        }, { threshold: 0.1 });
        
        if (this.elements.video) {
            this.observer.observe(this.elements.video);
        }
    },
    
    setupVideoEvents: function() {
        const vid = this.elements.video;
        
        // Clean old events to avoid duplication (clone and replace)
        const newVid = vid.cloneNode(true);
        vid.parentNode.replaceChild(newVid, vid);
        this.elements.video = newVid;
        
        // Re-attach observer to new element
        if (this.observer) {
            this.observer.disconnect();
            this.observer.observe(newVid);
        }
        
        const self = this;
        
        // Event: Video Ends
        this.elements.video.addEventListener('ended', function() {
            self.handleVideoEnd();
        });
        
        // Event: Can Play (Fade In)
        this.elements.video.addEventListener('canplay', function() {
            self.elements.video.play().then(() => {
                self.elements.overlay.classList.add('is-playing');
                self.elements.overlay.classList.remove('is-ended');
                
                // Ensure visibility classes are enforced
                self.elements.overlay.style.display = 'flex';
                self.elements.overlay.classList.add('is-active');
                
                // Smooth Fade In
                self.elements.video.classList.remove('video-fade-out');
            }).catch(e => console.warn("Auto-play prevented", e));
        });
        
        // Event: Error
        this.elements.video.addEventListener('error', function() {
            console.error("Video load error, skipping...");
            self.handleVideoEnd(); // Skip to next to avoid stuck state
        });
    },
    
    playCategory: function(category) {
        if (!this.playlist || !this.playlist[category]) return;
        
        // Safety: If element is hidden (user left page), do not start new playback
        if (!this.isElementVisible(this.elements.video)) return;
        
        this.state = 'playing_' + category;
        
        // Pick a video
        const files = Array.isArray(this.playlist[category]) ? this.playlist[category] : [this.playlist[category]];
        if (files.length === 0) return;
        
        // Random selection for all categories
        const selectedSrc = files[Math.floor(Math.random() * files.length)];
        
        this.transitionToVideo(selectedSrc);
    },
    
    transitionToVideo: function(src) {
        const vid = this.elements.video;
        if (!vid) return;

        // 1. Fade Out Current Video (Reveal Character Image underneath)
        vid.classList.add('video-fade-out');
        
        // 2. Wait for fade out (matches CSS transition: 1.2s)
        setTimeout(() => {
            // Check visibility again before loading new source
            if (this.isElementVisible(vid)) {
                vid.src = src;
                // 'canplay' event will automatically trigger play() and Fade In
            }
        }, 1200); 
    },
    
    handleVideoEnd: function() {
        // FIX 2: Stop chain if hidden (tab switched)
        if (!this.isElementVisible(this.elements.video)) return;
        
        // Determine next step based on current state
        if (this.state === 'playing_intro') {
            // Intro done -> Go to Loop immediately
            this.playCategory('loop');
        } 
        else if (this.state === 'playing_select') {
            // Selection done -> Go back to Loop
            this.playCategory('loop');
        } 
        else if (this.state === 'playing_loop') {
            // Loop done -> Wait a bit -> Play another Loop
            this.elements.video.classList.add('video-fade-out'); // Ensure faded out
            
            const waitTime = Math.random() * 3000 + 2000; // 2-5 seconds random delay
            this.loopTimer = setTimeout(() => {
                this.playCategory('loop');
            }, waitTime);
        }
    },
    
    isElementVisible: function(el) {
        // Robust check: offsetParent returns null if element or any parent has display: none
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

// Global function for mute toggle (called by onclick in HTML)
window.toggleVideoMute = function(videoId) {
  const video = document.getElementById(videoId);
  const muteBtn = video ? video.parentElement.querySelector('.video-mute-btn') : null;
  
  if (!video || !muteBtn) return;
  
  video.muted = !video.muted;
  
  if (video.muted) {
    muteBtn.innerHTML = '<i class="fa-solid fa-volume-xmark"></i>';
    muteBtn.classList.remove('is-unmuted');
    muteBtn.title = 'Sesi Aç';
  } else {
    muteBtn.innerHTML = '<i class="fa-solid fa-volume-high"></i>';
    muteBtn.classList.add('is-unmuted');
    muteBtn.title = 'Sesi Kapat';
  }
};

// Register Shiny Handlers
$(document).ready(function() {
    // Handler: Initialize System
    Shiny.addCustomMessageHandler('initCharacterVideoSystem', function(data) {
        CinematicVideoManager.init(data);
    });

    // Handler: Trigger Selection Video (Save Button)
    Shiny.addCustomMessageHandler('triggerVideoSelection', function(data) {
        CinematicVideoManager.triggerSelection();
    });
});