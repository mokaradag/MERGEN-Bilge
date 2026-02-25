// Dosya Yolu: www/js/image_gallery.js
// Görsel galerisi JavaScript işlevleri - animasyon ve etkileşim yönetimi

(function() {
  'use strict';

  window.ImageGallery = {
    init: function() {
      this.bindEvents();
    },

    bindEvents: function() {
      // Kart hover sınıfı ekle/kaldır
      $(document).on('mouseenter', '.gallery-card', function() {
        $(this).addClass('gallery-card-hovered');
      });

      $(document).on('mouseleave', '.gallery-card', function() {
        $(this).removeClass('gallery-card-hovered');
      });

      // Tıklama animasyonu
      $(document).on('click', '.gallery-card-image-wrapper', function() {
        var card = $(this).closest('.gallery-card');
        card.addClass('gallery-card-clicked');
        setTimeout(function() {
          card.removeClass('gallery-card-clicked');
        }, 300);
      });
    }
  };

  $(document).ready(function() {
    window.ImageGallery.init();
  });
})();