// www/js/bilge_yolac_motor.js
// Bilge Yolaç oyun motoru: canvas yönetimi, oyun döngüsü, DPI, yeniden boyutlandırma, zamanlama, durum makinesi

(function() {
  "use strict";

  // Ana ad alanı oluştur
  window.BilgeYolac = window.BilgeYolac || {};

  // Paylasilan yapilandirma
  window.BilgeYolac.config = {
    PIKSEL_BOYUT: 3,
    KARAKTER_BOYUT: 16,
    KARE_HIZI: 60,
    SEVIYE_SURESI: 45000,        // 45 saniye
    GECIS_SURESI: 2000,          // 2 saniye gecis
    YERCEKIM: 0.3,
    SURTUNME: 0.85,
    ZEMIN_ORANI: 0.78,           // Canvas yuksekliginin %78'i zemin seviyesi
    YILDIZ_SAYISI: 120,
    PARCACIK_SINIRI: 80,
    KARAKTER_RENKLERI: {
      mergen:   { ana: "#7C4DFF", koyu: "#5B2FCF", acik: "#A47DFF", parlama: "rgba(124,77,255,0.3)" },
      ulgen:    { ana: "#2F6DF6", koyu: "#1A4DC0", acik: "#6B9BFF", parlama: "rgba(47,109,246,0.3)" },
      kayra:    { ana: "#2ECC71", koyu: "#1A9C54", acik: "#6EE89B", parlama: "rgba(46,204,113,0.3)" },
      erlik:    { ana: "#E74C3C", koyu: "#B53A2E", acik: "#F08070", parlama: "rgba(231,76,60,0.3)" },
      umay_ana: { ana: "#E98686", koyu: "#C05F5F", acik: "#F5ABAB", parlama: "rgba(233,134,134,0.3)" }
    }
  };

  // Paylaşılan değiştirilebilir durum
  window.BilgeYolac.state = {
    canvas: null,
    ctx: null,
    calisiyor: false,
    animFrameId: null,
    mevcutSeviye: 0,
    kare: 0,
    sonKareZamani: 0,
    deltaZaman: 0,
    seviyeBaslangic: 0,
    gecisAktif: false,
    gecisIlerleme: 0,
    gecisBaslangic: 0,
    containerId: null,
    dpiOrani: 1,
    canvasGenislik: 0,
    canvasYukseklik: 0,
    zeminY: 0,
    karakterler: [],
    yildizlar: [],
    parcaciklar: [],
    fareX: -1000,
    fareY: -1000,
    fareUzerinde: false,
    temaRenk: "#7C4DFF",
    oyunDurumu: "bekleme"  // bekleme, oynuyor, gecis, zafer
  };

  // Motor fonksiyonları
  window.BilgeYolac.motor = {

    // Canvas başlat
    init: function(containerId) {
      var state = window.BilgeYolac.state;
      var config = window.BilgeYolac.config;

      state.containerId = containerId;
      var container = document.getElementById(containerId);
      if (!container) return false;

      // Eski canvas varsa temizle
      var eskiCanvas = container.querySelector(".bilge-yolac-canvas");
      if (eskiCanvas) {
        container.removeChild(eskiCanvas);
      }

      // Yeni canvas oluştur
      var canvas = document.createElement("canvas");
      canvas.className = "bilge-yolac-canvas";
      container.appendChild(canvas);

      state.canvas = canvas;
      state.ctx = canvas.getContext("2d");
      state.dpiOrani = window.devicePixelRatio || 1;

      this.boyutAyarla();

      // Oyun durumunu sıfırla
      state.kare = 0;
      state.mevcutSeviye = 0;
      state.seviyeBaslangic = 0;
      state.gecisAktif = false;
      state.oyunDurumu = "bekleme";
      state.parcaciklar = [];

      return true;
    },

    // Canvas boyutlarını ayarla
    boyutAyarla: function() {
      var state = window.BilgeYolac.state;
      var canvas = state.canvas;
      if (!canvas) return;

      var container = canvas.parentElement;
      if (!container) return;

      var genislik = container.clientWidth;
      var yukseklik = container.clientHeight;
      var dpi = state.dpiOrani;

      canvas.width = genislik * dpi;
      canvas.height = yukseklik * dpi;
      canvas.style.width = genislik + "px";
      canvas.style.height = yukseklik + "px";

      state.ctx.setTransform(dpi, 0, 0, dpi, 0, 0);
      state.canvasGenislik = genislik;
      state.canvasYukseklik = yukseklik;
      state.zeminY = Math.floor(yukseklik * window.BilgeYolac.config.ZEMIN_ORANI);
    },

    // Ana oyun döngüsünü başlat
    baslat: function() {
      var state = window.BilgeYolac.state;
      if (state.calisiyor) return;

      state.calisiyor = true;
      state.sonKareZamani = performance.now();
      state.seviyeBaslangic = performance.now();
      state.oyunDurumu = "oynuyor";

      // Alt sistemleri başlat
      if (window.BilgeYolac.karakterler && window.BilgeYolac.karakterler.baslat) {
        window.BilgeYolac.karakterler.baslat();
      }
      if (window.BilgeYolac.dunya && window.BilgeYolac.dunya.baslat) {
        window.BilgeYolac.dunya.baslat();
      }
      if (window.BilgeYolac.efektler && window.BilgeYolac.efektler.baslat) {
        window.BilgeYolac.efektler.baslat();
      }
      if (window.BilgeYolac.arayuz && window.BilgeYolac.arayuz.baslat) {
        window.BilgeYolac.arayuz.baslat();
      }
      if (window.BilgeYolac.oyun && window.BilgeYolac.oyun.baslat) {
        window.BilgeYolac.oyun.baslat();
      }

      var self = this;
      function dongu(zaman) {
        if (!state.calisiyor) return;
        state.deltaZaman = Math.min(zaman - state.sonKareZamani, 50);
        state.sonKareZamani = zaman;
        state.kare++;

        self.guncelle(zaman);
        self.ciz();

        state.animFrameId = requestAnimationFrame(dongu);
      }
      state.animFrameId = requestAnimationFrame(dongu);
    },

    // Oyun döngüsünü durdur
    durdur: function() {
      var state = window.BilgeYolac.state;
      state.calisiyor = false;
      if (state.animFrameId) {
        cancelAnimationFrame(state.animFrameId);
        state.animFrameId = null;
      }
    },

    // Güncelleme adımı
    guncelle: function(zaman) {
      var state = window.BilgeYolac.state;
      var config = window.BilgeYolac.config;

      // Seviye zamanlayicisi
      var seviyeGecenSure = zaman - state.seviyeBaslangic;

      if (!state.gecisAktif && seviyeGecenSure > config.SEVIYE_SURESI) {
        // Seviye geçişi başlat
        state.gecisAktif = true;
        state.gecisBaslangic = zaman;
        state.oyunDurumu = "gecis";
      }

      if (state.gecisAktif) {
        var gecisGecen = zaman - state.gecisBaslangic;
        state.gecisIlerleme = Math.min(gecisGecen / config.GECIS_SURESI, 1);

        if (state.gecisIlerleme >= 1) {
          // Sonraki seviyeye gec
          state.mevcutSeviye = (state.mevcutSeviye + 1) % 5;
          state.gecisAktif = false;
          state.gecisIlerleme = 0;
          state.seviyeBaslangic = zaman;
          state.oyunDurumu = "oynuyor";

          if (window.BilgeYolac.dunya && window.BilgeYolac.dunya.seviyeDegistir) {
            window.BilgeYolac.dunya.seviyeDegistir(state.mevcutSeviye);
          }
        }
      }

      // Alt sistemleri güncelle
      if (window.BilgeYolac.dunya && window.BilgeYolac.dunya.guncelle) {
        window.BilgeYolac.dunya.guncelle(zaman);
      }
      if (window.BilgeYolac.karakterler && window.BilgeYolac.karakterler.guncelle) {
        window.BilgeYolac.karakterler.guncelle(zaman);
      }
      if (window.BilgeYolac.efektler && window.BilgeYolac.efektler.guncelle) {
        window.BilgeYolac.efektler.guncelle(zaman);
      }
      if (window.BilgeYolac.oyun && window.BilgeYolac.oyun.guncelle) {
        window.BilgeYolac.oyun.guncelle(zaman);
      }
      if (window.BilgeYolac.arayuz && window.BilgeYolac.arayuz.guncelle) {
        window.BilgeYolac.arayuz.guncelle(zaman);
      }
    },

    // Çizim adımı
    ciz: function() {
      var state = window.BilgeYolac.state;
      var ctx = state.ctx;
      if (!ctx) return;

      // Canvas temizle
      ctx.clearRect(0, 0, state.canvasGenislik, state.canvasYukseklik);

      // Arka plan (dunya)
      if (window.BilgeYolac.dunya && window.BilgeYolac.dunya.ciz) {
        window.BilgeYolac.dunya.ciz(ctx);
      }

      // Efektler (arka plan katmani)
      if (window.BilgeYolac.efektler && window.BilgeYolac.efektler.cizArkaPlan) {
        window.BilgeYolac.efektler.cizArkaPlan(ctx);
      }

      // Karakterler
      if (window.BilgeYolac.karakterler && window.BilgeYolac.karakterler.ciz) {
        window.BilgeYolac.karakterler.ciz(ctx);
      }

      // Efektler (on plan katmani)
      if (window.BilgeYolac.efektler && window.BilgeYolac.efektler.cizOnPlan) {
        window.BilgeYolac.efektler.cizOnPlan(ctx);
      }

      // Arayuz (UI kaplama)
      if (window.BilgeYolac.arayuz && window.BilgeYolac.arayuz.ciz) {
        window.BilgeYolac.arayuz.ciz(ctx);
      }

      // Gecis efekti
      if (state.gecisAktif) {
        this.gecisEfektiCiz(ctx);
      }
    },

    // Seviye gecis efekti
    gecisEfektiCiz: function(ctx) {
      var state = window.BilgeYolac.state;
      var ilerleme = state.gecisIlerleme;

      // Fade out/in efekti
      var opaklik;
      if (ilerleme < 0.5) {
        opaklik = ilerleme * 2; // 0 -> 1
      } else {
        opaklik = (1 - ilerleme) * 2; // 1 -> 0
      }

      ctx.save();
      ctx.fillStyle = "rgba(0, 0, 0, " + (opaklik * 0.8) + ")";
      ctx.fillRect(0, 0, state.canvasGenislik, state.canvasYukseklik);
      ctx.restore();
    },

    // Yeniden boyutlandırma
    yenidenBoyutlandir: function() {
      var self = this;
      if (this._boyutZamanlayici) {
        clearTimeout(this._boyutZamanlayici);
      }
      this._boyutZamanlayici = setTimeout(function() {
        self.boyutAyarla();
        if (window.BilgeYolac.dunya && window.BilgeYolac.dunya.boyutGuncelle) {
          window.BilgeYolac.dunya.boyutGuncelle();
        }
        if (window.BilgeYolac.karakterler && window.BilgeYolac.karakterler.boyutGuncelle) {
          window.BilgeYolac.karakterler.boyutGuncelle();
        }
      }, 100);
    }
  };

  // Pencere boyut değişimi dinleyicisi
  window.addEventListener("resize", function() {
    if (window.BilgeYolac.state.calisiyor) {
      window.BilgeYolac.motor.yenidenBoyutlandir();
    }
  });

})();
