// www/js/ai_expert_handlers.js
// Dosya Yolu: www/js/ai_expert_handlers.js
// Açıklama: AI Uzman için Shiny özel mesaj işleyicileri ve durdurma butonu
//           bağlayıcıları. Çalışma zamanı durum makinesi ai_expert_manager.js
//           içinde kalır; bu dosya yalnızca yükleme sırası korunan bağlama
//           katmanıdır.

(function(window, document, $) {
  'use strict';

  function getManager() {
    return window.AIExpertManager;
  }

  function setVisualizerVisible(data) {
    var container = document.querySelector('.tts-visualizer-container');
    if (!container) return;

    if (data && data.visible) {
      container.classList.remove('shiny-visual-hidden');
    } else {
      container.classList.add('shiny-visual-hidden');
    }
  }

  // Bayat istek koruması: sunucu token'ı taşıyan mesajlar MergenSpeech token
  // kaydından geçer. Token'sız (eski) mesajlar mevcut davranışı korur.
  function speechTokenAccept(data) {
    if (!window.MergenSpeech || !data || data.speechToken === undefined) return true;
    return window.MergenSpeech.accept(data.speechToken);
  }

  function speechTokenIsCurrent(data) {
    if (!window.MergenSpeech || !data || data.speechToken === undefined) return true;
    return window.MergenSpeech.isCurrent(data.speechToken);
  }

  // --- SHINY MESAJ İŞLEYİCİLERİ ---
  $(document).ready(function() {

    // Altyazı + ses senkronize başlatma (TTS hazır olduktan sonra çağrılır)
    Shiny.addCustomMessageHandler('aiExpertStartWithAudio', function(data) {
      if (!speechTokenAccept(data)) return;
      getManager().startWithAudio(data);
    });

    // Sadece altyazı başlatma mesajı (TTS yoksa)
    Shiny.addCustomMessageHandler('aiExpertStartSubtitle', function(data) {
      if (!speechTokenAccept(data)) return;
      getManager().startSubtitle(data);
    });

    // Sonraki AI Uzman ses parçasını kuyruğa ekle. Bayat bir konuşmanın geç
    // gelen parçası YENİ konuşmanın kuyruğuna giremez.
    Shiny.addCustomMessageHandler('aiExpertQueueAudioChunk', function(data) {
      if (!speechTokenIsCurrent(data)) return;
      getManager().queueAudioChunk(data);
    });

    // Ses oynatma mesajı (eski uyumluluk)
    Shiny.addCustomMessageHandler('aiExpertPlayAudio', function(data) {
      getManager().playAudio(data);
    });

    // Ses olmadan geri dönüş mesajı. Bayat (eski) bir başarısız konuşmanın geç
    // gelen ses-yok geri dönüşü, YENİ konuşmaya karşı gizleme zamanlayıcısı
    // kuramamalı; bu yüzden token güncel değilse yok say.
    Shiny.addCustomMessageHandler('aiExpertNoAudioFallback', function(data) {
      if (!speechTokenIsCurrent(data)) return;
      getManager().noAudioFallback(data);
    });

    // Durdurma mesajı: aktif token geçersizleşir, bayat parçalar oynayamaz
    Shiny.addCustomMessageHandler('aiExpertStopSubtitle', function(data) {
      if (window.MergenSpeech) window.MergenSpeech.markStopped();
      getManager().stopSubtitle(data);
    });

    // TTS görselleştiricisi görünürlüğü
    Shiny.addCustomMessageHandler('aiExpertVisualizerVisibility', setVisualizerVisible);

    // Sayfa değişikliği mesajı (R tarafından gönderilir)
    Shiny.addCustomMessageHandler('aiExpertSetPage', function(data) {
      getManager().setPage(data.page);
    });

    // Durdurma butonu doğrudan tıklama işleyicisi (Shiny binding'e ek olarak)
    $(document).on('click', '.ai-expert-stop-btn', function(e) {
      e.preventDefault();
      e.stopPropagation();
      console.log('[AI_EXPERT] Durdurma butonu tıklandı (JS)');
      if (window.MergenSpeech) window.MergenSpeech.markStopped();
      getManager().stopSubtitle({});
    });
  });
})(window, document, jQuery);
