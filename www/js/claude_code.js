// =============================================================================
// Dosya Yolu: www/js/claude_code.js
// Açıklama: Claude Code entegrasyon sayfasının istemci tarafı mantığı.
//           Mesaj gösterimi, 8-bit piksel karakter animasyonu, düşünme
//           efektleri ve klavye kısayollarını yönetir.
// =============================================================================

(function() {
  'use strict';

  // ---------------------------------------------------------------------------
  // 8-BiT PiKSEL KARAKTER TANiMLARI
  // Her karakter için 8x8 piksel haritası (0=boş, 1=ana renk, 2=koyu ton)
  // ---------------------------------------------------------------------------
  var PIXEL_CHARACTERS = {
    mergen: {
      // Ok ve yay motifli karakter
      pixels: [
        [0,0,0,1,1,0,0,0],
        [0,0,1,1,1,1,0,0],
        [0,1,2,1,1,2,1,0],
        [0,1,1,1,1,1,1,0],
        [0,0,1,2,2,1,0,0],
        [0,1,1,1,1,1,1,0],
        [0,1,0,1,1,0,1,0],
        [0,1,0,0,0,0,1,0]
      ],
      color: '#7C4DFF',
      darkColor: '#5635B2'
    },
    ulgen: {
      // Isik halesine sahip karakter
      pixels: [
        [0,0,1,1,1,1,0,0],
        [0,1,1,1,1,1,1,0],
        [1,1,2,1,1,2,1,1],
        [0,1,1,1,1,1,1,0],
        [0,0,1,2,2,1,0,0],
        [0,1,1,1,1,1,1,0],
        [0,1,0,1,1,0,1,0],
        [0,0,1,0,0,1,0,0]
      ],
      color: '#2F6DF6',
      darkColor: '#1E4DB0'
    },
    kayra: {
      // Harita/pusulali stratejist
      pixels: [
        [0,0,1,1,1,1,0,0],
        [0,1,2,1,1,2,1,0],
        [0,1,1,1,1,1,1,0],
        [0,0,1,1,1,1,0,0],
        [0,1,1,2,2,1,1,0],
        [1,1,1,1,1,1,1,1],
        [0,1,0,1,1,0,1,0],
        [0,1,1,0,0,1,1,0]
      ],
      color: '#12A97B',
      darkColor: '#0C7A58'
    },
    erlik: {
      // Keskin gozlu elestirmen
      pixels: [
        [0,0,2,1,1,2,0,0],
        [0,2,1,1,1,1,2,0],
        [0,1,2,1,1,2,1,0],
        [0,1,1,2,2,1,1,0],
        [0,0,1,1,1,1,0,0],
        [0,1,2,1,1,2,1,0],
        [0,1,0,1,1,0,1,0],
        [0,2,0,0,0,0,2,0]
      ],
      color: '#B66A2C',
      darkColor: '#8F5321'
    },
    umay: {
      // Sefkatli rehber (turna motifli)
      pixels: [
        [0,0,1,1,1,1,0,0],
        [0,1,1,1,1,1,1,0],
        [1,1,2,1,1,2,1,1],
        [0,1,1,1,1,1,1,0],
        [0,0,1,1,1,1,0,0],
        [0,1,1,1,1,1,1,0],
        [1,0,1,1,1,1,0,1],
        [0,0,1,0,0,1,0,0]
      ],
      color: '#E98686',
      darkColor: '#C45E5E'
    }
  };

  // ---------------------------------------------------------------------------
  // PiKSEL KARAKTER CiZiM MOTORU
  // ---------------------------------------------------------------------------
  var animationFrameId = null;
  var starParticles = [];

  /**
   * 8-bit piksel karakteri canvas uzerine cizer
   * @param {HTMLCanvasElement} canvas - Hedef canvas
   * @param {string} characterId - Karakter kimliği
   * @param {number} frame - Animasyon karesi
   */
  function drawPixelCharacter(canvas, characterId, frame) {
    if (!canvas) return;
    var ctx = canvas.getContext('2d');
    var charData = PIXEL_CHARACTERS[characterId] || PIXEL_CHARACTERS.mergen;
    var pixels = charData.pixels;
    var pixelSize = 8; // Her piksel 8x8 cizilir (64x64 canvas)

    ctx.clearRect(0, 0, canvas.width, canvas.height);

    // Ziplama efekti
    var bounceY = Math.sin(frame * 0.08) * 3;

    // Piksel haritasini ciz
    for (var y = 0; y < pixels.length; y++) {
      for (var x = 0; x < pixels[y].length; x++) {
        var val = pixels[y][x];
        if (val === 0) continue;

        if (val === 1) {
          ctx.fillStyle = charData.color;
        } else {
          ctx.fillStyle = charData.darkColor;
        }

        ctx.fillRect(
          x * pixelSize,
          y * pixelSize + bounceY,
          pixelSize - 1,
          pixelSize - 1
        );
      }
    }

    // Yıldız parçacıkları ekle
    drawStarParticles(ctx, charData.color, frame, canvas.width, canvas.height);
  }

  /**
   * Parlayan yıldız parçacıklarını çizer
   */
  function drawStarParticles(ctx, color, frame, width, height) {
    // Yeni parçacıklar ekle (arada sırada)
    if (frame % 15 === 0) {
      starParticles.push({
        x: Math.random() * width,
        y: Math.random() * height,
        size: Math.random() * 3 + 1,
        life: 0,
        maxLife: 30 + Math.random() * 30
      });
    }

    // Parçacıkları çiz ve güncelle
    for (var i = starParticles.length - 1; i >= 0; i--) {
      var p = starParticles[i];
      p.life++;

      if (p.life > p.maxLife) {
        starParticles.splice(i, 1);
        continue;
      }

      var alpha = 1 - (p.life / p.maxLife);
      var scale = Math.sin((p.life / p.maxLife) * Math.PI);

      ctx.save();
      ctx.globalAlpha = alpha * 0.7;
      ctx.fillStyle = color;
      ctx.fillRect(
        p.x - p.size * scale / 2,
        p.y - p.size * scale / 2,
        p.size * scale,
        p.size * scale
      );
      ctx.restore();
    }

    // Fazla parçacıkları temizle
    if (starParticles.length > 20) {
      starParticles = starParticles.slice(-15);
    }
  }

  /**
   * Düşünme animasyon döngüsünü başlatır
   */
  function startThinkingAnimation(canvasId, characterId) {
    var canvas = document.getElementById(canvasId);
    if (!canvas) return;

    var frame = 0;
    starParticles = [];

    function animate() {
      drawPixelCharacter(canvas, characterId, frame);
      frame++;
      animationFrameId = requestAnimationFrame(animate);
    }

    animate();
  }

  /**
   * Düşünme animasyon döngüsünü durdurur
   */
  function stopThinkingAnimation() {
    if (animationFrameId) {
      cancelAnimationFrame(animationFrameId);
      animationFrameId = null;
    }
    starParticles = [];
  }

  // ---------------------------------------------------------------------------
  // MESAJ EKLEME FONKSIYONU
  // ---------------------------------------------------------------------------

  /**
   * Çıktı alanına yeni bir mesaj kabarcığı ekler
   * @param {Object} data - Mesaj verileri
   */
  function addMessage(data) {
    var target = document.getElementById(data.target);
    if (!target) return;

    var msgDiv = document.createElement('div');
    var typeClass = 'cc-message-' + (data.type || 'assistant');
    msgDiv.className = 'cc-message ' + typeClass;

    // Karakter rengi varsa uyarla
    if (data.accentColor) {
      msgDiv.style.setProperty('--cc-accent', data.accentColor);
    }

    // Baslik
    var headerHtml = '<div class="cc-message-header">';
    if (data.type === 'user') {
      headerHtml += '<span class="cc-message-sender">Siz</span>';
    } else if (data.type === 'error') {
      headerHtml += '<span class="cc-message-sender" style="color:#E57373;">Hata</span>';
    } else {
      var charName = data.characterName || 'Claude Code';
      headerHtml += '<span class="cc-message-sender" style="color:' +
                    (data.accentColor || '#7C4DFF') + ';">' + charName + '</span>';
    }

    if (data.timestamp) {
      headerHtml += '<span class="cc-message-time">' + data.timestamp + '</span>';
    }

    if (data.duration) {
      headerHtml += '<span class="cc-message-duration">' + data.duration + ' sn</span>';
    }

    headerHtml += '</div>';

    // İçerik
    var bodyHtml = '<div class="cc-message-body">';
    if (data.type === 'user') {
      bodyHtml += '<pre style="white-space:pre-wrap;margin:0;background:transparent;border:none;padding:0;">' +
                  data.content + '</pre>';
    } else {
      bodyHtml += data.content;
    }
    bodyHtml += '</div>';

    msgDiv.innerHTML = headerHtml + bodyHtml;
    target.appendChild(msgDiv);

    // Otomatik kaydir
    var wrapper = target.closest('.cc-output-wrapper');
    if (wrapper) {
      wrapper.scrollTop = wrapper.scrollHeight;
    }
  }

  // ---------------------------------------------------------------------------
  // SHINY MESAJ İŞLEYİCİLERİ
  // ---------------------------------------------------------------------------

  // Mesaj Ekleme
  Shiny.addCustomMessageHandler('cc-add-message', function(data) {
    addMessage(data);
  });

  // Çıktıyı Temizle
  Shiny.addCustomMessageHandler('cc-clear-output', function(data) {
    var target = document.getElementById(data.target);
    if (target) {
      target.innerHTML = '';
    }
  });

  // Düşünme Animasyonunu Başlat
  Shiny.addCustomMessageHandler('cc-thinking-start', function(data) {
    var overlay = document.getElementById(data.overlayId);
    var textEl = document.getElementById(data.textId);
    var statusEl = document.getElementById(data.statusId);

    if (overlay) {
      overlay.classList.remove('cc-hidden');
    }

    if (textEl) {
      textEl.textContent = data.message || 'Düşünüyor...';
      if (data.accentColor) {
        textEl.style.color = data.accentColor;
      }
    }

    if (statusEl) {
      statusEl.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Çalışıyor...';
    }

    // 8-bit animasyonu başlat
    startThinkingAnimation(data.canvasId, data.characterId || 'mergen');

    // Düşünme mesajını periyodik olarak değiştir
    if (window.ccThinkingInterval) clearInterval(window.ccThinkingInterval);
    window.ccThinkingInterval = setInterval(function() {
      if (textEl && overlay && !overlay.classList.contains('cc-hidden')) {
        // R tarafına mesaj değişimi isteği gönder
        Shiny.setInputValue(data.statusId.replace('status_text', 'thinking_tick'),
                            Math.random(), {priority: 'event'});
      }
    }, 3000);
  });

  // Düşünme Animasyonunu Durdur
  Shiny.addCustomMessageHandler('cc-thinking-stop', function(data) {
    var overlay = document.getElementById(data.overlayId);

    if (overlay) {
      overlay.classList.add('cc-hidden');
    }

    stopThinkingAnimation();

    if (window.ccThinkingInterval) {
      clearInterval(window.ccThinkingInterval);
      window.ccThinkingInterval = null;
    }
  });

  // Durum Çubuğu Güncelle
  Shiny.addCustomMessageHandler('cc-update-status', function(data) {
    var statusEl = document.getElementById(data.statusId);
    var durationEl = document.getElementById(data.durationId);

    if (statusEl) {
      statusEl.textContent = data.status || '';
    }

    if (durationEl) {
      durationEl.textContent = data.duration || '';
    }
  });

  // ---------------------------------------------------------------------------
  // KLAVYE KISAYOLLARI
  // ---------------------------------------------------------------------------

  document.addEventListener('keydown', function(e) {
    // Ctrl+Enter veya Shift+Enter ile komutu gönder
    if ((e.ctrlKey || e.shiftKey) && e.key === 'Enter') {
      var textarea = e.target;
      if (textarea && textarea.classList.contains('cc-prompt-input')) {
        e.preventDefault();
        // En yakın modüldeki çalıştır düğmesini bul ve tıkla
        var container = textarea.closest('.cc-terminal-panel');
        if (container) {
          var runBtn = container.querySelector('.cc-run-btn');
          if (runBtn && !runBtn.disabled) {
            runBtn.click();
          }
        }
      }
    }
  });

})();