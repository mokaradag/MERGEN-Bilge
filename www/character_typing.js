// Character typing effect - word by word
window.typeCharacterLore = function(text, elementId, delay = 80, onComplete) {
  const element = document.getElementById(elementId);
  if (!element) return;
  
  // Clear existing content and make visible
  element.textContent = '';
  element.style.opacity = '1';
  
  // Split by words (including spaces)
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

// Generic typing helper (character by character)
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