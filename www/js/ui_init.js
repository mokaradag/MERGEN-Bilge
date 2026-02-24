// www/js/ui_init.js
// Bu dosya arayüz başlatma işlemlerini ve tema ayarlarını içerir.

$(document).ready(function() {
  // Toast bildirim kapsayıcısının varlığını kontrol et
  if (!document.getElementById('toast-container')) {
    const tc = document.createElement('div');
    tc.id = 'toast-container';
    tc.className = 'toast-container';
    document.body.appendChild(tc);
  }

  // Material-darker temasının varlığını kontrol et, yoksa ekle
  (function ensureCMTheme(){
    const hasThemeCss = Array.from(document.styleSheets).some(ss => {
      try { return Array.from(ss.cssRules || []).some(r => (r.selectorText||'').includes('.cm-s-material-darker.CodeMirror')); }
      catch(e){ return false; }
    });
    if (!hasThemeCss) {
      const style = document.createElement('style');
      style.textContent = `
        .cm-s-material-darker.CodeMirror{background:#263238!important;color:#eceff1!important}
        .cm-s-material-darker .CodeMirror-gutters{background:#263238!important;border-right:none!important}
        .cm-s-material-darker .CodeMirror-linenumber{color:#90a4ae!important}
      `;
      document.head.appendChild(style);
      console.warn('[MERGEN] CodeMirror theme CSS not found; injected safe fallback.');
    }
  })();

  // Ayarlar açılır menüsündeki değişiklikleri izle
  const settingsObserver = new MutationObserver(function(mutations) {
    const dropdown = document.querySelector('#settings_yapilandirma_module-model_selection');
    if (dropdown && dropdown.selectize) {
      const currentValue = dropdown.selectize.getValue();
      if (currentValue) {
        $(dropdown).trigger('change');
      }
    }
  });
  
  // Yapılandırma sekmesi görünür olduğunda izlemeye başla
  $(document).on('click', '[data-value="settings_yapilandirma"]', function() {
    setTimeout(function() {
      const dropdown = document.querySelector('#settings_yapilandirma_module-model_selection');
      if (dropdown) {
        settingsObserver.observe(dropdown.parentNode, {
          childList: true,
          subtree: true
        });
      }
    }, 100);
  });

  // Karartma önleyici (Anti-dimming)
  (function antiDim() {
    if (document.getElementById('anti-dim-style')) return;
    const style = document.createElement('style');
    style.id = 'anti-dim-style';
    style.textContent = `
      body.shiny-busy::before,
      body.shiny-busy::after {
        display: none !important;
        content: '' !important;
        opacity: 0 !important;
        pointer-events: none !important;
      }
    `;
    document.head.appendChild(style);
  })();

  // Uygulama markalaması (Başlık ve Favicon)
  (function setBranding() {
    document.title = 'MERGEN Bilge';
    const linkId = 'app-favicon';
    let link = document.getElementById(linkId);
    if (!link) {
      link = document.createElement('link');
      link.id = linkId;
      link.rel = 'icon';
      link.type = 'image/png';
      document.head.appendChild(link);
    }
    link.href = 'mergen_avatar.png';
  })();
});