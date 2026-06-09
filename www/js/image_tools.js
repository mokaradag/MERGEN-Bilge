/* ==============================================================================
 * www/js/image_tools.js
 * Görsel oluşturma araçları için JavaScript fonksiyonları
 * İndirme, kopyalama ve yazdırma işlemleri
 * ============================================================================== */

// ------------------------------------------------------------------------------
// GÖRSEL İNDİRME
// ------------------------------------------------------------------------------

/**
 * Oluşturulan görseli indir
 * @param {HTMLElement} button - Tıklanan buton elementi
 */
window.downloadGeneratedImage = function(button) {
  const container = button.closest('.generated-image-container');
  if (!container) {
    console.error('[IMAGE_TOOLS] Container bulunamadı');
    return;
  }
  
  const img = container.querySelector('.generated-image');
  if (!img || !img.src) {
    showToast('Görsel bulunamadı', 'error');
    return;
  }
  
  // Dosya adı oluştur
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const filename = `mergen_bilge_${timestamp}.png`;
  
  // Base64 ise doğrudan indir
  if (img.src.startsWith('data:')) {
    const link = document.createElement('a');
    link.href = img.src;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    showToast('Görsel indiriliyor...', 'success');
    return;
  }
  
  // URL ise fetch ile indir
  fetch(img.src)
    .then(response => response.blob())
    .then(blob => {
      const url = window.URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = filename;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      window.URL.revokeObjectURL(url);
      showToast('Görsel indiriliyor...', 'success');
    })
    .catch(err => {
      console.error('[IMAGE_TOOLS] İndirme hatası:', err);
      showToast('Görsel indirilemedi', 'error');
    });
};

// ------------------------------------------------------------------------------
// GÖRSEL KOPYALAMA
// ------------------------------------------------------------------------------

/**
 * Data URL'i Blob'a dönüştür
 * @param {string} dataUrl - data:image/... biçimindeki kaynak
 * @returns {Blob}
 */
window.dataUrlToBlob = function(dataUrl) {
  var parts = String(dataUrl || '').split(',');
  var header = parts[0] || '';
  var data = parts[1] || '';
  var mimeMatch = header.match(/data:([^;]+);base64/i);
  var mimeType = mimeMatch ? mimeMatch[1] : 'image/png';

  var binary = atob(data);
  var len = binary.length;
  var bytes = new Uint8Array(len);

  for (var i = 0; i < len; i++) {
    bytes[i] = binary.charCodeAt(i);
  }

  return new Blob([bytes], { type: mimeType });
};

/**
 * HTML içeriğini panoya kopyala
 * @param {string} html - HTML yükü
 * @param {string} plainText - Düz metin yedeği
 * @returns {Promise<void>}
 */
window.copyHtmlToClipboard = function(html, plainText) {
  return new Promise(function(resolve, reject) {
    var tamamlandi = false;

    function temizle() {
      document.removeEventListener('copy', onCopy, true);
    }

    function onCopy(e) {
      try {
        if (e.clipboardData) {
          e.clipboardData.setData('text/html', html);
          e.clipboardData.setData('text/plain', plainText || '');
          e.preventDefault();
          tamamlandi = true;
          temizle();
          resolve();
        }
      } catch (err) {
        temizle();
        reject(err);
      }
    }

    document.addEventListener('copy', onCopy, true);

    try {
      var basarili = document.execCommand('copy');

      if (tamamlandi) {
        return;
      }

      temizle();

      if (basarili) {
        resolve();
      } else {
        reject(new Error('HTML copy basarisiz'));
      }
    } catch (err) {
      temizle();
      reject(err);
    }
  });
};

/**
 * Görsel elemanından gömülü HTML yükü üret
 * @param {HTMLImageElement} img - Görsel elemanı
 * @returns {string}
 */
window.buildEmbeddedImageHtml = function(img) {
  var srcToUse = img.src || '';

  try {
    if (img.complete && img.naturalWidth > 0 && img.naturalHeight > 0) {
      var canvas = document.createElement('canvas');
      var ctx = canvas.getContext('2d');

      canvas.width = img.naturalWidth;
      canvas.height = img.naturalHeight;
      ctx.drawImage(img, 0, 0);

      srcToUse = canvas.toDataURL('image/png');
    }
  } catch (err) {
    console.warn('[IMAGE_TOOLS] HTML kopyası için canvas üretilemedi:', err);
  }

  var escapedSrc = String(srcToUse)
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');

  return '<img src="' + escapedSrc + '" alt="MERGEN Bilge" />';
};

/**
 * Oluşturulan görseli panoya kopyala
 * @param {HTMLElement} button - Tıklanan buton elementi
 */
