// Dosya Yolu: www/js/chat_search_modal.js
// Açıklama:   Sohbet içerik arama modalı - açma, kapama, arama ve sonuç gösterme işlemleri.
//             Kayıtlı söyleşilerde tam metin araması yapar.

(function() {
  'use strict';

  // Debounce yardımcısı (çift tetiklenmeyi önle)
  var _searchTimeout = null;
  var _lastTerm = '';

  // Modal HTML'ini oluştur ve DOM'a ekle
  function createSearchModal() {
    if (document.getElementById('chat-search-overlay')) return;

    var overlay = document.createElement('div');
    overlay.id = 'chat-search-overlay';
    overlay.className = 'chat-search-overlay';
    overlay.innerHTML =
      '<div class="chat-search-modal">' +
        '<div class="chat-search-header">' +
          '<i class="fas fa-search chat-search-icon"></i>' +
          '<input type="text" class="chat-search-input" placeholder="Söyleşi içeriklerinde ara..." autocomplete="off" />' +
          '<button class="chat-search-close" title="Kapat (Esc)"><i class="fas fa-times"></i></button>' +
        '</div>' +
        '<div class="chat-search-info" style="display:none;">' +
          '<span><span class="chat-search-count">0</span> sonuç bulundu</span>' +
          '<span class="chat-search-hint">Söyleşiye gitmek için tıklayın</span>' +
        '</div>' +
        '<div class="chat-search-loading">' +
          '<div class="chat-search-spinner"></div>' +
          '<p>Aranıyor...</p>' +
        '</div>' +
        '<div class="chat-search-initial">' +
          '<i class="fas fa-search"></i>' +
          '<p>Tüm söyleşi içeriklerinde arama yapın</p>' +
          '<p style="font-size:12px; color:#444;">En az 2 karakter girin</p>' +
        '</div>' +
        '<div class="chat-search-empty">' +
          '<i class="fas fa-inbox"></i>' +
          '<p>Sonuç bulunamadı</p>' +
          '<p style="font-size:12px;">Farklı anahtar kelimeler deneyin</p>' +
        '</div>' +
        '<div class="chat-search-results"></div>' +
      '</div>';

    document.body.appendChild(overlay);

    // Arka plana tıklanınca kapat
    overlay.addEventListener('click', function(e) {
      if (e.target === overlay) {
        closeSearchModal();
      }
    });

    // Modal içi olaylar
    var closeBtn = overlay.querySelector('.chat-search-close');
    closeBtn.addEventListener('click', closeSearchModal);

    var searchInput = overlay.querySelector('.chat-search-input');
    searchInput.addEventListener('input', function() {
      var term = searchInput.value.trim();
      handleSearchInput(term);
    });

    // Enter tuşuyla anında arama
    searchInput.addEventListener('keydown', function(e) {
      if (e.key === 'Escape') {
        closeSearchModal();
      }
    });
  }

  // Arama girişini işle (debounce ile)
  function handleSearchInput(term) {
    // Aynı terim için tekrar arama yapma
    if (term === _lastTerm) return;
    _lastTerm = term;

    clearTimeout(_searchTimeout);

    var overlay = document.getElementById('chat-search-overlay');
    if (!overlay) return;

    var loading = overlay.querySelector('.chat-search-loading');
    var initial = overlay.querySelector('.chat-search-initial');
    var empty = overlay.querySelector('.chat-search-empty');
    var results = overlay.querySelector('.chat-search-results');
    var info = overlay.querySelector('.chat-search-info');

    // Kısa terimler için başlangıç durumuna dön
    if (term.length < 2) {
      loading.classList.remove('active');
      empty.classList.remove('active');
      results.innerHTML = '';
      info.style.display = 'none';
      initial.classList.remove('hidden');
      return;
    }

    // Yükleniyor göster
    initial.classList.add('hidden');
    empty.classList.remove('active');
    results.innerHTML = '';
    info.style.display = 'none';
    loading.classList.add('active');

    // Debounce: 400ms bekle
    _searchTimeout = setTimeout(function() {
      if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
        Shiny.setInputValue('chat_search_query', {
          term: term,
          nonce: Date.now()
        }, { priority: 'event' });
      }
    }, 400);
  }

  // Modal'ı aç
  function openSearchModal() {
    createSearchModal();
    var overlay = document.getElementById('chat-search-overlay');
    if (!overlay) return;

    overlay.classList.add('active');
    _lastTerm = '';

    // Durumları sıfırla
    var loading = overlay.querySelector('.chat-search-loading');
    var initial = overlay.querySelector('.chat-search-initial');
    var empty = overlay.querySelector('.chat-search-empty');
    var results = overlay.querySelector('.chat-search-results');
    var info = overlay.querySelector('.chat-search-info');
    var input = overlay.querySelector('.chat-search-input');

    loading.classList.remove('active');
    empty.classList.remove('active');
    initial.classList.remove('hidden');
    results.innerHTML = '';
    info.style.display = 'none';
    input.value = '';

    // Arama kutusuna odaklan
    setTimeout(function() {
      input.focus();
    }, 100);
  }

  // Modal'ı kapat
  function closeSearchModal() {
    var overlay = document.getElementById('chat-search-overlay');
    if (overlay) {
      overlay.classList.remove('active');
    }
    _lastTerm = '';
    clearTimeout(_searchTimeout);
  }

  // Metindeki arama terimini vurgula
  function highlightTerm(text, term) {
    if (!text || !term) return escapeHtml(text || '');
    var escaped = escapeHtml(text);
    var escapedTerm = escapeRegExp(term);
    var regex = new RegExp('(' + escapedTerm + ')', 'gi');
    return escaped.replace(regex, '<span class="chat-search-highlight">$1</span>');
  }

  // HTML özel karakterlerini güvenli hale getir
  function escapeHtml(str) {
    var div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
  }

  // Regex özel karakterlerini güvenli hale getir
  function escapeRegExp(str) {
    return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  // Sunucudan gelen arama sonuçlarını işle
  function handleSearchResults(data) {
    var overlay = document.getElementById('chat-search-overlay');
    if (!overlay || !overlay.classList.contains('active')) return;

    var loading = overlay.querySelector('.chat-search-loading');
    var empty = overlay.querySelector('.chat-search-empty');
    var results = overlay.querySelector('.chat-search-results');
    var info = overlay.querySelector('.chat-search-info');
    var initial = overlay.querySelector('.chat-search-initial');
    var countEl = overlay.querySelector('.chat-search-count');

    loading.classList.remove('active');
    initial.classList.add('hidden');

    var term = data.term || '';
    var items = data.results || [];
    var totalCount = data.count || 0;

    if (items.length === 0) {
      empty.classList.add('active');
      results.innerHTML = '';
      info.style.display = 'none';
      return;
    }

    empty.classList.remove('active');
    countEl.textContent = totalCount;
    info.style.display = 'flex';

    // Sonuç kartlarını oluştur
    var html = '';
    items.forEach(function(item) {
      html += '<div class="chat-search-result-card" data-chat-id="' + escapeHtml(item.chat_id) + '">';
      html += '<div class="chat-search-result-header">';
      html += '<span class="chat-search-result-title">' + escapeHtml(item.chat_title || 'Söyleşi') + '</span>';
      html += '<div class="chat-search-result-meta">';
      html += '<span class="chat-search-match-badge">' + item.match_count + ' eşleşme</span>';
      html += '</div>';
      html += '</div>';
      html += '<div class="chat-search-snippets">';

      if (item.snippets && item.snippets.length > 0) {
        item.snippets.forEach(function(snippet) {
          var labelClass = snippet.type === 'user' ? 'user-label' : 'ai-label';
          var labelText = snippet.type === 'user' ? 'Soru' : 'Yanıt';
          html += '<div class="chat-search-snippet">';
          html += '<span class="chat-search-snippet-label ' + labelClass + '">' + labelText + '</span>';
          // Zaman damgası varsa göster
          if (snippet.timestamp) {
            html += '<span class="chat-search-snippet-timestamp">' + escapeHtml(snippet.timestamp) + '</span> ';
          }
          html += highlightTerm(snippet.snippet, term);
          html += '</div>';
        });
      }

      html += '</div>';
      html += '</div>';
    });

    results.innerHTML = html;

    // Sonuç kartlarına tıklama olayı ekle
    results.querySelectorAll('.chat-search-result-card').forEach(function(card) {
      card.addEventListener('click', function() {
        var chatId = card.getAttribute('data-chat-id');
        if (chatId && typeof Shiny !== 'undefined' && Shiny.setInputValue) {
          Shiny.setInputValue('chat_search_load_chat', chatId, { priority: 'event' });
          closeSearchModal();
        }
      });
    });
  }

  // Shiny mesaj handler'ı kaydet
  $(document).ready(function() {
    // Modal'ı oluştur (sayfa yüklendiğinde)
    createSearchModal();

    // Sunucudan gelen arama sonuçlarını dinle
    if (typeof Shiny !== 'undefined') {
      Shiny.addCustomMessageHandler('chatSearchResults', handleSearchResults);
    }
  });

  // Global erişim için fonksiyonları dışa aktar
  window.openChatSearchModal = openSearchModal;
  window.closeChatSearchModal = closeSearchModal;
})();