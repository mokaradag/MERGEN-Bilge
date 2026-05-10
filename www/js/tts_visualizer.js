/* www/js/tts_visualizer.js */
/**
 * Dosya Yolu: www/js/tts_visualizer.js
 * Açıklama: Metinden Sese (TTS) işlemi sırasında aktif olan dinamik ses dalgası görselleştiricisi.
 * Canvas API kullanarak "Sonic Pulse" animasyonları oluşturur, karakterin
 * tema rengine göre dinamik olarak renklenir ve konuşma moduna geçer.
 */

$(document).ready(function() {
  
  // --- Sabitler ---
  // Görselleştiricinin çalışma modları: Bekleme (Sakin) ve Konuşma (Aktif)
  const MODES = { IDLE: 'IDLE', TALKING: 'TALKING' };

  // --- Görselleştirici Sınıfı ---
  class SonicPulseVisualizer {
    /**
     * @param {string} canvasId Çizim yapılacak canvas elemanının ID'si
     * @param {string} overlaySelector İsim katmanı seçicisi
     */
    constructor(canvasId, overlaySelector) {
      this.canvas = document.getElementById(canvasId);
      this.$overlay = $(overlaySelector);
      
      if (!this.canvas) return;

      this.ctx = this.canvas.getContext('2d');
      this.width = 0;
      this.height = 0;
      this.mode = MODES.IDLE;
      this.baseColor = '#7C4DFF'; // Varsayılan tema rengi
      this.time = 0;
      this.particles = []; // Konuşma modunda çıkan partiküller
      this.strands = this.generateStrands(12); // Dalga katmanları
      
      this.resize();
      window.addEventListener('resize', () => this.resize());
      this.animate();
    }

    /**
     * Rastgele parametrelerle dalga katmanları (strands) oluşturur.
     * @param {number} count Oluşturulacak katman sayısı
     */
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

    /**
     * Canvas boyutlarını kapsayıcı elemana göre ayarlar ve yüksek DPI desteği sağlar.
     */
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

    // Çalışma modunu değiştir (IDLE / TALKING)
    setMode(mode) { this.mode = mode; }
    
    // Tema rengini ayarlar (Hex formatında)
    setColor(hex) { this.baseColor = hex; }

    /**
     * Hex renk kodunu RGB nesnesine dönüştürür.
     */
    hexToRgb(hex) {
      const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
      return result ? {
        r: parseInt(result[1], 16),
        g: parseInt(result[2], 16),
        b: parseInt(result[3], 16)
      } : { r: 124, g: 77, b: 255 };
    }

    /**
     * Ana animasyon döngüsü (requestAnimationFrame).
     */
    animate() {
      if (!this.ctx) return;
      const render = () => {
        // Eğer eleman gizliyse ve bekleme modundaysa kaynak tüketmemek için çizimi atla
        if (!this.canvas.offsetParent && this.mode === MODES.IDLE) {
           requestAnimationFrame(render);
           return;
        }

        const isTalking = (this.mode === MODES.TALKING);
        const speed = isTalking ? 2.5 : 0.5;
        const globalAmp = isTalking ? 0.8 : 0.2;
        this.time += 0.02 * speed;

        // Canvas'ı temizle
        this.ctx.clearRect(0, 0, this.width, this.height);
        this.ctx.globalCompositeOperation = 'lighter';
        this.ctx.lineCap = 'round';
        this.ctx.lineJoin = 'round';

        const centerY = this.height / 2;
        const rgb = this.hexToRgb(this.baseColor);
        
        // Dalga katmanlarını çiz
        this.strands.forEach((strand) => {
          this.ctx.beginPath();
          const colorStr = `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${strand.alpha})`;
          let isFirst = true;
          for (let x = 0; x <= this.width; x += 4) {
            const nx = (x / this.width) * 2 - 1; 
            // "Windowing" fonksiyonu: Kenarlarda dalgayı sıfırlar (Gassian benzeri efekt)
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

        // Konuşma modunda rastgele partiküller oluştur
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

        // Partikülleri güncelle ve çiz
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

  // --- Başlatma Mantığı ---
  let visualizer = null;
  
  // --- SAYFA BAŞLIĞINA YERLEŞTİRME YARDIMCILARI ---
  // Aktif sekmedeki görünür başlığı bulur ve TTS görselleştiriciyi
  // bu başlığın içine taşır.
  function getActiveHeader() {
    const selectors = [
      '.tab-pane.active .chat-header:visible',
      '.tab-pane.active .files-header:visible',
      '.tab-pane.active .settings-header-fixed:visible',
      '.content-wrapper .chat-header:visible',
      '.content-wrapper .files-header:visible',
      '.content-wrapper .settings-header-fixed:visible'
    ];

    for (const selector of selectors) {
      const $header = $(selector).first();
      if ($header.length) {
        return $header;
      }
    }

    return $();
  }

  function mountVisualizerInHeader() {
    const $wrapper = $('#tts_visualizer_floating');
    if (!$wrapper.length) return;

    const $header = getActiveHeader();
    if (!$header.length) return;

    const $visibleChildren = $header.children(':visible');

    // Başlıkta sol grup ile sağ grup arasına yerleştir.
    if ($visibleChildren.length >= 2) {
      $wrapper.insertAfter($visibleChildren.eq(0));
    } else {
      $header.append($wrapper);
    }

    if (visualizer) {
      visualizer.resize();
      setTimeout(() => visualizer.resize(), 60);
    }
  }

  setTimeout(() => {
    // Görselleştiriciyi başlat
    visualizer = new SonicPulseVisualizer('tts_canvas', '.tts-overlay-name');

    // Aktif sayfa başlığına yerleştir
    mountVisualizerInHeader();
    setTimeout(mountVisualizerInHeader, 250);
    
    // Görünürlük değişikliklerini izle (Konteynır gösterildiğinde boyutları düzelt)
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

    // R veya diğer JS dosyalarından erişilebilecek küresel durum nesnesi
    window.ttsVisualizerState = {
      // Konuşma moduna geç ve UI'ı güncelle
      setTalking: function() { 
        if(visualizer) visualizer.setMode(MODES.TALKING); 
        
        var $container = $('.tts-visualizer-container');
        $container.addClass('talking-mode');

        // DİNAMİK RENK: Görselleştiricinin o anki tema rengini UI elemanlarına uygula
        if (visualizer && visualizer.baseColor) {
            var color = visualizer.baseColor;
            
            // Konteynır kenarlığı ve parlaması
            $container.css({
                'border-color': color,
                'box-shadow': '0 0 20px ' + color + '40, inset 0 0 15px rgba(0,0,0,0.3)'
            });
            
            // "Durdur" ipucu rengi
            $container.find('.tts-tooltip').css({
                'border-color': color,
                'box-shadow': '0 4px 20px rgba(0, 0, 0, 0.6), 0 0 10px ' + color + '33' 
            });
        }
      },
      
      // Bekleme moduna dön ve UI stillerini temizle
      setIdle: function() { 
        if(visualizer) visualizer.setMode(MODES.IDLE); 
        
        var $container = $('.tts-visualizer-container');
        $container.removeClass('talking-mode');
        
        // Dinamik renkleri sıfırla (CSS varsayılanlarına dön)
        $container.css({'border-color': '', 'box-shadow': ''});
        $container.find('.tts-tooltip').css({'border-color': '', 'box-shadow': ''});
      },
	  
	  // Duraklatma durumu (TTS sesi geçici olarak durduğunda)
      setPaused: function() {
        if(visualizer) visualizer.setMode(MODES.IDLE);
      },

      // Seslendirmeyi ve animasyonu tamamen durdur (Kullanıcı tıkladığında çağrılır)
      stop: function() {
        // 1. Görselleri sıfırla
        this.setIdle();

        // 2. Ana TTS motorunu durdur
        if (window.mergenTTS && typeof window.mergenTTS.stop === 'function') {
            window.mergenTTS.stop();
        }

        // 3. AI Uzman konuşmasını da durdur (varsa)
        if (window.AIExpertManager && window.AIExpertManager.state.isSpeaking) {
            window.AIExpertManager.stopSubtitle({});
        }

        // 4. Mevcut tüm ses elemanlarını zorla durdur
        $('audio').each(function() {
            try {
                this.pause();
                this.currentTime = 0;
            } catch(e) {}
        });
      }
    };
  }, 100);

  // --- TIKLAMA İŞLEYİCİSİ ---
  // Görselleştiriciye tıklandığında seslendirmeyi durdurur
  $(document).on('click', '.tts-visualizer-container', function() {
    if ($(this).hasClass('talking-mode')) {
        if (window.ttsVisualizerState) {
            window.ttsVisualizerState.stop();
        }
    }
  });

  // --- Shiny Mesaj İşleyicileri ---
  // Canvas boyutunu yeniden hesapla
  Shiny.addCustomMessageHandler('resizeTTSVisualizer', function(message) {
    mountVisualizerInHeader();
    if (visualizer) {
      visualizer.resize();
      setTimeout(() => visualizer.resize(), 200);
    }
  });

  // TTS durumunu (konuşma/durma) R'dan gelen verilere göre güncelle
  Shiny.addCustomMessageHandler('updateTTSVisualizer', function(message) {
      mountVisualizerInHeader();
      if (!visualizer || !window.ttsVisualizerState) return;
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

        // Süre bilgisi varsa otomatik olarak bekleme moduna geçmek için zamanlayıcı kur
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
  
  // --- Sekme Değişikliği İzleyici ---
  // Gizli sekmelerde canvas boyutları 0 olabilir, sekme açıldığında yeniden boyutlandır
  $(document).on('shown.bs.tab', function() {
    setTimeout(function() {
      mountVisualizerInHeader();
      if (visualizer) {
        visualizer.resize();
        setTimeout(function() { visualizer.resize(); }, 200);
      }
    }, 100);
  });

  $(window).on('resize', function() {
    setTimeout(function() {
      mountVisualizerInHeader();
    }, 50);
  });

  // --- Ses Olayı Dinleyicileri (Yedek) ---
  // Sayfadaki herhangi bir ses oynatıldığında görselleştiriciyi tetikle
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