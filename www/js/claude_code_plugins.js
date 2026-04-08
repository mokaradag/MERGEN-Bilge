/* =============================================================================
   Dosya Yolu: www/js/claude_code_plugins.js
   Açıklama: Claude Code Plugin paneli için JavaScript işleyicileri.
             Shiny mesaj dinleyicileri ve plugin sayaç rozeti güncelleme.
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

})();