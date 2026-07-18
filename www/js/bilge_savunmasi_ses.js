// www/js/bilge_savunmasi_ses.js
// Bilge Savunması ses katmanı. Sesler İSTEĞE BAĞLIDIR: yalnızca depoya konmuş
// yerel dosyalar (assets/bilge_savunmasi/ses/*) çalınır; dosya yoksa katman
// sessiz no-op olarak çalışır ve oyun tam deneyim sunmaya devam eder.
// Otomatik yüksek sesli çalma yoktur; ilk kullanıcı etkileşiminden önce hiçbir
// ses başlatılmaz (tarayıcı autoplay kurallarına saygı). Müzik ve efekt sesi
// ayrı ayarlanır; ayarlar kalıcıdır (köprü üzerinden profile yazılır).

(function() {
  "use strict";

  var BS = window.BilgeSavunmasi = window.BilgeSavunmasi || {};

  var durum = {
    muzikSeviyesi: 0.4,
    efektSeviyesi: 0.6,
    sessiz: true,            // varsayılan: kapalı; kullanıcı ayarıyla açılır
    etkilesimOldu: false,
    muzik: null,
    onbellek: {},            // ad -> Audio | false (yok)
    kokYol: "assets/bilge_savunmasi/ses/"
  };

  function dosyaAl(ad) {
    if (durum.onbellek[ad] !== undefined) return durum.onbellek[ad];
    try {
      var ses = new Audio(durum.kokYol + ad + ".mp3");
      ses.addEventListener("error", function() {
        durum.onbellek[ad] = false;   // dosya yok: kalıcı no-op
      });
      durum.onbellek[ad] = ses;
      return ses;
    } catch (hata) {
      durum.onbellek[ad] = false;
      return false;
    }
  }

  BS.ses = {

    etkilesimIsaretle: function() {
      durum.etkilesimOldu = true;
    },

    ayarla: function(ayarlar) {
      if (!ayarlar) return;
      if (typeof ayarlar.muzik === "number") {
        durum.muzikSeviyesi = BS.yardimci.kirp(ayarlar.muzik, 0, 1);
      }
      if (typeof ayarlar.efekt === "number") {
        durum.efektSeviyesi = BS.yardimci.kirp(ayarlar.efekt, 0, 1);
      }
      if (typeof ayarlar.sessiz === "boolean") {
        durum.sessiz = ayarlar.sessiz;
      }
      if (durum.muzik) {
        durum.muzik.volume = durum.sessiz ? 0 : durum.muzikSeviyesi;
      }
    },

    ayarlariAl: function() {
      return {
        muzik: durum.muzikSeviyesi,
        efekt: durum.efektSeviyesi,
        sessiz: durum.sessiz
      };
    },

    efekt: function(ad) {
      if (durum.sessiz || !durum.etkilesimOldu ||
          durum.efektSeviyesi <= 0) return;
      var ses = dosyaAl("efekt_" + ad);
      if (!ses) return;
      try {
        var kopya = ses.cloneNode();
        kopya.volume = durum.efektSeviyesi;
        var soz = kopya.play();
        if (soz && soz.catch) soz.catch(function() {});
      } catch (hata) { /* sessiz kal */ }
    },

    muzikBaslat: function() {
      if (durum.sessiz || !durum.etkilesimOldu || durum.muzik) return;
      var ses = dosyaAl("muzik_dongu");
      if (!ses) return;
      try {
        ses.loop = true;
        ses.volume = durum.muzikSeviyesi;
        var soz = ses.play();
        if (soz && soz.catch) soz.catch(function() {});
        durum.muzik = ses;
      } catch (hata) { /* sessiz kal */ }
    },

    muzikDurdur: function() {
      if (!durum.muzik) return;
      try {
        durum.muzik.pause();
        durum.muzik.currentTime = 0;
      } catch (hata) { /* yoksay */ }
      durum.muzik = null;
    },

    // Sayfadan ayrılırken tüm sesler durur.
    tumunuDurdur: function() {
      BS.ses.muzikDurdur();
    },

    // MERGEN Bilge arka fon müziğini owner tabanlı kısar/bırakır. Uygulamanın
    // MusicManager duck sözleşmesine saygı duyar; MusicManager yoksa no-op.
    uygulamaMuzigiKis: function() {
      if (window.MusicManager && typeof window.MusicManager.duck === "function") {
        window.MusicManager.duck("oyun");
      }
    },

    uygulamaMuzigiBirak: function() {
      if (window.MusicManager && typeof window.MusicManager.unduck === "function") {
        window.MusicManager.unduck("oyun");
      }
    }
  };
})();
