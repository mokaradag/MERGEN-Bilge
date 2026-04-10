// www/js/ai_expert_manager.js
// Dosya Yolu: www/js/ai_expert_manager.js
// Açıklama: AI Uzman altyazı animasyonları, TTS senkronizasyonu ve
//            müzik ses kısma (ducking) yönetimi.
//            Altyazı gösterimi TTS sesi ile senkronize başlatılır.
//            Durdurma butonu doğrudan çalışır.
//            Yazı tipi boyutu ayarlardan alınır.

const AIExpertManager = {

  // --- Durum değişkenleri ---
  state: {
    isSpeaking: false,        // AI şimdi konuşuyor mu
    currentText: '',          // Görüntülenecek tam metin
    displayedChars: 0,        // Şimdiye kadar görünen karakter sayısı
    typeInterval: null,       // Yazma animasyonu interval referansı
    hideTimeout: null,        // Gizleme zamanlayıcısı
    audioElement: null,       // Ses elemanı (AI konuşması için)
    nsPrefix: '',             // Shiny namespace öneki
    accentColor: '#7C4DFF',   // Karakter tema rengi
    fontSize: 'medium',       // Yazı tipi boyutu ayarı
    stopRequested: false,     // Durdurma istendi mi
    currentPage: 'chat',      // Aktif sayfa (altyazı konumu için)
    sequenceMode: false,      // Parçalı TTS akışı aktif mi
    totalChunks: 1,           // Toplam parça sayısı
    nextChunkIndex: 1,        // Sıradaki beklenecek parça indeksi
    queuedChunks: [],         // Hazır gelen ses parçaları kuyruğu
    chunkWaitTimer: null,     // Sonraki parçayı bekleme zamanlayıcısı
    speechToken: 0            // Eski zamanlayıcıların yeni konuşmayı kapatmasını önler
  },

  // --- Yapılandırma ---
  config: {
    typeSpeed: 35,            // Karakter başına yazma hızı (ms)
    sentencePause: 250,       // Cümle sonu duraklaması (ms)
    fadeOutDelay: 2000,       // Ses bittikten sonra bekleme (ms)
    maxVisibleChars: 300,     // Ekranda görünen maksimum karakter
    wordFadeThreshold: 250,   // Eski kelimelerin solmaya başladığı eşik
    chunkPollInterval: 150,   // Sonraki ses parçasını kontrol aralığı (ms)
    chunkWaitMaxMs: 30000     // Sonraki ses parçası için azami bekleme süresi (ms)
  },

  // --- BAŞLATMA (Altyazı + Ses Birlikte - Senkronize) ---
  // TTS hazır olduktan sonra çağrılır, böylece altyazı ve ses aynı anda başlar
  startWithAudio: function(data) {
    // Yarış durumu kontrolü: Zaten konuşuyorsa durdur
    if (this.state.isSpeaking) {
      this._forceCleanup();
    }

    this.state.stopRequested = false;
    this.state.isSpeaking = true;
    this.state.currentText = data.text || '';
    this.state.displayedChars = 0;
    this.state.nsPrefix = data.nsPrefix || '';
    this.state.accentColor = data.accentColor || '#7C4DFF';
    this.state.fontSize = data.fontSize || 'medium';
    this.state.totalChunks = Math.max(1, Number(data.totalChunks || 1));
    this.state.sequenceMode = this.state.totalChunks > 1;
    this.state.nextChunkIndex = 1;
    this.state.queuedChunks = [];
    this.state.speechToken += 1;

    // Önceki konuşmadan kalmış zamanlayıcıları temizle
    if (this.state.typeInterval) {
      clearInterval(this.state.typeInterval);
      this.state.typeInterval = null;
    }
    if (this.state.hideTimeout) {
      clearTimeout(this.state.hideTimeout);
      this.state.hideTimeout = null;
    }
    if (this.state.chunkWaitTimer) {
      clearTimeout(this.state.chunkWaitTimer);
      this.state.chunkWaitTimer = null;
    }

    var strip = this._getStrip();
    var avatar = this._getAvatar();
    var textEl = this._getTextElement();

    if (!strip || !textEl) {
      console.warn('[AI_EXPERT] Altyazı elemanları bulunamadı');
      return;
    }

    // Yazı tipi boyutunu uygula
    this._applyFontSize(textEl);

    // Avatar güncelle
    if (avatar && data.avatarSrc) {
      avatar.src = data.avatarSrc;
      avatar.style.borderColor = this.state.accentColor;
    }

    // CSS değişkenini güncelle
    strip.style.setProperty('--ai-expert-accent', this.state.accentColor);

    // Metni sıfırla
    textEl.textContent = '';
    textEl.classList.add('ai-expert-typing');

    // Sayfa bazlı konum sınıfını uygula
    this._applyPageClass(strip);

    // Şeridi göster (giriş animasyonu)
    strip.classList.remove('ai-expert-hidden', 'ai-expert-exiting');
    strip.classList.add('ai-expert-entering', 'ai-expert-visible', 'ai-expert-speaking');

    setTimeout(function() {
      strip.classList.remove('ai-expert-entering');
    }, 600);

    // Müzik ses kısma
    if (window.MusicManager) {
      window.MusicManager.duck();
    }

    // TTS görselleştiricisini aktive et
    if (window.ttsVisualizerState && window.ttsVisualizerState.setTalking) {
      window.ttsVisualizerState.setTalking();
    }

    // Yazma animasyonunu başlat
    this._startTyping();

    // Sesi oynat (senkronize - altyazıyla birlikte)
    this._playAudioInternal(data.audioSrc, data.audioDuration);

    console.log('[AI_EXPERT] Altyazı + ses senkronize başlatıldı:', this.state.currentText.substring(0, 50) + '...');
  },

  // --- BAŞLATMA (Sadece Altyazı - TTS Yoksa) ---
  startSubtitle: function(data) {
    if (this.state.isSpeaking) {
      this._forceCleanup();
    }

    this.state.stopRequested = false;
    this.state.isSpeaking = true;
    this.state.currentText = data.text || '';
    this.state.displayedChars = 0;
    this.state.nsPrefix = data.nsPrefix || '';
    this.state.accentColor = data.accentColor || '#7C4DFF';
    this.state.fontSize = data.fontSize || 'medium';
    this.state.speechToken += 1;

    // Önceki konuşmadan kalmış zamanlayıcıları temizle
    if (this.state.typeInterval) {
      clearInterval(this.state.typeInterval);
      this.state.typeInterval = null;
    }
    if (this.state.hideTimeout) {
      clearTimeout(this.state.hideTimeout);
      this.state.hideTimeout = null;
    }
    if (this.state.chunkWaitTimer) {
      clearTimeout(this.state.chunkWaitTimer);
      this.state.chunkWaitTimer = null;
    }

    var strip = this._getStrip();
    var avatar = this._getAvatar();
    var textEl = this._getTextElement();

    if (!strip || !textEl) {
      console.warn('[AI_EXPERT] Altyazı elemanları bulunamadı');
      return;
    }

    // Yazı tipi boyutunu uygula
    this._applyFontSize(textEl);

    // Avatar güncelle
    if (avatar && data.avatarSrc) {
      avatar.src = data.avatarSrc;
      avatar.style.borderColor = this.state.accentColor;
    }

    // CSS değişkenini güncelle
    strip.style.setProperty('--ai-expert-accent', this.state.accentColor);

    // Metni sıfırla
    textEl.textContent = '';
    textEl.classList.add('ai-expert-typing');

    // Sayfa bazlı konum sınıfını uygula
    this._applyPageClass(strip);

    // Şeridi göster
    strip.classList.remove('ai-expert-hidden', 'ai-expert-exiting');
    strip.classList.add('ai-expert-entering', 'ai-expert-visible', 'ai-expert-speaking');

    setTimeout(function() {
      strip.classList.remove('ai-expert-entering');
    }, 600);

    // Müzik ses kısma
    if (window.MusicManager) {
      window.MusicManager.duck();
    }

    // TTS görselleştiricisini aktive et (ses olmasa bile animasyon göster)
    if (window.ttsVisualizerState && window.ttsVisualizerState.setTalking) {
      window.ttsVisualizerState.setTalking();
    }

    // Yazma animasyonunu başlat
    this._startTyping();

    console.log('[AI_EXPERT] Altyazı başlatıldı (sessiz):', this.state.currentText.substring(0, 50) + '...');
  },

  // --- YAZI TİPİ BOYUTU UYGULAMA ---
  _applyFontSize: function(textEl) {
    if (!textEl) return;

    // Ayar değerine göre CSS sınıfı uygula
    textEl.classList.remove('ai-font-small', 'ai-font-medium', 'ai-font-large', 'ai-font-xlarge');

    switch (this.state.fontSize) {
      case 'small':
        textEl.classList.add('ai-font-small');
        break;
      case 'large':
        textEl.classList.add('ai-font-large');
        break;
      case 'xlarge':
      case 'x-large':
        textEl.classList.add('ai-font-xlarge');
        break;
      default: // medium
        textEl.classList.add('ai-font-medium');
        break;
    }
  },

  // --- YAZMA ANIMASYONU ---
  _startTyping: function() {
    var self = this;

    // Önceki interval'i temizle
    if (this.state.typeInterval) {
      clearInterval(this.state.typeInterval);
      this.state.typeInterval = null;
    }

    var text = this.state.currentText;
    var textEl = this._getTextElement();
    if (!textEl || !text) return;

    this.state.typeInterval = setInterval(function() {
      // Durdurma kontrolü
      if (!self.state.isSpeaking || self.state.stopRequested) {
        clearInterval(self.state.typeInterval);
        self.state.typeInterval = null;
        return;
      }

      if (self.state.displayedChars >= text.length) {
        // Tüm metin yazıldı
        clearInterval(self.state.typeInterval);
        self.state.typeInterval = null;
        textEl.classList.remove('ai-expert-typing');
        return;
      }

      self.state.displayedChars++;
      var visible = text.substring(0, self.state.displayedChars);

      // Ekranda görünen metin çok uzunsa başından kırp
      if (visible.length > self.config.maxVisibleChars) {
        var trimStart = visible.length - self.config.maxVisibleChars;
        var spaceIdx = visible.indexOf(' ', trimStart);
        if (spaceIdx > 0 && spaceIdx < trimStart + 30) {
          visible = '...' + visible.substring(spaceIdx + 1);
        } else {
          visible = '...' + visible.substring(trimStart);
        }
      }

      textEl.textContent = visible;

      // Cümle sonu duraklaması (. ! ?)
      var currentChar = text[self.state.displayedChars - 1];
      if ('.!?'.indexOf(currentChar) >= 0 && self.state.displayedChars < text.length) {
        clearInterval(self.state.typeInterval);
        self.state.typeInterval = null;
        setTimeout(function() {
          if (self.state.isSpeaking && !self.state.stopRequested) {
            self._startTyping();
          }
        }, self.config.sentencePause);
      }
    }, this.config.typeSpeed);
  },

  // --- DAHİLİ SES OYNATMA (senkronize başlatma için) ---
  _playAudioInternal: function(src, duration) {
    var self = this;

    // Mevcut sesi durdur
    this._stopAudio();

    if (!src) return;

    var audio = new Audio();
    audio.src = src;
    audio.volume = 1.0;
    audio.preload = 'auto';
    this.state.audioElement = audio;

    audio.addEventListener('ended', function() {
      if (self.state.audioElement !== audio) return;
      self._onAudioEnded();
    }, { once: true });

    audio.addEventListener('error', function() {
      if (self.state.audioElement !== audio) return;
      console.warn('[AI_EXPERT] Ses oynatma hatası');
      self._onAudioEnded();
    }, { once: true });

    var playPromise = audio.play();
    if (playPromise !== undefined) {
      playPromise.catch(function(err) {
        console.warn('[AI_EXPERT] Otomatik oynatma engellendi:', err.message);
        // Ses oynatılamazsa süre tahminiyle devam et
        self._scheduleHide(self._estimateReadTime(self.state.currentText));
      });
    }
  },
  
  // --- SONRAKİ SES PARÇASINI KUYRUKLA ---
  queueAudioChunk: function(data) {
    if (!this.state.isSpeaking) return;

    var chunkIndex = Number(data.index || 0);
    var chunkDuration = Number(data.audioDuration || 0);

    this.state.queuedChunks.push({
      index: chunkIndex,
      text: data.text || '',
      audioSrc: data.audioSrc || '',
      audioDuration: chunkDuration
    });

    this.state.queuedChunks.sort(function(a, b) {
      return a.index - b.index;
    });

    console.log('[AI_EXPERT] Parça kuyruğa alındı:', chunkIndex, 'Beklenen:', this.state.nextChunkIndex);

    if (!this.state.audioElement) {
      this._tryPlayNextQueuedChunk();
    }
  },

  // --- SIRADAKİ HAZIR PARÇAYI OYNATMAYI DENE ---
  _tryPlayNextQueuedChunk: function() {
    var expectedIndex = Number(this.state.nextChunkIndex);
    var queueIndex = this.state.queuedChunks.findIndex(function(item) {
      return item.index === expectedIndex;
    });

    if (queueIndex < 0) return false;

    var item = this.state.queuedChunks.splice(queueIndex, 1)[0];
    var textEl = this._getTextElement();

    if (textEl) {
      textEl.textContent = '';
      textEl.classList.add('ai-expert-typing');
    }

    this.state.currentText = item.text || '';
    this.state.displayedChars = 0;
    this.state.nextChunkIndex += 1;

    // Yeni parça başlarken eski gizleme/bekleme zamanlayıcılarını iptal et
    if (this.state.hideTimeout) {
      clearTimeout(this.state.hideTimeout);
      this.state.hideTimeout = null;
    }
    if (this.state.chunkWaitTimer) {
      clearTimeout(this.state.chunkWaitTimer);
      this.state.chunkWaitTimer = null;
    }

    console.log('[AI_EXPERT] Sıradaki ses parçası oynatılıyor:', item.index);

    this._startTyping();
    this._playAudioInternal(item.audioSrc, item.audioDuration);

    return true;
  },

  // --- SONRAKİ PARÇAYI KISA SÜRE BEKLE ---
  _waitForNextChunk: function() {
    var self = this;
    var startedAt = Date.now();

    if (this.state.chunkWaitTimer) {
      clearTimeout(this.state.chunkWaitTimer);
      this.state.chunkWaitTimer = null;
    }

    console.log('[AI_EXPERT] Sonraki parça bekleniyor. Beklenen indeks:', this.state.nextChunkIndex);

    var poll = function() {
      if (!self.state.isSpeaking) return;

      if (self._tryPlayNextQueuedChunk()) {
        self.state.chunkWaitTimer = null;
        return;
      }

      if ((Date.now() - startedAt) >= self.config.chunkWaitMaxMs) {
        console.warn('[AI_EXPERT] Sonraki parça zamanında gelmedi, konuşma sonlandırılıyor.');
        self.state.chunkWaitTimer = null;
        self._scheduleHide(800);
        return;
      }

      self.state.chunkWaitTimer = setTimeout(poll, self.config.chunkPollInterval);
    };

    poll();
  },

  // --- SES OYNATMA (eski uyumluluk için) ---
  playAudio: function(data) {
    this._playAudioInternal(data.src, data.duration);
  },

  // --- SES BİTTİKTEN SONRA ---
  _onAudioEnded: function() {
    this.state.audioElement = null;

    // Parçalı akış varsa sıradaki parçaya geç
    if (this.state.sequenceMode && this.state.nextChunkIndex < this.state.totalChunks) {
      if (this._tryPlayNextQueuedChunk()) {
        return;
      }

      this._waitForNextChunk();
      return;
    }

    this.state.sequenceMode = false;
    this.state.totalChunks = 1;
    this.state.nextChunkIndex = 1;
    this.state.queuedChunks = [];

    // TTS görselleştiricisini durdur
    if (window.ttsVisualizerState && window.ttsVisualizerState.setIdle) {
      window.ttsVisualizerState.setIdle();
    }

    // Altyazıyı kısa bir gecikmeyle gizle
    this._scheduleHide(this.config.fadeOutDelay);
  },

  // --- SES OLMADAN GERİ DÖNÜŞ (fallback) ---
  noAudioFallback: function(data) {
    var textLength = data.textLength || this.state.currentText.length || 100;
    var estimatedMs = this._estimateReadTime(this.state.currentText || '');
    this._scheduleHide(estimatedMs);
  },

  // --- OKUMA SÜRESİ TAHMİNİ ---
  _estimateReadTime: function(text) {
    if (!text || !text.length) return 8000;
    // Ortalama Türkçe okuma hızı: dakikada ~150 kelime (sesli okuma), kelime başı ~6 karakter
    var words = text.length / 6;
    var minutes = words / 150;
    var ms = Math.max(6000, Math.min(30000, minutes * 60 * 1000));
    return ms + this.config.fadeOutDelay;
  },

  // --- GİZLEME ZAMANLAYICISI ---
  _scheduleHide: function(delayMs) {
    var self = this;
    var scheduledToken = this.state.speechToken;

    if (this.state.hideTimeout) {
      clearTimeout(this.state.hideTimeout);
    }

    this.state.hideTimeout = setTimeout(function() {
      // Eski konuşmadan kalan zamanlayıcı yeni konuşmayı kapatamasın
      if (scheduledToken !== self.state.speechToken) return;
      self._hideSubtitle();
    }, delayMs);
  },

  // --- ALTYAZIYI GİZLE ---
  _hideSubtitle: function() {
    // Çok parçalı konuşma hâlâ devam ediyorsa gizleme yapma
    if (this.state.sequenceMode && (
      this.state.audioElement ||
      this.state.queuedChunks.length > 0 ||
      this.state.nextChunkIndex < this.state.totalChunks
    )) {
      console.log('[AI_EXPERT] Aktif parça akışı devam ettiği için gizleme ertelendi.');
      return;
    }

    var strip = this._getStrip();
    var textEl = this._getTextElement();

    if (strip) {
      strip.classList.remove('ai-expert-visible', 'ai-expert-speaking', 'ai-expert-entering');
      strip.classList.add('ai-expert-exiting');

      setTimeout(function() {
        strip.classList.remove('ai-expert-exiting');
        strip.classList.add('ai-expert-hidden');
      }, 500);
    }

    if (textEl) {
      textEl.classList.remove('ai-expert-typing');
    }

    // Durumu sıfırla
    this.state.isSpeaking = false;
    this.state.stopRequested = false;
    this.state.currentText = '';
    this.state.displayedChars = 0;
    this.state.sequenceMode = false;
    this.state.totalChunks = 1;
    this.state.nextChunkIndex = 1;
    this.state.queuedChunks = [];

    if (this.state.chunkWaitTimer) {
      clearTimeout(this.state.chunkWaitTimer);
      this.state.chunkWaitTimer = null;
    }

    // Müzik sesini geri getir
    if (window.MusicManager && !window.MusicManager.state._sttActive) {
      window.MusicManager.unduck();
    }

    // TTS görselleştiricisini durdur
    if (window.ttsVisualizerState && window.ttsVisualizerState.setIdle) {
      window.ttsVisualizerState.setIdle();
    }

    // Shiny'ye konuşma bitti sinyali gönder
    if (this.state.nsPrefix) {
      var inputId = this.state.nsPrefix + 'ai_expert_speech_ended';
      Shiny.setInputValue(inputId, Date.now(), { priority: 'event' });
    }
  },

  // --- DURDURMA (Kullanıcı butona tıkladığında veya R'dan sinyal geldiğinde) ---
  stopSubtitle: function(data) {
    console.log('[AI_EXPERT] Konuşma durduruluyor...');

    // Durdurma bayrağını ayarla (animasyon döngüsünü kırmak için)
    this.state.stopRequested = true;

    // Zamanlayıcıları temizle
    if (this.state.typeInterval) {
      clearInterval(this.state.typeInterval);
      this.state.typeInterval = null;
    }
    if (this.state.hideTimeout) {
      clearTimeout(this.state.hideTimeout);
      this.state.hideTimeout = null;
    }
    if (this.state.chunkWaitTimer) {
      clearTimeout(this.state.chunkWaitTimer);
      this.state.chunkWaitTimer = null;
    }

    // Sesi zorla durdur
    this._stopAudio();

    // TTS görselleştiricisini durdur
    if (window.ttsVisualizerState) {
      if (window.ttsVisualizerState.setIdle) window.ttsVisualizerState.setIdle();
    }

    // Müzik sesini geri getir
    if (window.MusicManager && !window.MusicManager.state._sttActive) {
      window.MusicManager.unduck();
    }

    // Altyazıyı hemen gizle
    var strip = this._getStrip();
    var textEl = this._getTextElement();

    if (strip) {
      strip.classList.remove('ai-expert-visible', 'ai-expert-speaking', 'ai-expert-entering');
      strip.classList.add('ai-expert-exiting');
      setTimeout(function() {
        strip.classList.remove('ai-expert-exiting');
        strip.classList.add('ai-expert-hidden');
      }, 300);
    }

    if (textEl) {
      textEl.classList.remove('ai-expert-typing');
    }

    // Durumu sıfırla
    this.state.isSpeaking = false;
    this.state.currentText = '';
    this.state.displayedChars = 0;
    this.state.sequenceMode = false;
    this.state.totalChunks = 1;
    this.state.nextChunkIndex = 1;
    this.state.queuedChunks = [];

    // Shiny'ye konuşma bitti sinyali gönder
    if (this.state.nsPrefix || (data && data.nsPrefix)) {
      var prefix = this.state.nsPrefix || data.nsPrefix || '';
      var inputId = prefix + 'ai_expert_speech_ended';
      Shiny.setInputValue(inputId, Date.now(), { priority: 'event' });
    }

    console.log('[AI_EXPERT] Konuşma durduruldu');
  },

  // --- ZORLA TEMİZLEME (yeni konuşma başlamadan önce) ---
  _forceCleanup: function() {
    this.state.stopRequested = true;
    if (this.state.typeInterval) {
      clearInterval(this.state.typeInterval);
      this.state.typeInterval = null;
    }
    if (this.state.hideTimeout) {
      clearTimeout(this.state.hideTimeout);
      this.state.hideTimeout = null;
    }
    if (this.state.chunkWaitTimer) {
      clearTimeout(this.state.chunkWaitTimer);
      this.state.chunkWaitTimer = null;
    }
    this._stopAudio();
    this.state.isSpeaking = false;
    this.state.stopRequested = false;
    this.state.sequenceMode = false;
    this.state.totalChunks = 1;
    this.state.nextChunkIndex = 1;
    this.state.queuedChunks = [];
  },

  // --- SES DURDURMA ---
  _stopAudio: function() {
    if (this.state.audioElement) {
      try {
        this.state.audioElement.pause();
        this.state.audioElement.currentTime = 0;
        this.state.audioElement.removeAttribute('src');
        this.state.audioElement.load();
      } catch(e) { /* yoksay */ }
      this.state.audioElement = null;
    }
  },

  // --- SAYFA BAZLI KONUM AYARI ---
  _applyPageClass: function(strip) {
    if (!strip) return;
    // Önceki sayfa sınıflarını kaldır
    strip.classList.remove('ai-expert-page-chat', 'ai-expert-page-files');
    // Aktif sayfaya göre sınıf ekle
    var page = this.state.currentPage || 'chat';
    if (page === 'chat') {
      strip.classList.add('ai-expert-page-chat');
    } else if (page === 'files') {
      strip.classList.add('ai-expert-page-files');
    }
  },

  // Aktif sayfayı güncelle (R tarafından çağrılır)
  setPage: function(page) {
    this.state.currentPage = page || 'chat';
    // Eğer konuşma devam ediyorsa konum sınıfını hemen güncelle
    var strip = this._getStrip();
    if (strip) {
      this._applyPageClass(strip);
    }
  },

  // --- DOM ELEMAN YARDIMCILARI ---
  _getStrip: function() {
    if (!this.state.nsPrefix) return null;
    return document.getElementById(this.state.nsPrefix + 'subtitle_strip');
  },

  _getAvatar: function() {
    if (!this.state.nsPrefix) return null;
    return document.getElementById(this.state.nsPrefix + 'subtitle_avatar');
  },

  _getTextElement: function() {
    if (!this.state.nsPrefix) return null;
    return document.getElementById(this.state.nsPrefix + 'subtitle_text');
  }
};

