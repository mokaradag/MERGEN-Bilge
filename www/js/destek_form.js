// Dosya Yolu: www/js/destek_form.js
// Açıklama: Destek sayfası form etkileşimleri.
//           Memnuniyet seçici, NPS puanlama, etiket/kategori seçimi,
//           dosya sürükle-bırak, konu ekleme/silme ve form sıfırlama işlevleri.

// ==============================================================================
// MEMNUNİYET SEÇİCİ (Tekrar tıklayarak iptal edilebilir)
// ==============================================================================

/**
 * Memnuniyet puanını seç veya iptal et (emoji butonları)
 * @param {string} inputId - Shiny gizli input ID'si
 * @param {number} value - Seçilen puan (1-5)
 */
function destekSelectSatisfaction(inputId, value) {
  var hiddenInput = document.getElementById(inputId);
  if (!hiddenInput) return;

  var container = hiddenInput.closest('.destek-form-group');
  var items = container.querySelectorAll('.destek-satisfaction-item');
  var currentValue = hiddenInput.value;

  // Aynı değere tıklanırsa iptal et (toggle)
  if (currentValue === String(value)) {
    items.forEach(function(item) {
      item.classList.remove('active');
    });
    hiddenInput.value = '';
    Shiny.setInputValue(inputId, '', {priority: 'event'});
  } else {
    // Yeni değer seç
    items.forEach(function(item) {
      item.classList.remove('active');
    });
    var selected = container.querySelector('.destek-satisfaction-item[data-value="' + value + '"]');
    if (selected) {
      selected.classList.add('active');
    }
    hiddenInput.value = value;
    Shiny.setInputValue(inputId, value, {priority: 'event'});
  }

  // Hata mesajını gizle
  var errorEl = document.getElementById(inputId.replace('memnuniyet', 'hata_memnuniyet'));
  if (errorEl) errorEl.style.display = 'none';
}

// ==============================================================================
// NPS SEÇİCİ (Tekrar tıklayarak iptal edilebilir)
// ==============================================================================

/**
 * NPS puanını seç veya iptal et (0-10 butonları)
 * @param {string} inputId - Shiny gizli input ID'si
 * @param {number} value - Seçilen puan (0-10)
 */
function destekSelectNPS(inputId, value) {
  var hiddenInput = document.getElementById(inputId);
  if (!hiddenInput) return;

  var container = hiddenInput.closest('.destek-form-group');
  var buttons = container.querySelectorAll('.destek-nps-btn');
  var currentValue = hiddenInput.value;

  // Aynı değere tıklanırsa iptal et (toggle)
  if (currentValue === String(value)) {
    buttons.forEach(function(btn) {
      btn.classList.remove('active');
    });
    hiddenInput.value = '';
    Shiny.setInputValue(inputId, '', {priority: 'event'});
  } else {
    // Yeni değer seç
    buttons.forEach(function(btn) {
      btn.classList.remove('active');
    });
    var selected = container.querySelector('.destek-nps-btn[data-value="' + value + '"]');
    if (selected) {
      selected.classList.add('active');
    }
    hiddenInput.value = value;
    Shiny.setInputValue(inputId, value, {priority: 'event'});
  }
}

// ==============================================================================
// ETİKET SEÇİCİ (Çoklu)
// ==============================================================================

/**
 * Etiket seçimini değiştir (toggle)
 * @param {HTMLElement} el - Tıklanan etiket butonu
 * @param {string} inputId - Shiny gizli input ID'si
 */
function destekToggleTag(el, inputId) {
  el.classList.toggle('active');

  // Seçili etiketleri topla
  var container = el.closest('.destek-tags-container');
  var activeTags = container.querySelectorAll('.destek-tag-btn.active');
  var values = Array.from(activeTags).map(function(btn) {
    return btn.getAttribute('data-tag');
  });

  var combinedValue = values.join(',');
  document.getElementById(inputId).value = combinedValue;
  Shiny.setInputValue(inputId, combinedValue, {priority: 'event'});
}

