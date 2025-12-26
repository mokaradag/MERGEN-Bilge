// www/js/markdown-parser.js
(function() {
  'use strict';

  function parseStreamingMarkdown(text) {
    if (!text) return '';
    
    let html = text;
    
    const codeBlockMatches = text.match(/```/g);
    const isInCodeBlock = codeBlockMatches && codeBlockMatches.length % 2 === 1;
    
    if (isInCodeBlock) {
      const lastCodeBlockStart = text.lastIndexOf('```');
      const beforeCode = text.substring(0, lastCodeBlockStart);
      const codeContent = text.substring(lastCodeBlockStart);
      
      let parsedBefore = parseMarkdownWithoutCode(beforeCode);
      
      const langMatch = codeContent.match(/```(\w+)?\n?/);
      const language = langMatch && langMatch[1] ? langMatch[1] : 'plaintext';
      const codeLines = codeContent.substring(codeContent.indexOf('\n') + 1);
      
      const codeHtml = `
        <div class="code-container streaming-code">
          <div class="code-header">
            <span class="code-language">${language}</span>
            <span class="streaming-indicator">
              <i class="fas fa-circle-notch"></i> Streaming...
            </span>
          </div>
          <pre class="code-content streaming"><code class="${language}">${escapeHtml(codeLines)}</code></pre>
        </div>
      `;
      
      return parsedBefore + codeHtml;
    }
    
    html = html.replace(/```(\w+)?\n([\s\S]*?)```/g, function(match, lang, code) {
      lang = lang || 'plaintext';
      return `
        <div class="code-container">
          <div class="code-header">
            <span class="code-language">${lang}</span>
          </div>
          <pre class="code-content"><code class="${lang}">${escapeHtml(code)}</code></pre>
        </div>
      `;
    });
    
    return parseMarkdownWithoutCode(html);
  }

  function escapeHtml(text) {
    const map = {
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#039;'
    };
    return text.replace(/[&<>"']/g, m => map[m]);
  }

  function parseMarkdownWithoutCode(text) {
    if (!text) return '';
    
    let html = text;
    
    html = html.replace(/^### (.+)$/gm, '<h3>$1</h3>');
    html = html.replace(/^## (.+)$/gm, '<h2>$1</h2>');
    html = html.replace(/^# (.+)$/gm, '<h1>$1</h1>');
    html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
    html = html.replace(/\*([^*]+)\*/g, '<em>$1</em>');
    html = html.replace(/`([^`]+)`/g, '<code class="inline-code">$1</code>');
    html = html.replace(/^- (.+)$/gm, '<li>$1</li>');
    html = html.replace(/(<li>.*<\/li>)/s, '<ul>$1</ul>');
    html = html.replace(/\n/g, '<br>');
    
    return html;
  }

  // Export to window
  window.parseStreamingMarkdown = parseStreamingMarkdown;
  window.escapeHtml = escapeHtml;
  window.parseMarkdownWithoutCode = parseMarkdownWithoutCode;
})();