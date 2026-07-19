// www/js/button_busy_ack.js
// Anında düğme geri bildirimi katmanı: Yeni Söyleşi ve Ayarları Kaydet
// düğmeleri tıklandığı anda "meşgul" durumuna geçer; ilk shiny:idle (veya
// güvenlik süresi) durumu geri açar. Sunucu tarafı akışlar idempotenttir;
// bu katman yalnızca algılanan gecikmeyi ve yinelenen tıklama görünümünü
// giderir. Başarı/hata/iptal her yolda durum geri döner.

(function($) {
  'use strict';

  function mergenButtonBusyAck(btn) {
    if (btn.classList.contains('mergen-btn-busy')) return false;
    btn.classList.add('mergen-btn-busy');
    btn.setAttribute('aria-disabled', 'true');

    var restored = false;
    var restore = function() {
      if (restored) return;
      restored = true;
      btn.classList.remove('mergen-btn-busy');
      btn.removeAttribute('aria-disabled');
      $(document).off('shiny:idle', restore);
    };
    $(document).on('shiny:idle', restore);
    setTimeout(restore, 5000);
    return true;
  }

  // Yeni Söyleşi: anında geri bildirim + gereksiz otomatik konuşmayı yerelde
  // durdur (kullanıcı eylemi otomatik konuşmadan önceliklidir).
  $(document).on('click', '#new_chat_btn', function() {
    if (!mergenButtonBusyAck(this)) return;

    if (window.MergenSpeech && window.MergenSpeech.markStopped) {
      window.MergenSpeech.markStopped();
    }
    if (window.AIExpertManager && window.AIExpertManager.stopSubtitle) {
      window.AIExpertManager.stopSubtitle({});
    }
  });

  // Ayarları Kaydet (Kişiselleştirme/Yapılandırma): kısa ömürlü meşgul durumu;
  // yinelenen gönderim görünümünü engeller, sayfa donmuş gibi görünmez.
  $(document).on('click',
    '#settings_kisisel_module-save_settings, ' +
    '#settings_yapilandirma_module-save_settings',
    function() { mergenButtonBusyAck(this); });
})(jQuery);