// ==============================================================================
// KATEGORİ SEÇİCİ (Çoklu)
// ==============================================================================

/**
 * Kategori seçimini değiştir (toggle)
 * @param {HTMLElement} el - Tıklanan kategori butonu
 * @param {string} inputId - Shiny gizli input ID'si
 */
function destekToggleCategory(el, inputId) {
  el.classList.toggle('active');

  var container = el.closest('.destek-category-container');
  var activeCategories = container.querySelectorAll('.destek-category-btn.active');
  var values = Array.from(activeCategories).map(function(btn) {
    return btn.getAttribute('data-category');
  });

  var combinedValue = values.join(',');
  document.getElementById(inputId).value = combinedValue;
  Shiny.setInputValue(inputId, combinedValue, {priority: 'event'});

  // Hata mesajını gizle
  var errorEl = document.getElementById(inputId.replace('secili_kategoriler', 'hata_kategoriler'));
  if (errorEl && values.length > 0) errorEl.style.display = 'none';
}

// ==============================================================================
// ÖNCELİK SEÇİCİ (Tekli - tekrar tıklayarak iptal edilebilir)
// ==============================================================================

/**
 * Öncelik seviyesini seç veya iptal et
 * @param {HTMLElement} el - Tıklanan öncelik butonu
 * @param {string} inputId - Shiny gizli input ID'si
 */
function destekSelectPriority(el, inputId) {
  var container = el.closest('.destek-priority-container');
  var hiddenInput = document.getElementById(inputId);
  if (!hiddenInput) return;

  var currentValue = hiddenInput.value;
  var clickedValue = el.getAttribute('data-priority');

  // Aynı değere tıklanırsa iptal et (toggle)
  if (currentValue === clickedValue) {
    container.querySelectorAll('.destek-priority-btn').forEach(function(btn) {
      btn.classList.remove('active');
    });
    hiddenInput.value = '';
    Shiny.setInputValue(inputId, '', {priority: 'event'});
  } else {
    // Yeni değer seç
    container.querySelectorAll('.destek-priority-btn').forEach(function(btn) {
      btn.classList.remove('active');
    });
    el.classList.add('active');
    hiddenInput.value = clickedValue;
    Shiny.setInputValue(inputId, clickedValue, {priority: 'event'});
  }
}

// ==============================================================================
// ONAY KUTUSU (CHECKBOX) - "0" ve "1" değerleri ile çalışır
// ==============================================================================

/**
 * İletişim izni onay kutusunu değiştir
 * @param {string} inputId - Shiny gizli input ID'si
 */
function destekToggleCheckbox(inputId) {
  var hiddenInput = document.getElementById(inputId);
  var visualCheckbox = document.getElementById(inputId.replace('iletisim_izni', 'iletisim_checkbox_visual'));

  if (!hiddenInput || !visualCheckbox) return;

  var isChecked = hiddenInput.value === '1';
  hiddenInput.value = isChecked ? '0' : '1';

  if (isChecked) {
    visualCheckbox.classList.remove('checked');
  } else {
    visualCheckbox.classList.add('checked');
  }

  Shiny.setInputValue(inputId, hiddenInput.value, {priority: 'event'});
}

// ==============================================================================
// KARAKTER SAYACI
// ==============================================================================

/**
 * Metin alanı karakter sayacını güncelle
 * @param {HTMLTextAreaElement} textarea - Metin alanı
 * @param {string} counterId - Sayaç span ID'si
 */
function destekUpdateCharCount(textarea, counterId) {
  var counter = document.getElementById(counterId);
  if (!counter) return;

  var count = textarea.value.length;
  var max = textarea.getAttribute('maxlength') || 500;
  counter.textContent = count + ' / ' + max;

  if (count > max * 0.9) {
    counter.classList.add('destek-limit-warning');
  } else {
    counter.classList.remove('destek-limit-warning');
  }
}

// ==============================================================================
// KONU EKLEME / SİLME (Dinamik "Konu" / "Konular" etiketi)
// ==============================================================================

