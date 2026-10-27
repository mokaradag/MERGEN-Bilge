// Dosya Yolu: www/js/destek_yardim_chatbot.js
// Açıklama: Yardım Merkezi yapay zeka sohbet asistanı istemci tarafı işlevleri.
//           Mesaj gönderme, mesaj ekleme, düşünme animasyonu ve kaydırma yönetimi.

// ==============================================================================
// MESAJ GÖNDERME
// ==============================================================================

/**
 * Kullanıcının mesajını Shiny'ye gönder
 * @param {string} nsPrefix - Modül namespace öneki
 */
function destekChatbotGonder(nsPrefix) {
  var input = document.getElementById(nsPrefix + 'chatbot_input');
  if (!input) return;

  var mesaj = input.value.trim();
  if (!mesaj) return;

  // Girişi temizle
  input.value = '';

  // Shiny'ye gönder
  Shiny.setInputValue(nsPrefix + 'chatbot_mesaj', mesaj, {priority: 'event'});
}

// ==============================================================================
// ZENGİN METİN BİÇİMLENDİRME
// ==============================================================================

/**
 * Bot yanıtını zengin metin formatına dönüştür (kod blokları, kalın, italik, liste)
 * @param {string} text - Ham metin
 * @returns {string} HTML çıktısı
 */
