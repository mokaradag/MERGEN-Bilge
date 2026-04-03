// www/js/bilge_yolac_motor.js
// Bilge Yolaç oyun motoru: canvas yönetimi, kamera sistemi, oyun döngüsü,
// DPI ölçekleme, platform çizimi, seviye geçişleri ve giriş durumu.

(function() {
  "use strict";

  window.BilgeYolac = window.BilgeYolac || {};
  var BY = window.BilgeYolac;

  BY.config = {
    PIKSEL_BOYUT: 2,
    KARAKTER_BOYUT: 32,
    KARE_HIZI: 60,
    GECIS_SURESI: 2000,
    YERCEKIM: 0.4,
    SURTUNME: 0.85,
    ZEMIN_ORANI: 0.78,
    YILDIZ_SAYISI: 120,
    PARCACIK_SINIRI: 180,
    KAMERA_YUMUSAMA: 0.08,
    KAMERA_ONE_BAKIS: 70,
    KARAKTER_RENKLERI: {
      mergen:   { ana: "#7C4DFF", koyu: "#5B2FCF", acik: "#A47DFF", parlama: "rgba(124,77,255,0.3)" },
      ulgen:    { ana: "#2F6DF6", koyu: "#1A4DC0", acik: "#6B9BFF", parlama: "rgba(47,109,246,0.3)" },
      kayra:    { ana: "#2ECC71", koyu: "#1A9C54", acik: "#6EE89B", parlama: "rgba(46,204,113,0.3)" },
      erlik:    { ana: "#E74C3C", koyu: "#B53A2E", acik: "#F08070", parlama: "rgba(231,76,60,0.3)" },
      umay_ana: { ana: "#E98686", koyu: "#C05F5F", acik: "#F5ABAB", parlama: "rgba(233,134,134,0.3)" }
    },
    DUSMAN_RENKLERI: {
      drone:    { ana: "#00E5FF", koyu: "#0099AA", acik: "#66F0FF" },
      jammer:   { ana: "#FF6B00", koyu: "#CC5500", acik: "#FF9944" },
      sentinel: { ana: "#8844CC", koyu: "#6633AA", acik: "#AA66EE" },
      glitch:   { ana: "#FF0055", koyu: "#CC0044", acik: "#FF4488" },
      boss:     { ana: "#FFD700", koyu: "#CC9900", acik: "#FFE855" }
    }
  };

  function bosGirisDurumu() {
    return {
      sol: false,
      sag: false,
      yukari: false,
      asagi: false,
      bosluk: false,
      tikla: false,
      yukariTetik: false,
      asagiTetik: false,
      boslukTetik: false
    };
  }

  BY.state = {
    canvas: null,
    ctx: null,
    dpiOrani: 1,
    canvasGenislik: 0,
    canvasYukseklik: 0,
    zeminY: 0,

    calisiyor: false,
    animFrameId: null,
    kare: 0,
    sonKareZamani: 0,
    deltaZaman: 0,

    kameraX: 0,
    dunyaGenislik: 3500,

    mevcutSeviye: 0,
    oyunDurumu: "bekleme",

    karakterler: [],
    dusmanlar: [],
    mermiler: [],
    platformlar: [],
    parcaciklar: [],

    skor: 0,
    takimCan: 100,
    takimMaxCan: 100,

    gecisAktif: false,
    gecisIlerleme: 0,
    gecisBaslangic: 0,

    fareX: -1000,
    fareY: -1000,
    fareUzerinde: false,

    temaRenk: "#7C4DFF",
    containerId: null,
    yildizlar: [],

    giris: bosGirisDurumu(),
    aktifDunyaId: "mergen",
    takimYon: 1
  };

  BY.dunyaDanEkrana = function(wx, wy) {
    return { x: wx - BY.state.kameraX, y: wy };
  };

  function kameraGuncelle() {
    var state = BY.state;
    var config = BY.config;
    var karakterler = state.karakterler;
    if (!karakterler || karakterler.length === 0) return;

    var toplamX = 0;
    var toplamHizX = 0;
    var sayac = 0;

    for (var i = 0; i < karakterler.length; i++) {
      if (karakterler[i].can !== undefined && karakterler[i].can <= 0) continue;
      toplamX += karakterler[i].x;
      toplamHizX += (karakterler[i].hizX || 0);
      sayac++;
    }

    if (sayac === 0) return;

    var merkezX = toplamX / sayac;
    var ortHizX = toplamHizX / sayac;
    var oneBakis = ortHizX * config.KAMERA_ONE_BAKIS;
    var hedefX = merkezX + oneBakis - state.canvasGenislik * 0.35;

    state.kameraX += (hedefX - state.kameraX) * config.KAMERA_YUMUSAMA;

    if (state.kameraX < 0) state.kameraX = 0;
    var maxKamera = state.dunyaGenislik - state.canvasGenislik;
    if (maxKamera < 0) maxKamera = 0;
    if (state.kameraX > maxKamera) state.kameraX = maxKamera;
  }

  function platformlariCiz(ctx) {
    var state = BY.state;
    var platformlar = state.platformlar;
    if (!platformlar || platformlar.length === 0) return;

    var aksan = state.temaRenk || "#7C4DFF";

    for (var i = 0; i < platformlar.length; i++) {
      var p = platformlar[i];
      var ekranX = p.x - state.kameraX;
      var ekranY = p.y;

      if (ekranX + p.genislik < -50 || ekranX > state.canvasGenislik + 50) continue;

      ctx.save();

      var grad = ctx.createLinearGradient(ekranX, ekranY, ekranX, ekranY + p.yukseklik);
      grad.addColorStop(0, aksan);
      grad.addColorStop(1, "rgba(0,0,0,0.55)");
      ctx.fillStyle = grad;
      ctx.fillRect(ekranX, ekranY, p.genislik, p.yukseklik);

      ctx.shadowColor = aksan;
      ctx.shadowBlur = 6;
      ctx.strokeStyle = aksan;
      ctx.lineWidth = 1;
      ctx.strokeRect(ekranX, ekranY, p.genislik, p.yukseklik);

      ctx.shadowBlur = 0;
      ctx.strokeStyle = "rgba(255,255,255,0.25)";
      ctx.beginPath();
      ctx.moveTo(ekranX + 1, ekranY + 0.5);
      ctx.lineTo(ekranX + p.genislik - 1, ekranY + 0.5);
      ctx.stroke();

      ctx.restore();
    }
  }

  BY.motor = {
    init: function(containerId) {
      var state = BY.state;

      state.containerId = containerId;
      var container = document.getElementById(containerId);
      if (!container) return false;

      var eskiCanvas = container.querySelector(".bilge-yolac-canvas");
      if (eskiCanvas) container.removeChild(eskiCanvas);

      var canvas = document.createElement("canvas");
      canvas.className = "bilge-yolac-canvas";
      container.appendChild(canvas);

      state.canvas = canvas;
      state.ctx = canvas.getContext("2d");
      state.dpiOrani = window.devicePixelRatio || 1;

      state.kare = 0;
      state.sonKareZamani = 0;
      state.deltaZaman = 0;
      state.kameraX = 0;
      state.dunyaGenislik = 3500;
      state.mevcutSeviye = 0;
      state.oyunDurumu = "bekleme";
      state.karakterler = [];
      state.dusmanlar = [];
      state.mermiler = [];
      state.platformlar = [];
      state.parcaciklar = [];
      state.skor = 0;
      state.takimCan = 100;
      state.takimMaxCan = 100;
      state.gecisAktif = false;
      state.gecisIlerleme = 0;
      state.gecisBaslangic = 0;
      state.fareX = -1000;
      state.fareY = -1000;
      state.fareUzerinde = false;
      state.temaRenk = "#7C4DFF";
      state.yildizlar = [];
      state.giris = bosGirisDurumu();
      state.aktifDunyaId = "mergen";
      state.takimYon = 1;

      this.boyutAyarla();
      return true;
    },

    boyutAyarla: function() {
      var state = BY.state;
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
      state.zeminY = Math.floor(yukseklik * BY.config.ZEMIN_ORANI);

      var altSistemler = ["dunya", "karakterler", "fizik", "dusmanlar", "efektler", "arayuz"];
      for (var i = 0; i < altSistemler.length; i++) {
        var alt = BY[altSistemler[i]];
        if (alt && typeof alt.boyutGuncelle === "function") {
          try { alt.boyutGuncelle(); } catch (e) { console.warn("[BilgeYolac] Boyut güncelleme hatası:", e); }
        }
      }
    },

    baslat: function() {
      var state = BY.state;
      if (state.calisiyor) return;

      state.calisiyor = true;
      state.sonKareZamani = performance.now();
      state.oyunDurumu = "bekleme";

      var baslatSirasi = ["varliklar", "dunya", "karakterler", "fizik", "dusmanlar", "efektler", "arayuz", "oyun", "etkilesim"];
      for (var i = 0; i < baslatSirasi.length; i++) {
        var alt = BY[baslatSirasi[i]];
        if (alt && typeof alt.baslat === "function") {
          try { alt.baslat(); } catch (e) { console.warn("[BilgeYolac] Başlatma hatası:", e); }
        }
      }

      if (BY.seviye && typeof BY.seviye.yukle === "function") {
        try { BY.seviye.yukle(state.mevcutSeviye); } catch (e) { console.warn("[BilgeYolac] Seviye yükleme hatası:", e); }
      }

      var self = this;
      function dongu(zaman) {
        if (!state.calisiyor) return;

        state.deltaZaman = Math.min(zaman - state.sonKareZamani, 50);
        state.sonKareZamani = zaman;
        state.kare++;

        try { self.guncelle(zaman); } catch (e) { console.error("[BilgeYolac] Güncelleme hatası:", e); }
        try { self.ciz(); } catch (e) { console.error("[BilgeYolac] Çizim hatası:", e); }

        state.animFrameId = requestAnimationFrame(dongu);
      }

      state.animFrameId = requestAnimationFrame(dongu);
    },

    durdur: function() {
      var state = BY.state;
      state.calisiyor = false;
      if (state.animFrameId) {
        cancelAnimationFrame(state.animFrameId);
        state.animFrameId = null;
      }
    },

    guncelle: function(zaman) {
      var state = BY.state;

      if (state.gecisAktif) {
        var gecisGecen = zaman - state.gecisBaslangic;
        state.gecisIlerleme = Math.min(gecisGecen / BY.config.GECIS_SURESI, 1);

        if (state.gecisIlerleme >= 0.5 && !state._gecisYuklendi) {
          state._gecisYuklendi = true;
          var sonrakiSeviye = (state.mevcutSeviye + 1) % 5;
          state.mevcutSeviye = sonrakiSeviye;

          if (BY.seviye && typeof BY.seviye.yukle === "function") {
            BY.seviye.yukle(sonrakiSeviye);
          }

          if (BY.dunya && typeof BY.dunya.seviyeDegistir === "function") {
            BY.dunya.seviyeDegistir(sonrakiSeviye);
          }

          state.kameraX = 0;

          for (var i = 0; i < state.karakterler.length; i++) {
            state.karakterler[i].x = 60 + i * 40;
          }
        }

        if (state.gecisIlerleme >= 1) {
          state.gecisAktif = false;
          state.gecisIlerleme = 0;
          state._gecisYuklendi = false;
          state.oyunDurumu = "oynuyor";
        }
        return;
      }

      kameraGuncelle();

      var guncellemeSirasi = ["dunya", "fizik", "karakterler", "dusmanlar", "efektler", "oyun", "arayuz", "etkilesim"];
      for (var j = 0; j < guncellemeSirasi.length; j++) {
        var alt = BY[guncellemeSirasi[j]];
        if (alt && typeof alt.guncelle === "function") {
          try { alt.guncelle(zaman); } catch (e) { console.warn("[BilgeYolac] Güncelleme hatası:", e); }
        }
      }
    },

    ciz: function() {
      var state = BY.state;
      var ctx = state.ctx;
      if (!ctx) return;

      ctx.clearRect(0, 0, state.canvasGenislik, state.canvasYukseklik);

      if (BY.dunya && typeof BY.dunya.ciz === "function") BY.dunya.ciz(ctx);
      if (BY.efektler && typeof BY.efektler.cizArkaPlan === "function") BY.efektler.cizArkaPlan(ctx);

      platformlariCiz(ctx);

      if (BY.dusmanlar && typeof BY.dusmanlar.ciz === "function") BY.dusmanlar.ciz(ctx);
      if (BY.karakterler && typeof BY.karakterler.ciz === "function") BY.karakterler.ciz(ctx);
      if (BY.dunya && typeof BY.dunya.cizOnPlan === "function") BY.dunya.cizOnPlan(ctx);

      if (BY.efektler && typeof BY.efektler.cizOnPlan === "function") BY.efektler.cizOnPlan(ctx);
      if (BY.arayuz && typeof BY.arayuz.ciz === "function") BY.arayuz.ciz(ctx);

      if (state.gecisAktif) this.gecisEfektiCiz(ctx);
    },

    gecisEfektiCiz: function(ctx) {
      var state = BY.state;
      var ilerleme = state.gecisIlerleme;
      var opaklik = ilerleme < 0.5 ? ilerleme * 2 : (1 - ilerleme) * 2;

      ctx.save();
      ctx.fillStyle = "rgba(0, 0, 0, " + (opaklik * 0.9) + ")";
      ctx.fillRect(0, 0, state.canvasGenislik, state.canvasYukseklik);

      if (opaklik > 0.7) {
        var seviyeNo = state.mevcutSeviye + 1;
        var seviyeIsmi = "";
        if (BY.seviye && typeof BY.seviye.mevcutVeriAl === "function") {
          var veri = BY.seviye.mevcutVeriAl();
          if (veri && veri.isim) seviyeIsmi = " - " + veri.isim;
        }

        var alfa = (opaklik - 0.7) / 0.3;
        ctx.fillStyle = "rgba(255,255,255," + alfa + ")";
        ctx.font = "bold 20px monospace";
        ctx.textAlign = "center";
        ctx.fillText("Seviye " + seviyeNo + seviyeIsmi, state.canvasGenislik / 2, state.canvasYukseklik / 2);
      }
      ctx.restore();
    },

    gecisBaslat: function() {
      var state = BY.state;
      if (state.gecisAktif) return;
      state.gecisAktif = true;
      state.gecisBaslangic = performance.now();
      state.gecisIlerleme = 0;
      state._gecisYuklendi = false;
      state.oyunDurumu = "gecis";
    },

    yenidenBoyutlandir: function() {
      var self = this;
      if (this._boyutZamanlayici) clearTimeout(this._boyutZamanlayici);
      this._boyutZamanlayici = setTimeout(function() {
        self.boyutAyarla();
        if (BY.seviye && typeof BY.seviye.yukle === "function") {
          BY.seviye.yukle(BY.state.mevcutSeviye);
        }
      }, 150);
    }
  };

  window.addEventListener("resize", function() {
    if (BY.state.calisiyor) BY.motor.yenidenBoyutlandir();
  });

})();