// Konu sayacı (benzersiz ID üretimi için)
var destekKonuSayac = 1;

/**
 * Konu etiketini güncelle (tekil/çoğul)
 * @param {string} nsPrefix - Modül namespace öneki
 */
function destekUpdateKonuLabel(nsPrefix) {
  var container = document.getElementById(nsPrefix + 'konular_container');
  if (!container) return;

  var rows = container.querySelectorAll('.destek-konu-row');
  var label = document.getElementById(nsPrefix + 'konu_label');
  if (label) {
    if (rows.length > 1) {
      label.textContent = 'Konular';
    } else {
      label.textContent = 'Konu';
    }
    // CSS ::after ile yıldız ekleniyor, ek HTML gerekmez
  }
}

/**
 * Yeni konu girişi ekle
 * @param {string} nsPrefix - Modül namespace öneki
 */
function destekAddKonu(nsPrefix) {
  destekKonuSayac++;
  var container = document.getElementById(nsPrefix + 'konular_container');
  if (!container) return;

  var row = document.createElement('div');
  row.className = 'destek-konu-row';
  row.setAttribute('data-index', destekKonuSayac);

  var input = document.createElement('input');
  input.type = 'text';
  input.className = 'destek-text-input destek-konu-input';
  input.id = nsPrefix + 'konu_' + destekKonuSayac;
  input.placeholder = 'Örn: Profil resmi yüklenmiyor';
  input.maxLength = 200;
  // Her tuş vuruşunda konuları topla
  input.oninput = function() {
    destekCollectKonular(nsPrefix);
  };

  var deleteBtn = document.createElement('button');
  deleteBtn.className = 'destek-konu-sil-btn';
  deleteBtn.type = 'button';
  deleteBtn.innerHTML = '<i class="fas fa-trash"></i>';
  deleteBtn.setAttribute('data-index', destekKonuSayac);
  deleteBtn.onclick = function() {
    row.remove();
    destekCollectKonular(nsPrefix);
    destekUpdateKonuLabel(nsPrefix);
  };

  row.appendChild(input);
  row.appendChild(deleteBtn);
  container.appendChild(row);

  input.focus();

  // Etiketi güncelle
  destekUpdateKonuLabel(nsPrefix);
}

/**
 * Tüm konu girişlerini topla ve Shiny'ye gönder
 * @param {string} nsPrefix - Modül namespace öneki
 */
function destekCollectKonular(nsPrefix) {
  var container = document.getElementById(nsPrefix + 'konular_container');
  if (!container) return;

  var inputs = container.querySelectorAll('.destek-text-input');
  var values = [];
  inputs.forEach(function(input) {
    var val = input.value.trim();
    if (val) values.push(val);
  });

  var combined = values.join(' || ');
  Shiny.setInputValue(nsPrefix + 'konular_birlesik', combined, {priority: 'event'});

  // Geçerli değer varsa hata mesajını gizle
  if (combined.length > 0) {
    var errorEl = document.getElementById(nsPrefix + 'hata_konular');
    if (errorEl) errorEl.style.display = 'none';
  }
}

// ==============================================================================
// DOSYA SÜRÜKLE-BIRAK
// ==============================================================================

/**
 * Sürükle-bırak dosya işleme
 * @param {DragEvent} event - Sürükleme olayı
 * @param {string} nsPrefix - Modül namespace öneki
 */
function destekHandleDrop(event, nsPrefix) {
  event.preventDefault();
  event.currentTarget.classList.remove('destek-drag-over');

  var files = event.dataTransfer.files;
  if (!files || files.length === 0) return;

  // Shiny dosya yükleme mekanizmasını kullanarak dosyaları işle
  var fileInput = document.getElementById(nsPrefix + 'dosya_input');
  if (fileInput) {
    // DataTransfer nesnesini oluştur
    var dt = new DataTransfer();
    for (var i = 0; i < files.length; i++) {
      var file = files[i];
      // Kabul edilen dosya türlerini kontrol et
      var validTypes = ['image/png', 'image/jpeg', 'image/gif', 'video/mp4'];
      if (validTypes.indexOf(file.type) !== -1) {
        if (file.size <= 10 * 1024 * 1024) {
          dt.items.add(file);
        }
      }
    }
    fileInput.files = dt.files;
    // Change olayını tetikle (Shiny'nin dosyayı algılaması için)
    $(fileInput).trigger('change');
  }
}

