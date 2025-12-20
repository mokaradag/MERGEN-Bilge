/* www/js/cinematic_video.js */

const CinematicVideoManager = {
    state: {
        currentChar: null,
        data: null,
        timer: null,
        isPlaying: false
    },
    elements: {
        video: null,
        image: null
    },
    config: {
        imageDisplayDuration: 3000 // Resim goruntulenme suresi (ms)
    },

    init: function(config) {
        this.elements.video = document.getElementById(config.videoElementId);
        this.elements.image = document.getElementById(config.imageElementId);

        if (this.elements.video) {
            // Videolarin sesini ac
            this.elements.video.muted = false;
            
            // Video bittiginde ne yapilacagini yonet
            this.elements.video.onended = () => {
                this.handleVideoEnd();
            };
        }
        
        // Tab degisikligini dinle (Ayarlar sayfasi kontrolu icin)
        $(document).on('shown.bs.tab', 'a[data-toggle="tab"]', (e) => {
            if (this.isSettingsTabActive()) {
                // Eger Ayarlar sayfasina donulduyse ve video oynamiyorsa, donguyu baslat
                // Ancak kullanici istegi: Ayarlar acildiginda intro oynamali
                if (this.state.data) {
                    this.playSequence('intro');
                }
            }
        });
    },

    isSettingsTabActive: function() {
        // Aktif tabin data-value degerini kontrol et
        const activeTab = document.querySelector('.sidebar-menu li.active a');
        return activeTab && (activeTab.getAttribute('data-value') === 'settings' || activeTab.getAttribute('data-value') === 'tab_settings');
    },

    // Rastgele video secimi
    getRandomVideo: function(type) {
        if (!this.state.data || !this.state.data.videos || !this.state.data.videos[type]) return null;
        const videos = this.state.data.videos[type];
        if (videos.length === 0) return null;
        return videos[Math.floor(Math.random() * videos.length)];
    },

    // Yeni karakter verisi yuklendiginde
    loadCharacter: function(data) {
        // Eski islemleri durdur
        this.stopEverything();
        
        this.state.data = data;
        this.state.currentChar = data.character;
        
        // Intro ile basla
        this.playSequence('intro');
    },

    // Belirli bir video turunu oynat
    playSequence: function(type) {
        this.clearTimer();
        
        const videoSrc = this.getRandomVideo(type);
        
        // Eger video yoksa sadece resmi goster
        if (!videoSrc) {
            this.showImage();
            return;
        }

        // Simdi videoyu oynat
        this.state.lastVideoType = type; // Hangi tur video oynadigini kaydet
        this.showVideo(videoSrc);
    },

    showVideo: function(src) {
        if (!this.elements.video) return;

        this.elements.image.style.display = 'none';
        this.elements.video.style.display = 'block';
        this.elements.video.src = src;
        this.elements.video.muted = false; // Ses acik
        
        const playPromise = this.elements.video.play();
        if (playPromise !== undefined) {
            playPromise.catch(error => {
                console.warn("Video oynatma hatasi:", error);
                // Hata olursa resme don
                this.showImage();
            });
        }
    },

    showImage: function() {
        if (!this.elements.image || !this.state.data) return;

        this.elements.video.style.display = 'none';
        this.elements.image.src = this.state.data.image;
        this.elements.image.style.display = 'block';
        
        // Resmi gosterirken sesi kapat/videoyu durdur
        this.elements.video.pause();
    },

    handleVideoEnd: function() {
        // Video bitti, resmi goster
        this.showImage();

        // Son oynatilan video turune gore karar ver
        if (this.state.lastVideoType === 'intro' || this.state.lastVideoType === 'select') {
            // Intro veya Select bitti -> Resim goster -> Sonra Loop
            this.scheduleNextLoop();
        } else if (this.state.lastVideoType === 'loop') {
            // Loop bitti -> Resim goster -> Sonra tekrar Loop (Eger hala ayarlar sayfasindaysa)
            this.scheduleNextLoop();
        }
    },

    scheduleNextLoop: function() {
        // Eger baska sayfadaysak yeni video kuyruklama
        if (!this.isSettingsTabActive()) return;

        this.clearTimer();
        
        // Bir sure resmi goster, sonra loop videosuna gec
        this.state.timer = setTimeout(() => {
            // Sure doldugunda hala ayarlar sayfasinda miyiz kontrol et
            if (this.isSettingsTabActive()) {
                this.playSequence('loop');
            }
        }, this.config.imageDisplayDuration);
    },

    // Ayarlari Kaydet tetikleyicisi
    playSelectSequence: function() {
        this.playSequence('select');
    },

    stopEverything: function() {
        this.clearTimer();
        if (this.elements.video) {
            this.elements.video.pause();
            this.elements.video.currentTime = 0;
        }
    },

    clearTimer: function() {
        if (this.state.timer) {
            clearTimeout(this.state.timer);
            this.state.timer = null;
        }
    }
};

// Shiny mesaj dinleyicileri
Shiny.addCustomMessageHandler('updateCharacterVideo', function(data) {
    CinematicVideoManager.loadCharacter(data);
});

Shiny.addCustomMessageHandler('triggerVideoSelection', function(message) {
    CinematicVideoManager.playSelectSequence();
});