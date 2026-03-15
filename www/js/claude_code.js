// =============================================================================
// Dosya Yolu: www/js/claude_code.js
// Açıklama: Claude Code entegrasyon sayfasının istemci tarafı mantığı.
//           Mesaj gösterimi, araç kullanımı görüntüleme, küçültülmüş 8-bit
//           piksel animasyonu, düşünme mesajı döngüsü, karakter teması
//           güncelleme, klavye kısayolları ve prompt değeri yönetimini sağlar.
// =============================================================================

(function() {
  'use strict';

  // -------------------------------------------------------------------------
  // 8-BİT PİKSEL KARAKTER TANIMLARI (küçültülmüş animasyon için)
  // Her karakter 8x8 piksel haritası (0=boş, 1=ana renk, 2=koyu ton)
  // -------------------------------------------------------------------------
  var PIXEL_CHARS_MINI = {
    mergen: {
      frames: [
        [[0,0,0,1,1,0,0,0],[0,0,1,1,1,1,0,0],[0,1,2,1,1,2,1,0],[0,1,1,1,1,1,1,0],
         [0,0,1,2,2,1,0,0],[0,1,1,1,1,1,1,0],[0,1,0,1,1,0,1,0],[0,1,0,0,0,0,1,0]],
        [[0,0,0,1,1,0,0,0],[0,0,1,1,1,1,0,0],[0,1,2,1,1,2,1,0],[0,1,1,1,1,1,1,0],
         [0,0,1,2,2,1,0,0],[0,1,1,1,1,1,1,0],[0,0,1,1,1,1,0,0],[0,1,0,0,0,0,1,0]]
      ],
      color: '#7C4DFF', darkColor: '#5635B2'
    },
    ulgen: {
      frames: [
        [[0,0,1,1,1,1,0,0],[0,1,1,1,1,1,1,0],[1,1,2,1,1,2,1,1],[0,1,1,1,1,1,1,0],
         [0,0,1,2,2,1,0,0],[0,1,1,1,1,1,1,0],[0,1,0,1,1,0,1,0],[0,0,1,0,0,1,0,0]],
        [[0,0,1,1,1,1,0,0],[0,1,1,1,1,1,1,0],[1,1,2,1,1,2,1,1],[0,1,1,1,1,1,1,0],
         [0,0,1,2,2,1,0,0],[0,1,1,1,1,1,1,0],[0,0,1,1,1,1,0,0],[0,1,0,0,0,0,1,0]]
      ],
      color: '#2F6DF6', darkColor: '#1E4DB0'
    },
    kayra: {
      frames: [
        [[0,0,1,1,1,1,0,0],[0,1,2,1,1,2,1,0],[0,1,1,1,1,1,1,0],[0,0,1,1,1,1,0,0],
         [0,1,1,2,2,1,1,0],[1,1,1,1,1,1,1,1],[0,1,0,1,1,0,1,0],[0,1,1,0,0,1,1,0]],
        [[0,0,1,1,1,1,0,0],[0,1,2,1,1,2,1,0],[0,1,1,1,1,1,1,0],[0,0,1,1,1,1,0,0],
         [0,1,1,2,2,1,1,0],[1,1,1,1,1,1,1,1],[0,0,1,1,1,1,0,0],[0,1,0,0,0,0,1,0]]
      ],
      color: '#12A97B', darkColor: '#0C7A58'
    },
    erlik: {
      frames: [
        [[0,0,2,1,1,2,0,0],[0,2,1,1,1,1,2,0],[0,1,2,1,1,2,1,0],[0,1,1,2,2,1,1,0],
         [0,0,1,1,1,1,0,0],[0,1,2,1,1,2,1,0],[0,1,0,1,1,0,1,0],[0,2,0,0,0,0,2,0]],
        [[0,0,2,1,1,2,0,0],[0,2,1,1,1,1,2,0],[0,1,2,1,1,2,1,0],[0,1,1,2,2,1,1,0],
         [0,0,1,1,1,1,0,0],[0,1,2,1,1,2,1,0],[0,0,1,1,1,1,0,0],[0,2,0,0,0,0,2,0]]
      ],
      color: '#B66A2C', darkColor: '#8F5321'
    },
    umay: {
      frames: [
        [[0,0,1,1,1,1,0,0],[0,1,1,1,1,1,1,0],[1,1,2,1,1,2,1,1],[0,1,1,1,1,1,1,0],
         [0,0,1,1,1,1,0,0],[0,1,1,1,1,1,1,0],[1,0,1,1,1,1,0,1],[0,0,1,0,0,1,0,0]],
        [[0,0,1,1,1,1,0,0],[0,1,1,1,1,1,1,0],[1,1,2,1,1,2,1,1],[0,1,1,1,1,1,1,0],
         [0,0,1,1,1,1,0,0],[0,1,1,1,1,1,1,0],[0,0,1,1,1,1,0,0],[1,0,0,0,0,0,0,1]]
      ],
      color: '#E98686', darkColor: '#C45E5E'
    }
  };

  // -------------------------------------------------------------------------
  // KÜÇÜLTÜLMÜŞANİMASYON MOTORU
  // -------------------------------------------------------------------------
  var miniAnimFrameId = null;
  var miniFrame = 0;
  var miniParticles = [];

  function drawMiniCharacter(canvas, characterId, frame) {
    if (!canvas) return;
    var ctx = canvas.getContext('2d');
    var charData = PIXEL_CHARS_MINI[characterId] || PIXEL_CHARS_MINI.mergen;
    var frameIdx = Math.floor(frame / 15) % charData.frames.length;
    var pixels = charData.frames[frameIdx];
    var pixelSize = 6;

    ctx.clearRect(0, 0, canvas.width, canvas.height);

    // Zıplama efekti
    var bounceY = Math.sin(frame * 0.1) * 2;

    for (var y = 0; y < pixels.length; y++) {
      for (var x = 0; x < pixels[y].length; x++) {
        var val = pixels[y][x];
        if (val === 0) continue;
        ctx.fillStyle = val === 1 ? charData.color : charData.darkColor;
        ctx.fillRect(x * pixelSize, y * pixelSize + bounceY, pixelSize - 1, pixelSize - 1);
      }
    }

    // Parçacıklar
    if (frame % 20 === 0) {
      miniParticles.push({
        x: Math.random() * canvas.width,
        y: Math.random() * canvas.height,
        size: Math.random() * 2 + 1,
        life: 0, maxLife: 25 + Math.random() * 20
      });
    }
    for (var i = miniParticles.length - 1; i >= 0; i--) {
      var p = miniParticles[i];
      p.life++;
      if (p.life > p.maxLife) { miniParticles.splice(i, 1); continue; }
      var alpha = 1 - (p.life / p.maxLife);
      ctx.globalAlpha = alpha * 0.5;
      ctx.fillStyle = charData.color;
      ctx.fillRect(p.x, p.y, p.size, p.size);
    }
    ctx.globalAlpha = 1;
    if (miniParticles.length > 10) miniParticles = miniParticles.slice(-8);
  }

  function startMiniAnimation(canvasId, characterId) {
    var canvas = document.getElementById(canvasId);
    if (!canvas) return;
    miniFrame = 0;
    miniParticles = [];

    function animate() {
      drawMiniCharacter(canvas, characterId, miniFrame);
      miniFrame++;
      miniAnimFrameId = requestAnimationFrame(animate);
    }
    animate();
  }

  function stopMiniAnimation() {
    if (miniAnimFrameId) {
      cancelAnimationFrame(miniAnimFrameId);
      miniAnimFrameId = null;
    }
    miniParticles = [];
  }

  // -------------------------------------------------------------------------
  // ARAÇ KULLANIMI GÖRÜNTÜLEMESİ (açılır/kapanır)
  // -------------------------------------------------------------------------
  function toggleToolBlock(el) {
    var result = el.closest('.cc-tool-block').querySelector('.cc-tool-result');
    if (result) {
      result.classList.toggle('cc-tool-result-hidden');
      var icon = el.querySelector('.cc-tool-toggle-icon');
      if (icon) {
        icon.classList.toggle('fa-chevron-down');
        icon.classList.toggle('fa-chevron-right');
      }
    }
  }

  // Araç blokları için tıklama işleyicisi (event delegation)
  document.addEventListener('click', function(e) {
    var header = e.target.closest('.cc-tool-header');
    if (header && header.closest('.cc-tool-block')) {
      toggleToolBlock(header);
    }
  });

  // -------------------------------------------------------------------------
  // MESAJ EKLEME
  // -------------------------------------------------------------------------
  function addMessage(data) {
    var target = document.getElementById(data.target);
    if (!target) return;

    // Karşılama ekranını gizle ve animasyonu durdur
    if (data.welcomeId) {
      var welcome = document.getElementById(data.welcomeId);
      if (welcome) {
        welcome.classList.remove('cc-welcome-active');
        if (typeof window.ccStopWelcome === 'function') {
          window.ccStopWelcome();
        }
      }
    }

    var msgDiv = document.createElement('div');
    var typeClass = 'cc-message-' + (data.type || 'assistant');
    msgDiv.className = 'cc-message ' + typeClass;

    if (data.accentColor) {
      msgDiv.style.setProperty('--cc-accent', data.accentColor);
    }

    // Başlık
    var headerHtml = '<div class="cc-message-header">';
    if (data.type === 'user') {
      var senderName = data.senderName || 'Siz';
      headerHtml += '<span class="cc-message-sender">' + senderName + '</span>';
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

    // Araç kullanımı (açılır/kapanır bloklar)
    var toolHtml = '';
    if (data.toolContent && data.toolContent.length > 0) {
      toolHtml = '<div class="cc-tool-section">' +
                 '<div class="cc-tool-section-header">' +
                 '<i class="fas fa-cogs"></i> Araç Kullanımları' +
                 '</div>' + data.toolContent + '</div>';
    }

    // İçerik
    var bodyHtml = '<div class="cc-message-body">';
    if (data.type === 'user') {
      bodyHtml += '<pre class="cc-user-pre">' + data.content + '</pre>';
    } else {
      bodyHtml += data.content;
    }
    bodyHtml += '</div>';

    msgDiv.innerHTML = headerHtml + toolHtml + bodyHtml;

    // Araç sonuçlarını varsayılan olarak gizle
    var toolResults = msgDiv.querySelectorAll('.cc-tool-result');
    toolResults.forEach(function(tr) {
      tr.classList.add('cc-tool-result-hidden');
    });

    // Açma/kapama ikonlarını ekle
    var toolHeaders = msgDiv.querySelectorAll('.cc-tool-header');
    toolHeaders.forEach(function(th) {
      if (!th.querySelector('.cc-tool-toggle-icon')) {
        var toggleIcon = document.createElement('i');
        toggleIcon.className = 'fas fa-chevron-right cc-tool-toggle-icon';
        th.appendChild(toggleIcon);
      }
      th.style.cursor = 'pointer';
    });

    target.appendChild(msgDiv);

    // Otomatik kaydır
    var wrapper = target.closest('.cc-output-wrapper');
    if (wrapper) {
      wrapper.scrollTop = wrapper.scrollHeight;
    }
  }

  // -------------------------------------------------------------------------
  // PROMPT DEĞER OKUMA YARDIMCISI
  // Shiny'nin raw textarea'dan değer okuması için prompt değerini gönderir
  // -------------------------------------------------------------------------
  function sendPromptValue(ns) {
    var textarea = document.querySelector('.cc-prompt-input');
    if (!textarea) return;
    var value = textarea.value || '';
    // Shiny'ye prompt değerini gönder
    var inputId = ns ? ns.replace(/-$/, '') + '-prompt_value' : 'claude_code_module-prompt_value';
    Shiny.setInputValue(inputId, value, {priority: 'event'});
  }

  // -------------------------------------------------------------------------
  // SHINY MESAJ İŞLEYİCİLERİ
  // -------------------------------------------------------------------------

  // Mesaj Ekleme
  Shiny.addCustomMessageHandler('cc-add-message', function(data) {
    addMessage(data);
  });

  // Çıktıyı Temizle ve karşılama ekranını göster
  Shiny.addCustomMessageHandler('cc-clear-output', function(data) {
    var target = document.getElementById(data.target);
    if (target) target.innerHTML = '';

    if (data.welcomeId) {
      var welcome = document.getElementById(data.welcomeId);
      if (welcome) {
        welcome.classList.add('cc-welcome-active');
        // Karşılama animasyonunu yeniden başlat
        if (typeof window.ccStartWelcome === 'function') {
          window.ccStartWelcome(data.welcomeId);
        }
      }
    }
  });

  // Düşünme animasyonunu başlat (küçültülmüş)
  Shiny.addCustomMessageHandler('cc-thinking-start', function(data) {
    var overlay = document.getElementById(data.overlayId);
    var textEl = document.getElementById(data.textId);
    var statusEl = document.getElementById(data.statusId);

    if (overlay) overlay.classList.remove('cc-hidden');

    if (textEl) {
      textEl.textContent = data.message || 'Düşünüyor...';
      if (data.accentColor) textEl.style.color = data.accentColor;
    }

    if (statusEl) {
      statusEl.innerHTML = '<i class="fas fa-spinner fa-spin" style="color:#64B5F6;"></i> <span style="color:#64B5F6;">Çalışıyor...</span>';
    }

    startMiniAnimation(data.canvasId, data.characterId || 'mergen');

    // Düşünme mesajını periyodik değiştir (3 saniyede bir)
    if (window.ccThinkingInterval) clearInterval(window.ccThinkingInterval);
    window.ccThinkingInterval = setInterval(function() {
      if (textEl && overlay && !overlay.classList.contains('cc-hidden')) {
        // thinking_tick adını namespace ile oluştur
        var tickId = data.statusId.replace('status_text', 'thinking_tick');
        Shiny.setInputValue(tickId, Math.random(), {priority: 'event'});
      }
    }, 3000);
  });

  // Düşünme animasyonunu durdur
  Shiny.addCustomMessageHandler('cc-thinking-stop', function(data) {
    var overlay = document.getElementById(data.overlayId);
    if (overlay) overlay.classList.add('cc-hidden');

    stopMiniAnimation();

    if (window.ccThinkingInterval) {
      clearInterval(window.ccThinkingInterval);
      window.ccThinkingInterval = null;
    }
  });

  // Düşünme metni güncelleme
  Shiny.addCustomMessageHandler('cc-update-thinking-text', function(data) {
    var textEl = document.getElementById(data.textId);
    if (textEl) {
      textEl.style.opacity = '0';
      setTimeout(function() {
        textEl.textContent = data.message || '';
        textEl.style.opacity = '1';
      }, 200);
    }
  });

  // Durum çubuğu güncelle (ikon + renk destekli)
  Shiny.addCustomMessageHandler('cc-update-status', function(data) {
    var statusEl = document.getElementById(data.statusId);
    var durationEl = document.getElementById(data.durationId);

    if (statusEl) {
      var iconClass = data.statusIcon || 'circle';
      var color = data.statusColor || '#81C784';
      statusEl.innerHTML = '<i class="fas fa-' + iconClass + '" style="color:' + color + ';"></i> ' +
                          '<span style="color:' + color + ';">' + (data.status || '') + '</span>';
    }

    if (durationEl) {
      durationEl.textContent = data.duration || '';
    }
  });

  // Karakter teması güncelleme
  Shiny.addCustomMessageHandler('cc-update-theme', function(data) {
    var container = document.querySelector('.claude-code-container');
    if (!container) return;

    container.setAttribute('data-character', data.characterId || 'mergen');

    // CSS değişkenlerini güncelle
    var accent = data.accentColor || '#7C4DFF';
    var hover = data.accentHover || accent;
    container.style.setProperty('--cc-theme-accent', accent);
    container.style.setProperty('--cc-theme-hover', hover);

    // Rozet rengini güncelle
    var badge = container.querySelector('.cc-badge');
    if (badge) {
      badge.style.background = 'linear-gradient(135deg, ' + accent + ' 0%, ' + hover + ' 100%)';
    }

    // Karşılama ekranını da güncelle
    if (typeof window.ccUpdateWelcomeTheme === 'function') {
      window.ccUpdateWelcomeTheme(data.characterId, accent);
    }
  });

  // -------------------------------------------------------------------------
  // KLAVYE KISAYOLLARI VE DÜĞME TIKLAMA YÖNETİMİ
  // -------------------------------------------------------------------------

  // Çalıştır düğmesine tıklanmadan önce prompt değerini Shiny'ye gönder
  document.addEventListener('click', function(e) {
    var runBtn = e.target.closest('.cc-run-btn');
    if (runBtn && !runBtn.disabled) {
      // Prompt değerini hemen Shiny'ye gönder
      var container = runBtn.closest('.cc-terminal-panel') || runBtn.closest('.claude-code-container');
      if (container) {
        var textarea = container.querySelector('.cc-prompt-input');
        if (textarea) {
          var ns = textarea.id.replace(/prompt_input$/, '');
          var inputId = ns + 'prompt_value';
          Shiny.setInputValue(inputId, textarea.value || '', {priority: 'event'});
        }
      }
    }
  }, true); // capture phase - düğme tıklamasından önce çalışır

  // Ctrl+Enter veya Shift+Enter ile gönder
  document.addEventListener('keydown', function(e) {
    if ((e.ctrlKey || e.shiftKey) && e.key === 'Enter') {
      var textarea = e.target;
      if (textarea && textarea.classList.contains('cc-prompt-input')) {
        e.preventDefault();
        var container = textarea.closest('.cc-terminal-panel') || textarea.closest('.claude-code-container');
        if (container) {
          var runBtn = container.querySelector('.cc-run-btn');
          if (runBtn && !runBtn.disabled) {
            // Önce prompt değerini gönder
            var ns = textarea.id.replace('prompt_input', '');
            var inputId = ns + 'prompt_value';
            Shiny.setInputValue(inputId, textarea.value || '', {priority: 'event'});
            // Sonra düğmeyi tıkla (küçük gecikme ile)
            setTimeout(function() { runBtn.click(); }, 50);
          }
        }
      }
    }
  });

})();
