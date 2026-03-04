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
    // Bot mesajı: avatar + balon
    var avatar = document.createElement('div');
    avatar.className = 'destek-chatbot-avatar';
    avatar.innerHTML = '<i class="fas fa-robot"></i>';
    messageDiv.appendChild(avatar);

    var bubble = document.createElement('div');
    bubble.className = 'destek-chatbot-bubble';
    bubble.textContent = mesaj;
    messageDiv.appendChild(bubble);
  } else {
    // Kullanıcı mesajı: sadece balon
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