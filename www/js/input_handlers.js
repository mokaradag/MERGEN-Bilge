// www/js/input_handlers.js
// Bu dosya kullanıcı girdilerini, klavye kısayollarını ve gönderme butonunu yönetir.

$(document).ready(function() {
  // Textarea için otomatik yeniden boyutlandırma ayarı
  const messageInput = document.getElementById('message_input');
  if (messageInput) {
    messageInput.addEventListener('input', function() {
      this.style.height = 'auto';
      this.style.height = Math.min(this.scrollHeight, 150) + 'px';
    });
  }

  // Gecikmeli (Debounced) giriş işleyicisi
  const debouncedInputHandler = (typeof debounce === 'function') ? debounce(function(element) {
      if (typeof window.adjustTextareaHeight === 'function') window.adjustTextareaHeight(element);
      if (typeof window.updateCharCounter === 'function') window.updateCharCounter();
  }, 300) : function() {};
  
  $(document).on('input', '.chat-input', function() { 
      debouncedInputHandler(this);
  });

  // Gönder butonu işleyicisi
  $(document).on('click', '#send_stop_btn', function(event) {
    if ($(this).hasClass('stop-mode')) {
      return;
    }
    event.preventDefault();

    const textarea = $('.chat-input');
    const promptText = textarea.val() || '';

    if (promptText.trim().length === 0 && $('#file_prompt_indicator_ui').children().length === 0) {
      if (typeof window.showToast === 'function') {
        window.showToast('Lütfen bir mesaj yazın.', 'warning');
      }
      return;
    }

    Shiny.setInputValue("send_prompt_from_js", {
      text: promptText,
      nonce: Math.random()
    }, { priority: "event" });

    textarea.val('');
    if (textarea[0] && typeof window.adjustTextareaHeight === 'function') window.adjustTextareaHeight(textarea[0]);
    if (typeof window.updateCharCounter === 'function') window.updateCharCounter();
    textarea.focus();

    setTimeout(() => {
        if (typeof window.scrollToBottom === 'function') window.scrollToBottom(true);
    }, 50);
  });

  // Sohbet giriş alanı tuşları
  $(document).on('keyup', function(e) {
    const chatInput = $(e.target);

    if (chatInput.is('.chat-input')) {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        const promptText = chatInput.val() || '';

        if (promptText.trim().length === 0 && $('#file_prompt_indicator_ui').children().length === 0) {
          if (typeof window.showToast === 'function') {
            window.showToast('Lütfen bir mesaj yazın.', 'warning');
          }
          return;
        }

        Shiny.setInputValue("send_prompt_from_js", {
          text: promptText,
          nonce: Math.random()
        }, { priority: "event" });

        chatInput.val('');
        if (chatInput[0] && typeof window.adjustTextareaHeight === 'function') window.adjustTextareaHeight(chatInput[0]);
        if (typeof window.updateCharCounter === 'function') window.updateCharCounter();
        setTimeout(() => {
            if (typeof window.scrollToBottom === 'function') window.scrollToBottom(true);
        }, 50);

      } else if (e.key === 'Escape') {
        e.preventDefault();
        e.target.value = '';
        if (typeof window.updateCharCounter === 'function') window.updateCharCounter();
        if (typeof window.adjustTextareaHeight === 'function') window.adjustTextareaHeight(e.target);
      }

      return;
    }
  });

  // Global kısayollar
  $(document).on('keydown', function(e) {
    const key = (e.key || '').toLowerCase();

    if (e.ctrlKey && e.altKey && !e.shiftKey && !e.metaKey && key === 'n') {
      e.preventDefault();
      e.stopPropagation();

      const newChatButton = document.getElementById('new_chat_btn');
      if (newChatButton) {
        newChatButton.click();
      }
      return;
    }

    if (e.ctrlKey && e.altKey && !e.shiftKey && !e.metaKey && key === 'u') {
      e.preventDefault();
      e.stopPropagation();

      const fileInput = document.getElementById('file_upload');
      if (fileInput) {
        fileInput.click();
      }
      return;
    }

    if (e.key === 'PageUp' || e.key === 'PageDown') {
      e.preventDefault();
      e.stopPropagation();

      var chatContainer = $('.chat-container');

      if (chatContainer.length) {
        var sayfaKaydirmaMiktari = Math.max(160, Math.floor(chatContainer[0].clientHeight * 0.98));
        var hedefScrollTop = chatContainer.scrollTop() + (e.key === 'PageUp' ? -sayfaKaydirmaMiktari : sayfaKaydirmaMiktari);

        chatContainer.stop(true).animate({
          scrollTop: hedefScrollTop
        }, 200);
      }
      return;
    }

    if (e.key === 'Escape') {
      $('.modal').modal('hide');
    }
  });

  $(document).on('keydown', '.chat-input', function(e) {
    if (e.key === 'Enter' && !e.shiftKey) e.preventDefault();
  });

  // Scroll olayını dinle (checkScrollPosition utils.js içinde tanımlı)
  function initScrollListener() {
    var container = document.querySelector('.chat-container');
    if (!container) {
      setTimeout(initScrollListener, 500);
      return;
    }
    
    container.addEventListener('scroll', function() {
      var distanceFromBottom = this.scrollHeight - this.scrollTop - this.clientHeight;
      var isNearBottom = distanceFromBottom < 20;
      
      window.isNearBottom = isNearBottom;
      
      if (isNearBottom) {
        $('#scroll_to_bottom_container').removeClass('show');
      } else {
        $('#scroll_to_bottom_container').addClass('show');
      }
    });
    
    var distanceFromBottom = container.scrollHeight - container.scrollTop - container.clientHeight;
    if (distanceFromBottom > 20) {
      $('#scroll_to_bottom_container').addClass('show');
    }
  }
  
  setTimeout(initScrollListener, 500);

  // Pasif dinleyiciler (DevTools uyarılarını engellemek için)
  const _chatEl = document.querySelector('.chat-container');
  if (_chatEl) {
    _chatEl.addEventListener('wheel', () => {}, { passive: true });
    _chatEl.addEventListener('touchstart', () => {}, { passive: true });
    _chatEl.addEventListener('touchmove', () => {}, { passive: true });
  }

  // Aşağı kaydırma butonu tıklaması
  $(document).on('click', '#scroll_to_bottom', function() { 
      if (typeof window.scrollToBottom === 'function') {
        window.scrollToBottom(true);
        setTimeout(function() {
          $('#scroll_to_bottom_container').removeClass('show');
        }, 100);
      }
  });
});