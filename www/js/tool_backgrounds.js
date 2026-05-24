// ============================================================
// Başlık: Araç Bağlamlı Sohbet Arka Plan Yöneticisi
// Dosya: www/js/tool_backgrounds.js
// Açıklama: Karşılama ekranından bir araç seçildiğinde Ana Söyleşi
//           arka planında ilgili araç ailesine uygun hafif heptagon ve
//           bağlam parçacık (snippet) animasyonlarını yönetir. Tüm
//           katmanlar pointer-events tutmaz; sohbet etkileşimi etkilenmez.
//           Yapılandırma sayfasından "Araç Arka Plan Animasyonları"
//           ayarı kapatılırsa katman anında gizlenir.
//
//           Genişletme: yeni bir araç ailesi eklenmek istenirse
//           TOOL_BACKGROUND_SNIPPETS objesine yeni anahtar/değer
//           çiftleri eklenmesi yeterlidir. R/JS/CSS tarafında ek
//           anahtar eklemek için family eşlemesini güncelleyin.
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

  // Hızlı eylem (quick action) id -> araç ailesi eşlemesi.
  // R tarafındaki tool_mode_config ile uyumludur; yeni eylem eklenirse
  // burada da kaydedilmelidir.
  var ACTION_TO_FAMILY = {
    'coding-support'    : 'coding',
    'project-process'   : 'process',
    'app-expert'        : 'app_expert',
    'resource-analysis' : 'sql_analysis',
    'excel-analysis'    : 'mcp_excel',
    'image-creation'    : 'image',
    'summarization'     : 'summarization'
  };

  // Araç adı (R tarafında settings flag adı) -> araç ailesi eşlemesi.
  // Server tarafındaki enable_* bayraklarını izleyen mesajlardan ya da
  // tool_active mesajlarından gelen ipuçlarını eşler.
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
  // 2. Bağlam parçacıkları (snippet) kayıtları
  // -------------------------------------------------
  var TOOL_BACKGROUND_SNIPPETS = {
    coding: [
      'function analyze(data) { return insights; }',
      "const result = await model.run(prompt);",
      "if (status === 'ready') deploy();",
      'SELECT id, status FROM tasks WHERE active = 1;',
      'try { renderChart(data); } catch (err) { log(err); }',
      'for (const item of items) process(item);',
      'def predict(x): return model(x)',
      'git rebase -i HEAD~3',
      'docker build -t mergen:latest .',
      'export const API = "/api/v1";',
      'await Promise.all(tasks.map(run));',
      'type Result = { ok: true, value: T };'
    ],
    process: [
      'Sürec -> Izlek -> Rehber -> Sablon',
      'Kontrol noktasi: uygunluk / onay / kayit',
      'Dokuman arama: baslik, kapsam, revizyon',
      'Politika -> Prosedur -> Talimat -> Form',
      'Onay akisi: hazirlayan -> kontrol -> onay',
      'Versiyon kontrolu: r0 -> r1 -> r2',
      'Sorumlu | Vekil | Onaylayan | Bilgilendirilen',
      'KPI: cevrim suresi, hata orani, tekrar yapilanma',
      'Risk: olasilik x etki x maruziyet',
      'Surec sahibi -> Operasyonel sahibi',
      'ISO 9001 | dokuman yonetim sistemi',
      'IK / Satinalma / Lojistik / Kalite akisi'
    ],
    app_expert: [
      'P6: Activity ID -> WBS -> Baseline',
      'SAP PS: WBS Element / Network / Milestone',
      'Jira: Epic -> Story -> Sprint -> Status',
      'Risk Register: probability x impact',
      'Workflow: request -> review -> approval',
      'Confluence | Jira | Bitbucket',
      'P6 baseline vs current schedule',
      'SAP CO: cost center / order / element',
      'ITSM: Incident / Problem / Change',
      'Primavera Resource Loading curve',
      'SAP Notifications / Service Orders',
      'Jira JQL: project = MB AND sprint in openSprints()'
    ],
    mcp_excel: [
      '=SUM(B2:B24)',
      '=XLOOKUP(A2,Table1[ID],Table1[Value])',
      'Pivot: Region x Month x Cost',
      'Date | Category | Amount | Forecast',
      'Chart: line / bar / scatter',
      '=IFERROR(VLOOKUP(...), "Yok")',
      '=AVERAGEIFS(C:C, A:A, "Aktif")',
      'Power Query: Group By -> Sum',
      'Excel: dilimleyici + zaman cizelgesi',
      'Slicer: Filter by Sector / Region',
      '=SUMPRODUCT((A:A=B1)*(C:C))',
      'Pivot Cache | Power Pivot | DAX'
    ],
    sql_analysis: [
      'Resource Load: planned vs actual',
      'SPI = EV / PV',
      'CPI = EV / AC',
      'Critical Path: total float <= 0',
      'SELECT project_id, cost, finish_date FROM portfolio',
      'WBS | Activity | Resource | Duration',
      'WITH cte AS (SELECT ... FROM ...) SELECT * FROM cte',
      'GROUP BY project_id, period',
      'CASE WHEN status="Aktif" THEN 1 ELSE 0 END',
      'JOIN sap_cost ON wbs_id = wbs_code',
      'P6 + SAP PS: schedule / budget / workforce',
      'Forecast vs Actual: kullanim orani'
    ],
    summarization: [
      'Amac | Kapsam | Bulgular | Sonuc',
      'Ana fikir -> kanit -> cikarim',
      'Uzun metin -> yapilandirilmis ozet',
      'Karar maddeleri / riskler / aksiyonlar',
      'Yonetici ozeti / detay ozet',
      'Soru -> Cevap -> Referans',
      'TLDR: temel cikarim',
      'Anahtar baslik #1, #2, #3',
      'Yapilandirilmis maddeleme (madde isaretleri)',
      'Toplanti notlari -> karar -> aksiyon',
      'Belge -> kaynaklar -> bibliyografya',
      'Veri tablosu -> ozetlenmis grafik'
    ],
    image: [
      'composition: cinematic, balanced, minimal',
      'style: technical illustration',
      'lighting: soft rim light',
      'palette: blue / orange / neutral',
      'aspect: 16:9 cinematic',
      'detail: ultra-detailed, sharp focus',
      'mood: calm, professional',
      'render: studio quality',
      'subject: ASELSAN tarzi minimal sahne',
      'lens: 50mm f/1.8',
      'background: subtle gradient',
      'pose: neutral, balanced'
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
    if (!s) return true; // varsayilan: acik
    if (typeof s[ENABLED_KEY] === 'boolean') return s[ENABLED_KEY];
    return true;
  }

  function getWrapper() {
    return document.querySelector(WRAPPER_SELECTOR);
  }

  function welcomeVisible() {
    var w = document.querySelector(WELCOME_SELECTOR);
    if (!w) return false;
    var style = w.getAttribute('style') || '';
    if (/display\s*:\s*none/i.test(style)) return false;
    // jQuery fadeOut tarafindan display:none uygulanir; ayrica visibility kontrolu:
    return w.offsetParent !== null;
  }

  function heptagonPoints(r, cx, cy) {
    cx = cx == null ? 120 : cx;
    cy = cy == null ? 120 : cy;
    var vx = [0, 0.7818315, 0.9749279, 0.4338837, -0.4338837, -0.9749279, -0.7818315];
    var vy = [-1, -0.6234898, 0.2225209, 0.9009689, 0.9009689, 0.2225209, -0.6234898];
    var pts = [];
    for (var i = 0; i < 7; i++) {
      pts.push((cx + r * vx[i]).toFixed(2) + ',' + (cy + r * vy[i]).toFixed(2));
    }
    return pts.join(' ');
  }

  function buildHeptagonSvg(radius) {
    var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 240 240');
    svg.setAttribute('aria-hidden', 'true');
    svg.setAttribute('focusable', 'false');
    var poly = document.createElementNS('http://www.w3.org/2000/svg', 'polygon');
    poly.setAttribute('points', heptagonPoints(radius));
    svg.appendChild(poly);
    return svg;
  }

  function ensureLayer(wrapper) {
    if (!wrapper) return null;
    var layer = wrapper.querySelector(':scope > .tool-bg-layer');
    if (layer) return layer;

    layer = document.createElement('div');
    layer.className = 'tool-bg-layer';
    layer.setAttribute('aria-hidden', 'true');

    var hept = document.createElement('div');
    hept.className = 'tool-bg-heptagon';
    hept.appendChild(buildHeptagonSvg(106));
    hept.appendChild(buildHeptagonSvg(80));
    hept.appendChild(buildHeptagonSvg(52));
    layer.appendChild(hept);

    var snip = document.createElement('div');
    snip.className = 'tool-bg-snippets';
    layer.appendChild(snip);

    // Layer'i ilk cocuk olarak ekle ki diger gercek bilesenler ustte kalsin
    wrapper.insertBefore(layer, wrapper.firstChild);
    return layer;
  }

  function clearSnippets(layer) {
    if (!layer) return;
    var holder = layer.querySelector('.tool-bg-snippets');
    if (holder) holder.innerHTML = '';
  }

  function renderSnippets(family) {
    var wrapper = getWrapper();
    if (!wrapper) return;
    var layer = ensureLayer(wrapper);
    if (!layer) return;
    clearSnippets(layer);

    if (!family || !TOOL_BACKGROUND_SNIPPETS[family]) return;

    var holder = layer.querySelector('.tool-bg-snippets');
    if (!holder) return;

    var pool = TOOL_BACKGROUND_SNIPPETS[family].slice();
    // Karistir
    for (var i = pool.length - 1; i > 0; i--) {
      var j = Math.floor(Math.random() * (i + 1));
      var tmp = pool[i]; pool[i] = pool[j]; pool[j] = tmp;
    }
    var count = Math.min(8, pool.length);
    for (var k = 0; k < count; k++) {
      var item = document.createElement('div');
      item.className = 'tool-bg-snippet';
      // Sol/sag kenara kacir, ortayi acik birak
      var side = (k % 2 === 0) ? 'left' : 'right';
      item.setAttribute('data-side', side);
      var top = 8 + Math.random() * 78; // %
      item.style.top = top.toFixed(1) + '%';
      // Animasyon suresi 22-42 saniye arasi rastgele
      var duration = (22 + Math.random() * 20).toFixed(1) + 's';
      // Negatif gecikme: ilk acilista hareket hazir basliyor
      var delay = (-Math.random() * 22).toFixed(1) + 's';
      item.style.animationDuration = duration;
      item.style.animationDelay = delay;
      item.textContent = pool[k];
      holder.appendChild(item);
    }
  }

  // -------------------------------------------------
  // 4. Genel API
  // -------------------------------------------------
  var currentFamily = null;

  function applyFamily(family, options) {
    options = options || {};
    var wrapper = getWrapper();
    if (!wrapper) return;

    // Onceki katmani temizle/kur
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
      return;
    }
    wrapper.classList.remove('tool-bg-disabled');

    if (!welcomeVisible()) {
      renderSnippets(family);
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
        renderSnippets(currentFamily);
      }
    } else {
      wrapper.classList.add('tool-bg-disabled');
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
  // 5. Olay baglantilari
  // -------------------------------------------------
  function bindQuickActionListener() {
    // Welcome kartlarina tiklamayi yakala: _handleQuickAction shiny'e gondermeden
    // once data-action-id'yi okuyabiliriz; ancak guvenli olmak icin pasif
    // dinleyici kullaniyoruz.
    document.addEventListener('click', function (ev) {
      var btn = ev.target && ev.target.closest && ev.target.closest('.modern-welcome-action-btn');
      if (!btn) return;
      var actionId = btn.getAttribute('data-action-id') || '';
      var fam = familyForActionId(actionId);
      if (fam) {
        // Welcome kapanmadan once aileyi belirle; renderSnippets welcome gizlenince
        // otomatik calisacak ama burada da onceden kayit edelim.
        applyFamily(fam);
      }
    }, true);
  }

  function bindWelcomeVisibilityWatch() {
    var welcome = document.querySelector(WELCOME_SELECTOR);
    if (!welcome) {
      // Welcome konteyner dinamik render edilebilir; yeniden dene
      window.setTimeout(bindWelcomeVisibilityWatch, 200);
      return;
    }

    var mo = new MutationObserver(function () {
      var wrapper = getWrapper();
      if (!wrapper) return;
      if (!currentFamily) return;
      if (welcomeVisible()) {
        clearSnippets(wrapper.querySelector(':scope > .tool-bg-layer'));
      } else {
        if (isEnabled()) {
          renderSnippets(currentFamily);
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

    // Yapilandirma anahtari acik/kapali bilgisi
    window.Shiny.addCustomMessageHandler('toggleToolBackgrounds', function (data) {
      var enabled = !!(data && data.enabled);
      setEnabled(enabled, { persist: true });
    });

    // Sunucu tarafindan tetiklenen aile degisimi (opsiyonel; quick action zaten
    // istemci tarafinda yakalaniyor)
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
    // Yeni Soylesi butonuna tiklandiginda arka plani temizle
    document.addEventListener('click', function (ev) {
      var t = ev.target;
      if (!t || !t.closest) return;
      var btn = t.closest('#new_chat_btn');
      if (btn) {
        clearBackground();
      }
    }, true);
  }

  function bindTabSwitchReset() {
    // Ana sohbet disindaki sekmelere gecince arka plani temizlemek gerekmez;
    // wrapper zaten gorunmez. Ama saved chat yuklendiginde de baska bir
    // sebepten temizlik gerekirse buradan yapilabilir.
    document.addEventListener('shiny:value', function () {
      // no-op, gelistirme icin yer tutucu
    });
  }

  // Tema degisiminde snippet'leri yeniden render et (renk degisimi icin)
  function bindThemeChangeRefresh() {
    window.addEventListener('mergen:themechange', function () {
      if (currentFamily && !welcomeVisible() && isEnabled()) {
        renderSnippets(currentFamily);
      }
    });
  }

  // -------------------------------------------------
  // 6. Genel API erisilebilir kil
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
    }
  };

  // -------------------------------------------------
  // 7. Boot
  // -------------------------------------------------
  function boot() {
    bindQuickActionListener();
    bindWelcomeVisibilityWatch();
    bindShinyToggles();
    bindNewChatReset();
    bindTabSwitchReset();
    bindThemeChangeRefresh();
    // Acilista wrapper olusana kadar bekle; saglam olmasi icin layer'i bir kez kur
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
