    let globalMessageObserver = null;
    
    /* NEW: global widescreen flag and helpers */
    let isWidescreenMode = false; // authoritative client-side flag
    
    // Helper: add/remove widescreen classes on containers & wrappers in one place
    function applyWidescreen(enabled, scopeEl) {
      isWidescreenMode = !!enabled;
    
      const $scope = scopeEl ? $(scopeEl) : $(document);
    
      // Containers
      const $chat = $scope.find('.chat-container').length ? $scope.find('.chat-container') : $('.chat-container');
      const $input = $scope.find('.input-container').length ? $scope.find('.input-container') : $('.input-container');
      const $content = $scope.find('.content-wrapper').length ? $scope.find('.content-wrapper') : $('.content-wrapper');
      const $chatContentWrapper = $scope.find('.chat-content-wrapper').length ? $scope.find('.chat-content-wrapper') : $('.chat-content-wrapper');
    
      if (enabled) {
        $chat.addClass('widescreen-mode');
        $input.addClass('widescreen-mode');
        $content.addClass('widescreen-mode'); // harmless if not styled
        $chatContentWrapper.addClass('widescreen').removeClass('normal-screen');
      } else {
        $chat.removeClass('widescreen-mode');
        $input.removeClass('widescreen-mode');
        $content.removeClass('widescreen-mode');
        $chatContentWrapper.removeClass('widescreen').addClass('normal-screen');
      }
    
      updateMessageWrappersForWidescreen($scope);
    }
    
    // Helper: normalize every message wrapper width to match the current mode
    function updateMessageWrappersForWidescreen(scopeEl) {
      const $scope = scopeEl ? $(scopeEl) : $(document);
      const $wrappers = $scope.find('[id^="message_wrapper_"]');
    
      if (isWidescreenMode) {
        $wrappers.removeClass('narrow-wrapper');
      } else {
        $wrappers.addClass('narrow-wrapper');
      }
    }
    
    /* ==========================================================
       ISSUE 4 & 6 FIX: Enhanced streaming markdown parser
       (with code detection, styled streaming blocks, improved MD)
       ========================================================== */
    function parseStreamingMarkdown(text) {
      if (!text) return '';
      
      let html = text;
      
      // Check for incomplete code blocks
      const codeBlockMatches = text.match(/```/g);
      const isInCodeBlock = codeBlockMatches && codeBlockMatches.length % 2 === 1;
      
      if (isInCodeBlock) {
        const lastCodeBlockStart = text.lastIndexOf('```');
        const beforeCode = text.substring(0, lastCodeBlockStart);
        const codeContent = text.substring(lastCodeBlockStart);
        
        let parsedBefore = parseMarkdownWithoutCode(beforeCode);
        
        const langMatch = codeContent.match(/```(\w+)?\n?/);
        const language = langMatch && langMatch[1] ? langMatch[1] : 'plaintext';
        const codeLines = codeContent.substring(codeContent.indexOf('\n') + 1);
        
        // Create streaming code block with immediate visibility
        const codeHtml = `
          <div class="code-container streaming-code">
            <div class="code-header">
              <span class="code-language">${language}</span>
              <span class="streaming-indicator">
                <i class="fas fa-circle-notch"></i> Streaming...
              </span>
            </div>
            <pre class="code-content streaming"><code class="${language}">${escapeHtml(codeLines)}</code></pre>
          </div>
        `;
        
        return parsedBefore + codeHtml;
      }
      
      // Parse complete code blocks
      html = html.replace(/```(\w+)?\n([\s\S]*?)```/g, function(match, lang, code) {
        lang = lang || 'plaintext';
        return `
          <div class="code-container">
            <div class="code-header">
              <span class="code-language">${lang}</span>
            </div>
            <pre class="code-content"><code class="${lang}">${escapeHtml(code)}</code></pre>
          </div>
        `;
      });
      
      return parseMarkdownWithoutCode(html);
    }
    
    // Helper: create streaming code block with simple syntax highlighting simulation
    function createStreamingCodeBlock(code, language) {
      const displayLang = language.toUpperCase();
      const lines = code.split('\n');
      const lineNumbers = lines.map((_, i) => i + 1).join('\n');
      
      let highlightedCode = escapeHtml(code);
      
      // Basic syntax highlighting
      if (['r', 'python', 'javascript', 'js'].includes(language.toLowerCase())) {
        const keywords = language.toLowerCase() === 'r' ? 
          ['function', 'if', 'else', 'for', 'while', 'return', 'library', 'require'] :
          language.toLowerCase() === 'python' ?
          ['def', 'class', 'if', 'else', 'elif', 'for', 'while', 'return', 'import', 'from'] :
          ['function', 'if', 'else', 'for', 'while', 'return', 'const', 'let', 'var'];
        
        keywords.forEach(kw => {
          const regex = new RegExp(`\\b${kw}\\b`, 'g');
          highlightedCode = highlightedCode.replace(regex, `<span style="color: #c678dd;">${kw}</span>`);
        });
        
        // Highlight strings
        highlightedCode = highlightedCode.replace(/"([^"\\]|\\.)*"/g, '<span style="color: #98c379;">$&</span>');
        highlightedCode = highlightedCode.replace(/'([^'\\]|\\.)*'/g, '<span style="color: #98c379;">$&</span>');
        
        // Highlight numbers
        highlightedCode = highlightedCode.replace(/\b\d+(\.\d+)?\b/g, '<span style="color: #d19a66;">$&</span>');
      }
      
      return `
        <div class="code-container streaming-code">
          <div class="code-header">
            <span class="code-language">${displayLang}</span>
            <span class="streaming-indicator">
              <i class="fas fa-circle-notch fa-spin"></i> Streaming...
            </span>
          </div>
          <div class="code-body">
            <div class="line-numbers">${lineNumbers}</div>
            <div class="code-content streaming">
              <pre><code>${highlightedCode}</code></pre>
            </div>
          </div>
        </div>
      `;
    }
    
    // Helper: create complete (non-streaming) code block with line numbers
    function createCompleteCodeBlock(code, displayLang) {
      const lines = code.split('\n');
      const lineNumbers = lines.map((_, i) => i + 1).join('\n');
      
      return `
        <div class="code-container">
          <div class="code-header">
            <span class="code-language">${displayLang}</span>
            <button class="code-copy-btn" onclick="copyCodeBlock(this)" title="Copy Code">
              <i class="fas fa-copy"></i>
            </button>
          </div>
          <div class="code-body">
            <div class="line-numbers">${lineNumbers}</div>
            <div class="code-content">
              <pre><code>${escapeHtml(code)}</code></pre>
            </div>
          </div>
        </div>
      `;
    }
    
    // Escape HTML for code blocks
    function escapeHtml(text) {
      const map = {
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#039;'
      };
      return text.replace(/[&<>"']/g, m => map[m]);
    }
    
    /* ==========================================================
       ISSUE 6 FIX: Improved markdown parser (non-code)
       - avoids extra newlines
       - robust lists (ordered/unordered)
       ========================================================== */
    function parseMarkdownWithoutCode(text) {
      if (!text) return '';
      
      let html = text;
      
      // Headers
      html = html.replace(/^### (.+)$/gm, '<h3>$1</h3>');
      html = html.replace(/^## (.+)$/gm, '<h2>$1</h2>');
      html = html.replace(/^# (.+)$/gm, '<h1>$1</h1>');
      
      // Bold
      html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
      
      // Italic
      html = html.replace(/\*([^*]+)\*/g, '<em>$1</em>');
      
      // Inline code
      html = html.replace(/`([^`]+)`/g, '<code class="inline-code">$1</code>');
      
      // Lists
      html = html.replace(/^- (.+)$/gm, '<li>$1</li>');
      html = html.replace(/(<li>.*<\/li>)/s, '<ul>$1</ul>');
      
      // Line breaks
      html = html.replace(/\n/g, '<br>');
      
      return html;
    }
    
    /* ============================================================
       CRITICAL: Global functions defined OUTSIDE document.ready
       so they persist after Shiny app restart
       ============================================================ */
    
    // Initialize CodeMirror
    window.initializeCodeMirrorInElement = function(elementId) {
      if (typeof CodeMirror === 'undefined') {
        console.error('CodeMirror not loaded');
        return;
      }
      const container = document.getElementById(elementId);
      if (!container) return;
      // Ensure each textarea has at least one unique attribute (DevTools autofill warning)
      container.querySelectorAll('textarea.codemirror-textarea').forEach((ta, idx) => {
        if (!ta.hasAttribute('id') && !ta.hasAttribute('name')) {
          const uid = (ta.dataset.codeId || (elementId + '_' + idx));
          ta.setAttribute('name', 'cm_' + uid);
        }
      });
    
      const textareas = container.querySelectorAll('.codemirror-textarea:not(.cm-initialized)');
    
      textareas.forEach(ta => {
        const lang = ta.dataset.lang || 'text';
        const langConfig = {
          r: { mode: 'r', fold: 'brace' },
          python: { mode: 'python', fold: 'indent' },
          javascript: { mode: 'javascript', fold: 'brace' },
          java: { mode: 'text/x-java', fold: 'brace' },
          csharp: { mode: 'text/x-csharp', fold: 'brace' },
          cpp: { mode: 'text/x-c++src', fold: 'brace' },
          c: { mode: 'text/x-csrc', fold: 'brace' },
          php: { mode: 'php', fold: ['brace', 'comment'] },
          bash: { mode: 'shell', fold: 'indent' },
          swift: { mode: 'swift', fold: 'brace' },
          typescript: { mode: 'text/typescript', fold: 'brace' },
          kotlin: { mode: 'text/x-kotlin', fold: 'brace' },
          scala: { mode: 'text/x-scala', fold: 'brace' },
          julia: { mode: 'julia', fold: 'indent' },
          ruby: { mode: 'ruby', fold: 'indent' },
          go: { mode: 'go', fold: 'brace' },
          powershell: { mode: 'powershell', fold: 'brace' },
          lisp: { mode: 'commonlisp', fold: 'indent' },
          vbnet: { mode: 'vb', fold: 'indent' },
          fortran: { mode: 'fortran', fold: 'indent' },
          matlab: { mode: 'octave', fold: 'indent' },
          sql: { mode: 'text/x-sql', fold: 'comment' },
          css: { mode: 'css', fold: 'brace' },
          html: { mode: 'htmlmixed', fold: 'xml' },
          text: { mode: 'text/plain', fold: 'indent' }
        };
    
        const config = langConfig[lang] || langConfig.text;
    
        try {
          const editor = CodeMirror.fromTextArea(ta, {
            mode: config.mode,
            theme: 'material-darker',
            lineNumbers: true,
            readOnly: true,
            lineWrapping: true,
            foldGutter: true,
            gutters: ["CodeMirror-linenumbers", "CodeMirror-foldgutter"],
            // harmless if addon missing; helpful if present
            autoRefresh: true
          });
          
        editor.on('gutterClick', function(cm, line, gutter, event) {
          if (gutter === 'CodeMirror-foldgutter') {
            // Store state on the editor instance, not globally
            if (!cm._isFolding) {
              cm._isFolding = true;
              setTimeout(() => { cm._isFolding = false; }, 200);
            }
          }
        });
          
          // Ensure correct sizing even if inserted hidden/animating
          editor.setSize('100%', 'auto');
          
          const robustRefresh = () => {
            try {
              editor.refresh();
              setTimeout(() => editor.refresh(), 50);
              setTimeout(() => editor.refresh(), 200);
              requestAnimationFrame(() => editor.refresh());
            } catch(e) {}
          };
          
          ta.classList.add('cm-initialized');
          robustRefresh();
          window.addEventListener('resize', robustRefresh, { passive: true });
        } catch (e) {
          console.error('Failed to initialize CodeMirror for textarea:', ta, e);
        }
      });
    };
    
    // Copy code from CodeMirror instance
    window.copyCodeFromCM = function(btn) {
      try {
        const cmInstance = btn.closest('.code-container').querySelector('.CodeMirror').CodeMirror;
        const code = cmInstance.getValue();
        navigator.clipboard.writeText(code).then(() => {
          window.showToast('Kod panoya kopyalandı.', 'success');
          const i = btn.querySelector('i');
          const originalClass = i.className;
          i.className = 'fas fa-check';
          setTimeout(() => { i.className = originalClass; }, 2000);
        });
      } catch (e) {
        console.error("Failed to copy from CodeMirror:", e);
        window.showToast('Kopyalama başarısız oldu.', 'error');
      }
    };
    
    // Copy AI message content
    window.copyAIMessageContent = function(msgId) {
      try {
        const msgElement = document.getElementById(msgId);
        if (!msgElement) {
          window.showToast('Mesaj bulunamadı.', 'error');
          return;
        }
        
        const isStreaming = msgElement.dataset.streaming === "true";
        let textContent = '';
        
        if (isStreaming) {
          // Get current streaming content
          const streamingContent = msgElement.querySelector('.streaming-content');
          if (streamingContent) {
            textContent = streamingContent.textContent || streamingContent.innerText;
          }
        } else {
          // Extract text from completed message
          const contentElements = msgElement.querySelectorAll('p, pre, code, h1, h2, h3, h4, h5, h6, li, td, th');
          contentElements.forEach(el => {
            if (!el.closest('button')) {
              textContent += el.textContent + '\n';
            }
          });
          
          if (!textContent.trim()) {
            textContent = msgElement.textContent || msgElement.innerText;
          }
        }
        
        navigator.clipboard.writeText(textContent.trim()).then(() => {
          window.showToast('İçerik panoya kopyalandı.', 'success');
          
          // Update button icon
          const btn = document.querySelector(`#copy_ai_${msgId}`);
          if (btn) {
            const icon = btn.querySelector('i');
            const originalClass = icon.className;
            icon.className = 'fas fa-check';
            setTimeout(() => { icon.className = originalClass; }, 2000);
          }
        }).catch(err => {
          window.showToast('Kopyalama başarısız oldu.', 'error');
        });
      } catch (e) {
        console.error('Copy failed:', e);
        window.showToast('Kopyalama başarısız oldu.', 'error');
      }
    };
    
    // Toast function - global (with container guard)
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
    /* ============================================================
       END global functions
       ============================================================ */
    
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
    
      // -------------------------------------------------
      // Message handlers
      // -------------------------------------------------
    
      // Like/dislike button color handlers
      Shiny.addCustomMessageHandler('updateFeedback', function(data) {
        const messageId = data.messageId;
        const action = data.action;
    
        if (action === 'like') {
          $(`#like_${messageId}`).addClass('active liked');
          $(`#dislike_${messageId}`).removeClass('active disliked');
        } else if (action === 'dislike') {
          $(`#dislike_${messageId}`).addClass('active disliked');
          $(`#like_${messageId}`).removeClass('active liked');
        } else if (action === 'remove_like') {
          $(`#like_${messageId}`).removeClass('active liked');
        } else if (action === 'remove_dislike') {
          $(`#dislike_${messageId}`).removeClass('active disliked');
        }
      });
    
      /* IMPROVED WIDESCREEN TOGGLE (client authoritative & retroactive) */
      Shiny.addCustomMessageHandler('toggleWidescreen', function(data) {
        applyWidescreen(!!data.enabled);
        // Persist through your existing settings blob if present
        try {
          const raw = localStorage.getItem('mergen_settings');
          const settings = raw ? JSON.parse(raw) : {};
          settings.enable_widescreen = !!data.enabled;
          localStorage.setItem('mergen_settings', JSON.stringify(settings));
        } catch (e) { /* ignore */ }
      });
    
      // FIX #11: Toggle all timestamps retroactively
      Shiny.addCustomMessageHandler('toggleAllTimestamps', function(data) {
        if (data.enabled) {
          $('.message-time').removeClass('hidden');
        } else {
          $('.message-time').addClass('hidden');
        }
      });
    
      // FIX #15: Font size update only for chat messages
      Shiny.addCustomMessageHandler('updateFontSize', function(data) {
        $('.message-content').removeClass('font-small font-medium font-large font-xlarge');
        $('.message-content').addClass('font-' + data.size);
      });
    
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
    
      // Cinematic Intro Animation
      function initIntro() {
        const canvas = document.getElementById('neural-canvas');
        if (!canvas) return;
    
        const ctx = canvas.getContext('2d');
        canvas.width = window.innerWidth;
        canvas.height = window.innerHeight;
    
        const particles = [];
        const particleCount = 300;
    
        class Particle {
          constructor() {
            this.x = Math.random() * canvas.width;
            this.y = Math.random() * canvas.height;
            this.vx = (Math.random() - 0.5) * 0.2;
            this.vy = (Math.random() - 0.5) * 0.2;
            this.radius = Math.random() * 1.5 + 0.5;
            const colors = ['rgba(255, 255, 255, 0.9)', 'rgba(200, 220, 255, 0.8)', 'rgba(150, 180, 255, 0.7)'];
            this.color = colors[Math.floor(Math.random() * colors.length)];
          }
    
          update() {
            this.x += this.vx;
            this.y += this.vy;
            if (this.x < 0 || this.x > canvas.width) this.vx *= -1;
            if (this.y < 0 || this.y > canvas.height) this.vy *= -1;
          }
    
          draw() {
            ctx.beginPath();
            ctx.arc(this.x, this.y, this.radius, 0, Math.PI * 2);
            ctx.fillStyle = this.color;
            ctx.fill();
          }
        }
    
        for (let i = 0; i < particleCount; i++) {
          particles.push(new Particle());
        }
    
        function animate() {
          ctx.clearRect(0, 0, canvas.width, canvas.height);
          particles.forEach(p => { p.update(); p.draw(); });
    
          for (let i = 0; i < particles.length; i++) {
            for (let j = i + 1; j < particles.length; j++) {
              const distance = Math.sqrt((particles[i].x - particles[j].x) ** 2 + (particles[i].y - particles[j].y) ** 2);
              if (distance < 150) {
                ctx.beginPath();
                ctx.moveTo(particles[i].x, particles[i].y);
                ctx.lineTo(particles[j].x, particles[j].y);
                ctx.strokeStyle = `rgba(150, 180, 255, ${(1 - distance / 150) * 0.5})`;
                ctx.lineWidth = 1.2;
                ctx.stroke();
              }
            }
          }
          requestAnimationFrame(animate);
        }
    
        animate();
    
        setTimeout(() => {
          document.body.classList.add('app-ready');
        
          $('#intro-container').addClass('fade-out');
          setTimeout(() => $('#intro-container').remove(), 1000);
        }, 500);
      }
    
      initIntro();
    
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
    
      // Enhanced Typing Animation Manager (with FIX #5: larger text)
      const TypingAnimationManager = {
        instance: null,
        timers: [],
    
        create: function(wrapper) {
          this.destroy();
    
          // FIX #5: Enhanced structure with larger text
          const animationHTML = `
            <div class="stage" id="typing-stage">
              <div class="animation-container">
                <div class="ring ring-large" aria-hidden="true">
                  <svg viewBox="0 0 100 100" preserveAspectRatio="xMidYMid meet">
                    <circle class="track" cx="50" cy="50" r="44"></circle>
                    <g class="rotator">
                      <circle class="tail" cx="50" cy="50" r="44"></circle>
                    </g>
                  </svg>
                  <div class="label label-large" role="status" aria-live="polite">
                    <span>D</span><span>ü</span><span>ş</span><span>ü</span><span>n</span><span>ü</span><span>y</span><span>o</span><span>r</span><span>u</span><span>m</span>
                  </div>
                </div>
              </div>
              <div class="name-wrap">
                <div class="name-particles" id="nameParticles" aria-hidden="true"></div>
                <div class="ai-name ai-name-large" id="filmRoll">
                  <div class="word" aria-label="MERGEN">
                    <span class="letter">M</span><span class="letter">E</span><span class="letter">R</span>
                    <span class="letter">G</span><span class="letter">E</span><span class="letter">N</span>
                  </div>
                  <div class="word" aria-label="Bilge">
                    <span class="letter">B</span><span class="letter">i</span><span class="letter">l</span>
                    <span class="letter">g</span><span class="letter">e</span>
                  </div>
                </div>
              </div>
            </div>
          `;
    
          wrapper.innerHTML = animationHTML;
          this.initAnimation();
        },
    
        initAnimation: function() {
          const prefersReduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
          if (prefersReduced) return;
    
          const root = document.getElementById('filmRoll');
          const layer = document.getElementById('nameParticles');
          if (!root || !layer) return;
    
          const letters = Array.from(root.querySelectorAll('.letter'));
          const PARTICLES = 6;
          const IN_STAGGER = 80;
          const IN_DUR = 420;
          const HOLD_TIME = 1200;
          const OUT_STAGGER = 90;
          const OUT_DUR = 420;
    
          const self = this;
    
          function rand(min, max) { return Math.random() * (max - min) + min; }
    
          function resetSpark(el) {
            const rect = layer.getBoundingClientRect();
            const w = rect.width || layer.clientWidth;
            const h = rect.height || layer.clientHeight;
    
            const leftPct = (rand(0, w) / w) * 100;
            const topPct = (rand(0, h) / h) * 100;
            const size = rand(2, 4).toFixed(1) + 'px';
            const scale = (0.7 + Math.random() * 0.7).toFixed(2);
            const dx = rand(-18, 18).toFixed(1) + 'px';
            const dy = rand(-14, 14).toFixed(1) + 'px';
            const dur = rand(2.2, 3.6).toFixed(2) + 's';
            const delay = rand(0, 1.0).toFixed(2) + 's';
    
            el.style.setProperty('--left', leftPct + '%');
            el.style.setProperty('--top', topPct + '%');
            el.style.setProperty('--size', size);
            el.style.setProperty('--dx', dx);
            el.style.setProperty('--dy', dy);
            el.style.setProperty('--scale', scale);
            el.style.animationDuration = dur + ', 8s';
            el.style.animationDelay = delay + ', 0s';
          }
    
          function createSpark() {
            const s = document.createElement('span');
            s.className = 'spark';
            resetSpark(s);
            s.addEventListener('animationiteration', (e) => {
              if (e.animationName === 'sparkDrift') resetSpark(s);
            });
            return s;
          }
    
          function seedParticles() {
            layer.innerHTML = '';
            for (let i = 0; i < PARTICLES; i++) {
              layer.appendChild(createSpark());
            }
          }
    
          function setT(fn, ms) {
            const t = setTimeout(fn, ms);
            self.timers.push(t);
            return t;
          }
    
          function resetInState() {
            const shift = '40px';
            letters.forEach(el => {
              el.style.transition = 'none';
              el.style.transform = `translateX(${shift})`;
              el.style.opacity = '0';
            });
            void root.offsetHeight;
            letters.forEach(el => {
              el.style.transition = 'transform 420ms cubic-bezier(.22,.61,.36,1), opacity 300ms ease';
            });
          }
    
          function animateIn() {
            resetInState();
            letters.forEach((el, i) => {
              setT(() => {
                el.style.transform = 'translateX(0)';
                el.style.opacity = '1';
              }, i * IN_STAGGER);
            });
            return (letters.length - 1) * IN_STAGGER + IN_DUR;
          }
    
          function animateOut() {
            letters.forEach((el, i) => {
              setT(() => {
                el.style.transform = 'translateX(-150%)';
                el.style.opacity = '0';
              }, i * OUT_STAGGER);
            });
            return (letters.length - 1) * OUT_STAGGER + OUT_DUR;
          }
    
          function cycle() {
            const inTime = animateIn();
            setT(() => {
              setT(() => {
                const outTime = animateOut();
                setT(cycle, outTime + 200);
              }, HOLD_TIME);
            }, inTime + 50);
          }
    
          seedParticles();
          cycle();
    
          this.instance = { root, layer, letters };
        },
    
        destroy: function() {
          this.timers.forEach(clearTimeout);
          this.timers = [];
          this.instance = null;
        }
      };
    
      // Keyboard shortcuts
      $(document).on('keydown', function(e) {
        if (e.ctrlKey && e.key === '/') {
          e.preventDefault();
          showKeyboardShortcuts();
        }
      });
    
      function showKeyboardShortcuts() {
        const shortcuts = `
          <div class="shortcuts-modal-content">
            <h3 style="color: var(--text-primary); margin-bottom: 20px;">Klavye Kısayolları</h3>
            <table class="shortcuts-table" style="width: 100%;">
              <tr><td style="padding: 8px;"><kbd>Enter</kbd></td><td>Mesaj gönder</td></tr>
              <tr><td style="padding: 8px;"><kbd>Shift + Enter</kbd></td><td>Yeni satır</td></tr>
              <tr><td style="padding: 8px;"><kbd>Ctrl + N</kbd></td><td>Yeni sohbet</td></tr>
              <tr><td style="padding: 8px;"><kbd>Ctrl + U</kbd></td><td>Dosya yükle</td></tr>
              <tr><td style="padding: 8px;"><kbd>Ctrl + /</kbd></td><td>Bu yardımı göster</td></tr>
              <tr><td style="padding: 8px;"><kbd>Esc</kbd></td><td>İptal/Temizle</td></tr>
              <tr><td style="padding: 8px;"><kbd>Page Up/Down</kbd></td><td>Sayfa kaydır</td></tr>
            </table>
          </div>
        `;
    
        const modalId = 'shortcuts_modal_' + Date.now();
        const modal = $(`
          <div id="${modalId}" class="shortcuts-modal" style="
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            background: var(--background-light);
            border: 1px solid var(--border-color);
            border-radius: 12px;
            padding: 24px;
            z-index: 10000;
            box-shadow: 0 8px 32px rgba(0,0,0,0.3);
            max-width: 500px;
            color: var(--text-secondary);
          ">
            ${shortcuts}
            <button onclick="$('#${modalId}').remove(); $('#${modalId}_backdrop').remove();" style="
              margin-top: 20px;
              padding: 8px 16px;
              background: var(--primary-color);
              color: white;
              border: none;
              border-radius: 6px;
              cursor: pointer;
              width: 100%;
            ">Kapat</button>
          </div>
        `);
    
        const backdrop = $(`<div id="${modalId}_backdrop" style="
          position: fixed;
          top: 0;
          left: 0;
          width: 100%;
          height: 100%;
          background: rgba(0, 0, 0, 0.5);
          z-index: 9999;
        " onclick="$('#${modalId}, #${modalId}_backdrop').remove()"></div>`);
    
        $('body').append(backdrop).append(modal);
      }
    
      // Utility functions
      window.adjustTextareaHeight = function(textarea) {
        if (!textarea) return;
        textarea.style.height = 'auto';
        textarea.style.height = Math.min(textarea.scrollHeight, 120) + 'px';
      }
    
      function scrollToBottom(smooth = true) {
        const container = $('.chat-container');
        if (container.length) {
          container[0].scrollTo({
            top: container[0].scrollHeight,
            behavior: smooth ? 'smooth' : 'auto'
          });
        }
      }
    
      function checkScrollPosition() {
        const container = $('.chat-container');
        if (container.length) {
          const scrollHeight = container[0].scrollHeight;
          const scrollTop = container.scrollTop();
          const clientHeight = container.height();
          isNearBottom = (scrollHeight - scrollTop - clientHeight) < 100;
          $('#scroll_to_bottom_container').toggleClass('show', !isNearBottom);
        }
      }
    
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
          
          // Update scroll position flag
          window.isNearBottom = true;
        };
    
        // Check if near bottom
        $(document).on('scroll', '.chat-content-wrapper', function() {
          const threshold = 100;
          const isNear = this.scrollHeight - this.scrollTop - this.clientHeight < threshold;
          window.isNearBottom = isNear;
        });
    
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
    
        // FIX #3: Character counter
      const charLimit = 20000;
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
    
        $(document).on('change', '#file_manager_module-bulk_upload', function () {
          const hasFiles = this.files && this.files.length > 0;
            const $grp = $(this).closest('.input-group');
            const $txt = $grp.find('.form-control');
            if (hasFiles) {
              $txt.val(Array.from(this.files).map(f => f.name).join(', '));
            } else {
              $txt.val('').attr('placeholder', 'Henüz dosya seçilmedi');
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
    
      // Shiny Custom Message Handlers
      Shiny.addCustomMessageHandler('showToast', function(data) { showToast(data.message, data.type, data.duration); });
      Shiny.addCustomMessageHandler('saveSettings', function(settings) { try { localStorage.setItem('mergen_settings', JSON.stringify(settings)); } catch (e) { console.error('Failed to save settings:', e); } });
      Shiny.addCustomMessageHandler('loadSettings', function(data) { try { const s = localStorage.getItem('mergen_settings'); if (s) { Shiny.setInputValue("settings_module-loaded_settings", JSON.parse(s), { priority: 'event' }); } } catch (e) { console.error('Failed to load settings:', e); } });
      Shiny.addCustomMessageHandler('clearSettings', function(data) { localStorage.removeItem('mergen_settings'); });
    
      Shiny.addCustomMessageHandler('toggleSendButton', function(message) { $('#send_stop_btn').prop('disabled', message.disable); });
    
      // Initialize streaming message (set data-streaming="true" for ISSUE 2)
        Shiny.addCustomMessageHandler('initStreamingMessage', function(data) {
          const messageDiv = document.getElementById(data.id);
          if (messageDiv) {
            messageDiv.innerHTML = '<div class="streaming-content" data-streaming="true"></div>';
            messageDiv.dataset.streaming = 'true';
            
            // Hide action buttons
            const wrapper = document.getElementById('message_wrapper_' + data.id);
            if (wrapper) {
              const actionButtons = wrapper.querySelectorAll('.streaming-hidden');
              actionButtons.forEach(btn => {
                btn.style.display = 'none';
              });
            }
          }
        });
    
      /* ==========================================================
         Enhanced streaming update handler (replaces older one)
         ========================================================== */
        Shiny.addCustomMessageHandler('streamingUpdate', function(data) {
          const messageDiv = document.getElementById(data.id);
          if (!messageDiv) return;
          
          let contentDiv = messageDiv.querySelector('.streaming-content');
          if (!contentDiv) {
            contentDiv = messageDiv;
          }
          
          if (data.isPartial) {
            // Parse and apply rich text formatting with immediate code display
            const formattedHtml = parseStreamingMarkdown(data.text);
            contentDiv.innerHTML = formattedHtml;
            
            // Always scroll during streaming
            window.smartScrollToBottom(false); // Use instant scroll for streaming
          }
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
            
      // Legacy streaming handler (for backward compatibility)
      Shiny.addCustomMessageHandler('streamUpdate', function(message) {
        try {
          const message_div = $('#' + message.id);
          if (message_div.length > 0) {
            let content_area = message_div.find('.message-content-body');
            if (content_area.length === 0) {
                message_div.html('<div class="message-content-body"></div>');
                content_area = message_div.find('.message-content-body');
            }
            content_area.text(content_area.text() + message.text);
          }
        } catch (e) {
          console.error('streamUpdate handler error', e);
        }
      });
    
      /* ==========================================================
         Enhanced finalize streaming message handler (ISSUE 2, 4, 6)
         (replaces older finalize handler)
         ========================================================== */
        Shiny.addCustomMessageHandler('finalizeStreamingMessage', function(data) {
          const messageDiv = document.getElementById(data.id);
          if (!messageDiv) return;
          
          // Update streaming status
          messageDiv.dataset.streaming = "false";
          
          // Remove streaming classes
          const wrapper = document.getElementById('message_wrapper_' + data.id);
          if (wrapper) {
            const aiMessage = wrapper.querySelector('.ai-message');
            if (aiMessage) {
              aiMessage.classList.remove('streaming-message');
            }
            
            // Show action buttons
            const actionButtons = wrapper.querySelectorAll('.streaming-hidden');
            actionButtons.forEach(btn => {
              btn.classList.remove('streaming-hidden');
              btn.style.display = 'inline-flex';
              btn.disabled = false;
            });
          }
          
          // Replace with final formatted HTML
          messageDiv.innerHTML = data.html;
          
            // Initialize CodeMirror (do not rely on server `hasCode`)
            if (window.initializeCodeMirrorInElement) {
              setTimeout(() => window.initializeCodeMirrorInElement('message_wrapper_' + data.id), 0);
            }
          
          // Final scroll adjustment
          if (window.isNearBottom) {
            window.smartScrollToBottom();
          }
        });
    
        Shiny.addCustomMessageHandler('streamEnd', function(message) {
            try {
                const message_div = $('#' + message.id);
                if (message_div.length > 0) {
                    if (window.initializeCodeMirror) {
                      window.initializeCodeMirror();
                    } else if (window.initializeCodeMirrorInElement) {
                      // IMPORTANT: initializer expects the wrapper id
                      window.initializeCodeMirrorInElement('message_wrapper_' + message.id);
                    }
                }
            } catch(e) {
                console.error("Error in streamEnd handler:", e);
            }
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
    
        Shiny.addCustomMessageHandler('forceSettingsUpdate', function(data) {
          // Force update the settings module's dropdown
          const dropdown = document.querySelector('#settings_module-model_selection');
          if (dropdown) {
            dropdown.value = data.model;
            // Trigger change event
            dropdown.dispatchEvent(new Event('change'));
          }
        });
    
        Shiny.addCustomMessageHandler('updateModelDropdown', function(data) {
          const modelDropdown = document.querySelector('#settings_module-model_selection');
          if (modelDropdown) {
            if (modelDropdown.selectize) {
              modelDropdown.selectize.setValue(data.model, true);
            } else {
              modelDropdown.value = data.model;
            }
          }
        });
    
        Shiny.addCustomMessageHandler('resetBulkUploadCaption', function () {
          const $input = $('#file_manager_module-bulk_upload');
          if (!$input.length) return;
          // Clear the file element
          $input.val('');
          // Reset the visible text box caption
          const $grp = $input.closest('.input-group');
          $grp.find('.form-control').val('').attr('placeholder', 'Henüz dosya seçilmedi');
        });
        
      window.copyMessageContent = function(btn, content) {
        navigator.clipboard.writeText(content).then(() => {
          showToast('İçerik panoya kopyalandı.', 'success');
          const i = $(btn).find('i');
          const c = i.attr('class');
          i.removeClass().addClass('fas fa-check');
          setTimeout(() => i.removeClass().addClass(c), 2000);
        }).catch(err => showToast('Kopyalama başarısız oldu.', 'error'));
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
    
        window.copyCodeBlock = function(button) {
          const codeContainer = button.closest('.code-container');
          const codeContent = codeContainer.querySelector('.code-content code');
          
          if (codeContent) {
            const text = codeContent.textContent;
            navigator.clipboard.writeText(text).then(() => {
              const icon = button.querySelector('i');
              icon.className = 'fas fa-check';
              showToast('Kod kopyalandı!', 'success');
              setTimeout(() => {
                icon.className = 'fas fa-copy';
              }, 2000);
            }).catch(err => {
              showToast('Kopyalama başarısız oldu.', 'error');
            });
          }
        };
    
    }); // end document.ready
    
    // Neural Network Animation for Welcome Screen
    const NeuralWelcomeAnimation = {
      canvas: null,
      ctx: null,
      particles: [],
      animationId: null,
      particleCount: 100,
    
      init: function() {
        const container = document.querySelector('.welcome-container');
        if (!container) return;
    
        let wrapper = container.querySelector('.neural-background');
        if (!wrapper) {
          wrapper = document.createElement('div');
          wrapper.className = 'neural-background';
          const cv = document.createElement('canvas');
          cv.className = 'neural-canvas-welcome';
          wrapper.appendChild(cv);
          container.insertBefore(wrapper, container.firstChild);
        }
    
        let canvas = wrapper.querySelector('canvas.neural-canvas-welcome');
        if (!canvas) {
          canvas = document.createElement('canvas');
          canvas.className = 'neural-canvas-welcome';
          wrapper.appendChild(canvas);
        }
    
        this.canvas = canvas;
        this.ctx = canvas.getContext('2d');
    
        // Use CSS --primary-color for the canvas color
        const cssPrimary = getComputedStyle(document.documentElement).getPropertyValue('--primary-color').trim();
        function hexToRgb(hex){ let c=hex.replace('#',''); if (c.length===3) c=c.split('').map(x=>x+x).join(''); const n=parseInt(c,16); return {r:(n>>16)&255,g:(n>>8)&255,b:n&255}; }
        this.primaryRGB = hexToRgb(cssPrimary || '#ff6b35');
    
        this.resize();
        window.addEventListener('resize', () => this.resize(), { passive: true });
    
        this.createParticles();
        this.animate();
      },
      
      resize: function() {
        if (!this.canvas) return;
        const container = this.canvas.parentElement;
        this.canvas.width = container.clientWidth;
        this.canvas.height = container.clientHeight;
      },
      
      createParticles: function() {
        this.particles = [];
        for (let i = 0; i < this.particleCount; i++) {
          this.particles.push({
            x: Math.random() * this.canvas.width,
            y: Math.random() * this.canvas.height,
            vx: (Math.random() - 0.5) * 0.2,
            vy: (Math.random() - 0.5) * 0.2,
            radius: Math.random() * 1.5 + 0.5,
            opacity: Math.random() * 0.5 + 0.3
          });
        }
      },
      
      animate: function() {
        if (!this.ctx || !this.canvas) return;
        
        // Clear canvas
        this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
        
        // Update and draw particles
        this.particles.forEach((p, i) => {
          // Update position
          p.x += p.vx;
          p.y += p.vy;
          
          // Bounce off walls
          if (p.x < 0 || p.x > this.canvas.width) p.vx *= -1;
          if (p.y < 0 || p.y > this.canvas.height) p.vy *= -1;
          
          // Draw particle
          this.ctx.beginPath();
          this.ctx.arc(p.x, p.y, p.radius, 0, Math.PI * 2);
          this.ctx.fillStyle = `rgba(${this.primaryRGB.r}, ${this.primaryRGB.g}, ${this.primaryRGB.b}, ${p.opacity})`;
          this.ctx.fill();
          
          // Draw connections to nearby particles
          for (let j = i + 1; j < this.particles.length; j++) {
            const p2 = this.particles[j];
            const distance = Math.sqrt((p.x - p2.x) ** 2 + (p.y - p2.y) ** 2);
            
            if (distance < 100) {
              this.ctx.beginPath();
              this.ctx.moveTo(p.x, p.y);
              this.ctx.lineTo(p2.x, p2.y);
              const opacity = (1 - distance / 100) * 0.3;
              this.ctx.strokeStyle = `rgba(${this.primaryRGB.r}, ${this.primaryRGB.g}, ${this.primaryRGB.b}, ${opacity})`;
              this.ctx.lineWidth = 0.5;
              this.ctx.stroke();
            }
          }
        });
        
        // Continue animation
        this.animationId = requestAnimationFrame(() => this.animate());
      },
      
      destroy: function() {
        if (this.animationId) {
          cancelAnimationFrame(this.animationId);
          this.animationId = null;
        }
        
        const bg = document.querySelector('.neural-background');
        if (bg) {
          bg.classList.add('fade-out');
          setTimeout(() => bg.remove(), 500);
        }
        
        this.canvas = null;
        this.ctx = null;
        this.particles = [];
      }
    };
    
    // Initialize neural animation when welcome screen appears
    Shiny.addCustomMessageHandler('showNeuralAnimation', function(message) {
      setTimeout(() => {
        NeuralWelcomeAnimation.init();
      }, 100);
    });
    
    // Watch for chat messages and destroy animation when chat starts
    document.addEventListener('DOMContentLoaded', function() {
      const observer = new MutationObserver(function(mutations) {
        const hasMessages = document.querySelector('.message-bubble');
        if (hasMessages) {
          NeuralWelcomeAnimation.destroy();
        }
      });
      
      const chatContainer = document.querySelector('#chat_content_container');
      if (chatContainer) {
        observer.observe(chatContainer, {
          childList: true,
          subtree: true
        });
      }
    });
    
    // Update health timestamp
    Shiny.addCustomMessageHandler('updateHealthTimestamp', function(data) {
      const elem = document.getElementById('last_update_time');
      if (elem) {
        elem.textContent = 'Son Güncelleme: ' + data.time;
      }
    });
    
    // Character button management
    Shiny.addCustomMessageHandler('updateCharacterButtons', function(data) {
      // Remove active class from all buttons
      document.querySelectorAll('.character-btn').forEach(btn => {
        btn.classList.remove('active');
        btn.style.background = 'transparent';
      });
      
      // Add active class and color to selected button
      const activeBtn = document.querySelector(`[data-character="${data.character}"]`);
      if (activeBtn) {
        activeBtn.classList.add('active');
        activeBtn.style.background = data.accent_active;
        
        // Add hover effects
        activeBtn.addEventListener('mouseenter', function() {
          if (this.classList.contains('active')) {
            this.style.background = data.accent;
          }
        });
        
        activeBtn.addEventListener('mouseleave', function() {
          if (this.classList.contains('active')) {
            this.style.background = data.accent_active;
          }
        });
      }
    });
    
    // Character info update handler
    Shiny.addCustomMessageHandler('updateCharacterInfo', function(data) {
      const infoArea = document.querySelector('[id$="character_info_area"]');
      if (infoArea) {
        // Force clear and update
        infoArea.innerHTML = data.html;
      }
    });

// Smooth character image cross-fade with preload + cleanup guards
Shiny.addCustomMessageHandler('transitionCharacterImage', function(data) {
  const container = document.getElementById(data.containerId);
  if (!container) return;

  if (!container.__characterImageState) {
    container.__characterImageState = { pendingImage: null };
  }

  const state = container.__characterImageState;

  if (state.pendingImage) {
    state.pendingImage.onload = null;
    state.pendingImage.onerror = null;
    state.pendingImage = null;
  }

  const existingImages = Array.from(container.querySelectorAll('.character-image'));
  const incoming = document.createElement('img');
  incoming.className = 'character-image';
  incoming.alt = data.displayName || '';
  if ('decoding' in incoming) {
    incoming.decoding = 'async';
  }
  incoming.style.willChange = 'opacity, filter';
  incoming.style.height = '100%';
  incoming.style.width = 'auto';
  incoming.style.maxHeight = '100%';

  const applyVisibleState = () => {
    if (state.pendingImage !== incoming) {
      return;
    }

    state.pendingImage = null;

    if (getComputedStyle(container).position === 'static') {
      container.style.position = 'relative';
    }

    container.appendChild(incoming);

    // Force layout before toggling visibility
    void incoming.offsetWidth;
    requestAnimationFrame(() => {
      incoming.classList.add('is-visible');
    });

    incoming.addEventListener(
      'transitionend',
      (event) => {
        if (event.propertyName === 'opacity') {
          incoming.classList.remove('is-entering');
        }
      },
      { once: true }
    );

    existingImages.forEach((img) => {
      img.classList.remove('is-visible');
      img.classList.add('is-exiting');
      img.addEventListener(
        'transitionend',
        (event) => {
          if (event.propertyName === 'opacity' && img.parentNode === container) {
            img.remove();
          }
        },
        { once: true }
      );
    });
  };

  incoming.addEventListener('load', applyVisibleState, { once: true });

  incoming.addEventListener('error', function() {
    if (state.pendingImage === incoming) {
      state.pendingImage = null;
    }
    console.error('Karakter görseli yüklenemedi:', data.imageUrl);
    existingImages.forEach((img) => {
      img.classList.add('is-visible');
      img.classList.remove('is-exiting');
    });
  }, { once: true });

  state.pendingImage = incoming;

  const url = (typeof data.imageUrl === 'string' && data.imageUrl.length)
    ? data.imageUrl.replace(/^\/+/, '')
    : '';

  if (!url) {
    state.pendingImage = null;
    return;
  }

  incoming.src = url;
});

// Character info update with word-by-word typing
Shiny.addCustomMessageHandler('updateCharacterInfoTyping', function(data) {
  const infoArea = document.getElementById(data.infoAreaId);
  if (!infoArea) return;
  
  // Create title element
  const titleDiv = document.createElement('div');
  titleDiv.className = 'character-title';
  titleDiv.style.color = data.accentColor;
  titleDiv.style.fontSize = '22px';
  titleDiv.style.fontWeight = '700';
  titleDiv.style.marginBottom = '16px';
  titleDiv.textContent = data.title;
  titleDiv.style.opacity = '0';
  
  // Create lore element with unique ID
  const loreDiv = document.createElement('div');
  const loreId = 'character_lore_' + Date.now();
  loreDiv.id = loreId;
  loreDiv.className = 'character-lore';
  loreDiv.style.fontSize = '17px';
  loreDiv.style.lineHeight = '1.7';
  loreDiv.style.color = 'var(--text-secondary)';
  loreDiv.style.opacity = '0';
  
  // Clear and add elements
  infoArea.innerHTML = '';
  infoArea.appendChild(titleDiv);
  infoArea.appendChild(loreDiv);
  
  // Fade in title
  setTimeout(() => {
    titleDiv.style.transition = 'opacity 0.4s ease';
    titleDiv.style.opacity = '1';
  }, 100);
  
  // Start typing effect for lore after title appears
  setTimeout(() => {
    loreDiv.style.opacity = '1';
    if (window.typeCharacterLore) {
      window.typeCharacterLore(data.lore, loreId, 60);
    } else {
      loreDiv.textContent = data.lore;
    }
  }, 500);
});

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