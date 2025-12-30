// www/js/shiny_message_handlers.js
// Bu dosya Shiny sunucusundan gelen özel mesajları işleyen fonksiyonları içerir.

$(document).ready(function() {
    // Takip sorularını oluştur ve göster
    function renderFollowupSuggestions(data) {
        if (!data || !data.id) return;
        const questions = (Array.isArray(data.followups) ? data.followups : [])
          .map(q => (q ? String(q).trim() : ''))
          .filter(q => q.length);

        const wrapper = document.getElementById('message_wrapper_' + data.id);
        if (!wrapper) return;
        const host = wrapper.querySelector('.ai-message') || wrapper;
        let box = document.getElementById('followup_container_' + data.id);

        if (!questions.length) {
          if (box && box.parentNode) {
            box.parentNode.removeChild(box);
          }
          return;
        }

        if (!box) {
          box = document.createElement('div');
          box.id = 'followup_container_' + data.id;
          host.appendChild(box);
        }

        box.className = 'followup-suggestions-box';
        box.classList.toggle('pending', !!data.pending);
        box.dataset.hasItems = 'true';
        box.innerHTML = '';

        const title = document.createElement('div');
        title.className = 'followup-suggestions-title';
        const icon = document.createElement('i');
        icon.className = 'fas fa-lightbulb';
        const label = document.createElement('span');
        label.textContent = 'Önerilen Takip Soruları';
        title.appendChild(icon);
        title.appendChild(label);

        const list = document.createElement('div');
        list.className = 'followup-suggestions-list';

        questions.forEach(question => {
          const btn = document.createElement('button');
          btn.type = 'button';
          btn.className = 'followup-option';
          btn.dataset.question = question;

          const textSpan = document.createElement('span');
          textSpan.textContent = question;
          const arrow = document.createElement('i');
          arrow.className = 'fas fa-arrow-up-right-from-square';

          btn.appendChild(textSpan);
          btn.appendChild(arrow);
          list.appendChild(btn);
        });

        box.appendChild(title);
        box.appendChild(list);

        const shouldAutoScroll = (typeof window === 'undefined') ? false :
          (typeof window.isNearBottom === 'undefined' || window.isNearBottom === true);
        if (shouldAutoScroll) {
          setTimeout(() => {
            if (typeof window.smartScrollToBottom === 'function') {
              window.smartScrollToBottom(true);
            } else if (typeof window.scrollToBottom === 'function') {
              window.scrollToBottom(true);
            }
          }, 20);
        }
    }

    // Beğen/Beğenme butonu renk işleyicileri
    Shiny.addCustomMessageHandler('updateFeedback', function(data) {
        const messageId = data.messageId;
        const action = data.action;
    
        if (action === 'like') {
          $(`#like_${messageId}`).addClass('active liked');
          $(`#dislike_${messageId}`).removeClass('active disliked');
        } else if (action === 'dislike') {
          $(`#dislike_${messageId}`).addClass('active disliked');
          $(`#like_${messageId}`).removeClass('active liked');
        } else if (action === 'remove_like') {
          $(`#like_${messageId}`).removeClass('active liked');
        } else if (action === 'remove_dislike') {
          $(`#dislike_${messageId}`).removeClass('active disliked');
        }
    });

    // Geniş ekran geçişi (Widescreen Toggle)
	Shiny.addCustomMessageHandler('toggleWidescreen', function(data) {
		const enabled = !!data.enabled;
		if (typeof applyWidescreen === 'function') {
			applyWidescreen(enabled);
		}
		try {
		  const raw = localStorage.getItem('mergen_settings');
		  const settings = raw ? JSON.parse(raw) : {};
		  settings.enable_widescreen = enabled;
		  localStorage.setItem('mergen_settings', JSON.stringify(settings));
		} catch (e) {}
		
		setTimeout(function() {
			if (typeof applyWidescreen === 'function') {
				applyWidescreen(enabled);
			}
		}, 100);
	});

    // Tüm zaman damgalarını görünür yap/gizle
    Shiny.addCustomMessageHandler('toggleAllTimestamps', function(data) {
        if (data.enabled) {
          $('.message-time').removeClass('hidden');
        } else {
          $('.message-time').addClass('hidden');
        }
    });

    // Yazı boyutunu güncelle
    Shiny.addCustomMessageHandler('updateFontSize', function(data) {
        $('.message-content').removeClass('font-small font-medium font-large font-xlarge');
        $('.message-content').addClass('font-' + data.size);
    });

    // Bildirim (Toast) göster
    Shiny.addCustomMessageHandler('showToast', function(data) { 
        if (window.showToast) showToast(data.message, data.type, data.duration); 
    });

    // Ayarları tarayıcı hafızasına kaydet
    Shiny.addCustomMessageHandler('saveSettings', function(settings) { 
        try { 
            localStorage.setItem('mergen_settings', JSON.stringify(settings)); 
        } catch (e) { 
            console.error('Ayarlar kaydedilemedi:', e); 
        } 
    });

    // Ayarları tarayıcı hafızasından yükle
    Shiny.addCustomMessageHandler('loadSettings', function(data) { 
        try { 
            const s = localStorage.getItem('mergen_settings'); 
            if (s) { 
                Shiny.setInputValue("settings_module-loaded_settings", JSON.parse(s), { priority: 'event' }); 
            } 
        } catch (e) { 
            console.error('Ayarlar yüklenemedi:', e); 
        } 
    });

    // Ayarları temizle
    Shiny.addCustomMessageHandler('clearSettings', function(data) { 
        localStorage.removeItem('mergen_settings'); 
    });

    // Gönder butonunu aktif/pasif yap
    Shiny.addCustomMessageHandler('toggleSendButton', function(message) { 
        $('#send_stop_btn').prop('disabled', message.disable); 
    });

    // Takip önerilerini güncelle
    Shiny.addCustomMessageHandler('updateFollowupSuggestions', renderFollowupSuggestions);

    // Ayarları güncellemeye zorla
    Shiny.addCustomMessageHandler('forceSettingsUpdate', function(data) {
        const dropdown = document.querySelector('#settings_module-model_selection');
        if (dropdown) {
          dropdown.value = data.model;
          dropdown.dispatchEvent(new Event('change'));
        }
    });

    // Model seçim kutusunu güncelle
    Shiny.addCustomMessageHandler('updateModelDropdown', function(data) {
        const modelDropdown = document.querySelector('#settings_module-model_selection');
        if (modelDropdown) {
          if (modelDropdown.selectize) {
            modelDropdown.selectize.setValue(data.model, true);
          } else {
            modelDropdown.value = data.model;
          }
        }
    });

    // Toplu yükleme başlığını sıfırla
    Shiny.addCustomMessageHandler('resetBulkUploadCaption', function () {
        const $input = $('#file_manager_module-bulk_upload');
        if (!$input.length) return;
        $input.val('');
        const $grp = $input.closest('.input-group');
        $grp.find('.form-control').val('').attr('placeholder', 'Henüz dosya seçilmedi');
        const $progress = $('#bulk_upload_div .shiny-file-input-progress');
        $progress.hide();
        $progress.find('.progress-bar').removeClass('upload-complete');
    });

    // Sağlık zaman damgasını güncelle
    Shiny.addCustomMessageHandler('updateHealthTimestamp', function(data) {
      const elem = document.getElementById('last_update_time');
      if (elem) {
        elem.textContent = 'Son Güncelleme: ' + data.time;
      }
    });

    // Yönetici zaman damgasını güncelle
    Shiny.addCustomMessageHandler('updateAdminTimestamp', function(data) {
        var el = document.getElementById(data.id);
        if (el) {
          el.textContent = 'Son Güncelleme: ' + data.time;
        }
    });
});