/**
 * Yüklenen dosya listesini güncelle
 * @param {string} nsPrefix - Modül namespace öneki
 * @param {Array} files - Dosya bilgileri dizisi [{name, size}]
 */
function destekUpdateFileList(nsPrefix, files) {
  var listContainer = document.getElementById(nsPrefix + 'dosya_listesi');
  if (!listContainer) return;

  listContainer.innerHTML = '';

  if (!files || files.length === 0) return;

  files.forEach(function(file, index) {
    var item = document.createElement('div');
    item.className = 'destek-file-item';

    var sizeMB = (file.size / (1024 * 1024)).toFixed(2);
    var truncName = file.name.length > 30 ? file.name.substring(0, 27) + '...' : file.name;

    item.innerHTML =
      '<i class="fas fa-file destek-file-item-icon"></i>' +
      '<div class="destek-file-item-info">' +
        '<div class="destek-file-item-name">' + truncName + '</div>' +
        '<div class="destek-file-item-size">' + sizeMB + ' MB</div>' +
      '</div>' +
      '<button class="destek-file-item-remove" onclick="destekRemoveFile(\'' + nsPrefix + '\', ' + (index + 1) + ')" title="Kaldır">' +
        '<i class="fas fa-xmark"></i>' +
      '</button>';

    listContainer.appendChild(item);
  });
}

/**
 * Dosyayı listeden kaldır
 * @param {string} nsPrefix - Modül namespace öneki
 * @param {number} index - Dosya indeksi (1-tabanlı)
 */
function destekRemoveFile(nsPrefix, index) {
  Shiny.setInputValue(nsPrefix + 'dosya_sil', index, {priority: 'event'});
}

// ==============================================================================
// FORM SIFIRLAMA
// ==============================================================================

/**
 * Geri bildirim formunu sıfırla
 * @param {string} nsPrefix - Modül namespace öneki
 */
function destekResetFeedbackForm(nsPrefix) {
  // Memnuniyet seçimini temizle
  document.querySelectorAll('.destek-satisfaction-item').forEach(function(item) {
    item.classList.remove('active');
  });
  var memnuniyetInput = document.getElementById(nsPrefix + 'memnuniyet');
  if (memnuniyetInput) {
    memnuniyetInput.value = '';
    Shiny.setInputValue(nsPrefix + 'memnuniyet', '', {priority: 'event'});
  }

  // NPS seçimini temizle
  document.querySelectorAll('.destek-nps-btn').forEach(function(btn) {
    btn.classList.remove('active');
  });
  var npsInput = document.getElementById(nsPrefix + 'nps_puan');
  if (npsInput) {
    npsInput.value = '';
    Shiny.setInputValue(nsPrefix + 'nps_puan', '', {priority: 'event'});
  }

  // Etiketleri temizle
  document.querySelectorAll('.destek-tag-btn').forEach(function(btn) {
    btn.classList.remove('active');
  });
  var tagsInput = document.getElementById(nsPrefix + 'secili_etiketler');
  if (tagsInput) {
    tagsInput.value = '';
    Shiny.setInputValue(nsPrefix + 'secili_etiketler', '', {priority: 'event'});
  }

  // Metin alanlarını temizle
  ['en_cok_sevilen', 'gelistirme'].forEach(function(fieldId) {
    var textarea = document.getElementById(nsPrefix + fieldId);
    if (textarea) textarea.value = '';
  });

  // Sayaçları sıfırla
  ['sevilen_counter', 'gelistirme_counter'].forEach(function(counterId) {
    var counter = document.getElementById(nsPrefix + counterId);
    if (counter) {
      counter.textContent = '0 / 500';
      counter.classList.remove('destek-limit-warning');
    }
  });

  // İletişim iznini sıfırla (değer: "0")
  var iletisimInput = document.getElementById(nsPrefix + 'iletisim_izni');
  var checkboxVisual = document.getElementById(nsPrefix + 'iletisim_checkbox_visual');
  if (iletisimInput) {
    iletisimInput.value = '0';
    Shiny.setInputValue(nsPrefix + 'iletisim_izni', '0', {priority: 'event'});
  }
  if (checkboxVisual) checkboxVisual.classList.remove('checked');
}

