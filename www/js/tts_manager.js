// www/js/tts_manager.js

$(document).ready(function() {
  // -------------------------------------------------
  // TTS (Metin Okuma) Kuyruk Sistemi
  // -------------------------------------------------
  window.mergenTTS = {
    queue: [],
    isPlaying: false,
    currentAudio: null,
    
    // Okumayı tamamen durdurur, kuyruğu temizler ve görselleştiriciyi sıfırlar
    stop: function() {
      // Çalan ses varsa durdur
      if (this.currentAudio) {
        this.currentAudio.pause();
        this.currentAudio.currentTime = 0;
        this.currentAudio = null;
      }
      
      // Kuyruğu ve durumu sıfırla
      this.queue = [];
      this.isPlaying = false;
      
      // Görselleştiriciyi (varsa) bekleme moduna al
      if (window.ttsVisualizerState && window.ttsVisualizerState.setIdle) {
        window.ttsVisualizerState.setIdle();
      }

      // Müzik yöneticisi varsa sesi tekrar aç (unduck)
      if (window.MusicManager) {
        window.MusicManager.unduck();
      }
    }
  };

  // Shiny'den gelen 'playAudioMessage' mesajını dinler
  Shiny.addCustomMessageHandler('playAudioMessage', function(message) {
    if (!message || !message.src) return;

    // Gelen parçayı kuyruğa ekle (sıra numarası/index ile)
    window.mergenTTS.queue.push({
      id: message.id,
      src: message.src,
      index: message.chunkIndex || 0
    });

    // Doğru cümle sırasını sağlamak için kuyruğu indekse göre sırala (0, 1, 2...)
    window.mergenTTS.queue.sort((a, b) => a.index - b.index);

    // Kuyruğu işlemeye başla
    processTTSQueue();
  });

  // Kuyruktaki sesleri sırayla işleyen fonksiyon
  function processTTSQueue() {
    // Halihazırda çalıyorsa veya kuyruk boşsa işlem yapma
    if (window.mergenTTS.isPlaying || window.mergenTTS.queue.length === 0) return;

    // Kuyruğun başındaki öğeyi al
    const item = window.mergenTTS.queue.shift();
    window.mergenTTS.isPlaying = true;

    // Görselleştiriciyi konuşma moduna al
    if (window.ttsVisualizerState && window.ttsVisualizerState.setTalking) {
      window.ttsVisualizerState.setTalking();
    }

    try {
      window.mergenTTS.currentAudio = new Audio(item.src);
      const audio = window.mergenTTS.currentAudio;
      audio.volume = 1.0;

      // Oynatma başladığında tetiklenir
      audio.onplay = function() {
        if (window.ttsVisualizerState && window.ttsVisualizerState.setTalking) {
          window.ttsVisualizerState.setTalking();
        }
        // Arka plan müziğini kıs (duck)
        if (window.MusicManager) {
          window.MusicManager.duck();
        }
      };

      // Duraklatıldığında tetiklenir
      audio.onpause = function() {
        // Eğer ses bitmediyse ve duraklatıldıysa görselleştiriciyi duraklat
        if (!audio.ended && window.ttsVisualizerState && window.ttsVisualizerState.setPaused) {
          window.ttsVisualizerState.setPaused();
        }
      };

      // Oynatma bittiğinde tetiklenir
      audio.onended = function() {
        window.mergenTTS.isPlaying = false;
        
        // Eğer kuyruk tamamen bittiyse
        if (window.mergenTTS.queue.length === 0) {
          if (window.ttsVisualizerState && window.ttsVisualizerState.setIdle) {
            window.ttsVisualizerState.setIdle();
          }
          // Müziğin sesini tekrar aç
          if (window.MusicManager) {
            window.MusicManager.unduck();
          }
        }
        // Bir sonraki parçaya geç
        processTTSQueue();
      };

      // Hata durumunda tetiklenir
      audio.onerror = function(e) {
        console.warn("[MERGEN TTS] Ses hatası:", e);
        window.mergenTTS.isPlaying = false;
        
        if (window.ttsVisualizerState && window.ttsVisualizerState.setIdle) {
          window.ttsVisualizerState.setIdle();
        }

        // Hata oldu ve kuyruk boşaldıysa müziği düzelt
        if (window.mergenTTS.queue.length === 0 && window.MusicManager) {
            window.MusicManager.unduck();
        }

        processTTSQueue();
      };

      // Sesi oynatmaya çalış
      const playPromise = audio.play();
      if (playPromise !== undefined) {
        playPromise.then(() => {
          console.log("[MERGEN TTS] Parça oynatılıyor, İndeks:", item.index);
        }).catch(error => {
          console.warn("[MERGEN TTS] Otomatik oynatma engellendi veya hata:", error);
          window.mergenTTS.isPlaying = false;
          
          if (window.ttsVisualizerState && window.ttsVisualizerState.setIdle) {
            window.ttsVisualizerState.setIdle();
          }

          // Hata oldu ve kuyruk boşaldıysa müziği düzelt
          if (window.mergenTTS.queue.length === 0 && window.MusicManager) {
            window.MusicManager.unduck();
          }

          processTTSQueue();
        });
      }
    } catch (e) {
      console.error("[MERGEN TTS] İstisna oluştu:", e);
      window.mergenTTS.isPlaying = false;
      
      if (window.ttsVisualizerState && window.ttsVisualizerState.setIdle) {
        window.ttsVisualizerState.setIdle();
      }

      // Hata oldu ve kuyruk boşaldıysa müziği düzelt
      if (window.mergenTTS.queue.length === 0 && window.MusicManager) {
        window.MusicManager.unduck();
      }

      processTTSQueue();
    }
  }
});