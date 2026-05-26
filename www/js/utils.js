// www/js/utils.js
// Bu dosya genel yardımcı fonksiyonları ve araçları içerir.

// Global değişkenler
window.isNearBottom = true;
const charLimit = 20000;

// Debounce (gecikmeli çalıştırma) fonksiyonu
function debounce(func, wait) {
  let timeout;
  return function executedFunction(...args) {
    const later = () => {
      clearTimeout(timeout);
      func(...args);
    };
    clearTimeout(timeout);
    timeout = setTimeout(later, wait);
  };
}

// Textarea yüksekliğini içeriğe göre ayarla
// Kaydırma çubuğu yalnızca içerik 120 piksel sınırını aştığında görünür;
// tek satır içerikte 'overflow-y: hidden' durumu korunur. Bu, Windows VM
// üzerinde tek satır mesajda bile beliren kaydırma çubuğu regresyonunu
// önler.
window.adjustTextareaHeight = function(textarea) {
  if (!textarea) return;
  textarea.style.height = 'auto';
  var newHeight = Math.min(textarea.scrollHeight, 120);
  textarea.style.height = newHeight + 'px';
  textarea.style.overflowY = textarea.scrollHeight > 120 ? 'auto' : 'hidden';
};

// Sohbet penceresini en alta kaydır
window.scrollToBottom = function(smooth) {
  if (smooth === undefined) smooth = true;
  var container = $('.chat-container');
  if (container.length) {
    container[0].scrollTo({
      top: container[0].scrollHeight,
      behavior: smooth ? 'smooth' : 'auto'
    });
    
    window.isNearBottom = true;
    $('#scroll_to_bottom_container').removeClass('show');
  }
};

// Akıllı kaydırma (Smart Scroll)
window.smartScrollToBottom = function(smooth = true) {
  const chatWrapper = document.querySelector('.chat-content-wrapper');
  const chatContainer = document.querySelector('.chat-container');
  
  if (chatWrapper) {
    chatWrapper.scrollTo({
      top: chatWrapper.scrollHeight,
      behavior: smooth ? 'smooth' : 'auto'
    });
  } else if (chatContainer) {
    chatContainer.scrollTo({
      top: chatContainer.scrollHeight,
      behavior: smooth ? 'smooth' : 'auto'
    });
  }
  
  window.isNearBottom = true;
  $('#scroll_to_bottom_container').removeClass('show');
};

// Kaydırma pozisyonunu kontrol et (Kullanıcı yukarıda mı?)
window.checkScrollPosition = function() {
  var container = $('.chat-container');
  if (container.length) {
    var scrollHeight = container[0].scrollHeight;
    var scrollTop = container.scrollTop();
    var clientHeight = container.height();
    var distanceFromBottom = scrollHeight - scrollTop - clientHeight;
    
    window.isNearBottom = distanceFromBottom < 20;
    
    if (window.isNearBottom) {
      $('#scroll_to_bottom_container').removeClass('show');
    } else {
      $('#scroll_to_bottom_container').addClass('show');
    }
  }
};

// Karakter sayacını güncelle
window.updateCharCounter = function() {
  const chatInputEl = (typeof window.getMergenChatInputElement === 'function')
    ? window.getMergenChatInputElement()
    : (
      document.getElementById('user_input') ||
      document.querySelector('.chat-input') ||
      document.querySelector('textarea[name="user_input"]')
    );
  const counterEl = document.getElementById('char_counter');
  if (!counterEl) return;

  const currentLength = chatInputEl ? (chatInputEl.value || '').length : 0;
  counterEl.textContent = `${currentLength} / ${charLimit}`;

  if (currentLength > charLimit) {
    counterEl.style.color = 'var(--danger-color)';
    counterEl.classList.remove('char-limit-exceeded');
    void counterEl.offsetWidth;
    counterEl.classList.add('char-limit-exceeded');
  } else {
    counterEl.style.color = 'var(--text-muted)';
    counterEl.classList.remove('char-limit-exceeded');
  }
};

