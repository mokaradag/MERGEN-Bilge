// =============================================================================
// Dosya Yolu: www/js/claude_code_sessions.js
// Açıklama: Bilge Yolaç Oturumları sayfasının istemci köprüsü. Kayıtlı bir
//           oturumun mesaj geçmişini çalışma alanına geri oynatan
//           'cc-hydrate-session' Shiny mesaj işleyicisini sağlar.
//
//           Mesaj görünümü tek kaynaktan üretilir: claude_code.js içindeki
//           addMessage yolu window.MergenClaudeCode.addMessage köprüsüyle
//           yeniden kullanılır. Köprü yoksa (beklenmedik yükleme sırası)
//           içerik textContent ile inert olarak basılır; ham HTML asla
//           güvenilmeyen bir yoldan innerHTML'e verilmez.
// =============================================================================

(function() {
  'use strict';

  // Köprü yokken kullanılan güvenli (inert) yedek mesaj basımı.
  function fallbackAppendMessage(target, msg) {
    var div = document.createElement('div');
    div.className = 'cc-message cc-message-' + (msg.type || 'assistant');

    var body = document.createElement('pre');
    body.className = 'cc-user-pre';
    // Yedek yol inert kalır: HTML yorumlanmaz, metin olarak gösterilir.
    body.textContent = String(msg.content || '').replace(/<[^>]*>/g, ' ');
    div.appendChild(body);

    target.appendChild(div);
  }

  Shiny.addCustomMessageHandler('cc-set-model-selection', function(data) {
    var value = String((data && data.value) || '');
    var inputId = String((data && data.inputId) || '');
    if (!inputId || !value) return;

    var selected = null;
    document.querySelectorAll('.cc-model-tier-btn').forEach(function(btn) {
      if (btn.getAttribute('data-value') === value) {
        selected = btn;
      }
    });

    if (selected) {
      var group = selected.closest('.cc-model-tier-group') || document;
      group.querySelectorAll('.cc-model-tier-btn').forEach(function(btn) {
        btn.classList.remove('active');
      });
      selected.classList.add('active');
    }

    if (window.Shiny && typeof window.Shiny.setInputValue === 'function') {
      window.Shiny.setInputValue(inputId, value, { priority: 'event' });
    }
  });

  Shiny.addCustomMessageHandler('cc-hydrate-session', function(data) {
    var target = document.getElementById(data.target);
    if (!target) return;

    // Mevcut görünümü temizle; karşılama ekranını gizli tut.
    target.innerHTML = '';

    if (data.welcomeId) {
      var welcome = document.getElementById(data.welcomeId);
      if (welcome) {
        welcome.classList.remove('cc-welcome-active');
        if (typeof window.ccStopWelcome === 'function') {
          window.ccStopWelcome();
        }
      }
    }

    var messages = data.messages || [];
    var bridge = (window.MergenClaudeCode &&
                  typeof window.MergenClaudeCode.addMessage === 'function')
      ? window.MergenClaudeCode.addMessage
      : null;

    for (var i = 0; i < messages.length; i++) {
      var m = messages[i] || {};
      var payload = {
        target: data.target,
        welcomeId: data.welcomeId,
        type: m.type || 'assistant',
        content: m.content || '',
        timestamp: m.timestamp || '',
        duration: m.duration || null,
        toolContent: m.toolContent || '',
        senderName: data.senderName || 'Siz',
        characterName: data.characterName || 'Claude Code',
        accentColor: data.accentColor || ''
      };

      if (bridge) {
        bridge(payload);
      } else {
        fallbackAppendMessage(target, payload);
      }
    }

    // Durum çubuğu: oturumun geçmişten yüklendiğini ve resume durumunu göster.
    if (data.statusId) {
      var statusEl = document.getElementById(data.statusId);
      if (statusEl) {
        var renk = data.resumeOk ? '#81C784' : '#FFB74D';
        var ikon = data.resumeOk ? 'rotate-right' : 'clock-rotate-left';
        var metin = data.resumeOk
          ? 'Oturum yüklendi - devam edilebilir'
          : 'Oturum geçmişi yüklendi';
        statusEl.innerHTML =
          '<i class="fas fa-' + ikon + '" style="color:' + renk + ';"></i> ' +
          '<span style="color:' + renk + ';">' + metin + '</span>';
      }
    }

    if (data.durationId) {
      var durationEl = document.getElementById(data.durationId);
      if (durationEl) durationEl.textContent = '';
    }

    // En alta kaydır (son çalıştırma görünür olsun).
    var wrapper = target.closest('.cc-output-wrapper');
    if (wrapper) {
      wrapper.scrollTop = wrapper.scrollHeight;
    }
  });

})();
