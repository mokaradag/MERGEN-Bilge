// www/js/codemirror-manager.js
(function() {
  'use strict';

  // Desteklenen diller: her anahtarın modu www/codemirror altında gerçek
  // olarak yüklenir (R/config_ui_assets.R codemirror_modes). fold, katlama
  // oluğunun önce deneyeceği yardımcılardır; ardından modun kendi (auto)
  // katlaması denenir.
  const LANG_CONFIG = {
    r: { mode: 'r', fold: 'brace' },
    python: { mode: 'python', fold: 'indent' },
    javascript: { mode: 'javascript', fold: 'brace' },
    typescript: { mode: 'text/typescript', fold: 'brace' },
    json: { mode: 'application/json', fold: 'brace' },
    java: { mode: 'text/x-java', fold: 'brace' },
    csharp: { mode: 'text/x-csharp', fold: 'brace' },
    cpp: { mode: 'text/x-c++src', fold: 'brace' },
    c: { mode: 'text/x-csrc', fold: 'brace' },
    kotlin: { mode: 'text/x-kotlin', fold: 'brace' },
    scala: { mode: 'text/x-scala', fold: 'brace' },
    php: { mode: 'php', fold: ['brace', 'comment'] },
    bash: { mode: 'shell', fold: 'indent' },
    powershell: { mode: 'powershell', fold: 'brace' },
    swift: { mode: 'swift', fold: 'brace' },
    go: { mode: 'go', fold: 'brace' },
    rust: { mode: 'rust', fold: 'brace' },
    ruby: { mode: 'ruby', fold: 'indent' },
    perl: { mode: 'perl', fold: 'brace' },
    lua: { mode: 'lua', fold: 'indent' },
    julia: { mode: 'julia', fold: 'indent' },
    lisp: { mode: 'commonlisp', fold: 'indent' },
    vbnet: { mode: 'vb', fold: 'indent' },
    fortran: { mode: 'fortran', fold: 'indent' },
    matlab: { mode: 'octave', fold: 'indent' },
    sql: { mode: 'text/x-sql', fold: 'comment' },
    tsql: { mode: 'text/x-mssql', fold: 'comment' },
    mysql: { mode: 'text/x-mysql', fold: 'comment' },
    pgsql: { mode: 'text/x-pgsql', fold: 'comment' },
    plsql: { mode: 'text/x-plsql', fold: 'comment' },
    sqlite: { mode: 'text/x-sqlite', fold: 'comment' },
    css: { mode: 'css', fold: 'brace' },
    html: { mode: 'htmlmixed', fold: 'xml' },
    xml: { mode: 'xml', fold: 'xml' },
    yaml: { mode: 'yaml', fold: 'indent' },
    toml: { mode: 'toml', fold: 'indent' },
    properties: { mode: 'properties', fold: 'indent' },
    markdown: { mode: 'markdown', fold: 'markdown' },
    dockerfile: { mode: 'dockerfile', fold: 'indent' },
    diff: { mode: 'diff', fold: 'indent' },
    text: { mode: 'text/plain', fold: 'indent' }
  };

  // Kod çiti etiketlerinde sık görülen kısaltmalar -> kanonik anahtar.
  const LANG_ALIASES = {
    rscript: 'r',
    py: 'python', py3: 'python', python3: 'python',
    js: 'javascript', jsx: 'javascript', mjs: 'javascript', cjs: 'javascript', node: 'javascript',
    ts: 'typescript', tsx: 'typescript',
    jsonc: 'json', json5: 'json',
    cs: 'csharp', 'c#': 'csharp',
    'c++': 'cpp', cc: 'cpp', cxx: 'cpp', hpp: 'cpp', h: 'c',
    kt: 'kotlin', kts: 'kotlin',
    sh: 'bash', shell: 'bash', zsh: 'bash', ksh: 'bash', console: 'bash',
    ps1: 'powershell', pwsh: 'powershell',
    golang: 'go', rs: 'rust', rb: 'ruby', pl: 'perl', pm: 'perl', jl: 'julia',
    commonlisp: 'lisp', elisp: 'lisp',
    vb: 'vbnet', vba: 'vbnet', 'vb.net': 'vbnet',
    octave: 'matlab', f90: 'fortran', f95: 'fortran',
    mssql: 'tsql', sqlserver: 'tsql', 't-sql': 'tsql', mariadb: 'mysql',
    postgres: 'pgsql', postgresql: 'pgsql', psql: 'pgsql', oracle: 'plsql',
    htm: 'html', xhtml: 'html', svg: 'xml', xsl: 'xml', xaml: 'xml',
    yml: 'yaml', ini: 'properties', cfg: 'properties', conf: 'properties',
    md: 'markdown', docker: 'dockerfile', containerfile: 'dockerfile',
    patch: 'diff',
    txt: 'text', plaintext: 'text', plain: 'text', output: 'text', log: 'text'
  };

  const warnedLanguages = Object.create(null);

  function isModeRegistered(spec) {
    if (spec === 'text/plain') return true;
    const resolved = CodeMirror.resolveMode(spec);
    return !!(resolved && resolved.name && resolved.name !== 'null' &&
              CodeMirror.modes[resolved.name]);
  }

  // Dil etiketini gerçekten yüklenmiş bir moda çözer. Desteklenmeyen dil
  // düz metin olarak gösterilir; desteklenen dilin modu eksikse bu bir
  // dağıtım hatasıdır ve bir kez uyarılır.
  function resolveLanguage(rawLang) {
    const lang = String(rawLang || 'text').trim().toLowerCase();
    const key = LANG_CONFIG[lang] ? lang : (LANG_ALIASES[lang] || null);

    if (key) {
      const config = LANG_CONFIG[key];
      if (isModeRegistered(config.mode)) return { key: key, mode: config.mode, fold: config.fold };
      if (!warnedLanguages[key]) {
        warnedLanguages[key] = true;
        console.warn('[MERGEN] CodeMirror modu yüklenmemiş: ' + key + ' (' + config.mode + ')');
      }
      return { key: 'text', mode: 'text/plain', fold: LANG_CONFIG.text.fold };
    }

    // Upstream mod meta verisi (mode/meta) başka takma adları da çözer.
    const info = (CodeMirror.findModeByName && CodeMirror.findModeByName(lang)) ||
                 (CodeMirror.findModeByExtension && CodeMirror.findModeByExtension(lang));
    if (info && info.mode && CodeMirror.modes[info.mode]) {
      return { key: lang, mode: info.mime || info.mode, fold: 'indent' };
    }
    return { key: 'text', mode: 'text/plain', fold: LANG_CONFIG.text.fold };
  }

  function buildRangeFinder(fold) {
    const names = Array.isArray(fold) ? fold : [fold];
    const finders = names
      .map(function(name) { return CodeMirror.fold && CodeMirror.fold[name]; })
      .filter(function(finder) { return typeof finder === 'function'; });
    if (CodeMirror.fold && CodeMirror.fold.auto) finders.push(CodeMirror.fold.auto);
    if (!finders.length) return undefined;
    return finders.length === 1 ? finders[0] : CodeMirror.fold.combine.apply(null, finders);
  }

  // Editör genişliği değişince (yerleşimin oturması, gizli kabın açılması,
  // kenar çubuğu/geniş ekran geçişi) satır sarması yeniden ölçülür. Tam
  // yenileme uzun belgede tüm satırları yeniden çizdiğinden (viewportMargin:
  // Infinity) yalnızca genişlik GERÇEKTEN değiştiğinde yapılır.
  const measuredWidths = new WeakMap();
  const widthObserver = typeof ResizeObserver === 'function'
    ? new ResizeObserver(function(entries) {
        entries.forEach(function(entry) {
          const wrapper = entry.target;
          if (!wrapper.isConnected) { widthObserver.unobserve(wrapper); return; }
          const width = wrapper.clientWidth;
          if (!width || measuredWidths.get(wrapper) === width) return;
          measuredWidths.set(wrapper, width);
          if (wrapper.CodeMirror) wrapper.CodeMirror.refresh();
        });
      })
    : null;

  function watchEditorLayout(editor) {
    const wrapper = editor.getWrapperElement();
    measuredWidths.set(wrapper, wrapper.clientWidth);
    if (widthObserver) widthObserver.observe(wrapper);
    // Yazı tipi sonradan yüklenirse karakter ölçüleri değişir.
    if (document.fonts && document.fonts.status !== 'loaded' && document.fonts.ready) {
      document.fonts.ready.then(function() { editor.refresh(); });
    }
  }

  window.mergenCodeMirrorResolveLanguage = resolveLanguage;
  window.mergenCodeMirrorLanguages = function() { return Object.keys(LANG_CONFIG); };

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
      const config = resolveLanguage(ta.dataset.lang);
      const rangeFinder = buildRangeFinder(config.fold);

      const options = {
        mode: config.mode,
        theme: 'material-darker',
        lineNumbers: true,
        readOnly: true,
        lineWrapping: true,
        // Katlama oluğu tıklamayı kendisi işler (addon/fold/foldgutter).
        foldGutter: true,
        gutters: ["CodeMirror-linenumbers", "CodeMirror-foldgutter"],
        // Yukseklik 'auto' oldugundan viewport sanallastirmasi uzun kodu
        // kirpiyordu; Infinity belgenin tamamini render eder.
        viewportMargin: Infinity
      };
      if (rangeFinder) {
        options.foldGutter = { rangeFinder: rangeFinder };
        options.foldOptions = { rangeFinder: rangeFinder };
      }

      try {
        const editor = CodeMirror.fromTextArea(ta, options);
        const wrapper = editor.getWrapperElement();
        wrapper.setAttribute('data-lang', config.key);
        wrapper.classList.add('cm-lang-' + config.key);

        editor.setSize('100%', 'auto');

        ta.classList.add('cm-initialized');
        // Pencere yeniden boyutlanınca CodeMirror canlı editörleri kendisi
        // yeniden ölçer; diğer genişlik değişimlerini watchEditorLayout izler.
        watchEditorLayout(editor);
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