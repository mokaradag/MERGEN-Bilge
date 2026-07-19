// www/js/bilge_savunmasi_ses.js
// Bilge Savunması ses katmanı. Sesler İSTEĞE BAĞLIDIR: yalnızca depoya konmuş
// yerel dosyalar çalınır; dosya yoksa katman sessiz no-op olarak çalışır ve
// oyun tam deneyim sunmaya devam eder. Müzik listeleri sunucudan bs-init ile
// gelir (assets/bilge_savunmasi/muzik/<grup>/ klasörleri): "menu" ana menü
// teması, "bolum_1"/"bolum_2" seviye gruplarıdır; her gruptan rastgele parça
// seçilir ve parça bitince aynı gruptan yenisi çalınır. Otomatik yüksek sesli
// çalma yoktur; ilk kullanıcı etkileşiminden önce hiçbir ses başlatılmaz
// (tarayıcı autoplay kurallarına saygı). Müzik ve efekt sesi ayrı ayarlanır;
// ayarlar kalıcıdır (köprü üzerinden profile yazılır).

(function() {
  "use strict";

  var BS = window.BilgeSavunmasi = window.BilgeSavunmasi || {};

  var durum = {
    muzikSeviyesi: 0.4,
    efektSeviyesi: 0.6,
    sessiz: false,           // oyun sesi varsayılan açık; profil ayarı ezer
    etkilesimOldu: false,
    muzik: null,             // aktif müzik Audio nesnesi
    aktifGrup: null,         // çalan müzik grubu
    bekleyenGrup: null,      // etkileşim/ayar sonrası başlatılacak grup
    calmaListeleri: {},      // grup -> [url, ...] (sunucudan)
    sonCalinan: {},          // grup -> son çalınan url (ardışık tekrar azaltma)
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

  // Gruptan rastgele parça seç; birden fazla parça varsa son çalınanı atla.
  function parcaSec(grup) {
    var liste = durum.calmaListeleri[grup];
    if (!liste || !liste.length) return null;
    if (liste.length === 1) return liste[0];
    var aday;
    do {
      aday = liste[Math.floor(Math.random() * liste.length)];
    } while (aday === durum.sonCalinan[grup]);
    return aday;
  }

  // Grubun sıradaki parçasını başlat; parça yüklenemezse listeden düşür ve
  // sınırlı biçimde bir sonrakini dene (sonsuz hata döngüsü yok).
  function parcaCal(grup) {
    var url = parcaSec(grup);
    if (!url) {
      // Liste yok/boş: eski tekil döngü dosyası varsa onunla devam et.
      var eski = dosyaAl("muzik_dongu");
      if (!eski) return;
      try {
        eski.loop = true;
        eski.volume = durum.sessiz ? 0 : durum.muzikSeviyesi;
        var eskiSoz = eski.play();
        if (eskiSoz && eskiSoz.catch) eskiSoz.catch(function() {});
        durum.muzik = eski;
      } catch (hata) { /* sessiz kal */ }
      return;
    }

    try {
      var ses = new Audio(url);
      ses.volume = durum.sessiz ? 0 : durum.muzikSeviyesi;
      durum.muzik = ses;
      durum.aktifGrup = grup;
      durum.sonCalinan[grup] = url;

      ses.addEventListener("ended", function() {
        // Bayat parça koruması: yalnızca hâlâ aktif müzikse devam et.
        if (durum.muzik !== ses || durum.sessiz) return;
        parcaCal(grup);
      }, { once: true });

      ses.addEventListener("error", function() {
        if (durum.muzik !== ses) return;
        // Bozuk/eksik dosyayı listeden düşür; kalan varsa devam et.
        var liste = durum.calmaListeleri[grup] || [];
        durum.calmaListeleri[grup] = liste.filter(function(u) { return u !== url; });
        durum.muzik = null;
        if (durum.calmaListeleri[grup].length) parcaCal(grup);
      }, { once: true });

      var soz = ses.play();
      if (soz && soz.catch) {
        soz.catch(function() {
          // Autoplay engeli: ilk gerçek etkileşimde yeniden denenir.
          if (durum.muzik === ses) {
            durum.muzik = null;
            durum.bekleyenGrup = grup;
          }
        });
      }
    } catch (hata) { /* sessiz kal */ }
  }

  BS.ses = {

    etkilesimIsaretle: function() {
      durum.etkilesimOldu = true;
      // Autoplay engeli yüzünden bekleyen müzik varsa şimdi başlat.
      if (durum.bekleyenGrup && !durum.muzik && !durum.sessiz) {
        var grup = durum.bekleyenGrup;
        durum.bekleyenGrup = null;
        parcaCal(grup);
      }
    },

    // Sunucudan gelen grup -> url listeleri (bs-init "muzik" alanı).
    muzikListesiAyarla: function(listeler) {
      if (!listeler) return;
      Object.keys(listeler).forEach(function(grup) {
        var liste = listeler[grup];
        if (Object.prototype.toString.call(liste) === "[object Array]") {
          durum.calmaListeleri[grup] = liste.filter(function(u) {
            return typeof u === "string" && u.length > 0;
          });
        }
      });
    },

    // Verilen grubun müziğine geç (menü <-> seviye geçişleri).
    muzikCal: function(grup) {
      if (!grup) return;
      if (durum.aktifGrup === grup && durum.muzik) return;   // zaten çalıyor
      BS.ses.muzikDurdur();
      durum.aktifGrup = grup;
      if (durum.sessiz || !durum.etkilesimOldu) {
        durum.bekleyenGrup = grup;
        return;
      }
      durum.bekleyenGrup = null;
      parcaCal(grup);
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
        var acildi = durum.sessiz && !ayarlar.sessiz;
        durum.sessiz = ayarlar.sessiz;
        if (durum.sessiz) {
          // Ses kapatıldı: aktif grup hatırlanır, müzik durur.
          durum.bekleyenGrup = durum.aktifGrup || durum.bekleyenGrup;
          BS.ses.muzikDurdur();
          durum.aktifGrup = durum.bekleyenGrup;
        } else if (acildi && durum.etkilesimOldu && !durum.muzik) {
          var grup = durum.bekleyenGrup || durum.aktifGrup;
          durum.bekleyenGrup = null;
          if (grup) { durum.aktifGrup = grup; parcaCal(grup); }
        }
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

    // Geriye uyumluluk: grup listesi yoksa eski tekil döngü dosyası çalınır.
    muzikBaslat: function() {
      if (durum.muzik) return;
      BS.ses.muzikCal(durum.aktifGrup || durum.bekleyenGrup || "bolum_1");
    },

    muzikDurdur: function() {
      if (!durum.muzik) return;
      var ses = durum.muzik;
      durum.muzik = null;   // önce koparılır: ended/error geri çağrıları bayatlar
      try {
        ses.pause();
        ses.currentTime = 0;
      } catch (hata) { /* yoksay */ }
    },

    // Sayfadan ayrılırken tüm sesler durur; aktif grup dönüş için hatırlanır.
    tumunuDurdur: function() {
      durum.bekleyenGrup = durum.aktifGrup || durum.bekleyenGrup;
      BS.ses.muzikDurdur();
    },

    // Sayfaya dönüşte hatırlanan grubu kaldığı yerden başlat.
    muzikSurdur: function() {
      if (durum.muzik || durum.sessiz) return;
      var grup = durum.bekleyenGrup || durum.aktifGrup;
      if (!grup || !durum.etkilesimOldu) return;
      durum.bekleyenGrup = null;
      durum.aktifGrup = grup;
      parcaCal(grup);
    },

    // MERGEN Bilge arka fon müziğini owner tabanlı susturur/bırakır. "oyun"
    // sahibi, ses yaşam döngüsü katmanında TAM sessizlik uygular (oyun
    // sayfasında uygulama müziği hiç duyulmaz); MusicManager yoksa no-op.
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
