// ==============================================================================
// Dosya Yolu: www/js/streaming_markdown_safety.js
// Açıklama: Streaming markdown çıktısı için güvenli HTML kaçış yardımcıları.
// ==============================================================================

(function() {
  'use strict';

  const HTML_ESCAPE_MAP = Object.freeze({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#039;'
  });

  function asString(value) {
    if (value === null || typeof value === 'undefined') {
      return '';
    }

    return String(value);
  }

  function escapeHtml(value) {
    return asString(value).replace(/[&<>"']/g, function(character) {
      return HTML_ESCAPE_MAP[character];
    });
  }

  function normalizeLanguage(value) {
    const language = asString(value).trim().toLowerCase();

    if (/^[a-z0-9_-]{1,32}$/.test(language)) {
      return language;
    }

    return 'plaintext';
  }

  window.MergenMarkdownSafety = Object.freeze({
    escapeHtml: escapeHtml,
    normalizeLanguage: normalizeLanguage
  });
})();