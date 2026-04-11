// www/js/tts_manager.js

$(document).ready(function() {
  // -------------------------------------------------
  // TTS (Metin Okuma) Kuyruk Sistemi
  // -------------------------------------------------
  window.mergenTTS = {
    queue: [],
    isPlaying: false,
    currentAudio: null,
    stop: function() {
      if (this.currentAudio) {
        this.currentAudio.pause();
        this.currentAudio.currentTime = 0;
        this.currentAudio = null;
      }
      this.queue = [];
      this.isPlaying = false;
      if (window.ttsVisualizerState && window.ttsVisualizerState.setIdle) {
        window.ttsVisualizerState.setIdle();
      }
      // "Seslendirmeyi Durdur" basıldığında onended çalışmadığı için
      // arka plan müziğini burada normale döndür
      if (window.MusicManager) {
        window.MusicManager.unduck();
      }
      // AI Uzman modülüne TTS durumunu bildir (yarış durumu önleme)
      try { Shiny.setInputValue('tts_is_playing', false, { priority: 'event' }); } catch(e) {}
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

  function processTTSQueue() {
    if (window.mergenTTS.isPlaying || window.mergenTTS.queue.length === 0) return;

    const item = window.mergenTTS.queue.shift();
    window.mergenTTS.isPlaying = true;

    if (window.ttsVisualizerState && window.ttsVisualizerState.setTalking) {
      window.ttsVisualizerState.setTalking();
    }

    try {
      window.mergenTTS.currentAudio = new Audio(item.src);
      const audio = window.mergenTTS.currentAudio;
      audio.volume = 1.0;

		audio.onplay = function() {
		  if (window.ttsVisualizerState && window.ttsVisualizerState.setTalking) {
			window.ttsVisualizerState.setTalking();
		  }
		  if (window.MusicManager) {
			window.MusicManager.duck();
		  }
		  // AI Uzman modülüne TTS başladığını bildir (yarış durumu önleme)
		  try { Shiny.setInputValue('tts_is_playing', true, { priority: 'event' }); } catch(e) {}
		};

      audio.onpause = function() {
        if (!audio.ended && window.ttsVisualizerState && window.ttsVisualizerState.setPaused) {
          window.ttsVisualizerState.setPaused();
        }
      };

		audio.onended = function() {
		  window.mergenTTS.isPlaying = false;
		  if (window.mergenTTS.queue.length === 0) {
			if (window.ttsVisualizerState && window.ttsVisualizerState.setIdle) {
			  window.ttsVisualizerState.setIdle();
			}
			if (window.MusicManager) {
			  window.MusicManager.unduck();
			}
			// AI Uzman modülüne TTS bittiğini bildir
			try { Shiny.setInputValue('tts_is_playing', false, { priority: 'event' }); } catch(e) {}
		  }
		  processTTSQueue();
		};

      audio.onerror = function(e) {
        console.warn("[MERGEN TTS] Ses hatası:", e);
        window.mergenTTS.isPlaying = false;
        const kuyrukBos = window.mergenTTS.queue.length === 0;
        if (kuyrukBos && window.ttsVisualizerState && window.ttsVisualizerState.setIdle) {
          window.ttsVisualizerState.setIdle();
        }
        if (kuyrukBos && window.MusicManager) {
          window.MusicManager.unduck();
        }
        if (kuyrukBos) {
          try { Shiny.setInputValue('tts_is_playing', false, { priority: 'event' }); } catch(e) {}
        }
        processTTSQueue();
      };

      const playPromise = audio.play();
      if (playPromise !== undefined) {
        playPromise.then(() => {
          console.log("[MERGEN TTS] Parça oynatılıyor", item.index);
        }).catch(error => {
          console.warn("[MERGEN TTS] Otomatik oynatma engellendi:", error);
          window.mergenTTS.isPlaying = false;
          const kuyrukBos = window.mergenTTS.queue.length === 0;
          if (kuyrukBos && window.ttsVisualizerState && window.ttsVisualizerState.setIdle) {
            window.ttsVisualizerState.setIdle();
          }
          if (kuyrukBos && window.MusicManager) {
            window.MusicManager.unduck();
          }
          if (kuyrukBos) {
            try { Shiny.setInputValue('tts_is_playing', false, { priority: 'event' }); } catch(e) {}
          }
          processTTSQueue();
        });
      }
    } catch (e) {
      console.error("[MERGEN TTS] İstisna:", e);
      window.mergenTTS.isPlaying = false;
      if (window.ttsVisualizerState && window.ttsVisualizerState.setIdle) {
        window.ttsVisualizerState.setIdle();
      }
      processTTSQueue();
    }
  }
});