function destekChatbotFormatMessage(text) {
  // Model yanıtı veridir: kod blokları yer tutucuya alınır, kalan metnin TAMAMI
  // kaçışlanır ve biçimlendirme yalnızca kaçışlı metin üzerinde çalışır.
  var kodBloklari = [];
  // NUL yer tutucu sınırlayıcıdır; metindeki NUL atılır, yer tutucu taklit edilemez.
  var formatted = String(text == null ? '' : text).replace(/\u0000/g, '').replace(/```(\w*)\n?([\s\S]*?)```/g, function(match, lang, code) {
    var langLabel = lang ? '<span class="destek-code-lang">' + destekEscapeHtml(lang) + '</span>' : '';
    kodBloklari.push('<div class="destek-code-block">' +
      '<div class="destek-code-header">' + langLabel +
        '<button class="destek-code-copy-btn" onclick="destekChatbotCopyCode(this)" title="Kopyala">' +
          '<i class="fas fa-copy"></i>' +
        '</button>' +
      '</div>' +
      '<pre class="destek-code-pre"><code>' + destekEscapeHtml(code.trim()) + '</code></pre>' +
    '</div>');
    return '\u0000DESTEK_KOD_' + (kodBloklari.length - 1) + '\u0000';
  });

  formatted = destekEscapeHtml(formatted);

  // Satır içi kod (`...`)
  formatted = formatted.replace(/`([^`]+)`/g, '<code class="destek-inline-code">$1</code>');

  // Başlıklar (### h3, ## h2, # h1)
  formatted = formatted.replace(/^####\s+(.+)$/gm, '<h4 class="destek-chat-heading">$1</h4>');
  formatted = formatted.replace(/^###\s+(.+)$/gm, '<h4 class="destek-chat-heading">$1</h4>');
  formatted = formatted.replace(/^##\s+(.+)$/gm, '<h3 class="destek-chat-heading">$1</h3>');
  formatted = formatted.replace(/^#\s+(.+)$/gm, '<h3 class="destek-chat-heading">$1</h3>');

  // Kalın (**...**)
  formatted = formatted.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');

  // İtalik (*...*)
  formatted = formatted.replace(/(?<!\*)\*([^*]+)\*(?!\*)/g, '<em>$1</em>');

  // Madde işaretli listeler (- veya * ile başlayan satırlar)
  formatted = formatted.replace(/^[\-\*]\s+(.+)$/gm, '<li>$1</li>');
  formatted = formatted.replace(/(<li>[\s\S]*?<\/li>)/g, '<ul class="destek-chat-list">$1</ul>');
  // Bitişik <ul> etiketlerini birleştir
  formatted = formatted.replace(/<\/ul>\s*<ul class="destek-chat-list">/g, '');

  // Numaralı listeler (1. 2. vb.)
  formatted = formatted.replace(/^\d+\.\s+(.+)$/gm, '<li>$1</li>');

  // Satır sonlarını <br> olarak koru (kod blokları dışında)
  formatted = formatted.replace(/\n/g, '<br>');

  // Başlık etiketleri etrafındaki gereksiz <br> etiketlerini temizle
  formatted = formatted.replace(/<br>\s*(<h[34] class="destek-chat-heading">)/g, '$1');
  formatted = formatted.replace(/(<\/h[34]>)\s*<br>/g, '$1');

  kodBloklari.forEach(function(blok, i) {
    formatted = formatted.split('\u0000DESTEK_KOD_' + i + '\u0000').join(blok);
  });

  return formatted;
}

/**
 * HTML özel karakterlerini escape et (ortak MergenMarkdownSafety tercih edilir)
 */
function destekEscapeHtml(text) {
  var safety = window.MergenMarkdownSafety;
  if (safety && typeof safety.escapeHtml === 'function') {
    return safety.escapeHtml(text);
  }
  var div = document.createElement('div');
  div.textContent = text == null ? '' : String(text);
  return div.innerHTML;
}

/**
 * Kod bloğunu panoya kopyala
 */
function destekChatbotCopyCode(btn) {
  var codeBlock = btn.closest('.destek-code-block');
  if (!codeBlock) return;
  var code = codeBlock.querySelector('code');
  if (!code) return;

  navigator.clipboard.writeText(code.textContent).then(function() {
    var icon = btn.querySelector('i');
    if (icon) {
      icon.className = 'fas fa-check';
      setTimeout(function() { icon.className = 'fas fa-copy'; }, 1500);
    }
  });
}

// ==============================================================================
// MESAJ EKLEME
// ==============================================================================

/**
 * Sohbet alanına yeni mesaj ekle
 * @param {string} nsPrefix - Modül namespace öneki
 * @param {string} mesaj - Mesaj metni
 * @param {string} tip - Mesaj tipi: 'user' veya 'bot'
 */
function destekChatbotMesajEkle(nsPrefix, mesaj, tip) {
  var container = document.getElementById(nsPrefix + 'chatbot_messages');
  if (!container) return;

  var messageDiv = document.createElement('div');
  messageDiv.className = 'destek-chatbot-message destek-chatbot-message-' + tip;

  if (tip === 'bot') {
    // Bot mesajı: avatar + zengin metin balon
    var avatar = document.createElement('div');
    avatar.className = 'destek-chatbot-avatar';
    avatar.innerHTML = '<i class="fas fa-robot"></i>';
    messageDiv.appendChild(avatar);

    var bubble = document.createElement('div');
    bubble.className = 'destek-chatbot-bubble';
    bubble.innerHTML = destekChatbotFormatMessage(mesaj);
    messageDiv.appendChild(bubble);
  } else {
    // Kullanıcı mesajı: düz metin balon
    var bubble = document.createElement('div');
    bubble.className = 'destek-chatbot-bubble';
    bubble.textContent = mesaj;
    messageDiv.appendChild(bubble);
  }

  container.appendChild(messageDiv);

  // Otomatik kaydır
  container.scrollTop = container.scrollHeight;
}

// ==============================================================================
// SOHBET TEMİZLEME
// ==============================================================================

/**
 * Sohbet geçmişini temizle ve başlangıç mesajını yeniden ekle
 * @param {string} nsPrefix - Modül namespace öneki
 */
function destekChatbotTemizle(nsPrefix) {
  var container = document.getElementById(nsPrefix + 'chatbot_messages');
  if (!container) return;

  // Tüm mesajları kaldır
  container.innerHTML = '';

  // Başlangıç mesajını yeniden ekle
  var welcomeDiv = document.createElement('div');
  welcomeDiv.className = 'destek-chatbot-message destek-chatbot-message-bot';
  welcomeDiv.innerHTML =
    '<div class="destek-chatbot-avatar"><i class="fas fa-robot"></i></div>' +
    '<div class="destek-chatbot-bubble">' +
      'Merhaba! Ben MERGEN Bilge Yardım Asistanı. Uygulama hakkında sorularınızı yanıtlayabilirim. Nasıl yardımcı olabilirim?' +
    '</div>';
  container.appendChild(welcomeDiv);

  // Shiny'ye sohbet temizleme sinyali gönder
  Shiny.setInputValue(nsPrefix + 'chatbot_temizle', Math.random(), {priority: 'event'});
}

// ==============================================================================
// DÜŞÜNME ANİMASYONU
// ==============================================================================

/**
 * Düşünme animasyonunu göster
 * @param {string} nsPrefix - Modül namespace öneki
 */
function destekChatbotDusunmeGoster(nsPrefix) {
  var thinking = document.getElementById(nsPrefix + 'chatbot_thinking');
  if (thinking) {
    thinking.style.display = 'flex';
    // Mesaj alanını kaydır
    var container = document.getElementById(nsPrefix + 'chatbot_messages');
    if (container) {
      container.scrollTop = container.scrollHeight;
    }
  }
}

/**
 * Düşünme animasyonunu gizle
 * @param {string} nsPrefix - Modül namespace öneki
 */
function destekChatbotDusunmeGizle(nsPrefix) {
  var thinking = document.getElementById(nsPrefix + 'chatbot_thinking');
  if (thinking) {
    thinking.style.display = 'none';
  }
}