window.copyGeneratedImage = async function(button) {
  const container = button.closest('.generated-image-container');
  if (!container) {
    showToast('Görsel bulunamadı', 'error');
    return;
  }

  const img = container.querySelector('.generated-image');
  if (!img || !img.src) {
    showToast('Görsel bulunamadı', 'error');
    return;
  }

  if (!img.complete || img.naturalWidth <= 0 || img.naturalHeight <= 0) {
    showToast('Görsel henüz tam yüklenmedi', 'warning');
    return;
  }

  try {
    var gercekGorselKopyasiDestekli =
      window.isSecureContext &&
      navigator.clipboard &&
      typeof navigator.clipboard.write === 'function' &&
      typeof window.ClipboardItem !== 'undefined';

    // Önce gerçek bitmap kopyalamayı dene
    if (gercekGorselKopyasiDestekli) {
      try {
        let blob = null;

        if (img.src.startsWith('data:image/')) {
          blob = window.dataUrlToBlob(img.src);
        } else {
          try {
            const canvas = document.createElement('canvas');
            const ctx = canvas.getContext('2d');

            canvas.width = img.naturalWidth;
            canvas.height = img.naturalHeight;
            ctx.drawImage(img, 0, 0);

            const pngDataUrl = canvas.toDataURL('image/png');
            blob = window.dataUrlToBlob(pngDataUrl);
          } catch (canvasErr) {
            console.warn('[IMAGE_TOOLS] Canvas yolu başarısız, fetch denenecek:', canvasErr);

            const response = await fetch(img.src, { credentials: 'same-origin' });
            if (!response.ok) {
              throw new Error('Gorsel verisi alinamadi');
            }
            blob = await response.blob();
          }
        }

        if (blob && blob.size) {
          await navigator.clipboard.write([
            new ClipboardItem({
              [blob.type || 'image/png']: blob
            })
          ]);

          showToast('Görsel panoya kopyalandı', 'success');
          return;
        }
      } catch (binaryErr) {
        console.warn('[IMAGE_TOOLS] Gerçek görsel kopyalama başarısız, HTML yolu denenecek:', binaryErr);
      }
    }

    // HTTP / güvenli olmayan bağlam için HTML tabanlı yedek yol
    try {
      var htmlPayload = window.buildEmbeddedImageHtml(img);
      await window.copyHtmlToClipboard(
        htmlPayload,
        'MERGEN Bilge görseli'
      );

      showToast(
        'Görsel HTML olarak panoya kopyalandı. Word/PowerPoint deneyin; Paint desteklemeyebilir.',
        'success'
      );
      return;

    } catch (htmlErr) {
      console.error('[IMAGE_TOOLS] HTML kopyalama hatası:', htmlErr);
    }

    if (!window.isSecureContext) {
      showToast(
        'HTTP oturumlarında gerçek görsel kopyalama tarayıcı tarafından kısıtlanabilir. HTTPS üretimde tam destek verecektir.',
        'error'
      );
      return;
    }

    showToast('Kopyalama başarısız. Tarayıcı izni gerekebilir.', 'error');

  } catch (err) {
    console.error('[IMAGE_TOOLS] Kopyalama hatası:', err);
    showToast('Kopyalama başarısız. Tarayıcı izni gerekebilir.', 'error');
  }
};

// ------------------------------------------------------------------------------
// GÖRSEL YAZDIRMA
// ------------------------------------------------------------------------------

/**
 * Oluşturulan görseli yazdır
 * @param {HTMLElement} button - Tıklanan buton elementi
 */
window.printGeneratedImage = function(button) {
  const container = button.closest('.generated-image-container');
  if (!container) {
    showToast('Görsel bulunamadı', 'error');
    return;
  }

  const img = container.querySelector('.generated-image');
  if (!img || !img.src) {
    showToast('Görsel bulunamadı', 'error');
    return;
  }

  // Yazdırma penceresi oluştur. Pencereyi otomatik kapatmak bazı tarayıcılarda
  // yazdırma diyaloğu açılmadan sekmenin anlık kapanmasına/flicker'a yol açıyor;
  // bu nedenle pencere açık bırakılır ve kullanıcı normal şekilde kapatabilir.
  const printWindow = window.open('', '_blank');
  if (!printWindow) {
    showToast('Açılır pencere engellendi', 'error');
    return;
  }

  const printDoc = printWindow.document;
  const safeTitle = 'MERGEN Bilge - Görsel Yazdır';

  printDoc.open();
  printDoc.write(`
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <title>${safeTitle}</title>
      <style>
        body {
          margin: 0;
          padding: 20px;
          min-height: 100vh;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          font-family: Arial, sans-serif;
          background: #fff;
        }
        img {
          max-width: 100%;
          max-height: 90vh;
          object-fit: contain;
        }
        .watermark {
          margin-top: 10px;
          font-size: 12px;
          color: #666;
        }
        @media print {
          body { padding: 0; min-height: auto; }
          .watermark { display: none; }
        }
      </style>
    </head>
    <body></body>
    </html>
  `);
  printDoc.close();

  const printableImg = printDoc.createElement('img');
  printableImg.alt = img.alt || 'Oluşturulan görsel';
  printableImg.src = img.src;

  const watermark = printDoc.createElement('p');
  watermark.className = 'watermark';
  watermark.textContent = 'MERGEN Bilge ile oluşturuldu';

  printDoc.body.appendChild(printableImg);
  printDoc.body.appendChild(watermark);

  const triggerPrint = function() {
    printWindow.focus();
    printWindow.setTimeout(function() {
      printWindow.print();
    }, 150);
  };

  if (printableImg.complete && printableImg.naturalWidth > 0) {
    triggerPrint();
  } else {
    printableImg.addEventListener('load', triggerPrint, { once: true });
    printableImg.addEventListener('error', function() {
      showToast('Görsel yazdırmaya hazırlanamadı', 'error');
    }, { once: true });
  }
};

