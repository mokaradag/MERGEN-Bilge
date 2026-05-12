// =============================================================================
// Dosya Yolu: www/js/encoding_utils.js
// Açıklama: Türkçe karakter ve emoji mojibake onarımı için ortak istemci
//           yardımcıları. Bilge Yolaç ve genel Shiny mesajları tarafından
//           paylaşılır.
// =============================================================================

(function() {
  'use strict';

  if (window.MergenEncoding && typeof window.MergenEncoding.normalizeText === 'function') {
    return;
  }

  var WIN1252_REVERSE = {};
  (function() {
    var map = [
      0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
      0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
      0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
      0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178
    ];

    for (var i = 0; i < map.length; i++) {
      WIN1252_REVERSE[map[i]] = 0x80 + i;
    }
  })();

  function unicodeToWin1252Byte(cp) {
    if (cp < 0x80) return cp;
    if (cp >= 0xA0 && cp <= 0xFF) return cp;
    if (WIN1252_REVERSE[cp] !== undefined) return WIN1252_REVERSE[cp];
    return -1;
  }

  function decodeWin1252MojibakeOnce(text) {
    if (!text || typeof text !== 'string') return text;
    if (typeof TextDecoder !== 'function') return text;

    var bytes = [];
    var hasHighByte = false;

    for (var i = 0; i < text.length; i++) {
      var cp = text.charCodeAt(i);

      // Doğru gelen emoji/surrogate çiftlerini mojibake sanma.
      if (cp >= 0xD800 && cp <= 0xDFFF) {
        return text;
      }

      var b = unicodeToWin1252Byte(cp);
      if (b < 0) return text;

      if (b >= 0x80) hasHighByte = true;
      bytes.push(b);
    }

    if (!hasHighByte) return text;

    try {
      var decoded = new TextDecoder('utf-8', { fatal: true }).decode(new Uint8Array(bytes));
      if (decoded && decoded !== text && decoded.indexOf('\uFFFD') === -1) {
        return decoded;
      }
    } catch (e) {}

    return text;
  }

  function fixMojibake(text) {
    if (!text || typeof text !== 'string') return text;

    var out = text;
    for (var i = 0; i < 2; i++) {
      var fixed = decodeWin1252MojibakeOnce(out);
      if (fixed === out) break;
      out = fixed;
    }

    return out;
  }

  // Büyük manuel emoji sözlüğü yerine algoritmik düzeltme ana yoldur.
  // Bu küçük tablo, TextDecoder bulunmayan veya kısmi bozulmuş tarayıcı
  // durumları için savunmacı yedektir.
  var FALLBACK_MOJIBAKE_MAP = {
    'Ã§': 'ç',
    'Ã‡': 'Ç',
    'Ã¶': 'ö',
    'Ã–': 'Ö',
    'Ã¼': 'ü',
    'Ãœ': 'Ü',
    'Ä±': 'ı',
    'Ä°': 'İ',
    'ÄŸ': 'ğ',
    'Äž': 'Ğ',
    'ÅŸ': 'ş',
    'Åž': 'Ş',

    'â€™': '’',
    'â€˜': '‘',
    'â€œ': '“',
    'â€“': '–',
    'â€”': '—',
    'â€¦': '…',
    'â€¢': '•',
    'Â ': ' ',
    'Â': '',

    'âœ…': '✅',
    'ğŸš€': '🚀',
    'ðŸš€': '🚀',
    'ï¸': '️'
  };

  function fixMojibakeText(text) {
    if (!text || typeof text !== 'string') return text;

    var out = fixMojibake(String(text));

    Object.keys(FALLBACK_MOJIBAKE_MAP)
      .sort(function(a, b) { return b.length - a.length; })
      .forEach(function(bad) {
        out = out.split(bad).join(FALLBACK_MOJIBAKE_MAP[bad]);
      });

    out = out
      .replace(/S\u0327/g, '\u015E')
      .replace(/s\u0327/g, '\u015F')
      .replace(/S\u0326/g, '\u015E')
      .replace(/s\u0326/g, '\u015F');

    try {
      out = out.normalize('NFC');
    } catch (e) {}

    return out;
  }

  function fixHtmlTextMojibake(html) {
    if (!html || typeof html !== 'string') return html;

    return html.replace(/>([^<]+)</g, function(match, textContent) {
      return '>' + fixMojibakeText(textContent) + '<';
    });
  }

  function normalizeText(text) {
    return fixMojibakeText(text);
  }

  function normalizePayload(value) {
    if (typeof value === 'string') {
      return normalizeText(value);
    }

    if (Array.isArray(value)) {
      return value.map(normalizePayload);
    }

    if (value && typeof value === 'object') {
      var out = {};
      Object.keys(value).forEach(function(key) {
        out[key] = normalizePayload(value[key]);
      });
      return out;
    }

    return value;
  }

  window.MergenEncoding = {
    fixMojibake: fixMojibake,
    fixMojibakeText: fixMojibakeText,
    fixHtmlTextMojibake: fixHtmlTextMojibake,
    normalizeText: normalizeText,
    normalizePayload: normalizePayload
  };

  // Eski Bilge Yolaç çağrı noktaları için geriye dönük uyumluluk.
  window.ccFixMojibake = fixMojibake;
  window.ccFixMojibakeText = fixMojibakeText;
})();