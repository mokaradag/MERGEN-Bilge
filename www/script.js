    let globalMessageObserver = null;
        
    $(document).ready(function() {
                              
          // Initialize near bottom flag
          window.isNearBottom = true;
          
          // Initialize any CodeMirror instances
          if (window.initializeCodeMirrorInElement) {
            $('.code-container').each(function() {
              const wrapperId = $(this).closest('[id^="message_wrapper_"]').attr('id');
              if (wrapperId) {
                window.initializeCodeMirrorInElement(wrapperId);
              }
            });
          }
    
          // Set up auto-resize for textarea
      const messageInput = document.getElementById('message_input');
      if (messageInput) {
        messageInput.addEventListener('input', function() {
          this.style.height = 'auto';
          this.style.height = Math.min(this.scrollHeight, 150) + 'px';
        });
      }
                    
      // Global variables
      window.isNearBottom = true;
      let sessionTimeout;
      let warningShown = false;
    
      // Performance monitoring
      const performanceMonitor = window.performanceMonitor || {
        start: function(action) { this[action + '_start'] = performance.now(); },
        end: function(action) {
          const duration = performance.now() - this[action + '_start'];
          Shiny.setInputValue('performance_data', { action: action, duration: Math.round(duration) }, { priority: 'event' });
        }
      };
    
        // Check if near bottom
        $(document).on('scroll', '.chat-content-wrapper', function() {
          const threshold = 100;
          const isNear = this.scrollHeight - this.scrollTop - this.clientHeight < threshold;
          window.isNearBottom = isNear;
        });
                
        // Debounced input handler
        const debouncedInputHandler = debounce(function(element) {
            adjustTextareaHeight(element);
            window.updateCharCounter();
        }, 300);
        
        $(document).on('input', '.chat-input', function() { 
            debouncedInputHandler(this);
        });
    
      // Send button handler with FIX #3 for character counter
      $(document).on('click', '#send_stop_btn', function(event) {
        if ($(this).hasClass('stop-mode')) {
          return;
        }
        event.preventDefault();
    
        const textarea = $('.chat-input');
        const promptText = textarea.val() || '';
    
        if (promptText.trim().length === 0 && $('#file_prompt_indicator_ui').children().length === 0) {
          return;
        }
    
        Shiny.setInputValue("send_prompt_from_js", {
          text: promptText,
          nonce: Math.random()
        }, { priority: "event" });
    
        textarea.val('');
        if (textarea[0]) window.adjustTextareaHeight(textarea[0]);
        window.updateCharCounter();  // FIX #3: Reset counter
        textarea.focus();
    
        setTimeout(() => scrollToBottom(true), 50);
      });
    
      // Keyboard shortcuts
      $(document).on('keyup', function(e) {
        const chatInput = $(e.target);
        if (chatInput.is('.chat-input')) {
          if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            const promptText = chatInput.val() || '';
    
            if (promptText.trim().length === 0 && $('#file_prompt_indicator_ui').children().length === 0) {
              return;
            }
    
            Shiny.setInputValue("send_prompt_from_js", {
              text: promptText,
              nonce: Math.random()
            }, { priority: "event" });
    
            chatInput.val('');
            if (chatInput[0]) window.adjustTextareaHeight(chatInput[0]);
            window.updateCharCounter();  // FIX #3: Reset counter
            setTimeout(() => scrollToBottom(true), 50);
    
          } else if (e.key === 'Escape') {
            e.preventDefault();
            e.target.value = '';
            window.updateCharCounter();
            window.adjustTextareaHeight(e.target);
          }
          return;
        }
    
        // Global shortcuts
        if (e.ctrlKey && e.key === 'n') {
          e.preventDefault();
          $('#new_chat_btn').click();
        }
        if (e.ctrlKey && e.key === 'u') {
          e.preventDefault();
          $('#file_upload').click();
        }
    
        if (e.key === 'PageUp') {
          e.preventDefault();
          $('.chat-container').animate({ scrollTop: '-=300' }, 200);
        }
        if (e.key === 'PageDown') {
          e.preventDefault();
          $('.chat-container').animate({ scrollTop: '+=300' }, 200);
        }
        if (e.key === 'Escape') {
          $('.modal').modal('hide');
        }
      });
    
      $(document).on('keydown', '.chat-input', function(e) {
        if (e.key === 'Enter' && !e.shiftKey) e.preventDefault();
      });
    
      $('.chat-container').on('scroll', checkScrollPosition);
        
        // add passive listeners to quiet DevTools scroll/touch warnings
        const _chatEl = document.querySelector('.chat-container');
        if (_chatEl) {
          _chatEl.addEventListener('wheel', () => {}, { passive: true });
          _chatEl.addEventListener('touchstart', () => {}, { passive: true });
          _chatEl.addEventListener('touchmove', () => {}, { passive: true });
        }
    
      $(document).on('click', '#scroll_to_bottom', function() { scrollToBottom(true); });
              
      $(document).on('click', '.followup-option', function(e) {
        e.preventDefault();
        const question = $(this).data('question');
        if (!question || !window.Shiny || !Shiny.setInputValue) {
          return;
        }
        Shiny.setInputValue('followup_question_clicked', {
          text: question,
          nonce: Date.now()
        }, { priority: 'event' });
      });
    
      $(document).on('shown.bs.tab', 'a[data-toggle="tab"]', function(e) {
        const tabId = $(e.target).attr('data-value');
        if (tabId) {
          localStorage.setItem('mergen_active_tab', tabId);
        }
      });
    
      /* On shiny connected: restore last tab & PREAPPLY widescreen from saved settings
         so layout is correct even before server's first message arrives. */
      $(document).on('shiny:connected', function(event) {
        // PREAPPLY widescreen from localStorage if available
        try {
          const raw = localStorage.getItem('mergen_settings');
          if (raw) {
            const settings = JSON.parse(raw);
            if (typeof settings.enable_widescreen === 'boolean') {
              applyWidescreen(!!settings.enable_widescreen);
            }
          }
        } catch (e) { /* ignore */ }
    
        setTimeout(() => { if (window.updateCharCounter) window.updateCharCounter(); }, 100);
      });
                                    
          // Attach single handler
        $(document).on('click', '[data-chat-id]', function(e) {
          e.preventDefault();
          e.stopPropagation();
          
          const $elem = $(this);
          const chatId = $elem.attr('data-chat-id');
          
          // FIXED: Remove problematic loading class check that was blocking first clicks
          // Simply send the event directly
          Shiny.setInputValue("saved_chats_module-load_chat_id", chatId, {priority: "event"});
          
          return false;
        });
                                
      $(window).on('focus', function() {
        if (document.title.startsWith('(1)')) {
          document.title = 'MERGEN Bilge';
        }
      });
    
      // Message observer
      const messageObserver = new MutationObserver(muts => {
        let shouldScroll = false;
        muts.forEach(m => {
          m.addedNodes && m.addedNodes.forEach(node => {
            if (!(node instanceof HTMLElement)) return;
    
            if (node.id === 'typing-animation-wrapper') {
              TypingAnimationManager.create(node);
              shouldScroll = true;
            } else if (node.classList.contains('message-bubble')) {
              // Ensure the wrapper around this bubble matches current widescreen state
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
        globalMessageObserver.observe(chatContainer, { childList: true, subtree: true });
      }
    	  
        // Auto-init CM whenever a .codemirror-textarea is inserted
        (function attachCMObserver(){
          const root = document.querySelector('#chat_content_container, #_content_container, .chat-container');
          if (!root) { console.warn('[MERGEN] CM observer: root not found'); return; }
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
          obs.observe(root, { childList: true, subtree: true });
        })();
    
        $(document).on('shiny:disconnected', function(event) {
          // Clean up ALL observers and timers
          if (globalMessageObserver) {
            globalMessageObserver.disconnect();
            globalMessageObserver = null;
          }
          TypingAnimationManager.destroy();
          // Clear any pending timeouts
          if (window.pendingTimeouts) {
            window.pendingTimeouts.forEach(clearTimeout);
          }
          $('.disconnect-overlay').css('display', 'flex');
        });
    
        // Reinitialize on Shiny reconnection
        $(document).on('shiny:connected', function(event) {
          // Reinitialize CodeMirror observer
          (function attachCMObserver(){
            const root = document.querySelector('#chat_content_container, #_content_container, .chat-container');
            if (!root) { console.warn('[MERGEN] CM observer: root not found'); return; }
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
            obs.observe(root, { childList: true, subtree: true });
            console.log('[MERGEN] CodeMirror observer reinitialized after reconnection');
          })();
        });
    
      // Other functions
        window.sendCapabilityMessage = function(message, model) {
          if (model) {
            console.log('Setting model to:', model);
            
            // First update the model via Shiny
            Shiny.setInputValue('quick_action_model_change', model, {priority: 'event'});
            
            // Then send the message after a short delay
            setTimeout(function() {
              document.getElementById('user_input').value = message;
              document.getElementById('user_input').dispatchEvent(new Event('input'));
              
              // Another small delay before clicking send
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
            
      // (Moved to global scope) window.initializeCodeMirrorInElement
    
      // (Moved to global scope) window.copyCodeFromCM
        
      // Toast function (moved global) and expose as window for any top-level calls (defensive)
      // also expose as window for any top-level calls (defensive)
      // window.showToast = showToast; // already set globally
    
      // Make isNearBottom available globally for streaming
      window.isNearBottom = isNearBottom;
    
      /* ==========================================================
         ISSUE 2 FIX: Copy functionality for AI messages during/after streaming
         ========================================================== */
        // (Moved to global scope) window.copyAIMessageContent  
    
    }); // end document.ready
        	    
// Handle source link clicks
$(document).on('click', '.source-link', function() {
  const filename = $(this).data('filename');
  const sourceId = $(this).data('source-id');
  
  console.log('[SOURCE CLICK] User clicked:', filename);
  console.log('[SOURCE CLICK] Source ID:', sourceId);
  
  Shiny.setInputValue('source_file_clicked', {
    filename: filename,
    sourceId: sourceId,
    nonce: Math.random()
  }, {priority: 'event'});
});

$(document).ready(function() {
  if (!window.__analysisFileLinkBound) {
    window.__analysisFileLinkBound = true;
    
    $(document).on('click', '.analysis-file-link', function(e) {
      e.preventDefault();
      e.stopPropagation();
      
      var filepath = $(this).attr('data-filepath');
      
      if (filepath) {
        Shiny.setInputValue('analysis_file_clicked', {
          filepath: filepath,
          nonce: Math.random()
        }, {priority: 'event'});
      }
    });
  }
});