// www/js/bilge_yolac_seviye.js
// Bilge Yolaç seviye sistemi: 5 seviye tanımı, platform düzenleri, düşman yerleşimleri, boss ve çıkış noktaları

(function() {
  "use strict";

  var BY = window.BilgeYolac;
  if (!BY) return;

  var state = BY.state;

  // ── Seviye verileri ───────────────────────────────────────────────────────
  // Platform y değerleri canvasYukseklik oranı olarak tanımlanır (0.35 - 0.72 arası)
  // x değerleri dünya koordinatlarında, genislik/yukseklik piksel cinsindendir

  var SEVIYE_VERILERI = [

    // ── Seviye 0: Kozmik Radar Alanı ──────────────────────────────────────
    {
      isim: "Kozmik Radar Alanı",
      dunyaGenislik: 3500,
      tema: 0,
      platformlar: [
        // Sol bölge: giriş merdiveni
        { x: 200,  y: 0.68, genislik: 120, yukseklik: 12 },
        { x: 380,  y: 0.60, genislik: 100, yukseklik: 12 },
        { x: 550,  y: 0.52, genislik: 140, yukseklik: 14 },
        // Orta bölge: radar platformları
        { x: 850,  y: 0.65, genislik: 160, yukseklik: 12 },
        { x: 1100, y: 0.55, genislik: 100, yukseklik: 12 },
        { x: 1350, y: 0.45, genislik: 180, yukseklik: 14 },
        // Sağ bölge: yükselen geçit
        { x: 1800, y: 0.62, genislik: 120, yukseklik: 12 },
        { x: 2100, y: 0.50, genislik: 140, yukseklik: 14 },
        { x: 2450, y: 0.58, genislik: 160, yukseklik: 12 },
        { x: 2800, y: 0.70, genislik: 200, yukseklik: 14 }
      ],
      dusmanSpawnlar: [
        { x: 600,  tip: "drone" },
        { x: 1000, tip: "drone" },
        { x: 1400, tip: "drone" },
        { x: 1900, tip: "jammer" },
        { x: 2300, tip: "drone" },
        { x: 2700, tip: "jammer" }
      ],
      bossSpawn: { x: 3200, tip: "boss" },
      cikisNoktasi: { x: 3400 }
    },

    // ── Seviye 1: Fütüristik Radar Üssü ──────────────────────────────────
    {
      isim: "Fütüristik Radar Üssü",
      dunyaGenislik: 3800,
      tema: 1,
      platformlar: [
        // Giriş bölgesi: düz platformlar
        { x: 180,  y: 0.70, genislik: 140, yukseklik: 12 },
        { x: 400,  y: 0.62, genislik: 100, yukseklik: 12 },
        // İlk yükseliş zinciri
        { x: 620,  y: 0.54, genislik: 120, yukseklik: 14 },
        { x: 830,  y: 0.46, genislik: 100, yukseklik: 12 },
        { x: 1050, y: 0.38, genislik: 160, yukseklik: 14 },
        // Orta alan: üs yapıları
        { x: 1400, y: 0.60, genislik: 200, yukseklik: 16 },
        { x: 1700, y: 0.50, genislik: 140, yukseklik: 12 },
        { x: 1950, y: 0.42, genislik: 120, yukseklik: 12 },
        // Sağ bölge: iniş platformları
        { x: 2300, y: 0.55, genislik: 160, yukseklik: 14 },
        { x: 2600, y: 0.65, genislik: 180, yukseklik: 12 },
        { x: 2900, y: 0.48, genislik: 100, yukseklik: 12 },
        { x: 3150, y: 0.58, genislik: 140, yukseklik: 14 }
      ],
      dusmanSpawnlar: [
        { x: 500,  tip: "drone" },
        { x: 850,  tip: "drone" },
        { x: 1200, tip: "jammer" },
        { x: 1600, tip: "sentinel" },
        { x: 2000, tip: "drone" },
        { x: 2400, tip: "jammer" },
        { x: 2800, tip: "sentinel" },
        { x: 3100, tip: "drone" }
      ],
      bossSpawn: { x: 3500, tip: "boss" },
      cikisNoktasi: { x: 3700 }
    },

    // ── Seviye 2: Mistik Tekno Orman ──────────────────────────────────────
    {
      isim: "Mistik Tekno Orman",
      dunyaGenislik: 4000,
      tema: 2,
      platformlar: [
        // Orman girişi: dal benzeri platformlar
        { x: 150,  y: 0.65, genislik: 100, yukseklik: 10 },
        { x: 320,  y: 0.55, genislik: 80,  yukseklik: 10 },
        { x: 500,  y: 0.45, genislik: 120, yukseklik: 12 },
        { x: 700,  y: 0.60, genislik: 90,  yukseklik: 10 },
        // Orman derinlikleri: zigzag dal yolu
        { x: 950,  y: 0.50, genislik: 140, yukseklik: 12 },
        { x: 1200, y: 0.38, genislik: 100, yukseklik: 12 },
        { x: 1400, y: 0.55, genislik: 160, yukseklik: 14 },
        { x: 1650, y: 0.42, genislik: 120, yukseklik: 12 },
        // Orman kalbi: geniş ağaç taçları
        { x: 1950, y: 0.48, genislik: 200, yukseklik: 16 },
        { x: 2250, y: 0.58, genislik: 110, yukseklik: 12 },
        { x: 2500, y: 0.40, genislik: 130, yukseklik: 12 },
        // Orman çıkışı: alçalan patika
        { x: 2800, y: 0.52, genislik: 150, yukseklik: 14 },
        { x: 3100, y: 0.62, genislik: 180, yukseklik: 14 },
        { x: 3400, y: 0.70, genislik: 160, yukseklik: 12 }
      ],
      dusmanSpawnlar: [
        { x: 400,  tip: "drone" },
        { x: 700,  tip: "glitch" },
        { x: 1050, tip: "sentinel" },
        { x: 1350, tip: "drone" },
        { x: 1700, tip: "jammer" },
        { x: 2000, tip: "glitch" },
        { x: 2350, tip: "sentinel" },
        { x: 2700, tip: "drone" },
        { x: 3000, tip: "jammer" },
        { x: 3300, tip: "glitch" }
      ],
      bossSpawn: { x: 3700, tip: "boss" },
      cikisNoktasi: { x: 3900 }
    },

    // ── Seviye 3: Kadim Tekno Tapınak ─────────────────────────────────────
    {
      isim: "Kadim Tekno Tapınak",
      dunyaGenislik: 4200,
      tema: 3,
      platformlar: [
        // Tapınak girişi: simetrik basamaklar
        { x: 160,  y: 0.72, genislik: 120, yukseklik: 14 },
        { x: 340,  y: 0.64, genislik: 100, yukseklik: 12 },
        { x: 520,  y: 0.56, genislik: 100, yukseklik: 12 },
        { x: 700,  y: 0.48, genislik: 140, yukseklik: 14 },
        // İç avlu: yükselen sütunlar
        { x: 950,  y: 0.40, genislik: 80,  yukseklik: 10 },
        { x: 1120, y: 0.52, genislik: 160, yukseklik: 14 },
        { x: 1380, y: 0.36, genislik: 100, yukseklik: 12 },
        { x: 1580, y: 0.60, genislik: 180, yukseklik: 16 },
        // Kutsal salon: geniş platformlar
        { x: 1900, y: 0.45, genislik: 200, yukseklik: 16 },
        { x: 2200, y: 0.55, genislik: 120, yukseklik: 12 },
        { x: 2420, y: 0.42, genislik: 140, yukseklik: 14 },
        { x: 2680, y: 0.65, genislik: 100, yukseklik: 12 },
        // Tapınak çıkışı: inen yol
        { x: 2950, y: 0.50, genislik: 160, yukseklik: 14 },
        { x: 3200, y: 0.58, genislik: 130, yukseklik: 12 },
        { x: 3450, y: 0.68, genislik: 180, yukseklik: 14 },
        { x: 3700, y: 0.72, genislik: 140, yukseklik: 12 }
      ],
      dusmanSpawnlar: [
        { x: 400,  tip: "sentinel" },
        { x: 700,  tip: "drone" },
        { x: 1000, tip: "jammer" },
        { x: 1300, tip: "glitch" },
        { x: 1600, tip: "sentinel" },
        { x: 1950, tip: "drone" },
        { x: 2250, tip: "glitch" },
        { x: 2550, tip: "jammer" },
        { x: 2850, tip: "sentinel" },
        { x: 3150, tip: "drone" },
        { x: 3400, tip: "glitch" },
        { x: 3650, tip: "jammer" }
      ],
      bossSpawn: { x: 3900, tip: "boss" },
      cikisNoktasi: { x: 4100 }
    },

    // ── Seviye 4: Elektronik Harp Meydanı ─────────────────────────────────
    {
      isim: "Elektronik Harp Meydanı",
      dunyaGenislik: 4500,
      tema: 4,
      platformlar: [
        // Siperhane girişi: düzensiz bariyerler
        { x: 140,  y: 0.70, genislik: 100, yukseklik: 12 },
        { x: 320,  y: 0.58, genislik: 80,  yukseklik: 10 },
        { x: 480,  y: 0.48, genislik: 120, yukseklik: 12 },
        { x: 670,  y: 0.62, genislik: 90,  yukseklik: 10 },
        // Ön cephe: dalgalı platform dizisi
        { x: 880,  y: 0.42, genislik: 140, yukseklik: 14 },
        { x: 1100, y: 0.55, genislik: 100, yukseklik: 12 },
        { x: 1300, y: 0.38, genislik: 110, yukseklik: 12 },
        { x: 1520, y: 0.50, genislik: 160, yukseklik: 14 },
        // Savaş alanı merkezi: büyük karakol platformları
        { x: 1800, y: 0.60, genislik: 200, yukseklik: 16 },
        { x: 2100, y: 0.44, genislik: 120, yukseklik: 12 },
        { x: 2330, y: 0.36, genislik: 100, yukseklik: 12 },
        { x: 2550, y: 0.52, genislik: 180, yukseklik: 14 },
        // Arka cephe: yoğun platform ağı
        { x: 2850, y: 0.65, genislik: 140, yukseklik: 12 },
        { x: 3080, y: 0.48, genislik: 120, yukseklik: 14 },
        { x: 3300, y: 0.40, genislik: 100, yukseklik: 12 },
        { x: 3520, y: 0.56, genislik: 160, yukseklik: 14 },
        { x: 3780, y: 0.68, genislik: 200, yukseklik: 16 },
        { x: 4050, y: 0.72, genislik: 140, yukseklik: 12 }
      ],
      dusmanSpawnlar: [
        { x: 350,  tip: "drone" },
        { x: 600,  tip: "glitch" },
        { x: 850,  tip: "sentinel" },
        { x: 1100, tip: "jammer" },
        { x: 1350, tip: "drone" },
        { x: 1600, tip: "glitch" },
        { x: 1900, tip: "sentinel" },
        { x: 2200, tip: "jammer" },
        { x: 2500, tip: "drone" },
        { x: 2750, tip: "glitch" },
        { x: 3000, tip: "sentinel" },
        { x: 3250, tip: "jammer" },
        { x: 3500, tip: "glitch" },
        { x: 3800, tip: "sentinel" },
        { x: 4000, tip: "drone" }
      ],
      bossSpawn: { x: 4200, tip: "boss" },
      cikisNoktasi: { x: 4400 }
    }
  ];

  // ── Seviye modülü ─────────────────────────────────────────────────────────
  BY.seviye = {

    // Belirtilen seviyeyi yükle ve durumu güncelle
    yukle: function(seviyeNo) {
      if (seviyeNo < 0 || seviyeNo >= SEVIYE_VERILERI.length) {
        console.warn("[BilgeYolac] Geçersiz seviye numarası:", seviyeNo);
        seviyeNo = 0;
      }

      var veri = SEVIYE_VERILERI[seviyeNo];

      // Dünya genişliğini ayarla
      state.dunyaGenislik = veri.dunyaGenislik;
      state.mevcutSeviye = seviyeNo;

      // Platformları oluştur: y oranlarını gerçek piksel değerlerine dönüştür
      var canvasYukseklik = state.canvasYukseklik || 400; // Varsayılan yükseklik
      var platformlar = [];

      for (var i = 0; i < veri.platformlar.length; i++) {
        var kaynak = veri.platformlar[i];
        platformlar.push({
          x: kaynak.x,
          y: Math.floor(canvasYukseklik * kaynak.y),
          genislik: kaynak.genislik,
          yukseklik: kaynak.yukseklik
        });
      }

      state.platformlar = platformlar;

      // Düşman spawn verilerini düşman modülüne ilet
      if (BY.dusmanlar && typeof BY.dusmanlar.baslat === "function") {
        try {
          BY.dusmanlar.baslat(veri.dusmanSpawnlar);
        } catch (e) {
          console.warn("[BilgeYolac] Düşman başlatma hatası:", e);
        }
      }

      // Mermileri ve parçacıkları temizle (yeni seviye için)
      state.mermiler = [];
      state.parcaciklar = [];
    },

    // Mevcut seviye verilerini döndür
    mevcutVeriAl: function() {
      var seviyeNo = state.mevcutSeviye || 0;
      if (seviyeNo < 0 || seviyeNo >= SEVIYE_VERILERI.length) return null;
      return SEVIYE_VERILERI[seviyeNo];
    },

    // Mevcut seviyenin platformlarını döndür (state'ten)
    platformlariAl: function() {
      return state.platformlar || [];
    },

    // Mevcut seviyenin düşman spawn noktalarını döndür
    dusmanSpawnlariAl: function() {
      var veri = this.mevcutVeriAl();
      return veri ? veri.dusmanSpawnlar : [];
    },

    // Mevcut seviyenin boss spawn bilgisini döndür
    bossSpawnAl: function() {
      var veri = this.mevcutVeriAl();
      return veri ? veri.bossSpawn : null;
    },

    // Mevcut seviyenin çıkış noktasını döndür
    cikisNoktasiAl: function() {
      var veri = this.mevcutVeriAl();
      return veri ? veri.cikisNoktasi : null;
    },

    // Toplam seviye sayısını döndür
    seviyeSayisi: function() {
      return SEVIYE_VERILERI.length;
    }
  };

})();