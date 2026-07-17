// www/js/speech_controller.js
// Paylaşılan konuşma denetleyicisi: sunucu tarafından verilen tekdüze artan
// konuşma token'larının istemci kaydı (bayat istek koruması), sınırlı statik
// varlık ön-yükleme ve chunked_pcm modunda Web Audio PCM kuyruğu oynatıcısı.
// Altyazı/görselleştirici yaşam döngüsü AIExpertManager'da kalır; bu dosya
// taşıma (transport) ve token sahipliği katmanıdır.

(function(window, document) {
  'use strict';

  // --- Token kaydı: sunucu token'ları tekdüze artar ---
  var MergenSpeech = {
    state: {
      currentToken: 0,      // Kabul edilen en yüksek token
      stoppedThrough: 0     // Bu ve altındaki token'lar durdurulmuş sayılır
    },

    // Gelen mesaj token'ını değerlendir: bayatsa reddet, yeniyse kabul et.
    // token verilmemişse (eski/dinamik yol) mevcut davranış korunur.
    accept: function(token) {
      if (token === undefined || token === null) return true;
      var t = Number(token);
      if (!isFinite(t)) return true;
      if (t <= this.state.stoppedThrough) return false;
      if (t < this.state.currentToken) return false;
      this.state.currentToken = t;
      return true;
    },

    // Token hâlâ güncel mi? (parça kuyruğu için; ilerletme yapmaz)
    isCurrent: function(token) {
      if (token === undefined || token === null) return true;
      var t = Number(token);
      if (!isFinite(t)) return true;
      return t === this.state.currentToken && t > this.state.stoppedThrough;
    },

    // Aktif konuşma durduruldu: mevcut token ve altı geçersizleşir.
    markStopped: function() {
      if (this.state.currentToken > this.state.stoppedThrough) {
        this.state.stoppedThrough = this.state.currentToken;
      }
    }
  };

  // --- Sınırlı statik varlık ön-yükleme (HTTP önbelleği ısıtma) ---
  var prefetched = {};
  var prefetchOrder = [];
  var PREFETCH_MAX = 12;

  function prefetchUrls(urls) {
    if (!urls || !urls.length) return;
    for (var i = 0; i < urls.length; i++) {
      var url = String(urls[i] || '');
      if (!url || prefetched[url]) continue;

      prefetched[url] = true;
      prefetchOrder.push(url);
      if (prefetchOrder.length > PREFETCH_MAX) {
        delete prefetched[prefetchOrder.shift()];
      }

      try {
        var audio = new Audio();
        audio.preload = 'auto';
        audio.src = url;
        // Öğe referansı tutulmaz; tarayıcı HTTP önbelleği ısınır, canlı
        // decoder bırakılmaz (startup medya ısıtma desenine uygun).
        audio.load();
      } catch (e) { /* yoksay */ }
    }
  }

  // --- Web Audio PCM kuyruğu oynatıcısı (gerçek akış) ---
  var pcm = {
    ctx: null,
    streamId: null,
    sampleRate: 16000,
    channels: 1,
    bitsPerSample: 16,
    nextStartTime: 0,
    endReceived: false,
    scheduled: [],
    playingNotified: false,
    headerSkipped: false,
    headerBuf: null,       // RIFF/olmayan kararı verilene kadar biriken baştaki baytlar
    carry: null,           // Kareye hizalanmayan artık baytlar sonraki parçaya taşınır
    pending: [],           // AudioContext 'running' olana kadar bekleyen ham PCM parçaları
    resuming: false,       // resume() çağrıldı, .then/.catch bekleniyor
    drainTimer: null
  };

  function pcmReset() {
    for (var i = 0; i < pcm.scheduled.length; i++) {
      try { pcm.scheduled[i].stop(); } catch (e) { /* yoksay */ }
    }
    pcm.scheduled = [];
    if (pcm.drainTimer) { clearTimeout(pcm.drainTimer); pcm.drainTimer = null; }
    pcm.streamId = null;
    pcm.nextStartTime = 0;
    pcm.endReceived = false;
    pcm.playingNotified = false;
    pcm.headerSkipped = false;
    pcm.headerBuf = null;
    pcm.carry = null;
    pcm.pending = [];
  }

  // Bağlam 'running' değilse (askıya alınmış/kullanıcı etkileşimi bekliyor)
  // parçayı zamanlamak yerine kuyruğa al; devam edince (veya zaten
  // çalışıyorsa) sırayla zamanla. Bu, source.start()'un askıda bir bağlamda
  // sessizce "asılı kalmasını" (zaman ilerlemez, onended asla ateşlenmez,
  // görselleştirici/müzik kısma ve tts_is_playing durumu takılı kalır) önler.
  function pcmEnqueueOrSchedule(bytes) {
    if (pcm.ctx && pcm.ctx.state === 'running' && !pcm.pending.length) {
      pcmScheduleChunk(bytes);
      return;
    }
    pcm.pending.push(bytes);
    pcmEnsureContextRunning();
  }

  function pcmFlushPending() {
    if (!pcm.pending.length) return;
    var queued = pcm.pending;
    pcm.pending = [];
    for (var i = 0; i < queued.length; i++) {
      pcmScheduleChunk(queued[i]);
    }
  }

  function pcmEnsureContextRunning() {
    if (!pcm.ctx) return;
    if (pcm.ctx.state === 'running') { pcmFlushPending(); return; }
    if (pcm.resuming) return;

    pcm.resuming = true;
    var expectedStreamId = pcm.streamId;
    pcm.ctx.resume().then(function() {
      pcm.resuming = false;
      // Bu arada akış değişmiş/durdurulmuş olabilir; bayat sonucu yoksay.
      if (pcm.streamId !== expectedStreamId) return;
      pcmFlushPending();
    }).catch(function(e) {
      pcm.resuming = false;
      console.warn('[SPEECH] AudioContext devam ettirilemedi (kullanıcı etkileşimi gerekebilir):', e);
      // Sesli oynatma mümkün değil: bekleyen parçaları at, akışı temizle.
      pcm.pending = [];
      if (pcm.streamId === expectedStreamId) MergenSpeech.pcmStop();
    });
  }

  function pcmNotifyPlaying(isPlaying) {
    try {
      if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
        Shiny.setInputValue('tts_is_playing', !!isPlaying, { priority: 'event' });
      }
    } catch (e) { /* yoksay */ }
  }

  function pcmOnFirstPlayback() {
    if (pcm.playingNotified) return;
    pcm.playingNotified = true;

    // Görselleştirici ve müzik kısma yalnızca GERÇEK oynatma başlarken
    if (window.ttsVisualizerState && window.ttsVisualizerState.setTalking) {
      window.ttsVisualizerState.setTalking();
    }
    if (window.MusicManager && typeof window.MusicManager.duck === 'function') {
      window.MusicManager.duck('tts');
    }
    pcmNotifyPlaying(true);
  }

  function pcmFinish(streamId, notifyServer) {
    var wasActive = pcm.streamId === streamId && pcm.playingNotified;
    pcmReset();

    if (window.ttsVisualizerState && window.ttsVisualizerState.setIdle) {
      window.ttsVisualizerState.setIdle();
    }
    if (window.MusicManager && typeof window.MusicManager.unduck === 'function') {
      window.MusicManager.unduck('tts');
    }
    if (wasActive) pcmNotifyPlaying(false);

    if (notifyServer && typeof Shiny !== 'undefined' && Shiny.setInputValue) {
      Shiny.setInputValue('speech_pcm_drained', {
        streamId: streamId, at: Date.now()
      }, { priority: 'event' });
    }
  }

  function base64ToBytes(b64) {
    var bin = atob(b64);
    var bytes = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return bytes;
  }

  function pcmScheduleChunk(bytes) {
    if (!pcm.ctx) return;

    // İlk parça(lar) WAV başlığıyla gelirse (RIFF) 44 baytlık başlığı atla.
    // Sunucu pompası ilk parçayı 44 bayttan KISA gönderebilir (parça boyutu
    // sunucu tarafında dosya büyüme hızına bağlıdır); bu durumda RIFF
    // kararını HEMEN vermek (ve headerSkipped'i erken kilitlemek) başlığın
    // geri kalanının PCM örneği olarak çözülmesine ve tüm akışın kalıcı
    // biçimde yanlış bayt sınırında bozulmasına yol açardı. Bu yüzden karar
    // verilene kadar (>= 44 bayt birikene kadar) baytlar bir arabellekte
    // tutulur; hiçbir şey erken çözülmez/zamanlanmaz.
    if (!pcm.headerSkipped) {
      if (pcm.headerBuf && pcm.headerBuf.length) {
        var headerMerged = new Uint8Array(pcm.headerBuf.length + bytes.length);
        headerMerged.set(pcm.headerBuf, 0);
        headerMerged.set(bytes, pcm.headerBuf.length);
        bytes = headerMerged;
        pcm.headerBuf = null;
      }

      if (bytes.length < 44) {
        pcm.headerBuf = bytes;
        return;
      }

      pcm.headerSkipped = true;
      if (bytes[0] === 0x52 && bytes[1] === 0x49 &&
          bytes[2] === 0x46 && bytes[3] === 0x46) {
        bytes = bytes.subarray(44);
      }
    }
    // Önceki parçadan taşınan (tam kareye tamamlanmayan) baytları öne ekle.
    // Sunucu pompası bayt sınırını 16-bit örneğe/kanal karesine hizalamayabilir;
    // artık baytlar sonraki parçaya taşınmazsa tek bir tek bayt bile sonraki
    // tüm örnekleri yanlış sınırda çözer ve akış boyunca sesi bozar.
    if (pcm.carry && pcm.carry.length) {
      var merged = new Uint8Array(pcm.carry.length + bytes.length);
      merged.set(pcm.carry, 0);
      merged.set(bytes, pcm.carry.length);
      bytes = merged;
      pcm.carry = null;
    }

    var bytesPerFrame = pcm.channels * 2;   // 16-bit örnek * kanal sayısı
    var frameCount = Math.floor(bytes.length / bytesPerFrame);
    var usableBytes = frameCount * bytesPerFrame;

    // Tam kareye tamamlanmayan kalan baytları sonraki parça için sakla (kopya)
    if (usableBytes < bytes.length) {
      pcm.carry = bytes.slice(usableBytes);
    }
    if (frameCount < 1) return;

    // 16-bit little-endian PCM -> Float32 (yalnızca tam kareler)
    var sampleCount = frameCount * pcm.channels;
    var view = new DataView(bytes.buffer, bytes.byteOffset, usableBytes);
    var floats = new Float32Array(sampleCount);
    for (var i = 0; i < sampleCount; i++) {
      floats[i] = view.getInt16(i * 2, true) / 32768;
    }

    var buffer = pcm.ctx.createBuffer(pcm.channels, frameCount, pcm.sampleRate);
    for (var ch = 0; ch < pcm.channels; ch++) {
      var channelData = buffer.getChannelData(ch);
      for (var f = 0; f < frameCount; f++) {
        channelData[f] = floats[f * pcm.channels + ch];
      }
    }

    var source = pcm.ctx.createBufferSource();
    source.buffer = buffer;
    source.connect(pcm.ctx.destination);

    var now = pcm.ctx.currentTime;
    if (pcm.nextStartTime < now + 0.03) pcm.nextStartTime = now + 0.03;

    source.onended = function() {
      var idx = pcm.scheduled.indexOf(source);
      if (idx >= 0) pcm.scheduled.splice(idx, 1);
      // Tamamlanma: akış sonu geldi VE zamanlanmış kuyruk gerçekten boşaldı VE
      // AudioContext devam etmesini bekleyen (henüz zamanlanmamış) parça yok.
      if (pcm.endReceived && pcm.scheduled.length === 0 && !pcm.pending.length && pcm.streamId) {
        pcmFinish(pcm.streamId, true);
      }
    };

    source.start(pcm.nextStartTime);
    pcm.nextStartTime += buffer.duration;
    pcm.scheduled.push(source);
    pcmOnFirstPlayback();
  }

  MergenSpeech.pcmStop = function() {
    if (!pcm.streamId) return;
    var streamId = pcm.streamId;
    try {
      if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
        Shiny.setInputValue('speech_pcm_stopped', {
          streamId: streamId, at: Date.now()
        }, { priority: 'event' });
      }
    } catch (e) { /* yoksay */ }
    pcmFinish(streamId, false);
  };

  MergenSpeech.pcmIsActive = function() {
    return !!pcm.streamId;
  };

  // --- Shiny mesaj işleyicileri ---
  // Ertelenmiş (defer) yükleme ve dinamik ekleme senaryolarında da güvenli:
  // DOM hazırsa hemen bağla, değilse DOMContentLoaded bekle.
  function bindSpeechHandlers() {
    {
      if (typeof Shiny === 'undefined' || !Shiny.addCustomMessageHandler) return;

      Shiny.addCustomMessageHandler('speechPrefetch', function(data) {
        prefetchUrls((data && data.urls) || []);
      });

      Shiny.addCustomMessageHandler('speechPcmStreamStart', function(data) {
        if (!data || !data.streamId) return;

        // Yeni akış eski akışı değiştirir
        if (pcm.streamId) pcmFinish(pcm.streamId, false);

        try {
          if (!pcm.ctx) {
            var Ctx = window.AudioContext || window.webkitAudioContext;
            pcm.ctx = new Ctx();
          }
        } catch (e) {
          console.warn('[SPEECH] AudioContext açılamadı:', e);
          return;
        }

        pcm.streamId = String(data.streamId);
        pcm.sampleRate = Number(data.sampleRate) || 16000;
        pcm.channels = Number(data.channels) || 1;
        pcm.bitsPerSample = Number(data.bitsPerSample) || 16;
        pcm.nextStartTime = 0;
        pcm.endReceived = false;
        pcm.playingNotified = false;
        pcm.headerSkipped = false;
        pcm.pending = [];

        // Askıya alınmışsa (kullanıcı etkileşimi bekliyor) devam ettirmeyi
        // hemen başlat; gelecek parçalar 'running' olana kadar kuyruklanır.
        pcmEnsureContextRunning();
      });

      Shiny.addCustomMessageHandler('speechPcmStreamChunk', function(data) {
        if (!data || String(data.streamId) !== pcm.streamId) return;
        try {
          pcmEnqueueOrSchedule(base64ToBytes(String(data.b64 || '')));
        } catch (e) {
          console.warn('[SPEECH] PCM parçası çözülemedi:', e);
        }
      });

      Shiny.addCustomMessageHandler('speechPcmStreamEnd', function(data) {
        if (!data || String(data.streamId) !== pcm.streamId) return;

        // Akış, 44 bayttan kısa toplam yanıtla bitebilir: başlık kararı hiç
        // verilmemiş olabilir. Kalan baytları PCM olarak işle (başlıksız
        // sayılır) ki sessizce kaybolmasınlar.
        if (pcm.headerBuf && pcm.headerBuf.length) {
          var leftoverHeaderBytes = pcm.headerBuf;
          pcm.headerBuf = null;
          pcm.headerSkipped = true;
          pcmEnqueueOrSchedule(leftoverHeaderBytes);
        }

        pcm.endReceived = true;
        // Hiç parça oynatılmadıysa/zamanlanmış kuyruk boşsa VE AudioContext
        // devam etmesini bekleyen kuyruklanmış parça da yoksa hemen bitir.
        if (pcm.scheduled.length === 0 && !pcm.pending.length) {
          pcmFinish(pcm.streamId, true);
        }
      });
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bindSpeechHandlers);
  } else {
    bindSpeechHandlers();
  }

  window.MergenSpeech = MergenSpeech;
})(window, document);
