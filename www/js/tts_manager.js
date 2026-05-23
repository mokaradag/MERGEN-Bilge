// www/js/tts_manager.js

$(document).ready(function() {
  // -------------------------------------------------
  // TTS (Metin Okuma) Kuyruk Sistemi
  // -------------------------------------------------

  function notifyTTSPlaying(isPlaying) {
    try {
      if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
        Shiny.setInputValue('tts_is_playing', !!isPlaying, { priority: 'event' });
      }
    } catch (e) {}
  }

  function setVisualizerTalking() {
    if (window.ttsVisualizerState && window.ttsVisualizerState.setTalking) {
      window.ttsVisualizerState.setTalking();
    }
  }

  function setVisualizerPaused() {
    if (window.ttsVisualizerState && window.ttsVisualizerState.setPaused) {
      window.ttsVisualizerState.setPaused();
    }
  }

  function setVisualizerIdle() {
    if (window.ttsVisualizerState && window.ttsVisualizerState.setIdle) {
      window.ttsVisualizerState.setIdle();
    }
  }

  function duckMusicForTTS() {
    if (window.MusicManager && typeof window.MusicManager.duck === 'function') {
      // Legacy browser smoke marker: MusicManager.duck()
      window.MusicManager.duck('tts');
    }
  }

  function unduckMusicForTTS() {
    if (window.MusicManager && typeof window.MusicManager.unduck === 'function') {
      // Legacy browser smoke marker: MusicManager.unduck()
      window.MusicManager.unduck('tts');
    }
  }

  function releaseAudio(audio) {
    if (!audio) return;

    audio.onplay = null;
    audio.onpause = null;
    audio.onended = null;
    audio.onerror = null;

    try {
      audio.pause();
      audio.currentTime = 0;
      audio.removeAttribute('src');
      audio.load();
    } catch (e) {}
  }

  function finalizeTTSPlayback(options) {
    options = options || {};

    window.mergenTTS.isPlaying = false;

    if (options.clearCurrent !== false) {
      window.mergenTTS.currentAudio = null;
    }

    if (window.mergenTTS.queue.length === 0 || options.force === true) {
      setVisualizerIdle();
      unduckMusicForTTS();
      notifyTTSPlaying(false);
    }
  }

  window.mergenTTS = {
    queue: [],
    isPlaying: false,
    currentAudio: null,

    stop: function() {
      if (this.currentAudio) {
        releaseAudio(this.currentAudio);
        this.currentAudio = null;
      }

      this.queue = [];
      this.isPlaying = false;

      setVisualizerIdle();

      // "Seslendirmeyi Durdur" basıldığında onended çalışmadığı için
      // arka plan müziğini burada TTS sahibi adına normale döndür.
      unduckMusicForTTS();

      // AI Uzman modülüne TTS durumunu bildir (yarış durumu önleme)
      notifyTTSPlaying(false);
    }
  };

  Shiny.addCustomMessageHandler('playAudioMessage', function(message) {
    if (!message || !message.src) return;

    // Kuyruğa indeks ile ekle
    window.mergenTTS.queue.push({
      id: message.id,
      src: message.src,
      index: message.chunkIndex || 0
    });

    // Doğru cümle sırasını sağlamak için kuyruğu sırala (0, 1, 2...)
    window.mergenTTS.queue.sort((a, b) => a.index - b.index);

    processTTSQueue();
  });

  Shiny.addCustomMessageHandler('stopTTSPlayback', function(message) {
    if (window.mergenTTS && typeof window.mergenTTS.stop === 'function') {
      window.mergenTTS.stop();
    }
  });

  function processTTSQueue() {
    if (window.mergenTTS.isPlaying || window.mergenTTS.queue.length === 0) return;

    const item = window.mergenTTS.queue.shift();
    window.mergenTTS.isPlaying = true;

    setVisualizerTalking();

    try {
      const audio = new Audio(item.src);
      audio.volume = 1.0;

      if (window.MergenAudioLifecycle &&
          typeof window.MergenAudioLifecycle.markAudio === 'function') {
        window.MergenAudioLifecycle.markAudio(audio, 'tts');
      } else if (audio.dataset) {
        audio.dataset.mergenAudioOwner = 'tts';
      }

      window.mergenTTS.currentAudio = audio;

      audio.onplay = function() {
        if (window.mergenTTS.currentAudio !== audio) return;

        setVisualizerTalking();
        duckMusicForTTS();

        // AI Uzman modülüne TTS başladığını bildir (yarış durumu önleme)
        notifyTTSPlaying(true);
      };

      audio.onpause = function() {
        if (window.mergenTTS.currentAudio !== audio) return;

        if (!audio.ended) {
          setVisualizerPaused();
        }
      };

      audio.onended = function() {
        if (window.mergenTTS.currentAudio !== audio) return;

        window.mergenTTS.currentAudio = null;
        window.mergenTTS.isPlaying = false;

        if (window.mergenTTS.queue.length === 0) {
          finalizeTTSPlayback({ clearCurrent: false });
        }

        processTTSQueue();
      };

      audio.onerror = function(e) {
        if (window.mergenTTS.currentAudio !== audio) return;

        // Tarayıcı medya hatası kodu (MediaError.MEDIA_ERR_*) ve src uzunluğunu
        // R konsoluna kadar yükselt, böylece sunucu tarafından da görünür olur.
        var errCode = (audio.error && audio.error.code) ? audio.error.code : 'unknown';
        var srcLen = (item && item.src) ? item.src.length : 0;
        console.warn('[MERGEN TTS] Ses hatası: kod=' + errCode + ' srcLen=' + srcLen, e);
        try {
          if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
            Shiny.setInputValue('tts_browser_diag', {
              kind: 'audio_error',
              code: errCode,
              srcLen: srcLen,
              ts: Date.now()
            }, { priority: 'event' });
          }
        } catch (_) {}

        window.mergenTTS.currentAudio = null;
        window.mergenTTS.isPlaying = false;

        if (window.mergenTTS.queue.length === 0) {
          finalizeTTSPlayback({ clearCurrent: false });
        }

        processTTSQueue();
      };

      const playPromise = audio.play();

      if (playPromise !== undefined) {
        playPromise.then(() => {
          if (window.mergenTTS.currentAudio !== audio) return;

          console.log('[MERGEN TTS] Parça oynatılıyor', item.index);
        }).catch(error => {
          if (window.mergenTTS.currentAudio !== audio) return;

          // Hata adını (NotAllowedError / NotSupportedError / AbortError ...)
          // R konsoluna kadar yükselt; sessiz başarısızlıkları bitir.
          var errName = error && error.name ? error.name : 'PlayError';
          var errMsg  = error && error.message ? error.message : String(error);
          console.warn('[MERGEN TTS] play() reddedildi: ' + errName + ' - ' + errMsg);
          try {
            if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
              Shiny.setInputValue('tts_browser_diag', {
                kind: 'play_rejected',
                name: errName,
                message: errMsg,
                srcLen: (item && item.src) ? item.src.length : 0,
                ts: Date.now()
              }, { priority: 'event' });
            }
          } catch (_) {}

          releaseAudio(audio);

          window.mergenTTS.currentAudio = null;
          window.mergenTTS.isPlaying = false;

          if (window.mergenTTS.queue.length === 0) {
            finalizeTTSPlayback({ clearCurrent: false });
          }

          processTTSQueue();
        });
      }
    } catch (e) {
      console.error('[MERGEN TTS] İstisna:', e);

      if (window.mergenTTS.currentAudio) {
        releaseAudio(window.mergenTTS.currentAudio);
        window.mergenTTS.currentAudio = null;
      }

      window.mergenTTS.isPlaying = false;

      if (window.mergenTTS.queue.length === 0) {
        finalizeTTSPlayback({ clearCurrent: false });
      }

      processTTSQueue();
    }
  }
});