// www/js/bilge_yolac_fizik.js
// Bilge Yolaç fizik motoru: yerçekimi, sürtünme, platform çarpışması, mermi güncelleme, AABB çarpışma tespiti

(function() {
  "use strict";

  var BY = window.BilgeYolac;
  if (!BY) return;

  var config = BY.config;
  var state = BY.state;

  // ── Fizik modülü ──────────────────────────────────────────────────────────
  BY.fizik = {

    // Alt sistem başlatma (gerektiğinde platformları yükle)
    baslat: function() {
      // Fizik sistemi başlatıldığında özel bir işlem gerekmez
      // Platformlar seviye modülü tarafından yüklenir
    },

    // Her kare çağrılan güncelleme döngüsü
    guncelle: function() {
      // Mermileri güncelle ve çarpışma kontrolü yap
      this.mermileriGuncelle();
    },

    // Boyut değişiminde yeniden hesaplama
    boyutGuncelle: function() {
      // zeminY motor tarafından güncellenir, ek işlem gerekmez
    },

    // ── Yerçekimi ve sürtünme uygula ──────────────────────────────────────
    // Verilen varlığın hız ve konumunu fizik kurallarına göre günceller
    yercegimiUygula: function(varlik) {
      if (!varlik) return;

      // Dikey hıza yerçekimi ekle
      varlik.hizY = (varlik.hizY || 0) + config.YERCEKIM;

      // Yatay hıza sürtünme uygula
      varlik.hizX = (varlik.hizX || 0) * config.SURTUNME;

      // Çok küçük yatay hızları sıfırla (titreşimi önle)
      if (Math.abs(varlik.hizX) < 0.01) {
        varlik.hizX = 0;
      }

      // Konumu hıza göre güncelle
      varlik.x += varlik.hizX;
      varlik.y += varlik.hizY;
    },

    // ── Platform ve zemin çarpışma kontrolü ────────────────────────────────
    // Varlığın platformlara ve zemine çarpışmasını kontrol eder
    // Çarpışma varsa konumu düzeltir ve hızı sıfırlar
    platformCarpisma: function(varlik) {
      if (!varlik) return { zemindeMi: false };

      var zemindeMi = false;
      var vGen = varlik.genislik || 16;
      var vYuk = varlik.yukseklik || 16;
      var zeminSeviyesi = state.zeminY;

      // Varlığın alt kenarı
      var altKenar = varlik.y + vYuk;

      // 1. Zemin çarpışma kontrolü
      if (altKenar >= zeminSeviyesi) {
        varlik.y = zeminSeviyesi - vYuk;
        varlik.hizY = 0;
        zemindeMi = true;
      }

      // 2. Platform çarpışma kontrolü
      var platformlar = state.platformlar;
      if (platformlar && platformlar.length > 0) {
        for (var i = 0; i < platformlar.length; i++) {
          var p = platformlar[i];

          // Varlığın yatay olarak platformla örtüşüp örtüşmediğini kontrol et
          var varlikSag = varlik.x + vGen;
          var varlikSol = varlik.x;
          var platSag = p.x + p.genislik;
          var platSol = p.x;

          // Yatay örtüşme var mı?
          if (varlikSag <= platSol || varlikSol >= platSag) continue;

          // Önceki karedeki alt kenar (hızı çıkararak tahmin et)
          var oncekiAlt = altKenar - (varlik.hizY || 0);

          // Yukarıdan aşağıya düşerek platforma çarptı mı?
          if (oncekiAlt <= p.y && altKenar >= p.y) {
            varlik.y = p.y - vYuk;
            varlik.hizY = 0;
            zemindeMi = true;
            break; // İlk çarpışan platformda dur
          }
        }
      }

      varlik.zemindeMi = zemindeMi;
      return { zemindeMi: zemindeMi };
    },

    // ── AABB kutu çarpışma kontrolü ────────────────────────────────────────
    // İki dikdörtgenin kesişip kesişmediğini kontrol eder
    kutucukCarpisma: function(a, b) {
      if (!a || !b) return false;

      var aGen = a.genislik || 16;
      var aYuk = a.yukseklik || 16;
      var bGen = b.genislik || 16;
      var bYuk = b.yukseklik || 16;

      return (
        a.x < b.x + bGen &&
        a.x + aGen > b.x &&
        a.y < b.y + bYuk &&
        a.y + aYuk > b.y
      );
    },

    // ── Mermi güncelleme ve çarpışma kontrolü ──────────────────────────────
    // Tüm mermilerin konumunu günceller, süresi dolmuş olanları kaldırır,
    // çarpışma kontrolü yapar
    mermileriGuncelle: function() {
      var mermiler = state.mermiler;
      if (!mermiler || mermiler.length === 0) return;

      var kalacaklar = [];

      for (var i = 0; i < mermiler.length; i++) {
        var m = mermiler[i];

        // Konumu güncelle
        m.x += (m.hizX || 0);
        m.y += (m.hizY || 0);

        // Yaşam süresini azalt
        m.yasam = (m.yasam || 0) - 1;

        // Süresi dolduysa veya dünya dışına çıktıysa kaldır
        if (m.yasam <= 0) continue;
        if (m.x < -100 || m.x > state.dunyaGenislik + 100) continue;
        if (m.y < -100 || m.y > state.canvasYukseklik + 100) continue;

        var mGen = m.genislik || 4;
        var mYuk = m.yukseklik || 4;
        var carpitiMi = false;

        // Takım mermisi → düşmanlara çarpışma kontrolü
        if (m.sahip === "takim") {
          var dusmanlar = state.dusmanlar;
          if (dusmanlar) {
            for (var j = 0; j < dusmanlar.length; j++) {
              var d = dusmanlar[j];
              if (!d || d.can <= 0) continue;

              if (this.kutucukCarpisma(
                { x: m.x, y: m.y, genislik: mGen, yukseklik: mYuk },
                { x: d.x, y: d.y, genislik: d.genislik || 24, yukseklik: d.yukseklik || 24 }
              )) {
                // Düşmana hasar ver
                d.can -= (m.hasar || 5);
                carpitiMi = true;

                // Çarpışma parçacık efekti oluştur
                if (BY.efektler && typeof BY.efektler.parcacikEkle === "function") {
                  BY.efektler.parcacikEkle(m.x, m.y, m.renk || "#FFFFFF", 3);
                }

                break;
              }
            }
          }
        }

        // Düşman mermisi → takım karakterlerine çarpışma kontrolü
        if (m.sahip === "dusman" && !carpitiMi) {
          var karakterler = state.karakterler;
          if (karakterler) {
            for (var k = 0; k < karakterler.length; k++) {
              var kar = karakterler[k];
              if (!kar || (kar.can !== undefined && kar.can <= 0)) continue;

              if (this.kutucukCarpisma(
                { x: m.x, y: m.y, genislik: mGen, yukseklik: mYuk },
                { x: kar.x, y: kar.y, genislik: kar.genislik || 32, yukseklik: kar.yukseklik || 32 }
              )) {
                // Takıma hasar ver
                state.takimCan = Math.max(0, state.takimCan - (m.hasar || 3));
                carpitiMi = true;

                // Çarpışma parçacık efekti
                if (BY.efektler && typeof BY.efektler.parcacikEkle === "function") {
                  BY.efektler.parcacikEkle(m.x, m.y, "#FF4444", 3);
                }

                break;
              }
            }
          }
        }

        // Çarpışmadıysa mermiyi koru
        if (!carpitiMi) {
          kalacaklar.push(m);
        }
      }

      state.mermiler = kalacaklar;
    },

    // ── Ekran/dünya sınır kontrolü ─────────────────────────────────────────
    // Varlığı dünya sınırları içinde tutar
    ekranSinirlariKontrol: function(varlik) {
      if (!varlik) return;

      // Yatay sınırlama: dünya genişliği içinde kal
      if (varlik.x < 0) {
        varlik.x = 0;
        varlik.hizX = 0;
      }

      var maxX = state.dunyaGenislik;
      var vGen = varlik.genislik || 16;
      if (varlik.x + vGen > maxX) {
        varlik.x = maxX - vGen;
        varlik.hizX = 0;
      }

      // Dikey sınırlama: canvas yüksekliği içinde kal
      if (varlik.y < 0) {
        varlik.y = 0;
        varlik.hizY = 0;
      }

      var maxY = state.canvasYukseklik;
      var vYuk = varlik.yukseklik || 16;
      if (varlik.y + vYuk > maxY) {
        varlik.y = maxY - vYuk;
        varlik.hizY = 0;
      }
    }
  };

})();