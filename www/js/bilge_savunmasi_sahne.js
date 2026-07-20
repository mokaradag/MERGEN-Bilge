// www/js/bilge_savunmasi_sahne.js
// Bilge Savunması sahne destek katmanı: tam ekran yönetimi, oyun müzik
// gruplarının (menü/seviye) orkestrasyonu, koşu içi öğretici metinleri ve
// plan (blueprint) rehber paneli. bilge_savunmasi_uygulama.js bu katmana
// delege eder; burada oyun durumu OKUNUR ama koşu yaşam döngüsü yönetilmez.

(function() {
  "use strict";

  var BS = window.BilgeSavunmasi = window.BilgeSavunmasi || {};

  BS.sahne = {

    // ── Tam ekran ─────────────────────────────────────────────────────────────
    tamEkranMi: function() {
      return !!(document.fullscreenElement || document.webkitFullscreenElement);
    },

    tamEkranDegistir: function(hedef) {
      try {
        if (BS.sahne.tamEkranMi()) {
          var cikis = document.exitFullscreen || document.webkitExitFullscreen;
          if (cikis) {
            var cikisSoz = cikis.call(document);
            if (cikisSoz && cikisSoz.catch) cikisSoz.catch(function() {});
          }
          return;
        }
        if (!hedef) return;
        var iste = hedef.requestFullscreen || hedef.webkitRequestFullscreen;
        if (iste) {
          var soz = iste.call(hedef);
          if (soz && soz.catch) soz.catch(function() {});
        }
      } catch (hata) { /* tam ekran desteklenmiyorsa sessiz kal */ }
    },

    // Tam ekran değişimlerini dinle (bir kez kur; geri çağrı boyutlandırır).
    tamEkranDinle: function(geriCagri) {
      if (BS.sahne._tamEkranDinliyor) return;
      BS.sahne._tamEkranDinliyor = true;
      ["fullscreenchange", "webkitfullscreenchange"].forEach(function(ad) {
        document.addEventListener(ad, function() {
          try { geriCagri(); } catch (hata) { /* yoksay */ }
        });
      });
    },

    // ── Müzik orkestrasyonu ───────────────────────────────────────────────────
    menuMuzigi: function() {
      BS.ses.muzikCal("menu");
    },

    seviyeMuzigi: function(harita) {
      BS.ses.muzikCal((harita && harita.muzikGrubu) || "bolum_1");
    },

    // ── Öğretici (yalnızca ilk harita, ilerleme yokken) ───────────────────────
    ogreticiGerekliMi: function() {
      var veri = BS.veri.init;
      var kosu = BS.uygulama && BS.uygulama.kosu;
      return kosu && kosu.sim.durum.haritaId === "baglam_kapisi" &&
        (!veri.kampanya || veri.kampanya.length === 0);
    },

    ogreticiIlerlet: function(asama) {
      if (!BS.sahne.ogreticiGerekliMi()) return;
      var kosu = BS.uygulama.kosu;
      var metinler = {
        baslangic: "Alttaki karttan bir savunucu ya da kule seç ve rotanın " +
          "yanına yerleştir. Emre dengeli bir başlangıçtır.",
        yerlestirildi: "Harika! Dalga başlayınca tehditler soldan çekirdeğe " +
          "akar. Hazır olunca dalgayı başlat.",
        dalga2: "Kaynak biriktikçe savunucuya/kuleye tıklayıp Yükselt ile " +
          "güçlendir; Q ile yetenek kullan. Kuleler (6-8) kalabalığı yönetir."
      };
      if (metinler[asama] && kosu.ogreticiAdimi !== asama) {
        kosu.ogreticiAdimi = asama;
        kosu.hud.ogreticiGoster(metinler[asama]);
        setTimeout(function() {
          if (BS.uygulama.kosu === kosu) kosu.hud.ogreticiGoster(null);
        }, 9000);
      }
    },

    // ── Kule olay bağlayıcıları (bir kez; uygulama orkestratörü tetikler) ─────
    kuleOlaylariniBagla: function() {
      if (BS.sahne._kuleOlaylariBagli) return;
      BS.sahne._kuleOlaylariBagli = true;

      function aktifKosu() {
        return BS.uygulama ? BS.uygulama.kosu : null;
      }

      // Kule kartı/kısayolu: yerleşim modunu aç-kapat (kahraman modunu temizler).
      BS.olaylar.ekle("girdi-kule-kisayol", function(veri) {
        var kosu = aktifKosu();
        if (!kosu || !BS.denge.kuleAl(veri.kule)) return;
        kosu.arayuz.yerlesimKahraman = null;
        kosu.arayuz.seciliKahraman = null;
        kosu.arayuz.seciliKule = null;
        kosu.arayuz.yerlesimKule =
          kosu.arayuz.yerlesimKule === veri.kule ? null : veri.kule;
        kosu.hud.secimGuncelle();
      });

      BS.olaylar.ekle("girdi-kule-yerlestir", function(veri) {
        var kosu = aktifKosu();
        if (!kosu) return;
        var sonucYer = kosu.sim.kuleYerlestir(veri.kule, veri.x, veri.y);
        if (sonucYer.tamam) {
          kosu.arayuz.yerlesimKule = null;
          kosu.arayuz.seciliKule = sonucYer.kuleNo;
          kosu.hud.secimGuncelle();
          BS.ses.efekt("yerlestir");
          BS.sahne.ogreticiIlerlet("yerlestirildi");
        } else if (sonucYer.neden === "kaynak") {
          kosu.hud.ogreticiGoster("Yeterli kaynak yok.");
          setTimeout(function() {
            if (aktifKosu() === kosu) kosu.hud.ogreticiGoster(null);
          }, 2500);
        }
      });

      BS.olaylar.ekle("hud-kule-yukselt", function(veri) {
        var kosu = aktifKosu();
        if (!kosu) return;
        if (kosu.sim.kuleYukselt(veri.kule).tamam) {
          BS.ses.efekt("yukselt");
          kosu.hud.secimGuncelle();
        }
      });

      BS.olaylar.ekle("hud-kule-sat", function(veri) {
        var kosu = aktifKosu();
        if (!kosu) return;
        if (kosu.sim.kuleSat(veri.kule).tamam) {
          kosu.arayuz.seciliKule = null;
          kosu.hud.secimGuncelle();
        }
      });
    },

    // ── Plan (blueprint) rehber paneli ────────────────────────────────────────
    planRehberiKur: function(kosu, yan) {
      if (!kosu || !kosu.planBilgi || !yan) return;
      var plan = kosu.planBilgi;
      var sonuc = plan.yaratici_sonucu || {};
      var yerlesimler = (plan.plan && plan.plan.yerlesimler) || [];

      var bolum = document.createElement("div");
      bolum.className = "bs-yan-bolum bs-plan-rehberi";
      bolum.innerHTML = '<h4 class="bs-yan-baslik">Plan Rehberi</h4>' +
        '<p class="bs-yan-notu">' + BS.yardimci.htmlKacis(plan.baslik || "") +
        ' · Hedef: ' + BS.yardimci.sayiBicimle(sonuc.puan || 0) + ' puan</p>' +
        '<ul class="bs-plan-zaman-cizelgesi">' +
        yerlesimler.map(function(y) {
          return '<li data-bs-plan-dalga="' + y.dalga + '">D' + y.dalga + ": " +
            BS.yardimci.htmlKacis(y.kahraman) + " (" + y.x + "," + y.y +
            ") K" + y.seviye + '</li>';
        }).join("") + '</ul>';
      yan.appendChild(bolum);
    }
  };
})();
