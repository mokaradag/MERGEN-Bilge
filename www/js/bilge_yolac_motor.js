// www/js/bilge_yolac_motor.js
// Bilge Yolaç oyun motoru: canvas yönetimi, kamera sistemi, oyun döngüsü, DPI ölçekleme, platform çizimi, seviye geçişleri

(function() {
  "use strict";

  // Ana ad alanı oluştur
  window.BilgeYolac = window.BilgeYolac || {};
  var BY = window.BilgeYolac;

  // ── Paylaşılan yapılandırma ────────────────────────────────────────────────
  BY.config = {
    PIKSEL_BOYUT: 2,
    KARAKTER_BOYUT: 32,
    KARE_HIZI: 60,
    GECIS_SURESI: 2000,            // 2 saniyelik seviye geçiş efekti
    YERCEKIM: 0.4,
    SURTUNME: 0.85,
    ZEMIN_ORANI: 0.78,             // Canvas yüksekliğinin %78'i zemin seviyesi
    YILDIZ_SAYISI: 120,
    PARCACIK_SINIRI: 150,
    KAMERA_YUMUSAMA: 0.06,         // Kamera takip yumuşatma katsayısı (lerp)

    // Her karakter için renk paleti
    KARAKTER_RENKLERI: {
      mergen:   { ana: "#7C4DFF", koyu: "#5B2FCF", acik: "#A47DFF", parlama: "rgba(124,77,255,0.3)" },
      ulgen:    { ana: "#2F6DF6", koyu: "#1A4DC0", acik: "#6B9BFF", parlama: "rgba(47,109,246,0.3)" },
      kayra:    { ana: "#2ECC71", koyu: "#1A9C54", acik: "#6EE89B", parlama: "rgba(46,204,113,0.3)" },
      erlik:    { ana: "#E74C3C", koyu: "#B53A2E", acik: "#F08070", parlama: "rgba(231,76,60,0.3)" },
      umay_ana: { ana: "#E98686", koyu: "#C05F5F", acik: "#F5ABAB", parlama: "rgba(233,134,134,0.3)" }
    },

    // Düşman tiplerinin renk paleti
    DUSMAN_RENKLERI: {
      drone:    { ana: "#00E5FF", koyu: "#0099AA", acik: "#66F0FF" },
      jammer:   { ana: "#FF6B00", koyu: "#CC5500", acik: "#FF9944" },
      sentinel: { ana: "#8844CC", koyu: "#6633AA", acik: "#AA66EE" },
      glitch:   { ana: "#FF0055", koyu: "#CC0044", acik: "#FF4488" },
      boss:     { ana: "#FFD700", koyu: "#CC9900", acik: "#FFE855" }
    }
  };

  // ── Paylaşılan değiştirilebilir durum ──────────────────────────────────────
  BY.state = {
    canvas: null,
    ctx: null,
    dpiOrani: 1,
    canvasGenislik: 0,
    canvasYukseklik: 0,
    zeminY: 0,

    // Oyun döngüsü zamanlaması
    calisiyor: false,
    animFrameId: null,
    kare: 0,
    sonKareZamani: 0,
    deltaZaman: 0,

    // Kamera – dünya koordinatlarında görüntü alanının sol kenarı
    kameraX: 0,

    // Dünya boyutları (mevcut seviye toplam genişliği)
    dunyaGenislik: 3500,

    // Seviye ve oyun durumu
    mevcutSeviye: 0,
    oyunDurumu: "bekleme",       // bekleme | oynuyor | boss | gecis | zafer

    // Varlık dizileri
    karakterler: [],
    dusmanlar: [],
    mermiler: [],
    platformlar: [],
    parcaciklar: [],

    // Skor ve takım sağlığı
    skor: 0,
    takimCan: 100,
    takimMaxCan: 100,

    // Seviye geçiş durumu
    gecisAktif: false,
    gecisIlerleme: 0,
    gecisBaslangic: 0,

    // Fare durumu
    fareX: -1000,
    fareY: -1000,
    fareUzerinde: false,

    // Tema rengi (mevcut seviye aksan rengi)
    temaRenk: "#7C4DFF",

    // Kapsayıcı element kimliği
    containerId: null,

    // Yıldız verileri (dünya tarafından doldurulur)
    yildizlar: []
  };

  // ── Yardımcı: dünya koordinatından ekran koordinatına ─────────────────────
  BY.dunyaDanEkrana = function(wx, wy) {
    return { x: wx - BY.state.kameraX, y: wy };
  };

  // ── Kamera güncelleme ─────────────────────────────────────────────────────
  function kameraGuncelle() {
    var state = BY.state;
    var config = BY.config;

    // Takımın merkez noktasını hesapla
    var karakterler = state.karakterler;
    if (!karakterler || karakterler.length === 0) return;

    var toplamX = 0;
    var toplamHizX = 0;
    var sayac = 0;
    for (var i = 0; i < karakterler.length; i++) {
      // Sadece hayatta olan karakterleri hesaba kat
      if (karakterler[i].can !== undefined && karakterler[i].can <= 0) continue;
      toplamX += karakterler[i].x;
      toplamHizX += (karakterler[i].hizX || 0);
      sayac++;
    }

    // Hiç hayatta karakter kalmadıysa kamerayı güncelleme
    if (sayac === 0) return;

    var merkezX = toplamX / sayac;
    var ortHizX = toplamHizX / sayac;

    // Hareket yönünde hafif öne bakış (lead)
    var oneBakis = ortHizX * 40;

    // Kameranın hedefi: takım merkezini ekranın yaklaşık 1/3'ünde tut
    var hedefX = merkezX + oneBakis - state.canvasGenislik * 0.35;

    // Yumuşak takip (lerp)
    state.kameraX += (hedefX - state.kameraX) * config.KAMERA_YUMUSAMA;

    // Kamerayı dünya sınırları içinde tut
    if (state.kameraX < 0) state.kameraX = 0;
    var maxKamera = state.dunyaGenislik - state.canvasGenislik;
    if (maxKamera < 0) maxKamera = 0;
    if (state.kameraX > maxKamera) state.kameraX = maxKamera;
  }

  // ── Platform çizimi ───────────────────────────────────────────────────────
  function platformlariCiz(ctx) {
    var state = BY.state;
    var platformlar = state.platformlar;
    if (!platformlar || platformlar.length === 0) return;

    // Mevcut seviye aksan rengini al
    var aksan = state.temaRenk || "#7C4DFF";

    for (var i = 0; i < platformlar.length; i++) {
      var p = platformlar[i];

      // Dünya koordinatından ekran koordinatına dönüştür
      var ekranX = p.x - state.kameraX;
      var ekranY = p.y;

      // Görüş alanı dışındaysa çizme
      if (ekranX + p.genislik < -50 || ekranX > state.canvasGenislik + 50) continue;

      ctx.save();

      // Hafif degrade dolgu
      var grad = ctx.createLinearGradient(ekranX, ekranY, ekranX, ekranY + p.yukseklik);
      grad.addColorStop(0, aksan);
      grad.addColorStop(1, "rgba(0,0,0,0.5)");
      ctx.fillStyle = grad;
      ctx.fillRect(ekranX, ekranY, p.genislik, p.yukseklik);

      // Kenar parlama efekti
      ctx.shadowColor = aksan;
      ctx.shadowBlur = 6;
      ctx.strokeStyle = aksan;
      ctx.lineWidth = 1;
      ctx.strokeRect(ekranX, ekranY, p.genislik, p.yukseklik);

      // Üst kenar vurgu çizgisi
      ctx.shadowBlur = 0;
      ctx.strokeStyle = "rgba(255,255,255,0.3)";
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(ekranX + 1, ekranY + 0.5);
      ctx.lineTo(ekranX + p.genislik - 1, ekranY + 0.5);
      ctx.stroke();

      ctx.restore();
    }
  }

  // ── Motor nesnesi ─────────────────────────────────────────────────────────
  BY.motor = {

    // Canvas'ı ve tüm durum özelliklerini ilk değerlerine döndür
    init: function(containerId) {
      var state = BY.state;

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

      // Durum özelliklerini sıfırla
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

      this.boyutAyarla();

      return true;
    },

    // Canvas boyutlarını güncelle ve zemin seviyesini hesapla
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

      // Alt sistemlerin boyut güncellemelerini tetikle
      var altSistemler = ["dunya", "karakterler", "fizik", "dusmanlar", "efektler", "arayuz"];
      for (var i = 0; i < altSistemler.length; i++) {
        var alt = BY[altSistemler[i]];
        if (alt && typeof alt.boyutGuncelle === "function") {
          try {
            alt.boyutGuncelle();
          } catch (e) {
            console.warn("[BilgeYolac] " + altSistemler[i] + " boyut güncelleme hatası:", e);
          }
        }
      }
    },

    // Oyun döngüsünü başlat – alt sistemleri sırasıyla tetikle
    baslat: function() {
      var state = BY.state;
      if (state.calisiyor) return;

      state.calisiyor = true;
      state.sonKareZamani = performance.now();
      state.oyunDurumu = "bekleme";

      // Alt sistemleri belirlenen sırayla başlat
      var baslatSirasi = ["dunya", "karakterler", "fizik", "dusmanlar", "efektler", "arayuz", "oyun", "etkilesim"];
      for (var i = 0; i < baslatSirasi.length; i++) {
        var alt = BY[baslatSirasi[i]];
        if (alt && typeof alt.baslat === "function") {
          try {
            alt.baslat();
          } catch (e) {
            console.warn("[BilgeYolac] " + baslatSirasi[i] + " başlatma hatası:", e);
          }
        }
      }

      // Seviye verilerini yükle
      if (BY.seviye && typeof BY.seviye.yukle === "function") {
        try {
          BY.seviye.yukle(state.mevcutSeviye);
        } catch (e) {
          console.warn("[BilgeYolac] Seviye yükleme hatası:", e);
        }
      }

      // Animasyon döngüsünü başlat
      var self = this;
      function dongu(zaman) {
        if (!state.calisiyor) return;

        // Delta zamanı hesapla, 50ms ile sınırla (fizik sıçramalarını önle)
        state.deltaZaman = Math.min(zaman - state.sonKareZamani, 50);
        state.sonKareZamani = zaman;
        state.kare++;

        // Güncelleme ve çizim adımlarını hata korumalı çalıştır
        try {
          self.guncelle(zaman);
        } catch (e) {
          console.error("[BilgeYolac] Güncelleme hatası:", e);
        }

        try {
          self.ciz();
        } catch (e) {
          console.error("[BilgeYolac] Çizim hatası:", e);
        }

        state.animFrameId = requestAnimationFrame(dongu);
      }

      state.animFrameId = requestAnimationFrame(dongu);
    },

    // Oyun döngüsünü durdur
    durdur: function() {
      var state = BY.state;
      state.calisiyor = false;
      if (state.animFrameId) {
        cancelAnimationFrame(state.animFrameId);
        state.animFrameId = null;
      }
    },

    // ── Güncelleme adımı ──────────────────────────────────────────────────
    guncelle: function(zaman) {
      var state = BY.state;

      // Seviye geçişi devam ediyorsa yalnızca geçiş güncelle
      if (state.gecisAktif) {
        var gecisGecen = zaman - state.gecisBaslangic;
        state.gecisIlerleme = Math.min(gecisGecen / BY.config.GECIS_SURESI, 1);

        // Tam kararmada (yarı noktada) yeni seviyeyi yükle
        if (state.gecisIlerleme >= 0.5 && !state._gecisYuklendi) {
          state._gecisYuklendi = true;
          var sonrakiSeviye = (state.mevcutSeviye + 1) % 5;
          state.mevcutSeviye = sonrakiSeviye;

          // Seviye verilerini yükle
          if (BY.seviye && typeof BY.seviye.yukle === "function") {
            BY.seviye.yukle(sonrakiSeviye);
          }

          // Dünya temasını güncelle
          if (BY.dunya && typeof BY.dunya.seviyeDegistir === "function") {
            BY.dunya.seviyeDegistir(sonrakiSeviye);
          }

          // Kamerayı sıfırla
          state.kameraX = 0;

          // Karakterleri başlangıç noktasına döndür
          for (var i = 0; i < state.karakterler.length; i++) {
            state.karakterler[i].x = 60 + i * 40;
          }
        }

        // Geçiş tamamlandı
        if (state.gecisIlerleme >= 1) {
          state.gecisAktif = false;
          state.gecisIlerleme = 0;
          state._gecisYuklendi = false;
          state.oyunDurumu = "oynuyor";
        }

        return; // Geçiş sırasında alt sistemleri güncelleme
      }

      // Kamerayı güncelle
      kameraGuncelle();

      // Alt sistemleri güncelle
      var guncellemeSirasi = ["dunya", "fizik", "karakterler", "dusmanlar", "efektler", "oyun", "arayuz", "etkilesim"];
      for (var i = 0; i < guncellemeSirasi.length; i++) {
        var alt = BY[guncellemeSirasi[i]];
        if (alt && typeof alt.guncelle === "function") {
          try {
            alt.guncelle(zaman);
          } catch (e) {
            console.warn("[BilgeYolac] " + guncellemeSirasi[i] + " güncelleme hatası:", e);
          }
        }
      }
    },

    // ── Çizim adımı ──────────────────────────────────────────────────────
    ciz: function() {
      var state = BY.state;
      var ctx = state.ctx;
      if (!ctx) return;

      // Canvas'ı temizle
      ctx.clearRect(0, 0, state.canvasGenislik, state.canvasYukseklik);

      // 1. Arka plan (gökyüzü, dağlar, zemin)
      if (BY.dunya && typeof BY.dunya.ciz === "function") {
        BY.dunya.ciz(ctx);
      }

      // 2. Arka plan efektleri (parçacıklar, izler vb.)
      if (BY.efektler && typeof BY.efektler.cizArkaPlan === "function") {
        BY.efektler.cizArkaPlan(ctx);
      }

      // 3. Platformları çiz
      platformlariCiz(ctx);

      // 4. Düşmanları çiz
      if (BY.dusmanlar && typeof BY.dusmanlar.ciz === "function") {
        BY.dusmanlar.ciz(ctx);
      }

      // 5. Karakterleri çiz
      if (BY.karakterler && typeof BY.karakterler.ciz === "function") {
        BY.karakterler.ciz(ctx);
      }

      // 6. Ön plan efektleri (hasar sayıları, parlamalar vb.)
      if (BY.efektler && typeof BY.efektler.cizOnPlan === "function") {
        BY.efektler.cizOnPlan(ctx);
      }

      // 7. Arayüz katmanı (skor, sağlık çubuğu, mini harita vb.)
      if (BY.arayuz && typeof BY.arayuz.ciz === "function") {
        BY.arayuz.ciz(ctx);
      }

      // 8. Seviye geçiş efekti (karartma/aydınlatma)
      if (state.gecisAktif) {
        this.gecisEfektiCiz(ctx);
      }
    },

    // Seviye geçişinde karartma/aydınlatma efekti çiz
    gecisEfektiCiz: function(ctx) {
      var state = BY.state;
      var ilerleme = state.gecisIlerleme;

      // İlk yarı: kararma (0→1), ikinci yarı: aydınlanma (1→0)
      var opaklik;
      if (ilerleme < 0.5) {
        opaklik = ilerleme * 2;
      } else {
        opaklik = (1 - ilerleme) * 2;
      }

      ctx.save();
      ctx.fillStyle = "rgba(0, 0, 0, " + (opaklik * 0.9) + ")";
      ctx.fillRect(0, 0, state.canvasGenislik, state.canvasYukseklik);

      // Geçiş metnini göster (tam kararmada)
      if (opaklik > 0.7) {
        var seviyeNo = state.mevcutSeviye + 1;
        var seviyeIsmi = "";

        // Seviye ismini al
        if (BY.seviye && typeof BY.seviye.mevcutVeriAl === "function") {
          var veri = BY.seviye.mevcutVeriAl();
          if (veri && veri.isim) seviyeIsmi = " - " + veri.isim;
        }

        var alfa = (opaklik - 0.7) / 0.3;
        ctx.fillStyle = "rgba(255, 255, 255, " + alfa + ")";
        ctx.font = "bold 20px monospace";
        ctx.textAlign = "center";
        ctx.fillText("Seviye " + seviyeNo + seviyeIsmi, state.canvasGenislik / 2, state.canvasYukseklik / 2);
      }

      ctx.restore();
    },

    // Seviye geçişini başlat
    gecisBaslat: function() {
      var state = BY.state;
      if (state.gecisAktif) return;
      state.gecisAktif = true;
      state.gecisBaslangic = performance.now();
      state.gecisIlerleme = 0;
      state._gecisYuklendi = false;
      state.oyunDurumu = "gecis";
    },

    // Debounce ile pencere yeniden boyutlandırma
    yenidenBoyutlandir: function() {
      var self = this;
      if (this._boyutZamanlayici) {
        clearTimeout(this._boyutZamanlayici);
      }
      this._boyutZamanlayici = setTimeout(function() {
        self.boyutAyarla();

        // Seviye platformlarının Y değerlerini yeniden hesapla
        if (BY.seviye && typeof BY.seviye.yukle === "function") {
          BY.seviye.yukle(BY.state.mevcutSeviye);
        }
      }, 150);
    }
  };

  // ── Pencere boyut değişimi dinleyicisi ──────────────────────────────────
  window.addEventListener("resize", function() {
    if (BY.state.calisiyor) {
      BY.motor.yenidenBoyutlandir();
    }
  });

})();