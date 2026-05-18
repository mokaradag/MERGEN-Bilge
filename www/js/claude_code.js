// =============================================================================
// Dosya Yolu: www/js/claude_code.js
// Açıklama: Claude Code entegrasyon sayfasının istemci tarafı mantığı.
//           Mesaj gösterimi, araç kullanımı görüntüleme, küçültülmüş 16x16
//           piksel animasyonu, düşünme mesajı döngüsü, karakter teması
//           güncelleme, klavye kısayolları ve prompt değeri yönetimini sağlar.
// =============================================================================

(function() {
  'use strict';

  // -------------------------------------------------------------------------
  // 16x16 PİKSEL KARAKTER TANIMLARI (küçültülmüş animasyon için)
  // Her karakter 16x16 piksel haritası (0=boş, 1=ana renk, 2=koyu ton, 3=açık ton)
  // idle ve düşünme kareleri tanımlanıyor
  // -------------------------------------------------------------------------
  var PIXEL_CHARS_MINI = {
    mergen: {
      frames: [
        // Kare 1: Durağan poz (idle)
        [[0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,1,2,1,2,1,0,0,0,0,0,0],
         [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
         [0,0,0,0,1,2,1,1,1,2,1,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,0,1,2,1,0,0,0,0,0,0,0],
         [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
         [0,0,0,1,2,1,1,1,1,1,2,1,0,0,0,0],
         [0,0,3,1,2,1,1,1,1,1,2,1,3,0,0,0],
         [0,0,3,0,1,1,1,1,1,1,1,0,3,0,0,0],
         [0,0,3,0,0,1,2,1,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,2,1,0,1,2,0,0,0,0,0,0],
         [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,2,2,0,2,2,0,0,0,0,0,0]],
        // Kare 2: Düşünme pozu (hafif eğilme + kol hareketi)
        [[0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,1,2,1,2,1,0,0,0,0,0,0],
         [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
         [0,0,0,0,1,2,1,1,1,2,1,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,0,1,2,1,0,0,0,0,0,0,0],
         [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
         [0,0,0,1,2,1,1,1,1,1,2,1,0,0,0,0],
         [0,0,3,1,2,1,1,1,1,1,2,1,3,0,0,0],
         [0,0,3,0,1,1,1,1,1,1,1,0,3,0,0,0],
         [0,0,0,0,0,1,2,1,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
         [0,0,0,0,1,2,0,0,0,2,1,0,0,0,0,0],
         [0,0,0,0,2,1,0,0,0,1,2,0,0,0,0,0],
         [0,0,0,0,2,2,0,0,0,2,2,0,0,0,0,0]],
        // Kare 3: Düşünme pozu 2 (kol yukarıda)
        [[0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,1,2,1,2,1,0,0,0,0,0,0],
         [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
         [0,0,0,0,1,1,1,1,1,2,1,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,0,1,2,1,0,0,0,0,0,0,0],
         [0,0,0,3,1,1,1,1,1,1,1,0,0,0,0,0],
         [0,0,3,0,2,1,1,1,1,1,2,1,0,0,0,0],
         [0,3,0,0,2,1,1,1,1,1,2,1,0,0,0,0],
         [0,0,0,0,1,1,1,1,1,1,1,0,3,0,0,0],
         [0,0,0,0,0,1,2,1,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,2,1,0,1,2,0,0,0,0,0,0],
         [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,2,2,0,2,2,0,0,0,0,0,0]]
      ],
      color: '#7C4DFF', darkColor: '#5635B2', lightColor: '#A47DFF'
    },
    ulgen: {
      frames: [
        [[0,0,0,3,0,0,0,0,0,0,0,3,0,0,0,0],
         [0,0,3,0,3,0,0,3,0,0,3,0,3,0,0,0],
         [0,0,3,0,0,1,1,1,1,1,0,0,3,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,1,1,2,1,2,1,1,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0],
         [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
         [0,0,0,1,2,1,1,1,1,1,2,1,0,0,0,0],
         [0,0,0,1,2,1,3,1,3,1,2,1,0,0,0,0],
         [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
         [0,0,0,0,0,1,2,1,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,2,1,0,1,2,0,0,0,0,0,0],
         [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,2,2,0,2,2,0,0,0,0,0,0]],
        [[0,0,0,3,0,0,0,0,0,0,0,3,0,0,0,0],
         [0,0,3,0,3,0,0,3,0,0,3,0,3,0,0,0],
         [0,0,3,0,0,1,1,1,1,1,0,0,3,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,1,1,2,1,2,1,1,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0],
         [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
         [0,0,0,1,2,1,1,1,1,1,2,1,0,0,0,0],
         [0,0,0,1,2,1,3,1,3,1,2,1,0,0,0,0],
         [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
         [0,0,0,0,0,1,2,1,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
         [0,0,0,0,1,2,0,0,0,2,1,0,0,0,0,0],
         [0,0,0,0,2,1,0,0,0,1,2,0,0,0,0,0],
         [0,0,0,0,2,2,0,0,0,2,2,0,0,0,0,0]],
        [[0,0,0,3,0,0,0,0,0,0,0,3,0,0,0,0],
         [0,0,3,0,3,0,0,3,0,0,3,0,3,0,0,0],
         [0,0,3,0,0,1,1,1,1,1,0,0,3,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,1,1,2,1,2,1,1,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0],
         [0,0,3,0,1,1,1,1,1,1,1,0,0,0,0,0],
         [0,3,0,1,2,1,1,1,1,1,2,1,0,0,0,0],
         [3,0,0,1,2,1,3,1,3,1,2,1,0,0,0,0],
         [0,0,0,0,1,1,1,1,1,1,1,0,3,0,0,0],
         [0,0,0,0,0,1,2,1,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,2,1,0,1,2,0,0,0,0,0,0],
         [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,2,2,0,2,2,0,0,0,0,0,0]]
      ],
      color: '#2F6DF6', darkColor: '#1E4DB0', lightColor: '#6B9BFF'
    },
    kayra: {
      frames: [
        [[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
         [0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,1,1,2,1,2,1,1,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0],
         [0,0,3,0,1,1,1,1,1,1,1,0,0,0,0,0],
         [0,0,3,1,2,1,1,1,1,1,2,1,0,3,0,0],
         [0,0,3,1,2,1,1,1,1,1,2,1,0,3,0,0],
         [0,0,3,0,1,1,1,1,1,1,1,0,3,3,3,0],
         [0,0,3,0,0,1,2,1,2,1,0,0,0,3,0,0],
         [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,2,1,0,1,2,0,0,0,0,0,0],
         [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,2,2,0,2,2,0,0,0,0,0,0]],
        [[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
         [0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,1,1,2,1,2,1,1,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0],
         [0,0,3,0,1,1,1,1,1,1,1,0,0,0,0,0],
         [0,0,3,1,2,1,1,1,1,1,2,1,0,3,0,0],
         [0,0,3,1,2,1,1,1,1,1,2,1,0,3,0,0],
         [0,0,3,0,1,1,1,1,1,1,1,0,3,3,3,0],
         [0,0,3,0,0,1,2,1,2,1,0,0,0,3,0,0],
         [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
         [0,0,0,0,1,2,0,0,0,2,1,0,0,0,0,0],
         [0,0,0,0,2,1,0,0,0,1,2,0,0,0,0,0],
         [0,0,0,0,2,2,0,0,0,2,2,0,0,0,0,0]],
        [[0,0,0,0,0,0,0,0,0,0,0,0,0,3,0,0],
         [0,0,0,0,0,0,1,1,1,0,0,0,3,3,3,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,3,0,0],
         [0,0,0,0,1,1,2,1,2,1,1,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0],
         [0,0,3,0,1,1,1,1,1,1,1,0,0,0,0,0],
         [0,0,3,1,2,1,1,1,1,1,2,1,3,0,0,0],
         [0,0,3,1,2,1,1,1,1,1,2,0,0,0,0,0],
         [0,0,3,0,1,1,1,1,1,1,1,0,0,0,0,0],
         [0,0,0,0,0,1,2,1,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,2,1,0,1,2,0,0,0,0,0,0],
         [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,2,2,0,2,2,0,0,0,0,0,0]]
      ],
      color: '#12A97B', darkColor: '#0C7A58', lightColor: '#6EE89B'
    },
    erlik: {
      frames: [
        [[0,0,0,0,0,3,0,3,0,3,0,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,1,1,2,1,1,0,0,0,0,0,0],
         [0,0,0,0,1,1,2,1,2,1,1,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0],
         [0,0,3,0,1,1,1,1,1,1,1,0,0,0,0,0],
         [0,0,3,1,2,1,1,2,1,1,2,1,0,0,0,0],
         [0,0,3,1,2,1,1,1,1,1,2,1,0,0,0,0],
         [0,0,3,0,1,1,1,1,1,1,1,0,0,0,0,0],
         [0,0,3,0,0,1,2,1,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,2,1,0,1,2,0,0,0,0,0,0],
         [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,2,2,0,2,2,0,0,0,0,0,0]],
        [[0,0,0,0,0,3,0,3,0,3,0,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,1,1,2,1,1,0,0,0,0,0,0],
         [0,0,0,0,1,1,2,1,2,1,1,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0],
         [0,0,3,0,1,1,1,1,1,1,1,0,0,0,0,0],
         [0,0,3,1,2,1,1,2,1,1,2,1,0,0,0,0],
         [0,0,3,1,2,1,1,1,1,1,2,1,0,0,0,0],
         [0,0,3,0,1,1,1,1,1,1,1,0,0,0,0,0],
         [0,0,0,0,0,1,2,1,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
         [0,0,0,0,1,2,0,0,0,2,1,0,0,0,0,0],
         [0,0,0,0,2,1,0,0,0,1,2,0,0,0,0,0],
         [0,0,0,0,2,2,0,0,0,2,2,0,0,0,0,0]],
        [[0,0,0,0,0,3,0,3,0,3,0,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,1,1,2,1,1,0,0,0,0,0,0],
         [0,0,0,0,1,1,2,1,2,1,1,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0],
         [0,0,0,0,1,1,1,1,1,1,1,3,0,0,0,0],
         [0,0,0,1,2,1,1,2,1,1,2,0,3,0,0,0],
         [0,0,0,1,2,1,1,1,1,1,2,0,0,3,0,0],
         [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
         [0,0,0,0,0,1,2,1,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,2,1,0,1,2,0,0,0,0,0,0],
         [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,2,2,0,2,2,0,0,0,0,0,0]]
      ],
      color: '#E74C3C', darkColor: '#B53A2E', lightColor: '#F08070'
    },
    umay: {
      frames: [
        [[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
         [0,0,0,0,0,1,3,3,3,1,0,0,0,0,0,0],
         [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
         [0,0,0,0,1,1,2,1,2,1,1,0,0,0,0,0],
         [0,0,0,0,0,1,1,3,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0],
         [0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0],
         [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
         [0,0,0,1,2,1,1,1,1,1,2,1,0,0,0,0],
         [0,0,0,1,2,1,3,1,3,1,2,1,0,0,0,0],
         [0,0,0,1,1,1,3,3,3,1,1,1,0,0,0,0],
         [0,0,0,0,1,1,3,1,3,1,1,0,0,0,0,0],
         [0,0,0,0,0,1,3,3,3,1,0,0,0,0,0,0],
         [0,0,0,0,0,2,1,0,1,2,0,0,0,0,0,0],
         [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,2,2,0,2,2,0,0,0,0,0,0]],
        [[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
         [0,0,0,0,0,1,3,3,3,1,0,0,0,0,0,0],
         [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
         [0,0,0,0,1,1,2,1,2,1,1,0,0,0,0,0],
         [0,0,0,0,0,1,1,3,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0],
         [0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0],
         [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
         [0,0,0,1,2,1,1,1,1,1,2,1,0,0,0,0],
         [0,0,0,1,2,1,3,1,3,1,2,1,0,0,0,0],
         [0,0,0,1,1,1,3,3,3,1,1,1,0,0,0,0],
         [0,0,0,0,1,1,3,1,3,1,1,0,0,0,0,0],
         [0,0,0,0,0,1,3,3,3,1,0,0,0,0,0,0],
         [0,0,0,0,1,2,0,0,0,2,1,0,0,0,0,0],
         [0,0,0,0,2,1,0,0,0,1,2,0,0,0,0,0],
         [0,0,0,0,2,2,0,0,0,2,2,0,0,0,0,0]],
        [[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
         [0,0,0,0,0,1,3,3,3,1,0,0,0,0,0,0],
         [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
         [0,0,0,0,1,1,2,1,2,1,1,0,0,0,0,0],
         [0,0,0,0,0,1,1,3,1,1,0,0,0,0,0,0],
         [0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0],
         [0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0],
         [0,0,3,0,1,1,1,1,1,1,1,0,3,0,0,0],
         [0,3,0,1,2,1,1,1,1,1,2,1,0,3,0,0],
         [3,0,0,1,2,1,3,1,3,1,2,1,0,0,3,0],
         [0,0,0,1,1,1,3,3,3,1,1,1,0,0,0,0],
         [0,0,0,0,1,1,3,1,3,1,1,0,0,0,0,0],
         [0,0,0,0,0,1,3,3,3,1,0,0,0,0,0,0],
         [0,0,0,0,0,2,1,0,1,2,0,0,0,0,0,0],
         [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
         [0,0,0,0,0,2,2,0,2,2,0,0,0,0,0,0]]
      ],
      color: '#E98686', darkColor: '#C45E5E', lightColor: '#F5ABAB'
    }
  };

  // -------------------------------------------------------------------------
  // KÜÇÜLTÜLMÜŞ ANİMASYON MOTORU (16x16 piksel)
  // -------------------------------------------------------------------------
  var miniAnimFrameId = null;
  var miniFrame = 0;
  var miniParticles = [];

  function drawMiniCharacter(canvas, characterId, frame) {
    if (!canvas) return;
    var ctx = canvas.getContext('2d');
    var charData = PIXEL_CHARS_MINI[characterId] || PIXEL_CHARS_MINI.mergen;
    var frameIdx = Math.floor(frame / 20) % charData.frames.length;
    var pixels = charData.frames[frameIdx];
    var pixelSize = 3;

    ctx.clearRect(0, 0, canvas.width, canvas.height);

    // Zıplama efekti
    var bounceY = Math.sin(frame * 0.08) * 1.5;

    for (var y = 0; y < pixels.length; y++) {
      for (var x = 0; x < pixels[y].length; x++) {
        var val = pixels[y][x];
        if (val === 0) continue;
        if (val === 1) ctx.fillStyle = charData.color;
        else if (val === 2) ctx.fillStyle = charData.darkColor;
        else ctx.fillStyle = charData.lightColor || charData.color;
        ctx.fillRect(x * pixelSize, y * pixelSize + bounceY, pixelSize - 1, pixelSize - 1);
      }
    }

    // Parçacıklar
    if (frame % 20 === 0) {
      miniParticles.push({
        x: Math.random() * canvas.width,
        y: Math.random() * canvas.height,
        size: Math.random() * 2 + 1,
        life: 0, maxLife: 25 + Math.random() * 20
      });
    }
    for (var i = miniParticles.length - 1; i >= 0; i--) {
      var p = miniParticles[i];
      p.life++;
      if (p.life > p.maxLife) { miniParticles.splice(i, 1); continue; }
      var alpha = 1 - (p.life / p.maxLife);
      ctx.globalAlpha = alpha * 0.5;
      ctx.fillStyle = charData.color;
      ctx.fillRect(p.x, p.y, p.size, p.size);
    }
    ctx.globalAlpha = 1;
    if (miniParticles.length > 10) miniParticles = miniParticles.slice(-8);
  }

  function startMiniAnimation(canvasId, characterId) {
    var canvas = document.getElementById(canvasId);
    if (!canvas) return;
    miniFrame = 0;
    miniParticles = [];

    function animate() {
      drawMiniCharacter(canvas, characterId, miniFrame);
      miniFrame++;
      miniAnimFrameId = requestAnimationFrame(animate);
    }
    animate();
  }

  function stopMiniAnimation() {
    if (miniAnimFrameId) {
      cancelAnimationFrame(miniAnimFrameId);
      miniAnimFrameId = null;
    }
    miniParticles = [];
  }

  // -------------------------------------------------------------------------
  // ARAÇ KULLANIMI GÖRÜNTÜLEMESİ (açılır/kapanır)
  // -------------------------------------------------------------------------
  function toggleToolBlock(el) {
    var result = el.closest('.cc-tool-block').querySelector('.cc-tool-result');
    if (result) {
      result.classList.toggle('cc-tool-result-hidden');
      var icon = el.querySelector('.cc-tool-toggle-icon');
      if (icon) {
        icon.classList.toggle('fa-chevron-down');
        icon.classList.toggle('fa-chevron-right');
      }
    }
  }

  // Tüm araç sonuçlarını gizle/göster
  window.ccToggleAllTools = function(el) {
    var section = el.closest('.cc-tool-section');
    if (!section) return;
    var results = section.querySelectorAll('.cc-tool-result');
    var icon = el.querySelector('i');
    // Hepsi gizli mi kontrol et
    var allHidden = true;
    results.forEach(function(r) {
      if (!r.classList.contains('cc-tool-result-hidden')) allHidden = false;
    });
    results.forEach(function(r) {
      if (allHidden) {
        r.classList.remove('cc-tool-result-hidden');
      } else {
        r.classList.add('cc-tool-result-hidden');
      }
    });
    // İkonu güncelle
    var headers = section.querySelectorAll('.cc-tool-toggle-icon');
    headers.forEach(function(h) {
      h.classList.remove('fa-chevron-right', 'fa-chevron-down');
      h.classList.add(allHidden ? 'fa-chevron-down' : 'fa-chevron-right');
    });
    if (icon) {
      icon.classList.remove('fa-eye', 'fa-eye-slash');
      icon.classList.add(allHidden ? 'fa-eye' : 'fa-eye-slash');
    }
  };

  // Araç blokları için tıklama işleyicisi (event delegation)
  document.addEventListener('click', function(e) {
    var header = e.target.closest('.cc-tool-header');
    if (header && header.closest('.cc-tool-block')) {
      toggleToolBlock(header);
    }
  });

  // -------------------------------------------------------------------------
  // MESAJ EKLEME
  // -------------------------------------------------------------------------
  function addMessage(data) {
    var target = document.getElementById(data.target);
    if (!target) return;

    // Karşılama ekranını gizle ve animasyonu durdur
    if (data.welcomeId) {
      var welcome = document.getElementById(data.welcomeId);
      if (welcome) {
        welcome.classList.remove('cc-welcome-active');
        if (typeof window.ccStopWelcome === 'function') {
          window.ccStopWelcome();
        }
      }
    }

    var msgDiv = document.createElement('div');
    var typeClass = 'cc-message-' + (data.type || 'assistant');
    msgDiv.className = 'cc-message ' + typeClass;

    if (data.accentColor) {
      msgDiv.style.setProperty('--cc-accent', data.accentColor);
    }

    // Başlık
    var headerHtml = '<div class="cc-message-header">';
    if (data.type === 'user') {
      var senderName = data.senderName || 'Siz';
      headerHtml += '<span class="cc-message-sender">' + senderName + '</span>';
    } else if (data.type === 'error') {
      headerHtml += '<span class="cc-message-sender" style="color:#E57373;">Hata</span>';
    } else {
      var charName = data.characterName || 'Claude Code';
      headerHtml += '<span class="cc-message-sender" style="color:' +
                    (data.accentColor || '#7C4DFF') + ';">' + charName + '</span>';
    }

    if (data.timestamp) {
      headerHtml += '<span class="cc-message-time">' + data.timestamp + '</span>';
    }
    if (data.duration) {
      headerHtml += '<span class="cc-message-duration">' + data.duration + ' sn</span>';
    }
    headerHtml += '</div>';

    // Araç kullanımı (açılır/kapanır bloklar, tümünü gizle/göster düğmesi)
    var toolHtml = '';
    if (data.toolContent && data.toolContent.length > 0) {
      toolHtml = '<div class="cc-tool-section">' +
                 '<div class="cc-tool-section-header">' +
                 '<i class="fas fa-cogs"></i> Araç Kullanımları' +
                 '<span class="cc-tool-toggle-all" onclick="window.ccToggleAllTools(this)" title="Tümünü gizle/göster">' +
                 '<i class="fas fa-eye"></i></span>' +
                 '</div>' + data.toolContent + '</div>';
    }

    // İçerik (mojibake düzeltmesi: R/Shiny çift kodlama sorunu)
    var content = data.content || '';
    if (data.type !== 'user') {
      // Asistan/hata mesajlarında HTML içindeki mojibake'yi düzelt
      content = content.replace(/>([^<]+)</g, function(match, txt) {
        var fixed = txt;

        if (typeof window.ccFixMojibake === 'function') {
          fixed = window.ccFixMojibake(fixed);
        }

        if (typeof window.ccFixMojibakeText === 'function') {
          fixed = window.ccFixMojibakeText(fixed);
        }

        return '>' + fixed + '<';
      });
    }
    var bodyHtml = '<div class="cc-message-body">';
    if (data.type === 'user') {
      bodyHtml += '<pre class="cc-user-pre">' + data.content + '</pre>';
    } else {
      bodyHtml += content;
    }
    bodyHtml += '</div>';

    msgDiv.innerHTML = headerHtml + toolHtml + bodyHtml;

    // Araç sonuçlarını varsayılan olarak GÖSTER (kullanıcı kapatabilir)
    var toolResults = msgDiv.querySelectorAll('.cc-tool-result');
    // Sonuçlar açık başlar, kullanıcı tıklayarak kapatabilir

    // Açma/kapama ikonlarını ekle
    var toolHeaders = msgDiv.querySelectorAll('.cc-tool-header');
    toolHeaders.forEach(function(th) {
      if (!th.querySelector('.cc-tool-toggle-icon')) {
        var toggleIcon = document.createElement('i');
        toggleIcon.className = 'fas fa-chevron-down cc-tool-toggle-icon';
        th.appendChild(toggleIcon);
      }
      th.style.cursor = 'pointer';
    });

    target.appendChild(msgDiv);

    // Otomatik kaydır
    var wrapper = target.closest('.cc-output-wrapper');
    if (wrapper) {
      wrapper.scrollTop = wrapper.scrollHeight;
    }
  }

  // -------------------------------------------------------------------------
  // PROMPT DEĞER OKUMA YARDIMCISI
  // Shiny'nin raw textarea'dan değer okuması için prompt değerini gönderir
  // -------------------------------------------------------------------------
  function sendPromptValue(ns) {
    var textarea = document.querySelector('.cc-prompt-input');
    if (!textarea) return;
    var value = textarea.value || '';
    // Shiny'ye prompt değerini gönder
    var inputId = ns ? ns.replace(/-$/, '') + '-prompt_value' : 'claude_code_module-prompt_value';
    Shiny.setInputValue(inputId, value, {priority: 'event'});
  }

  // -------------------------------------------------------------------------
  // SHINY MESAJ İŞLEYİCİLERİ
  // -------------------------------------------------------------------------

  // Mesaj Ekleme
  Shiny.addCustomMessageHandler('cc-add-message', function(data) {
    addMessage(data);
  });

  // Çıktıyı Temizle ve karşılama ekranını göster
  Shiny.addCustomMessageHandler('cc-clear-output', function(data) {
    var target = document.getElementById(data.target);
    if (target) target.innerHTML = '';

    var statusEl = document.getElementById(data.statusId);
    if (statusEl) statusEl.innerHTML = '';

    var durationEl = document.getElementById(data.durationId);
    if (durationEl) durationEl.textContent = '';

    if (data.welcomeId) {
      var welcome = document.getElementById(data.welcomeId);
      if (welcome) {
        welcome.classList.add('cc-welcome-active');
        // Karşılama animasyonunu yeniden başlat
        if (typeof window.ccStartWelcome === 'function') {
          window.ccStartWelcome(data.welcomeId);
        }
      }
    }
  });

  // Düşünme animasyonunu başlat (küçültülmüş)
  Shiny.addCustomMessageHandler('cc-thinking-start', function(data) {
    var overlay = document.getElementById(data.overlayId);
    var textEl = document.getElementById(data.textId);
    var statusEl = document.getElementById(data.statusId);
    var durationEl = document.getElementById(data.durationId);

    if (overlay) overlay.classList.remove('cc-hidden');

    if (textEl) {
      textEl.textContent = data.message || 'Düşünüyor...';
      if (data.accentColor) textEl.style.color = data.accentColor;
    }

    if (statusEl) {
      statusEl.innerHTML = '<i class="fas fa-spinner fa-spin" style="color:#64B5F6;"></i> <span style="color:#64B5F6;">Çalışıyor...</span>';
    }

    // Canlı süre sayacını başlat
    if (window.ccDurationInterval) {
      clearInterval(window.ccDurationInterval);
      window.ccDurationInterval = null;
    }

    window.ccDurationStart = Date.now();

    if (durationEl) {
      durationEl.textContent = '0 sn';
    }

    window.ccDurationInterval = setInterval(function() {
      var currentDurationEl = document.getElementById(data.durationId);
      if (!currentDurationEl) return;

      var elapsedSec = Math.floor((Date.now() - window.ccDurationStart) / 1000);
      currentDurationEl.textContent = elapsedSec + ' sn';
    }, 1000);

    startMiniAnimation(data.canvasId, data.characterId || 'mergen');

    // Düşünme mesajını periyodik değiştir (3 saniyede bir)
    // Sunucu tarafına istek göndererek yeni mesaj al
    if (window.ccThinkingInterval) clearInterval(window.ccThinkingInterval);
    window.ccThinkingInterval = setInterval(function() {
      // Overlay hala görünür mü kontrol et (DOM'dan tekrar al)
      var currentOverlay = document.getElementById(data.overlayId);
      var currentTextEl = document.getElementById(data.textId);
      if (currentTextEl && currentOverlay && !currentOverlay.classList.contains('cc-hidden')) {
        var tickId = data.statusId.replace('status_text', 'thinking_tick');
        Shiny.setInputValue(tickId, Math.random(), {priority: 'event'});
      } else {
        // Overlay gizlenmişse interval'i temizle
        clearInterval(window.ccThinkingInterval);
        window.ccThinkingInterval = null;
      }
    }, 3000);
  });

  // Düşünme animasyonunu durdur
  Shiny.addCustomMessageHandler('cc-thinking-stop', function(data) {
    var overlay = document.getElementById(data.overlayId);
    if (overlay) overlay.classList.add('cc-hidden');

    stopMiniAnimation();

    if (window.ccThinkingInterval) {
      clearInterval(window.ccThinkingInterval);
      window.ccThinkingInterval = null;
    }

    // Canlı süre sayacını durdur
    if (window.ccDurationInterval) {
      clearInterval(window.ccDurationInterval);
      window.ccDurationInterval = null;
    }
  });

  // Düşünme metni güncelleme
  Shiny.addCustomMessageHandler('cc-update-thinking-text', function(data) {
    var textEl = document.getElementById(data.textId);
    if (textEl) {
      textEl.style.opacity = '0';
      setTimeout(function() {
        textEl.textContent = data.message || '';
        textEl.style.opacity = '1';
      }, 200);
    }
  });

  // Durum çubuğu güncelle (ikon + renk destekli)
  Shiny.addCustomMessageHandler('cc-update-status', function(data) {
    var statusEl = document.getElementById(data.statusId);
    var durationEl = document.getElementById(data.durationId);

    if (statusEl) {
      var iconClass = data.statusIcon || 'circle';
      var color = data.statusColor || '#81C784';
      statusEl.innerHTML = '<i class="fas fa-' + iconClass + '" style="color:' + color + ';"></i> ' +
                          '<span style="color:' + color + ';">' + (data.status || '') + '</span>';
    }

    if (durationEl) {
      durationEl.textContent = data.duration || '';
    }
  });

  // Yazı tipi boyutu güncelleme (Ayarlar sayfasından)
  Shiny.addCustomMessageHandler('cc-update-font-size', function(data) {
    var container = document.querySelector('.claude-code-container');
    if (!container) return;
    // Üst seviye content-wrapper'a sınıf ekle
    var wrapper = container.closest('.content-wrapper') || container.closest('.tab-pane') || container;
    wrapper.classList.remove('font-small', 'font-medium', 'font-large', 'font-xlarge');
    wrapper.classList.add('font-' + (data.size || 'medium'));
  });

  // Karakter teması güncelleme
  Shiny.addCustomMessageHandler('cc-update-theme', function(data) {
    var container = document.querySelector('.claude-code-container');
    if (!container) return;

    container.setAttribute('data-character', data.characterId || 'mergen');

    // CSS değişkenlerini güncelle
    var accent = data.accentColor || '#7C4DFF';
    var hover = data.accentHover || accent;
    container.style.setProperty('--cc-theme-accent', accent);
    container.style.setProperty('--cc-theme-hover', hover);

    // Rozet rengini güncelle
    var badge = container.querySelector('.cc-badge');
    if (badge) {
      badge.style.background = 'linear-gradient(135deg, ' + accent + ' 0%, ' + hover + ' 100%)';
    }

    // Karşılama ekranını da güncelle
    if (typeof window.ccUpdateWelcomeTheme === 'function') {
      window.ccUpdateWelcomeTheme(data.characterId, accent);
    }
  });

  // -------------------------------------------------------------------------
  // ARAYÜZ DURUMU GÜNCELLEME (later::later bağlamından güvenli çağrı)
  // shinyjs oturum bulamadığında çökmeyi önlemek için doğrudan DOM günceller.
  // -------------------------------------------------------------------------

  // Akış sonlandırma: düğmeleri güncelle (çalıştır etkinleştir, durdur gizle)
  Shiny.addCustomMessageHandler('cc-finalize-ui', function(data) {
    // Çalıştır düğmesini etkinleştir
    // shinyjs::disable hem disabled özniteliği hem de disabled sınıfı ekler,
    // ikisini de kaldırmak gerekir.
    if (data.runBtnId) {
      var runBtn = document.getElementById(data.runBtnId);
      if (runBtn) {
        runBtn.disabled = false;
        runBtn.removeAttribute('disabled');
        runBtn.classList.remove('disabled');
      }
    }
    // Durdur düğmesini gizle
    if (data.stopBtnId) {
      var stopBtn = document.getElementById(data.stopBtnId);
      if (stopBtn) {
        stopBtn.classList.add('cc-hidden');
      }
    }
  });

  // Eleman metin içeriğini güncelle (dizin yolu vb.)
  Shiny.addCustomMessageHandler('cc-update-element-text', function(data) {
    if (data.elementId) {
      var el = document.getElementById(data.elementId);
      if (el) {
        el.textContent = data.text || '';
      }
    }
  });

  // -------------------------------------------------------------------------
  // KLAVYE KISAYOLLARI VE DÜĞME TIKLAMA YÖNETİMİ
  // -------------------------------------------------------------------------

  // Çalıştır düğmesine tıklanmadan önce prompt değerini Shiny'ye gönder
  document.addEventListener('click', function(e) {
    var runBtn = e.target.closest('.cc-run-btn');
    if (runBtn && !runBtn.disabled) {
      // Önce önceki durum çubuğunu temizle
      var container = runBtn.closest('.cc-terminal-panel') || runBtn.closest('.claude-code-container');
      if (container) {
        var statusEl = container.querySelector('.cc-status-text');
        if (statusEl) {
          // Anlık görsel geri bildirim: kullanıcı tıkladığı anda durum çubuğu
          // "Hazırlanıyor..." göstersin. Sunucu workdir doğrulama, doküman
          // bağlamı hazırlama gibi işlemleri synchronous yaptığı için
          // cc-thinking-start mesajı bu işlemler bittiğinde gelir. Bu boşluk
          // UNC ağ paylaşımında birkaç yüz ms tutabilir.
          statusEl.innerHTML =
            '<i class="fas fa-spinner fa-spin" style="color:#64B5F6;"></i> ' +
            '<span style="color:#64B5F6;">Hazırlanıyor...</span>';
        }

        var durationEl = container.querySelector('.cc-duration-text');
        if (durationEl) durationEl.textContent = '';

        // Prompt değerini hemen Shiny'ye gönder
        var textarea = container.querySelector('.cc-prompt-input');
        if (textarea) {
          var ns = textarea.id.replace(/prompt_input$/, '');
          var inputId = ns + 'prompt_value';
          Shiny.setInputValue(inputId, textarea.value || '', {priority: 'event'});
        }
      }
    }
  }, true);

  // Ctrl+Enter veya Shift+Enter ile gönder
  document.addEventListener('keydown', function(e) {
    if ((e.ctrlKey || e.shiftKey) && e.key === 'Enter') {
      var textarea = e.target;
      if (textarea && textarea.classList.contains('cc-prompt-input')) {
        e.preventDefault();
        var container = textarea.closest('.cc-terminal-panel') || textarea.closest('.claude-code-container');
        if (container) {
          var runBtn = container.querySelector('.cc-run-btn');
          if (runBtn && !runBtn.disabled) {
            // Önce prompt değerini gönder
            var ns = textarea.id.replace('prompt_input', '');
            var inputId = ns + 'prompt_value';
            Shiny.setInputValue(inputId, textarea.value || '', {priority: 'event'});
            // Sonra düğmeyi tıkla (küçük gecikme ile)
            setTimeout(function() { runBtn.click(); }, 50);
          }
        }
      }
    }
  });

  // -------------------------------------------------------------------------
  // ANLIK GÖRSEL GERİ BİLDİRİM - UI GECİKME GİZLEME
  //
  // Shiny observers senkron çalışır. UNC ağ paylaşımındaki dizin listeleme,
  // çalışma dizini hazırlama veya dosya kopyalama gibi işlemler 200ms ile
  // birkaç saniye sürebilir. Bu sürede kullanıcı düğmeye bastığında hiçbir
  // şey olmadığını sanır. Capture-phase tıklama dinleyicileri, Shiny event
  // işleme başlamadan ÖNCE çalışarak anlık görsel geri bildirim verir.
  // Geri bildirim Shiny output güncellemesi DOM'u yeniden çizdiğinde veya
  // bir zamanlayıcı süresi dolduğunda otomatik olarak kaldırılır.
  // -------------------------------------------------------------------------

  document.addEventListener('click', function(e) {
    // 1) Dizin İçeriği yenileme düğmesi: ikon hemen spin animasyonu kazansın
    //    ve içerik alanı kısa süre Yenileniyor... yazsın. Asenkron listeleme
    //    bittiğinde renderUI yeni içeriği yerleştirerek yer tutucuyu siler.
    var refreshBtn = e.target.closest('.cc-refresh-btn');
    if (refreshBtn && !refreshBtn.disabled) {
      var icon = refreshBtn.querySelector('i.fa-sync, i.fa-sync-alt, i');
      if (icon) {
        icon.classList.add('fa-spin');
        setTimeout(function() {
          if (icon) icon.classList.remove('fa-spin');
        }, 4000);
      }

      // En yakın panel içindeki dizin içeriği alanını bul (multi-instance güvenli)
      var panel = refreshBtn.closest('.cc-folder-panel, .cc-folder-section, .cc-sidebar-panel, .cc-side-panel') ||
                  refreshBtn.closest('.claude-code-container') ||
                  document;
      var dirContents = panel.querySelector('[id$="dir_contents_ui"]');
      if (dirContents) {
        dirContents.innerHTML =
          '<p class="cc-dir-empty cc-dir-loading">' +
          '<i class="fas fa-spinner fa-spin"></i> Yenileniyor...' +
          '</p>';
      }
    }

    // 2) Üretilen dosya indirme kartı: anlık olarak "Hazırlanıyor..." göster.
    //    Tarayıcı download başlattığında varsayılan davranış sürdürülür.
    var downloadCard = e.target.closest('.cc-generated-file-card');
    if (downloadCard) {
      var action = downloadCard.querySelector('.cc-generated-file-action');
      if (action && action.getAttribute('data-original-text') === null) {
        action.setAttribute('data-original-text', action.textContent || 'İndir');
        action.textContent = 'Hazırlanıyor...';
        action.classList.add('cc-generated-file-action-loading');
        setTimeout(function() {
          var original = action.getAttribute('data-original-text');
          if (original !== null) {
            action.textContent = original;
            action.removeAttribute('data-original-text');
          }
          action.classList.remove('cc-generated-file-action-loading');
        }, 1500);
      }
    }
  }, true);

})();