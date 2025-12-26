// www/js/shortcuts_manager.js

$(document).ready(function() {
  // Klavye kısayolları dinleyicisi
  $(document).on('keydown', function(e) {
    if (e.ctrlKey && e.key === '/') {
      e.preventDefault();
      showKeyboardShortcuts();
    }
  });

  function showKeyboardShortcuts() {
    const shortcuts = `
      <div class="shortcuts-modal-content">
        <h3 style="color: var(--text-primary); margin-bottom: 20px;">Klavye Kısayolları</h3>
        <table class="shortcuts-table" style="width: 100%;">
          <tr><td style="padding: 8px;"><kbd>Enter</kbd></td><td>Mesaj gönder</td></tr>
          <tr><td style="padding: 8px;"><kbd>Shift + Enter</kbd></td><td>Yeni satır</td></tr>
          <tr><td style="padding: 8px;"><kbd>Ctrl + N</kbd></td><td>Yeni sohbet</td></tr>
          <tr><td style="padding: 8px;"><kbd>Ctrl + U</kbd></td><td>Dosya yükle</td></tr>
          <tr><td style="padding: 8px;"><kbd>Ctrl + /</kbd></td><td>Bu yardımı göster</td></tr>
          <tr><td style="padding: 8px;"><kbd>Esc</kbd></td><td>İptal/Temizle</td></tr>
          <tr><td style="padding: 8px;"><kbd>Page Up/Down</kbd></td><td>Sayfa kaydır</td></tr>
        </table>
      </div>
    `;

    const modalId = 'shortcuts_modal_' + Date.now();
    const modal = $(`
      <div id="${modalId}" class="shortcuts-modal" style="
        position: fixed;
        top: 50%;
        left: 50%;
        transform: translate(-50%, -50%);
        background: var(--background-light);
        border: 1px solid var(--border-color);
        border-radius: 12px;
        padding: 24px;
        z-index: 10000;
        box-shadow: 0 8px 32px rgba(0,0,0,0.3);
        max-width: 500px;
        color: var(--text-secondary);
      ">
        ${shortcuts}
        <button onclick="$('#${modalId}').remove(); $('#${modalId}_backdrop').remove();" style="
          margin-top: 20px;
          padding: 8px 16px;
          background: var(--primary-color);
          color: white;
          border: none;
          border-radius: 6px;
          cursor: pointer;
          width: 100%;
        ">Kapat</button>
      </div>
    `);

    const backdrop = $(`<div id="${modalId}_backdrop" style="
      position: fixed;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      background: rgba(0, 0, 0, 0.5);
      z-index: 9999;
    " onclick="$('#${modalId}, #${modalId}_backdrop').remove()"></div>`);

    $('body').append(backdrop).append(modal);
  }
});