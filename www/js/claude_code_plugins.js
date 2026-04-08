/* =============================================================================
   Dosya Yolu: www/js/claude_code_plugins.js
   Açıklama: Claude Code Plugin paneli için JavaScript işleyicileri.
             Shiny mesaj dinleyicileri, giriş alanı değer aktarımı ve
             plugin sayaç rozeti güncelleme mantığını kapsar.
   ============================================================================= */

(function() {
  'use strict';

  // --- Eklenti sayaç rozeti güncelleme ---
  Shiny.addCustomMessageHandler('cc-plugins-update-count', function(msg) {
    var badge = document.getElementById(msg.badgeId);
    if (!badge) return;

    if (msg.count > 0) {
      badge.textContent = msg.count;
      badge.classList.remove('cc-hidden');
    } else {
      badge.classList.add('cc-hidden');
    }
  });

  // --- Giriş alanı temizleme ---
  Shiny.addCustomMessageHandler('cc-plugins-clear-input', function(msg) {
    var input = document.getElementById(msg.inputId);
    if (input) {
      input.value = '';
    }
  });

  // --- Plugin giriş alanlarının değerlerini Shiny'ye iletme ---
  // Shiny, saf HTML input elementlerinin değerini otomatik takip etmez.
  // Bu yüzden buton tıklamasından önce değerleri inputBinding ile aktarırız.
  $(document).ready(function() {

    // Plugin kurulum giriş alanı: buton tıklanmadan hemen önce değeri Shiny'ye gönder
    $(document).on('click', '[id$="install_plugin"]', function() {
      var ns = this.id.replace('install_plugin', '');
      var input = document.getElementById(ns + 'plugin_install_input');
      if (input) {
        Shiny.setInputValue(ns + 'plugin_install_value', input.value, {priority: 'event'});
      }
    });

    // Marketplace URL giriş alanı: buton tıklanmadan hemen önce değeri Shiny'ye gönder
    $(document).on('click', '[id$="add_marketplace"]', function() {
      var ns = this.id.replace('add_marketplace', '');
      var input = document.getElementById(ns + 'marketplace_url_input');
      if (input) {
        Shiny.setInputValue(ns + 'marketplace_url_value', input.value, {priority: 'event'});
      }
    });

    // Enter tuşu ile kurulum/marketplace ekleme
    $(document).on('keypress', '.cc-plugins-input', function(e) {
      if (e.which === 13) {
        // En yakın action butonunu bul ve tıkla
        var row = $(this).closest('.cc-plugins-marketplace-row, .cc-plugins-install-row');
        var btn = row.find('.cc-plugins-action-btn, .cc-plugins-install-btn');
        if (btn.length > 0) {
          btn.first().click();
        }
      }
    });
  });

})();
