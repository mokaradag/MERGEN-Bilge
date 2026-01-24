// www/js/interaction_handlers.js
// Bu dosya kullanıcı etkileşimlerini (tıklamalar, sekme değişimleri vb.) yönetir.

$(document).ready(function() {
  // Takip sorusu seçeneğine tıklama
  $(document).on('click', '.followup-option', function(e) {
    e.preventDefault();
    const question = $(this).data('question');
    if (!question || !window.Shiny || !Shiny.setInputValue) {
      return;
    }
    Shiny.setInputValue('followup_question_clicked', {
      text: question,
      nonce: Date.now()
    }, { priority: 'event' });
  });

  // Sekme değişimi kaydı
  $(document).on('shown.bs.tab', 'a[data-toggle="tab"]', function(e) {
    const tabId = $(e.target).attr('data-value');
    if (tabId) {
      localStorage.setItem('mergen_active_tab', tabId);
    }
  });

  // Pencere odaklanması (Başlık güncelleme)
  $(window).on('focus', function() {
    if (document.title.startsWith('(1)')) {
      document.title = 'MERGEN Bilge';
    }
  });
});

// Kaynak linki tıklamaları
$(document).on('click', '.source-link', function() {
  const filename = $(this).data('filename');
  const sourceId = $(this).data('source-id');
  
  console.log('[SOURCE CLICK] User clicked:', filename);
  console.log('[SOURCE CLICK] Source ID:', sourceId);
  
  Shiny.setInputValue('source_file_clicked', {
    filename: filename,
    sourceId: sourceId,
    nonce: Math.random()
  }, {priority: 'event'});
});

// Analiz dosyası linki tıklamaları
$(document).ready(function() {
  if (!window.__analysisFileLinkBound) {
    window.__analysisFileLinkBound = true;
    
    $(document).on('click', '.analysis-file-link', function(e) {
      e.preventDefault();
      e.stopPropagation();
      
      var filepath = $(this).attr('data-filepath');
      
      if (filepath) {
        Shiny.setInputValue('analysis_file_clicked', {
          filepath: filepath,
          nonce: Math.random()
        }, {priority: 'event'});
      }
    });
  }
});