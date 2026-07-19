// www/js/input_handlers.js
// Bu dosya kullanıcı girdilerini, klavye kısayollarını ve gönderme butonunu yönetir.

$(document).ready(function() {
  // Sohbet giriş seçicilerini tek yerde tut.
  const CHAT_INPUT_SELECTOR = '#user_input, .chat-input, textarea[name="user_input"]';

  function getChatInputElement(context) {
    if (context && context.matches && context.matches(CHAT_INPUT_SELECTOR)) {
      return context;
    }
    return document.querySelector(CHAT_INPUT_SELECTOR);
  }

  window.MERGEN_CHAT_INPUT_SELECTOR = CHAT_INPUT_SELECTOR;
  window.getMergenChatInputElement = function(context) {
    return getChatInputElement(context);
  };

  function getChatInputValue($input) {
    if (!$input || !$input.length) return '';
    return $input.val() || '';
  }

  function hasFilePromptContext() {
    return $('#file_prompt_indicator_ui').children().length > 0;
  }

  function refreshChatInput(inputEl) {
    if (inputEl && typeof window.adjustTextareaHeight === 'function') {
      window.adjustTextareaHeight(inputEl);
    }
    if (typeof window.updateCharCounter === 'function') {
      window.updateCharCounter();
    }
  }

  function clearChatInput($input) {
    $input.val('');
    refreshChatInput($input[0]);
  }

  function sendPromptFromInput(inputEl) {
    if ($('#send_stop_btn').hasClass('stop-mode')) {
      return false;
    }

    const $input = $(getChatInputElement(inputEl));
    const promptText = getChatInputValue($input);

    if (promptText.trim().length === 0 && !hasFilePromptContext()) {
      if (typeof window.showToast === 'function') {
        window.showToast('Lütfen bir mesaj yazın.', 'warning');
      }
      return false;
    }

    if (typeof Shiny === 'undefined' || typeof Shiny.setInputValue !== 'function') {
      if (typeof window.showToast === 'function') {
        window.showToast('Gönderim için Shiny bağlantısı henüz hazır değil.', 'warning');
      }
      return false;
    }

    Shiny.setInputValue("send_prompt_from_js", {
      text: promptText,
      nonce: Math.random()
    }, { priority: "event" });

    clearChatInput($input);
    $input.focus();

    setTimeout(() => {
        if (typeof window.scrollToBottom === 'function') window.scrollToBottom(true);
    }, 50);

    return true;
  }

  // Textarea başlangıç durumunu gerçek UI sözleşmesine göre hazırla.
  const chatInput = getChatInputElement();
  if (chatInput) {
    refreshChatInput(chatInput);
  }

  // Gecikmeli (Debounced) giriş işleyicisi
  const debouncedInputHandler = (typeof debounce === 'function') ? debounce(function(element) {
      refreshChatInput(element);
  }, 300) : function() {};
  
  $(document).on('input', CHAT_INPUT_SELECTOR, function() { 
      debouncedInputHandler(this);
  });

  // Gönder butonu işleyicisi
  $(document).on('click', '#send_stop_btn', function(event) {
    if ($(this).hasClass('stop-mode')) {
      return;
    }
    event.preventDefault();
    sendPromptFromInput(getChatInputElement());
  });

  // Sohbet giriş alanı tuşları
  $(document).on('keyup', CHAT_INPUT_SELECTOR, function(e) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendPromptFromInput(this);
    } else if (e.key === 'Escape') {
      e.preventDefault();
      this.value = '';
      refreshChatInput(this);
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

  $(document).on('keydown', CHAT_INPUT_SELECTOR, function(e) {
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