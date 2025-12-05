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
    
    // Config
    const CHUNK_INTERVAL_MS = 3000;
    let isRecordingActive = false;
    let chunkTimer = null;
    
    function init(config) {
        const { canvasId, nsPrefix } = config;
        canvasElement = document.getElementById(canvasId);
        if(!canvasElement) return;
        
        canvasCtx = canvasElement.getContext("2d");
        
        navigator.mediaDevices.getUserMedia({ audio: true })
            .then(audioStream => {
                stream = audioStream;
                startVisualizer(stream);
                
                isRecordingActive = true;
                startRecordingLoop(stream, nsPrefix);
            })
            .catch(err => {
                console.error("Microphone access denied:", err);
                alert("Mikrofona erişilemedi. Lütfen izinleri kontrol edin.");
            });
    }
    
    function startVisualizer(stream) {
        if (!audioContext) {
            audioContext = new (window.AudioContext || window.webkitAudioContext)();
        }
        analyser = audioContext.createAnalyser();
        analyser.fftSize = 2048; 
        const source = audioContext.createMediaStreamSource(stream);
        source.connect(analyser);
        dataArray = new Uint8Array(analyser.frequencyBinCount);
        draw();
    }
    
    function draw() {
        if (!canvasElement) return;
        animationId = requestAnimationFrame(draw);
        analyser.getByteTimeDomainData(dataArray);
        
        const width = canvasElement.width;
        const height = canvasElement.height;
        
        canvasCtx.fillStyle = '#1e1e1e'; 
        canvasCtx.fillRect(0, 0, width, height);
        
        canvasCtx.lineWidth = 2;
        const gradient = canvasCtx.createLinearGradient(0, 0, width, 0);
        gradient.addColorStop(0, '#7C4DFF'); 
        gradient.addColorStop(0.5, '#2F6DF6'); 
        gradient.addColorStop(1, '#12A97B'); 
        
        canvasCtx.strokeStyle = gradient;
        canvasCtx.beginPath();
        
        const sliceWidth = width * 1.0 / dataArray.length;
        let x = 0;
        
        for (let i = 0; i < dataArray.length; i++) {
            const v = dataArray[i] / 128.0;
            const y = v * height / 2;
            if (i === 0) canvasCtx.moveTo(x, y);
            else canvasCtx.lineTo(x, y);
            x += sliceWidth;
        }
        canvasCtx.lineTo(width, height / 2);
        canvasCtx.stroke();
    }
    
    function startRecordingLoop(stream, nsPrefix) {
        const mimeType = MediaRecorder.isTypeSupported("audio/webm") ? "audio/webm" : "audio/ogg";
        mediaRecorder = new MediaRecorder(stream, { mimeType });
        let audioChunks = [];

        mediaRecorder.ondataavailable = (event) => {
            if (event.data.size > 0) audioChunks.push(event.data);
        };

        mediaRecorder.onstop = () => {
            if (audioChunks.length > 0) {
                const blob = new Blob(audioChunks, { type: mimeType });
                // Only send if there is data
                if (blob.size > 0) {
                    sendChunkToShiny(blob, nsPrefix);
                }
            }
            if (isRecordingActive) {
                // Immediate restart for continuous flow
                startRecordingLoop(stream, nsPrefix);
            }
        };

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
        if (mediaRecorder && mediaRecorder.state === "recording") {
            mediaRecorder.stop();
        }
    }
    
    function startRecording(nsPrefix) {
        if (!isRecordingActive && stream) {
            isRecordingActive = true;
            startRecordingLoop(stream, nsPrefix);
        }
    }
    
    function stopAndCleanup(nsPrefix) {
        isRecordingActive = false;
        if (chunkTimer) clearTimeout(chunkTimer);
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