// www/js/character_typing.js
// Bu dosya karakter hikayesi ve genel metinler için yazma efektlerini içerir.

// Karakter yazma efekti - kelime kelime
window.typeCharacterLore = function(text, elementId, delay = 80, onComplete) {
  const element = document.getElementById(elementId);
  if (!element) return;

  // Mevcut içeriği temizle ve görünür yap
  element.textContent = '';
  element.style.opacity = '1';

  // Kelimelere ayır (boşluklar dahil)
  const words = text.match(/\S+\s*/g) || [];
  let index = 0;

  function typeWord() {
    if (index < words.length) {
      element.textContent += words[index];
      index++;
      setTimeout(typeWord, delay);
    } else if (typeof onComplete === 'function') {
      onComplete();
    }
  }

  typeWord();
};

// Genel yazma yardımcısı (karakter karakter)
window.typeCharacterText = function(target, text, delay = 35, onComplete) {
  const element = typeof target === 'string' ? document.getElementById(target) : target;
  if (!element) {
    if (typeof onComplete === 'function') onComplete();
    return;
  }

  const characters = Array.from(text || '');
  let index = 0;
  element.textContent = '';

  function typeNext() {
    if (index < characters.length) {
      element.textContent += characters[index];
      index++;
      setTimeout(typeNext, delay);
    } else if (typeof onComplete === 'function') {
      onComplete();
    }
  }

  typeNext();
};