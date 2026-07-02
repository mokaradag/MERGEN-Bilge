/* ==============================================================================
 * www/js/process_tools.js
 * Dosya Yolu: www/js/process_tools.js
 * Açıklama: Süreç Yönetimi (Langflow) modu sohbet içi süreç akışı seçici
 *           kontrolünü yönetir. Seçili akış Shiny'e (chat_process_flow) aktarılır
 *           ve sunucu bu değere göre ilgili Langflow süreç akışını çağırır.
 * ============================================================================== */

window.toggleProcessControls = function(show) {
  var controls = document.getElementById('process_chat_controls');
  if (controls) {
    if (show) {
      controls.classList.remove('hidden');
    } else {
      controls.classList.add('hidden');
    }
  }
};

window.getProcessFlowSelection = function() {
  var flowSelect = document.getElementById('chat_process_flow');
  return flowSelect ? flowSelect.value : '';
};

document.addEventListener('DOMContentLoaded', function() {
  var flowSelect = document.getElementById('chat_process_flow');

  if (flowSelect) {
    // Sayfa açılışında seçim Shiny'e YAYINLANMAZ. Aksi halde DOM varsayılanı
    // (flow_1), sunucu kalıcı seçimi (process_flow_selection) geri yükleyip
    // senkronlamadan önce yayınlanır; settingsInit gözlemcisi bunu kalıcılaştırıp
    // kullanıcının kayıtlı akış seçimini ezerdi. Seçim yalnızca gerçek kullanıcı
    // değişikliğinde (change) ya da sunucu Süreç modunu etkinleştirdiğinde
    // (toggleProcessMode / syncProcessFlowToChat) bildirilir.
    flowSelect.addEventListener('change', function() {
      if (window.Shiny) {
        Shiny.setInputValue('chat_process_flow', this.value, {priority: 'event'});
      }
    });
  }
});

if (window.Shiny) {
  // Model seçim kilidi merkezi MergenToolModelLock yöneticisine bırakılır.
  Shiny.addCustomMessageHandler('toggleProcessMode', function(data) {
    window.toggleProcessControls(data && data.active);

    // Panel açıldığında mevcut seçili akışı Shiny'e yeniden bildir; böylece
    // sunucu tarafı seçim (settings) ile istemci görünümü hizalı kalır.
    if (data && data.active) {
      var flowSelect = document.getElementById('chat_process_flow');
      if (flowSelect) {
        Shiny.setInputValue('chat_process_flow', flowSelect.value, {priority: 'event'});
      }
    }

    if (window.MergenToolModelLock && typeof window.MergenToolModelLock.refresh === 'function') {
      window.MergenToolModelLock.refresh();
    }
  });

  // Ayarlar/oturum tarafından seçili akış senkronizasyonu (kalıcı seçim geri
  // yükleme için). Değer bir akış anahtarıdır (flow_1, flow_2, ...).
  Shiny.addCustomMessageHandler('syncProcessFlowToChat', function(data) {
    var flowSelect = document.getElementById('chat_process_flow');
    if (flowSelect && data && data.flow_key) {
      flowSelect.value = data.flow_key;
      Shiny.setInputValue('chat_process_flow', data.flow_key, {priority: 'event'});
    }
  });
}

console.log('[PROCESS_TOOLS] Süreç Yönetimi akış seçici yüklendi');
