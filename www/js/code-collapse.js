// www/js/code-collapse.js
// Kod bloklarını daraltma/genişletme işlevselliği

(function() {
  'use strict';

  /**
   * Kod bloğunu daralt veya genişlet
   * @param {HTMLElement} btn - Tıklanan daralt/genişlet butonu
   */
  window.toggleCodeCollapse = function(btn) {
    const container = btn.closest('.code-container');
    if (!container) return;

    const cmWrapper = container.querySelector('.CodeMirror');
    const textarea = container.querySelector('.codemirror-textarea');
    const collapseInfo = container.querySelector('.code-collapse-info');
    const icon = btn.querySelector('i');

    // Daraltma durumunu değiştir
    const isCollapsed = container.classList.toggle('code-collapsed');

    if (isCollapsed) {
      // Satır sayısını hesapla
      let lineCount = 0;
      if (cmWrapper && cmWrapper.CodeMirror) {
        lineCount = cmWrapper.CodeMirror.lineCount();
      } else if (textarea) {
        lineCount = (textarea.value || textarea.textContent || '').split('\n').length;
      }

      // Bilgi çubuğunu göster
      if (collapseInfo) {
        const lineCountSpan = collapseInfo.querySelector('.code-collapse-line-count');
        if (lineCountSpan) {
          lineCountSpan.textContent = lineCount + ' satır gizlendi';
        }
        collapseInfo.style.display = 'flex';
      }

      // CodeMirror editörünü gizle
      if (cmWrapper) cmWrapper.style.display = 'none';

      // İkon değiştir: aşağı ok (genişletme işareti)
      if (icon) icon.className = 'fas fa-chevron-down';
    } else {
      // Bilgi çubuğunu gizle
      if (collapseInfo) collapseInfo.style.display = 'none';

      // CodeMirror editörünü göster ve yenile
      if (cmWrapper) {
        cmWrapper.style.display = '';
        try {
          cmWrapper.CodeMirror.refresh();
        } catch (e) { /* sessizce geç */ }
      }

      // İkon değiştir: yukarı ok (daraltma işareti)
      if (icon) icon.className = 'fas fa-chevron-up';
    }
  };

  /**
   * Bilgi çubuğuna tıklandığında kodu genişlet
   * @param {HTMLElement} infoBar - Tıklanan bilgi çubuğu
   */
  window.expandCodeFromInfo = function(infoBar) {
    const container = infoBar.closest('.code-container');
    if (!container) return;

    const collapseBtn = container.querySelector('.code-collapse-btn');
    if (collapseBtn && container.classList.contains('code-collapsed')) {
      toggleCodeCollapse(collapseBtn);
    }
  };

})();