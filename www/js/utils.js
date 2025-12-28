// www/js/utils.js
// Bu dosya genel yardımcı fonksiyonları ve araçları içerir.

// Global değişkenler
window.isNearBottom = true;
const charLimit = 20000;

// Debounce (gecikmeli çalıştırma) fonksiyonu
function debounce(func, wait) {
  let timeout;
  return function executedFunction(...args) {
    const later = () => {
      clearTimeout(timeout);
      func(...args);
    };
    clearTimeout(timeout);
    timeout = setTimeout(later, wait);
  };
}

// Textarea yüksekliğini içeriğe göre ayarla
window.adjustTextareaHeight = function(textarea) {
  if (!textarea) return;
  textarea.style.height = 'auto';
  textarea.style.height = Math.min(textarea.scrollHeight, 120) + 'px';
};

// Sohbet penceresini en alta kaydır
window.scrollToBottom = function(smooth = true) {
  const container = $('.chat-container');
  if (container.length) {
    container[0].scrollTo({
      top: container[0].scrollHeight,
      behavior: smooth ? 'smooth' : 'auto'
    });
  }
};

// Akıllı kaydırma (Smart Scroll)
window.smartScrollToBottom = function(smooth = true) {
  const chatWrapper = document.querySelector('.chat-content-wrapper');
  const chatContainer = document.querySelector('.chat-container');
  
  if (chatWrapper) {
    chatWrapper.scrollTo({
      top: chatWrapper.scrollHeight,
      behavior: smooth ? 'smooth' : 'auto'
    });
  } else if (chatContainer) {
    chatContainer.scrollTo({
      top: chatContainer.scrollHeight,
      behavior: smooth ? 'smooth' : 'auto'
    });
  }
  
  // Kaydırma pozisyonu bayrağını güncelle
  window.isNearBottom = true;
};

// Kaydırma pozisyonunu kontrol et (Kullanıcı yukarıda mı?)
window.checkScrollPosition = function() {
  const container = $('.chat-container');
  if (container.length) {
    const scrollHeight = container[0].scrollHeight;
    const scrollTop = container.scrollTop();
    const clientHeight = container.height();
    window.isNearBottom = (scrollHeight - scrollTop - clientHeight) < 100;
    $('#scroll_to_bottom_container').toggleClass('show', !window.isNearBottom);
  }
};

// Karakter sayacını güncelle
window.updateCharCounter = function() {
  const chatInputEl = document.getElementById('user_input') ||
                     document.querySelector('.chat-input') ||
                     document.querySelector('textarea[name="user_input"]');
  const counterEl = document.getElementById('char_counter');
  if (!counterEl) return;

  const currentLength = chatInputEl ? (chatInputEl.value || '').length : 0;
  counterEl.textContent = `${currentLength} / ${charLimit}`;

  if (currentLength > charLimit) {
    counterEl.style.color = 'var(--danger-color)';
    counterEl.classList.remove('char-limit-exceeded');
    void counterEl.offsetWidth;
    counterEl.classList.add('char-limit-exceeded');
  } else {
    counterEl.style.color = 'var(--text-muted)';
    counterEl.classList.remove('char-limit-exceeded');
  }
};

// Mesaj içeriğini panoya kopyala
window.copyMessageContent = function(btn, content) {
  navigator.clipboard.writeText(content).then(() => {
    if (window.showToast) showToast('İçerik panoya kopyalandı.', 'success');
    const i = $(btn).find('i');
    const c = i.attr('class');
    i.removeClass().addClass('fas fa-check');
    setTimeout(() => i.removeClass().addClass(c), 2000);
  }).catch(err => {
    if (window.showToast) showToast('Kopyalama başarısız oldu.', 'error');
  });
};

// Kod bloğunu panoya kopyala
window.copyCodeBlock = function(button) {
  const codeContainer = button.closest('.code-container');
  const codeContent = codeContainer.querySelector('.code-content code');
  
  if (codeContent) {
    const text = codeContent.textContent;
    navigator.clipboard.writeText(text).then(() => {
      const icon = button.querySelector('i');
      icon.className = 'fas fa-check';
      if (window.showToast) showToast('Kod kopyalandı!', 'success');
      setTimeout(() => {
        icon.className = 'fas fa-copy';
      }, 2000);
    }).catch(err => {
      if (window.showToast) showToast('Kopyalama başarısız oldu.', 'error');
    });
  }
};