/**
 * Hata bildirim formunu sıfırla
 * @param {string} nsPrefix - Modül namespace öneki
 */
function destekResetBugForm(nsPrefix) {
  // Konu girişlerini tek girişe indir
  var konuContainer = document.getElementById(nsPrefix + 'konular_container');
  if (konuContainer) {
    var rows = konuContainer.querySelectorAll('.destek-konu-row');
    rows.forEach(function(row, i) {
      if (i === 0) {
        var input = row.querySelector('.destek-text-input');
        if (input) input.value = '';
      } else {
        row.remove();
      }
    });
  }

  // Konu etiketini güncelle
  destekUpdateKonuLabel(nsPrefix);

  // Konuları sıfırla
  Shiny.setInputValue(nsPrefix + 'konular_birlesik', '', {priority: 'event'});

  // Kategorileri temizle
  var katContainer = document.getElementById(nsPrefix + 'kategori_container');
  if (katContainer) {
    katContainer.querySelectorAll('.destek-category-btn').forEach(function(btn) {
      btn.classList.remove('active');
    });
  }
  var katInput = document.getElementById(nsPrefix + 'secili_kategoriler');
  if (katInput) {
    katInput.value = '';
    Shiny.setInputValue(nsPrefix + 'secili_kategoriler', '', {priority: 'event'});
  }

  // Önceliği temizle (seçim yok)
  var oncContainer = document.getElementById(nsPrefix + 'oncelik_container');
  if (oncContainer) {
    oncContainer.querySelectorAll('.destek-priority-btn').forEach(function(btn) {
      btn.classList.remove('active');
    });
  }
  var oncInput = document.getElementById(nsPrefix + 'secili_oncelik');
  if (oncInput) {
    oncInput.value = '';
    Shiny.setInputValue(nsPrefix + 'secili_oncelik', '', {priority: 'event'});
  }

  // Açıklamayı temizle
  var aciklama = document.getElementById(nsPrefix + 'hata_aciklama');
  if (aciklama) aciklama.value = '';

  var aciklamaCounter = document.getElementById(nsPrefix + 'aciklama_counter');
  if (aciklamaCounter) {
    aciklamaCounter.textContent = '0 / 500';
    aciklamaCounter.classList.remove('destek-limit-warning');
  }

  // Dosya listesini temizle
  var dosyaListesi = document.getElementById(nsPrefix + 'dosya_listesi');
  if (dosyaListesi) dosyaListesi.innerHTML = '';

  // Hata mesajlarını gizle
  ['hata_konular', 'hata_kategoriler', 'hata_aciklama_msg'].forEach(function(id) {
    var el = document.getElementById(nsPrefix + id);
    if (el) el.style.display = 'none';
  });
}

// ==============================================================================
// KLAVYE KISAYOLLARI
// ==============================================================================

// Form gönderimi için Ctrl+Enter / Cmd+Enter kısayolu
document.addEventListener('keydown', function(e) {
  if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
    // Aktif destek formunu bul
    var activeGeriBildirim = document.querySelector('.destek-tab-content.active .destek-submit-btn, .destek-tab-content[style*="block"] .destek-submit-btn');
    if (!activeGeriBildirim) {
      // Geri bildirim formunda olabilir (doğrudan görünür)
      var visibleSubmit = document.querySelector('#sekme_geri_bildirim:not([style*="none"]) .destek-submit-btn');
      if (visibleSubmit) {
        visibleSubmit.click();
        return;
      }
    }
    if (activeGeriBildirim) {
      activeGeriBildirim.click();
    }
  }
});

