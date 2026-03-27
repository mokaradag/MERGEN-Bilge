// www/js/bilge_yolac_kopru.js
// Shiny köprüsü: karşılama ekranı başlat/durdur, tema güncelleme, sekme değişim tespiti, Shiny mesaj işleyicileri

(function() {
  "use strict";

  var BY = window.BilgeYolac;
  if (!BY) return;

  // ════════════════════════════════════════════════════════════════════════
  //  KARŞILAMA EKRANI BAŞLAT
  // ════════════════════════════════════════════════════════════════════════

  function karsilamaBaslat(containerId) {
    var hedefId = containerId || "claude_code_module-welcome_screen";

    var container = document.getElementById(hedefId);
    if (!container) return;

    // Kapsayıcıyı aktif yap
    container.classList.add("cc-welcome-active");

    // Motoru başlat (canvas oluşturur, durumu sıfırlar)
    var basarili = BY.motor.init(hedefId);
    if (!basarili) return;

    // Motoru çalıştır (oyun döngüsünü başlatır, alt sistemleri tetikler)
    BY.motor.baslat();

    // Etkileşimi başlat (motor çalıştıktan sonra, canvas hazır olunca)
    if (BY.etkilesim && BY.etkilesim.baslat) {
      BY.etkilesim.baslat();
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  KARŞILAMA EKRANI DURDUR
  // ════════════════════════════════════════════════════════════════════════

  function karsilamaDurdur() {
    // Motoru durdur (animasyon döngüsünü iptal eder)
    BY.motor.durdur();

    // Etkileşim dinleyicilerini temizle
    if (BY.etkilesim && BY.etkilesim.temizle) {
      BY.etkilesim.temizle();
    }

    // Canvas'ı kapsayıcıdan kaldır
    var state = BY.state;
    if (state.canvas && state.canvas.parentElement) {
      state.canvas.parentElement.removeChild(state.canvas);
      state.canvas = null;
      state.ctx = null;
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  TEMA GÜNCELLEME
  // ════════════════════════════════════════════════════════════════════════

  function temaGuncelle(karakterId, aksanRenk) {
    // Geçerli bir karakter kimliği verilmişse ilgili renk paletini kullan
    if (karakterId && BY.config.KARAKTER_RENKLERI[karakterId]) {
      BY.state.temaRenk = BY.config.KARAKTER_RENKLERI[karakterId].ana;
    } else if (aksanRenk) {
      BY.state.temaRenk = aksanRenk;
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  GLOBAL FONKSİYONLAR (claude_code.js ile uyumluluk)
  // ════════════════════════════════════════════════════════════════════════

  window.ccStartWelcome = function(containerId) {
    karsilamaBaslat(containerId);
  };

  window.ccStopWelcome = function() {
    karsilamaDurdur();
  };

  window.ccUpdateWelcomeTheme = function(karakterId, aksanRenk) {
    temaGuncelle(karakterId, aksanRenk);
  };

  // ════════════════════════════════════════════════════════════════════════
  //  SHINY MESAJ İŞLEYİCİLERİ VE SEKME DEĞİŞİM TESPİTİ
  // ════════════════════════════════════════════════════════════════════════

  if (typeof Shiny !== "undefined") {

    // Karşılama ekranını başlat
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
        // Claude Code sekmesine geçildi
        setTimeout(function() {
          var container = document.getElementById("claude_code_module-welcome_screen");
          if (container && container.classList.contains("cc-welcome-active")) {
            // Zaten aktifse ama motor durmuşsa yeniden başlat
            if (!BY.state.calisiyor) {
              karsilamaBaslat();
            }
          }
        }, 300);
      } else {
        // Başka sekmeye geçildi - motoru duraksat (bellek tasarrufu)
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
