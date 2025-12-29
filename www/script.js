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