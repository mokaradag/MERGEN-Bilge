// www/js/stt_client.js


// Medya tanılama logu: üretimde sessiz; localStorage.MERGEN_DEBUG_MEDIA = "1"
// ile açılır. Uyarı/hata logları (console.warn/error) her zaman açık kalır.
var mergenMediaDbg = window.__mergenMediaDbg = window.__mergenMediaDbg || function() {
  try {
    if (window.localStorage && localStorage.getItem('MERGEN_DEBUG_MEDIA') === '1' && window.console) {
      console.log.apply(console, arguments);
    }
  } catch (e) {}
};

window.STT_Client = (function() {
    let mediaRecorder = null;
    let audioContext = null;
    let stream = null;
    let animationId = null;
    let analyser = null;
    let dataArray = null;
    let canvasCtx = null;
    let canvasElement = null;
    
    // UI Elements
    let timerElement = null;
    let dbElement = null;
    let startTime = 0;
    let timerInterval = null;
    let accentColor = '#7C4DFF';
    
    // Config
    const CHUNK_INTERVAL_MS = 3000;
    // Sessizlik eşiği biraz düşürüldü: kısa/alçak sesli "merhaba" gibi ifadeler
    // eskiden istemci tarafında elenip hiç gönderilmiyordu (issue #2).
    const SILENCE_THRESHOLD = 0.02;

    function restoreMusicAfterSTT() {
        if (window.MusicManager &&
            typeof window.MusicManager.unduckAfterSTT === 'function') {
            window.MusicManager.unduckAfterSTT();
        }
    }
    
    let isRecordingActive = false;
    let chunkTimer = null;
    let audioChunks = [];
    let currentSegmentMaxRMS = 0;
    let lifecycleToken = 0;
	
    let modalCleanupElement = null;

    function setSttModalInactive() {
        try {
            if (window.Shiny && typeof window.Shiny.setInputValue === 'function') {
                window.Shiny.setInputValue('stt_modal_active', false, { priority: 'event' });
            }
        } catch (e) {}
    }

    function unbindModalHiddenCleanup() {
        if (modalCleanupElement && window.jQuery) {
            try {
                window.jQuery(modalCleanupElement).off('hidden.bs.modal.mergenSttCleanup');
            } catch (e) {}
        }
        modalCleanupElement = null;
    }

    function bindModalHiddenCleanup(nsPrefix) {
        unbindModalHiddenCleanup();

        if (!canvasElement || !window.jQuery) return;

        const modal = canvasElement.closest('.modal');
        if (!modal) return;

        modalCleanupElement = modal;

        window.jQuery(modal)
            .off('hidden.bs.modal.mergenSttCleanup')
            .one('hidden.bs.modal.mergenSttCleanup', function() {
                mergenMediaDbg('[STT] Modal kapanış fallback temizliği çalıştı');
                try {
                    stopAndCleanup(nsPrefix || '');
                } catch (e) {
                    console.warn('[STT] Modal kapanış temizliği başarısız:', e);
                    restoreMusicAfterSTT();
                }
                setSttModalInactive();
            });
    }
    
    // --- SONIC PULSE VISUALIZER STATE ---
    const MODES = {
        IDLE: 'IDLE',
        LISTENING: 'LISTENING'
    };
    
    // Modern colors (Blue/Purple/Pink gradients) independent of character theme
    const VIS_CONFIGS = {
        LISTENING:  { colors: ['#22d3ee', '#3b82f6', '#06b6d4'], speed: 1.2, ampMult: 1.0, tension: 0.8, glow: 15, particleRate: 0.2 },
        IDLE:       { colors: ['#475569', '#64748b', '#94a3b8'], speed: 0.4, ampMult: 0.2, tension: 0.5, glow: 0, particleRate: 0 }
    };

    let currentMode = MODES.IDLE;
    let width = 0;
    let height = 0;
    let time = 0;
    let strands = [];
    let particles = [];
    let smoothedVolume = 0;
    let smoothedFreqs = new Array(64).fill(0);
    
	function init(config) {
		config = config || {};

		// Önceki bekleyen mikrofon isteğini ve kayıt oturumunu geçersiz kıl
		if (stream || mediaRecorder || audioContext || isRecordingActive) {
			stopAndCleanup(config.nsPrefix || '');
		}
		const token = ++lifecycleToken;

		// STT başlatılırken müziği tamamen sessize al - mikrofon paraziti önlenir
		if (window.MusicManager) {
			window.MusicManager.duckForSTT();
		}

		const { canvasId, timerId, dbId, nsPrefix } = config;
		if (!canvasId) {
			restoreMusicAfterSTT();
			return;
		}

		canvasElement = document.getElementById(canvasId);
		timerElement = timerId ? document.getElementById(timerId) : null;
        dbElement = dbId ? document.getElementById(dbId) : null;
        accentColor = config.accentColor || '#7C4DFF';
        
        // 1. Set Avatar Border Color Dynamically
        const avatarEl = document.querySelector('.stt-avatar');
        if (avatarEl) {
            avatarEl.style.borderColor = accentColor;
        }
        
        if(!canvasElement) {
            restoreMusicAfterSTT();
            return;
        }

        bindModalHiddenCleanup(nsPrefix || '');
        
        canvasCtx = canvasElement.getContext("2d");
        
        // Resize Handler
        window.addEventListener('resize', resizeCanvas);
        resizeCanvas();
        
        // Initialize Visualizer Elements
        strands = generateStrands(40);
        particles = [];
        
        // Start Microphone
        navigator.mediaDevices.getUserMedia({ audio: true })
            .then(audioStream => {
                if (token !== lifecycleToken || !canvasElement) {
                    audioStream.getTracks().forEach(track => track.stop());
                    return;
                }

                stream = audioStream;
                startVisualizer(stream);
                
                isRecordingActive = true;
                currentMode = MODES.LISTENING;
                
                startTime = Date.now();
                startTimer();
                startRecordingLoop(stream, nsPrefix);
                
                // Start Animation Loop
                draw(); 
            })
            .catch(err => {
                if (token !== lifecycleToken) return;

                console.warn("[STT] Mikrofon erişimi başlatılamadı:", err);
                isRecordingActive = false;
                currentMode = MODES.IDLE;
                restoreMusicAfterSTT();
                alert("Mikrofona erişilemedi. Lütfen tarayıcı izinlerini kontrol edin.");
            });
    }
    
    function resizeCanvas() {
        if (!canvasElement || !canvasElement.parentElement) return;
        const rect = canvasElement.parentElement.getBoundingClientRect();
        width = rect.width;
        height = rect.height;
        
        const dpr = window.devicePixelRatio || 1;
        canvasElement.width = width * dpr;
        canvasElement.height = height * dpr;
        if (canvasCtx.setTransform) {
            canvasCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
        } else {
            canvasCtx.scale(dpr, dpr);
        }
    }
    
    function generateStrands(count) {
        return Array.from({ length: count }).map((_, i) => ({
            phaseOffset: Math.random() * Math.PI * 2,
            frequency: 1 + Math.random() * 3,
            speed: 0.5 + Math.random() * 1.5,
            amplitude: 0.3 + Math.random() * 0.7,
            colorOffset: i / count,
        }));
    }
    
	function startVisualizer(stream) {
	  if (!audioContext) {
		audioContext = new (window.AudioContext || window.webkitAudioContext)();
	  }
	  analyser = audioContext.createAnalyser();
	  analyser.fftSize = 256;
	  analyser.smoothingTimeConstant = 0.85;

	  const source = audioContext.createMediaStreamSource(stream);
	  source.connect(analyser);
	  dataArray = new Uint8Array(analyser.frequencyBinCount);
	  // Not: Müzik zaten init() içinde duckForSTT() ile sessize alındı
	}
    
    function draw() {
        if (!canvasElement) return;
        animationId = requestAnimationFrame(draw);
        
        // --- DATA PROCESSING ---
        let vol = 0;
        if (analyser) {
            analyser.getByteFrequencyData(dataArray);
            
            // Calculate RMS
            let sum = 0;
            for(let i=0; i<dataArray.length; i++) sum += dataArray[i] * dataArray[i];
            const rms = Math.sqrt(sum / dataArray.length);
            
            // Normalize volume (0.0 to 1.0)
            vol = Math.min(rms / 128, 1.0);
            
            // Update recording logic
            if (isRecordingActive) {
                currentSegmentMaxRMS = Math.max(currentSegmentMaxRMS, (rms / 128.0));
            }

            // DB Display
            if (dbElement && vol > 0.001) {
                 const db = 20 * Math.log10(vol);
                 dbElement.innerText = Math.max(-60, Math.floor(db * 2)) + " dB";
            } else if (dbElement) {
                 dbElement.innerText = "-Inf dB";
            }
        }
        
        // --- ANIMATION STATE ---
        const config = CONFIGS[currentMode] || CONFIGS.IDLE;
        time += 0.01 * config.speed;
        
        smoothedVolume += (vol - smoothedVolume) * 0.1;
        const renderVol = Math.max(0.01, smoothedVolume);

        // Smooth Frequencies
        for(let i=0; i<64; i++) {
             const target = dataArray ? (dataArray[i] || 0) : 0;
             smoothedFreqs[i] += (target - smoothedFreqs[i]) * 0.15;
        }
        
        // --- DRAWING ---
        canvasCtx.clearRect(0, 0, width, height);
        canvasCtx.globalCompositeOperation = 'lighter';
        canvasCtx.lineCap = 'round';
        canvasCtx.lineJoin = 'round';
        
        const centerY = height / 2;
        
        // 1. Draw Strands
        strands.forEach((strand, idx) => {
             const freqIndex = idx % 20;
             const freqVal = (smoothedFreqs[freqIndex] || 0) / 255;

             // Color Cycling
             const colorTime = time * 0.2 + strand.colorOffset;
             const colorCycle = Math.floor(colorTime) % config.colors.length;
             const baseColor = config.colors[colorCycle];

             canvasCtx.beginPath();
             
             // Dynamic Amplitude
             const effectiveAmp = (height * 0.4) * config.ampMult * (0.5 + renderVol + freqVal) * strand.amplitude;
             
             let isFirst = true;
             // Reduce resolution slightly for performance
             for (let x = 0; x <= width; x += 5) {
                 const nx = (x / width) * 2 - 1; 
                 const window = Math.pow(1 - Math.pow(nx, 2), 2); // Hanning window
                 
                 const wave = Math.sin(
                   (x * 0.01 * strand.frequency * config.tension) +
                   (time * strand.speed) +
                   strand.phaseOffset
                 );
                 
                 // Add harmonic detail
                 const harmonic = Math.cos((x * 0.03) - (time * strand.speed * 1.5)) * 0.3;
                 
                 const y = centerY + (wave + harmonic) * effectiveAmp * window;
                 
                 if (isFirst) { canvasCtx.moveTo(x, y); isFirst = false; }
                 else { canvasCtx.lineTo(x, y); }
             }
             
             const opacity = Math.min(1, (renderVol * 0.8 + 0.2) * (1 - Math.abs(idx/strands.length - 0.5)));
             
             canvasCtx.strokeStyle = baseColor;
             canvasCtx.lineWidth = 1.5;
             canvasCtx.globalAlpha = opacity;
             canvasCtx.shadowBlur = config.glow;
             canvasCtx.shadowColor = baseColor;
             canvasCtx.stroke();
             canvasCtx.globalAlpha = 1.0;
             canvasCtx.shadowBlur = 0;
        });
        
        // 2. Particles
        if (Math.random() < config.particleRate * renderVol * 2) {
            particles.push({
               x: width / 2 + (Math.random() - 0.5) * width * 0.5,
               y: centerY + (Math.random() - 0.5) * 50,
               vx: (Math.random() - 0.5) * 2,
               vy: (Math.random() - 0.5) * 2,
               life: 1.0,
               size: Math.random() * 2 + 1,
               color: config.colors[Math.floor(Math.random() * config.colors.length)]
            });
        }
        
        particles.forEach((p, i) => {
            p.x += p.vx;
            p.y += p.vy;
            p.life -= 0.02;
            p.size *= 0.95;
            
            if(p.life <= 0) { particles.splice(i, 1); return; }
            
            canvasCtx.beginPath();
            canvasCtx.arc(p.x, p.y, p.size, 0, Math.PI*2);
            canvasCtx.fillStyle = p.color;
            canvasCtx.globalAlpha = p.life * renderVol;
            canvasCtx.fill();
        });
        canvasCtx.globalAlpha = 1.0;
    }
    
    // Config Alias
    const CONFIGS = VIS_CONFIGS;

    function startTimer() {
        if (timerInterval) clearInterval(timerInterval);
        timerInterval = setInterval(() => {
            if (!isRecordingActive) return;
            const diff = Math.floor((Date.now() - startTime) / 1000);
            const m = Math.floor(diff / 60).toString().padStart(2, '0');
            const s = (diff % 60).toString().padStart(2, '0');
            if (timerElement) timerElement.innerText = `${m}:${s}`;
        }, 1000);
    }
    
    function startRecordingLoop(stream, nsPrefix) {
        const options = { mimeType: 'audio/webm' };
        try {
            mediaRecorder = new MediaRecorder(stream, options);
        } catch (e) {
            mediaRecorder = new MediaRecorder(stream); 
        }

        audioChunks = [];
        currentSegmentMaxRMS = 0;

        mediaRecorder.addEventListener('dataavailable', event => {
            if (event.data.size > 0) audioChunks.push(event.data);
        });

        mediaRecorder.addEventListener('stop', () => {
            if (currentSegmentMaxRMS >= SILENCE_THRESHOLD && audioChunks.length > 0) {
                const blob = new Blob(audioChunks, { type: 'audio/webm' });
                if (blob.size > 0) {
                    sendChunkToShiny(blob, nsPrefix);
                }
            }
            if (isRecordingActive) {
                setTimeout(() => {
                    startRecordingLoop(stream, nsPrefix);
                }, 50);
            }
        });

        mediaRecorder.start();

        chunkTimer = setTimeout(() => {
            if (mediaRecorder && mediaRecorder.state === "recording") {
                mediaRecorder.stop();
            }
        }, CHUNK_INTERVAL_MS);
    }
    
    function sendChunkToShiny(blob, nsPrefix) {
        const reader = new FileReader();
        reader.readAsDataURL(blob);
        reader.onloadend = function() {
            const base64data = reader.result.split(',')[1];
            Shiny.setInputValue(nsPrefix + "-audio_chunk", base64data, { priority: "event" });
        };
    }
    
    function stopRecording(nsPrefix) {
        isRecordingActive = false;
        currentMode = MODES.IDLE;
        if (chunkTimer) clearTimeout(chunkTimer);
        if (mediaRecorder && mediaRecorder.state === "recording") {
            mediaRecorder.stop();
        }
    }
    
    function startRecording(nsPrefix) {
        if (!isRecordingActive && stream) {
            isRecordingActive = true;
            currentMode = MODES.LISTENING;
            startRecordingLoop(stream, nsPrefix);
        }
    }
    
		function stopAndCleanup(nsPrefix) {
			unbindModalHiddenCleanup();

			lifecycleToken++;
			isRecordingActive = false;
			currentMode = MODES.IDLE;
        if (chunkTimer) clearTimeout(chunkTimer);
        if (timerInterval) clearInterval(timerInterval);
        if (animationId) cancelAnimationFrame(animationId);
        
        if (mediaRecorder && mediaRecorder.state !== "inactive") mediaRecorder.stop();
        if (stream) stream.getTracks().forEach(track => track.stop());
        if (audioContext) {
            audioContext.close();
            audioContext = null;
        }
        
		mediaRecorder = null;
		stream = null;
		canvasElement = null;
		window.removeEventListener('resize', resizeCanvas);

		// STT bitti: müziği yumuşak geçişle normale döndür
		restoreMusicAfterSTT();
    }
    
    return {
        init: init,
        startRecording: startRecording,
        stopRecording: stopRecording,
        stopAndCleanup: stopAndCleanup
    };
})();

Shiny.addCustomMessageHandler('initSTT', function(msg) {
    window.STT_Client.init(msg);
});