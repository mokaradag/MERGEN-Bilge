// www/js/settings_tools.js
// Ayarlar sayfası - Analiz Araçları buton seçim ve açıklama yönetimi

(function() {
  'use strict';

  // Araç tanımları: ikon, tema rengi, açıklama
  var TOOL_DEFINITIONS = {
    enable_rdata_tools: {
      icon: 'chart-bar',
      label: 'Proje ve Kaynak Analizi',
      accent: '#06b6d4',
      rgb: '6,182,212',
      description: 'Kurumsal veri gölündeki (rData) proje ve kaynak verilerini SQL sorguları ile analiz eder. Veritabanı tablolarına doğrudan erişim sağlayarak detaylı raporlar ve istatistiksel analizler üretir.'
    },
    enable_mcp_tools: {
      icon: 'file-excel',
      label: 'Excel Analizi (MCP)',
      accent: '#10b981',
      rgb: '16,185,129',
      description: 'Model Context Protocol (MCP) aracılığıyla yüklenen Excel dosyalarını analiz eder. Dosya içeriğini otomatik olarak okur, SQL sorguları çalıştırır ve sütun istatistikleri çıkarır.'
    },
    enable_summarization_tools: {
      icon: 'file-alt',
      label: 'Dosya Özetleme',
      accent: '#a855f7',
      rgb: '168,85,247',
      description: 'Yüklenen dokümanları (PDF, DOCX, TXT) kapsamlı şekilde özetler. Önemli başlıkları, alt konuları ve sayısal verileri koruyarak kısa, standart veya detaylı özet çıkarır.'
    },
    enable_coding_tools: {
      icon: 'code',
      label: 'Kod Uzmanı',
      accent: '#f59e0b',
      rgb: '245,158,11',
      description: 'Python, R, JavaScript ve diğer dillerde kod yazma, hata ayıklama, optimizasyon ve algoritma tasarımı konusunda uzman düzeyde destek sağlar.'
    },
    enable_process_tools: {
      icon: 'briefcase',
      label: 'Süreç Yönetimi',
      accent: '#3b82f6',
      rgb: '59,130,246',
      description: 'Kurumsal süreç, izleç, rehber ve şablon dokümanları hakkında bilgi sağlar. İş akışları, standart operasyon talimatları ve şirket politikaları konusunda rehberlik eder.'
    },
    enable_app_expert_tools: {
      icon: 'window-maximize',
      label: 'Uygulama Uzmanı',
      accent: '#8b5cf6',
      rgb: '139,92,246',
      description: 'Uygulama mimarisi, API tasarımı, veritabanı şemaları ve yazılım geliştirme süreçleri konusunda derinlemesine teknik danışmanlık sunar.'
    },
    enable_image_tools: {
      icon: 'image',
      label: 'Görsel Uzmanı',
      accent: '#ec4899',
      rgb: '236,72,153',
      description: 'DALL-E modeli ile metin tabanlı açıklamalardan yapay zeka görselleri oluşturur. Farklı boyut ve kalite seçenekleri ile özelleştirilebilir.'
    }
  };

  // Yazma efekti değişkenleri
  var _typingTimer = null;
  var _typingIndex = 0;
  var _typingText = '';

  // Yazma efekti ile açıklama göster
  function typeDescription(element, text, accentColor) {
    // Önceki animasyonu iptal et
    if (_typingTimer) {
      clearInterval(_typingTimer);
      _typingTimer = null;
    }

    _typingText = text;
    _typingIndex = 0;
    element.innerHTML = '<span class="typing-cursor"></span>';

    // İmleç rengini ayarla
    var cursor = element.querySelector('.typing-cursor');
    if (cursor && accentColor) {
      cursor.style.background = accentColor;
    }

    _typingTimer = setInterval(function() {
      if (_typingIndex < _typingText.length) {
        // Her adımda 2-3 karakter ekle (hızlı yazma)
        var charsToAdd = Math.min(3, _typingText.length - _typingIndex);
        var chunk = _typingText.substring(_typingIndex, _typingIndex + charsToAdd);
        
        // İmleci kaldır, metin ekle, imleci geri koy
        var cursorEl = element.querySelector('.typing-cursor');
        if (cursorEl) cursorEl.remove();
        element.innerHTML += chunk;
        element.innerHTML += '<span class="typing-cursor" style="background:' + (accentColor || 'var(--primary-color)') + '"></span>';
        
        _typingIndex += charsToAdd;
      } else {
        clearInterval(_typingTimer);
        _typingTimer = null;
        // Animasyon bittikten sonra imleci kaldır
        var cursorEl = element.querySelector('.typing-cursor');
        if (cursorEl) {
          setTimeout(function() { cursorEl.remove(); }, 1500);
        }
      }
    }, 15);
  }

  // Buton tıklama işleyicisi
  function handleToolButtonClick(toolName, button, nsPrefix) {
    var isActive = button.classList.contains('active');
    var def = TOOL_DEFINITIONS[toolName];

    // Tüm butonları pasif yap
    var allButtons = document.querySelectorAll('.tool-select-btn');
    allButtons.forEach(function(btn) {
      btn.classList.remove('active');
    });

    // Shiny checkbox'larını güncelle - önce hepsini kapat
    Object.keys(TOOL_DEFINITIONS).forEach(function(key) {
      var cbId = nsPrefix + key;
      var cb = document.getElementById(cbId);
      if (cb) {
        cb.checked = false;
        $(cb).trigger('change');
      }
    });

    // Açıklama alanını güncelle
    var descArea = document.querySelector('.tool-desc-detail');
    
    if (!isActive) {
      // Butonu aktif yap
      button.classList.add('active');

      // İlgili checkbox'ı aç
      var cbId = nsPrefix + toolName;
      var cb = document.getElementById(cbId);
      if (cb) {
        cb.checked = true;
        $(cb).trigger('change');
      }

      // Açıklamayı yazma efekti ile göster
      if (descArea && def) {
        typeDescription(descArea, def.description, def.accent);
      }
    } else {
      // Zaten aktifti, kapat (toggle off)
      if (descArea) {
        if (_typingTimer) { clearInterval(_typingTimer); _typingTimer = null; }
        descArea.textContent = '';
      }
    }
  }

  // Checkbox değişikliklerini dinle (dışarıdan gelen güncellemeler için)
  function syncButtonsFromCheckboxes(nsPrefix) {
    Object.keys(TOOL_DEFINITIONS).forEach(function(toolName) {
      var cbId = nsPrefix + toolName;
      var cb = document.getElementById(cbId);
      if (!cb) return;

      // MutationObserver ile checkbox değişikliklerini izle
      var observer = new MutationObserver(function() {
        var btn = document.querySelector('.tool-select-btn[data-tool="' + toolName + '"]');
        if (!btn) return;
        
        if (cb.checked && !btn.classList.contains('active')) {
          // Önce diğerlerini pasif yap
          document.querySelectorAll('.tool-select-btn').forEach(function(b) {
            b.classList.remove('active');
          });
          btn.classList.add('active');
          
          var def = TOOL_DEFINITIONS[toolName];
          var descArea = document.querySelector('.tool-desc-detail');
          if (descArea && def) {
            typeDescription(descArea, def.description, def.accent);
          }
        } else if (!cb.checked && btn.classList.contains('active')) {
          btn.classList.remove('active');
        }
      });

      observer.observe(cb, { attributes: true, attributeFilter: ['checked'] });

      // change event'i de dinle (Shiny updateCheckboxInput için)
      $(cb).on('change', function() {
        setTimeout(function() {
          var btn = document.querySelector('.tool-select-btn[data-tool="' + toolName + '"]');
          if (!btn) return;
          
          if (cb.checked) {
            document.querySelectorAll('.tool-select-btn').forEach(function(b) {
              if (b !== btn) b.classList.remove('active');
            });
            btn.classList.add('active');
            var def = TOOL_DEFINITIONS[toolName];
            var descArea = document.querySelector('.tool-desc-detail');
            if (descArea && def) {
              typeDescription(descArea, def.description, def.accent);
            }
          } else {
            btn.classList.remove('active');
          }
        }, 50);
      });
    });
  }

  // Başlangıçta butonları oluştur (Shiny hazır olduğunda)
  function initToolButtons() {
    var container = document.querySelector('.tool-selector-buttons');
    if (!container || container.dataset.initialized) return;
    container.dataset.initialized = 'true';

    // NS prefix'ini checkbox'lardan çıkar
    var nsPrefix = '';
    var sampleCb = document.getElementById('settings_module-enable_rdata_tools');
    if (sampleCb) {
      nsPrefix = 'settings_module-';
    }

    container.innerHTML = '';

    Object.keys(TOOL_DEFINITIONS).forEach(function(toolName) {
      var def = TOOL_DEFINITIONS[toolName];
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'tool-select-btn';
      btn.setAttribute('data-tool', toolName);
      btn.style.setProperty('--tool-accent', def.accent);
      btn.style.setProperty('--tool-r', def.rgb.split(',')[0]);
      btn.style.setProperty('--tool-g', def.rgb.split(',')[1]);
      btn.style.setProperty('--tool-b', def.rgb.split(',')[2]);

      btn.innerHTML = '<i class="fas fa-' + def.icon + '"></i><span>' + def.label + '</span>';

      // Mevcut checkbox durumuna göre aktif yap
      var cb = document.getElementById(nsPrefix + toolName);
      if (cb && cb.checked) {
        btn.classList.add('active');
      }

      btn.addEventListener('click', function() {
        handleToolButtonClick(toolName, btn, nsPrefix);
      });

      container.appendChild(btn);
    });

    // Checkbox senkronizasyonunu başlat
    syncButtonsFromCheckboxes(nsPrefix);

    // Başlangıçta aktif olan aracın açıklamasını göster
    var activeBtn = container.querySelector('.tool-select-btn.active');
    if (activeBtn) {
      var activeTool = activeBtn.getAttribute('data-tool');
      var def = TOOL_DEFINITIONS[activeTool];
      var descArea = document.querySelector('.tool-desc-detail');
      if (descArea && def) {
        descArea.textContent = def.description;
      }
    }
  }

  // DOM hazır olduğunda başlat
  document.addEventListener('DOMContentLoaded', function() {
    // Shiny bağlantısı kurulduktan sonra başlat
    $(document).on('shiny:connected', function() {
      setTimeout(initToolButtons, 500);
    });
  });

  // Sekme değişikliğinde yeniden başlat (Ayarlar sekmesine geçiş)
  $(document).on('click', '[data-value="settings"]', function() {
    setTimeout(initToolButtons, 300);
  });
})();