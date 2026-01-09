// www/js/welcome_greeting.js
// Karşılama ekranı için dinamik yazı animasyonu

window.WelcomeGreeting = (function() {
  const AI_MESSAGES = [
    "Sistemler çevrimiçi. Size nasıl yardımcı olabilirim?",
    "Veri akışı optimize edildi. Görev bekliyorum.",
    "Merhaba. Bugün hangi problemi çözüyoruz?",
    "Yaratıcılığınızı genişletmek için hazırım.",
    "Kod tabanı analizi için beklemedeyim.",
    "Güvenlik protokolleri güncel. Sorgu bekleniyor.",
    "Büyük veri setleri işlenmeye hazır.",
    "Algoritmik verimlilik en üst seviyede.",
    "Sinir ağları senkronize edildi. Başlayalım.",
    "Derin öğrenme modelleri aktif. Ne tasarlıyoruz?",
    "Hesaplama kapasitesi %100. Emirlerinizi bekliyorum.",
    "Mantık çekirdekleri hazır. Veri girişi yapın.",
    "Dijital asistanınız göreve hazır.",
    "İşlem gücü rezerve edildi. Komut verin.",
    "Sentezleme modülü aktif. Fikirlerinizi bekliyorum.",
    "Veri desenleri taranıyor. Hazırım."
  ];

  let textElement = null;
  let currentText = '';
  let currentIndex = 0;
  let isDeleting = false;
  let delta = 50;
  let intervalId = null;
  let indicesQueue = [];
  let pointer = 0;

  function shuffleIndices() {
    const arr = Array.from({ length: AI_MESSAGES.length }, (_, i) => i);
    for (let i = arr.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [arr[i], arr[j]] = [arr[j], arr[i]];
    }
    return arr;
  }

  function init(element) {
    textElement = element;
    if (!textElement) return;
    
    indicesQueue = shuffleIndices();
    pointer = 0;
    currentIndex = indicesQueue[0];
    
    tick();
    intervalId = setInterval(tick, delta);
  }

  function tick() {
    const fullText = AI_MESSAGES[currentIndex];
    let updatedText = isDeleting
      ? fullText.substring(0, currentText.length - 1)
      : fullText.substring(0, currentText.length + 1);

    currentText = updatedText;
    
    if (textElement) {
      textElement.textContent = currentText;
    }

    if (isDeleting) {
      delta = 30;
    }

    if (!isDeleting && updatedText === fullText) {
      isDeleting = true;
      delta = 8000;
    } else if (isDeleting && updatedText === '') {
      isDeleting = false;
      
      pointer++;
      if (pointer >= indicesQueue.length) {
        const lastUsedIndex = indicesQueue[indicesQueue.length - 1];
        let newDeck = shuffleIndices();
        
        if (newDeck[0] === lastUsedIndex && AI_MESSAGES.length > 1) {
          [newDeck[0], newDeck[newDeck.length - 1]] = [newDeck[newDeck.length - 1], newDeck[0]];
        }
        
        indicesQueue = newDeck;
        pointer = 0;
      }
      
      currentIndex = indicesQueue[pointer];
      delta = 50;
    } else if (!isDeleting && updatedText !== fullText) {
      delta = 40 + Math.random() * 40;
    }

    if (intervalId) {
      clearInterval(intervalId);
      intervalId = setInterval(tick, delta);
    }
  }

  function destroy() {
    if (intervalId) {
      clearInterval(intervalId);
      intervalId = null;
    }
    textElement = null;
    currentText = '';
  }

  return {
    init: init,
    destroy: destroy
  };
})();