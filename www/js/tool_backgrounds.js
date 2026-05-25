// ============================================================
// Başlık: Araç Bağlamlı Sohbet Arka Plan Yöneticisi
// Dosya: www/js/tool_backgrounds.js
// Açıklama: Karşılama ekranından bir araç seçildiğinde Ana Söyleşi
//           arka planında ilgili araç ailesine uygun KÖŞE yedigen
//           kümesi + LANE-tabanlı karakter karakter beliren snippet
//           animasyonlarını yönetir.
//
//           Tasarım kararları (kullanıcı isteğine göre güncellendi):
//             - Snippet havuzu = welcome progress loading havuzu
//               (window.MergenLoadingSnippets). Aynı pool kullanılır.
//             - Rendering = window.MergenLoadingCodestream.buildItem
//               ile alo-code-item yapısı; her karakter ayrı span; alo-ch
//               + alo-ch-on sınıflarıyla sırayla belirir.
//             - 7 iç içe yedigen kümesi alt-sol köşede çeyrek kesit.
//             - Sabit dikey lane'ler — snippet'ler asla üst üste binmez.
//             - "Araç Arka Plan Animasyonları" toggle kapatılırsa tüm
//               sahne anında gizlenir.
// ============================================================

(function () {
  'use strict';

  var SETTINGS_KEY = 'mergen_settings';
  var ENABLED_KEY = 'enable_tool_backgrounds';
  var WRAPPER_SELECTOR = '#chat_main_wrapper';
  var WELCOME_SELECTOR = '#welcome_fullscreen_container';

  // Sol 2 + orta 2 + sağ 2 = 6 lane. Snippet sayısı bilinçli olarak
  // azaltıldı (max 3 aktif); rahatsız edici sahne önlenir. Orta lane'ler
  // mevcut tasarımı zenginleştirir; iki orta lane farklı dikey yerleşim
  // alır ve hafifçe daha şeffaf olur (CSS .alo-code-in opacity ile).
  // Üst üste binme imkansızdır — bir lane "busy" iken kullanılmaz.
  var LANE_DEFS = [
    { id: 'L1', side: 'left',   top: 12 },
    { id: 'L2', side: 'left',   top: 54 },
    { id: 'M1', side: 'center', top: 24 },
    { id: 'M2', side: 'center', top: 68 },
    { id: 'R1', side: 'right',  top: 18 },
    { id: 'R2', side: 'right',  top: 58 }
  ];

  var ACTION_TO_FAMILY = {
    'coding-support'    : 'coding',
    'project-process'   : 'process',
    'app-expert'        : 'app_expert',
    'resource-analysis' : 'sql_analysis',
    'excel-analysis'    : 'mcp_excel',
    'image-creation'    : 'image',
    'summarization'     : 'summarization'
  };

  var FLAG_TO_FAMILY = {
    'enable_coding_tools'        : 'coding',
    'enable_process_tools'       : 'process',
    'enable_app_expert_tools'    : 'app_expert',
    'enable_rdata_tools'         : 'sql_analysis',
    'enable_mcp_tools'           : 'mcp_excel',
    'enable_image_tools'         : 'image',
    'enable_summarization_tools' : 'summarization'
  };
  
  // -------------------------------------------------
  // Snippet filtreleri ve yedek havuz
  // Not: Fonksiyon yoğunluğu bütçesi için
  // www/js/tool_backgrounds_snippets.js içine taşındı.
  // -------------------------------------------------
  var TOOL_BACKGROUND_SNIPPET_CATALOG =
    window.MergenToolBackgroundSnippetCatalog || {};

  var FAMILY_FILTERS =
    TOOL_BACKGROUND_SNIPPET_CATALOG.FAMILY_FILTERS || {};

  var FALLBACK_SNIPPETS =
    TOOL_BACKGROUND_SNIPPET_CATALOG.FALLBACK_SNIPPETS || {};

  // Geriye uyumluluk sözleşmesi: TOOL_BACKGROUND_SNIPPETS sembolü korunur.
  var TOOL_BACKGROUND_SNIPPETS = FALLBACK_SNIPPETS;

  function getLoadingPool() {
    if (!window.MergenLoadingSnippets) return [];
    if (!Array.isArray(window.MergenLoadingSnippets)) return [];
    return window.MergenLoadingSnippets;
  }

  function getSharedRenderer() {
    // Welcome loading IIFE buildItem/tokenize fonksiyonlarını burada
    // paylaşır. Yalnız mevcut/çağrılabilir ise döner; aksi halde lokal
    // basit fallback'a düşeriz.
    var api = window.MergenLoadingCodestream;
    if (api && typeof api.buildItem === 'function') return api;
    return null;
  }

  function pickSnippetForFamily(family, lastSigs) {
    var filter = FAMILY_FILTERS[family];
    var pool = getLoadingPool();
    var candidates = [];

    if (pool.length > 0 && typeof filter === 'function') {
      for (var i = 0; i < pool.length; i++) {
        try { if (filter(pool[i])) candidates.push(pool[i]); }
        catch (e) { /* yoksay */ }
      }
    }

    if (candidates.length === 0) {
      candidates = (FALLBACK_SNIPPETS[family] || []).slice();
    }
    if (candidates.length === 0) return null;

    // Son kullanılanları atlamaya çalış
    var attempts = 5;
    while (attempts-- > 0) {
      var c = candidates[Math.floor(Math.random() * candidates.length)];
      var sig = (c.lang || c.tag || '') + '::' +
                ((c.lines && c.lines[0]) ? c.lines[0] : '');
      if (lastSigs.indexOf(sig) === -1) {
        c.__sig = sig;
        return c;
      }
    }
    var chosen = candidates[Math.floor(Math.random() * candidates.length)];
    chosen.__sig = (chosen.lang || chosen.tag || '') + '::' +
                   ((chosen.lines && chosen.lines[0]) ? chosen.lines[0] : '');
    return chosen;
  }

  // -------------------------------------------------
  // Yardımcılar
  // -------------------------------------------------
  function readSettings() {
    try {
      var raw = window.localStorage.getItem(SETTINGS_KEY);
      if (!raw) return null;
      var parsed = JSON.parse(raw);
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        return parsed;
      }
    } catch (e) { /* yoksay */ }
    return null;
  }

  function persistEnabled(value) {
    try {
      var s = readSettings() || {};
      s[ENABLED_KEY] = !!value;
      window.localStorage.setItem(SETTINGS_KEY, JSON.stringify(s));
    } catch (e) { /* yoksay */ }
  }

  function isEnabled() {
    var s = readSettings();
    if (!s) return true;
    if (typeof s[ENABLED_KEY] === 'boolean') return s[ENABLED_KEY];
    return true;
  }

  function isReducedMotion() {
    try {
      return window.matchMedia &&
             window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    } catch (e) { return false; }
  }

  function getWrapper() { return document.querySelector(WRAPPER_SELECTOR); }

  function welcomeVisible() {
    var w = document.querySelector(WELCOME_SELECTOR);
    if (!w) return false;
    var style = w.getAttribute('style') || '';
    if (/display\s*:\s*none/i.test(style)) return false;
    return w.offsetParent !== null;
  }

  // -------------------------------------------------
  // Heptagon (welcome loading alo-corner ile aynı: 7 iç içe yedigen)
  // -------------------------------------------------
  function heptPointsString(cx, cy, r) {
    var pts = [];
    for (var i = 0; i < 7; i++) {
      var a = -Math.PI / 2 + (i * 2 * Math.PI) / 7;
      pts.push((cx + r * Math.cos(a)).toFixed(2) + ',' +
               (cy + r * Math.sin(a)).toFixed(2));
    }
    return pts.join(' ');
  }

  function buildCornerHeptagonsSvg() {
    var ns = 'http://www.w3.org/2000/svg';
    var svg = document.createElementNS(ns, 'svg');
    svg.setAttribute('viewBox', '-150 -150 300 300');
    svg.setAttribute('aria-hidden', 'true');
    svg.setAttribute('focusable', 'false');
    var radii = [22, 38, 56, 74, 92, 110, 130];
    for (var i = 0; i < 7; i++) {
      var poly = document.createElementNS(ns, 'polygon');
      poly.setAttribute('points', heptPointsString(0, 0, radii[i]));
      poly.setAttribute('class', 'hept-' + (i + 1));
      svg.appendChild(poly);
    }
    return svg;
  }

  // -------------------------------------------------
  // Layer kurma (idempotent). CSS sözleşme adları korunur:
  //   .tool-bg-heptagon, .tool-bg-snippets
  // -------------------------------------------------
  function ensureCornerLayer(layer) {
    if (!layer) return null;
    var glow = layer.querySelector(':scope > .tool-bg-corner-glow');
    if (!glow) {
      glow = document.createElement('div');
      glow.className = 'tool-bg-corner-glow';
      layer.appendChild(glow);
    }
    var corner = layer.querySelector(':scope > .tool-bg-corner-heptagons');
    if (!corner) {
      corner = document.createElement('div');
      // .tool-bg-heptagon sınıfı tarihsel sözleşme; korunur.
      corner.className = 'tool-bg-corner-heptagons tool-bg-heptagon';
      corner.appendChild(buildCornerHeptagonsSvg());
      layer.appendChild(corner);
    } else if (!corner.querySelector('svg')) {
      corner.appendChild(buildCornerHeptagonsSvg());
    }
    return corner;
  }

  function ensureLaneContainer(layer) {
    if (!layer) return null;
    var lanes = layer.querySelector(':scope > .tool-bg-snippet-lanes');
    if (!lanes) {
      lanes = document.createElement('div');
      // .tool-bg-snippets sınıfı tarihsel sözleşme; korunur.
      lanes.className = 'tool-bg-snippet-lanes tool-bg-snippets';
      layer.appendChild(lanes);
    }
    for (var i = 0; i < LANE_DEFS.length; i++) {
      var def = LANE_DEFS[i];
      var el = lanes.querySelector(
        '.tool-bg-snippet-lane[data-lane="' + def.id + '"]'
      );
      if (!el) {
        el = document.createElement('div');
        el.className = 'tool-bg-snippet-lane';
        el.setAttribute('data-lane', def.id);
        el.setAttribute('data-side', def.side);
        el.setAttribute('data-busy', 'false');
        el.style.top = def.top + 'vh';
        lanes.appendChild(el);
      }
    }
    return lanes;
  }

  // Geriye uyumluluk sözleşmesi: eski test isimleri korunur.
  function ensureHeptagonLayer(layer) { return ensureCornerLayer(layer); }
  function ensureSnippetsHolder(layer) { return ensureLaneContainer(layer); }

  function buildHeptagonSvg(radius) {
    // Geriye uyumluluk: tek yedigen üreteci. Yeni tasarımda
    // buildCornerHeptagonsSvg ile 7 iç içe yedigen çizilir; bu wrapper
    // yalnızca .tool-bg-heptagon test sözleşmesi için korunur.
    var ns = 'http://www.w3.org/2000/svg';
    var svg = document.createElementNS(ns, 'svg');
    svg.setAttribute('viewBox', '0 0 240 240');
    svg.setAttribute('aria-hidden', 'true');
    var poly = document.createElementNS(ns, 'polygon');
    poly.setAttribute('points', heptPointsString(120, 120, radius || 100));
    svg.appendChild(poly);
    return svg;
  }

  function ensureLayer(wrapper) {
    if (!wrapper) return null;
    var layer = wrapper.querySelector(':scope > .tool-bg-layer');
    if (!layer) {
      layer = document.createElement('div');
      layer.className = 'tool-bg-layer';
      layer.setAttribute('aria-hidden', 'true');
      wrapper.insertBefore(layer, wrapper.firstChild);
    } else if (layer.getAttribute('aria-hidden') !== 'true') {
      layer.setAttribute('aria-hidden', 'true');
    }
    // Idempotent: her çağrıda alt katmanları tamamla.
    // .tool-bg-heptagon ve .tool-bg-snippets sözleşmeleri korunur.
    ensureHeptagonLayer(layer);
    ensureSnippetsHolder(layer);
    return layer;
  }

  // -------------------------------------------------
  // Snippet öğesi inşası
  //   Tercih: window.MergenLoadingCodestream.buildItem (welcome loading
  //          IIFE'sinde tanımlı, alo-code-item + tokenizer + sözdizimi
  //          renklendirme dahil).
  //   Yedek: minimum karakter span'lı satır render (font yok yine ama
  //          karakter karakter typing efekti korunur).
  // -------------------------------------------------
  function buildSnippetEl(snippet) {
    var shared = getSharedRenderer();
    if (shared) {
      var built = shared.buildItem(snippet);
      if (built && built.el) {
        // Tool-bg konteyner sınıfı ekle (CSS opacity/transform için).
        built.el.classList.add('tool-bg-typed-snippet');
        // Welcome loading progress sahnesi caret kullanmıyor; aynı görsel
        // dili korumak için tool bg snippet'lerine de caret eklenmez.
        return built;
      }
    }

    // Yedek: en sade satır render — tokenize/renklendirme yok ama
    // karakter karakter typing efekti korunur.
    var lines = (snippet.lines || []).slice(0, 5);
    var label = snippet.tag || snippet.lang || '';
    var el = document.createElement('div');
    el.className = 'tool-bg-typed-snippet alo-code-item' +
                   (snippet.tag ? ' alo-code-note' : '');
    if (label) {
      var lab = document.createElement('span');
      lab.className = 'alo-code-lang' + (snippet.tag ? ' alo-lang-note' : '');
      lab.textContent = label;
      el.appendChild(lab);
    }
    var charSpans = [];
    for (var li = 0; li < lines.length; li++) {
      var lineEl = document.createElement('span');
      lineEl.className = 'alo-code-line';
      var text = lines[li] || ' ';
      for (var ci = 0; ci < text.length; ci++) {
        var ch = text.charAt(ci);
        var sp = document.createElement('span');
        sp.className = 'alo-ch alo-tok-prose';
        sp.textContent = ch;
        if (ch === ' ' || ch === '\t') sp.classList.add('alo-ch-on');
        else charSpans.push(sp);
        lineEl.appendChild(sp);
      }
      el.appendChild(lineEl);
    }
    // Welcome loading progress sahnesi caret kullanmıyor; yedek render
    // yolu da aynı görsel sözleşmeyi korur (caret eklenmez).
    return { el: el, charSpans: charSpans };
  }

  // -------------------------------------------------
  // Snippet yaşam döngüsü
  // -------------------------------------------------
  var spawnTimer = null;
  var currentFamily = null;
  var ACTIVE_SNIPPETS = [];

  function findFreeLane(layer) {
    if (!layer) return null;
    var lanes = layer.querySelectorAll('.tool-bg-snippet-lane');
    var free = [];
    for (var i = 0; i < lanes.length; i++) {
      if (lanes[i].getAttribute('data-busy') !== 'true') free.push(lanes[i]);
    }
    if (free.length === 0) return null;
    return free[Math.floor(Math.random() * free.length)];
  }

  function revealNext(rec) {
    if (!rec || rec.dissolved) return;
    if (rec.revealIndex >= rec.charSpans.length) {
      rec.timer = window.setTimeout(function () {
        dropSnippet(rec);
      }, 4200 + Math.random() * 2400);
      return;
    }
    rec.charSpans[rec.revealIndex].classList.add('alo-ch-on');
    rec.revealIndex++;
    rec.timer = window.setTimeout(function () { revealNext(rec); },
                                  15 + Math.random() * 15);
  }

  function dropSnippet(rec) {
    if (!rec || rec.dissolved) return;
    rec.dissolved = true;
    if (rec.el) rec.el.classList.add('is-leaving');
    rec.timer = window.setTimeout(function () {
      try { if (rec.el) rec.el.remove(); } catch (e) {}
      if (rec.lane) rec.lane.setAttribute('data-busy', 'false');
      var idx = ACTIVE_SNIPPETS.indexOf(rec);
      if (idx >= 0) ACTIVE_SNIPPETS.splice(idx, 1);
    }, 900);
  }

  function spawnOneSnippet(family) {
    var wrapper = getWrapper();
    if (!wrapper || welcomeVisible() || !isEnabled() || !family) return;
    var layer = ensureLayer(wrapper);
    if (!layer) return;
    var lane = findFreeLane(layer);
    if (!lane) return;

    var lastSigs = ACTIVE_SNIPPETS
      .map(function (a) { return a.sig || ''; })
      .filter(function (s) { return s.length > 0; });

    var snippet = pickSnippetForFamily(family, lastSigs);
    if (!snippet) return;

    var built = buildSnippetEl(snippet);
    if (!built || !built.el) return;
    lane.appendChild(built.el);
    lane.setAttribute('data-busy', 'true');

    var rec = {
      lane: lane,
      el: built.el,
      charSpans: built.charSpans || [],
      revealIndex: 0,
      sig: snippet.__sig || '',
      timer: null,
      dissolved: false
    };
    ACTIVE_SNIPPETS.push(rec);

    window.requestAnimationFrame(function () {
      if (built.el) built.el.classList.add('alo-code-in');
    });

    if (isReducedMotion()) {
      for (var i = 0; i < rec.charSpans.length; i++) {
        rec.charSpans[i].classList.add('alo-ch-on');
      }
      rec.revealIndex = rec.charSpans.length;
      rec.timer = window.setTimeout(function () { dropSnippet(rec); },
                                    5000 + Math.random() * 2500);
    } else {
      rec.timer = window.setTimeout(function () { revealNext(rec); },
                                    240 + Math.random() * 260);
    }
  }

  // Aktif snippet limiti (max 3); kullanıcı şikayeti: çok fazla snippet
  // rahatsız edici görünüyor. Welcome loading progress ile uyumlu daha
  // sakin sahne.
  var MAX_ACTIVE_SNIPPETS = 3;

  function startSpawnLoop(family) {
    stopSpawnLoop();
    spawnTimer = window.setInterval(function () {
      if (!currentFamily || ACTIVE_SNIPPETS.length >= MAX_ACTIVE_SNIPPETS) return;
      spawnOneSnippet(currentFamily);
    }, 2200);
    // İlk dalga sadece 2 snippet — sahne kalabalık başlamasın.
    window.setTimeout(function () { spawnOneSnippet(family); }, 250);
    window.setTimeout(function () { spawnOneSnippet(family); }, 1100);
  }

  function stopSpawnLoop() {
    if (spawnTimer) { window.clearInterval(spawnTimer); spawnTimer = null; }
    for (var i = 0; i < ACTIVE_SNIPPETS.length; i++) {
      var r = ACTIVE_SNIPPETS[i];
      if (r && r.timer) window.clearTimeout(r.timer);
      if (r && r.el) { try { r.el.remove(); } catch (e) {} }
      if (r && r.lane) r.lane.setAttribute('data-busy', 'false');
    }
    ACTIVE_SNIPPETS = [];
  }

  function clearSnippets(layer) {
    if (!layer) return;
    var lanes = layer.querySelectorAll('.tool-bg-snippet-lane');
    for (var i = 0; i < lanes.length; i++) {
      lanes[i].innerHTML = '';
      lanes[i].setAttribute('data-busy', 'false');
    }
    stopSpawnLoop();
  }

  // -------------------------------------------------
  // Genel API
  // -------------------------------------------------
  function applyFamily(family, options) {
    options = options || {};
    var wrapper = getWrapper();
    if (!wrapper) return;
    ensureLayer(wrapper);

    if (!family || typeof family !== 'string') {
      wrapper.removeAttribute('data-tool-bg');
      clearSnippets(wrapper.querySelector(':scope > .tool-bg-layer'));
      currentFamily = null;
      return;
    }

    currentFamily = family;
    wrapper.setAttribute('data-tool-bg', family);

    if (!isEnabled()) {
      wrapper.classList.add('tool-bg-disabled');
      stopSpawnLoop();
      return;
    }
    wrapper.classList.remove('tool-bg-disabled');

    clearSnippets(wrapper.querySelector(':scope > .tool-bg-layer'));
    if (!welcomeVisible()) startSpawnLoop(family);
  }

  function clearBackground() { applyFamily(null); }

  function setEnabled(enabled, options) {
    options = options || {};
    var wrapper = getWrapper();
    var v = !!enabled;
    if (options.persist !== false) persistEnabled(v);
    if (!wrapper) return;
    if (v) {
      wrapper.classList.remove('tool-bg-disabled');
      // Re-enable bug onarımı: katmanı yeniden kur, varsa mevcut aileyi
      // tekrar uygula. Bu sayede ayar bir oturumda kapatılıp tekrar
      // açıldığında animasyonlar güvenilir biçimde geri gelir.
      ensureLayer(wrapper);
      if (currentFamily && !welcomeVisible()) {
        // Önce eski snippet ve timer'ları temizle, sonra başlat.
        stopSpawnLoop();
        startSpawnLoop(currentFamily);
      }
    } else {
      wrapper.classList.add('tool-bg-disabled');
      stopSpawnLoop();
      clearSnippets(wrapper.querySelector(':scope > .tool-bg-layer'));
    }
  }

  function familyForActionId(actionId) {
    return actionId ? (ACTION_TO_FAMILY[actionId] || null) : null;
  }
  function familyForFlag(flag) {
    return flag ? (FLAG_TO_FAMILY[flag] || null) : null;
  }

  // -------------------------------------------------
  // Olay bağlantıları
  // -------------------------------------------------
  function bindQuickActionListener() {
    document.addEventListener('click', function (ev) {
      var btn = ev.target && ev.target.closest &&
                ev.target.closest('.modern-welcome-action-btn');
      if (!btn) return;
      var fam = familyForActionId(btn.getAttribute('data-action-id') || '');
      if (fam) applyFamily(fam);
    }, true);
  }

  function bindWelcomeVisibilityWatch() {
    var welcome = document.querySelector(WELCOME_SELECTOR);
    if (!welcome) {
      window.setTimeout(bindWelcomeVisibilityWatch, 200);
      return;
    }
    var mo = new MutationObserver(function () {
      var wrapper = getWrapper();
      if (!wrapper || !currentFamily) return;
      if (welcomeVisible()) {
        stopSpawnLoop();
        clearSnippets(wrapper.querySelector(':scope > .tool-bg-layer'));
      } else if (isEnabled()) {
        startSpawnLoop(currentFamily);
      }
    });
    mo.observe(welcome, { attributes: true, attributeFilter: ['style', 'class'] });
  }

  function bindShinyToggles() {
    if (!window.Shiny || typeof window.Shiny.addCustomMessageHandler !== 'function') {
      window.setTimeout(bindShinyToggles, 200);
      return;
    }

    window.Shiny.addCustomMessageHandler('toggleToolBackgrounds', function (data) {
      setEnabled(!!(data && data.enabled), { persist: true });
    });

    window.Shiny.addCustomMessageHandler('setToolBackgroundFamily', function (data) {
      if (!data) return;
      var fam = null;
      if (typeof data.family === 'string' && data.family) fam = data.family;
      else if (typeof data.action_id === 'string' && data.action_id) {
        fam = familyForActionId(data.action_id);
      } else if (typeof data.flag === 'string' && data.flag) {
        fam = familyForFlag(data.flag);
      }
      if (fam) applyFamily(fam);
      else if (data && data.clear === true) clearBackground();
    });
  }

  function bindNewChatReset() {
    document.addEventListener('click', function (ev) {
      var t = ev.target;
      if (t && t.closest && t.closest('#new_chat_btn')) clearBackground();
    }, true);
  }

  function bindThemeChangeRefresh() {
    window.addEventListener('mergen:themechange', function () {
      if (currentFamily && !welcomeVisible() && isEnabled()) {
        stopSpawnLoop();
        startSpawnLoop(currentFamily);
      }
    });
  }

  // -------------------------------------------------
  // Genel API
  // -------------------------------------------------
  window.MergenToolBackgrounds = {
    apply: applyFamily,
    clear: clearBackground,
    setEnabled: setEnabled,
    isEnabled: isEnabled,
    familyForActionId: familyForActionId,
    familyForFlag: familyForFlag,
    KNOWN_FAMILIES: Object.keys(FAMILY_FILTERS),
    register: function (family, snippetList) {
      if (typeof family !== 'string' || !family) return false;
      if (!Array.isArray(snippetList)) return false;
      FALLBACK_SNIPPETS[family] = snippetList.slice();
      return true;
    },
    _debug: {
      activeCount: function () { return ACTIVE_SNIPPETS.length; },
      lanes: function () { return LANE_DEFS.slice(); }
    }
  };

  // -------------------------------------------------
  // Boot
  // -------------------------------------------------
  function boot() {
    bindQuickActionListener();
    bindWelcomeVisibilityWatch();
    bindShinyToggles();
    bindNewChatReset();
    bindThemeChangeRefresh();

    var tries = 0;
    var t = window.setInterval(function () {
      var wrapper = getWrapper();
      if (wrapper) {
        ensureLayer(wrapper);
        if (!isEnabled()) wrapper.classList.add('tool-bg-disabled');
        window.clearInterval(t);
      } else if (++tries > 50) {
        window.clearInterval(t);
      }
    }, 100);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();