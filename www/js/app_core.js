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

  // CodeMirror observer fonksiyonunu tanımla (tekrar kullanılabilir)
  // NOT: Önceden iki ayrı yerde aynı kod vardı, şimdi tek fonksiyona çıkarıldı
  function attachCMObserver(isReconnection = false) {
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
    if (isReconnection) {
      console.log('[MERGEN] CodeMirror observer reinitialized after reconnection');
    }
  }
 
  // .codemirror-textarea eklendiğinde CM'yi otomatik başlat
  attachCMObserver(false);
 
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
    attachCMObserver(true);
  });

  // Diğer fonksiyonlar
	window.sendCapabilityMessage = function(message, model) {
	  if (model) {
		console.log('Setting model to:', model);

		// Use Shiny.setInputValue if available, otherwise set input directly
		if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
		  Shiny.setInputValue('quick_action_model_change', model, {
			priority: 'event'	
		  });

		  setTimeout(function() {
			if (document.getElementById('user_input')) {
			  document.getElementById('user_input').value = message;
			  document.getElementById('user_input').dispatchEvent(new Event('input'));

			  setTimeout(function() {
				if (document.getElementById('send_stop_btn')) {
				  document.getElementById('send_stop_btn').click();
				}
			  }, 100);
			}
		  }, 200);
		} else {
		  console.warn('Shiny is not available yet');
		}
	  } else {
		if (document.getElementById('user_input')) {
		  document.getElementById('user_input').value = message;
		  document.getElementById('user_input').dispatchEvent(new Event('input'));
		  if (document.getElementById('send_stop_btn')) {
			document.getElementById('send_stop_btn').click();
		  }
		}
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

  // Hızlı işlem butonları için tooltip yönetimi
  $(document).ready(function() {

	// Hoş geldin ekranı tooltip'lerini temizleyen merkezi fonksiyon
	// Not: Bootstrap tooltip'leri (.tooltip) burada kaldırılmaz,
	// Yönetici Paneli ve diğer sayfaların tooltip'lerini bozmamak için.
	window.clearAllTooltips = function() {
	  $('.custom-tooltip').remove();
	  $('.modern-welcome-action-btn').each(function() {
		var t = $(this).data('custom-tooltip');
		if (t) t.remove();
		$(this).removeData('custom-tooltip');
	  });
	};

	// Butonlardan title attribute'unu sakla ve kaldır (tarayıcı tooltip'ini engelle)
	function storeOriginalTitles() {
	  $('.modern-welcome-action-btn').each(function() {
		var title = $(this).attr('title');
		if (title) {
		  $(this).data('original-title', title);
		  $(this).removeAttr('title');
		}
	  });
	}

	// Sayfa yüklendiğinde ve dinamik içerik eklendiğinde title'ları sakla
	storeOriginalTitles();
	var welcomeTitleObserver = new MutationObserver(function() {
	  storeOriginalTitles();
	});
	var welcomeContainer = document.getElementById('welcome_fullscreen_container');
	if (welcomeContainer) {
	  welcomeTitleObserver.observe(welcomeContainer, { childList: true, subtree: true });
	}

	// Buton üzerine gelince tooltip göster
	$(document).on('mouseenter', '.modern-welcome-action-btn', function() {
	  var $btn = $(this);
	  // Eğer title henüz data'ya aktarılmamışsa aktar
	  if (!$btn.data('original-title') && $btn.attr('title')) {
		$btn.data('original-title', $btn.attr('title'));
		$btn.removeAttr('title');
	  }
	  var title = $btn.data('original-title');
	  if (!title || title.trim() === '') return;

	  // Önceki tooltip varsa temizle
	  var existing = $btn.data('custom-tooltip');
	  if (existing) existing.remove();

	  // Başlık ve açıklamayı ayır (format: "Başlık\n\nAçıklama")
	  var parts = title.split('\n\n');
	  var tooltipTitle = parts[0] || '';
	  var tooltipDesc = parts.slice(1).join('\n\n') || '';

	  // Butonun tema rengini al
	  var themeR = $btn.css('--theme-r') || getComputedStyle(this).getPropertyValue('--theme-r').trim();
	  var themeG = $btn.css('--theme-g') || getComputedStyle(this).getPropertyValue('--theme-g').trim();
	  var themeB = $btn.css('--theme-b') || getComputedStyle(this).getPropertyValue('--theme-b').trim();
	  var themeColor = 'rgb(' + themeR + ',' + themeG + ',' + themeB + ')';
	  var themeBorderColor = 'rgba(' + themeR + ',' + themeG + ',' + themeB + ', 0.25)';
	  var themeGlowColor = 'rgba(' + themeR + ',' + themeG + ',' + themeB + ', 0.08)';

	  var tooltipHtml =
		'<div style="font-size:14px;font-weight:700;color:' + themeColor + ';margin-bottom:6px;letter-spacing:-0.01em;">' +
		  $('<span>').text(tooltipTitle).html() +
		'</div>' +
		(tooltipDesc ? '<div style="font-size:12.5px;color:rgba(255,255,255,0.7);line-height:1.5;">' +
		  $('<span>').text(tooltipDesc).html() +
		'</div>' : '');

	  var tooltip = $('<div class="custom-tooltip"></div>')
		.html(tooltipHtml)
		.css({
		  position: 'fixed',
		  'z-index': '9999',
		  'background': 'linear-gradient(135deg, rgba(15, 15, 20, 0.97) 0%, rgba(10, 10, 15, 0.97) 100%)',
		  padding: '12px 16px',
		  'border-radius': '12px',
		  'max-width': '300px',
		  'word-wrap': 'break-word',
		  'border': '1px solid ' + themeBorderColor,
		  'backdrop-filter': 'blur(20px)',
		  'box-shadow': '0 12px 32px rgba(0, 0, 0, 0.5), 0 0 0 1px rgba(255,255,255,0.04), inset 0 1px 0 rgba(255,255,255,0.04)',
		  'pointer-events': 'none'
		})
		.appendTo('body');

	  var btnRect = this.getBoundingClientRect();
	  tooltip.css({
		top: (btnRect.top - tooltip.outerHeight() - 12) + 'px',
		left: (btnRect.left + (btnRect.width / 2) - (tooltip.outerWidth() / 2)) + 'px'
	  });

	  $btn.data('custom-tooltip', tooltip);
	});

	// Butondan ayrılınca tooltip kaldır
	$(document).on('mouseleave', '.modern-welcome-action-btn', function() {
	  var tooltip = $(this).data('custom-tooltip');
	  if (tooltip) {
		tooltip.remove();
		$(this).removeData('custom-tooltip');
	  }
	});

	// Butona tıklanınca tüm tooltip'leri temizle
	$(document).on('mousedown click', '.modern-welcome-action-btn', function() {
	  window.clearAllTooltips();
	});

	// Sayfa/sekme geçişlerinde tüm tooltip'leri temizle
	$(document).on('click', '.sidebar-menu a, .nav-tabs a, [data-toggle="tab"]', function() {
	  window.clearAllTooltips();
	});

	$(document).on('shiny:inputchanged', function(event) {
	  if (event.name === 'quick_template' || event.name === 'tabs') {
		window.clearAllTooltips();
	  }
	});

	$(document).on('shiny:visualchange', function(event) {
	  // Yalnızca hoş geldin ekranı görünürken tooltip'leri temizle
	  var $welcome = $('#welcome_fullscreen_container');
	  if ($welcome.length > 0 && $welcome.is(':visible')) {
	    window.clearAllTooltips();
	  }
	});

	// Welcome container gizlendiğinde tooltip'leri temizle
	var welcomeVisObserver = new MutationObserver(function(mutations) {
	  mutations.forEach(function(mutation) {
		var target = mutation.target;
		if (target.classList && (target.classList.contains('hidden') || target.style.display === 'none')) {
		  window.clearAllTooltips();
		}
	  });
	});
	if (welcomeContainer) {
	  welcomeVisObserver.observe(welcomeContainer, { attributes: true, attributeFilter: ['class', 'style'] });
	}

	// Güvenlik ağı: Buton artık DOM'da değilse veya welcome gizliyse tooltip'leri temizle
	setInterval(function() {
	  var tooltips = $('.custom-tooltip');
	  if (tooltips.length === 0) return;

	  // Welcome ekranı gizliyse veya boşsa tüm tooltip'leri temizle
	  var $welcome = $('#welcome_fullscreen_container');
	  var welcomeHidden = $welcome.hasClass('hidden') ||
						  $welcome.css('display') === 'none' ||
						  $welcome.children().length === 0;
	  if (welcomeHidden) {
		window.clearAllTooltips();
		return;
	  }

	  // Üzerine gelinen buton yoksa kalan tooltip'leri temizle
	  var hoveredBtn = $('.modern-welcome-action-btn:hover');
	  if (hoveredBtn.length === 0) {
		window.clearAllTooltips();
	  }
	}, 300);
  });
});