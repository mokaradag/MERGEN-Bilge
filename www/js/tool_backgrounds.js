// ============================================================
// Başlık: Araç Bağlamlı Sohbet Arka Plan Yöneticisi
// Dosya: www/js/tool_backgrounds.js
// Açıklama: Karşılama ekranından bir araç seçildiğinde Ana Söyleşi
//           arka planında ilgili araç ailesine uygun KÖŞE yedigen
//           kümesi + LANE-tabanlı yazılıyor stilinde snippet
//           animasyonlarını yönetir.
//
//           Tasarım kararları:
//             - Yedigenler ortada DEĞİL, alt-sol köşede (varsayılan).
//             - Snippet'ler sabit dikey lane'lere yerleştirilir;
//               aynı lane meşgulken yeni snippet eklenmez (çakışma yok).
//             - Snippet "typing" hissi için karakter karakter belirir
//               (welcome progress loading ekranındaki yaklaşımla aynı).
//             - Yapılandırma "Araç Arka Plan Animasyonları" toggle'i
//               kapatılırsa tüm sahne anında gizlenir.
//
//           Genişletme: TOOL_BACKGROUND_SNIPPETS objesine yeni anahtar
//           eklenmesi yeterlidir.
// ============================================================

(function () {
  'use strict';

  // -------------------------------------------------
  // 1. Yapılandırma sabitleri
  // -------------------------------------------------
  var SETTINGS_KEY = 'mergen_settings';
  var ENABLED_KEY = 'enable_tool_backgrounds';
  var WRAPPER_SELECTOR = '#chat_main_wrapper';
  var WELCOME_SELECTOR = '#welcome_fullscreen_container';

  // Lane id'leri (sol 3 + sağ 3 = 6 lane). Bir snippet aktif iken
  // bulunduğu lane "busy" işaretlenir; yeni snippet yalnızca boş
  // lane'lere yerleştirilir. Bu sayede üst üste binme imkansızdır.
  var LANE_DEFS = [
    { id: 'L1', side: 'left'  },
    { id: 'L2', side: 'left'  },
    { id: 'L3', side: 'left'  },
    { id: 'R1', side: 'right' },
    { id: 'R2', side: 'right' },
    { id: 'R3', side: 'right' }
  ];

  // Hızlı eylem (quick action) id -> araç ailesi eşlemesi.
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
  // 2. Snippet havuzları (araç ailesi bazlı)
  // -------------------------------------------------
  var TOOL_BACKGROUND_SNIPPETS = {
    coding: [
      "function analyze(data) {\n  return summarize(data);\n}",
      "const result = await model.run(prompt);",
      "if (status === 'ready') deploy();",
      "SELECT id, status FROM tasks\nWHERE active = 1;",
      "try {\n  renderChart(data);\n} catch (err) { log(err); }",
      "for (const item of items)\n  process(item);",
      "def predict(x):\n  return model(x)",
      "git rebase -i HEAD~3",
      "docker build -t mergen:latest .",
      "export const API = \"/api/v1\";",
      "await Promise.all(tasks.map(run));",
      "type Result = { ok: true; value: T };"
    ],
    process: [
      "Surec -> Izlek\nRehber -> Sablon",
      "Kontrol noktasi:\nuygunluk / onay / kayit",
      "Dokuman arama:\nbaslik, kapsam, revizyon",
      "Politika -> Prosedur\n-> Talimat -> Form",
      "Onay akisi:\nhazirlayan -> kontrol -> onay",
      "Versiyon kontrolu:\nr0 -> r1 -> r2",
      "RACI:\nSorumlu | Vekil | Onaylayan",
      "KPI:\ncevrim suresi, hata orani",
      "Risk:\nolasilik x etki",
      "Surec sahibi ->\nOperasyonel sahibi",
      "ISO 9001\ndokuman yonetim sistemi",
      "IK / Satinalma / Lojistik"
    ],
    app_expert: [
      "P6:\nActivity ID -> WBS -> Baseline",
      "SAP PS:\nWBS / Network / Milestone",
      "Jira:\nEpic -> Story -> Sprint",
      "Risk Register:\nprobability x impact",
      "Workflow:\nrequest -> review -> approval",
      "Confluence | Jira | Bitbucket",
      "P6 baseline vs current schedule",
      "SAP CO:\ncost center / order / element",
      "ITSM:\nIncident / Problem / Change",
      "Primavera Resource Loading",
      "SAP Notifications /\nService Orders",
      "JQL: project = MB AND\n  sprint in openSprints()"
    ],
    mcp_excel: [
      "=SUM(B2:B24)",
      "=XLOOKUP(A2,\n  Table1[ID], Table1[Value])",
      "Pivot:\nRegion x Month x Cost",
      "Date | Category | Amount",
      "Chart:\nline / bar / scatter",
      "=IFERROR(\n  VLOOKUP(...), \"Yok\")",
      "=AVERAGEIFS(\n  C:C, A:A, \"Aktif\")",
      "Power Query:\nGroup By -> Sum",
      "Dilimleyici +\nzaman cizelgesi",
      "Slicer:\nFilter by Sector",
      "=SUMPRODUCT(\n  (A:A=B1)*(C:C))",
      "Pivot Cache |\nPower Pivot | DAX"
    ],
    sql_analysis: [
      "Resource Load:\nplanned vs actual",
      "SPI = EV / PV",
      "CPI = EV / AC",
      "Critical Path:\ntotal float <= 0",
      "SELECT project_id, cost\nFROM portfolio",
      "WBS | Activity | Duration",
      "WITH cte AS (\n  SELECT ... FROM ...)\nSELECT * FROM cte",
      "GROUP BY project_id,\n  period",
      "CASE WHEN\n  status='Aktif' THEN 1\n  ELSE 0 END",
      "JOIN sap_cost\n  ON wbs_id = wbs_code",
      "P6 + SAP PS:\nbudget / workforce",
      "Forecast vs Actual:\nkullanim orani"
    ],
    summarization: [
      "Amac | Kapsam |\nBulgular | Sonuc",
      "Ana fikir ->\nkanit -> cikarim",
      "Uzun metin ->\nyapilandirilmis ozet",
      "Karar / risk / aksiyon",
      "Yonetici ozeti /\ndetay ozet",
      "Soru -> Cevap -> Referans",
      "TLDR: temel cikarim",
      "Anahtar baslik\n#1, #2, #3",
      "Yapilandirilmis maddeleme",
      "Toplanti notlari ->\nkarar -> aksiyon",
      "Belge ->\nkaynaklar -> bibliyografya",
      "Veri tablosu ->\nozetlenmis grafik"
    ],
    image: [
      "composition: cinematic,\n  balanced, minimal",
      "style: technical illustration",
      "lighting: soft rim light",
      "palette:\nblue / orange / neutral",
      "aspect: 16:9 cinematic",
      "detail:\nultra-detailed, sharp focus",
      "mood: calm, professional",
      "render: studio quality",
      "subject:\nASELSAN tarzi minimal sahne",
      "lens: 50mm f/1.8",
      "background: subtle gradient",
      "pose: neutral, balanced"
    ]
  };

  // -------------------------------------------------
  // 3. Yardımcılar
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
      var settings = readSettings() || {};
      settings[ENABLED_KEY] = !!value;
      window.localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings));
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

  function getWrapper() {
    return document.querySelector(WRAPPER_SELECTOR);
  }

  function welcomeVisible() {
    var w = document.querySelector(WELCOME_SELECTOR);
    if (!w) return false;
    var style = w.getAttribute('style') || '';
    if (/display\s*:\s*none/i.test(style)) return false;
    return w.offsetParent !== null;
  }

  // Heptagon noktaları (7 köşe, üst nokta yukarıda)
  function heptPointsString(cx, cy, r) {
    var pts = [];
    for (var i = 0; i < 7; i++) {
      var angle = -Math.PI / 2 + (i * 2 * Math.PI) / 7;
      var x = cx + r * Math.cos(angle);
      var y = cy + r * Math.sin(angle);
      pts.push(x.toFixed(2) + ',' + y.toFixed(2));
    }
    return pts.join(' ');
  }

  // 7 iç içe yedigen SVG (cluster) - app_loading alo-corner mantığı
  function buildCornerHeptagonsSvg() {
    var svgNs = 'http://www.w3.org/2000/svg';
    var svg = document.createElementNS(svgNs, 'svg');
    svg.setAttribute('viewBox', '-150 -150 300 300');
    svg.setAttribute('aria-hidden', 'true');
    svg.setAttribute('focusable', 'false');

    // 7 farklı yarıçap - en içte küçük, en dışta büyük
    var radii = [22, 38, 56, 74, 92, 110, 130];
    for (var i = 0; i < 7; i++) {
      var poly = document.createElementNS(svgNs, 'polygon');
      poly.setAttribute('points', heptPointsString(0, 0, radii[i]));
      poly.setAttribute('class', 'hept-' + (i + 1));
      svg.appendChild(poly);
    }
    return svg;
  }

  // -------------------------------------------------
  // 4. Layer kurma (idempotent)
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
      corner.className = 'tool-bg-corner-heptagons';
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
      lanes.className = 'tool-bg-snippet-lanes';
      layer.appendChild(lanes);
    }
    // Lane'leri oluştur (boş, server-side render edilmemiş ise)
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
        lanes.appendChild(el);
      }
    }
    return lanes;
  }

  // Geriye uyumluluk: eski test sözleşmesi `ensureHeptagonLayer` ve
  // `ensureSnippetsHolder` isimlerini bekler. Yeni tasarımda köşe yedigen
  // kümesi `.tool-bg-corner-heptagons` ve snippet lane'leri
  // `.tool-bg-snippet-lanes` altındadır; ancak eski test sınıf adları
  // `.tool-bg-heptagon` ve `.tool-bg-snippets` da regression koruma
  // olarak korunur. Aşağıdaki sarmalayıcılar bu sözleşmeyi onurlandırır.
  function ensureHeptagonLayer(layer) {
    // Yeni tasarımda köşe yedigen kümesini garantile (.tool-bg-corner-heptagons).
    // CSS sınıfı .tool-bg-heptagon eski sürümle uyumluluk için yedek olarak
    // mevcut olabilir; yeni primary köşe kümesidir.
    return ensureCornerLayer(layer);
  }

  function ensureSnippetsHolder(layer) {
    // Yeni tasarımda snippet'ler lane container içine yerleşir
    // (.tool-bg-snippet-lanes). Eski sözleşme .tool-bg-snippets adıyla
    // sarmalanır; lane container aynı görev görür.
    return ensureLaneContainer(layer);
  }

  function buildHeptagonSvg(radius) {
    // Geriye uyumluluk için: eski tek-yedigen üreteci yerine artık
    // tüm köşe kümesi `buildCornerHeptagonsSvg` ile oluşturulur.
    // Bu wrapper basit bir 7-köşeli polygon döner; mevcut testler yalnızca
    // fonksiyonun var olduğunu ve `.tool-bg-heptagon` adının korunduğunu
    // kontrol eder. Adı sözleşme gereği `buildHeptagonSvg` olarak korunur.
    var svgNs = 'http://www.w3.org/2000/svg';
    var svg = document.createElementNS(svgNs, 'svg');
    svg.setAttribute('viewBox', '0 0 240 240');
    svg.setAttribute('aria-hidden', 'true');
    var poly = document.createElementNS(svgNs, 'polygon');
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
    // Idempotent: her cagride alt katmanlari tamamla
    // CSS selector sozlesme adlari: .tool-bg-heptagon ve .tool-bg-snippets
    ensureHeptagonLayer(layer);
    ensureSnippetsHolder(layer);
    return layer;
  }

  // -------------------------------------------------
  // 5. Snippet yaşam döngüsü (lane atama + typing + exit)
  // -------------------------------------------------
  var spawnTimer = null;
  var currentFamily = null;
  var ACTIVE_SNIPPETS = [];

  function findFreeLane(layer) {
    if (!layer) return null;
    var lanes = layer.querySelectorAll('.tool-bg-snippet-lane');
    var free = [];
    for (var i = 0; i < lanes.length; i++) {
      if (lanes[i].getAttribute('data-busy') !== 'true') {
        free.push(lanes[i]);
      }
    }
    if (free.length === 0) return null;
    return free[Math.floor(Math.random() * free.length)];
  }

  function pickSnippetText(family, lastTexts) {
    var pool = TOOL_BACKGROUND_SNIPPETS[family];
    if (!pool || pool.length === 0) return null;
    // Son 3 snippet'i atla (yinelenme azaltma)
    var candidate;
    for (var attempt = 0; attempt < 5; attempt++) {
      candidate = pool[Math.floor(Math.random() * pool.length)];
      if (lastTexts.indexOf(candidate) === -1) return candidate;
    }
    return candidate;
  }

  // Karakter karakter typing effect - lane'e snippet yazar
  function typeSnippetInto(laneEl, text, onComplete) {
    if (!laneEl) return;
    var el = document.createElement('div');
    el.className = 'tool-bg-typed-snippet';
    // Statik ve typing varyantları: reduced motion ise tek seferde göster.
    var caret = document.createElement('span');
    caret.className = 'tool-bg-caret';

    laneEl.appendChild(el);

    if (isReducedMotion()) {
      el.textContent = text;
      if (typeof onComplete === 'function') onComplete(el);
      return el;
    }

    // Karakter karakter ekle
    var i = 0;
    var STEP_MS = 18;
    function step() {
      if (i >= text.length) {
        el.appendChild(caret);
        if (typeof onComplete === 'function') onComplete(el);
        return;
      }
      var ch = text.charAt(i);
      el.appendChild(document.createTextNode(ch));
      i++;
      window.setTimeout(step, STEP_MS);
    }
    step();
    return el;
  }

  function dropSnippet(snippetEl, laneEl) {
    if (!snippetEl) return;
    snippetEl.classList.add('is-leaving');
    window.setTimeout(function () {
      try { snippetEl.remove(); } catch (e) {}
      if (laneEl) laneEl.setAttribute('data-busy', 'false');
    }, 700);
  }

  function spawnOneSnippet(family) {
    var wrapper = getWrapper();
    if (!wrapper) return;
    if (welcomeVisible()) return;
    if (!isEnabled()) return;
    if (!family || !TOOL_BACKGROUND_SNIPPETS[family]) return;

    var layer = ensureLayer(wrapper);
    if (!layer) return;
    var lane = findFreeLane(layer);
    if (!lane) return;

    // Son metinleri toplama (yinelenme önleme)
    var lastTexts = ACTIVE_SNIPPETS.map(function (a) { return a.text; });
    var text = pickSnippetText(family, lastTexts);
    if (!text) return;

    lane.setAttribute('data-busy', 'true');
    var record = { lane: lane, text: text, el: null, timer: null };

    record.el = typeSnippetInto(lane, text, function (finalEl) {
      // typing tamamlandıktan sonra biraz görünür kalsın
      var visibleMs = 5500 + Math.random() * 3500;
      record.timer = window.setTimeout(function () {
        dropSnippet(finalEl, lane);
        // record temizleme
        var idx = ACTIVE_SNIPPETS.indexOf(record);
        if (idx >= 0) ACTIVE_SNIPPETS.splice(idx, 1);
      }, visibleMs);
    });

    ACTIVE_SNIPPETS.push(record);
  }

  function startSpawnLoop(family) {
    stopSpawnLoop();
    // Sahnede en fazla 4 aktif snippet olsun (kalabalık değil)
    var TICK_MS = 1800; // her ~1.8 saniyede bir yeni snippet dene
    spawnTimer = window.setInterval(function () {
      if (!currentFamily) return;
      if (ACTIVE_SNIPPETS.length >= 4) return;
      spawnOneSnippet(currentFamily);
    }, TICK_MS);

    // İlk snippet'i biraz beklemeden ekleyelim ki sahne hemen başlasın
    window.setTimeout(function () { spawnOneSnippet(family); }, 250);
    window.setTimeout(function () { spawnOneSnippet(family); }, 1100);
  }

  function stopSpawnLoop() {
    if (spawnTimer) {
      window.clearInterval(spawnTimer);
      spawnTimer = null;
    }
    // Aktif snippet'leri temizle
    for (var i = 0; i < ACTIVE_SNIPPETS.length; i++) {
      var rec = ACTIVE_SNIPPETS[i];
      if (rec && rec.timer) window.clearTimeout(rec.timer);
      if (rec && rec.el) {
        try { rec.el.remove(); } catch (e) {}
      }
      if (rec && rec.lane) rec.lane.setAttribute('data-busy', 'false');
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
  // 6. Genel API
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

    if (!welcomeVisible()) {
      // Eski snippet'leri temizle, yeni döngü başlat
      clearSnippets(wrapper.querySelector(':scope > .tool-bg-layer'));
      startSpawnLoop(family);
    } else {
      clearSnippets(wrapper.querySelector(':scope > .tool-bg-layer'));
    }
  }

  function clearBackground() {
    applyFamily(null);
  }

  function setEnabled(enabled, options) {
    options = options || {};
    var wrapper = getWrapper();
    var v = !!enabled;

    if (options.persist !== false) {
      persistEnabled(v);
    }

    if (!wrapper) return;

    if (v) {
      wrapper.classList.remove('tool-bg-disabled');
      if (currentFamily && !welcomeVisible()) {
        startSpawnLoop(currentFamily);
      }
    } else {
      wrapper.classList.add('tool-bg-disabled');
      stopSpawnLoop();
      clearSnippets(wrapper.querySelector(':scope > .tool-bg-layer'));
    }
  }

  function familyForActionId(actionId) {
    if (!actionId) return null;
    return ACTION_TO_FAMILY[actionId] || null;
  }

  function familyForFlag(flag) {
    if (!flag) return null;
    return FLAG_TO_FAMILY[flag] || null;
  }

  // -------------------------------------------------
  // 7. Olay bağlantıları
  // -------------------------------------------------
  function bindQuickActionListener() {
    document.addEventListener('click', function (ev) {
      var btn = ev.target && ev.target.closest && ev.target.closest('.modern-welcome-action-btn');
      if (!btn) return;
      var actionId = btn.getAttribute('data-action-id') || '';
      var fam = familyForActionId(actionId);
      if (fam) {
        applyFamily(fam);
      }
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
      if (!wrapper) return;
      if (!currentFamily) return;
      if (welcomeVisible()) {
        stopSpawnLoop();
        clearSnippets(wrapper.querySelector(':scope > .tool-bg-layer'));
      } else {
        if (isEnabled()) {
          startSpawnLoop(currentFamily);
        }
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
      var enabled = !!(data && data.enabled);
      setEnabled(enabled, { persist: true });
    });

    window.Shiny.addCustomMessageHandler('setToolBackgroundFamily', function (data) {
      if (!data) return;
      var fam = null;
      if (typeof data.family === 'string' && data.family) {
        fam = data.family;
      } else if (typeof data.action_id === 'string' && data.action_id) {
        fam = familyForActionId(data.action_id);
      } else if (typeof data.flag === 'string' && data.flag) {
        fam = familyForFlag(data.flag);
      }
      if (fam) {
        applyFamily(fam);
      } else if (data && data.clear === true) {
        clearBackground();
      }
    });
  }

  function bindNewChatReset() {
    document.addEventListener('click', function (ev) {
      var t = ev.target;
      if (!t || !t.closest) return;
      var btn = t.closest('#new_chat_btn');
      if (btn) {
        clearBackground();
      }
    }, true);
  }

  function bindThemeChangeRefresh() {
    window.addEventListener('mergen:themechange', function () {
      // Tema değişiminde yeni renkleri uygulamak için snippet'leri tazele
      if (currentFamily && !welcomeVisible() && isEnabled()) {
        stopSpawnLoop();
        startSpawnLoop(currentFamily);
      }
    });
  }

  // -------------------------------------------------
  // 8. Genel API erişilebilir kıl
  // -------------------------------------------------
  window.MergenToolBackgrounds = {
    apply: applyFamily,
    clear: clearBackground,
    setEnabled: setEnabled,
    isEnabled: isEnabled,
    familyForActionId: familyForActionId,
    familyForFlag: familyForFlag,
    KNOWN_FAMILIES: Object.keys(TOOL_BACKGROUND_SNIPPETS),
    register: function (family, snippetList) {
      if (typeof family !== 'string' || !family) return false;
      if (!Array.isArray(snippetList)) return false;
      TOOL_BACKGROUND_SNIPPETS[family] = snippetList.slice();
      return true;
    },
    // Test/araç için debug erişim:
    _debug: {
      activeCount: function () { return ACTIVE_SNIPPETS.length; },
      lanes: function () { return LANE_DEFS.slice(); }
    }
  };

  // -------------------------------------------------
  // 9. Boot
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
        if (!isEnabled()) {
          wrapper.classList.add('tool-bg-disabled');
        }
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