// Metni panoya kopyala
// Base64 kopya yükünü çöz
window.decodeCopyBase64 = function(payload) {
  if (!payload) return '';

  try {
    return decodeURIComponent(escape(atob(payload)));
  } catch (e) {
    try {
      return atob(payload);
    } catch (e2) {
      return '';
    }
  }
};

// Son çare textarea kopyalama
window.copyWithHiddenTextarea = function(text) {
  return new Promise(function(resolve, reject) {
    var textarea = document.createElement('textarea');
    textarea.value = text == null ? '' : String(text);
    textarea.setAttribute('readonly', '');
    textarea.style.position = 'fixed';
    textarea.style.left = '10px';
    textarea.style.top = '10px';
    textarea.style.width = '1px';
    textarea.style.height = '1px';
    textarea.style.padding = '0';
    textarea.style.border = '0';
    textarea.style.opacity = '0';
    textarea.style.zIndex = '-1';
    textarea.style.whiteSpace = 'pre';

    document.body.appendChild(textarea);

    var oncekıSecim = document.getSelection();
    var oncekıAraliklar = [];
    if (oncekıSecim) {
      for (var i = 0; i < oncekıSecim.rangeCount; i++) {
        oncekıAraliklar.push(oncekıSecim.getRangeAt(i));
      }
    }

    textarea.focus();
    textarea.select();
    textarea.setSelectionRange(0, textarea.value.length);

    try {
      var basarili = document.execCommand('copy');

      setTimeout(function() {
        document.body.removeChild(textarea);

        if (oncekıSecim) {
          oncekıSecim.removeAllRanges();
          oncekıAraliklar.forEach(function(r) {
            oncekıSecim.addRange(r);
          });
        }

        if (basarili) {
          resolve();
        } else {
          reject(new Error('Textarea copy basarisiz'));
        }
      }, 0);
    } catch (err) {
      document.body.removeChild(textarea);

      if (oncekıSecim) {
        oncekıSecim.removeAllRanges();
        oncekıAraliklar.forEach(function(r) {
          oncekıSecim.addRange(r);
        });
      }

      reject(err);
    }
  });
};

// Metni panoya güvenli biçimde kopyala
window.writeTextToClipboard = function(text) {
  var icerik = text == null ? '' : String(text);

  if (navigator.clipboard && window.isSecureContext) {
    return navigator.clipboard.writeText(icerik);
  }

  return new Promise(function(resolve, reject) {
    var tamamlandi = false;

    function temizle() {
      document.removeEventListener('copy', onCopy, true);
    }

    function onCopy(e) {
      try {
        if (e.clipboardData) {
          e.clipboardData.setData('text/plain', icerik);
          e.preventDefault();
          tamamlandi = true;
          temizle();
          resolve();
        }
      } catch (err) {
        temizle();
        reject(err);
      }
    }

    document.addEventListener('copy', onCopy, true);

    try {
      var basarili = document.execCommand('copy');

      if (tamamlandi) {
        return;
      }

      temizle();

      if (basarili) {
        window.copyWithHiddenTextarea(icerik).then(resolve).catch(reject);
      } else {
        window.copyWithHiddenTextarea(icerik).then(resolve).catch(reject);
      }
    } catch (err) {
      temizle();
      window.copyWithHiddenTextarea(icerik).then(resolve).catch(reject);
    }
  });
};

