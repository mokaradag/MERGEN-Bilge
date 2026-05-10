// www/js/file_handlers.js
// Bu dosya dosya yükleme, sürükle-bırak ve indirme işlemlerini içerir.

$(document).ready(function() {
  // Değişkenler
  let dragCounterChat = 0;
  let dragCounterFM = 0;
  let chatFileTimeout = null;

  function getChatWrapper() {
    return $('#chat_input_wrapper');
  }

  // --- Sohbet Penceresi Dosya Sürükle-Bırak İşlemleri ---
  
  $(document).on('dragenter', '#chat_input_wrapper, #chat_input_wrapper *', function (e) {
    e.preventDefault(); e.stopPropagation();
    dragCounterChat++;
    if (dragCounterChat === 1) { $('#drop_zone').removeClass('hidden'); getChatWrapper().addClass('dragging'); }
  });
  
  $(document).on('dragleave', '#chat_input_wrapper, #chat_input_wrapper *', function (e) {
    e.preventDefault(); e.stopPropagation();
    dragCounterChat--;
    if (dragCounterChat <= 0) { dragCounterChat = 0; $('#drop_zone').addClass('hidden'); getChatWrapper().removeClass('dragging'); }
  });
  
  $(document).on('dragover', '#chat_input_wrapper, #chat_input_wrapper *', function (e) { 
    e.preventDefault(); 
    e.stopPropagation(); 
  });
  
  $(document).on('drop', '#chat_input_wrapper, #drop_zone', function (e) {
    e.preventDefault(); e.stopPropagation();
    dragCounterChat = 0; 
    $('#drop_zone').addClass('hidden'); 
    getChatWrapper().removeClass('dragging');

    const files = (e.originalEvent && e.originalEvent.dataTransfer && e.originalEvent.dataTransfer.files) ? 
                  e.originalEvent.dataTransfer.files : null;
    if (!files || !files.length) return;

    // Sadece tek dosya kontrolü
    if (files.length > 1) {
      if (window.showToast) showToast('Sadece tek dosya yüklenebilir. İlk dosya işleniyor.', 'warning');
    }

    if (chatFileTimeout) {
      clearTimeout(chatFileTimeout);
    }
    
    chatFileTimeout = setTimeout(() => {
      const input = document.getElementById('file_upload');
      if (input) {
        const dt = new DataTransfer();
        dt.items.add(files[0]);
        input.files = dt.files;
        
        const changeEvent = new Event('change', { bubbles: true });
        input.dispatchEvent(changeEvent);
      } else {
        if (window.showToast) showToast('Dosya yükleme hatası. Lütfen tekrar deneyin.', 'error');
      }
    }, 100);
  });
  
  // Dosya butonuna tıklama işlemi
  $(document).on('click', '#file_btn_container', function(e) {
    e.preventDefault();
    e.stopPropagation();
    const fileInput = document.getElementById('file_upload');
    if (fileInput) {
      fileInput.click();
    }
  });

  // --- Dosya Yöneticisi Sürükle-Bırak İşlemleri ---
  
  function getFileManagerDropZone() {
    return $('#file_manager_module-main_drop_zone');
  }

  $(document).on('dragenter', '#file_manager_module-main_drop_zone, #file_manager_module-main_drop_zone *', function (e) {
    e.preventDefault(); e.stopPropagation();
    dragCounterFM++;
    if (dragCounterFM === 1) getFileManagerDropZone().addClass('dragging');
  });
  $(document).on('dragleave', '#file_manager_module-main_drop_zone, #file_manager_module-main_drop_zone *', function (e) {
    e.preventDefault(); e.stopPropagation();
    dragCounterFM--;
    if (dragCounterFM <= 0) { dragCounterFM = 0; getFileManagerDropZone().removeClass('dragging'); }
  });
  $(document).on('dragover', '#file_manager_module-main_drop_zone, #file_manager_module-main_drop_zone *', function (e) { e.preventDefault(); e.stopPropagation(); });
  
  $(document).on('drop', '#file_manager_module-main_drop_zone', function (e) {
    e.preventDefault(); e.stopPropagation();
    dragCounterFM = 0; getFileManagerDropZone().removeClass('dragging');
  
    const files = (e.originalEvent && e.originalEvent.dataTransfer && e.originalEvent.dataTransfer.files)
                    ? e.originalEvent.dataTransfer.files : null;
    if (!files || !files.length) return;
  
    try {
      const input = document.getElementById('file_manager_module-bulk_upload');
      if (!input) return;
      const dt = new DataTransfer();
  
      input.value = '';
  
      for (let i = 0; i < files.length; i++) dt.items.add(files[i]);
      input.files = dt.files;
      input.dispatchEvent(new Event('change', { bubbles: true }));
    } catch (err) {
      console.error('File Manager DnD assignment failed:', err);
      if (window.showToast) showToast('Dosya bırakma başarısız oldu.', 'error');
    }
  });

  // --- Toplu Yükleme İşlemleri ---

  function updateBulkUploadProgressBar() {
    const $progress = $('#bulk_upload_div .shiny-file-input-progress');
    if (!$progress.length) return;

    const $bar = $progress.find('.progress-bar');
    const $label = $progress.find('span');

    if ($label.length) {
      const text = ($label.text() || '').trim();
      if (/upload complete/i.test(text)) {
        $label.text('Aktarım için hazır');
        $bar.addClass('upload-complete');
      } else if (/uploading/i.test(text)) {
        $label.text('Yükleniyor...');
        $bar.removeClass('upload-complete');
      } else {
        $bar.removeClass('upload-complete');
      }
    }
  }

  function initBulkUploadProgressObserver() {
    const container = document.querySelector('#bulk_upload_div');
    if (!container || container._bulkProgressObserver) return;

    const observer = new MutationObserver(() => updateBulkUploadProgressBar());
    observer.observe(container, { childList: true, subtree: true, characterData: true });
    container._bulkProgressObserver = observer;
    updateBulkUploadProgressBar();
  }

  initBulkUploadProgressObserver();

  $(document).on('change', '#file_manager_module-bulk_upload', function () {
    const hasFiles = this.files && this.files.length > 0;
    const $grp = $(this).closest('.input-group');
    const $txt = $grp.find('.form-control');
    if (hasFiles) {
      $txt.val(Array.from(this.files).map(f => f.name).join(', '));
    } else {
      $txt.val('').attr('placeholder', 'Henüz dosya seçilmedi');
    }
    const $progress = $('#bulk_upload_div .shiny-file-input-progress');
    if (hasFiles && $progress.length) {
      $progress.show();
      $progress.find('.progress-bar').removeClass('upload-complete');
    }
    const $container = $('#file_manager_module-execute_bulk_upload_container');

    if (hasFiles) {
      $container.empty();
      
      const $buttonWrapper = $('<div></div>').css({
        'display': 'flex',
        'justify-content': 'center',
        'gap': '10px',
        'margin-top': '20px'
      });
      
      const $uploadBtn = $('<button></button>')
        .attr('id', 'file_manager_module-execute_bulk_upload')
        .addClass('btn btn-modern btn-success')
        .html('<i class="fas fa-upload"></i> Dosyaları Yükle');
      
      const $clearBtn = $('<button></button>')
        .attr('id', 'file_manager_module-clear_pending_files')
        .addClass('btn btn-modern btn-warning')
        .html('<i class="fas fa-times"></i> Dosyaları Temizle');
      
      $buttonWrapper.append($uploadBtn).append($clearBtn);
      $container.append($buttonWrapper).show();
      
      $uploadBtn.off('click').on('click', function(e) {
        e.preventDefault();
        Shiny.setInputValue('file_manager_module-execute_bulk_upload', Math.random(), {priority: 'event'});
          const $input = $('#file_manager_module-bulk_upload');
          if ($input.length) {
            const $grp = $input.closest('.input-group');
            $input.val('');
            $grp.find('.form-control').val('').attr('placeholder', 'Henüz dosya seçilmedi');
           }
          const $progress = $('#bulk_upload_div .shiny-file-input-progress');
          $progress.hide();
          $progress.find('.progress-bar').removeClass('upload-complete');
          $('#bulk_upload_div .progress').hide();
          $progress.find('.progress-bar').css('width', '0%');
          $progress.find('.progress-bar').text('');
          $progress.find('span').text('');
      });

      $clearBtn.off('click').on('click', function(e) {
        e.preventDefault();
        $('#file_manager_module-bulk_upload').val('');
        $('#file_manager_module-bulk_upload').trigger('change');
        $container.hide().empty();
        if (window.showToast) showToast('Dosya seçimi temizlendi', 'info');
        const $progress = $('#bulk_upload_div .shiny-file-input-progress');
        $progress.hide();
        $progress.find('.progress-bar').removeClass('upload-complete');
        $('#bulk_upload_div .progress').hide();
        $progress.find('.progress-bar').css('width', '0%');
        $progress.find('.progress-bar').text('');
        $progress.find('span').text('');
      });

    } else {
      $container.hide().empty();
    }
  });

  // --- Dosya Aksiyonları ve İndirme ---

  $(document).on('click', '.js-file-action', function (e) {
    e.preventDefault();
    e.stopPropagation();
    const action = $(this).data('action');
    const fileId = $(this).data('file-id') || $(this).data('id') || $(this).attr('data-file-id');
    if (action && fileId) {
      Shiny.setInputValue(
        "file_manager_module-file_action",
        { action: action, id: String(fileId), nonce: Math.random() },
        { priority: 'event' }
      );
    }
  });

  $(document).on('click', '.file-download, .js-download-btn', function(e) {
    e.preventDefault();
    e.stopPropagation();
  
    const $btn = $(this);
    const fileId = $btn.attr('data-download-id') ||
                   $btn.closest('.file-actions').find('[data-file-id]').first().data('file-id');
    if (!fileId) return;
  
    const linkId = 'file_manager_module-download_' + fileId;
    const linkEl = document.getElementById(linkId);
    if (!linkEl) {
      if (window.showToast) showToast('İndir linki hazırlanamadı.', 'error');
      return;
    }
  
    const tryClick = (retries = 15) => {
      const href = linkEl.getAttribute('href');
      if (href && href.trim() !== '' && href !== '#') {
        linkEl.click();
      } else if (retries > 0) {
        setTimeout(() => tryClick(retries - 1), 100);
      } else {
        if (window.showToast) showToast('İndirme hazırlanamadı. Lütfen tekrar deneyin.', 'error');
      }
    };
  
    tryClick();
  });
  
  $(document).on('click', 'a.shiny-download-link', function(e) {
    const href = $(this).attr('href');
    if (!href || href.trim() === '' || href === '#') {
      e.preventDefault();
      e.stopPropagation();
      return false;
    }
  });
  
  // Varsayılan sürükle-bırak davranışını engelle
  $(document).on('dragover dragenter', function(e) {
    e.preventDefault();
    e.stopPropagation();
  });
  
  $(document).on('drop', function(e) {
    e.preventDefault();
    e.stopPropagation();
  });
  
  // Dosya bırakma (Issue 8 Fix - Debounced)
  window.handleFileDrop = function(files) {
    if (window.fileUploadTimeout) {
      clearTimeout(window.fileUploadTimeout);
    }
    
    window.fileUploadTimeout = setTimeout(() => {
      const fileList = Array.from(files);
      if (fileList.length > 0) {
        Shiny.setInputValue('files_dropped', fileList.map(f => ({
          name: f.name,
          size: f.size,
          type: f.type
        })), {priority: 'event'});
      }
    }, 100);
  }
});