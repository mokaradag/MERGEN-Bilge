// www/js/toast.js
(function() {
  'use strict';

  function showToast(message, type = 'info', duration = 3000) {
    if (!document.getElementById('toast-container')) {
      const tc = document.createElement('div');
      tc.id = 'toast-container';
      tc.className = 'toast-container';
      document.body.appendChild(tc);
    }
    const toastId = 'toast_' + Date.now();
    const iconMap = {
      success: 'fa-check-circle',
      error: 'fa-exclamation-circle',
      warning: 'fa-exclamation-triangle',
      info: 'fa-info-circle'
    };
    const toast = $(`
      <div id="${toastId}" class="toast toast-${type}">
        <i class="fas ${iconMap[type]} toast-icon"></i>
        <span class="toast-message">${message}</span>
        <button class="toast-close" onclick="$('#${toastId}').remove()">
          <i class="fas fa-times"></i>
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