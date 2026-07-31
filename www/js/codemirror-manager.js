// www/js/codemirror-manager.js
(function() {
  'use strict';

  // Initialize CodeMirror
  window.initializeCodeMirrorInElement = function(elementId) {
    if (typeof CodeMirror === 'undefined') {
      console.error('CodeMirror not loaded');
      return;
    }
    const container = document.getElementById(elementId);
    if (!container) return;
    
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
          autoRefresh: true,
          // Yukseklik 'auto' oldugundan viewport sanallastirmasi uzun kodu
          // kirpiyordu; Infinity belgenin tamamini render eder.
          viewportMargin: Infinity
        });
        
        editor.on('gutterClick', function(cm, line, gutter, event) {
          if (gutter === 'CodeMirror-foldgutter') {
            if (!cm._isFolding) {
              cm._isFolding = true;
              setTimeout(() => { cm._isFolding = false; }, 200);
            }
          }
        });
        
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

  // Mesaj içeriğini kopyala (CodeMirror kod blokları dahil tam metin)
  window.copyAIMessageContent = function(msgId) {
    try {
      var msgElement = document.getElementById(msgId);
      if (!msgElement) {
        window.showToast('Mesaj bulunamadı.', 'error');
        return;
      }

      var isStreaming = msgElement.dataset.streaming === "true";
      var textParts = [];

      if (isStreaming) {
        var streamingContent = msgElement.querySelector('.streaming-content');
        if (streamingContent) {
          textParts.push(streamingContent.textContent || streamingContent.innerText || '');
        }
      } else {
        // Mesaj içeriğindeki tüm üst seviye elemanları sırayla dolaş
        var children = msgElement.children;
        for (var i = 0; i < children.length; i++) {
          var child = children[i];

          // Takip sorusu kutusunu atla
          if (child.classList.contains('followup-suggestions-box')) continue;
          // TTS ses oynatıcısını atla
          if (child.classList.contains('tts-audio-container')) continue;

          // Kod bloğu mu kontrol et (CodeMirror içerir)
          if (child.classList.contains('code-container')) {
            var cmEl = child.querySelector('.CodeMirror');
            if (cmEl && cmEl.CodeMirror) {
              // CodeMirror örneğinden tam kodu al
              textParts.push(cmEl.CodeMirror.getValue());
            } else {
              // Yedek: textarea'dan al
              var ta = child.querySelector('.codemirror-textarea');
              if (ta) {
                textParts.push(ta.value || ta.textContent || '');
              }
            }
          } else {
            // Normal metin içeriği
            var text = child.innerText || child.textContent || '';
            if (text.trim()) {
              textParts.push(text);
            }
          }
        }

        // Hiçbir şey bulunamadıysa yedek olarak tüm innerText'i al
        if (textParts.length === 0) {
          textParts.push(msgElement.innerText || msgElement.textContent || '');
        }
      }

      var fullText = textParts.join('\n\n').trim();
      navigator.clipboard.writeText(fullText).then(function() {
        window.showToast('İçerik panoya kopyalandı.', 'success');
        var btn = document.querySelector('#copy_ai_' + msgId) || document.querySelector('#copy_user_' + msgId);
        if (btn) {
          var icon = btn.querySelector('i');
          var originalClass = icon.className;
          icon.className = 'fas fa-check';
          setTimeout(function() { icon.className = originalClass; }, 2000);
        }
      }).catch(function(err) {
        window.showToast('Kopyalama başarısız oldu.', 'error');
      });
    } catch (e) {
      console.error('Kopyalama hatası:', e);
      window.showToast('Kopyalama başarısız oldu.', 'error');
    }
  };

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
})();