// =============================================================================
// Dosya Yolu: www/js/claude_code_streaming.js
// Açıklama: Claude Code canlı akış desteği. Kabuk komutları, dosya işlemleri
//           ve metin parçalarını gerçek zamanlı görüntüler. Kabuk görünürlüğü
//           açma/kapama düğmesi ve dosya önizleme mantığını içerir.
// =============================================================================

(function() {
  'use strict';

  // ---------------------------------------------------------------------------
  // KABUK GÖRÜNÜRLÜĞÜ DURUMU
  // Kullanıcının kabuk komutlarını gizleyip gizlemediğini takip eder.
  // ---------------------------------------------------------------------------
  var shellVisible = true;

  // ---------------------------------------------------------------------------
  // KABUK GÖRÜNÜRLÜĞÜNÜAÇ/KAPA
  // Tüm kabuk/araç bloklarının görünürlüğünü değiştirir.
  // ---------------------------------------------------------------------------
  window.ccToggleShellVisibility = function(el) {
    shellVisible = !shellVisible;
    var icon = el ? el.querySelector('i') : null;

    // Tüm araç bloklarını bul
    var allBlocks = document.querySelectorAll('.cc-shell-block');
    allBlocks.forEach(function(block) {
      if (shellVisible) {
        block.classList.remove('cc-shell-hidden');
      } else {
        block.classList.add('cc-shell-hidden');
      }
    });

    // İkonu güncelle
    if (icon) {
      if (shellVisible) {
        icon.classList.remove('fa-terminal');
        icon.classList.add('fa-terminal');
        el.title = 'Kabuk komutlarını gizle';
        el.classList.remove('cc-shell-toggle-off');
      } else {
        el.title = 'Kabuk komutlarını göster';
        el.classList.add('cc-shell-toggle-off');
      }
    }
  };

  // ---------------------------------------------------------------------------
  // CANLI AKIŞ PARÇASI EKLEME
  // Sunucudan gelen parçaları gerçek zamanlı olarak çıktı alanına ekler.
  // ---------------------------------------------------------------------------
  Shiny.addCustomMessageHandler('cc-stream-chunk', function(data) {
    var target = document.getElementById(data.target);
    if (!target) return;

    // Karşılama ekranını gizle
    if (data.welcomeId) {
      var welcome = document.getElementById(data.welcomeId);
      if (welcome && welcome.classList.contains('cc-welcome-active')) {
        welcome.classList.remove('cc-welcome-active');
        if (typeof window.ccStopWelcome === 'function') {
          window.ccStopWelcome();
        }
      }
    }

    var tip = data.chunkType || '';

    if (tip === 'tool_use') {
      // Yeni araç kullanımı bloğu ekle
      handleToolUseChunk(target, data);
    } else if (tip === 'tool_result') {
      // Mevcut araç bloğuna sonucu ekle
      handleToolResultChunk(target, data);
    } else if (tip === 'text' || tip === 'raw_text') {
      // Metin parçasını mevcut asistan mesajına ekle
      handleTextChunk(target, data);
    }

    // Otomatik kaydır
    scrollToBottom(target);
  });

  // ---------------------------------------------------------------------------
  // ARAÇ KULLANIMI BLOĞU EKLEME
  // Yeni bir kabuk komutu veya dosya işlemi bloğu oluşturur.
  // ---------------------------------------------------------------------------
  function handleToolUseChunk(target, data) {
    // Aktif mesaj konteynerini bul veya oluştur
    var msgContainer = getOrCreateStreamingMessage(target, data);

    // Araç bölümünü bul veya oluştur
    var toolSection = msgContainer.querySelector('.cc-tool-section');
    if (!toolSection) {
      toolSection = document.createElement('div');
      toolSection.className = 'cc-tool-section';
      toolSection.innerHTML =
        '<div class="cc-tool-section-header">' +
        '<i class="fas fa-cogs"></i> Araç Kullanımları ' +
        '<span class="cc-tool-count">(0)</span>' +
        '<span class="cc-tool-toggle-all" onclick="window.ccToggleAllTools(this)" ' +
        'title="Tümünü gizle/göster"><i class="fas fa-eye"></i></span>' +
        '<span class="cc-shell-visibility-toggle" ' +
        'onclick="window.ccToggleShellVisibility(this)" ' +
        'title="Kabuk komutlarını gizle/göster">' +
        '<i class="fas fa-terminal"></i></span>' +
        '</div>';
      // Araç bölümünü mesaj gövdesinin önüne ekle
      var body = msgContainer.querySelector('.cc-message-body');
      if (body) {
        msgContainer.insertBefore(toolSection, body);
      } else {
        msgContainer.appendChild(toolSection);
      }
    }

    // HTML parçasını ekle
    if (data.html) {
      var wrapper = document.createElement('div');
      wrapper.innerHTML = data.html;
      var block = wrapper.firstElementChild;
      if (block) {
        // Kabuk gizleme durumu aktifse bloğu gizle
        if (!shellVisible) {
          block.classList.add('cc-shell-hidden');
        }
        toolSection.appendChild(block);

        // Sayacı güncelle
        var count = toolSection.querySelectorAll('.cc-tool-block').length;
        var countEl = toolSection.querySelector('.cc-tool-count');
        if (countEl) {
          countEl.textContent = '(' + count + ')';
        }

        // Tıklama ile açma/kapama
        var header = block.querySelector('.cc-tool-header');
        if (header) {
          header.style.cursor = 'pointer';
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // ARAÇ SONUCU GÜNCELLEME
  // Mevcut araç bloğunun sonuç alanını günceller.
  // ---------------------------------------------------------------------------
  function handleToolResultChunk(target, data) {
    var aracId = data.toolId || '';
    if (!aracId) return;

    // Araç bloğunu ID ile bul
    var block = target.querySelector('.cc-tool-block[data-tool-id="' + aracId + '"]');
    if (!block) return;

    // Durum ikonunu güncelle (çalışıyor -> tamamlandı)
    var statusEl = block.querySelector('.cc-tool-status');
    if (statusEl) {
      statusEl.innerHTML = '<i class="fas fa-check" style="color:#81C784;"></i>';
      statusEl.classList.remove('cc-tool-running');
      statusEl.classList.add('cc-tool-done');
    }

    // Sonuç alanını güncelle
    var resultDiv = block.querySelector('.cc-tool-result');
    if (resultDiv && data.html) {
      resultDiv.classList.remove('cc-tool-result-pending');
      resultDiv.innerHTML = data.html;
    }
  }

  // ---------------------------------------------------------------------------
  // METİN PARCASI EKLEME
  // Metin parçalarını mevcut asistan mesajının gövdesine ekler.
  // ---------------------------------------------------------------------------
  function handleTextChunk(target, data) {
    var msgContainer = getOrCreateStreamingMessage(target, data);
    var body = msgContainer.querySelector('.cc-message-body');
    if (!body) return;

    // Metni birikimli olarak ekle
    var currentText = body.getAttribute('data-raw-text') || '';
    currentText += (data.html || '');
    body.setAttribute('data-raw-text', currentText);

    // Markdown'ı HTML'e dönüştür (basit düzeyde)
    body.innerHTML = currentText;
  }

  // ---------------------------------------------------------------------------
  // AKIŞ MESAJ KONTEYNERİ
  // Aktif akış mesajını bulur veya yeni bir tane oluşturur.
  // ---------------------------------------------------------------------------
  function getOrCreateStreamingMessage(target, data) {
    var streamingId = 'cc-streaming-msg';
    var existing = target.querySelector('#' + streamingId);
    if (existing) return existing;

    // Yeni asistan mesajı oluştur
    var msgDiv = document.createElement('div');
    msgDiv.id = streamingId;
    msgDiv.className = 'cc-message cc-message-assistant cc-message-streaming';

    if (data.accentColor) {
      msgDiv.style.setProperty('--cc-accent', data.accentColor);
    }

    // Başlık
    var charName = data.characterName || 'Claude Code';
    var headerHtml = '<div class="cc-message-header">' +
      '<span class="cc-message-sender" style="color:' +
      (data.accentColor || '#7C4DFF') + ';">' + charName + '</span>' +
      '<span class="cc-message-time">' + (data.timestamp || '') + '</span>' +
      '<span class="cc-streaming-indicator"><i class="fas fa-circle-notch fa-spin"></i></span>' +
      '</div>';

    // Gövde
    var bodyHtml = '<div class="cc-message-body"></div>';

    msgDiv.innerHTML = headerHtml + bodyHtml;
    target.appendChild(msgDiv);

    return msgDiv;
  }

  // ---------------------------------------------------------------------------
  // AKIŞ TAMAMLANDI
  // Akış mesajını sonlandırır, süre bilgisi ekler, kaydırma ID sini kaldırır.
  // ---------------------------------------------------------------------------
  Shiny.addCustomMessageHandler('cc-stream-end', function(data) {
    var target = document.getElementById(data.target);
    if (!target) return;

    var streamingMsg = target.querySelector('#cc-streaming-msg');
    if (streamingMsg) {
      // Akış ID sini kaldır (artık tamamlanmış mesaj)
      streamingMsg.removeAttribute('id');
      streamingMsg.classList.remove('cc-message-streaming');

      // Akış göstergesini kaldır
      var indicator = streamingMsg.querySelector('.cc-streaming-indicator');
      if (indicator) indicator.remove();

      // Süre bilgisi ekle
      if (data.duration) {
        var header = streamingMsg.querySelector('.cc-message-header');
        if (header) {
          var durationSpan = document.createElement('span');
          durationSpan.className = 'cc-message-duration';
          durationSpan.textContent = data.duration + ' sn';
          header.appendChild(durationSpan);
        }
      }

      // Mesaj gövdesini son içerikle güncelle (Markdown dönüştürme dahil)
      if (data.finalContent) {
        var body = streamingMsg.querySelector('.cc-message-body');
        if (body) {
          body.innerHTML = data.finalContent;
          body.removeAttribute('data-raw-text');
        }
      }

      // Araç bloklarındaki bekleyen sonuçları temizle
      var pendingResults = streamingMsg.querySelectorAll('.cc-tool-result-pending');
      pendingResults.forEach(function(r) {
        r.classList.remove('cc-tool-result-pending');
        var loading = r.querySelector('.cc-tool-result-loading');
        if (loading) loading.remove();
      });

      // Çalışıyor ikonlarını güncelle
      var runningStatuses = streamingMsg.querySelectorAll('.cc-tool-running');
      runningStatuses.forEach(function(s) {
        s.innerHTML = '<i class="fas fa-check" style="color:#81C784;"></i>';
        s.classList.remove('cc-tool-running');
        s.classList.add('cc-tool-done');
      });
    }

    scrollToBottom(target);
  });

  // ---------------------------------------------------------------------------
  // YARDIMCI: ALT KAYDIRMA
  // ---------------------------------------------------------------------------
  function scrollToBottom(target) {
    var wrapper = target.closest('.cc-output-wrapper');
    if (wrapper) {
      wrapper.scrollTop = wrapper.scrollHeight;
    }
  }

})();