// Mesaj düğümünden okunabilir metni çıkar
window.extractMessageTextFromNode = function(node) {
  if (!node) return '';

  var clone = node.cloneNode(true);

  clone.querySelectorAll(
    '.message-actions, .followup-suggestions-box, .tts-audio-player, .tts-audio-container, .image-actions, .image-watermark'
  ).forEach(function(el) {
    el.remove();
  });

  clone.querySelectorAll('br').forEach(function(br) {
    br.parentNode.replaceChild(document.createTextNode('\n'), br);
  });

  clone.querySelectorAll('.code-container').forEach(function(codeContainer) {
    var codeText = '';
    var cmNode = codeContainer.querySelector('.CodeMirror');
    var textAreaNode = codeContainer.querySelector('textarea.codemirror-textarea');
    var plainCodeNode = codeContainer.querySelector('code');

    if (cmNode && cmNode.CodeMirror) {
      codeText = cmNode.CodeMirror.getValue();
    } else if (textAreaNode) {
      codeText = textAreaNode.value || textAreaNode.textContent || '';
    } else if (plainCodeNode) {
      codeText = plainCodeNode.textContent || '';
    } else {
      codeText = codeContainer.textContent || '';
    }

    var pre = document.createElement('pre');
    pre.textContent = codeText;
    codeContainer.parentNode.replaceChild(pre, codeContainer);
  });

  clone.querySelectorAll('p, div, li, h1, h2, h3, h4, h5, h6, pre, tr').forEach(function(el) {
    el.appendChild(document.createTextNode('\n'));
  });

  var text = clone.textContent || '';

  return text
    .replace(/\r\n/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
};

// Mesajı mesaj kimliğine göre kopyala
window.copyRenderedMessageById = function(messageId, btn) {
  var wrapper = document.getElementById('message_wrapper_' + messageId);
  var contentNode = wrapper ? wrapper.querySelector('.message-content') : document.getElementById(messageId);

  if (!contentNode) {
    if (window.showToast) showToast('Kopyalama başarısız oldu.', 'error');
    return;
  }

  var payload = contentNode.getAttribute('data-copy-b64') || '';
  var text = payload ? window.decodeCopyBase64(payload) : '';

  if (!text) {
    text = window.extractMessageTextFromNode(contentNode);
  }

  if (!text) {
    if (window.showToast) showToast('Kopyalama başarısız oldu.', 'error');
    return;
  }

  window.writeTextToClipboard(text).then(function() {
    if (window.showToast) showToast('İçerik panoya kopyalandı.', 'success');

    if (btn) {
      var i = btn.querySelector('i');
      if (i) {
        var eskiSinif = i.className;
        i.className = 'fas fa-check';
        setTimeout(function() {
          i.className = eskiSinif;
        }, 2000);
      }
    }
  }).catch(function(err) {
    console.error('[COPY_MESSAGE] Kopyalama hatası:', err);
    if (window.showToast) showToast('Kopyalama başarısız oldu.', 'error');
  });
};

// Mesaj içeriğini panoya kopyala
window.copyMessageContent = function(btn, content) {
  window.writeTextToClipboard(content).then(function() {
    if (window.showToast) showToast('İçerik panoya kopyalandı.', 'success');
    const i = $(btn).find('i');
    const c = i.attr('class');
    i.removeClass().addClass('fas fa-check');
    setTimeout(function() {
      i.removeClass().addClass(c);
    }, 2000);
  }).catch(function(err) {
    if (window.showToast) showToast('Kopyalama başarısız oldu.', 'error');
  });
};

// Kod bloğunu panoya kopyala
window.copyCodeBlock = function(button) {
  const codeContainer = button.closest('.code-container');
  const codeContent = codeContainer.querySelector('.code-content code');
  
  if (codeContent) {
    const text = codeContent.textContent;
    window.writeTextToClipboard(text).then(function() {
      const icon = button.querySelector('i');
      icon.className = 'fas fa-check';
      if (window.showToast) showToast('Kod kopyalandı!', 'success');
      setTimeout(function() {
        icon.className = 'fas fa-copy';
      }, 2000);
    }).catch(function(err) {
      if (window.showToast) showToast('Kopyalama başarısız oldu.', 'error');
    });
  }
};

// Mesaj içeriğini panoya kopyala
window.copyMessageContent = function(btn, content) {
  window.writeTextToClipboard(content).then(function() {
    if (window.showToast) showToast('İçerik panoya kopyalandı.', 'success');
    const i = $(btn).find('i');
    const c = i.attr('class');
    i.removeClass().addClass('fas fa-check');
    setTimeout(function() {
      i.removeClass().addClass(c);
    }, 2000);
  }).catch(function(err) {
    if (window.showToast) showToast('Kopyalama başarısız oldu.', 'error');
  });
};

// Mesaj düğümünden okunabilir metni çıkar
window.extractMessageTextFromNode = function(node) {
  if (!node) return '';

  var clone = node.cloneNode(true);

  clone.querySelectorAll(
    '.message-actions, .followup-suggestions-box, .tts-audio-player, .tts-audio-container, .image-actions, .image-watermark'
  ).forEach(function(el) {
    el.remove();
  });

  clone.querySelectorAll('br').forEach(function(br) {
    br.parentNode.replaceChild(document.createTextNode('\n'), br);
  });

  clone.querySelectorAll('.code-container').forEach(function(codeContainer) {
    var codeText = '';
    var cmNode = codeContainer.querySelector('.CodeMirror');
    var textAreaNode = codeContainer.querySelector('textarea.codemirror-textarea');
    var plainCodeNode = codeContainer.querySelector('code');

    if (cmNode && cmNode.CodeMirror) {
      codeText = cmNode.CodeMirror.getValue();
    } else if (textAreaNode) {
      codeText = textAreaNode.value || textAreaNode.textContent || '';
    } else if (plainCodeNode) {
      codeText = plainCodeNode.textContent || '';
    } else {
      codeText = codeContainer.textContent || '';
    }

    var pre = document.createElement('pre');
    pre.textContent = codeText;
    codeContainer.parentNode.replaceChild(pre, codeContainer);
  });

  clone.querySelectorAll('p, div, li, h1, h2, h3, h4, h5, h6, pre, tr').forEach(function(el) {
    el.appendChild(document.createTextNode('\n'));
  });

  var text = clone.textContent || '';

  return text
    .replace(/\r\n/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
};

// Mesajı mesaj kimliğine göre kopyala
window.copyRenderedMessageById = function(messageId, btn) {
  var wrapper = document.getElementById('message_wrapper_' + messageId);
  var contentNode = wrapper ? wrapper.querySelector('.message-content') : document.getElementById(messageId);

  if (!contentNode) {
    if (window.showToast) showToast('Kopyalama başarısız oldu.', 'error');
    return;
  }

  var text = window.extractMessageTextFromNode(contentNode);

  if (!text) {
    if (window.showToast) showToast('Kopyalama başarısız oldu.', 'error');
    return;
  }

  window.writeTextToClipboard(text).then(function() {
    if (window.showToast) showToast('İçerik panoya kopyalandı.', 'success');

    if (btn) {
      var i = btn.querySelector('i');
      if (i) {
        var eskiSinif = i.className;
        i.className = 'fas fa-check';
        setTimeout(function() {
          i.className = eskiSinif;
        }, 2000);
      }
    }
  }).catch(function(err) {
    console.error('[COPY_MESSAGE] Kopyalama hatası:', err);
    if (window.showToast) showToast('Kopyalama başarısız oldu.', 'error');
  });
};

// Mesaj içeriğini panoya kopyala
window.copyMessageContent = function(btn, content) {
  window.writeTextToClipboard(content).then(function() {
    if (window.showToast) showToast('İçerik panoya kopyalandı.', 'success');
    const i = $(btn).find('i');
    const c = i.attr('class');
    i.removeClass().addClass('fas fa-check');
    setTimeout(function() {
      i.removeClass().addClass(c);
    }, 2000);
  }).catch(function(err) {
    if (window.showToast) showToast('Kopyalama başarısız oldu.', 'error');
  });
};

// Kod bloğunu panoya kopyala
window.copyCodeBlock = function(button) {
  const codeContainer = button.closest('.code-container');
  const codeContent = codeContainer.querySelector('.code-content code');
  
  if (codeContent) {
    const text = codeContent.textContent;
    window.writeTextToClipboard(text).then(function() {
      const icon = button.querySelector('i');
      icon.className = 'fas fa-check';
      if (window.showToast) showToast('Kod kopyalandı!', 'success');
      setTimeout(function() {
        icon.className = 'fas fa-copy';
      }, 2000);
    }).catch(function(err) {
      if (window.showToast) showToast('Kopyalama başarısız oldu.', 'error');
    });
  }
};