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
  
  try {
    // Canvas oluştur ve görseli çiz
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');
    
    // Görsel yüklenmişse boyutları al
    const tempImg = new Image();
    tempImg.crossOrigin = 'anonymous';
    
    tempImg.onload = async function() {
      canvas.width = tempImg.naturalWidth;
      canvas.height = tempImg.naturalHeight;
      ctx.drawImage(tempImg, 0, 0);
      
      try {
        // Canvas'ı blob'a dönüştür
        const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/png'));
        
        // Clipboard API ile kopyala
        await navigator.clipboard.write([
          new ClipboardItem({ 'image/png': blob })
        ]);
        
        showToast('Görsel panoya kopyalandı', 'success');
      } catch (clipboardErr) {
        console.error('[IMAGE_TOOLS] Clipboard hatası:', clipboardErr);
        showToast('Kopyalama başarısız. Tarayıcı izni gerekebilir.', 'error');
      }
    };
    
    tempImg.onerror = function() {
      showToast('Görsel yüklenemedi', 'error');
    };
    
    tempImg.src = img.src;
    
  } catch (err) {
    console.error('[IMAGE_TOOLS] Kopyalama hatası:', err);
    showToast('Kopyalama başarısız', 'error');
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
  
  // Yazdırma penceresi oluştur
  const printWindow = window.open('', '_blank');
  if (!printWindow) {
    showToast('Açılır pencere engellendi', 'error');
    return;
  }
  
  const printContent = `
    <!DOCTYPE html>
    <html>
    <head>
      <title>MERGEN Bilge - Görsel Yazdır</title>
      <style>
        body {
          margin: 0;
          padding: 20px;
          display: flex;
          flex-direction: column;
          align-items: center;
          font-family: Arial, sans-serif;
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
          body { padding: 0; }
          .watermark { display: none; }
        }
      </style>
    </head>
    <body>
      <img src="${img.src}" onload="window.print(); window.close();" />
      <p class="watermark">MERGEN Bilge ile oluşturuldu</p>
    </body>
    </html>
  `;
  
  printWindow.document.write(printContent);
  printWindow.document.close();
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
  const settingsSize = document.getElementById('settings_module-image_size');
  const settingsQuality = document.getElementById('settings_module-image_quality_hd');
  
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
  
  // Görsel modu aktif/pasif mesajı
  Shiny.addCustomMessageHandler('toggleImageMode', function(data) {
    window.toggleImageControls(data.active);
  });
}

console.log('[IMAGE_TOOLS] Görsel araçları yüklendi');