// ==============================================================================
// İSTATİSTİK SAYAÇ ANİMASYONU (Hakkında sayfası)
// ==============================================================================

/**
 * Sayfa kaydırıldığında istatistik sayılarını animasyonla sayar
 * IntersectionObserver kullanarak görünürlük takibi yapar
 */
(function() {
  var animated = false;

  function animateCounters() {
    if (animated) return;

    var counters = document.querySelectorAll('.destek-stat-animated');
    if (counters.length === 0) return;

    animated = true;

    counters.forEach(function(counter) {
      var target = parseInt(counter.getAttribute('data-target'), 10);
      var suffix = counter.getAttribute('data-suffix') || '';
      var useGradient = counter.hasAttribute('data-gradient');
      var duration = 1500;
      var startTime = null;

      function getGradientColor(percent) {
        // Kırmızı(0%) → Sarı(50%) → Yeşil(100%) gradyan renk skalası
        var r, g, b;
        if (percent <= 50) {
          // Kırmızı → Sarı (0-50%)
          var t = percent / 50;
          r = Math.round(239 + (250 - 239) * t);  // #ef4444 → #facc15
          g = Math.round(68 + (204 - 68) * t);
          b = Math.round(68 + (21 - 68) * t);
        } else {
          // Sarı → Yeşil (50-100%)
          var t2 = (percent - 50) / 50;
          r = Math.round(250 + (74 - 250) * t2);   // #facc15 → #4ade80
          g = Math.round(204 + (222 - 204) * t2);
          b = Math.round(21 + (128 - 21) * t2);
        }
        return 'rgb(' + r + ',' + g + ',' + b + ')';
      }

      function step(timestamp) {
        if (!startTime) startTime = timestamp;
        var progress = Math.min((timestamp - startTime) / duration, 1);
        // Yavaşlayan eğri (ease-out)
        var easedProgress = 1 - Math.pow(1 - progress, 3);
        var current = Math.round(easedProgress * target);
        counter.textContent = current + suffix;

        // Gradyan renk animasyonu (memnuniyet yüzdesi için)
        if (useGradient) {
          var percent = (current / target) * 100;
          var color = getGradientColor(percent);
          counter.style.color = color;
          // Hafif parlama efekti
          counter.style.textShadow = '0 0 20px ' + color.replace('rgb', 'rgba').replace(')', ',0.3)');
        }

        if (progress < 1) {
          requestAnimationFrame(step);
        }
      }

      requestAnimationFrame(step);
    });
  }

  // IntersectionObserver ile görünürlük takibi
  function setupObserver() {
    var statsSection = document.getElementById('destek-stats-section');
    if (!statsSection) return;

    if ('IntersectionObserver' in window) {
      var observer = new IntersectionObserver(function(entries) {
        entries.forEach(function(entry) {
          if (entry.isIntersecting) {
            animateCounters();
            observer.unobserve(entry.target);
          }
        });
      }, { threshold: 0.3 });
      observer.observe(statsSection);
    } else {
      // Eski tarayıcılar için geri dönüş
      animateCounters();
    }
  }

  // Sayfa yüklendiğinde veya Shiny sayfası açıldığında
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', setupObserver);
  } else {
    setupObserver();
  }

  // Shiny sekme değişikliklerini dinle (Hakkında sayfasına geçildiğinde)
  $(document).on('shiny:value', function() {
    setTimeout(function() {
      animated = false;
      setupObserver();
    }, 200);
  });

  // Sidebar menü tıklamalarını da dinle
  $(document).on('click', '.sidebar-menu a', function() {
    setTimeout(function() {
      animated = false;
      setupObserver();
    }, 500);
  });
})();
