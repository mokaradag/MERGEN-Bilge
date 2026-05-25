// www/js/app_loading_codestream.js
// Dosya Yolu: www/js/app_loading_codestream.js
// Açıklama: Açılış yükleme ekranındaki akan içerik katmanı motoru.
//   İçerik parçalarını (kod ve düz metin) ekranın kenar bantlarındaki
//   sabit ŞERİTLERE yerleştirir; öğeler asla üst üste binmez. Her görünür
//   karakter ayrı bir kapsayıcıdadır ve sırayla yumuşakça belirir
//   (sürekli fade-in). Düzen baştan sabit olduğundan yazıldıkça blok kaymaz.
//   Havuz: www/js/app_loading_snippets.js + www/js/app_loading_content.js.
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
    "left right inner outer having rank over count sum avg distinct guard data"
  ).split(" ").forEach(function (kw) { KEYWORDS[kw] = true; });

  // Dile göre satır yorum işaretleri
  var COMMENT_MARKS = {
    "R": ["#"], "Python": ["#"], "Bash": ["#"], "Julia": ["#"],
    "PowerShell": ["#"], "Ruby": ["#"], "PHP": ["#", "//"],
    "JavaScript": ["//"], "TypeScript": ["//"], "C++": ["//"], "C#": ["//"],
    "Java": ["//"], "Go": ["//"], "Rust": ["//"], "Kotlin": ["//"],
    "Swift": ["//"], "SQL": ["--"], "Lisp": [";"], "Fortran": ["!"],
    "MATLAB": ["%"], "ABAP": ["*"], "JQL": []
  };

  var IDENT_START = /[A-Za-z_$]/;
  var IDENT_BODY = /[A-Za-z0-9_$]/;
  var MAX_DISPLAY_LINES = 5;

  var container = null;
  var items = [];
  var lanes = [];
  var spawnTimer = null;
  var running = false;
  var reducedMotion = false;
  var MAX_ITEMS = 4;

  // --------------------------------------------------------------------------
  // Şerit (lane) düzeni - kod/metin öğeleri asla üst üste binmez
  // --------------------------------------------------------------------------

  function buildLanes() {
    lanes = [];
    // Sol ve sağ bantlardaki dikey şerit konumları (vh). Bantlar yatayda
    // ayrı taraflarda olduğundan sol-sağ çakışması da imkansızdır.
    var leftTops = [7, 35, 63];
    var rightTops = [19, 47, 75];
    var i;
    for (i = 0; i < leftTops.length; i++) {
      lanes.push({ side: "left", top: leftTops[i], busy: false });
    }
    for (i = 0; i < rightTops.length; i++) {
      lanes.push({ side: "right", top: rightTops[i], busy: false });
    }
  }

  function pickFreeLane() {
    var free = [];
    for (var i = 0; i < lanes.length; i++) {
      if (!lanes[i].busy) free.push(lanes[i]);
    }
    if (free.length === 0) return null;
    return free[Math.floor(Math.random() * free.length)];
  }

  // --------------------------------------------------------------------------
  // Belirteçleme
  // --------------------------------------------------------------------------

  // Tek kod satırını sözdizimi belirteçlerine ayır
  function tokenizeCodeLine(text, marks) {
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
        if (marks[m].length && text.substr(i, marks[m].length) === marks[m]) {
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

  // Düz metin / soru-yanıt satırı: baştaki kısa "Etiket:" öneki ayrı renklenir
  function tokenizeNoteLine(text) {
    var colon = text.indexOf(": ");
    if (colon > 0 && colon <= 14) {
      var label = text.slice(0, colon + 1);
      // Etiket tek kelime olmalı (en çok bir boşluk içermeli)
      if (label.replace(/[^ ]/g, "").length <= 1) {
        return [
          { t: label, c: "qmark" },
          { t: text.slice(colon + 1), c: "prose" }
        ];
      }
    }
    return [{ t: text, c: "prose" }];
  }

  // --------------------------------------------------------------------------
  // Öğe oluşturma ve karakter belirme
  // --------------------------------------------------------------------------

  // Öğe DOM'unu baştan tamamen kurar: her görünür karakter ayrı bir span'dir
  // ve düzendeki yerini hemen alır. Belirme sadece opaklığı değiştirir,
  // bu yüzden yazıldıkça hiçbir blok yatayda kaymaz.
  function buildItem(snippet) {
    var isNote = !!snippet.tag;
    var lines = snippet.lines.slice(0, MAX_DISPLAY_LINES);
    var marks = COMMENT_MARKS[snippet.lang] || ["#", "//"];

    var el = document.createElement("div");
    el.className = "alo-code-item" + (isNote ? " alo-code-note" : "");

    var label = isNote ? snippet.tag : snippet.lang;
    if (label) {
      var langEl = document.createElement("span");
      langEl.className = "alo-code-lang" + (isNote ? " alo-lang-note" : "");
      langEl.textContent = label;
      el.appendChild(langEl);
    }

    var charSpans = [];
    for (var li = 0; li < lines.length; li++) {
      var lineEl = document.createElement("span");
      lineEl.className = "alo-code-line";

      var tokens = isNote
        ? tokenizeNoteLine(lines[li])
        : tokenizeCodeLine(lines[li], marks);

      for (var ti = 0; ti < tokens.length; ti++) {
        var tok = tokens[ti];
        var cls = (tok.c && tok.c !== "plain")
          ? "alo-ch alo-tok-" + tok.c
          : "alo-ch";

        for (var ci = 0; ci < tok.t.length; ci++) {
          var chr = tok.t.charAt(ci);
          var span = document.createElement("span");
          span.className = cls;
          span.textContent = chr;
          if (chr === " " || chr === "\t") {
            // Boşluklar anında "açık"; belirme sırası yalnızca görünür
            // karakterleri kapsar, böylece efekt akıcı kalır.
            span.className = cls + " alo-ch-on";
          } else {
            charSpans.push(span);
          }
          lineEl.appendChild(span);
        }
      }

      if (!lineEl.firstChild) {
        lineEl.appendChild(document.createTextNode(" "));
      }
      el.appendChild(lineEl);
    }

    return { el: el, charSpans: charSpans };
  }

  function dissolveItem(item) {
    if (item.dissolved) return;
    item.dissolved = true;
    item.el.classList.add("alo-code-out");
    item.timer = window.setTimeout(function () {
      if (item.el && item.el.parentNode) {
        item.el.parentNode.removeChild(item.el);
      }
      // Şerit yalnızca eriyen öğe DOM'dan tamamen silindikten sonra
      // serbest kalır; böylece erime sırasında bir öğe başka bir öğeyle
      // aynı şeride yerleşip üst üste binemez.
      if (item.lane) {
        item.lane.busy = false;
      }
      var idx = items.indexOf(item);
      if (idx >= 0) items.splice(idx, 1);
    }, 1300);
  }

  // Sıradaki karakteri belirginleştir - sürekli fade-in
  function revealNext(item) {
    if (!running || item.dissolved) return;

    if (item.revealIndex >= item.charSpans.length) {
      item.timer = window.setTimeout(function () {
        if (running) dissolveItem(item);
      }, 2400 + Math.random() * 1700);
      return;
    }

    item.charSpans[item.revealIndex].classList.add("alo-ch-on");
    item.revealIndex++;
    item.timer = window.setTimeout(function () {
      revealNext(item);
    }, 15 + Math.random() * 15);
  }

  function spawnItem() {
    if (!running || !container) return;

    var pool = window.MergenLoadingSnippets;
    if (!pool || !pool.length) return;

    var lane = pickFreeLane();
    if (!lane) return;

    var snippet = pool[Math.floor(Math.random() * pool.length)];
    if (!snippet || !snippet.lines || !snippet.lines.length) return;

    var built = buildItem(snippet);
    var el = built.el;

    lane.busy = true;
    el.style.top = lane.top.toFixed(1) + "vh";
    if (lane.side === "left") {
      el.style.left = (2 + Math.random() * 9).toFixed(1) + "vw";
    } else {
      el.style.right = (2 + Math.random() * 9).toFixed(1) + "vw";
    }

    container.appendChild(el);

    var item = {
      el: el,
      lane: lane,
      charSpans: built.charSpans,
      revealIndex: 0,
      dissolved: false,
      timer: null
    };
    items.push(item);

    if (reducedMotion) {
      for (var i = 0; i < built.charSpans.length; i++) {
        built.charSpans[i].classList.add("alo-ch-on");
      }
      item.revealIndex = built.charSpans.length;
    }

    window.requestAnimationFrame(function () {
      el.classList.add("alo-code-in");
    });

    if (reducedMotion) {
      item.timer = window.setTimeout(function () {
        if (running) dissolveItem(item);
      }, 4200 + Math.random() * 2400);
    } else {
      item.timer = window.setTimeout(function () {
        revealNext(item);
      }, 240 + Math.random() * 260);
    }
  }

  function scheduleSpawn() {
    if (!running) return;

    if (items.length < MAX_ITEMS) {
      spawnItem();
    }

    var delay = reducedMotion
      ? 3200 + Math.random() * 2000
      : 1100 + Math.random() * 900;
    spawnTimer = window.setTimeout(scheduleSpawn, delay);
  }

  function start(containerElement) {
    if (running || !containerElement) return;

    container = containerElement;
    running = true;
    reducedMotion = !!(window.matchMedia &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches);
    MAX_ITEMS = reducedMotion ? 2 : 4;
    buildLanes();

    spawnItem();
    window.setTimeout(function () { if (running) spawnItem(); }, 700);
    spawnTimer = window.setTimeout(scheduleSpawn, 1500);
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
    lanes = [];
    container = null;
  }

  // Genel API: yükleme akışı yaşam döngüsü + tokenizer/builder paylaşımı.
  // Araç arka plan animasyonları (www/js/tool_backgrounds.js) buradaki
  // tokenizeCodeLine / tokenizeNoteLine / buildItem fonksiyonlarını yeniden
  // kullanarak aynı görsel imzayı (alo-code-item yapısı + One Dark
  // sözdizimi renklendirmesi + karakter karakter typing) Ana Söyleşi
  // arka planına taşır. Bu paylaşım sayesinde duplicate JS sözlüğü/parser'ı
  // bulunmaz; iki ekran aynı snippet havuzu + aynı render motorunu kullanır.
  window.MergenLoadingCodestream = {
    start: start,
    stop: stop,
    // Pure helpers - DOM bağımsız, container/state gerektirmezler.
    tokenizeCodeLine: tokenizeCodeLine,
    tokenizeNoteLine: tokenizeNoteLine,
    buildItem: buildItem,
    MAX_DISPLAY_LINES: MAX_DISPLAY_LINES,
    COMMENT_MARKS: COMMENT_MARKS
  };
})();
