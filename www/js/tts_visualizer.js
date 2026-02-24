// www/js/tts_visualizer.js

$(document).ready(function() {
  
  // --- Constants ---
  const MODES = { IDLE: 'IDLE', TALKING: 'TALKING' };

  // --- Visualizer Class ---
  class SonicPulseVisualizer {
    constructor(canvasId, overlaySelector) {
      this.canvas = document.getElementById(canvasId);
      this.$overlay = $(overlaySelector);
      
      if (!this.canvas) return;

      this.ctx = this.canvas.getContext('2d');
      this.width = 0;
      this.height = 0;
      this.mode = MODES.IDLE;
      this.baseColor = '#7C4DFF'; 
      this.time = 0;
      this.particles = [];
      this.strands = this.generateStrands(12); 
      
      this.resize();
      window.addEventListener('resize', () => this.resize());
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
      if (parent.clientWidth === 0 || parent.clientHeight === 0) return; 

      const rect = parent.getBoundingClientRect();
      this.width = rect.width || parent.offsetWidth || 0;
      this.height = rect.height || parent.offsetHeight || 0;

      const dpr = window.devicePixelRatio || 1;
      this.canvas.width = Math.max(this.width, 1) * dpr;
      this.canvas.height = Math.max(this.height, 1) * dpr;
      this.ctx.setTransform(1, 0, 0, 1, 0, 0);
      this.ctx.scale(dpr, dpr);
    }

    setMode(mode) { this.mode = mode; }
    setColor(hex) { this.baseColor = hex; }

    hexToRgb(hex) {
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
        if (!this.canvas.offsetParent && this.mode === MODES.IDLE) {
           requestAnimationFrame(render);
           return;
        }

        const isTalking = (this.mode === MODES.TALKING);
        const speed = isTalking ? 2.5 : 0.5;
        const globalAmp = isTalking ? 0.8 : 0.2;
        this.time += 0.02 * speed;

        this.ctx.clearRect(0, 0, this.width, this.height);
        this.ctx.globalCompositeOperation = 'lighter';
        this.ctx.lineCap = 'round';
        this.ctx.lineJoin = 'round';

        const centerY = this.height / 2;
        const rgb = this.hexToRgb(this.baseColor);
        
        this.strands.forEach((strand) => {
          this.ctx.beginPath();
          const colorStr = `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${strand.alpha})`;
          let isFirst = true;
          for (let x = 0; x <= this.width; x += 4) {
            const nx = (x / this.width) * 2 - 1; 
            const window = Math.pow(1 - Math.pow(nx, 2), 2); 
            const wave = Math.sin((x * 0.02 * strand.frequency) + (this.time * strand.speed) + strand.phaseOffset);
            const jitter = isTalking ? Math.sin(x * 0.1 + this.time * 5) * 0.1 : 0;
            const y = centerY + (wave + jitter) * (this.height * 0.4) * strand.amplitude * globalAmp * window;
            if (isFirst) { this.ctx.moveTo(x, y); isFirst = false; } else { this.ctx.lineTo(x, y); }
          }
          this.ctx.strokeStyle = colorStr;
          this.ctx.lineWidth = 1.5;
          this.ctx.shadowBlur = isTalking ? 10 : 0;
          this.ctx.shadowColor = this.baseColor;
          this.ctx.stroke();
          this.ctx.shadowBlur = 0;
        });

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

        this.ctx.fillStyle = this.baseColor;
        for (let i = this.particles.length - 1; i >= 0; i--) {
          let p = this.particles[i];
          p.x += p.vx;
          p.y += p.vy;
          p.life -= 0.05;
          if (p.life <= 0) { this.particles.splice(i, 1); continue; }
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

  setTimeout(() => {
    visualizer = new SonicPulseVisualizer('tts_canvas', '.tts-overlay-name');
    
    // Fix rendering when container shows up
    const canvasEl = document.getElementById('tts_canvas');
    if (canvasEl) {
      const container = canvasEl.parentElement;
      const resizeObserver = new MutationObserver(function(mutations) {
        if ($(container).is(':visible')) {
           visualizer.resize();
           setTimeout(() => visualizer.resize(), 50);
        }
      });
      resizeObserver.observe(container, { attributes: true, attributeFilter: ['class', 'style'] });
    }

    // Global State for controlling from R or other JS
    window.ttsVisualizerState = {
      setTalking: function() { 
        if(visualizer) visualizer.setMode(MODES.TALKING); 
        
        var $container = $('.tts-visualizer-container');
        $container.addClass('talking-mode');

        // FORCE DYNAMIC COLOR: Use the visualizer's current baseColor for borders/shadows
        if (visualizer && visualizer.baseColor) {
            var color = visualizer.baseColor;
            
            // Apply color to the main container border and glow
            $container.css({
                'border-color': color,
                'box-shadow': '0 0 20px ' + color + '40, inset 0 0 15px rgba(0,0,0,0.3)'
            });
            
            // Apply color to the "Stop" tooltip border and glow
            $container.find('.tts-tooltip').css({
                'border-color': color,
                'box-shadow': '0 4px 20px rgba(0, 0, 0, 0.6), 0 0 10px ' + color + '33' 
            });
        }
      },
      
      setIdle: function() {
        if(visualizer) visualizer.setMode(MODES.IDLE);

        var $container = $('.tts-visualizer-container');
        $container.removeClass('talking-mode');

        // RESET DYNAMIC COLORS (remove inline styles to fall back to CSS defaults)
        $container.css({'border-color': '', 'box-shadow': ''});
        $container.find('.tts-tooltip').css({'border-color': '', 'box-shadow': ''});
      },

      // Duraklatma durumu (TTS sesi geçici olarak durduğunda)
      setPaused: function() {
        if(visualizer) visualizer.setMode(MODES.IDLE);
      },

      stop: function() {
        // 1. Reset Visuals using setIdle (clears colors and classes)
        this.setIdle();

        // 2. Stop Main TTS Engine (Critical Fix for floating Audio objects)
        if (window.mergenTTS && typeof window.mergenTTS.stop === 'function') {
            window.mergenTTS.stop();
        }

        // 3. Brutal Stop Audio (Fallback for any other DOM audio elements)
        $('audio').each(function() {
            try {
                this.pause();
                this.currentTime = 0;
            } catch(e) {}
        });
      }
    };
  }, 100);

  // --- CLICK HANDLER (The Guaranteed Fix) ---
  // Listens on document to ensure dynamic elements are caught
  $(document).on('click', '.tts-visualizer-container', function() {
    // Only stop if currently in talking mode
    if ($(this).hasClass('talking-mode')) {
        if (window.ttsVisualizerState) {
            window.ttsVisualizerState.stop();
        }
    }
  });

  // --- Shiny Message Handler ---
  Shiny.addCustomMessageHandler('resizeTTSVisualizer', function(message) {
    if (visualizer) { visualizer.resize(); setTimeout(() => visualizer.resize(), 200); }
  });

  Shiny.addCustomMessageHandler('updateTTSVisualizer', function(message) {
      if (message.color) visualizer.setColor(message.color);
      
      if (message.state === 'talking') {
        if (visualizer) visualizer.resize();
        visualizer.setMode(MODES.TALKING);
        
        const $container = $('.tts-visualizer-container');
        $container.addClass('talking-mode');
        
		if (message.color) {
            $container.css({
                'border-color': message.color,
                'box-shadow': '0 0 20px ' + message.color + '40, inset 0 0 15px rgba(0,0,0,0.3)'
            });
            
            $container.find('.tts-tooltip').css({
                'border-color': message.color,
                'box-shadow': '0 4px 20px rgba(0, 0, 0, 0.6), 0 0 10px ' + message.color + '33' 
            });
        }

        if (message.duration > 0) {
          if (window._ttsTimer) clearTimeout(window._ttsTimer);
          window._ttsTimer = setTimeout(() => {
             window.ttsVisualizerState.setIdle();
             $('.tts-visualizer-container').css({'border-color': '', 'box-shadow': ''}); 
          }, (message.duration * 1000) + 500);
        }
      } else {
        window.ttsVisualizerState.setIdle();
        $('.tts-visualizer-container').css({'border-color': '', 'box-shadow': ''});
        
        if (window._ttsTimer) clearTimeout(window._ttsTimer);
      }
    });
  
  // --- Sekme değişikliğinde canvas boyutlandırma ---
  // Ana Söyleşi sekmesine geçildiğinde canvas boyutunu güncelle (gizli sekmede boyut 0 olabilir)
  $(document).on('shown.bs.tab', function() {
    if (visualizer) {
      setTimeout(function() {
        visualizer.resize();
        setTimeout(function() { visualizer.resize(); }, 200);
      }, 100);
    }
  });

  // --- Audio Event Listeners (Backup) ---
  document.addEventListener('play', function(e) {
    if(e.target && e.target.tagName === 'AUDIO') {
      if (window._ttsTimer) clearTimeout(window._ttsTimer);
      if (window.ttsVisualizerState) window.ttsVisualizerState.setTalking();
    }
  }, true);

  document.addEventListener('pause', function(e) {
    if(e.target && e.target.tagName === 'AUDIO') {
      if (window.ttsVisualizerState) window.ttsVisualizerState.setIdle();
    }
  }, true);

  document.addEventListener('ended', function(e) {
    if(e.target && e.target.tagName === 'AUDIO') {
      if (window.ttsVisualizerState) window.ttsVisualizerState.setIdle();
    }
  }, true);
});