// www/js/bilge_savunmasi_girdi.js
// Bilge Savunması girdi katmanı: fare, dokunmatik ve klavye denetimleri.
// Yerleştirme önizlemesi için imleç hücresini izler; tıklama/dokunma ile
// yerleştirme ve seçim yapar; klavye kısayolları (1-5 kahraman, Q yetenek,
// Boşluk duraklat, F hız, Esc iptal) sunar. Başarı hızlı tuşlamaya değil
// konumlandırma ve zamanlamaya dayanır. coz() tüm dinleyicileri kaldırır.

(function() {
  "use strict";

  var BS = window.BilgeSavunmasi = window.BilgeSavunmasi || {};

  BS.girdi = {

    bagla: function(cizici, sim, arayuz) {
      var tuval = cizici.tuval;
      var dinleyiciler = [];

      function ekle(hedef, ad, islev, secenek) {
        hedef.addEventListener(ad, islev, secenek || false);
        dinleyiciler.push({ hedef: hedef, ad: ad, islev: islev });
      }

      function hucreGuncelle(clientX, clientY) {
        var hucre = cizici.pikseldenHucre(clientX, clientY);
        arayuz.hucre = hucre;
        arayuz.hucreDurumu = sim.hucreDurumu(hucre.x, hucre.y);
      }

      function konumIsle(clientX, clientY) {
        hucreGuncelle(clientX, clientY);

        // Yerleştirme modu: uygun hücreye bırak.
        if (arayuz.yerlesimKahraman) {
          if (arayuz.hucreDurumu === "insa") {
            BS.olaylar.yay("girdi-yerlestir", {
              kahraman: arayuz.yerlesimKahraman,
              x: arayuz.hucre.x,
              y: arayuz.hucre.y
            });
          } else {
            BS.olaylar.yay("girdi-uyari", { neden: "hucre" });
          }
          return;
        }

        // Seçim: hücredeki kahramanı bul.
        var bulunan = null;
        Object.keys(sim.durum.kahramanlar).forEach(function(id) {
          var k = sim.durum.kahramanlar[id];
          if (k.yerlesik && k.x === arayuz.hucre.x && k.y === arayuz.hucre.y) {
            bulunan = id;
          }
        });
        arayuz.seciliKahraman = bulunan;
        BS.olaylar.yay("girdi-sec", { kahraman: bulunan });
      }

      ekle(tuval, "mousemove", function(e) {
        hucreGuncelle(e.clientX, e.clientY);
      });

      ekle(tuval, "click", function(e) {
        e.preventDefault();
        konumIsle(e.clientX, e.clientY);
      });

      ekle(tuval, "touchstart", function(e) {
        if (!e.touches || !e.touches.length) return;
        hucreGuncelle(e.touches[0].clientX, e.touches[0].clientY);
      }, { passive: true });

      ekle(tuval, "touchend", function(e) {
        if (!e.changedTouches || !e.changedTouches.length) return;
        e.preventDefault();
        konumIsle(e.changedTouches[0].clientX, e.changedTouches[0].clientY);
      });

      ekle(document, "keydown", function(e) {
        // Bir form alanındayken oyun kısayolları devreye girmez.
        var etiket = (e.target && e.target.tagName || "").toLowerCase();
        if (etiket === "input" || etiket === "textarea" || etiket === "select") {
          return;
        }

        var kahramanSirasi = ["emre", "selin", "deniz", "can", "ipek"];
        if (e.key >= "1" && e.key <= "5") {
          var id = kahramanSirasi[parseInt(e.key, 10) - 1];
          BS.olaylar.yay("girdi-kahraman-kisayol", { kahraman: id });
          e.preventDefault();
        } else if (e.key === " ") {
          BS.olaylar.yay("girdi-duraklat", {});
          e.preventDefault();
        } else if (e.key === "f" || e.key === "F") {
          BS.olaylar.yay("girdi-hiz", {});
          e.preventDefault();
        } else if (e.key === "q" || e.key === "Q") {
          if (arayuz.seciliKahraman) {
            BS.olaylar.yay("girdi-yetenek", { kahraman: arayuz.seciliKahraman });
            e.preventDefault();
          }
        } else if (e.key === "Escape") {
          if (arayuz.yerlesimKahraman) {
            arayuz.yerlesimKahraman = null;
            BS.olaylar.yay("girdi-iptal", {});
          } else {
            BS.olaylar.yay("girdi-menu", {});
          }
          e.preventDefault();
        }
      });

      return {
        coz: function() {
          dinleyiciler.forEach(function(kayit) {
            kayit.hedef.removeEventListener(kayit.ad, kayit.islev);
          });
          dinleyiciler = [];
        }
      };
    }
  };
})();
