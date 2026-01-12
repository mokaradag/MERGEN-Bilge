// www/js/app_core.js
// Bu dosya uygulamanın çekirdek mantığını, gözlemcileri ve bağlantı durumlarını yönetir.

let globalMessageObserver = null;

$(document).ready(function() {

  // Alt tarafa yakınlık bayrağını başlat
  window.isNearBottom = true;

  // CodeMirror örneklerini başlat
  if (window.initializeCodeMirrorInElement) {
    $('.code-container').each(function() {
      const wrapperId = $(this).closest('[id^="message_wrapper_"]').attr('id');
      if (wrapperId) {
        window.initializeCodeMirrorInElement(wrapperId);
      }
    });
  }

  // Global değişkenler
  window.isNearBottom = true;
  let sessionTimeout;
  let warningShown = false;

  // Performans izleme
  const performanceMonitor = window.performanceMonitor || {
    start: function(action) {
      this[action + '_start'] = performance.now();
    },
    end: function(action) {
      const duration = performance.now() - this[action + '_start'];
      Shiny.setInputValue('performance_data', {
        action: action,
        duration: Math.round(duration)
      }, {
        priority: 'event'
      });
    }
  };

  // Shiny bağlandığında: son sekmeyi geri yükle ve geniş ekran ayarını uygula
	$(document).on('shiny:connected', function(event) {
	  setTimeout(() => {
		try {
		  const raw = localStorage.getItem('mergen_settings');
		  let widescreenEnabled = true;
		  if (raw) {
			const settings = JSON.parse(raw);
			if (typeof settings.enable_widescreen === 'boolean') {
			  widescreenEnabled = settings.enable_widescreen;
			}
		  }
		  if (typeof applyWidescreen === 'function') {
			applyWidescreen(widescreenEnabled);
		  }
		} catch (e) {
		  if (typeof applyWidescreen === 'function') {
			applyWidescreen(true);
		  }
		}
		
		if (window.updateCharCounter) window.updateCharCounter();
	  }, 200);
	});

  // Mesaj gözlemcisi
  const messageObserver = new MutationObserver(muts => {
    let shouldScroll = false;
    muts.forEach(m => {
      m.addedNodes && m.addedNodes.forEach(node => {
        if (!(node instanceof HTMLElement)) return;

        if (node.id === 'typing-animation-wrapper') {
          TypingAnimationManager.create(node);
          shouldScroll = true;
        } else if (node.classList.contains('message-bubble')) {
          const wrapper = node.closest('[id^="message_wrapper_"]');
          if (wrapper) updateMessageWrappersForWidescreen(wrapper);
          shouldScroll = true;
        }
      });

      m.removedNodes && m.removedNodes.forEach(node => {
        if (node instanceof HTMLElement && node.id === 'typing-animation-wrapper') {
          TypingAnimationManager.destroy();
        }
      });
    });
    if (shouldScroll) setTimeout(() => scrollToBottom(true), 10);
  });

  const chatContainer = document.querySelector('.chat-container');
  if (chatContainer) {
    if (globalMessageObserver) {
      globalMessageObserver.disconnect();
    }
    globalMessageObserver = messageObserver;
    globalMessageObserver.observe(chatContainer, {
      childList: true,
      subtree: true
    });
  }

  // .codemirror-textarea eklendiğinde CM'yi otomatik başlat
  (function attachCMObserver() {
    const root = document.querySelector('#chat_content_container, #_content_container, .chat-container');
    if (!root) {
      console.warn('[MERGEN] CM observer: root not found');
      return;
    }
    const initFor = (ta) => {
      const wrapper = ta.closest('[id^="message_wrapper_"]');
      if (wrapper && window.initializeCodeMirrorInElement) {
        window.initializeCodeMirrorInElement(wrapper.id);
      }
    };
    const obs = new MutationObserver(muts => {
      muts.forEach(m => {
        m.addedNodes && m.addedNodes.forEach(node => {
          if (!(node instanceof HTMLElement)) return;
          if (node.matches && node.matches('.codemirror-textarea')) initFor(node);
          node.querySelectorAll && node.querySelectorAll('.codemirror-textarea').forEach(initFor);
        });
      });
    });
    obs.observe(root, {
      childList: true,
      subtree: true
    });
  })();

  // Bağlantı kesildiğinde temizlik yap
  $(document).on('shiny:disconnected', function(event) {
    if (globalMessageObserver) {
      globalMessageObserver.disconnect();
      globalMessageObserver = null;
    }
    TypingAnimationManager.destroy();
    if (window.pendingTimeouts) {
      window.pendingTimeouts.forEach(clearTimeout);
    }
    $('.disconnect-overlay').css('display', 'flex');
  });

  // Shiny yeniden bağlandığında tekrar başlat
  $(document).on('shiny:connected', function(event) {
    (function attachCMObserver() {
      const root = document.querySelector('#chat_content_container, #_content_container, .chat-container');
      if (!root) {
        console.warn('[MERGEN] CM observer: root not found');
        return;
      }
      const initFor = (ta) => {
        const wrapper = ta.closest('[id^="message_wrapper_"]');
        if (wrapper && window.initializeCodeMirrorInElement) {
          window.initializeCodeMirrorInElement(wrapper.id);
        }
      };
      const obs = new MutationObserver(muts => {
        muts.forEach(m => {
          m.addedNodes && m.addedNodes.forEach(node => {
            if (!(node instanceof HTMLElement)) return;
            if (node.matches && node.matches('.codemirror-textarea')) initFor(node);
            node.querySelectorAll && node.querySelectorAll('.codemirror-textarea').forEach(initFor);
          });
        });
      });
      obs.observe(root, {
        childList: true,
        subtree: true
      });
      console.log('[MERGEN] CodeMirror observer reinitialized after reconnection');
    })();
  });

  // Diğer fonksiyonlar
  window.sendCapabilityMessage = function(message, model) {
    if (model) {
      console.log('Setting model to:', model);

      Shiny.setInputValue('quick_action_model_change', model, {
        priority: 'event'
      });

      setTimeout(function() {
        document.getElementById('user_input').value = message;
        document.getElementById('user_input').dispatchEvent(new Event('input'));

        setTimeout(function() {
          document.getElementById('send_stop_btn').click();
        }, 100);
      }, 200);
    } else {
      document.getElementById('user_input').value = message;
      document.getElementById('user_input').dispatchEvent(new Event('input'));
      document.getElementById('send_stop_btn').click();
    }
  };
  
	window.showModernTooltip = function(tooltipId, buttonElement) {
	  let tooltip = document.getElementById(tooltipId);
	  if (!tooltip) return;
	  
	  // Tooltip metnini data attribute'dan al
	  const tooltipText = tooltip.getAttribute('data-tooltip-text') || '';
	  if (!tooltipText) return;
	  
	  const rect = buttonElement.getBoundingClientRect();
	  const escaped = String(tooltipText).replace(/</g, '&lt;').replace(/>/g, '&gt;');
	  
	  // Tooltip içeriğini oluştur
	  const contentDiv = tooltip.querySelector('.modern-tooltip-content');
	  if (contentDiv) {
		contentDiv.innerHTML = escaped;
	  }
	  
	  tooltip.style.display = 'block';
	  tooltip.style.left = (rect.left + rect.width / 2) + 'px';
	  tooltip.style.top = (rect.bottom + 12) + 'px';
	  tooltip.style.transform = 'translateX(-50%)';
	  
	  setTimeout(() => tooltip.style.opacity = '1', 10);
	};

	window.hideModernTooltip = function(tooltipId) {
	  const tooltip = document.getElementById(tooltipId);
	  if (!tooltip) return;
	  
	  tooltip.style.opacity = '0';
	  setTimeout(() => {
		tooltip.style.display = 'none';
	  }, 200);
	};

  // Alt tarafa yakınlık bayrağını global yap
  window.isNearBottom = isNearBottom;

});