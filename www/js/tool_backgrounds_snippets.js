// ============================================================
// Başlık: Araç Bağlamlı Sohbet Arka Plan Snippet Kataloğu
// Dosya: www/js/tool_backgrounds_snippets.js
// Açıklama: tool_backgrounds.js içindeki snippet filtreleri ve yedek
//           snippet havuzunu ayrı tutar. Davranış değiştirmez;
//           yalnızca fonksiyon yoğunluğunu azaltır.
// ============================================================

(function () {
  'use strict';

  function _isCodeOnly(item) {
    return !!item && !!item.lang && !item.tag &&
           item.lang !== 'JQL' && item.lang !== 'ABAP';
  }

  var FAMILY_FILTERS = {
    coding: function (i) { return _isCodeOnly(i); },
    process: function (i) {
      return i.tag === 'Proje Yönetimi' || i.tag === 'Primavera P6' ||
             i.tag === 'Veri Analizi'   || i.tag === 'MERGEN Bilge';
    },
    app_expert: function (i) {
      return i.tag === 'Primavera P6' || i.tag === 'Jira' ||
             i.tag === 'SAP' || i.lang === 'JQL' || i.lang === 'ABAP' ||
             i.tag === 'MERGEN Bilge';
    },
    sql_analysis: function (i) {
      return i.lang === 'SQL' || i.tag === 'Veri Analizi' ||
             i.tag === 'Proje Yönetimi' || i.tag === 'Primavera P6';
    },
    mcp_excel: function (i) {
      return i.lang === 'SQL' || i.tag === 'SAP' ||
             i.tag === 'Veri Analizi' || i.tag === 'MERGEN Bilge';
    },
    summarization: function (i) {
      return i.tag === 'MERGEN Bilge' || i.tag === 'Veri Analizi' ||
             i.tag === 'Sinyal İşleme' || i.tag === 'Radar Sistemleri' ||
             i.tag === 'Proje Yönetimi';
    },
    image: function (i) {
      return i.tag === 'MERGEN Bilge' || i.tag === 'Radar Sistemleri' ||
             i.tag === 'Sinyal İşleme' || i.tag === 'Elektronik Harp';
    }
  };

  var FALLBACK_SNIPPETS = {
    coding: [
      { lang: 'JavaScript', lines: [
        'function analyze(data) {',
        '  return summarize(data);',
        '}'
      ] },
      { lang: 'SQL', lines: [
        'SELECT id, status FROM tasks',
        'WHERE active = 1;'
      ] },
      { lang: 'Python', lines: [
        'def predict(x):',
        '    return model(x)'
      ] }
    ],
    process: [
      { tag: 'Proje Yönetimi', lines: [
        'Sürec sahibi -> sorumlu',
        'Onay akışı: hazırlayan -> kontrol -> onay'
      ] }
    ],
    app_expert: [
      { tag: 'Primavera P6', lines: ['Activity ID -> WBS -> Baseline'] }
    ],
    mcp_excel: [
      { tag: 'Veri Analizi', lines: [
        'Pivot: Bölge x Ay x Tutar',
        'Slicer ile filtrele'
      ] }
    ],
    sql_analysis: [
      { lang: 'SQL', lines: [
        'SELECT project_id, SUM(cost)',
        'FROM portfolio',
        'GROUP BY project_id'
      ] }
    ],
    summarization: [
      { tag: 'MERGEN Bilge', lines: [
        'Amaç | Kapsam | Bulgular | Sonuç'
      ] }
    ],
    image: [
      { tag: 'MERGEN Bilge', lines: [
        'Kurumsal tarz, dengeli kompozisyon'
      ] }
    ]
  };

  window.MergenToolBackgroundSnippetCatalog = {
    FAMILY_FILTERS: FAMILY_FILTERS,
    FALLBACK_SNIPPETS: FALLBACK_SNIPPETS
  };
})();