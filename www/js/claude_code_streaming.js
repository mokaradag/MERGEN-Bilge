// =============================================================================
// Dosya Yolu: www/js/claude_code_streaming.js
// Açıklama: Claude Code canlı akış desteği. Kabuk komutları, dosya işlemleri
//           ve metin parçalarını gerçek zamanlı görüntüler. Kabuk görünürlüğü
//           açma/kapama düğmesi ve dosya önizleme mantığını içerir.
// =============================================================================

(function() {
  'use strict';

  // ---------------------------------------------------------------------------
  // ORTAK KODLAMA YARDIMCISI
  // Asıl mojibake onarımı www/js/encoding_utils.js içindedir. Bu dosyada
  // yalnızca Bilge Yolaç'a özgü geriye uyumlu sarmalayıcılar tutulur.
  // ---------------------------------------------------------------------------
  function getEncodingHelper() {
    return window.MergenEncoding || {};
  }

  function fixMojibake(text) {
    var helper = getEncodingHelper();
    if (typeof helper.fixMojibake === 'function') {
      return helper.fixMojibake(text);
    }
    return text;
  }

  function fixMojibakeText(text) {
    var helper = getEncodingHelper();
    if (typeof helper.fixMojibakeText === 'function') {
      return helper.fixMojibakeText(text);
    }
    return text;
  }

  function normalizeMojibakeText(text) {
    var helper = getEncodingHelper();
    if (typeof helper.normalizeText === 'function') {
      return helper.normalizeText(text);
    }
    return fixMojibakeText(fixMojibake(text));
  }

  // Eski çağrı noktaları için global isimleri koru.
  window.ccFixMojibake = window.ccFixMojibake || fixMojibake;
  window.ccFixMojibakeText = window.ccFixMojibakeText || fixMojibakeText;

  function fixHtmlMojibake(html) {
    var helper = getEncodingHelper();
    if (typeof helper.fixHtmlTextMojibake === 'function') {
      return helper.fixHtmlTextMojibake(html);
    }

    if (!html || typeof html !== 'string') return html;
    return html.replace(/>([^<]+)</g, function(match, textContent) {
      return '>' + normalizeMojibakeText(textContent) + '<';
    });
  }

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
    } else if (tip === 'text_delta') {
      // Metin parçası (stream-json formatından anlık gelen token)
      handleTextDeltaChunk(target, data);
    } else if (tip === 'tool_input_delta') {
      // Araç girdisi delta (komut bilgisi parça parça geliyor)
      handleToolInputDelta(target, data);
    } else if (tip === 'content_block_stop') {
      // İçerik bloğu tamamlandı
      handleContentBlockStop(target, data);
    } else if (tip === 'text' || tip === 'raw_text' || tip === 'result') {
      // Eski format: tam metin parçası
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
      wrapper.innerHTML = fixHtmlMojibake(data.html);
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
  function findToolBlockById(target, toolId) {
    if (!target || !toolId) return null;

    var blocks = target.querySelectorAll('.cc-tool-block[data-tool-id]');
    for (var i = 0; i < blocks.length; i++) {
      if (blocks[i].getAttribute('data-tool-id') === toolId) {
        return blocks[i];
      }
    }

    return null;
  }

  function handleToolResultChunk(target, data) {
    var aracId = data.toolId || '';
    if (!aracId) return;

    // Araç bloğunu ID ile bul
    var block = findToolBlockById(target, aracId);
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
      resultDiv.innerHTML = fixHtmlMojibake(data.html);
    }
  }

  // ---------------------------------------------------------------------------
  // METİN DELTA PARCASI (stream-json formatı)
  // Metin tokenlerini anlık olarak asistan mesajının gövdesine ekler.
  // ---------------------------------------------------------------------------
  function handleTextDeltaChunk(target, data) {
    var msgContainer = getOrCreateStreamingMessage(target, data);
    var body = msgContainer.querySelector('.cc-message-body');
    if (!body) return;

    // Ham metni biriktir (mojibake varsa düzelt)
    var currentText = body.getAttribute('data-raw-text') || '';
    currentText += normalizeMojibakeText(data.html || '');
    body.setAttribute('data-raw-text', currentText);

    // Basit metin olarak göster (son biçimleme cc-stream-end ile yapılır)
    body.innerHTML = simpleMarkdownToHtml(currentText);
  }

  // ---------------------------------------------------------------------------
  // ARAÇ GİRDİSİ DELTA
  // Araç girdisi JSON parçasını biriktirerek komut bilgisini günceller.
  // Bu sayede kabuk komutu yazılırken kullanıcı canlı olarak görebilir.
  // ---------------------------------------------------------------------------
  function handleToolInputDelta(target, data) {
    var msgContainer = target.querySelector('#cc-streaming-msg');
    if (!msgContainer) return;

    // Son araç bloğunu bul
    var toolBlocks = msgContainer.querySelectorAll('.cc-tool-block');
    if (toolBlocks.length === 0) return;
    var lastBlock = toolBlocks[toolBlocks.length - 1];

    // JSON parçasını biriktir
    var currentJson = lastBlock.getAttribute('data-input-json') || '';
    currentJson += normalizeMojibakeText(data.html || '');
    lastBlock.setAttribute('data-input-json', currentJson);

    // Komutu canlı göster (JSON tamamlanmamış olsa da)
    var komut = extractCommandFromPartialJson(currentJson);
    if (komut) {
      var cmdEl = lastBlock.querySelector('.cc-tool-command');
      if (!cmdEl) {
        // Komut alanı yoksa oluştur
        var contentDiv = lastBlock.querySelector('.cc-tool-content');
        if (!contentDiv) {
          contentDiv = document.createElement('div');
          contentDiv.className = 'cc-tool-content cc-shell-content';
          var resultDiv = lastBlock.querySelector('.cc-tool-result');
          if (resultDiv) {
            lastBlock.insertBefore(contentDiv, resultDiv);
          } else {
            lastBlock.appendChild(contentDiv);
          }
        }
        contentDiv.innerHTML =
          '<code class="cc-tool-command cc-shell-command">' +
          '<span class="cc-shell-prompt">$ </span>' +
          '<span class="cc-cmd-text"></span>' +
          '<span class="cc-typing-cursor">|</span>' +
          '</code>';
        cmdEl = contentDiv.querySelector('.cc-cmd-text');
      } else {
        // Mevcut komut elemanı - sadece metin kısmını güncelle
        var cmdText = cmdEl.querySelector('.cc-cmd-text');
        if (cmdText) cmdEl = cmdText;
      }
      if (cmdEl) {
        cmdEl.textContent = komut;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // İÇERİK BLOĞU TAMAMLANDI
  // Araç girdisi deltası tamamlandığında son durumu günceller.
  // ---------------------------------------------------------------------------
  function handleContentBlockStop(target, data) {
    var msgContainer = target.querySelector('#cc-streaming-msg');
    if (!msgContainer) return;

    // Yazma imlecini kaldır
    var cursors = msgContainer.querySelectorAll('.cc-typing-cursor');
    cursors.forEach(function(c) { c.remove(); });

    // Son araç bloğunun girdisini tamamla
    var toolBlocks = msgContainer.querySelectorAll('.cc-tool-block');
    if (toolBlocks.length === 0) return;
    var lastBlock = toolBlocks[toolBlocks.length - 1];

    var inputJson = lastBlock.getAttribute('data-input-json') || '';
    if (inputJson) {
      // JSON tamamlandı - dosya yolunu veya aramayı göster
      try {
        var parsed = JSON.parse(inputJson);
        updateToolBlockWithInput(lastBlock, parsed);
      } catch (e) {
        // JSON ayrıştırılamazsa mevcut görünümü koru
      }
      lastBlock.removeAttribute('data-input-json');
    }
  }

  // ---------------------------------------------------------------------------
  // ARAÇ BLOĞUNU GİRDİ İLE GÜNCELLE
  // Tamamlanmış araç girdisine göre dosya yolu, arama deseni vb. gösterir.
  // ---------------------------------------------------------------------------
  function updateToolBlockWithInput(block, input) {
    var toolType = block.getAttribute('data-tool-type') || 'other';
    var contentDiv = block.querySelector('.cc-tool-content');

    if (toolType === 'file_read' && (input.path || input.file_path)) {
      // Dosya okuma - dosya yolunu göster
      if (!contentDiv) {
        contentDiv = document.createElement('div');
        contentDiv.className = 'cc-tool-content';
        var resultDiv = block.querySelector('.cc-tool-result');
        if (resultDiv) block.insertBefore(contentDiv, resultDiv);
        else block.appendChild(contentDiv);
      }
      contentDiv.innerHTML =
        '<span class="cc-tool-path">' +
        '<i class="fas fa-file-code cc-tool-path-icon"></i> ' +
        escapeHtml(normalizeMojibakeText(input.path || input.file_path)) +
        '</span>';

    } else if (toolType === 'file_write' && (input.path || input.file_path)) {
      // Dosya yazma - dosya yolu ve önizleme
      if (!contentDiv) {
        contentDiv = document.createElement('div');
        contentDiv.className = 'cc-tool-content';
        var resultDiv = block.querySelector('.cc-tool-result');
        if (resultDiv) block.insertBefore(contentDiv, resultDiv);
        else block.appendChild(contentDiv);
      }
      var html = '<span class="cc-tool-path">' +
        '<i class="fas fa-pen cc-tool-path-icon"></i> ' +
        escapeHtml(normalizeMojibakeText(input.path || input.file_path)) + '</span>';

      // Dosya içeriği önizlemesi
      var fileContent = normalizeMojibakeText(input.content || input.new_content || '');
      if (fileContent) {
        var lines = fileContent.split('\n');
        var preview = lines.slice(0, 10).join('\n');
        if (lines.length > 10) {
          preview += '\n... (+' + (lines.length - 10) + ' satır daha)';
        }
        html += '<div class="cc-file-preview">' +
          '<div class="cc-file-preview-header">' +
          '<i class="fas fa-eye"></i> Dosya Önizlemesi</div>' +
          '<pre class="cc-file-preview-content">' +
          escapeHtml(preview) + '</pre></div>';
      }
      contentDiv.innerHTML = html;

    } else if (toolType === 'search' && (input.pattern || input.query)) {
      // Arama
      if (!contentDiv) {
        contentDiv = document.createElement('div');
        contentDiv.className = 'cc-tool-content';
        var resultDiv = block.querySelector('.cc-tool-result');
        if (resultDiv) block.insertBefore(contentDiv, resultDiv);
        else block.appendChild(contentDiv);
      }
      contentDiv.innerHTML =
        '<span class="cc-tool-path">' +
        '<i class="fas fa-search cc-tool-path-icon"></i> ' +
        escapeHtml(normalizeMojibakeText(input.pattern || input.query)) + '</span>';
    }
    // bash komutu zaten handleToolInputDelta ile gösterildi
  }

  // ---------------------------------------------------------------------------
  // METİN PARCASI EKLEME (eski format)
  // Tam metin parçalarını mevcut asistan mesajının gövdesine ekler.
  // ---------------------------------------------------------------------------
  function handleTextChunk(target, data) {
    var msgContainer = getOrCreateStreamingMessage(target, data);
    var body = msgContainer.querySelector('.cc-message-body');
    if (!body) return;

    // Metni birikimli olarak ekle
    var currentText = body.getAttribute('data-raw-text') || '';
    currentText += normalizeMojibakeText(data.html || '');
    body.setAttribute('data-raw-text', currentText);

    body.innerHTML = simpleMarkdownToHtml(currentText);
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
    var charName = normalizeMojibakeText(data.characterName || 'Claude Code');
    var timestamp = normalizeMojibakeText(data.timestamp || '');
    var headerHtml = '<div class="cc-message-header">' +
      '<span class="cc-message-sender" style="color:' +
      (data.accentColor || '#7C4DFF') + ';">' + charName + '</span>' +
      '<span class="cc-message-time">' + timestamp + '</span>' +
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

    // Akış mesajı hiç oluşturulamadıysa ve son içerik varsa,
    // yedek olarak tamamlanmış bir mesaj oluştur
    if (!streamingMsg && data.finalContent) {
      streamingMsg = document.createElement('div');
      streamingMsg.className = 'cc-message cc-message-assistant';
      if (data.accentColor) {
        streamingMsg.style.setProperty('--cc-accent', data.accentColor);
      }
      var charName = data.characterName || 'Claude Code';
      var headerHtml = '<div class="cc-message-header">' +
        '<span class="cc-message-sender" style="color:' +
        (data.accentColor || '#7C4DFF') + ';">' + charName + '</span>' +
        '</div>';
      streamingMsg.innerHTML = headerHtml + '<div class="cc-message-body"></div>';
      target.appendChild(streamingMsg);
    }

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

      // Mesaj gövdesini son içerikle güncelle
      // HTML içindeki metin düğümlerinde mojibake düzeltmesi uygula
      if (data.finalContent) {
        var body = streamingMsg.querySelector('.cc-message-body');
        if (body) {
          body.innerHTML = fixHtmlMojibake(data.finalContent);
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
  // YARDIMCI: KISMI JSON'DAN KOMUT ÇIKARMA
  // Henüz tamamlanmamış JSON'dan "command" alanını çıkarmaya çalışır.
  // ---------------------------------------------------------------------------
  function extractCommandFromPartialJson(partialJson) {
    // Tamamlanmış JSON ise ayrıştır
    try {
      var obj = JSON.parse(partialJson);
      return obj.command || obj.cmd || null;
    } catch (e) {
      // Tamamlanmamış - regex ile çıkarmayı dene
      var match = partialJson.match(/"(?:command|cmd)"\s*:\s*"((?:[^"\\]|\\.)*)"/);
      if (match) return match[1].replace(/\\"/g, '"').replace(/\\\\/g, '\\');

      // Hala yazılıyor olabilir - açık tırnak arasındaki metni al
      var partialMatch = partialJson.match(/"(?:command|cmd)"\s*:\s*"((?:[^"\\]|\\.)*)$/);
      if (partialMatch) return partialMatch[1].replace(/\\"/g, '"').replace(/\\\\/g, '\\');

      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // YARDIMCI: HTML KAÇIŞ
  // ---------------------------------------------------------------------------
  function escapeHtml(text) {
    var div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  // ---------------------------------------------------------------------------
  // YARDIMCI: BASİT MARKDOWN -> HTML DÖNÜŞÜMÜ
  // Akış sırasında ham metni okunabilir HTML'e çevirir.
  // ---------------------------------------------------------------------------
  function simpleMarkdownToHtml(text) {
    if (!text) return '';

    text = fixMojibakeText(text);

    // Kod bloklarını koru (```)
    var codeBlocks = [];
    text = text.replace(/```(\w*)\n([\s\S]*?)```/g, function(match, lang, code) {
      var idx = codeBlocks.length;
      codeBlocks.push('<pre class="cc-code-block"><code>' + escapeHtml(code.trim()) + '</code></pre>');
      return '___CODE_BLOCK_' + idx + '___';
    });

    // Satır içi kod
    text = text.replace(/`([^`]+)`/g, '<code>$1</code>');

    // Kalın
    text = text.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');

    // İtalik
    text = text.replace(/\*(.+?)\*/g, '<em>$1</em>');

    // Başlıklar
    text = text.replace(/^### (.+)$/gm, '<h4>$1</h4>');
    text = text.replace(/^## (.+)$/gm, '<h3>$1</h3>');
    text = text.replace(/^# (.+)$/gm, '<h2>$1</h2>');

    // Satır sonlarını <br> ile değiştir (paragraf ayrımı)
    text = text.replace(/\n\n/g, '</p><p>');
    text = text.replace(/\n/g, '<br>');

    // Kod bloklarını geri koy
    for (var i = 0; i < codeBlocks.length; i++) {
      text = text.replace('___CODE_BLOCK_' + i + '___', codeBlocks[i]);
    }

    return '<p>' + text + '</p>';
  }

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