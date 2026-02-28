// www/js/ai_expert_manager.js
// Dosya Yolu: www/js/ai_expert_manager.js
// Açıklama: AI Uzman altyazı animasyonları, TTS senkronizasyonu ve
//            müzik ses kısma (ducking) yönetimi.
//            Yarış durumu (race condition) önleme mekanizmalarını içerir.

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
    accentColor: '#7C4DFF'    // Karakter tema rengi
  },

  // --- Yapılandırma ---
  config: {
    typeSpeed: 40,            // Karakter başına yazma hızı (ms)
    sentencePause: 300,       // Cümle sonu duraklaması (ms)
    fadeOutDelay: 2000,       // Ses bittikten sonra bekleme (ms)
    maxVisibleChars: 200,     // Ekranda görünen maksimum karakter
    wordFadeThreshold: 150    // Eski kelimelerin solmaya başladığı eşik
  },

  // --- BAŞLATMA ---

  // Altyazıyı göster ve yazma animasyonunu başlat
  startSubtitle: function(data) {
    // Yarış durumu kontrolü: Zaten konuşuyorsa durdur
    if (this.state.isSpeaking) {
      this.stopSubtitle({ nsPrefix: this.state.nsPrefix });
    }

    this.state.isSpeaking = true;
    this.state.currentText = data.text || '';
    this.state.displayedChars = 0;
    this.state.nsPrefix = data.nsPrefix || '';
    this.state.accentColor = data.accentColor || '#7C4DFF';

    var strip = this._getStrip();
    var avatar = this._getAvatar();
    var textEl = this._getTextElement();

    if (!strip || !textEl) {
      console.warn('[AI_EXPERT] Altyazı elemanları bulunamadı');
      return;
    }

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

    // Giriş animasyonu bittikten sonra 'entering' sınıfını kaldır
    setTimeout(function() {
      strip.classList.remove('ai-expert-entering');
    }, 600);

    // Müzik ses kısma
    if (window.MusicManager) {
      window.MusicManager.duck();
    }

    // Yazma animasyonunu başlat
    this._startTyping();

    console.log('[AI_EXPERT] Altyazı başlatıldı:', this.state.currentText.substring(0, 50) + '...');
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
      if (!self.state.isSpeaking) {
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
        // En yakın kelime sınırında kırp
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
          if (self.state.isSpeaking) {
            self._startTyping();
          }
        }, self.config.sentencePause);
      }
    }, this.config.typeSpeed);
  },

  // --- SES OYNATMA ---
  playAudio: function(data) {
    var self = this;

    // Mevcut sesi durdur (yarış durumu önleme)
    this._stopAudio();

    var audio = new Audio();
    audio.src = data.src;
    audio.volume = 1.0;
    audio.preload = 'auto';
    this.state.audioElement = audio;

    audio.addEventListener('ended', function() {
      if (self.state.audioElement !== audio) return; // Yarış koruması
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
        // Ses oynatma başarısız, sadece altyazı göster
        self._scheduleHide(self._estimateReadTime(self.state.currentText));
      });
    }
  },

  // --- SES BİTTİKTEN SONRA ---
  _onAudioEnded: function() {
    this.state.audioElement = null;

    // TTS görselleştiricisini durdur
    if (window.ttsVisualizerState && window.ttsVisualizerState.stop) {
      window.ttsVisualizerState.stop();
    }

    // Altyazıyı kısa bir gecikmeyle gizle
    this._scheduleHide(this.config.fadeOutDelay);
  },

  // --- SES OLMADAN GERİ DÖNÜŞ (fallback) ---
  noAudioFallback: function(data) {
    // Ses yoksa metin uzunluğuna göre tahmini gösterim süresi
    var textLength = data.textLength || this.state.currentText.length || 100;
    var estimatedMs = this._estimateReadTime(this.state.currentText || '');
    this._scheduleHide(estimatedMs);
  },

  // --- OKUMA SÜRESİ TAHMİNİ ---
  _estimateReadTime: function(text) {
    if (!text || !text.length) return 5000;
    // Ortalama Türkçe okuma hızı: dakikada ~180 kelime, kelime başı ~5.5 karakter
    var words = text.length / 5.5;
    var minutes = words / 180;
    var ms = Math.max(4000, Math.min(15000, minutes * 60 * 1000));
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

      // Animasyon bittikten sonra tamamen gizle
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
    this.state.currentText = '';
    this.state.displayedChars = 0;

    // Müzik sesini geri getir
    if (window.MusicManager && !window.MusicManager.state._sttActive) {
      window.MusicManager.unduck();
    }

    // Shiny'ye konuşma bitti sinyali gönder
    if (this.state.nsPrefix) {
      var inputId = this.state.nsPrefix + 'ai_expert_speech_ended';
      Shiny.setInputValue(inputId, Date.now(), { priority: 'event' });
    }
  },

  // --- DURDURMA ---
  stopSubtitle: function(data) {
    // Zamanlayıcıları temizle
    if (this.state.typeInterval) {
      clearInterval(this.state.typeInterval);
      this.state.typeInterval = null;
    }
    if (this.state.hideTimeout) {
      clearTimeout(this.state.hideTimeout);
      this.state.hideTimeout = null;
    }

    // Sesi durdur
    this._stopAudio();

    // TTS görselleştiricisini durdur
    if (window.ttsVisualizerState && window.ttsVisualizerState.stop) {
      window.ttsVisualizerState.stop();
    }

    // Altyazıyı gizle
    this._hideSubtitle();

    console.log('[AI_EXPERT] Konuşma durduruldu');
  },

  // --- SES DURDURMA ---
  _stopAudio: function() {
    if (this.state.audioElement) {
      try {
        this.state.audioElement.pause();
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

  // Altyazıyı başlatma mesajı
  Shiny.addCustomMessageHandler('aiExpertStartSubtitle', function(data) {
    AIExpertManager.startSubtitle(data);
  });

  // Ses oynatma mesajı
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
});