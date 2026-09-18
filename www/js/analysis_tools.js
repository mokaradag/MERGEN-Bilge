/* ==============================================================================
 * Dosya Yolu: www/js/analysis_tools.js
 * Açıklama:   Proje ve Kaynak Analizi aracının sohbet içi kontrol yönetimi,
 *             Ayarlar sayfası senkronizasyonu ve model seçici kilitleme mantığı.
 * ============================================================================== */

// ------------------------------------------------------------------------------
// ANALİZ KONTROLLERİNİ GÖSTER/GİZLE
// ------------------------------------------------------------------------------

/**
 * Analiz kontrol panelini göster veya gizle
 * @param {boolean} show - true: göster, false: gizle
 */
window.toggleAnalysisControls = function(show) {
  var controls = document.getElementById('analysis_chat_controls');
  if (controls) {
    if (show) {
      controls.classList.remove('hidden');
    } else {
      controls.classList.add('hidden');
    }
  }
};

// ------------------------------------------------------------------------------
// DERİN DÜŞÜNME BUTONU YÖNETİMİ
// ------------------------------------------------------------------------------

/**
 * Derin düşünme butonunun durumunu değiştir
 * @param {boolean} active - true: aktif, false: pasif
 */
window.setDeepThinkingState = function(active) {
  var btn = document.getElementById('chat_deep_thinking_toggle');
  if (!btn) return;

  if (active) {
    btn.classList.add('active');
    btn.setAttribute('title', 'Derin Düşünme: Aktif - Çoklu sorgu analizi yapılacak');
  } else {
    btn.classList.remove('active');
    btn.setAttribute('title', 'Derin Düşünme: Pasif - Tek sorgu analizi yapılacak');
  }

  // Detay seviyesi dropdown'ını aktifleştir/devre dışı bırak
  var detailSelect = document.getElementById('chat_analysis_detail');
  if (detailSelect) {
    detailSelect.disabled = !active;
    detailSelect.style.opacity = active ? '1' : '0.4';
  }
};

// ------------------------------------------------------------------------------
// MEVCUT AYARLARI AL
// ------------------------------------------------------------------------------

/**
 * Sohbet arayüzündeki analiz ayarlarını döndür
 * @returns {Object} Mevcut analiz ayarları
 */
window.getAnalysisSettings = function() {
  var btn = document.getElementById('chat_deep_thinking_toggle');
  var detailSelect = document.getElementById('chat_analysis_detail');

  return {
    deep_thinking: btn ? btn.classList.contains('active') : false,
    detail_level: detailSelect ? detailSelect.value : 'standart'
  };
};

// ------------------------------------------------------------------------------
// SOHBET ↔ AYARLAR SENKRONİZASYONU
// ------------------------------------------------------------------------------

/**
 * Analiz ayarlarını sohbet ve ayarlar sayfaları arasında senkronize et
 * @param {string} source - 'chat' veya 'settings'
 */
window.syncAnalysisSettings = function(source) {
  var chatDetail = document.getElementById('chat_analysis_detail');
  var chatDeepBtn = document.getElementById('chat_deep_thinking_toggle');
  var settingsDetail = document.getElementById('settings_yapilandirma_module-analysis_detail_level');
  var settingsDeep = document.getElementById('settings_yapilandirma_module-analysis_deep_thinking');

  if (source === 'chat') {
    // Sohbet → Ayarlar
    if (settingsDetail && chatDetail) {
      settingsDetail.value = chatDetail.value;
      $(settingsDetail).trigger('change');
    }
    if (settingsDeep && chatDeepBtn) {
      var isActive = chatDeepBtn.classList.contains('active');
      settingsDeep.checked = isActive;
      $(settingsDeep).trigger('change');
    }
  } else if (source === 'settings') {
    // Ayarlar → Sohbet
    if (chatDetail && settingsDetail) {
      chatDetail.value = settingsDetail.value;
    }
    if (chatDeepBtn && settingsDeep) {
      window.setDeepThinkingState(settingsDeep.checked);
    }
  }
};

// ------------------------------------------------------------------------------
// DOM OLAY DİNLEYİCİLERİ
// ------------------------------------------------------------------------------

document.addEventListener('DOMContentLoaded', function() {

  // Derin düşünme buton tıklama
  var deepBtn = document.getElementById('chat_deep_thinking_toggle');
  if (deepBtn) {
    deepBtn.addEventListener('click', function() {
      var isActive = this.classList.contains('active');
      var newState = !isActive;

      window.setDeepThinkingState(newState);
      window.syncAnalysisSettings('chat');

      // Shiny'ye bildir
      if (window.Shiny) {
        Shiny.setInputValue('chat_deep_thinking', newState, {priority: 'event'});
      }
    });
  }

  // Detay seviyesi dropdown değişikliği
  var detailSelect = document.getElementById('chat_analysis_detail');
  if (detailSelect) {
    detailSelect.addEventListener('change', function() {
      window.syncAnalysisSettings('chat');
      if (window.Shiny) {
        Shiny.setInputValue('chat_analysis_detail', this.value, {priority: 'event'});
      }
    });
  }
});

// ------------------------------------------------------------------------------
// SHINY MESAJ İŞLEYİCİLERİ
// ------------------------------------------------------------------------------

if (window.Shiny) {

  /**
   * Analiz modunu aç/kapat. Model seçim kilidi merkezi MergenToolModelLock
   * yöneticisine (tools_model_lock.js) bırakılır; böylece Görsel/Özet/Excel/Kod
   * gibi diğer araçların kilit durumu ile çakışma olmaz.
   */
  Shiny.addCustomMessageHandler('toggleAnalysisMode', function(data) {
    window.toggleAnalysisControls(data && data.active);

    if (window.MergenToolModelLock && typeof window.MergenToolModelLock.refresh === 'function') {
      window.MergenToolModelLock.refresh();
    }
  });

  /**
   * Ayarlar sayfasından sohbet kontrollerine senkronize et
   */
  Shiny.addCustomMessageHandler('syncAnalysisSettingsToChat', function(data) {
    var chatDetail = document.getElementById('chat_analysis_detail');
    var chatDeepBtn = document.getElementById('chat_deep_thinking_toggle');

    if (chatDetail && data.detail_level) {
      chatDetail.value = data.detail_level;
      Shiny.setInputValue('chat_analysis_detail', data.detail_level, {priority: 'event'});
    }

    if (typeof data.deep_thinking !== 'undefined') {
      window.setDeepThinkingState(data.deep_thinking);
      Shiny.setInputValue('chat_deep_thinking', data.deep_thinking, {priority: 'event'});
    }
  });

  /**
   * Sohbetten ayarlar sayfasına senkronize et
   */
  Shiny.addCustomMessageHandler('syncChatAnalysisSettingsToSettings', function(data) {
    var settingsDetail = document.getElementById('settings_yapilandirma_module-analysis_detail_level');
    var settingsDeep = document.getElementById('settings_yapilandirma_module-analysis_deep_thinking');

    if (settingsDetail && data.detail_level) {
      settingsDetail.value = data.detail_level;
      $(settingsDetail).trigger('change');
    }
    if (settingsDeep && typeof data.deep_thinking !== 'undefined') {
      settingsDeep.checked = data.deep_thinking;
      $(settingsDeep).trigger('change');
    }
  });
}

console.log('[ANALYSIS_TOOLS] Analiz araçları yüklendi');