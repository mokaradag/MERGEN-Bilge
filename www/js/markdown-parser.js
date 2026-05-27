// ==============================================================================
// Dosya Yolu: www/js/markdown-parser.js
// Açıklama: Streaming markdown metnini güvenli, küçük HTML alt kümesine çevirir.
// ==============================================================================

(function() {
  'use strict';

  function fallbackEscapeHtml(value) {
    const map = {
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#039;'
    };

    const text = value === null || typeof value === 'undefined'
      ? ''
      : String(value);

    return text.replace(/[&<>"']/g, function(character) {
      return map[character];
    });
  }

  function fallbackNormalizeLanguage(value) {
    const language = value === null || typeof value === 'undefined'
      ? ''
      : String(value).trim().toLowerCase();

    if (/^[a-z0-9_-]{1,32}$/.test(language)) {
      return language;
    }

    return 'plaintext';
  }

  function markdownSafety() {
    if (window.MergenMarkdownSafety &&
        typeof window.MergenMarkdownSafety.escapeHtml === 'function' &&
        typeof window.MergenMarkdownSafety.normalizeLanguage === 'function') {
      return window.MergenMarkdownSafety;
    }

    return {
      escapeHtml: fallbackEscapeHtml,
      normalizeLanguage: fallbackNormalizeLanguage
    };
  }

  function normalizeNewlines(text) {
    if (text === null || typeof text === 'undefined') {
      return '';
    }

    return String(text).replace(/\r\n?/g, '\n');
  }

  function parseStreamingMarkdown(text) {
    const source = normalizeNewlines(text);

    if (!source) {
      return '';
    }

    const parts = source.split('```');
    const htmlParts = [];

    for (let index = 0; index < parts.length; index += 1) {
      const segment = parts[index];

      if (index % 2 === 0) {
        htmlParts.push(parseMarkdownWithoutCode(segment));
        continue;
      }

      const isOpenStreamingCode =
        index === parts.length - 1 &&
        parts.length % 2 === 0;

      htmlParts.push(renderCodeBlock(segment, isOpenStreamingCode));
    }

    return htmlParts.join('');
  }

  function parseCodeFenceSegment(segment) {
    const source = normalizeNewlines(segment);
    const newlineIndex = source.indexOf('\n');
    const rawLanguage = newlineIndex >= 0
      ? source.substring(0, newlineIndex).trim()
      : source.trim();

    const firstLanguageToken = rawLanguage.split(/\s+/)[0] || '';
    const language = markdownSafety().normalizeLanguage(firstLanguageToken);
    const code = newlineIndex >= 0
      ? source.substring(newlineIndex + 1)
      : '';

    return {
      language: language,
      code: code
    };
  }

  function renderCodeBlock(segment, isStreaming) {
    const safety = markdownSafety();
    const parsed = parseCodeFenceSegment(segment);
    const containerClass = isStreaming
      ? 'code-container streaming-code'
      : 'code-container';
    const preClass = isStreaming
      ? 'code-content streaming'
      : 'code-content';
    const streamingIndicator = isStreaming
      ? `
            <span class="streaming-indicator">
              <i class="fas fa-circle-notch"></i> Streaming...
            </span>`
      : '';

    return `
        <div class="${containerClass}">
          <div class="code-header">
            <span class="code-language">${safety.escapeHtml(parsed.language)}</span>${streamingIndicator}
          </div>
          <pre class="${preClass}"><code class="${safety.escapeHtml(parsed.language)}">${safety.escapeHtml(parsed.code)}</code></pre>
        </div>
      `;
  }

  function parseInlineMarkdown(text) {
    const safety = markdownSafety();
    const codeFragments = [];
    let html = safety.escapeHtml(text);

    html = html.replace(/`([^`]+)`/g, function(match, code) {
      const token = '\u0000MERGEN_INLINE_CODE_' + codeFragments.length + '\u0000';
      codeFragments.push('<code class="inline-code">' + code + '</code>');
      return token;
    });

    html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
    html = html.replace(/\*([^*]+)\*/g, '<em>$1</em>');

    codeFragments.forEach(function(fragment, index) {
      const token = '\u0000MERGEN_INLINE_CODE_' + index + '\u0000';
      html = html.split(token).join(fragment);
    });

    return html;
  }

  function parseMarkdownWithoutCode(text) {
    const source = normalizeNewlines(text);

    if (!source) {
      return '';
    }

    const lines = source.split('\n');
    const htmlParts = [];
    let listOpen = false;

    function closeList() {
      if (listOpen) {
        htmlParts.push('</ul>');
        listOpen = false;
      }
    }

    lines.forEach(function(line, index) {
      const headingMatch = line.match(/^(#{1,3})\s+(.+)$/);
      const listMatch = line.match(/^- (.+)$/);

      if (headingMatch) {
        closeList();

        const level = headingMatch[1].length;
        htmlParts.push(
          '<h' + level + '>' +
          parseInlineMarkdown(headingMatch[2]) +
          '</h' + level + '>'
        );
        return;
      }

      if (listMatch) {
        if (!listOpen) {
          htmlParts.push('<ul>');
          listOpen = true;
        }

        htmlParts.push('<li>' + parseInlineMarkdown(listMatch[1]) + '</li>');
        return;
      }

      closeList();
      htmlParts.push(parseInlineMarkdown(line));

      if (index < lines.length - 1) {
        htmlParts.push('<br>');
      }
    });

    closeList();

    return htmlParts.join('');
  }

  function escapeHtml(text) {
    return markdownSafety().escapeHtml(text);
  }

  // Geriye dönük uyumluluk: mevcut kod bu global fonksiyon adlarını kullanıyor.
  window.parseStreamingMarkdown = parseStreamingMarkdown;
  window.escapeHtml = escapeHtml;
  window.parseMarkdownWithoutCode = parseMarkdownWithoutCode;
  window.MergenStreamingMarkdown = Object.freeze({
    parseStreamingMarkdown: parseStreamingMarkdown,
    parseMarkdownWithoutCode: parseMarkdownWithoutCode,
    escapeHtml: escapeHtml
  });
})();