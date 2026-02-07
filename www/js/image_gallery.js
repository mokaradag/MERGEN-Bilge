// Dosya Yolu: www/js/image_gallery.js
// Gorsel galerisi JavaScript islevleri - tooltip, animasyon ve etkilesim yonetimi

(function() {
  'use strict';

  window.ImageGallery = {
    init: function() {
      this.bindEvents();
    },

    bindEvents: function() {
      $(document).on('mouseenter', '.gallery-card', function() {
        $(this).addClass('gallery-card-hovered');
      });

      $(document).on('mouseleave', '.gallery-card', function() {
        $(this).removeClass('gallery-card-hovered');
      });

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
