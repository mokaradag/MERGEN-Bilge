// www/js/stt_client.js

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
    
    // Config
    const CHUNK_INTERVAL_MS = 3000;
    // SESSİZLİK EŞİĞİ (Gelişmiş Halüsinasyon Engelleyici)
    // Eğer 3 saniyelik dilimdeki maksimum ses seviyesi bu değerin altındaysa sunucuya gönderilmez.
    // 0.02 - 0.03 arası iyi bir değerdir. "Evet." gibi fısıltıları eler.
    const SILENCE_THRESHOLD = 0.025; 
    
    let isRecordingActive = false;
    let chunkTimer = null;
    let audioChunks = [];
    let currentSegmentMaxRMS = 0; // Segment içindeki max ses
    
    // Visualizer Değişkenleri
    let strands = [];
    let visTime = 0;
    let baseColor = '#7C4DFF';
    
    function init(config) {
        const { canvasId, timerId, dbId, nsPrefix, accentColor } = config;
        canvasElement = document.getElementById(canvasId);
        timerElement = document.getElementById(timerId);
        dbElement = document.getElementById(dbId);
        baseColor = accentColor || '#7C4DFF';
        
        if(!canvasElement) return;
        
        canvasCtx = canvasElement.getContext("2d");
        
        navigator.mediaDevices.getUserMedia({ audio: true })
            .then(audioStream => {
                stream = audioStream;
                startVisualizer(stream);
                
                isRecordingActive = true;
                startTime = Date.now();
                startTimer();
                startRecordingLoop(stream, nsPrefix);
            })
            .catch(err => {
                console.error("Microphone access denied:", err);
                alert("Mikrofona erişilemedi. Lütfen tarayıcı izinlerini kontrol edin.");
            });
    }
    
    // --- MODERN DALGA GÖRSELLEŞTİRİCİ ---
    // TTS modülündeki SonicPulse stilinin mikrofona uyarlanmış hali
    function generateStrands(count) {
        const s = [];
        for (let i = 0; i < count; i++) {
            s.push({
                phaseOffset: Math.random() * Math.PI * 2,
                frequency: 1 + Math.random() * 2, // Sıklık
                speed: 0.1 + Math.random() * 0.4, // Hareket hızı
                amplitude: 0.5 + Math.random() * 0.5,
                alpha: 0.3 + Math.random() * 0.5
            });
        }
        return s;
    }
    
    function hexToRgb(hex) {
        const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
        return result ? { r: parseInt(result[1], 16), g: parseInt(result[2], 16), b: parseInt(result[3], 16) } 
                      : { r: 124, g: 77, b: 255 };
    }
    
    function startVisualizer(stream) {
        if (!audioContext) {
            audioContext = new (window.AudioContext || window.webkitAudioContext)();
        }
        analyser = audioContext.createAnalyser();
        analyser.fftSize = 1024; 
        analyser.smoothingTimeConstant = 0.8;
        
        const source = audioContext.createMediaStreamSource(stream);
        source.connect(analyser);
        dataArray = new Uint8Array(analyser.frequencyBinCount);
        
        // 6 adet dalga çizgisi oluştur
        strands = generateStrands(6); 
        draw();
    }
    
    function draw() {
        if (!canvasElement) return;
        animationId = requestAnimationFrame(draw);
        
        analyser.getByteTimeDomainData(dataArray);
        
        // 1. RMS (Ses Gücü) Hesapla
        let sumSquares = 0;
        for (let i = 0; i < dataArray.length; i++) {
            const normalized = (dataArray[i] - 128) / 128.0;
            sumSquares += normalized * normalized;
        }
        const rms = Math.sqrt(sumSquares / dataArray.length);
        
        // Kayıt mantığı için max RMS'i güncelle (Sessizlik filtresi için)
        if (isRecordingActive) {
            currentSegmentMaxRMS = Math.max(currentSegmentMaxRMS, rms);
        }
        
        // dB Göstergesi
        if (dbElement && rms > 0.001) {
            const db = 20 * Math.log10(rms);
            // -60dB alt limit
            dbElement.innerText = Math.max(-60, Math.floor(db * 2)) + " dB";
        } else if (dbElement) {
             dbElement.innerText = "-Inf dB";
        }

        // 2. Çizim
        const width = canvasElement.width;
        const height = canvasElement.height;
        const centerY = height / 2;
        
        canvasCtx.clearRect(0, 0, width, height);
        
        // Sinyal genliğini görselleştirme için yükselt
        // Konuşurken RMS genellikle 0.1 - 0.3 arasıdır, bunu ekranda büyütmek gerekir.
        const globalAmp = rms * 5.0; 
        visTime += 0.05;
        
        const rgb = hexToRgb(baseColor);
        canvasCtx.lineCap = 'round';
        canvasCtx.lineJoin = 'round';
        
        strands.forEach((strand) => {
             canvasCtx.beginPath();
             const colorStr = `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${strand.alpha})`;
             
             let isFirst = true;
             // Çözünürlüğü düşürerek performansı artır (x += 8)
             for (let x = 0; x <= width; x += 8) {
                 const nx = (x / width) * 2 - 1; 
                 // Kenarları yumuşat (pencereleme)
                 const window = Math.pow(1 - Math.pow(nx, 2), 2); 
                 
                 // Dalga formülü
                 const wave = Math.sin((x * 0.015 * strand.frequency) + (visTime * strand.speed) + strand.phaseOffset);
                 
                 // Yüksek seslerde jitter (titreme) efekti ekle
                 const jitter = (rms > 0.1) ? (Math.random() - 0.5) * 5 : 0;
                 
                 const y = centerY + (wave * (height * 0.35) * strand.amplitude * globalAmp * window) + jitter;
                 
                 if (isFirst) { canvasCtx.moveTo(x, y); isFirst = false; }
                 else { canvasCtx.lineTo(x, y); }
             }
             canvasCtx.strokeStyle = colorStr;
             canvasCtx.lineWidth = 2;
             canvasCtx.stroke();
        });
    }
    
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
        currentSegmentMaxRMS = 0; // Yeni segment için sıfırla

        mediaRecorder.addEventListener('dataavailable', event => {
            if (event.data.size > 0) audioChunks.push(event.data);
        });

        mediaRecorder.addEventListener('stop', () => {
            // --- SESSİZLİK KAPISI (SILENCE GATE) ---
            // Eğer segment boyunca tespit edilen en yüksek ses eşiğin altındaysa, 
            // veri sessizdir ve sunucuya gönderilmez.
            if (currentSegmentMaxRMS >= SILENCE_THRESHOLD && audioChunks.length > 0) {
                const blob = new Blob(audioChunks, { type: 'audio/webm' });
                if (blob.size > 0) {
                    sendChunkToShiny(blob, nsPrefix);
                }
            } else {
                // Sessizlik nedeniyle atlandı (Debug için konsola yazılabilir)
                // console.log("Sessizlik filtresi: Paket atlandı.");
            }
            
            // Eğer kayıt hala aktifse döngüyü yeniden başlat
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
        if (chunkTimer) clearTimeout(chunkTimer);
        // Eğer durdur butonuna basıldıysa mevcut kaydı durdur ama gönderme (kilit R tarafında da var)
        if (mediaRecorder && mediaRecorder.state === "recording") {
            mediaRecorder.stop();
        }
    }
    
    function startRecording(nsPrefix) {
        if (!isRecordingActive && stream) {
            isRecordingActive = true;
            // Zamanlayıcıyı sıfırlama, devam et
            startRecordingLoop(stream, nsPrefix);
        }
    }
    
    function stopAndCleanup(nsPrefix) {
        isRecordingActive = false;
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