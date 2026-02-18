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

// Kaynak linki tıklamaları (Kaynakça kutusundaki dosya bağlantıları)
$(document).on('click', '.source-link', function(e) {
  e.preventDefault();
  e.stopPropagation();
  
  var $link = $(this);
  var filename = $link.data('filename') || ($link.find('.citation-file-name').text() || '').trim();
  var sourceId = $link.data('source-id') || '';
  
  console.log('[SOURCE CLICK] Dosya tıklandı:', filename);
  
  if (filename && window.Shiny) {
    Shiny.setInputValue('source_file_clicked', {
      filename: filename,
      sourceId: sourceId,
      nonce: Math.random()
    }, {priority: 'event'});
  }
});

// Satır içi alıntı numarası tıklamaları ([1], [2] gibi)
$(document).on('click', '.citation-index-btn', function(e) {
  e.preventDefault();
  e.stopPropagation();
  
  var citationNum = parseInt($(this).data('citation-num'), 10);
  if (isNaN(citationNum) || citationNum < 1) return;
  
  // Aynı mesaj baloncuğundaki Kaynakça kutusunu bul
  var $wrapper = $(this).closest('[id^="message_wrapper_"]');
  var $sourceLinks = $wrapper.find('.citation-sources-list .source-link');
  
  // Bulunamazsa sayfadaki en son Kaynakça kutusunu ara
  if ($sourceLinks.length === 0) {
    $sourceLinks = $('.citation-sources-list .source-link');
  }
  
  var $target = $sourceLinks.eq(citationNum - 1);
  if ($target.length > 0) {
    var filename = $target.data('filename') || ($target.find('.citation-file-name').text() || '').trim();
    console.log('[CITATION] Satır içi alıntı [' + citationNum + '] -> dosya:', filename);
    
    if (filename && window.Shiny) {
      Shiny.setInputValue('source_file_clicked', {
        filename: filename,
        sourceId: 'inline_citation_' + citationNum,
        nonce: Math.random()
      }, {priority: 'event'});
    }
  }
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