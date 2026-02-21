// www/js/intro_animation.js
// Dosya Yolu: www/js/intro_animation.js
// Açıklama: Giriş animasyonu başlatıcı. Derin uzay giriş ekranı yoksa
// veya atlanmışsa uygulamayı doğrudan hazır duruma getirir.

$(document).ready(function() {
  // Derin uzay konteyneri varsa müdahale etme (mode_selection.js yönetecek)
  var deepSpaceContainer = document.getElementById('deep-space-container');
  if (deepSpaceContainer) {
    // Derin uzay giriş ekranı mevcut, kendi akışına bırak
    return;
  }

  // Eski intro-container varsa temizle (geriye uyumluluk)
  var oldIntro = document.getElementById('intro-container');
  if (oldIntro) {
    document.body.classList.add('app-ready');
    oldIntro.classList.add('fade-out');
    setTimeout(function() {
      if (oldIntro.parentNode) {
        oldIntro.parentNode.removeChild(oldIntro);
      }
    }, 1000);
    return;
  }

  // Hiçbir giriş ekranı yoksa uygulamayı hazır olarak işaretle
  document.body.classList.add('app-ready');
});
