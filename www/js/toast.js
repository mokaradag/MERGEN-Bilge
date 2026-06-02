// www/js/toast.js
(function() {
  'use strict';

  function showToast(message, type = 'info', duration = 3000) {
    if (!document.getElementById('toast-container')) {
      const tc = document.createElement('div');
      tc.id = 'toast-container';
      tc.className = 'toast-container';
      // Erişilebilirlik: ekran okuyucuların bildirimleri seslendirmesi için
      // canlı bölge (live region) olarak işaretlenir.
      tc.setAttribute('role', 'status');
      tc.setAttribute('aria-live', 'polite');
      tc.setAttribute('aria-atomic', 'false');
      document.body.appendChild(tc);
    }
    const toastId = 'toast_' + Date.now();
    const iconMap = {
      success: 'fa-check-circle',
      error: 'fa-exclamation-circle',
      warning: 'fa-exclamation-triangle',
      info: 'fa-info-circle'
    };
    // Hata/uyarı bildirimleri için "alert" rolü daha güçlü seslendirme sağlar;
    // bilgi/başarı için "status" yeterlidir.
    const toastRole = (type === 'error' || type === 'warning') ? 'alert' : 'status';
    const toast = $(`
      <div id="${toastId}" class="toast toast-${type}" role="${toastRole}">
        <i class="fas ${iconMap[type]} toast-icon" aria-hidden="true"></i>
        <span class="toast-message">${message}</span>
        <button class="toast-close" aria-label="Bildirimi kapat" onclick="$('#${toastId}').remove()">
          <i class="fas fa-times" aria-hidden="true"></i>
        </button>
      </div>
    `);
    $('#toast-container').append(toast);
    setTimeout(() => {
      toast.addClass('hiding');
      setTimeout(() => toast.remove(), 300);
    }, duration);
  }
  
  window.showToast = showToast;
})();