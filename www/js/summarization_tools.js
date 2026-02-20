/* ==============================================================================
 * www/js/summarization_tools.js
 * Özetleme modu kontrol paneli yönetimi ve Ayarlar senkronizasyonu
 * ============================================================================== */

window.toggleSummaryControls = function(show) {
  var controls = document.getElementById('summary_chat_controls');
  if (controls) {
    if (show) {
      controls.classList.remove('hidden');
    } else {
      controls.classList.add('hidden');
    }
  }
};

window.getSummarySettings = function() {
  var detailSelect = document.getElementById('chat_summary_detail');
  var focusSelect = document.getElementById('chat_summary_focus');

  return {
    detail_level: detailSelect ? detailSelect.value : 'standard',
    focus_mode: focusSelect ? focusSelect.value : 'general'
  };
};

window.syncSummarySettings = function(source) {
  var chatDetail = document.getElementById('chat_summary_detail');
  var chatFocus = document.getElementById('chat_summary_focus');
  var settingsDetail = document.getElementById('settings_module-summary_detail_level');
  var settingsFocus = document.getElementById('settings_module-summary_focus_mode');

  if (source === 'chat') {
    if (settingsDetail && chatDetail) {
      settingsDetail.value = chatDetail.value;
      $(settingsDetail).trigger('change');
    }
    if (settingsFocus && chatFocus) {
      settingsFocus.value = chatFocus.value;
      $(settingsFocus).trigger('change');
    }
  } else if (source === 'settings') {
    if (chatDetail && settingsDetail) {
      chatDetail.value = settingsDetail.value;
    }
    if (chatFocus && settingsFocus) {
      chatFocus.value = settingsFocus.value;
    }
  }
};

document.addEventListener('DOMContentLoaded', function() {
  var chatDetail = document.getElementById('chat_summary_detail');
  var chatFocus = document.getElementById('chat_summary_focus');

  if (chatDetail) {
    chatDetail.addEventListener('change', function() {
      window.syncSummarySettings('chat');
      if (window.Shiny) {
        Shiny.setInputValue('chat_summary_detail', this.value, {priority: 'event'});
      }
    });
  }

  if (chatFocus) {
    chatFocus.addEventListener('change', function() {
      window.syncSummarySettings('chat');
      if (window.Shiny) {
        Shiny.setInputValue('chat_summary_focus', this.value, {priority: 'event'});
      }
    });
  }
});

if (window.Shiny) {
  Shiny.addCustomMessageHandler('syncSummarySettingsToChat', function(data) {
    var chatDetail = document.getElementById('chat_summary_detail');
    var chatFocus = document.getElementById('chat_summary_focus');

    if (chatDetail && data.detail_level) {
      chatDetail.value = data.detail_level;
      Shiny.setInputValue('chat_summary_detail', data.detail_level, {priority: 'event'});
    }
    if (chatFocus && data.focus_mode) {
      chatFocus.value = data.focus_mode;
      Shiny.setInputValue('chat_summary_focus', data.focus_mode, {priority: 'event'});
    }
  });

  Shiny.addCustomMessageHandler('toggleSummaryMode', function(data) {
    window.toggleSummaryControls(data.active);

    var modelWrapper = document.querySelector('.model-selector-wrapper');
    if (modelWrapper) {
      if (data.active) {
        modelWrapper.classList.add('model-selector-locked');
        modelWrapper.style.opacity = '0.5';
        modelWrapper.style.pointerEvents = 'none';
        modelWrapper.title = 'Özetleme modunda model seçimi devre dışı';
      } else {
        modelWrapper.classList.remove('model-selector-locked');
        var imageControls = document.getElementById('image_chat_controls');
        var imageActive = imageControls && !imageControls.classList.contains('hidden');
        var analysisControls = document.getElementById('analysis_chat_controls');
        var analysisActive = analysisControls && !analysisControls.classList.contains('hidden');
        if (!imageActive && !analysisActive) {
          modelWrapper.style.opacity = '1';
          modelWrapper.style.pointerEvents = 'auto';
          modelWrapper.title = 'Model Değiştir';
        }
      }
    }
  });

  Shiny.addCustomMessageHandler('syncChatSummarySettingsToSettings', function(data) {
    var settingsDetail = document.getElementById('settings_module-summary_detail_level');
    var settingsFocus = document.getElementById('settings_module-summary_focus_mode');

    if (settingsDetail && data.detail_level) {
      settingsDetail.value = data.detail_level;
      $(settingsDetail).trigger('change');
    }
    if (settingsFocus && data.focus_mode) {
      settingsFocus.value = data.focus_mode;
      $(settingsFocus).trigger('change');
    }
  });
}

console.log('[SUMMARIZATION_TOOLS] Özetleme araçları yüklendi');