// ------------------------------------------------------------------------------
// GÖRSEL KONTROL PANELİ YÖNETİMİ
// ------------------------------------------------------------------------------

/**
 * Görsel araçları moduna göre kontrol panelini göster/gizle
 * @param {boolean} show - Göster/gizle
 */
window.toggleImageControls = function(show) {
  const controls = document.getElementById('image_chat_controls');
  if (controls) {
    if (show) {
      controls.classList.remove('hidden');
    } else {
      controls.classList.add('hidden');
    }
  }
};

/**
 * Görsel ayarlarını al
 * @returns {Object} - { size: string, quality: string }
 */
window.getImageSettings = function() {
  const sizeSelect = document.getElementById('chat_image_size');
  const qualityCheckbox = document.getElementById('chat_image_quality_hd');
  
  return {
    size: sizeSelect ? sizeSelect.value : '1024x1024',
    quality: (qualityCheckbox && qualityCheckbox.checked) ? 'hd' : 'standard'
  };
};

// ------------------------------------------------------------------------------
// AYARLAR SENKRONİZASYONU
// ------------------------------------------------------------------------------

/**
 * Sohbet ve Ayarlar sayfası arasında görsel ayarlarını senkronize et
 */
window.syncImageSettings = function(source) {
  const chatSize = document.getElementById('chat_image_size');
  const chatQuality = document.getElementById('chat_image_quality_hd');
  const settingsSize = document.getElementById('settings_yapilandirma_module-image_size');
  const settingsQuality = document.getElementById('settings_yapilandirma_module-image_quality_hd');
  
  if (source === 'chat') {
    // Sohbetten Ayarlara
    if (settingsSize && chatSize) {
      settingsSize.value = chatSize.value;
      $(settingsSize).trigger('change');
    }
    if (settingsQuality && chatQuality) {
      settingsQuality.checked = chatQuality.checked;
      $(settingsQuality).trigger('change');
    }
  } else if (source === 'settings') {
    // Ayarlardan Sohbete
    if (chatSize && settingsSize) {
      chatSize.value = settingsSize.value;
    }
    if (chatQuality && settingsQuality) {
      chatQuality.checked = settingsQuality.checked;
    }
  }
};

// Olay dinleyicileri ekle
document.addEventListener('DOMContentLoaded', function() {
  // Sohbet kontrollerinden değişiklik
  const chatSize = document.getElementById('chat_image_size');
  const chatQuality = document.getElementById('chat_image_quality_hd');
  
  if (chatSize) {
    chatSize.addEventListener('change', function() {
      window.syncImageSettings('chat');
      // Shiny'ye bildir
      if (window.Shiny) {
        Shiny.setInputValue('chat_image_size', this.value, {priority: 'event'});
      }
    });
  }
  
  if (chatQuality) {
    chatQuality.addEventListener('change', function() {
      window.syncImageSettings('chat');
      if (window.Shiny) {
        Shiny.setInputValue('chat_image_quality_hd', this.checked, {priority: 'event'});
      }
    });
  }
});

// Shiny mesaj işleyicisi - Ayarlar sayfasından senkronizasyon
if (window.Shiny) {
  Shiny.addCustomMessageHandler('syncImageSettingsToChat', function(data) {
    const chatSize = document.getElementById('chat_image_size');
    const chatQuality = document.getElementById('chat_image_quality_hd');
    
    if (chatSize && data.size) {
      chatSize.value = data.size;
    }
    if (chatQuality && typeof data.quality_hd !== 'undefined') {
      chatQuality.checked = data.quality_hd;
    }
  });
  
  // Model seçim kilidi merkezi MergenToolModelLock yöneticisine bırakılır.
  Shiny.addCustomMessageHandler('toggleImageMode', function(data) {
    window.toggleImageControls(data && data.active);

    if (window.MergenToolModelLock && typeof window.MergenToolModelLock.refresh === 'function') {
      window.MergenToolModelLock.refresh();
    }
  });
  
  // Sohbet kontrollerinden Ayarlara senkronizasyon
  Shiny.addCustomMessageHandler('syncChatImageSettingsToSettings', function(data) {
    const settingsSize = document.getElementById('settings_yapilandirma_module-image_size');
    const settingsQuality = document.getElementById('settings_yapilandirma_module-image_quality_hd');
    
    if (settingsSize && data.size) {
      settingsSize.value = data.size;
      $(settingsSize).trigger('change');
    }
    if (settingsQuality && typeof data.quality_hd !== 'undefined') {
      settingsQuality.checked = data.quality_hd;
      $(settingsQuality).trigger('change');
    }
  });
}

console.log('[IMAGE_TOOLS] Görsel araçları yüklendi');