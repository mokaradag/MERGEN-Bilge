// www/js/bilge_yolac_kopru.js
// Shiny entegrasyonu: startWelcomeScreen/stopWelcomeScreen/ccUpdateWelcomeTheme globalleri, sekme değişim tespiti

(function() {
  "use strict";

  var BY = window.BilgeYolac;
  if (!BY) return;

  // Karşılama ekranını başlat
  function karsilamaBaslat(containerId) {
    var hedefId = containerId || "claude_code_module-welcome_screen";

    var container = document.getElementById(hedefId);
    if (!container) return;

    // Container'i aktif yap
    container.classList.add("cc-welcome-active");

    // Motoru başlat
    var basarili = BY.motor.init(hedefId);
    if (!basarili) return;

    // Etkileşimi başlat
    if (BY.etkilesim && BY.etkilesim.baslat) {
      BY.etkilesim.baslat();
    }

    // Motoru çalıştır
    BY.motor.baslat();
  }

  // Karşılama ekranını durdur
  function karsilamaDurdur() {
    // Motoru durdur
    BY.motor.durdur();

    // Etkileşimi temizle
    if (BY.etkilesim && BY.etkilesim.temizle) {
      BY.etkilesim.temizle();
    }

    // Canvas temizle
    var state = BY.state;
    if (state.canvas && state.canvas.parentElement) {
      state.canvas.parentElement.removeChild(state.canvas);
      state.canvas = null;
      state.ctx = null;
    }
  }

  // Tema güncelle
  function temaGuncelle(karakterId, aksanRenk) {
    // Renk şablonunu güncelle (eğer geçerli bir karakter ID'si verilmişse)
    if (karakterId && BY.config.KARAKTER_RENKLERI[karakterId]) {
      BY.state.temaRenk = BY.config.KARAKTER_RENKLERI[karakterId].ana;
    } else if (aksanRenk) {
      BY.state.temaRenk = aksanRenk;
    }
  }

  // Global fonksiyonları tanımla (claude_code.js ile uyumluluk)
  window.ccStartWelcome = function(containerId) {
    karsilamaBaslat(containerId);
  };

  window.ccStopWelcome = function() {
    karsilamaDurdur();
  };

  window.ccUpdateWelcomeTheme = function(karakterId, aksanRenk) {
    temaGuncelle(karakterId, aksanRenk);
  };

  // Shiny mesaj işleyicileri
  if (typeof Shiny !== "undefined") {

    // Karşılama ekranı başlat
    Shiny.addCustomMessageHandler("cc-init-welcome", function(mesaj) {
      var hedefId = mesaj.containerId || "claude_code_module-welcome_screen";
      setTimeout(function() {
        karsilamaBaslat(hedefId);
      }, 500);
    });

    // Karşılama ekranını göster
    Shiny.addCustomMessageHandler("cc-show-welcome", function(mesaj) {
      var hedefId = mesaj.containerId || "claude_code_module-welcome_screen";
      karsilamaBaslat(hedefId);
    });

    // Karşılama ekranını gizle
    Shiny.addCustomMessageHandler("cc-hide-welcome", function(mesaj) {
      karsilamaDurdur();
      var container = document.getElementById(mesaj.containerId || "claude_code_module-welcome_screen");
      if (container) {
        container.classList.remove("cc-welcome-active");
      }
    });

    // Sekme değişimi dinle
    $(document).on("shiny:inputchanged", function(e) {
      if (e.name === "tabs" && e.value === "claude_code") {
        // Bilge Yolaç sekmesine geçildi
        setTimeout(function() {
          var container = document.getElementById("claude_code_module-welcome_screen");
          if (container && container.classList.contains("cc-welcome-active")) {
            // Zaten aktifse motoru kontrol et
            if (!BY.state.calisiyor) {
              karsilamaBaslat();
            }
          }
        }, 300);
      } else {
        // Başka sekmeye geçildi - motoru durakla (bellek tasarrufu)
        if (BY.state.calisiyor) {
          BY.motor.durdur();
        }
      }
    });

    // Shiny bağlantısı kurulduğunda otomatik başlat
    $(document).on("shiny:connected", function() {
      setTimeout(function() {
        // Aktif sekme kontrolü
        var aktifSekme = $(".sidebar-menu .active a[data-value]").attr("data-value");
        if (aktifSekme === "claude_code") {
          var container = document.getElementById("claude_code_module-welcome_screen");
          if (container && container.classList.contains("cc-welcome-active")) {
            karsilamaBaslat();
          }
        }
      }, 800);
    });

  }

})();