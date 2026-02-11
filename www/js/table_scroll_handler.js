// www/js/table_scroll_handler.js
// Mesaj içeriğindeki geniş tabloları kaydırılabilir sarmalayıcıya yerleştirir.
// Hem mevcut hem de dinamik olarak eklenen (akış/geçmiş) tablolar desteklenir.

(function() {
  'use strict';

  /**
   * Verilen kök element içindeki sarmalanmamış tabloları sarmalayıcıya yerleştirir.
   * Aktif akış (streaming) mesajlarındaki tablolar atlanır.
   * @param {HTMLElement} root - Arama yapılacak kök element
   */
  function wrapTablesInElement(root) {
    if (!root) return;

    var tables = root.querySelectorAll('.message-content table');
    tables.forEach(function(table) {
      // Zaten sarmalanmışsa atla
      if (table.parentElement && table.parentElement.classList.contains('message-table-wrapper')) return;

      // Aktif akış içeriğindeki tabloları atla (innerHTML sürekli değişiyor)
      var streamingParent = table.closest('[data-streaming="true"]');
      if (streamingParent) return;

      // Sarmalayıcı oluştur ve tabloyu içine taşı
      var wrapper = document.createElement('div');
      wrapper.className = 'message-table-wrapper';
      table.parentNode.insertBefore(wrapper, table);
      wrapper.appendChild(table);
    });
  }

  // Sayfa yüklendiğinde mevcut tabloları sarmala
  $(document).ready(function() {
    wrapTablesInElement(document.body);

    // Yeni eklenen tablolar için MutationObserver
    var chatContainer = document.querySelector('.chat-container');
    if (!chatContainer) return;

    var tableObserver = new MutationObserver(function(mutations) {
      var hasNewTable = false;
      mutations.forEach(function(m) {
        if (!m.addedNodes) return;
        m.addedNodes.forEach(function(node) {
          if (node.nodeType !== 1) return;
          if (node.tagName === 'TABLE' || (node.querySelector && node.querySelector('table'))) {
            hasNewTable = true;
          }
        });
      });

      if (hasNewTable) {
        // Debounce - akış sırasında gereksiz çağrıları önle
        clearTimeout(window._tableWrapTimeout);
        window._tableWrapTimeout = setTimeout(function() {
          wrapTablesInElement(chatContainer);
        }, 200);
      }
    });

    tableObserver.observe(chatContainer, { childList: true, subtree: true });
  });

  // Global fonksiyon - diğer modüller tarafından çağrılabilir
  window.wrapMessageTables = wrapTablesInElement;
})();