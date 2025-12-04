// www/js/tts_visualizer.js

$(document).ready(function() {
  
  // --- Configuration ---
  const MODES = {
    IDLE: 'IDLE',
    TALKING: 'TALKING'
  };

  // --- Visualizer Class ---
  class SonicPulseVisualizer {
    constructor(canvasId, overlaySelector) {
      this.canvas = document.getElementById(canvasId);
      this.$overlay = $(overlaySelector);
      
      if (!this.canvas) return;

      this.ctx = this.canvas.getContext('2d');
      // Initialize with 0, resize will handle it
      this.width = 0;
      this.height = 0;
      
      // State
      this.mode = MODES.IDLE;
      this.baseColor = '#7C4DFF'; 
      
      // Animation State
      this.time = 0;
      this.particles = [];
      this.strands = this.generateStrands(12); 
      
      // Resize handling
      this.resize();
      window.addEventListener('resize', () => this.resize());
      
      // Start Loop
      this.animate();
    }

    generateStrands(count) {
      const strands = [];
      for (let i = 0; i < count; i++) {
        strands.push({
          phaseOffset: Math.random() * Math.PI * 2,
          frequency: 1 + Math.random() * 3,
          speed: 0.5 + Math.random() * 1.5,
          amplitude: 0.3 + Math.random() * 0.7,
          alpha: 0.3 + Math.random() * 0.5 
        });
      }
      return strands;
    }

    resize() {
      if (!this.canvas || !this.ctx) return;
      const parent = this.canvas.parentElement;
      
      // Check if parent is visible/has dimensions
      if (parent.clientWidth === 0 || parent.clientHeight === 0) {
        return; 
      }

      const rect = parent.getBoundingClientRect();
      this.width = rect.width || parent.offsetWidth || 0;
      this.height = rect.height || parent.offsetHeight || 0;

      const dpr = window.devicePixelRatio || 1;
      
      // Force canvas internal dimensions
      this.canvas.width = Math.max(this.width, 1) * dpr;
      this.canvas.height = Math.max(this.height, 1) * dpr;
      
      this.ctx.setTransform(1, 0, 0, 1, 0, 0);
      this.ctx.scale(dpr, dpr);
    }

    setMode(mode) {
      this.mode = mode;
    }

    setColor(hex) {
      this.baseColor = hex;
      if (this.$overlay.length) {
        this.$overlay.css('color', hex);
      }
    }

    setText(text) {
      if (this.$overlay.length && text) {
        this.$overlay.text(text);
      }
    }

    hexToRgb(hex) {
      const shorthandRegex = /^#?([a-f\d])([a-f\d])([a-f\d])$/i;
      hex = hex.replace(shorthandRegex, (m, r, g, b) => r + r + g + g + b + b);
      const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
      return result ? {
        r: parseInt(result[1], 16),
        g: parseInt(result[2], 16),
        b: parseInt(result[3], 16)
      } : { r: 124, g: 77, b: 255 };
    }

    animate() {
      if (!this.ctx) return;

      const render = () => {
        // Safety check if canvas was removed or hidden
        if (!this.canvas.offsetParent && this.mode === MODES.IDLE) {
           requestAnimationFrame(render);
           return;
        }

        // Config based on mode
        const isTalking = (this.mode === MODES.TALKING);
        const speed = isTalking ? 2.5 : 0.5;
        const globalAmp = isTalking ? 0.8 : 0.2;
        
        this.time += 0.02 * speed;

        // Clear
        this.ctx.clearRect(0, 0, this.width, this.height);
        this.ctx.globalCompositeOperation = 'lighter';
        this.ctx.lineCap = 'round';
        this.ctx.lineJoin = 'round';

        const centerY = this.height / 2;
        const rgb = this.hexToRgb(this.baseColor);
        
        // Draw Strands
        this.strands.forEach((strand, idx) => {
          this.ctx.beginPath();
          
          const colorStr = `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${strand.alpha})`;
          
          let isFirst = true;
          // Step size optimization for small canvas
          for (let x = 0; x <= this.width; x += 4) {
            const nx = (x / this.width) * 2 - 1; // -1 to 1
            const window = Math.pow(1 - Math.pow(nx, 2), 2); // Taper ends
            
            // Simulation wave math
            const wave = Math.sin(
              (x * 0.02 * strand.frequency) + 
              (this.time * strand.speed) + 
              strand.phaseOffset
            );
            
            // Add some "jitter" if talking
            const jitter = isTalking ? Math.sin(x * 0.1 + this.time * 5) * 0.1 : 0;
            
            const y = centerY + (wave + jitter) * (this.height * 0.4) * strand.amplitude * globalAmp * window;

            if (isFirst) { this.ctx.moveTo(x, y); isFirst = false; }
            else { this.ctx.lineTo(x, y); }
          }
          
          this.ctx.strokeStyle = colorStr;
          this.ctx.lineWidth = 1.5;
          this.ctx.shadowBlur = isTalking ? 10 : 0;
          this.ctx.shadowColor = this.baseColor;
          this.ctx.stroke();
          this.ctx.shadowBlur = 0;
        });

        // Particles (Only when talking)
        if (isTalking && Math.random() < 0.2) {
           this.particles.push({
             x: this.width / 2 + (Math.random() - 0.5) * (this.width * 0.5),
             y: centerY + (Math.random() - 0.5) * 20,
             vx: (Math.random() - 0.5) * 2,
             vy: (Math.random() - 0.5) * 2,
             life: 1.0,
             size: Math.random() * 2 + 0.5
           });
        }

        // Draw & Update Particles
        this.ctx.fillStyle = this.baseColor;
        for (let i = this.particles.length - 1; i >= 0; i--) {
          let p = this.particles[i];
          p.x += p.vx;
          p.y += p.vy;
          p.life -= 0.05;
          
          if (p.life <= 0) {
            this.particles.splice(i, 1);
            continue;
          }
          
          this.ctx.globalAlpha = p.life;
          this.ctx.beginPath();
          this.ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
          this.ctx.fill();
          this.ctx.globalAlpha = 1.0;
        }

        requestAnimationFrame(render);
      };
      
      render();
    }
  }

  // --- Initialization ---
  let visualizer = null;
  // NOT: stopBtnId ve setStopButtonState kaldırıldı

  setTimeout(() => {
    visualizer = new SonicPulseVisualizer('tts_canvas', '.tts-overlay-name');
    
    // MutationObserver to fix rendering when container visibility changes
    const canvasEl = document.getElementById('tts_canvas');
    if (canvasEl) {
      const container = canvasEl.parentElement; 
      
      const resizeObserver = new MutationObserver(function(mutations) {
        if ($(container).is(':visible')) {
           visualizer.resize();
           setTimeout(() => visualizer.resize(), 50);
           setTimeout(() => visualizer.resize(), 200);
        }
      });
      
      resizeObserver.observe(container, { 
        attributes: true, 
        attributeFilter: ['class', 'style'] 
      });
    }

    // Initial state setup helper
    window.ttsVisualizerState = {
      setTalking: function() { if(visualizer) visualizer.setMode(MODES.TALKING); },
      setIdle: function() { if(visualizer) visualizer.setMode(MODES.IDLE); },
      setPaused: function() { if(visualizer) visualizer.setMode(MODES.IDLE); },
      stop: function() {
        if(visualizer) visualizer.setMode(MODES.IDLE);
        
        // YENİ: Sınıfı kaldır
        $('.tts-visualizer-container').removeClass('talking-mode');

        // Stop actual audio playback
        var audios = document.querySelectorAll('audio');
        audios.forEach(function(audio) {
          try {
            audio.pause();
            audio.currentTime = 0;
          } catch(e) { console.error(e); }
        });
        
        // Clear global queue
        if(window.mergenTTS) {
          window.mergenTTS.queue = [];
          window.mergenTTS.isPlaying = false;
        }
      }
    };
  }, 100);

  // --- NEW: Click Listener for Container (Stop action) ---
  $(document).on('click', '.tts-visualizer-container', function() {
    // Sadece 'talking-mode' sınıfı varsa (yani konuşuyorsa) durdur
    if ($(this).hasClass('talking-mode')) {
      if (window.ttsVisualizerState) {
        window.ttsVisualizerState.stop();
      }
    }
  });

  // --- Shiny Message Handler ---
  Shiny.addCustomMessageHandler('resizeTTSVisualizer', function(message) {
    if (visualizer) {
      visualizer.resize();
      setTimeout(() => visualizer.resize(), 100);
      setTimeout(() => visualizer.resize(), 300);
    }
  });

  // Update Visualizer State
  Shiny.addCustomMessageHandler('updateTTSVisualizer', function(message) {
    if (message.color) visualizer.setColor(message.color);

    // Update Mode & Class Logic
    if (message.state === 'talking') {
      if (visualizer) visualizer.resize();

      visualizer.setMode(MODES.TALKING);
      // YENİ: Konuşma modu sınıfını ekle (CSS ve click için gerekli)
      $('.tts-visualizer-container').addClass('talking-mode');

      if (message.duration > 0) {
         if (window._ttsTimer) clearTimeout(window._ttsTimer);
         window._ttsTimer = setTimeout(() => {
           visualizer.setMode(MODES.IDLE);
           $('.tts-visualizer-container').removeClass('talking-mode');
         }, (message.duration * 1000) + 500);
      }
    } else {
      visualizer.setMode(MODES.IDLE);
      $('.tts-visualizer-container').removeClass('talking-mode');
      if (window._ttsTimer) clearTimeout(window._ttsTimer);
    }
  });
  
  // Audio Event Listeners (Sync visuals with raw audio events)
  document.addEventListener('play', function(e) {
    if(e.target && e.target.tagName === 'AUDIO') {
      if (window._ttsTimer) clearTimeout(window._ttsTimer);
      if (visualizer) visualizer.setMode(MODES.TALKING);
      $('.tts-visualizer-container').addClass('talking-mode');
    }
  }, true);

  document.addEventListener('pause', function(e) {
    if(e.target && e.target.tagName === 'AUDIO') {
      if (visualizer) visualizer.setMode(MODES.IDLE);
      $('.tts-visualizer-container').removeClass('talking-mode');
    }
  }, true);

  document.addEventListener('ended', function(e) {
    if(e.target && e.target.tagName === 'AUDIO') {
      if (visualizer) visualizer.setMode(MODES.IDLE);
      $('.tts-visualizer-container').removeClass('talking-mode');
    }
  }, true);

});