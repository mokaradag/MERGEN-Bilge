// =============================================================================
// Dosya Yolu: www/js/claude_code_streaming.js
// Açıklama: Claude Code canlı akış desteği. Kabuk komutları, dosya işlemleri
//           ve metin parçalarını gerçek zamanlı görüntüler. Kabuk görünürlüğü
//           açma/kapama düğmesi ve dosya önizleme mantığını içerir.
// =============================================================================

(function() {
  'use strict';

  // ---------------------------------------------------------------------------
  // UTF-8 ÇİFT KODLAMA DÜZELTMESİ (MOJIBAKE FIX)
  // Windows VM'de R/Shiny, UTF-8 baytlarını Windows-1252 olarak yorumlayıp
  // tekrar UTF-8'e kodluyor. Örnek: ç (UTF-8: C3 A7) → Ã (C3) + § (A7).
  // ğ gibi harfler daha karmaşık: UTF-8 C4 9F → Ä (C4) + Ÿ (0x9F→U+0178).
  // Windows-1252'nin 0x80-0x9F aralığı Latin-1'den farklı Unicode noktalarına
  // eşlenir, bu yüzden ters dönüşüm için özel bir tablo gerekir.
  // ---------------------------------------------------------------------------

  // Windows-1252 özel aralığı: Unicode kod noktası → orijinal bayt değeri
  // 0x80-0x9F aralığındaki baytlar Windows-1252'de farklı Unicode'lara eşlenir
  var WIN1252_REVERSE = {};
  (function() {
    var map = [
      0x20AC,0x0081,0x201A,0x0192,0x201E,0x2026,0x2020,0x2021,
      0x02C6,0x2030,0x0160,0x2039,0x0152,0x008D,0x017D,0x008F,
      0x0090,0x2018,0x2019,0x201C,0x201D,0x2022,0x2013,0x2014,
      0x02DC,0x2122,0x0161,0x203A,0x0153,0x009D,0x017E,0x0178
    ];
    for (var i = 0; i < map.length; i++) {
      WIN1252_REVERSE[map[i]] = 0x80 + i;
    }
  })();

  // Unicode kod noktasını Windows-1252 bayt değerine çevirir
  function unicodeToWin1252Byte(cp) {
    if (cp < 0x80) return cp;           // ASCII: aynı
    if (cp >= 0xA0 && cp <= 0xFF) return cp; // Latin-1 supplement: aynı
    if (WIN1252_REVERSE[cp] !== undefined) return WIN1252_REVERSE[cp];
    return -1; // Bu karakter Windows-1252'de yok → mojibake değil
  }

  function fixMojibake(text) {
    if (!text || typeof text !== 'string') return text;

    // Baytlara dönüştür (Windows-1252 Unicode → orijinal bayt)
    var bytes = [];
    for (var i = 0; i < text.length; i++) {
      var b = unicodeToWin1252Byte(text.charCodeAt(i));
      if (b < 0) return text; // Windows-1252 dışı karakter → mojibake değil
      bytes.push(b);
    }

    // ASCII-only metin ise dönüşüm gereksiz
    var hasHighByte = false;
    for (var j = 0; j < bytes.length; j++) {
      if (bytes[j] >= 0x80) { hasHighByte = true; break; }
    }
    if (!hasHighByte) return text;

    try {
      var decoded = new TextDecoder('utf-8').decode(new Uint8Array(bytes));
      // Başarılı ve farklı ise kullan (replacement char U+FFFD yoksa)
      if (decoded.indexOf('\uFFFD') === -1 && decoded !== text) {
        return decoded;
      }
    } catch (e) {}
    return text;
  }

  // Diğer JS dosyalarından erişim için global yap
  window.ccFixMojibake = fixMojibake;
  window.ccFixMojibakeText = fixMojibakeText;

  // HTML içindeki metin düğümlerindeki mojibake'yi düzelt
  // HTML etiketlerine dokunmaz, sadece metin kısımlarını düzeltir
  function fixHtmlMojibake(html) {
    if (!html || typeof html !== 'string') return html;
    // HTML etiketlerini koruyarak sadece metin kısımlarını düzelt
    return html.replace(/>([^<]+)</g, function(match, textContent) {
      var fixed = fixMojibake(textContent);
      fixed = fixMojibakeText(fixed);
      return '>' + fixed + '<';
    });
  }

  // ---------------------------------------------------------------------------
  // KABUK GÖRÜNÜRLÜĞÜ DURUMU
  // Kullanıcının kabuk komutlarını gizleyip gizlemediğini takip eder.
  // ---------------------------------------------------------------------------
  var shellVisible = true;

  // ---------------------------------------------------------------------------
  // MOJIBAKE DÜZELTME HARİTASI
  // Türkçe karakter ve sık görülen emoji bozulmalarını düzeltir.
  // ---------------------------------------------------------------------------
  var MOJIBAKE_MAP = {
    "Ã§": "\u00E7",
    "Ã‡": "\u00C7",
    "Ã¶": "\u00F6",
    "Ã–": "\u00D6",
    "Ã¼": "\u00FC",
    "Ãœ": "\u00DC",
    "Ä±": "\u0131",
    "Ä°": "\u0130",
    "ÄŸ": "\u011F",
    "Äž": "\u011E",
    "ÅŸ": "\u015F",
    "Åž": "\u015E",

    "â€™": "\u2019",
    "â€˜": "\u2018",
    "â€œ": "\u201C",
    "â€": "\u201D",
    "â€“": "\u2013",
    "â€”": "\u2014",
    "â€¦": "\u2026",
    "â€¢": "\u2022",
    "â—": "\u25CF",
    "Â©": "\u00A9",
    "Â®": "\u00AE",
    "Â°": "\u00B0",
    "Â±": "\u00B1",
    "Â·": "\u00B7",
    "Â ": " ",
    "Â": "",

    "ğŸ“Œ": "\uD83D\uDCCC",
    "ðŸ“Œ": "\uD83D\uDCCC",
    "ğŸ“": "\uD83D\uDCCD",
    "ðŸ“": "\uD83D\uDCCD",
    "ğŸ“Ž": "\uD83D\uDCCE",
    "ðŸ“Ž": "\uD83D\uDCCE",
    "ğŸ“": "\uD83D\uDCC1",
    "ðŸ“": "\uD83D\uDCC1",
    "ğŸ“‚": "\uD83D\uDCC2",
    "ðŸ“‚": "\uD83D\uDCC2",
    "ğŸ“„": "\uD83D\uDCC4",
    "ðŸ“„": "\uD83D\uDCC4",
    "ğŸ“‹": "\uD83D\uDCCB",
    "ðŸ“‹": "\uD83D\uDCCB",
    "ğŸ“": "\uD83D\uDCDD",
    "ðŸ“": "\uD83D\uDCDD",
    "ğŸ“Š": "\uD83D\uDCCA",
    "ðŸ“Š": "\uD83D\uDCCA",
    "ğŸ“ˆ": "\uD83D\uDCC8",
    "ðŸ“ˆ": "\uD83D\uDCC8",
    "ğŸ“‰": "\uD83D\uDCC9",
    "ðŸ“‰": "\uD83D\uDCC9",
    "ğŸ“¦": "\uD83D\uDCE6",
    "ðŸ“¦": "\uD83D\uDCE6",
    "ğŸ“¬": "\uD83D\uDCEC",
    "ðŸ“¬": "\uD83D\uDCEC",
    "ğŸ“­": "\uD83D\uDCED",
    "ðŸ“­": "\uD83D\uDCED",
    "ğŸ“ž": "\uD83D\uDCDE",
    "ðŸ“ž": "\uD83D\uDCDE",
    "ğŸ“±": "\uD83D\uDCF1",
    "ðŸ“±": "\uD83D\uDCF1",
    "ğŸ“§": "\uD83D\uDCE7",
    "ðŸ“§": "\uD83D\uDCE7",
    "ğŸ“¨": "\uD83D\uDCE8",
    "ðŸ“¨": "\uD83D\uDCE8",
    "ğŸ“©": "\uD83D\uDCE9",
    "ðŸ“©": "\uD83D\uDCE9",
    "ğŸ“¤": "\uD83D\uDCE4",
    "ðŸ“¤": "\uD83D\uDCE4",
    "ğŸ“¥": "\uD83D\uDCE5",
    "ðŸ“¥": "\uD83D\uDCE5",

    "ğŸ”": "\uD83D\uDD0D",
    "ðŸ”": "\uD83D\uDD0D",
    "ğŸ”Ž": "\uD83D\uDD0E",
    "ðŸ”Ž": "\uD83D\uDD0E",
    "ğŸ”§": "\uD83D\uDD27",
    "ðŸ”§": "\uD83D\uDD27",
    "ğŸ”¨": "\uD83D\uDD28",
    "ðŸ”¨": "\uD83D\uDD28",
    "ğŸ”¥": "\uD83D\uDD25",
    "ðŸ”¥": "\uD83D\uDD25",
    "ğŸ”’": "\uD83D\uDD12",
    "ðŸ”’": "\uD83D\uDD12",
    "ğŸ”“": "\uD83D\uDD13",
    "ðŸ”“": "\uD83D\uDD13",
    "ğŸ”": "\uD83D\uDD10",
    "ðŸ”": "\uD83D\uDD10",
    "ğŸ”‘": "\uD83D\uDD11",
    "ðŸ”‘": "\uD83D\uDD11",
    "ğŸ””": "\uD83D\uDD14",
    "ðŸ””": "\uD83D\uDD14",
    "ğŸ”•": "\uD83D\uDD15",
    "ðŸ”•": "\uD83D\uDD15",
    "ğŸ””": "\uD83D\uDD14",
    "ðŸ””": "\uD83D\uDD14",
    "ğŸ”„": "\uD83D\uDD04",
    "ðŸ”„": "\uD83D\uDD04",
    "ğŸ”": "\uD83D\uDD01",
    "ðŸ”": "\uD83D\uDD01",
    "ğŸ”ƒ": "\uD83D\uDD03",
    "ðŸ”ƒ": "\uD83D\uDD03",
    "ğŸ”™": "\uD83D\uDD19",
    "ðŸ”™": "\uD83D\uDD19",
    "ğŸ”š": "\uD83D\uDD1A",
    "ðŸ”š": "\uD83D\uDD1A",
    "ğŸ”›": "\uD83D\uDD1B",
    "ðŸ”›": "\uD83D\uDD1B",
    "ğŸ”œ": "\uD83D\uDD1C",
    "ðŸ”œ": "\uD83D\uDD1C",

    "ğŸ’¡": "\uD83D\uDCA1",
    "ðŸ’¡": "\uD83D\uDCA1",
    "ğŸ’¥": "\uD83D\uDCA5",
    "ðŸ’¥": "\uD83D\uDCA5",
    "ğŸ’£": "\uD83D\uDCA3",
    "ðŸ’£": "\uD83D\uDCA3",
    "ğŸ’°": "\uD83D\uDCB0",
    "ðŸ’°": "\uD83D\uDCB0",
    "ğŸ’¸": "\uD83D\uDCB8",
    "ðŸ’¸": "\uD83D\uDCB8",
    "ğŸ’¬": "\uD83D\uDCAC",
    "ðŸ’¬": "\uD83D\uDCAC",
    "ğŸ’­": "\uD83D\uDCAD",
    "ðŸ’­": "\uD83D\uDCAD",
    "ğŸ’¯": "\uD83D\uDCAF",
    "ðŸ’¯": "\uD83D\uDCAF",
    "ğŸ’ª": "\uD83D\uDCAA",
    "ðŸ’ª": "\uD83D\uDCAA",
    "ğŸ’»": "\uD83D\uDCBB",
    "ðŸ’»": "\uD83D\uDCBB",
    "ğŸ’¼": "\uD83D\uDCBC",
    "ðŸ’¼": "\uD83D\uDCBC",

    "ğŸš€": "\uD83D\uDE80",
    "ðŸš€": "\uD83D\uDE80",
    "ğŸš¨": "\uD83D\uDEA8",
    "ðŸš¨": "\uD83D\uDEA8",
    "ğŸš§": "\uD83D\uDEA7",
    "ðŸš§": "\uD83D\uDEA7",
    "ğŸš«": "\uD83D\uDEAB",
    "ðŸš«": "\uD83D\uDEAB",
    "ğŸš©": "\uD83D\uDEA9",
    "ðŸš©": "\uD83D\uDEA9",
    "ğŸšª": "\uD83D\uDEAA",
    "ðŸšª": "\uD83D\uDEAA",
    "ğŸ›‘": "\uD83D\uDED1",
    "ðŸ›‘": "\uD83D\uDED1",
    "ğŸ› ë¸": "\uD83D\uDEE1\uFE0F",
    "ðŸ› ë¸": "\uD83D\uDEE1\uFE0F",
    "ğŸ›¡ï¸": "\uD83D\uDEE1\uFE0F",
    "ðŸ›¡ï¸": "\uD83D\uDEE1\uFE0F",
    "ğŸ›¡️": "\uD83D\uDEE1\uFE0F",
    "ðŸ›¡️": "\uD83D\uDEE1\uFE0F",

    "ğŸ›": "\uD83D\uDC1B",
    "ðŸ›": "\uD83D\uDC1B",
    "ğŸ": "\uD83D\uDC0D",
    "ðŸ": "\uD83D\uDC0D",
    "ğŸ¬": "\uD83D\uDC2C",
    "ðŸ¬": "\uD83D\uDC2C",
    "ğŸ³": "\uD83D\uDC33",
    "ðŸ³": "\uD83D\uDC33",
    "ğŸº": "\uD83D\uDC3A",
    "ðŸº": "\uD83D\uDC3A",

    "âš¡": "\u26A1",
    "âœ…": "\u2705",
    "âŒ": "\u274C",
    "â—": "\u2757",
    "â•": "\u2755",
    "â“": "\u2753",
    "â”": "\u2754",
    "âœ”": "\u2714",
    "âœ–": "\u2716",
    "âœ¨": "\u2728",
    "â˜…": "\u2605",
    "â˜†": "\u2606",
    "â˜…ï¸": "\u2605",
    "â˜Ž": "\u260E",
    "â˜‘": "\u2611",
    "â˜": "\u2610",
    "â˜’": "\u2612",
    "â˜…": "\u2605",
    "â˜…": "\u2605",
    "âš ": "\u26A0",
    "âš ï¸": "\u26A0\uFE0F",
    "â˜…": "\u2605",
    "â˜…": "\u2605",
    "âœˆ": "\u2708",
    "âœˆï¸": "\u2708\uFE0F",
    "âœ‰": "\u2709",
    "âœ‰ï¸": "\u2709\uFE0F",
    "â˜": "\u2601",
    "â˜€": "\u2600",
    "â˜€ï¸": "\u2600\uFE0F",
    "â˜": "\u2602",
    "â˜‚ï¸": "\u2602\uFE0F",
    "â˜ƒ": "\u2603",
    "â˜ƒï¸": "\u2603\uFE0F",

    "ï¸": "\uFE0F"
  };

  function fixMojibakeText(text) {
    if (!text) return text;

    var out = String(text);
    Object.keys(MOJIBAKE_MAP)
      .sort(function(a, b) { return b.length - a.length; })
      .forEach(function(bad) {
        out = out.split(bad).join(MOJIBAKE_MAP[bad]);
      });

    // Büyük/küçük Ş için birleşik karakter varyasyonlarını toparla
    out = out
      .replace(/S\u0327/g, '\u015E')
      .replace(/s\u0327/g, '\u015F')
      .replace(/S\u0326/g, '\u015E')
      .replace(/s\u0326/g, '\u015F');

    try {
      out = out.normalize('NFC');
    } catch (e) {}

    return out;
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
  // METİN DELTA PARCASI (stream-json formatı)
  // Metin tokenlerini anlık olarak asistan mesajının gövdesine ekler.
  // ---------------------------------------------------------------------------
  function handleTextDeltaChunk(target, data) {
    var msgContainer = getOrCreateStreamingMessage(target, data);
    var body = msgContainer.querySelector('.cc-message-body');
    if (!body) return;

    // Ham metni biriktir (mojibake varsa düzelt)
    var currentText = body.getAttribute('data-raw-text') || '';
    currentText += fixMojibake(data.html || '');
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
    currentJson += (data.html || '');
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
        escapeHtml(input.path || input.file_path) +
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
        escapeHtml(input.path || input.file_path) + '</span>';

      // Dosya içeriği önizlemesi
      var fileContent = input.content || input.new_content || '';
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
        escapeHtml(input.pattern || input.query) + '</span>';
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
    currentText += fixMojibake(data.html || '');
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