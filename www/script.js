    let globalMessageObserver = null;
        
    $(document).ready(function() {
        // ensure toast container exists early
        if (!document.getElementById('toast-container')) {
          const tc = document.createElement('div');
          tc.id = 'toast-container';
          tc.className = 'toast-container';
          document.body.appendChild(tc);
        }
        
        // Ensure material-darker theme exists; inject safe fallback if missing
        (function ensureCMTheme(){
          const hasThemeCss = Array.from(document.styleSheets).some(ss => {
            try { return Array.from(ss.cssRules || []).some(r => (r.selectorText||'').includes('.cm-s-material-darker.CodeMirror')); }
            catch(e){ return false; }
          });
          if (!hasThemeCss) {
            const style = document.createElement('style');
            style.textContent = `
              .cm-s-material-darker.CodeMirror{background:#263238!important;color:#eceff1!important}
              .cm-s-material-darker .CodeMirror-gutters{background:#263238!important;border-right:none!important}
              .cm-s-material-darker .CodeMirror-linenumber{color:#90a4ae!important}
            `;
            document.head.appendChild(style);
            console.warn('[MERGEN] CodeMirror theme CSS not found; injected safe fallback.');
          }
        })();
    
        // Watch for programmatic changes to the settings dropdown
          const settingsObserver = new MutationObserver(function(mutations) {
            const dropdown = document.querySelector('#settings_module-model_selection');
            if (dropdown && dropdown.selectize) {
              const currentValue = dropdown.selectize.getValue();
              if (currentValue) {
                // Trigger change event to update Shiny
                $(dropdown).trigger('change');
              }
            }
          });
          
          // Start observing when settings tab is visible
          $(document).on('click', '[data-value="settings"]', function() {
            setTimeout(function() {
              const dropdown = document.querySelector('#settings_module-model_selection');
              if (dropdown) {
                settingsObserver.observe(dropdown.parentNode, {
                  childList: true,
                  subtree: true
                });
              }
            }, 100);
          });
        
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
            
      // Anti-dimming
      (function antiDim() {
        if (document.getElementById('anti-dim-style')) return;
        const style = document.createElement('style');
        style.id = 'anti-dim-style';
        style.textContent = `
          body.shiny-busy::before,
          body.shiny-busy::after {
            display: none !important;
            content: '' !important;
            opacity: 0 !important;
            pointer-events: none !important;
          }
        `;
        document.head.appendChild(style);
      })();
    
      // App branding
        (function setBranding() {
          document.title = 'MERGEN Bilge';
          const linkId = 'app-favicon';
          let link = document.getElementById(linkId);
          if (!link) {
            link = document.createElement('link');
            link.id = linkId;
            link.rel = 'icon';
            link.type = 'image/png';
            document.head.appendChild(link);
          }
          link.href = 'mergen_avatar.png';
        })();
    
      // Global variables
      window.isNearBottom = true;
      let dragCounterChat = 0;
      let dragCounterFM = 0;
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
    
      // FIX #12: Drag & Drop for single file only
      const $chatWrapper = $('#chat_input_wrapper');
      let chatFileTimeout = null;
      
      $(document).on('dragenter', '#chat_input_wrapper, #chat_input_wrapper *', function (e) {
        e.preventDefault(); e.stopPropagation();
        dragCounterChat++;
        if (dragCounterChat === 1) { $('#drop_zone').removeClass('hidden'); $chatWrapper.addClass('dragging'); }
      });
      
      $(document).on('dragleave', '#chat_input_wrapper, #chat_input_wrapper *', function (e) {
        e.preventDefault(); e.stopPropagation();
        dragCounterChat--;
        if (dragCounterChat <= 0) { dragCounterChat = 0; $('#drop_zone').addClass('hidden'); $chatWrapper.removeClass('dragging'); }
      });
      
      $(document).on('dragover', '#chat_input_wrapper, #chat_input_wrapper *', function (e) { 
        e.preventDefault(); 
        e.stopPropagation(); 
      });
      
      $(document).on('drop', '#chat_input_wrapper, #drop_zone', function (e) {
        e.preventDefault(); e.stopPropagation();
        dragCounterChat = 0; 
        $('#drop_zone').addClass('hidden'); 
        $chatWrapper.removeClass('dragging');
    
        const files = (e.originalEvent && e.originalEvent.dataTransfer && e.originalEvent.dataTransfer.files) ? 
                      e.originalEvent.dataTransfer.files : null;
        if (!files || !files.length) return;
    
        // FIX #12: Only process first file
        if (files.length > 1) {
          showToast('Sadece tek dosya yüklenebilir. İlk dosya işleniyor.', 'warning');
        }
    
        // Clear any pending timeout
        if (chatFileTimeout) {
          clearTimeout(chatFileTimeout);
        }
        
        // Add small delay to ensure DOM is ready
        chatFileTimeout = setTimeout(() => {
          const input = document.getElementById('file_upload');
          if (input) {
            const dt = new DataTransfer();
            dt.items.add(files[0]); // Only add first file
            input.files = dt.files;
            
            // Trigger change event
            const changeEvent = new Event('change', { bubbles: true });
            input.dispatchEvent(changeEvent);
          } else {
            showToast('Dosya yükleme hatası. Lütfen tekrar deneyin.', 'error');
          }
        }, 100);
      });
      
      // Also handle the file button click
      $(document).on('click', '#file_btn_container', function(e) {
        e.preventDefault();
        e.stopPropagation();
        const fileInput = document.getElementById('file_upload');
        if (fileInput) {
          fileInput.click();
        }
      });
    
      // File Manager drag & drop (unchanged)
      const $fmDrop = $('#file_manager_module-main_drop_zone');
      $(document).on('dragenter', '#file_manager_module-main_drop_zone, #file_manager_module-main_drop_zone *', function (e) {
        e.preventDefault(); e.stopPropagation();
        dragCounterFM++;
        if (dragCounterFM === 1) $fmDrop.addClass('dragging');
      });
      $(document).on('dragleave', '#file_manager_module-main_drop_zone, #file_manager_module-main_drop_zone *', function (e) {
        e.preventDefault(); e.stopPropagation();
        dragCounterFM--;
        if (dragCounterFM <= 0) { dragCounterFM = 0; $fmDrop.removeClass('dragging'); }
      });
      $(document).on('dragover', '#file_manager_module-main_drop_zone, #file_manager_module-main_drop_zone *', function (e) { e.preventDefault(); e.stopPropagation(); });
        $(document).on('drop', '#file_manager_module-main_drop_zone', function (e) {
          e.preventDefault(); e.stopPropagation();
          dragCounterFM = 0; $fmDrop.removeClass('dragging');
        
          const files = (e.originalEvent && e.originalEvent.dataTransfer && e.originalEvent.dataTransfer.files)
                          ? e.originalEvent.dataTransfer.files : null;
          if (!files || !files.length) return;
        
          try {
            const input = document.getElementById('file_manager_module-bulk_upload');
            if (!input) return;
            const dt = new DataTransfer();
        
            input.value = '';
        
            for (let i = 0; i < files.length; i++) dt.items.add(files[i]);
            input.files = dt.files;
            input.dispatchEvent(new Event('change', { bubbles: true }));
          } catch (err) {
            console.error('File Manager DnD assignment failed:', err);
            showToast('Dosya bırakma başarısız oldu.', 'error');
          }
        });

        function updateBulkUploadProgressBar() {
          const $progress = $('#bulk_upload_div .shiny-file-input-progress');
          if (!$progress.length) return;

          const $bar = $progress.find('.progress-bar');
          const $label = $progress.find('span');

          if ($label.length) {
            const text = ($label.text() || '').trim();
            if (/upload complete/i.test(text)) {
              $label.text('Aktarım için hazır');
              $bar.addClass('upload-complete');
            } else if (/uploading/i.test(text)) {
              $label.text('Yükleniyor...');
              $bar.removeClass('upload-complete');
            } else {
              $bar.removeClass('upload-complete');
            }
          }
        }

        function initBulkUploadProgressObserver() {
          const container = document.querySelector('#bulk_upload_div');
          if (!container || container._bulkProgressObserver) return;

          const observer = new MutationObserver(() => updateBulkUploadProgressBar());
          observer.observe(container, { childList: true, subtree: true, characterData: true });
          container._bulkProgressObserver = observer;
          updateBulkUploadProgressBar();
        }

        initBulkUploadProgressObserver();

        $(document).on('change', '#file_manager_module-bulk_upload', function () {
          const hasFiles = this.files && this.files.length > 0;
            const $grp = $(this).closest('.input-group');
            const $txt = $grp.find('.form-control');
            if (hasFiles) {
              $txt.val(Array.from(this.files).map(f => f.name).join(', '));
            } else {
              $txt.val('').attr('placeholder', 'Henüz dosya seçilmedi');
            }
          const $progress = $('#bulk_upload_div .shiny-file-input-progress');
          if (hasFiles && $progress.length) {
            $progress.show();
            $progress.find('.progress-bar').removeClass('upload-complete');
          }
          const $container = $('#file_manager_module-execute_bulk_upload_container');

          if (hasFiles) {
            // Clear any existing buttons first
            $container.empty();
            
            // Create button container
            const $buttonWrapper = $('<div></div>').css({
              'display': 'flex',
              'justify-content': 'center',
              'gap': '10px',
              'margin-top': '20px'
            });
            
            // Create "Dosyaları Yükle" button
            const $uploadBtn = $('<button></button>')
              .attr('id', 'file_manager_module-execute_bulk_upload')
              .addClass('btn btn-modern btn-success')
              .html('<i class="fas fa-upload"></i> Dosyaları Yükle');
            
            // Create "Dosyaları Temizle" button  
            const $clearBtn = $('<button></button>')
              .attr('id', 'file_manager_module-clear_pending_files')
              .addClass('btn btn-modern btn-warning')
              .html('<i class="fas fa-times"></i> Dosyaları Temizle');
            
            // Add buttons to wrapper and container
            $buttonWrapper.append($uploadBtn).append($clearBtn);
            $container.append($buttonWrapper).show();
            
            // Handle upload button click
            $uploadBtn.off('click').on('click', function(e) {
              e.preventDefault();
              Shiny.setInputValue('file_manager_module-execute_bulk_upload', Math.random(), {priority: 'event'});
                // Immediately clear the visible caption and the file input (UX)
                const $input = $('#file_manager_module-bulk_upload');
                if ($input.length) {
                  const $grp = $input.closest('.input-group');
                  $input.val('');
                  $grp.find('.form-control').val('').attr('placeholder', 'Henüz dosya seçilmedi');
                 }
                const $progress = $('#bulk_upload_div .shiny-file-input-progress');
                $progress.hide();
                $progress.find('.progress-bar').removeClass('upload-complete');
                $('#bulk_upload_div .progress').hide();
                $progress.find('.progress-bar').css('width', '0%');
                $progress.find('.progress-bar').text('');
                $progress.find('span').text('');
            });

            // Handle clear button click
            $clearBtn.off('click').on('click', function(e) {
              e.preventDefault();
              // Clear the file input
              $('#file_manager_module-bulk_upload').val('');
              // Trigger change to reset UI
              $('#file_manager_module-bulk_upload').trigger('change');
              // Hide the container
              $container.hide().empty();
              // Show toast notification
              showToast('Dosya seçimi temizlendi', 'info');
              const $progress = $('#bulk_upload_div .shiny-file-input-progress');
              $progress.hide();
              $progress.find('.progress-bar').removeClass('upload-complete');
              $('#bulk_upload_div .progress').hide();
              $progress.find('.progress-bar').css('width', '0%');
              $progress.find('.progress-bar').text('');
              $progress.find('span').text('');
            });

          } else {
            $container.hide().empty();
          }
        });
    
      $(document).on('click', '.js-file-action', function (e) {
        e.preventDefault();
        e.stopPropagation();
        const action = $(this).data('action');
        const fileId = $(this).data('file-id') || $(this).data('id') || $(this).attr('data-file-id');
        if (action && fileId) {
          Shiny.setInputValue(
            "file_manager_module-file_action",
            { action: action, id: String(fileId), nonce: Math.random() },
            { priority: 'event' }
          );
        }
      });

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
    
        // Prevent default drop behavior
        $(document).on('dragover dragenter', function(e) {
          e.preventDefault();
          e.stopPropagation();
        });
        
        $(document).on('drop', function(e) {
          e.preventDefault();
          e.stopPropagation();
        });
            
        // Single consolidated download handler  
        $(document).on('click', '.file-download, .js-download-btn', function(e) {
          e.preventDefault();
          e.stopPropagation();
        
          const $btn = $(this);
          const fileId = $btn.attr('data-download-id') ||
                         $btn.closest('.file-actions').find('[data-file-id]').first().data('file-id');
          if (!fileId) return;
        
          const linkId = 'file_manager_module-download_' + fileId; // namespaced id
          const linkEl = document.getElementById(linkId);
          if (!linkEl) {
            showToast('İndir linki hazırlanamadı.', 'error');
            return;
          }
        
          // If Shiny hasn't populated href yet, wait briefly and retry.
          const tryClick = (retries = 15) => {
            const href = linkEl.getAttribute('href');
            if (href && href.trim() !== '' && href !== '#') {
              linkEl.click(); // triggers the Shiny download
            } else if (retries > 0) {
              setTimeout(() => tryClick(retries - 1), 100);
            } else {
              showToast('İndirme hazırlanamadı. Lütfen tekrar deneyin.', 'error');
            }
          };
        
          tryClick();
        });
        
        // Extra guard: never navigate on empty download links (prevents reloads)
        $(document).on('click', 'a.shiny-download-link', function(e) {
          const href = $(this).attr('href');
          if (!href || href.trim() === '' || href === '#') {
            e.preventDefault();
            e.stopPropagation();
            return false;
          }
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
        
        // Fix Issue 8: Handle file drop with debouncing
        function handleFileDrop(files) {
          if (window.fileUploadTimeout) {
            clearTimeout(window.fileUploadTimeout);
          }
          
          window.fileUploadTimeout = setTimeout(() => {
            // Process files only once
            const fileList = Array.from(files);
            if (fileList.length > 0) {
              // Trigger upload only once
              Shiny.setInputValue('files_dropped', fileList.map(f => ({
                name: f.name,
                size: f.size,
                type: f.type
              })), {priority: 'event'});
            }
          }, 100);
        }
                        
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