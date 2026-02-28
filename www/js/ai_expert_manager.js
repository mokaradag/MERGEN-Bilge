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
    stopRequested: false      // Durdurma istendi mi
  },

  // --- Yapılandırma ---
  config: {
    typeSpeed: 35,            // Karakter başına yazma hızı (ms)
    sentencePause: 250,       // Cümle sonu duraklaması (ms)
    fadeOutDelay: 2000,       // Ses bittikten sonra bekleme (ms)
    maxVisibleChars: 300,     // Ekranda görünen maksimum karakter
    wordFadeThreshold: 250    // Eski kelimelerin solmaya başladığı eşik
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

  // --- SES OYNATMA (eski uyumluluk için) ---
  playAudio: function(data) {
    this._playAudioInternal(data.src, data.duration);
  },

  // --- SES BİTTİKTEN SONRA ---
  _onAudioEnded: function() {
    this.state.audioElement = null;

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

    if (this.state.hideTimeout) {
      clearTimeout(this.state.hideTimeout);
    }

    this.state.hideTimeout = setTimeout(function() {
      self._hideSubtitle();
    }, delayMs);
  },

  // --- ALTYAZIYI GİZLE ---
  _hideSubtitle: function() {
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
    this._stopAudio();
    this.state.isSpeaking = false;
    this.state.stopRequested = false;
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

  // Durdurma butonu doğrudan tıklama işleyicisi (Shiny binding'e ek olarak)
  $(document).on('click', '.ai-expert-stop-btn', function(e) {
    e.preventDefault();
    e.stopPropagation();
    console.log('[AI_EXPERT] Durdurma butonu tıklandı (JS)');
    AIExpertManager.stopSubtitle({});
  });
});
