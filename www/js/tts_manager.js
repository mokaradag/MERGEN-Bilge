// www/js/tts_manager.js

$(document).ready(function() {
  // -------------------------------------------------
  // TTS (Metin Okuma) Kuyruk Sistemi
  // -------------------------------------------------

  const TTS_AUDIO_OWNER = 'tts';

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
      window.MusicManager.duck(TTS_AUDIO_OWNER);
    }
  }

  function unduckMusicForTTS() {
    if (window.MusicManager && typeof window.MusicManager.unduck === 'function') {
      window.MusicManager.unduck(TTS_AUDIO_OWNER);
    }
  }

  function releaseCurrentAudio(audio) {
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
        releaseCurrentAudio(this.currentAudio);
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

        console.warn('[MERGEN TTS] Ses hatası:', e);

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

          console.warn('[MERGEN TTS] Otomatik oynatma engellendi:', error);

          releaseCurrentAudio(audio);
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
        releaseCurrentAudio(window.mergenTTS.currentAudio);
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