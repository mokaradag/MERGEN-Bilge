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