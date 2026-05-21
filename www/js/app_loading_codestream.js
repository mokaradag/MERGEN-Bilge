// www/js/app_loading_codestream.js
// Dosya Yolu: www/js/app_loading_codestream.js
// Açıklama: Açılış yükleme ekranındaki akan kod katmanı motoru.
//   Kod parçalarını ekranın kenar bantlarında rastgele konumlandırır,
//   karakter karakter yazar, hafif sözdizimi renklendirmesi uygular ve
//   yavaşça eriterek kaybeder. Havuz www/js/app_loading_snippets.js'tedir.
//   Bu dosya R/module_app_loading.R tarafından satır içine gömülür.

(function () {
  "use strict";

  // Sözdizimi anahtar kelimeleri (dil bağımsız, dekoratif renklendirme)
  var KEYWORDS = {};
  (
    "function func fn def lambda return if else elif endif for foreach while do " +
    "end class struct interface enum type record public private protected static " +
    "void int integer double float real string str bool boolean char var let const " +
    "val new delete import from package namespace using include this self super " +
    "true false nil null none and or not in is then begin async await yield match " +
    "case switch break continue with as defun select where group order by join " +
    "left right inner outer having rank over count sum avg distinct guard where"
  ).split(" ").forEach(function (kw) { KEYWORDS[kw] = true; });

  // Dile göre satır yorum işaretleri
  var COMMENT_MARKS = {
    "R": ["#"], "Python": ["#"], "Bash": ["#"], "Julia": ["#"],
    "PowerShell": ["#"], "Ruby": ["#"], "PHP": ["#", "//"],
    "JavaScript": ["//"], "TypeScript": ["//"], "C++": ["//"], "C#": ["//"],
    "Java": ["//"], "Go": ["//"], "Rust": ["//"], "Kotlin": ["//"],
    "Swift": ["//"], "SQL": ["--"], "Lisp": [";"], "Fortran": ["!"],
    "MATLAB": ["%"]
  };

  var IDENT_START = /[A-Za-z_$]/;
  var IDENT_BODY = /[A-Za-z0-9_$]/;

  var container = null;
  var items = [];
  var spawnTimer = null;
  var running = false;
  var reducedMotion = false;
  var MAX_ITEMS = 6;

  function escapeHtml(text) {
    return text
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  // Tek satırı sözdizimi belirteçlerine ayır
  function tokenizeLine(text, marks) {
    var tokens = [];
    var i = 0;
    var n = text.length;

    while (i < n) {
      var ch = text.charAt(i);

      if (ch === " " || ch === "\t") {
        var ws = i;
        while (i < n && (text.charAt(i) === " " || text.charAt(i) === "\t")) i++;
        tokens.push({ t: text.slice(ws, i), c: "plain" });
        continue;
      }

      var isComment = false;
      for (var m = 0; m < marks.length; m++) {
        if (text.substr(i, marks[m].length) === marks[m]) {
          tokens.push({ t: text.slice(i), c: "comment" });
          i = n;
          isComment = true;
          break;
        }
      }
      if (isComment) break;

      if (ch === '"' || ch === "'") {
        var s = i;
        i++;
        while (i < n && text.charAt(i) !== ch) {
          if (text.charAt(i) === "\\") i++;
          i++;
        }
        i = Math.min(i + 1, n);
        tokens.push({ t: text.slice(s, i), c: "string" });
        continue;
      }

      if (ch >= "0" && ch <= "9") {
        var d = i;
        while (i < n && /[0-9._]/.test(text.charAt(i))) i++;
        tokens.push({ t: text.slice(d, i), c: "number" });
        continue;
      }

      if (IDENT_START.test(ch)) {
        var w = i;
        while (i < n && IDENT_BODY.test(text.charAt(i))) i++;
        var word = text.slice(w, i);
        var cls = "plain";
        if (KEYWORDS[word.toLowerCase()]) {
          cls = "keyword";
        } else if (text.charAt(i) === "(") {
          cls = "func";
        }
        tokens.push({ t: word, c: cls });
        continue;
      }

      tokens.push({ t: ch, c: "punct" });
      i++;
    }

    return tokens;
  }

  // Belirteç dizisini en fazla `limit` karaktere kadar HTML'e dönüştür
  function tokensToHtml(tokens, limit) {
    var html = "";
    var used = 0;

    for (var i = 0; i < tokens.length; i++) {
      var tok = tokens[i];
      if (used >= limit) break;

      var slice = tok.t;
      if (used + slice.length > limit) {
        slice = slice.slice(0, limit - used);
      }
      used += slice.length;

      if (tok.c === "plain") {
        html += escapeHtml(slice);
      } else {
        html += '<span class="alo-tok-' + tok.c + '">' + escapeHtml(slice) + "</span>";
      }
    }

    return html;
  }

  function lineLength(tokens) {
    var total = 0;
    for (var i = 0; i < tokens.length; i++) total += tokens[i].t.length;
    return total;
  }

  // Kod öğesini kenar bantlarına yerleştir (merkez sahne korunur)
  function placeItem(el) {
    var side = Math.random() < 0.5 ? "left" : "right";
    var top = 7 + Math.random() * 77;

    if (side === "left") {
      el.style.left = (1 + Math.random() * 22).toFixed(1) + "vw";
    } else {
      el.style.right = (1 + Math.random() * 21).toFixed(1) + "vw";
    }
    el.style.top = top.toFixed(1) + "vh";
  }

  function renderItem(item) {
    var html = "";
    if (item.lang) {
      html += '<span class="alo-code-lang">' + escapeHtml(item.lang) + "</span>";
    }

    for (var i = 0; i <= item.lineIndex && i < item.lines.length; i++) {
      var limit = i < item.lineIndex ? Infinity : item.charInLine;
      var inner = tokensToHtml(item.lines[i], limit);
      if (i === item.lineIndex && !item.done) {
        inner += '<span class="alo-cursor"></span>';
      }
      html += '<span class="alo-code-line">' + (inner || "&nbsp;") + "</span>";
    }

    item.el.innerHTML = html;
  }

  function dissolveItem(item) {
    item.el.classList.add("alo-code-out");
    item.timer = window.setTimeout(function () {
      if (item.el && item.el.parentNode) {
        item.el.parentNode.removeChild(item.el);
      }
      var idx = items.indexOf(item);
      if (idx >= 0) items.splice(idx, 1);
    }, 1300);
  }

  function typeStep(item) {
    if (!running) return;

    var line = item.lines[item.lineIndex];
    item.charInLine++;

    if (item.charInLine >= item.lineLengths[item.lineIndex]) {
      item.charInLine = item.lineLengths[item.lineIndex];
      renderItem(item);
      item.lineIndex++;

      if (item.lineIndex >= item.lines.length) {
        item.done = true;
        renderItem(item);
        item.timer = window.setTimeout(function () {
          if (running) dissolveItem(item);
        }, 2300 + Math.random() * 1500);
        return;
      }

      item.charInLine = 0;
      item.timer = window.setTimeout(function () { typeStep(item); }, 150 + Math.random() * 170);
      return;
    }

    renderItem(item);
    item.timer = window.setTimeout(function () { typeStep(item); }, 13 + Math.random() * 22);
  }

  function spawnItem() {
    if (!running || !container) return;

    var pool = window.MergenLoadingSnippets;
    if (!pool || !pool.length) return;

    var snippet = pool[Math.floor(Math.random() * pool.length)];
    var marks = COMMENT_MARKS[snippet.lang] || ["#", "//"];

    var el = document.createElement("div");
    el.className = "alo-code-item";
    placeItem(el);
    container.appendChild(el);

    var tokenLines = snippet.lines.map(function (text) {
      return tokenizeLine(text, marks);
    });

    var item = {
      el: el,
      lang: snippet.lang,
      lines: tokenLines,
      lineLengths: tokenLines.map(lineLength),
      lineIndex: 0,
      charInLine: 0,
      done: false,
      timer: null
    };
    items.push(item);

    if (reducedMotion) {
      // Hareket azaltma: yazma efekti olmadan tüm bloğu göster
      item.lineIndex = item.lines.length - 1;
      item.charInLine = item.lineLengths[item.lineIndex];
      item.done = true;
      renderItem(item);
      window.requestAnimationFrame(function () { el.classList.add("alo-code-in"); });
      item.timer = window.setTimeout(function () {
        if (running) dissolveItem(item);
      }, 3600 + Math.random() * 2200);
      return;
    }

    renderItem(item);
    window.requestAnimationFrame(function () { el.classList.add("alo-code-in"); });
    item.timer = window.setTimeout(function () { typeStep(item); }, 220 + Math.random() * 260);
  }

  function scheduleSpawn() {
    if (!running) return;

    if (items.length < MAX_ITEMS) {
      spawnItem();
    }

    var delay = reducedMotion ? 2600 + Math.random() * 1800 : 760 + Math.random() * 620;
    spawnTimer = window.setTimeout(scheduleSpawn, delay);
  }

  function start(containerElement) {
    if (running || !containerElement) return;

    container = containerElement;
    running = true;
    reducedMotion = !!(window.matchMedia &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches);
    MAX_ITEMS = reducedMotion ? 3 : 6;

    // İlk birkaç öğeyi kademeli olarak başlat
    spawnItem();
    window.setTimeout(function () { if (running) spawnItem(); }, 520);
    spawnTimer = window.setTimeout(scheduleSpawn, 1100);
  }

  function stop() {
    running = false;
    if (spawnTimer) {
      window.clearTimeout(spawnTimer);
      spawnTimer = null;
    }
    for (var i = 0; i < items.length; i++) {
      if (items[i].timer) window.clearTimeout(items[i].timer);
    }
    items = [];
    container = null;
  }

  window.MergenLoadingCodestream = { start: start, stop: stop };
})();
