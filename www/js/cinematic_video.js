/* www/js/cinematic_video.js */
/**
 * Dosya Yolu: www/js/cinematic_video.js
 * Açıklama: Karakterlerin sinematik video döngülerini ve geçişlerini yöneten istemci taraflı yönetici.
 * Giriş (intro), döngü (loop) ve seçim (select) videoları arasındaki mantığı,
 * otomatik oynatma politikalarını ve statik görsel geçişlerini kontrol eder.
 */

const CinematicVideoManager = {
    // Yönetici durumu: Mevcut karakter, video listeleri, zamanlayıcılar ve oynatma durumu
    state: {
        currentChar: null,
        data: null,
        timer: null,
        isPlaying: false,
        lastVideoType: null,
        videoLoadAttempts: 0
    },
    // DOM eleman referansları
    elements: {
        video: null,
        image: null,
        container: null
    },
    // Başlatma yapılandırması (yeniden bağlanma için saklanır)
    _initConfig: null,
    // Başlatma tamamlandı mı
    _initialized: false,
    // Olay dinleyicileri kayıtlı mı
    _listenersAttached: false,
    // Yapılandırma ayarları
    config: {
        imageDisplayDuration: 4000, // Döngüler arasında statik görselin gösterilme süresi (ms)
        maxLoadAttempts: 3
    },

    /**
     * DOM elemanlarını ID'lere göre bul ve referansları güncelle.
     * init() ve loadCharacter() tarafından kullanılır.
     * @returns {boolean} Elemanlar başarıyla bulunduysa true
     */
    _ensureElements: function() {
        if (!this._initConfig) return false;

        var video = document.getElementById(this._initConfig.videoElementId);
        var image = document.getElementById(this._initConfig.imageElementId);
        var container = video ? video.parentElement : null;

        if (video && image && container) {
            this.elements.video = video;
            this.elements.image = image;
            this.elements.container = container;
            return true;
        }
        return false;
    },

    /**
     * Yöneticiyi başlatır ve gerekli olay dinleyicilerini (event listeners) kurar.
     * @param {Object} config Eleman ID'lerini içeren yapılandırma nesnesi
     */
    init: function(config) {
        // Yapılandırmayı sakla (yeniden bağlanma için)
        this._initConfig = config;

        if (!this._ensureElements()) {
            console.error('[VIDEO] Kritik DOM elemanları eksik.');
            return;
        }

        // Statik görsel yükleme hatası yönetimi
        this.elements.image.onerror = () => {
            console.warn('[VIDEO] Görsel yüklenemedi. Kırık ikon görünmemesi için gizleniyor.');
            if (this.elements.image) this.elements.image.style.opacity = '0';
            if (this.elements.video) this.elements.video.poster = "";
        };

        // Görsel yüklendiğinde görünür yap
        this.elements.image.onload = () => {
            if (this.elements.image) this.elements.image.style.opacity = '1';
        };

        /**
         * Tarayıcı otomatik oynatma (autoplay) politikası yönetimi:
         * Videolar başlangıçta sessiz (muted) başlatılır. İlk kullanıcı etkileşiminden (tıklama, tuş) sonra ses açılır.
         */
        this.elements.video.muted = true;
        this.elements.video.volume = 1.0;

        // Olay dinleyicilerini sadece bir kez kaydet
        if (!this._listenersAttached) {
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

            // Video olaylarını dinle
            this.elements.video.addEventListener('ended', () => this.handleVideoEnd());
            this.elements.video.addEventListener('error', (e) => this.handleVideoError(e));

            // Sekme görünürlüğü değiştiğinde performansı korumak için videoyu yönet
            document.addEventListener('visibilitychange', () => {
                if (document.hidden) {
                    this.pauseIfPlaying();
                } else {
                    this.resumeIfPaused();
                }
            });

            // Shiny sekmeleri arasındaki değişimi izle (Ayarlar sekmesine özel çalışma)
            $(document).on('shown.bs.tab', 'a[data-toggle="tab"]', (e) => {
                var nowOnSettings = this.isSettingsTabActive();

                if (nowOnSettings) {
                    // Elemanları yeniden doğrula (sekme geçişlerinde referans kaybı koruması)
                    this._ensureElements();
                    if (this.state.data) {
                        console.log('[VIDEO] Ayarlar sekmesine girildi, giriş (intro) başlatılıyor');
                        this.playSequence('intro');
                    }
                } else {
                    console.log('[VIDEO] Ayarlar sekmesinden çıkıldı, kaynak tüketmemek için durduruluyor');
                    this.stopEverything();
                }
            });

            this._listenersAttached = true;
        }

        this._initialized = true;
        console.log('[VIDEO] CinematicVideoManager başarıyla başlatıldı.');

        // Bekleyen karakter yüklemesi varsa şimdi işle
        if (this._pendingLoad) {
            var pending = this._pendingLoad;
            this._pendingLoad = null;
            console.log('[VIDEO] Bekleyen karakter yüklemesi işleniyor:', pending.data.character);
            this.loadCharacter({ data: pending.data, trigger: pending.trigger });
        }
    },

    /**
     * Mevcut aktif sekmenin "Ayarlar" (Kişiselleştirme veya Yapılandırma) olup olmadığını kontrol eder.
     */
    isSettingsTabActive: function() {
        var activeTab = document.querySelector('.sidebar-menu li.active a');
        if (!activeTab) return false;

        var dataValue = activeTab.getAttribute('data-value');
        var href = activeTab.getAttribute('href');

        return dataValue === 'settings' ||
               dataValue === 'tab_settings' ||
               href === '#shiny-tab-settings' ||
               dataValue === 'settings_kisisel' ||
               dataValue === 'settings_yapilandirma';
    },

    /**
     * Belirli bir kategoriden (intro, loop, select) rastgele bir video seçer.
     * @param {string} type Video kategorisi
     */
    getRandomVideo: function(type) {
        if (!this.state.data || !this.state.data.videos || !this.state.data.videos[type]) {
            console.warn('[VIDEO] \'' + type + '\' kategorisi bulunamadı');
            return null;
        }

        var videos = this.state.data.videos[type];

        if (!videos || (Array.isArray(videos) && videos.length === 0)) {
            console.warn('[VIDEO] \'' + type + '\' için video listesi boş');
            return null;
        }

        if (typeof videos === 'string' && videos.length > 0) {
            videos = [videos];
        }

        if (!Array.isArray(videos)) {
            console.error('[VIDEO] \'' + type + '\' geçersiz format:', typeof videos);
            return null;
        }

        var selected = videos[Math.floor(Math.random() * videos.length)];
        console.log('[VIDEO] \'' + type + '\' seçildi:', selected);
        return selected;
    },

    /**
     * R/Shiny tarafından gönderilen karakter verilerini yükler ve süreci başlatır.
     * @param {Object} message Karakter görsel ve video yollarını içeren veri
     */
    loadCharacter: function(message) {
        var data = message.data || message;
        var trigger = message.trigger || 'auto';

        console.log('[VIDEO] Karakter yükleniyor:', data.character, 'tetikleyici:', trigger);

        // DOM elemanları null ise yeniden bulmayı dene
        if (!this.elements.video || !this.elements.image) {
            if (this._initConfig) {
                console.log('[VIDEO] Elemanlar kayıp, yeniden bağlanmaya çalışılıyor...');
                if (this._ensureElements()) {
                    console.log('[VIDEO] Elemanlar yeniden bağlandı.');
                    // Başlatma henüz yapılmadıysa şimdi yap
                    if (!this._initialized) {
                        this.init(this._initConfig);
                        return; // init() bekleyen yüklemeyi işler
                    }
                } else {
                    console.warn('[VIDEO] DOM elemanları henüz hazır değil, veri saklanıyor ve bekleniyor');
                    this.state.data = data;
                    this.state.currentChar = data.character;
                    this._pendingLoad = { data: data, trigger: trigger };
                    return;
                }
            } else {
                console.warn('[VIDEO] DOM elemanları ve yapılandırma hazır değil, veri saklanıyor');
                this.state.data = data;
                this.state.currentChar = data.character;
                this._pendingLoad = { data: data, trigger: trigger };
                return;
            }
        }

        this.stopEverything();

        this.state.data = data;
        this.state.currentChar = data.character;

        if (data.image) {
            this.elements.image.src = data.image;
            this.elements.video.poster = data.image;
            console.log('[VIDEO] Resim ve poster güncellendi:', data.image);
        }

        var self = this;
        var playIntro = function() {
            if (self.isSettingsTabActive()) {
                console.log('[VIDEO] Giriş videosu başlatılıyor');
                self.playSequence('intro');
            }
        };

        // Eğer kullanıcı tıkladıysa hemen, otomatikse kısa bir gecikmeyle başlat
        if (trigger === 'click') {
            playIntro();
        } else {
            setTimeout(playIntro, 100);
        }
    },

    /**
     * Belirli bir kategorideki video döngüsünü yürütür.
     * @param {string} type Oynatılacak sekans tipi
     */
    playSequence: function(type) {
        if (!this.isSettingsTabActive()) {
            console.log('[VIDEO] Ayarlar sekmesinde değiliz, oynatma iptal edildi.');
            return;
        }

        this.clearTimer();
        var videoSrc = this.getRandomVideo(type);

        if (!videoSrc) {
            console.warn('[VIDEO] \'' + type + '\' için video yok, görsele dönülüyor.');
            this.showImage();
            this.scheduleNextLoop();
            return;
        }

        this.state.lastVideoType = type;
        this.showVideo(videoSrc);
    },

    /**
     * Video oynatıcıyı görünür yapar ve kaynağı yükleyip oynatır.
     * @param {string} src Video dosya yolu
     */
    showVideo: function(src) {
        if (!this.elements.video) return;

        console.log('[VIDEO] Oynatılıyor:', src);

        // Kapsayıcıya 'video-playing' sınıfı ekleyerek CSS üzerinden görünürlüğü ayarla
        if (this.elements.container) {
            this.elements.container.classList.add('video-playing');
        }

        this.elements.video.src = src;
        this.elements.video.load();
        this.state.isPlaying = true;

        // Arka plan müziği varsa sesini kıs (ducking)
        if (window.MusicManager) {
            window.MusicManager.duck();
        }

        var self = this;
        var playPromise = this.elements.video.play();
        if (playPromise) {
            playPromise.catch(function(error) {
                // Tarayıcı kısıtlaması nedeniyle engellenirse sessiz modda tekrar dene
                if (error.name === 'NotAllowedError' && self.elements.video && !self.elements.video.muted) {
                    console.warn('[VIDEO] Sesli oynatma engellendi, sessiz deneniyor');
                    self.elements.video.muted = true;
                    self.elements.video.play().catch(function(e2) {
                        console.error('[VIDEO] Oynatma tamamen başarısız:', e2);
                        self.handleVideoError(e2);
                    });
                    return;
                }
                console.error('[VIDEO] Oynatma hatası:', error);
                self.handleVideoError(error);
            });
        }
    },

    /**
     * Videoyu gizler ve statik görseli ön plana çıkarır.
     */
    showImage: function() {
        if (!this.elements.container) return;

        console.log('[VIDEO] Statik görsele geçiliyor');

        // CSS sınıfını kaldırarak varsayılan (görselin göründüğü) duruma dön
        this.elements.container.classList.remove('video-playing');

        this.pauseVideo();
        this.state.isPlaying = false;
    },

    /**
     * Videoyu duraklatır.
     */
    pauseVideo: function() {
        if (this.elements.video && !this.elements.video.paused) {
            this.elements.video.pause();
        }
    },

    /**
     * Eğer video aktif olarak oynuyorsa duraklatır.
     */
    pauseIfPlaying: function() {
        if (this.state.isPlaying) {
            this.pauseVideo();
        }
    },

    /**
     * Sayfa tekrar görünür olduğunda duraklatılan videoyu devam ettirir.
     */
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

    /**
     * Video sona erdiğinde bir sonraki adımı belirler.
     * Mantık: Giriş -> Bekleme -> Döngü, Seçim -> Bekleme -> Döngü
     */
    handleVideoEnd: function() {
        console.log('[VIDEO] Video sona erdi. Tip:', this.state.lastVideoType);

        this.showImage();

        // Arka plan müziğinin sesini normale döndür
        if (window.MusicManager) {
            window.MusicManager.unduck();
        }

        // Ayarlar sekmesindeysek bir sonraki döngüyü planla
        if (this.isSettingsTabActive()) {
            this.scheduleNextLoop();
        }
    },

    /**
     * Belirli bir bekleme süresinden sonra 'loop' tipi videoyu başlatır.
     */
    scheduleNextLoop: function() {
        this.clearTimer();
        var self = this;

        console.log('[VIDEO] Sonraki döngü planlandı: ' + this.config.imageDisplayDuration + 'ms');
        this.state.timer = setTimeout(function() {
            if (self.isSettingsTabActive()) {
                self.playSequence('loop');
            }
        }, this.config.imageDisplayDuration);
    },

    /**
     * Video yükleme/oynatma hatası durumunda görsele dön ve döngüyü sürdür.
     */
    handleVideoError: function(error) {
        console.error('[VIDEO] Hata oluştu:', error);
        this.showImage();
        this.scheduleNextLoop();
    },

    /**
     * Karakter seçildiğinde (örn: Ayarları Kaydet butonuna tıklandığında) oynatılır.
     */
    playSelectSequence: function() {
        // Elemanları doğrula (kaydet sonrası referans kaybı koruması)
        if (!this.elements.video || !this.elements.image) {
            this._ensureElements();
        }
        console.log('[VIDEO] Seçim animasyonu tetiklendi.');
        this.playSequence('select');
    },

    /**
     * Tüm zamanlayıcıları ve oynatmayı durdurarak temizlik yapar.
     */
    stopEverything: function() {
        this.clearTimer();
        this.pauseVideo();
        this.showImage();
        this.state.isPlaying = false;
        this.state.lastVideoType = null;
    },

    /**
     * Aktif zamanlayıcıyı (setTimeout) temizler.
     */
    clearTimer: function() {
        if (this.state.timer) {
            clearTimeout(this.state.timer);
            this.state.timer = null;
        }
    }
};

// Global erişim
window.CinematicVideoManager = CinematicVideoManager;

/**
 * R/Shiny Özel Mesaj İşleyicileri
 * $(document).ready() içinde kayıt edilir - Shiny'nin hazır olması garanti edilir
 */
$(document).ready(function() {
    // Karakter verileri güncellendiğinde tetiklenir
    Shiny.addCustomMessageHandler('updateCharacterVideo', function(data) {
        CinematicVideoManager.loadCharacter(data);
    });

    // Karakter seçim animasyonu (select) istendiğinde tetiklenir
    Shiny.addCustomMessageHandler('triggerVideoSelection', function(message) {
        CinematicVideoManager.playSelectSequence();
    });
});
