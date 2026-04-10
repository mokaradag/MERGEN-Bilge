// www/js/shiny_message_handlers.js
// Shiny sunucusundan gelen özel mesajları işleyen handler'lar

$(document).ready(function() {

// Sistem Durumu sayfasındaki "Son Güncelleme" zamanını güncelle
  Shiny.addCustomMessageHandler('updateHealthTimestamp', function(data) {
    var el = document.getElementById('last_update_time');
    if (el && data && data.time) {
      el.textContent = 'Son Güncelleme: ' + data.time;
    }
  });

  // Yönetici Paneli sayfasındaki "Son Güncelleme" zamanını güncelle
  Shiny.addCustomMessageHandler('updateAdminTimestamp', function(data) {
    if (data && data.id && data.time) {
      var el = document.getElementById(data.id);
      if (el) {
        el.textContent = 'Son Güncelleme: ' + data.time;
      }
    }
  });

  Shiny.addCustomMessageHandler('showToast', function(data) {
    if (typeof window.showToast === 'function') {
      window.showToast(data.message, data.type || 'info');
    }
  });

  Shiny.addCustomMessageHandler('scrollToBottom', function(data) {
    if (typeof window.scrollToBottom === 'function') {
      window.scrollToBottom(data.smooth !== false);
    }
  });

  Shiny.addCustomMessageHandler('smartScrollToBottom', function(data) {
    if (typeof window.smartScrollToBottom === 'function') {
      window.smartScrollToBottom();
    }
  });

  Shiny.addCustomMessageHandler('initializeCodeMirror', function(data) {
    setTimeout(function() {
      if (typeof window.initializeCodeMirror === 'function') {
        window.initializeCodeMirror();
      }
    }, 100);
  });

  Shiny.addCustomMessageHandler('initializeCodeMirrorInElement', function(data) {
    if (data && data.elementId && typeof window.initializeCodeMirrorInElement === 'function') {
      setTimeout(function() {
        window.initializeCodeMirrorInElement(data.elementId);
      }, 100);
    }
  });

  Shiny.addCustomMessageHandler('updateFontSize', function(data) {
    const container = document.querySelector('.chat-container');
    if (!container) return;
    
    container.classList.remove('font-small', 'font-medium', 'font-large', 'font-xlarge');
    
    if (data.size === 'small') {
      container.classList.add('font-small');
    } else if (data.size === 'large') {
      container.classList.add('font-large');
    } else if (data.size === 'xlarge') {
      container.classList.add('font-xlarge');
    } else {
      container.classList.add('font-medium');
    }
    
    setTimeout(function() {
      if (typeof window.smartScrollToBottom === 'function') {
        window.smartScrollToBottom();
      }
    }, 100);
  });

  Shiny.addCustomMessageHandler('toggleAllTimestamps', function(data) {
    const timestamps = document.querySelectorAll('.message-time');
    const enabled = data.enabled === true;
    
    timestamps.forEach(function(ts) {
      if (enabled) {
        ts.classList.remove('hidden');
        ts.style.display = '';
      } else {
        ts.classList.add('hidden');
        ts.style.display = 'none';
      }
    });
  });

  Shiny.addCustomMessageHandler('toggleWidescreen', function(data) {
    const container = document.querySelector('.chat-container');
    if (!container) return;
    
    if (data.enabled === true) {
      container.classList.add('widescreen-mode');
    } else {
      container.classList.remove('widescreen-mode');
    }
  });

  // NOT: initStreamingMessage, streamingUpdate ve finalizeStreamingMessage
  // işleyicileri streaming_manager.js tarafından yönetilir.
  // Shiny her mesaj tipi için yalnızca bir işleyici desteklediğinden burada tekrar tanımlamıyoruz.

  Shiny.addCustomMessageHandler('updateFollowupSuggestions', function(data) {
    if (!data || !data.id || !data.followups) return;
    
    const container = document.getElementById('followup_container_' + data.id);
    if (!container) return;
    
    container.innerHTML = '';
    
    if (data.pending) {
      container.classList.add('pending');
    } else {
      container.classList.remove('pending');
    }
    
    var titleDiv = document.createElement('div');
    titleDiv.className = 'followup-suggestions-title';
    titleDiv.innerHTML = '<i class="fas fa-lightbulb"></i><span>Önerilen Takip Soruları</span>';
    container.appendChild(titleDiv);
    
    var listDiv = document.createElement('div');
    listDiv.className = 'followup-suggestions-list';
    
    data.followups.forEach(function(question) {
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'followup-option';
      btn.setAttribute('data-question', question);
      
      var textSpan = document.createElement('span');
      textSpan.textContent = question;
      btn.appendChild(textSpan);
      
      var icon = document.createElement('i');
      icon.className = 'fas fa-arrow-up-right-from-square';
      btn.appendChild(icon);
      
      listDiv.appendChild(btn);
    });
    
    container.appendChild(listDiv);
  });

  // NOT: playAudioMessage işleyicisi tts_manager.js'deki kuyruk sistemi tarafından yönetilir.
  // Burada tekrar tanımlamıyoruz, çünkü Shiny her mesaj tipi için yalnızca bir işleyici destekler.

  Shiny.addCustomMessageHandler('showNeuralAnimation', function(message) {
    setTimeout(function() {
      if (window.NeuralWelcomeAnimation && typeof window.NeuralWelcomeAnimation.init === 'function') {
        window.NeuralWelcomeAnimation.init();
      }
    }, 120);
  });

  var modernWelcomeBootTimer = null;

	function clearModernWelcomeBootTimer() {
	  if (modernWelcomeBootTimer) {
		clearTimeout(modernWelcomeBootTimer);
		modernWelcomeBootTimer = null;
	  }
	}

	  function bootModernWelcome(message, attempt) {
		attempt = attempt || 0;

		const MAX_ATTEMPTS = 60;
		const RETRY_DELAY_MS = 20;

	  const welcomeContainer = document.querySelector('.modern-welcome-root');
	  const videoContainer = document.querySelector('.modern-welcome-video-container');
	  const neuralCanvas = document.querySelector('.modern-welcome-neural-canvas');
	  const greetingText = document.getElementById('dynamic-greeting-text');

	  const domReady = !!(
		welcomeContainer &&
		welcomeContainer.offsetParent !== null &&
		videoContainer &&
		neuralCanvas &&
		greetingText
	  );

	  const depsReady = !!(
		window.WelcomeVideoPlayer &&
		window.WelcomeNeuralNetwork &&
		window.WelcomeGreeting
	  );

	  if ((!domReady || !depsReady) && attempt < MAX_ATTEMPTS) {
		modernWelcomeBootTimer = setTimeout(function() {
		  bootModernWelcome(message, attempt + 1);
		}, RETRY_DELAY_MS);
		return;
	  }

	  modernWelcomeBootTimer = null;

	  if (!domReady || !depsReady) {
		console.warn('[WELCOME] Modern welcome bileşenleri zamanında hazır olmadı.');
		return;
	  }

	  if (window.WelcomeVideoPlayer && window.WelcomeVideoPlayer.destroy) {
		window.WelcomeVideoPlayer.destroy();
	  }
	  if (window.WelcomeNeuralNetwork && window.WelcomeNeuralNetwork.destroy) {
		window.WelcomeNeuralNetwork.destroy();
	  }
	  if (window.WelcomeGreeting && window.WelcomeGreeting.destroy) {
		window.WelcomeGreeting.destroy();
	  }

	  if (videoContainer) {
		window.WelcomeVideoPlayer.init(videoContainer);
	  }

	  if (neuralCanvas) {
		var accentColor = message && message.accentColor ? message.accentColor : null;
		if (!accentColor) {
		  var activeBtn = document.querySelector('.character-btn.active');
		  if (activeBtn) {
			accentColor = getComputedStyle(activeBtn).getPropertyValue('--character-accent').trim() || null;
		  }
		}
		window.WelcomeNeuralNetwork.init(neuralCanvas, accentColor);
	  }

	  if (greetingText) {
		window.WelcomeGreeting.init(greetingText);
	  }
	}

	  Shiny.addCustomMessageHandler('initModernWelcome', function(message) {
		clearModernWelcomeBootTimer();

		requestAnimationFrame(function() {
		  bootModernWelcome(message || {}, 0);
		});
	  });

  // NOT: Müzik işleyicileri (initMusicManager, toggleMusic, setMusicPlaylist, setMusicCharacter, setMusicVolume)
  // music_manager.js tarafından yönetilir. Burada tekrar tanımlamıyoruz.

  Shiny.addCustomMessageHandler('saveCurrentChat', function(messages) {
    try {
      if (messages && messages.length > 0) {
        localStorage.setItem('mergen_current_chat', JSON.stringify(messages));
      }
    } catch (e) {
      console.warn('Chat kaydedilemedi:', e);
    }
  });

  Shiny.addCustomMessageHandler('highlightSearchMatch', function(data) {
    if (!data || !data.messageId) return;
    
    const wrapper = document.getElementById('message_wrapper_' + data.messageId);
    if (!wrapper) return;
    
    wrapper.scrollIntoView({ behavior: 'smooth', block: 'center' });
    
    wrapper.classList.add('search-match-highlight');
    
    setTimeout(function() {
      wrapper.classList.remove('search-match-highlight');
    }, 3000);
  });

  Shiny.addCustomMessageHandler('clearSearchHighlights', function(data) {
    const highlighted = document.querySelectorAll('.search-match-highlight');
    highlighted.forEach(function(el) {
      el.classList.remove('search-match-highlight');
    });
  });

  window.addEventListener('beforeunload', function() {
    const chatContainer = document.getElementById('chat_content_container');
    if (chatContainer) {
      const messages = chatContainer.querySelectorAll('.message-bubble');
      if (messages.length > 0) {
        const messageData = [];
        messages.forEach(function(msg) {
          const wrapper = msg.closest('[id^="message_wrapper_"]');
          if (wrapper) {
            const id = wrapper.id.replace('message_wrapper_', '');
            const type = msg.classList.contains('user-message') ? 'user' : 'ai';
            const content = msg.textContent || '';
            
            messageData.push({ id: id, type: type, content: content });
          }
        });
        
        if (messageData.length > 0) {
          try {
            localStorage.setItem('mergen_current_chat', JSON.stringify(messageData));
          } catch (e) {
            console.warn('Chat kaydedilemedi:', e);
          }
        }
      }
    }
  });

  setTimeout(function() {
    try {
      const savedChat = localStorage.getItem('mergen_current_chat');
      if (savedChat) {
        const messages = JSON.parse(savedChat);
        if (messages && messages.length > 0) {
          Shiny.setInputValue('load_chat_from_storage', messages, { priority: 'event' });
        }
      }
    } catch (e) {
      console.warn('Chat yüklenemedi:', e);
    }
  }, 1000);

  Shiny.addCustomMessageHandler('removeExcelFromContext', function(msg) {
    var filenames = msg.filenames || [];
    filenames.forEach(function(fname) {
      var checkboxes = document.querySelectorAll('input.attach-checkbox[data-filename="' + fname + '"]');
      checkboxes.forEach(function(cb) {
        if (cb.checked) {
          cb.checked = false;
          var fid = cb.getAttribute('data-file-id');
          Shiny.setInputValue('file_manager_module-attach_toggled', {
            id: fid,
            filename: fname,
            checked: false,
            nonce: Math.random()
          }, {priority: 'event'});
        }
      });
    });
  });

  // Hızlı eylem butonları için güvenli işleyici (inline JS söz dizimi hatasını önler)
  // Mesaj metni Base64 ile kodlanmış data attribute'den okunur
  window._handleQuickAction = function(btn) {
    if (!btn) return;
    var msgB64 = btn.getAttribute('data-action-message') || '';
    var model = btn.getAttribute('data-action-model') || '';
    var actionId = btn.getAttribute('data-action-id') || '';

    // Base64 kodunu çöz
    var text = '';
    try {
      text = decodeURIComponent(escape(atob(msgB64)));
    } catch(e) {
      try { text = atob(msgB64); } catch(e2) { text = ''; }
    }

    Shiny.setInputValue('quick_template', {
      text: text,
      model: model,
      action_id: actionId
    }, {priority: 'event'});

    $('.custom-tooltip').remove();
    $('#welcome_fullscreen_container').fadeOut(300);
  };

});