// Global erişim
window.AIExpertManager = AIExpertManager;

// --- SHINY MESAJ İŞLEYİCİLERİ ---
$(document).ready(function() {

  // Altyazı + ses senkronize başlatma (TTS hazır olduktan sonra çağrılır)
  Shiny.addCustomMessageHandler('aiExpertStartWithAudio', function(data) {
    AIExpertManager.startWithAudio(data);
  });

  // Sadece altyazı başlatma mesajı (TTS yoksa)
  Shiny.addCustomMessageHandler('aiExpertStartSubtitle', function(data) {
    AIExpertManager.startSubtitle(data);
  });

  // Sonraki AI Uzman ses parçasını kuyruğa ekle
  Shiny.addCustomMessageHandler('aiExpertQueueAudioChunk', function(data) {
    AIExpertManager.queueAudioChunk(data);
  });

  // Ses oynatma mesajı (eski uyumluluk)
  Shiny.addCustomMessageHandler('aiExpertPlayAudio', function(data) {
    AIExpertManager.playAudio(data);
  });

  // Ses olmadan geri dönüş mesajı
  Shiny.addCustomMessageHandler('aiExpertNoAudioFallback', function(data) {
    AIExpertManager.noAudioFallback(data);
  });

  // Durdurma mesajı
  Shiny.addCustomMessageHandler('aiExpertStopSubtitle', function(data) {
    AIExpertManager.stopSubtitle(data);
  });

  // TTS görselleştiricisi görünürlüğü
  Shiny.addCustomMessageHandler('aiExpertVisualizerVisibility', function(data) {
    var container = document.querySelector('.tts-visualizer-container');
    if (container) {
      if (data.visible) {
        container.classList.remove('shiny-visual-hidden');
      } else {
        container.classList.add('shiny-visual-hidden');
      }
    }
  });

  // Sayfa değişikliği mesajı (R tarafından gönderilir)
  Shiny.addCustomMessageHandler('aiExpertSetPage', function(data) {
    AIExpertManager.setPage(data.page);
  });

  // Durdurma butonu doğrudan tıklama işleyicisi (Shiny binding'e ek olarak)
  $(document).on('click', '.ai-expert-stop-btn', function(e) {
    e.preventDefault();
    e.stopPropagation();
    console.log('[AI_EXPERT] Durdurma butonu tıklandı (JS)');
    AIExpertManager.stopSubtitle({});
  });
});