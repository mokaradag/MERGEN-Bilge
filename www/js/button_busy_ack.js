// www/js/button_busy_ack.js
// Anında düğme geri bildirimi katmanı: Yeni Söyleşi ve Ayarları Kaydet
// düğmeleri tıklandığı anda "meşgul" durumuna geçer; ilk shiny:idle (veya
// güvenlik süresi) durumu geri açar. Sunucu tarafı akışlar idempotenttir;
// bu katman yalnızca algılanan gecikmeyi ve yinelenen tıklama görünümünü
// giderir. Başarı/hata/iptal her yolda durum geri döner.

(function($) {
  'use strict';

  var NEW_CHAT_SELECTOR = '#new_chat_btn';
  var SAVE_SETTINGS_SELECTOR = '#settings_kisisel_module-save_settings, ' +
    '#settings_yapilandirma_module-save_settings';
  var BUSY_GUARD_SELECTOR = NEW_CHAT_SELECTOR + ', ' + SAVE_SETTINGS_SELECTOR;

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

  // Yakalama aşamasında engelleme: `pointer-events: none` yalnızca fare/dokunma
  // tabanlı tıklamaları durdurur. Odaklanmış bir düğmede Enter/Boşluk ile
  // tetiklenen klavye click'i bu CSS kuralını atlar ve Shiny'nin action-button
  // bağlayıcısı bu betikten önce yüklendiği için köpürme (bubble) aşamasında
  // engellemek de yetersiz kalır. Yakalama aşamasında durdurmak, meşgul
  // düğmeye yönelik her kaynaktan gelen tıklamanın Shiny'ye hiç ulaşmamasını
  // garanti eder (bkz. theme_manager.js aynı desen).
  document.addEventListener('click', function(ev) {
    if (!ev || !ev.target || !ev.target.closest) return;
    var btn = ev.target.closest(BUSY_GUARD_SELECTOR);
    if (!btn || !btn.classList.contains('mergen-btn-busy')) return;
    ev.preventDefault();
    ev.stopPropagation();
  }, true);

  // Yeni Söyleşi: anında geri bildirim + gereksiz otomatik konuşmayı yerelde
  // durdur (kullanıcı eylemi otomatik konuşmadan önceliklidir).
  $(document).on('click', NEW_CHAT_SELECTOR, function() {
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
  $(document).on('click', SAVE_SETTINGS_SELECTOR,
    function() { mergenButtonBusyAck(this); });
})(jQuery);
