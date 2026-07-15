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
    chunkAdvanceTimer: null,  // Altyazı-yalnız parçadan ilerleme zamanlayıcısı
    speechToken: 0,           // Eski geri çağrımların yeni konuşmayı kapatmasını önler
    serverSpeechSeq: null,     // Sunucu speech_seq belirteci (Shiny ended doğrulaması)
    currentChunkIndex: 0,     // Şu an oynayan parçanın indeksi (tanılama)
    chunkRetryCount: 0,       // Mevcut parça için oynatma yeniden deneme sayacı
    currentAudioDuration: 0,  // loadedmetadata'dan gelen gerçek medya süresi (sn)
    endedEmitted: false       // ai_expert_speech_ended sinyali yinelenmesin
  },

  // --- Yapılandırma ---
  config: {
    typeSpeed: 35,            // Karakter başına yazma hızı (ms)
    sentencePause: 250,       // Cümle sonu duraklaması (ms)
    fadeOutDelay: 2000,       // Ses bittikten sonra bekleme (ms)
    // Ekranda görünen maksimum karakter sayısı. Uzun parçalarda (3. parça ve
    // sonrası) altyazının ortadan kesilmemesi için yüksek tutulur.
    maxVisibleChars: 2000,
    wordFadeThreshold: 250,   // Eski kelimelerin solmaya başladığı eşik
    chunkPollInterval: 150,   // Sonraki ses parçasını kontrol aralığı (ms)
    chunkWaitMaxMs: 90000,    // Sonraki ses parçası için azami bekleme süresi (ms)
    maxPlaybackRetries: 1,    // Parça başına sınırlı oynatma yeniden denemesi
    subtitleOnlyMinMs: 1200,  // Sessiz (altyazı-yalnız) parçanın asgari görünme süresi (ms)
    subtitleOnlyMaxMs: 12000  // Sessiz parçanın azami görünme süresi (ms)
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
    this.state.serverSpeechSeq = data.speechSeq || null;
    this.state.currentChunkIndex = 0;
    this.state.chunkRetryCount = 0;
    this.state.currentAudioDuration = 0;
    this.state.endedEmitted = false;

    // Önceki konuşmadan kalmış zamanlayıcıları temizle
    this._clearAllTimers();

    var strip = this._getStrip();
    var avatar = this._getAvatar();
    var textEl = this._getTextElement();

    if (!strip || !textEl) {
      console.warn('[AI_EXPERT] Altyazı elemanları bulunamadı');
      this._forceCleanup();
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
      window.MusicManager.duck('ai_expert');
    }

    // TTS görselleştiricisini aktive et
    if (window.ttsVisualizerState && window.ttsVisualizerState.setTalking) {
      window.ttsVisualizerState.setTalking();
    }

    // Yazma animasyonunu başlat
    this._startTyping();

    // Sesi oynat (senkronize - altyazıyla birlikte). 1. parça daima ses içerir.
    this._playAudioInternal(data.audioSrc, 0, true);

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
    this.state.serverSpeechSeq = data.speechSeq || null;
    this.state.sequenceMode = false;
    this.state.totalChunks = 1;
    this.state.nextChunkIndex = 1;
    this.state.queuedChunks = [];
    this.state.currentChunkIndex = 0;
    this.state.chunkRetryCount = 0;
    this.state.currentAudioDuration = 0;
    this.state.endedEmitted = false;

    // Önceki konuşmadan kalmış zamanlayıcıları temizle
    this._clearAllTimers();

    var strip = this._getStrip();
    var avatar = this._getAvatar();
    var textEl = this._getTextElement();

    if (!strip || !textEl) {
      console.warn('[AI_EXPERT] Altyazı elemanları bulunamadı');
      this._forceCleanup();
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
      window.MusicManager.duck('ai_expert');
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

      // Altyazıyı en güncel metne kaydır. Uzun konuşmalarda metin sabit
      // yükseklikteki kutuyu aşınca (overflow gizli) 3. ve sonraki parçalar
      // alttan kırpılıyordu; en alta kaydırmak tüm parçaların okunmasını sağlar.
      try { textEl.scrollTop = textEl.scrollHeight; } catch (e) {}

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

  // --- DAHİLİ SES OYNATMA (parça bazlı; eskime + hata + yeniden deneme korumalı) ---
  // src: ses kaynağı, chunkIndex: parça indeksi (tanılama/eskime), hasAudio:
  // parçanın gerçek sesi var mı. hasAudio=false ise altyazı-yalnız yol izlenir.
  _playAudioInternal: function(src, chunkIndex, hasAudio) {
    var token = this.state.speechToken;

    // Önceki parçanın sesini ve handler'larını temizle (stale referans kalmasın).
    this._stopAudio();
    if (this.state.chunkAdvanceTimer) {
      clearTimeout(this.state.chunkAdvanceTimer);
      this.state.chunkAdvanceTimer = null;
    }

    this.state.currentChunkIndex = Number(chunkIndex || 0);
    this.state.chunkRetryCount = 0;
    this.state.currentAudioDuration = 0;

    // Sessiz (altyazı-yalnız) parça: ses yok -> metni göster, tahmini süreyle ilerle.
    // Böylece kurtarılamayan bir parçanın METNİ yine de gösterilir ve dizi durmaz.
    if (!src || hasAudio === false) {
      console.log('[AI_EXPERT] Parça sesi yok (altyazı-yalnız). idx=' + this.state.currentChunkIndex);
      this._scheduleSubtitleOnlyAdvance(token);
      return;
    }

    this._attachAudio(src, token, this.state.currentChunkIndex, true);
  },

  // --- SES ELEMANI BAĞLA (eskime + hata != bitti + sınırlı yeniden deneme) ---
  _attachAudio: function(src, token, chunkIndex, allowRetry) {
    var self = this;

    var audio = new Audio();
    if (window.MergenAudioLifecycle &&
        typeof window.MergenAudioLifecycle.markAudio === 'function') {
      window.MergenAudioLifecycle.markAudio(audio, 'ai_expert');
    } else if (audio.dataset) {
      audio.dataset.mergenAudioOwner = 'ai_expert';
    }
    audio.src = src;
    audio.volume = 1.0;
    audio.preload = 'auto';
    this.state.audioElement = audio;

    // Gerçek medya süresi (senkron için): sunucu sentez gecikmesi DEĞİL,
    // tarayıcının loadedmetadata ile çözdüğü gerçek süre kullanılır.
    var onMeta = function() {
      if (token !== self.state.speechToken || self.state.audioElement !== audio) return;
      if (isFinite(audio.duration) && audio.duration > 0) {
        self.state.currentAudioDuration = audio.duration;
        console.log('[AI_EXPERT] loadedmetadata idx=' + chunkIndex + ' süre=' + audio.duration.toFixed(2));
      }
    };
    var onEnded = function() {
      // Eskime koruması: eski parça/eski konuşma geri çağrımı yeni konuşmayı bozamaz.
      if (token !== self.state.speechToken || self.state.audioElement !== audio) return;
      self._advanceAfterChunk(token, 'ended');
    };
    var onError = function() {
      if (token !== self.state.speechToken || self.state.audioElement !== audio) return;
      var code = (audio.error && audio.error.code) || 0;
      // HATA, BİTTİ ile aynı DEĞİLDİR. Önce sınırlı bir kez yeniden dene.
      console.warn('[AI_EXPERT] Ses oynatma hatası. idx=' + chunkIndex + ' mediaErrorCode=' + code);
      if (allowRetry && self.state.chunkRetryCount < self.config.maxPlaybackRetries) {
        self.state.chunkRetryCount++;
        console.log('[AI_EXPERT] Parça sesi yeniden deneniyor (' +
          self.state.chunkRetryCount + '/' + self.config.maxPlaybackRetries + '). idx=' + chunkIndex);
        self._cleanupAudioElement(audio);
        if (self.state.audioElement === audio) self.state.audioElement = null;
        self._attachAudio(src, token, chunkIndex, false);
        return;
      }
      // Yeniden deneme tükendi: bu parça için altyazı-yalnız geçişle DEVAM et
      // (altyazıyı hemen gizleme; dizi durmasın).
      console.warn('[AI_EXPERT] Parça sesi kurtarılamadı, altyazı-yalnız geçişle devam. idx=' + chunkIndex);
      self._advanceAfterChunk(token, 'error');
    };

    audio.addEventListener('loadedmetadata', onMeta, { once: true });
    audio.addEventListener('ended', onEnded, { once: true });
    audio.addEventListener('error', onError, { once: true });
    // Handler referanslarını temizlik (removeEventListener) için sakla.
    audio._aiExpertHandlers = { meta: onMeta, ended: onEnded, error: onError };

    var playPromise = audio.play();
    if (playPromise !== undefined) {
      playPromise.catch(function(err) {
        if (token !== self.state.speechToken || self.state.audioElement !== audio) return;

        console.warn('[AI_EXPERT] Otomatik oynatma engellendi:', err.message);

        self._stopAudio();

        if (window.MusicManager) {
          window.MusicManager.unduck('ai_expert');
        }

        if (window.ttsVisualizerState && window.ttsVisualizerState.setIdle) {
          window.ttsVisualizerState.setIdle();
        }

        // Ses oynatılamazsa altyazı deneyimini koru, müziği kilitli bırakma
        self._scheduleHide(self._estimateReadTime(self.state.currentText));
      });
    }
  },

  // --- SESSİZ (ALTYAZI-YALNIZ) PARÇADAN İLERLE ---
  _scheduleSubtitleOnlyAdvance: function(token) {
    var self = this;
    if (this.state.chunkAdvanceTimer) {
      clearTimeout(this.state.chunkAdvanceTimer);
      this.state.chunkAdvanceTimer = null;
    }
    var ms = this._estimateChunkReadTime(this.state.currentText || '');
    this.state.chunkAdvanceTimer = setTimeout(function() {
      if (token !== self.state.speechToken) return;   // eskime koruması
      self.state.chunkAdvanceTimer = null;
      self._advanceAfterChunk(token, 'subtitle_only');
    }, ms);
  },

  // --- SONRAKİ SES PARÇASINI KUYRUKLA ---
  queueAudioChunk: function(data) {
    if (!this.state.isSpeaking) return;
    if (data.speechSeq !== undefined && this.state.serverSpeechSeq !== null &&
        Number(data.speechSeq) !== Number(this.state.serverSpeechSeq)) {
      console.warn('[AI_EXPERT] Eski speechSeq parçası yok sayıldı:', data.speechSeq);
      return;
    }

    var chunkIndex = Number(data.index || 0);
    var chunkDuration = Number(data.audioDuration || 0);
    // hasAudio açıkça verilmediyse audioSrc varlığından türet (geriye dönük uyum).
    var hasAudio = (data.hasAudio === undefined) ? !!(data.audioSrc) : !!data.hasAudio;

    this.state.queuedChunks.push({
      index: chunkIndex,
      text: data.text || '',
      audioSrc: data.audioSrc || '',
      audioDuration: chunkDuration,
      hasAudio: hasAudio,
      token: this.state.speechToken   // eskime koruması: hangi konuşmaya ait
    });

    this.state.queuedChunks.sort(function(a, b) {
      return a.index - b.index;
    });

    console.log('[AI_EXPERT] Parça kuyruğa alındı:', chunkIndex,
      'Beklenen:', this.state.nextChunkIndex, 'ses=' + hasAudio);

    // Şu an bir parça oynamıyorsa VE altyazı-yalnız bir parça beklemede değilse
    // sıradaki hazır parçayı oynatmayı dene (yalnızca beklenen indekste oynar).
    if (!this.state.audioElement && !this.state.chunkAdvanceTimer) {
      this._tryPlayNextQueuedChunk();
    }
  },

  // --- SIRADAKİ HAZIR PARÇAYI OYNATMAYI DENE ---
  // Yalnızca BEKLENEN indeksteki parçayı oynatır; böylece sentez sırası ne
  // olursa olsun oynatma kesin olarak parça indeksi sırasında ilerler.
  _tryPlayNextQueuedChunk: function() {
    var expectedIndex = Number(this.state.nextChunkIndex);
    var queueIndex = this.state.queuedChunks.findIndex(function(item) {
      return item.index === expectedIndex;
    });

    if (queueIndex < 0) return false;

    var item = this.state.queuedChunks.splice(queueIndex, 1)[0];

    // Eskime koruması: farklı bir konuşmaya ait kuyruk öğesini oynatma; sırayı
    // ilerletip sonrakini dene (yeni konuşma zaten kuyruğu sıfırlar; ekstra güvence).
    if (item.token !== undefined && item.token !== this.state.speechToken) {
      this.state.nextChunkIndex += 1;
      return this._tryPlayNextQueuedChunk();
    }

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

    console.log('[AI_EXPERT] Sıradaki ses parçası oynatılıyor:', item.index, 'ses=' + item.hasAudio);

    this._startTyping();
    this._playAudioInternal(item.audioSrc, item.index, item.hasAudio);

    return true;
  },

  // --- SONRAKİ PARÇAYI KISA SÜRE BEKLE ---
  _waitForNextChunk: function() {
    var self = this;
    var startedAt = Date.now();
    var token = this.state.speechToken;   // eskime koruması

    if (this.state.chunkWaitTimer) {
      clearTimeout(this.state.chunkWaitTimer);
      this.state.chunkWaitTimer = null;
    }

    console.log('[AI_EXPERT] Sonraki parça bekleniyor. Beklenen indeks:', this.state.nextChunkIndex);

    var poll = function() {
      // Durdurulmuş veya yeni bir konuşmayla değiştirilmiş dizinin beklemesi durur.
      if (!self.state.isSpeaking || token !== self.state.speechToken) return;

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
    this._playAudioInternal(data.src, 0, true);
  },

  // --- PARÇA BİTTİKTEN/BAŞARISIZ OLDUKTAN SONRA SIRADAKİNE GEÇ ---
  // reason: 'ended' | 'error' | 'subtitle_only'. Tüm çağrılar token korumalıdır.
  _advanceAfterChunk: function(token, reason) {
    if (token !== this.state.speechToken) return;   // eskime koruması

    // Bu parçanın sesini/handler'larını temizle (stale referans kalmasın).
    if (this.state.audioElement) {
      this._cleanupAudioElement(this.state.audioElement);
      this.state.audioElement = null;
    }
    if (this.state.chunkAdvanceTimer) {
      clearTimeout(this.state.chunkAdvanceTimer);
      this.state.chunkAdvanceTimer = null;
    }

    // Ses (yazma animasyonundan önce) erken bittiyse mevcut parça metnini KESME:
    // kalan metni hemen tam göster, sonra sıradaki parçaya geç.
    this._completeCurrentSubtitle();

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

  // --- MEVCUT PARÇA ALTYAZISINI HEMEN TAMAMLA (kesme yerine tam göster) ---
  _completeCurrentSubtitle: function() {
    if (this.state.typeInterval) {
      clearInterval(this.state.typeInterval);
      this.state.typeInterval = null;
    }
    var textEl = this._getTextElement();
    var text = this.state.currentText || '';
    if (!textEl || !text) return;

    this.state.displayedChars = text.length;
    var visible = text;
    if (visible.length > this.config.maxVisibleChars) {
      var trimStart = visible.length - this.config.maxVisibleChars;
      var spaceIdx = visible.indexOf(' ', trimStart);
      if (spaceIdx > 0 && spaceIdx < trimStart + 30) {
        visible = '...' + visible.substring(spaceIdx + 1);
      } else {
        visible = '...' + visible.substring(trimStart);
      }
    }
    textEl.textContent = visible;
    try { textEl.scrollTop = textEl.scrollHeight; } catch (e) {}
    textEl.classList.remove('ai-expert-typing');
  },

  // --- SES OLMADAN GERİ DÖNÜŞ (fallback) ---
  noAudioFallback: function(data) {
    if (data && data.speechSeq !== undefined && this.state.serverSpeechSeq !== null &&
        Number(data.speechSeq) !== Number(this.state.serverSpeechSeq)) {
      console.warn('[AI_EXPERT] Eski speechSeq fallback yok sayıldı:', data.speechSeq);
      return;
    }
    var textLength = data.textLength || this.state.currentText.length || 100;
    var estimatedMs = this._estimateReadTime(this.state.currentText || '');
    this._scheduleHide(estimatedMs);
  },

  // --- OKUMA SÜRESİ TAHMİNİ (tüm konuşma için; fadeOutDelay dahil) ---
  _estimateReadTime: function(text) {
    if (!text || !text.length) return 8000;
    // Ortalama Türkçe okuma hızı: dakikada ~150 kelime (sesli okuma), kelime başı ~6 karakter
    var words = text.length / 6;
    var minutes = words / 150;
    var ms = Math.max(6000, Math.min(30000, minutes * 60 * 1000));
    return ms + this.config.fadeOutDelay;
  },

  // --- TEK PARÇA OKUMA SÜRESİ (altyazı-yalnız parçadan ilerleme için; fadeOutDelay YOK) ---
  _estimateChunkReadTime: function(text) {
    if (!text || !text.length) return this.config.subtitleOnlyMinMs;
    var words = text.length / 6;
    var minutes = words / 150;
    var ms = minutes * 60 * 1000;
    return Math.max(this.config.subtitleOnlyMinMs, Math.min(this.config.subtitleOnlyMaxMs, ms));
  },

  // --- TÜM ZAMANLAYICILARI TEMİZLE ---
  _clearAllTimers: function() {
    if (this.state.typeInterval) { clearInterval(this.state.typeInterval); this.state.typeInterval = null; }
    if (this.state.hideTimeout) { clearTimeout(this.state.hideTimeout); this.state.hideTimeout = null; }
    if (this.state.chunkWaitTimer) { clearTimeout(this.state.chunkWaitTimer); this.state.chunkWaitTimer = null; }
    if (this.state.chunkAdvanceTimer) { clearTimeout(this.state.chunkAdvanceTimer); this.state.chunkAdvanceTimer = null; }
  },

  // --- "KONUŞMA BİTTİ" SİNYALİNİ TEK SEFER GÖNDER (yinelenme koruması) ---
  _emitSpeechEnded: function(overridePrefix) {
    if (this.state.endedEmitted) return;
    this.state.endedEmitted = true;
    var prefix = this.state.nsPrefix || overridePrefix || '';
    if (prefix && window.Shiny && Shiny.setInputValue) {
      Shiny.setInputValue(prefix + 'ai_expert_speech_ended', {
        timestamp: Date.now(),
        speechSeq: this.state.serverSpeechSeq
      }, { priority: 'event' });
    }
  },

  // --- TEK BİR SES ELEMANINI TEMİZLE (handler'ları kaldır + serbest bırak) ---
  _cleanupAudioElement: function(audio) {
    if (!audio) return;
    try {
      var h = audio._aiExpertHandlers;
      if (h) {
        if (h.meta) audio.removeEventListener('loadedmetadata', h.meta);
        if (h.ended) audio.removeEventListener('ended', h.ended);
        if (h.error) audio.removeEventListener('error', h.error);
        audio._aiExpertHandlers = null;
      }
      audio.pause();
      audio.currentTime = 0;
      audio.removeAttribute('src');
      audio.load();
    } catch (e) { /* yoksay */ }
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
    if (this.state.chunkAdvanceTimer) {
      clearTimeout(this.state.chunkAdvanceTimer);
      this.state.chunkAdvanceTimer = null;
    }

    // Müzik sesini geri getir
    if (window.MusicManager) {
      window.MusicManager.unduck('ai_expert');
    }

    // TTS görselleştiricisini durdur
    if (window.ttsVisualizerState && window.ttsVisualizerState.setIdle) {
      window.ttsVisualizerState.setIdle();
    }

    // Shiny'ye konuşma bitti sinyali gönder (tek sefer; yinelenme koruması)
    this._emitSpeechEnded();
  },

  // --- DURDURMA (Kullanıcı butona tıkladığında veya R'dan sinyal geldiğinde) ---
  stopSubtitle: function(data) {
    console.log('[AI_EXPERT] Konuşma durduruluyor...');

    // Durdurma bayrağını ayarla (animasyon döngüsünü kırmak için)
    this.state.stopRequested = true;
    // Konuşma belirtecini ilerlet: uçuştaki eski ended/error/timer geri çağrımları
    // (token !== speechToken) bu artışla anında geçersizleşir.
    this.state.speechToken += 1;

    // Zamanlayıcıları temizle (parça-ilerleme zamanlayıcısı dahil)
    this._clearAllTimers();

    // Sesi zorla durdur (handler'lar removeEventListener ile kaldırılır)
    this._stopAudio();

    // TTS görselleştiricisini durdur
    if (window.ttsVisualizerState) {
      if (window.ttsVisualizerState.setIdle) window.ttsVisualizerState.setIdle();
    }

    // Müzik sesini geri getir
    if (window.MusicManager) {
      window.MusicManager.unduck('ai_expert');
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

    // Shiny'ye konuşma bitti sinyali gönder (tek sefer; yinelenme koruması)
    this._emitSpeechEnded(data && data.nsPrefix);

    console.log('[AI_EXPERT] Konuşma durduruldu');
  },

  // --- ZORLA TEMİZLEME (yeni konuşma başlamadan önce) ---
  _forceCleanup: function() {
    this.state.stopRequested = true;
    this._clearAllTimers();
    this._stopAudio();

    if (window.MusicManager) {
      window.MusicManager.unduck('ai_expert');
    }
    if (window.ttsVisualizerState && window.ttsVisualizerState.setIdle) {
      window.ttsVisualizerState.setIdle();
    }

    this.state.isSpeaking = false;
    this.state.stopRequested = false;
    this.state.sequenceMode = false;
    this.state.totalChunks = 1;
    this.state.nextChunkIndex = 1;
    this.state.queuedChunks = [];
  },

  // --- SES DURDURMA (mevcut ses elemanını handler'larıyla birlikte temizler) ---
  _stopAudio: function() {
    if (this.state.audioElement) {
      this._cleanupAudioElement(this.state.audioElement);
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

