// www/js/ai_expert_manager.js
// Dosya Yolu: www/js/ai_expert_manager.js
// Aciklama: AI Uzman altyazi animasyonlari, TTS senkronizasyonu ve
//           muzik ses kisma (ducking) yonetimi.
//           Yaris durumu (race condition) onleme mekanizmalarini icerir.

const AIExpertManager = {

  // --- Durum degiskenleri ---
  state: {
    isSpeaking: false,        // AI simdi konusuyor mu
    currentText: '',          // Goruntulenecek tam metin
    displayedChars: 0,        // Simdiye kadar gorunen karakter sayisi
    typeInterval: null,       // Yazma animasyonu interval referansi
    hideTimeout: null,        // Gizleme zamanlayicisi
    audioElement: null,       // Ses elemani (AI konusmasi icin)
    nsPrefix: '',             // Shiny namespace oneki
    accentColor: '#7C4DFF'   // Karakter tema rengi
  },

  // --- Yapilandirma ---
  config: {
    typeSpeed: 40,            // Karakter basina yazma hizi (ms)
    sentencePause: 300,       // Cumle sonu duraklamasi (ms)
    fadeOutDelay: 2000,       // Ses bittikten sonra bekleme (ms)
    maxVisibleChars: 200,     // Ekranda gorunen maksimum karakter
    wordFadeThreshold: 150    // Eski kelimelerin solmaya basladigi esik
  },

  // --- BASLATMA ---

  // Altyaziyi goster ve yazma animasyonunu baslat
  startSubtitle: function(data) {
    // Yaris durumu kontrolu: Zaten konusuyorsa durdur
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
      console.warn('[AI_EXPERT] Altyazi elemanlari bulunamadi');
      return;
    }

    // Avatar guncelle
    if (avatar && data.avatarSrc) {
      avatar.src = data.avatarSrc;
      avatar.style.borderColor = this.state.accentColor;
    }

    // CSS degiskenini guncelle
    strip.style.setProperty('--ai-expert-accent', this.state.accentColor);

    // Metni sifirla
    textEl.textContent = '';
    textEl.classList.add('ai-expert-typing');

    // Seridi goster (giris animasyonu)
    strip.classList.remove('ai-expert-hidden', 'ai-expert-exiting');
    strip.classList.add('ai-expert-entering', 'ai-expert-visible', 'ai-expert-speaking');

    // Giris animasyonu bittikten sonra 'entering' sinifini kaldir
    setTimeout(function() {
      strip.classList.remove('ai-expert-entering');
    }, 600);

    // Muzik ses kisma
    if (window.MusicManager) {
      window.MusicManager.duck();
    }

    // Yazma animasyonunu baslat
    this._startTyping();

    console.log('[AI_EXPERT] Altyazi baslatildi:', this.state.currentText.substring(0, 50) + '...');
  },

  // --- YAZMA ANIMASYONU ---
  _startTyping: function() {
    var self = this;

    // Onceki interval'i temizle
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
        // Tum metin yazildi
        clearInterval(self.state.typeInterval);
        self.state.typeInterval = null;
        textEl.classList.remove('ai-expert-typing');
        return;
      }

      self.state.displayedChars++;
      var visible = text.substring(0, self.state.displayedChars);

      // Ekranda gorunen metin cok uzunsa basindan kirp
      if (visible.length > self.config.maxVisibleChars) {
        // En yakin kelime sinirinda kirp
        var trimStart = visible.length - self.config.maxVisibleChars;
        var spaceIdx = visible.indexOf(' ', trimStart);
        if (spaceIdx > 0 && spaceIdx < trimStart + 30) {
          visible = '...' + visible.substring(spaceIdx + 1);
        } else {
          visible = '...' + visible.substring(trimStart);
        }
      }

      textEl.textContent = visible;

      // Cumle sonu duraklamasi (. ! ?)
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

    // Mevcut sesi durdur (yaris durumu onleme)
    this._stopAudio();

    var audio = new Audio();
    audio.src = data.src;
    audio.volume = 1.0;
    audio.preload = 'auto';
    this.state.audioElement = audio;

    audio.addEventListener('ended', function() {
      if (self.state.audioElement !== audio) return; // Yaris korumasi
      self._onAudioEnded();
    }, { once: true });

    audio.addEventListener('error', function() {
      if (self.state.audioElement !== audio) return;
      console.warn('[AI_EXPERT] Ses oynatma hatasi');
      self._onAudioEnded();
    }, { once: true });

    var playPromise = audio.play();
    if (playPromise !== undefined) {
      playPromise.catch(function(err) {
        console.warn('[AI_EXPERT] Otomatik oynatma engellendi:', err.message);
        // Ses oynatma basarisiz, sadece altyazi goster
        self._scheduleHide(self._estimateReadTime(self.state.currentText));
      });
    }
  },

  // --- SES BITTIKTEN SONRA ---
  _onAudioEnded: function() {
    this.state.audioElement = null;

    // TTS gorsellestiricisini durdur
    if (window.ttsVisualizerState && window.ttsVisualizerState.stop) {
      window.ttsVisualizerState.stop();
    }

    // Altyaziyi kisa bir gecikmeyle gizle
    this._scheduleHide(this.config.fadeOutDelay);
  },

  // --- SES OLMADAN GERI DONUS (fallback) ---
  noAudioFallback: function(data) {
    // Ses yoksa metin uzunluguna gore tahmini gosterim suresi
    var textLength = data.textLength || this.state.currentText.length || 100;
    var estimatedMs = this._estimateReadTime(this.state.currentText || '');
    this._scheduleHide(estimatedMs);
  },

  // --- OKUMA SURESI TAHMINI ---
  _estimateReadTime: function(text) {
    if (!text || !text.length) return 5000;
    // Ortalama Turkce okuma hizi: dakikada ~180 kelime, kelime basi ~5.5 karakter
    var words = text.length / 5.5;
    var minutes = words / 180;
    var ms = Math.max(4000, Math.min(15000, minutes * 60 * 1000));
    return ms + this.config.fadeOutDelay;
  },

  // --- GIZLEME ZAMANLAYICISI ---
  _scheduleHide: function(delayMs) {
    var self = this;

    if (this.state.hideTimeout) {
      clearTimeout(this.state.hideTimeout);
    }

    this.state.hideTimeout = setTimeout(function() {
      self._hideSubtitle();
    }, delayMs);
  },

  // --- ALTYAZIYI GIZLE ---
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

    // Durumu sifirla
    this.state.isSpeaking = false;
    this.state.currentText = '';
    this.state.displayedChars = 0;

    // Muzik sesini geri getir
    if (window.MusicManager && !window.MusicManager.state._sttActive) {
      window.MusicManager.unduck();
    }

    // Shiny'ye konusma bitti sinyali gonder
    if (this.state.nsPrefix) {
      var inputId = this.state.nsPrefix + 'ai_expert_speech_ended';
      Shiny.setInputValue(inputId, Date.now(), { priority: 'event' });
    }
  },

  // --- DURDURMA ---
  stopSubtitle: function(data) {
    // Zamanlayicilari temizle
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

    // TTS gorsellestiricisini durdur
    if (window.ttsVisualizerState && window.ttsVisualizerState.stop) {
      window.ttsVisualizerState.stop();
    }

    // Altyaziyi gizle
    this._hideSubtitle();

    console.log('[AI_EXPERT] Konusma durduruldu');
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

// Global erisim
window.AIExpertManager = AIExpertManager;

// --- SHINY MESAJ ISLEYICILERI ---
$(document).ready(function() {

  // Altyaziyi baslatma mesaji
  Shiny.addCustomMessageHandler('aiExpertStartSubtitle', function(data) {
    AIExpertManager.startSubtitle(data);
  });

  // Ses oynatma mesaji
  Shiny.addCustomMessageHandler('aiExpertPlayAudio', function(data) {
    AIExpertManager.playAudio(data);
  });

  // Ses olmadan geri donus mesaji
  Shiny.addCustomMessageHandler('aiExpertNoAudioFallback', function(data) {
    AIExpertManager.noAudioFallback(data);
  });

  // Durdurma mesaji
  Shiny.addCustomMessageHandler('aiExpertStopSubtitle', function(data) {
    AIExpertManager.stopSubtitle(data);
  });

  // TTS gorsellestiricisi gorunurlugu
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
