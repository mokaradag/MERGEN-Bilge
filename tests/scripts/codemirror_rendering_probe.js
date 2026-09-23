// tests/scripts/codemirror_rendering_probe.js
// Gerçek CodeMirror kod bloğu davranışını tarayıcıda doğrular. Sayfa
// codemirror_rendering_check.R tarafından manifestteki CSS/JS ile üretilir;
// window.__CM_FIXTURES R'nin create_code_block_html() çıktısıdır.
(function () {
  'use strict';

  var failures = [];
  var logLines = [];
  var consoleErrors = [];
  var statusEl = document.getElementById('cm-check-status');
  var logEl = document.getElementById('cm-check-log');

  var origError = console.error;
  console.error = function () {
    consoleErrors.push(Array.prototype.slice.call(arguments).map(String).join(' '));
    return origError.apply(console, arguments);
  };
  window.addEventListener('error', function (e) { consoleErrors.push('window.error: ' + (e.message || e)); });
  // Kopyalama düğmesi bildirim gösterir; bildirim katmanı bu sayfada yoktur.
  window.showToast = function () {};

  function log(msg) { logLines.push(msg); }
  function check(cond, msg) { if (cond) { log('PASS ' + msg); } else { failures.push(msg); log('FAIL ' + msg); } }
  function wait(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }

  function rgb(str) {
    var m = String(str || '').match(/rgba?\(([^)]+)\)/);
    if (!m) return null;
    var p = m[1].split(',').map(function (x) { return parseFloat(x); });
    return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 };
  }
  function luminance(c) {
    function ch(v) { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }
  function contrast(a, b) {
    var la = luminance(a), lb = luminance(b);
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
  }
  function sameColor(a, b) { return a && b && a.r === b.r && a.g === b.g && a.b === b.b; }

  function mount(name) {
    var fx = window.__CM_FIXTURES[name];
    var wrap = document.createElement('div');
    wrap.id = 'message_wrapper_cmcheck_' + name;
    wrap.innerHTML = '<div class="message-bubble"><div class="ai-message"><div class="message-content">' +
      fx.html + '</div></div></div>';
    document.getElementById('cm-check-host').appendChild(wrap);
    window.initializeCodeMirrorInElement(wrap.id);
    var el = wrap.querySelector('.CodeMirror');
    return { wrap: wrap, el: el, cm: el && el.CodeMirror, fx: fx };
  }

  function tokenClasses(el) {
    var out = {};
    Array.prototype.forEach.call(el.querySelectorAll('.CodeMirror-code span[class*="cm-"]'), function (s) {
      s.className.split(/\s+/).forEach(function (c) { if (/^cm-/.test(c)) out[c] = out[c] || s; });
    });
    return out;
  }

  var REQUIRED_TOKENS = {
    python: ['cm-keyword', 'cm-def', 'cm-variable', 'cm-number', 'cm-string', 'cm-comment', 'cm-operator', 'cm-builtin'],
    r: ['cm-keyword', 'cm-variable', 'cm-number', 'cm-string', 'cm-comment', 'cm-atom'],
    javascript: ['cm-keyword', 'cm-def', 'cm-variable-2', 'cm-number', 'cm-string', 'cm-comment', 'cm-operator'],
    sql: ['cm-keyword', 'cm-string', 'cm-number', 'cm-comment']
  };

  function checkTheme(theme, blocks) {
    document.documentElement.setAttribute('data-theme', theme);
    Object.keys(REQUIRED_TOKENS).forEach(function (name) {
      var b = blocks[name];
      var bg = rgb(getComputedStyle(b.el).backgroundColor);
      var text = rgb(getComputedStyle(b.el.querySelector('.CodeMirror-line')).color);
      var lineBg = rgb(getComputedStyle(b.el.querySelector('.CodeMirror-line')).backgroundColor);
      var gutter = rgb(getComputedStyle(b.el.querySelector('.CodeMirror-gutters')).backgroundColor);
      var lineNo = rgb(getComputedStyle(b.el.querySelector('.CodeMirror-linenumber')).color);
      var dark = theme === 'dark';
      check(bg && (dark ? luminance(bg) < 0.05 : luminance(bg) > 0.85), theme + '/' + name + ': editör zemini tema ile uyumlu (' + getComputedStyle(b.el).backgroundColor + ')');
      check(lineBg && lineBg.a === 0, theme + '/' + name + ': satırlar kendi zeminini çizmez');
      check(gutter && (dark ? luminance(gutter) < 0.1 : luminance(gutter) > 0.75), theme + '/' + name + ': oluk zemini tema ile uyumlu');
      check(contrast(text, bg) >= 4.5, theme + '/' + name + ': metin kontrastı >= 4.5');
      check(contrast(lineNo, gutter) >= 3, theme + '/' + name + ': satır numarası kontrastı >= 3');
      var header = rgb(getComputedStyle(b.wrap.querySelector('.code-header')).backgroundColor);
      Array.prototype.forEach.call(b.wrap.querySelectorAll('.code-header-actions button i'), function (icon) {
        check(contrast(rgb(getComputedStyle(icon).color), header) >= 3,
              theme + '/' + name + ': başlık simgesi (' + icon.parentNode.className + ') kontrastı >= 3');
      });
      var tokens = tokenClasses(b.el);
      REQUIRED_TOKENS[name].forEach(function (cls) {
        var span = tokens[cls];
        check(!!span, theme + '/' + name + ': ' + cls + ' belirteci üretildi');
        if (span) {
          var c = rgb(getComputedStyle(span).color);
          check(!sameColor(c, text) && contrast(c, bg) >= 3, theme + '/' + name + ': ' + cls + ' ayırt edilir renkte');
        }
      });
    });
  }

  async function run() {
    try {
      check(typeof window.CodeMirror === 'function' && /^5\./.test(CodeMirror.version) &&
            !/compat/.test(CodeMirror.version), 'gerçek CodeMirror 5 yüklü (' + (window.CodeMirror && CodeMirror.version) + ')');
      check(Object.keys(CodeMirror.modes).length > 20, 'upstream modlar kayıtlı (' + Object.keys(CodeMirror.modes).length + ')');

      var langs = window.mergenCodeMirrorLanguages();
      var unresolved = langs.filter(function (k) { return k !== 'text' && window.mergenCodeMirrorResolveLanguage(k).key === 'text'; });
      check(unresolved.length === 0, 'ilan edilen her dil yüklü bir moda çözülür' + (unresolved.length ? ': ' + unresolved.join(',') : ''));
      check(window.mergenCodeMirrorResolveLanguage('py').key === 'python', 'py takma adı python moduna çözülür');
      check(window.mergenCodeMirrorResolveLanguage('bilinmeyen-dil').mode === 'text/plain', 'bilinmeyen dil düz metin kalır');

      var blocks = {};
      Object.keys(window.__CM_FIXTURES).forEach(function (name) { blocks[name] = mount(name); });
      await wait(200);

      Object.keys(blocks).forEach(function (name) {
        var b = blocks[name];
        check(!!b.cm, name + ': CodeMirror örneği oluştu');
        check(b.cm.getValue() === b.fx.code, name + ': editör değeri kaynak kodla aynı');
      });

      checkTheme('dark', blocks);
      // Başlık düğmeleri renk geçişi (transition) kullanır; ölçüm geçiş bitince yapılır.
      document.documentElement.setAttribute('data-theme', 'light');
      await wait(600);
      checkTheme('light', blocks);
      document.documentElement.setAttribute('data-theme', 'dark');

      // Uzun kod: tüm satırlar DOM'da (viewportMargin: Infinity), son satır kaydırılarak görünür.
      var long = blocks.long;
      var lines = long.el.querySelectorAll('.CodeMirror-code > div');
      check(long.cm.lineCount() === long.fx.code.split('\n').length, 'uzun kod: satır sayısı tam');
      check(lines.length === long.cm.lineCount(), 'uzun kod: tüm satırlar çizildi (' + lines.length + ')');
      var scroller = long.el.querySelector('.CodeMirror-scroll');
      scroller.scrollTop = scroller.scrollHeight;
      await wait(50);
      // Yazı tipi yüklenince yapılan tam yenileme satır düğümlerini değiştirebilir.
      lines = long.el.querySelectorAll('.CodeMirror-code > div');
      var last = lines[lines.length - 1].getBoundingClientRect();
      var box = scroller.getBoundingClientRect();
      check(scroller.scrollHeight > scroller.clientHeight, 'uzun kod: editör içinde kaydırılabilir');
      check(last.bottom <= box.bottom + 2 && last.top >= box.top - 2, 'uzun kod: son satır görünür hale gelir (' +
            [Math.round(last.top), Math.round(last.bottom), Math.round(box.top), Math.round(box.bottom),
             scroller.scrollTop, scroller.scrollHeight, scroller.clientHeight].join(',') + ')');

      // Katlama: gerçek oluk tıklaması (foldgutter) aralığı gizler, değer değişmez.
      var py = blocks.python;
      var marker = py.el.querySelector('.CodeMirror-foldgutter-open');
      check(!!marker, 'python: katlama işareti çizildi');
      var before = py.el.querySelectorAll('.CodeMirror-code > div').length;
      if (marker) {
        var r = marker.getBoundingClientRect();
        marker.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, button: 0,
          clientX: r.left + r.width / 2, clientY: r.top + r.height / 2 }));
        await wait(50);
      }
      var folded = py.cm.getAllMarks().filter(function (m) { return m.__isFold; }).length;
      var after = py.el.querySelectorAll('.CodeMirror-code > div').length;
      check(folded === 1 && after < before, 'python: oluk tıklaması kodu katlar (' + before + ' -> ' + after + ')');
      check(py.cm.getValue() === py.fx.code, 'python: katlama editör değerini değiştirmez');
      check(blocks.r.el.querySelectorAll('.CodeMirror-foldgutter-open').length > 0, 'r: süslü parantez katlaması çalışır');

      // Kopyalama: katlıyken bile TAM orijinal kod panoya gider.
      long.cm.foldCode(CodeMirror.Pos(0, 0));
      var copied = null;
      try {
        Object.defineProperty(navigator, 'clipboard', { configurable: true,
          value: { writeText: function (t) { copied = t; return Promise.resolve(); } } });
      } catch (e) { log('INFO clipboard stub kurulamadı: ' + e); }
      long.wrap.querySelector('.code-copy-btn').click();
      await wait(50);
      check(copied === long.fx.code, 'kopyalama: katlı uzun kodda tam orijinal metin (' + (copied ? copied.length : 0) + '/' + long.fx.code.length + ')');

      check(consoleErrors.length === 0, 'konsolda hata yok' + (consoleErrors.length ? ': ' + consoleErrors.join(' | ') : ''));
    } catch (e) {
      failures.push('istisna: ' + (e && e.stack ? e.stack : e));
    }

    logEl.textContent = logLines.join('\n');
    statusEl.textContent = failures.length === 0
      ? 'CODEMIRROR_RENDER_CHECK:PASS'
      : 'CODEMIRROR_RENDER_CHECK:FAIL ' + failures.length + '\n' + failures.join('\n');
  }

  run();
})();
