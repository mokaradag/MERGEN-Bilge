// www/js/bilge_savunmasi_dalga.js
// Bilge Savunması dalga denetleyicisi: harita dalga planlarını deterministik
// (tohumlu) doğuş programlarına genişletir, zorluk/değiştirici ölçeklerini
// uygular, patron dalgası kuralını taşır ve dalga önizleme özetleri üretir.
// Patron kuralı sunucu (R) tarafıyla birebir aynıdır: her 4. dalga ve son
// dalga patron dalgasıdır.

(function() {
  "use strict";

  var BS = window.BilgeSavunmasi = window.BilgeSavunmasi || {};

  BS.dalga = {

    patronDalgasiMi: function(dalgaNo, dalgaSayisi) {
      return (dalgaNo % 4 === 0) || (dalgaNo === dalgaSayisi);
    },

    // Tek dalganın doğuş programını üretir: [{ dusmanId, patronMu, yolIndex,
    // gecikme }] — gecikmeler dalga başından itibaren saniyedir.
    dalgaProgrami: function(harita, dalgaNo, zorluk, rng, degistirici) {
      var plan = harita.dalgaPlani[dalgaNo - 1] || [];
      var sayiCarpani = 1;
      if (degistirici && BS.denge.degistiriciler[degistirici] &&
          BS.denge.degistiriciler[degistirici].sayiCarpani) {
        sayiCarpani = BS.denge.degistiriciler[degistirici].sayiCarpani;
      }

      var girisler = [];
      var zamanImleci = 0;

      plan.forEach(function(grup) {
        var patronMu = grup.dusman.indexOf("patron:") === 0;
        var dusmanId = patronMu ? grup.dusman.slice(7) : grup.dusman;
        var adet = grup.adet;
        if (!patronMu) {
          adet = Math.max(1, Math.round(adet * sayiCarpani));
        }

        var tanim = BS.denge.dusmanAl(dusmanId);
        if (!tanim) return;

        for (var i = 0; i < adet; i++) {
          var aralik = patronMu ? 2.5 : (tanim.ozellik === "surulu" ? 0.35 : 0.8);
          zamanImleci += aralik + rng.aralik(0, 0.3);
          girisler.push({
            dusmanId: dusmanId,
            patronMu: patronMu,
            yolIndex: harita.yollar.length > 1
              ? rng.tamsayi(0, harita.yollar.length - 1)
              : 0,
            gecikme: zamanImleci
          });
        }
      });

      // Toplam giriş sayısı sunucu doğrulama sınırıyla uyumlu kalmalıdır.
      return girisler;
    },

    // Koşunun tamamı için deterministik dalga programları (tembel değil,
    // koşu başında bir kez üretilir; determinizmi netleştirir).
    kosuPlani: function(harita, zorluk, tohum, degistirici) {
      var rng = BS.rng.olustur(tohum);
      var dalgalar = [];
      for (var d = 1; d <= harita.dalgaSayisi; d++) {
        dalgalar.push({
          dalgaNo: d,
          patronMu: BS.dalga.patronDalgasiMi(d, harita.dalgaSayisi),
          girisler: BS.dalga.dalgaProgrami(harita, d, zorluk, rng, degistirici)
        });
      }
      return dalgalar;
    },

    // Önizleme: dalga kompozisyonunu tür bazında sayarak özetler.
    kompozisyonOzeti: function(dalgaKaydi) {
      var sayilar = {};
      (dalgaKaydi.girisler || []).forEach(function(giris) {
        if (!sayilar[giris.dusmanId]) {
          sayilar[giris.dusmanId] = { adet: 0, patronMu: giris.patronMu };
        }
        sayilar[giris.dusmanId].adet += 1;
      });

      return Object.keys(sayilar).map(function(id) {
        var tanim = BS.denge.dusmanAl(id) || { ad: id, renk: "#999" };
        return {
          id: id,
          ad: tanim.ad,
          renk: tanim.renk,
          adet: sayilar[id].adet,
          patronMu: sayilar[id].patronMu
        };
      });
    }
  };
})();
