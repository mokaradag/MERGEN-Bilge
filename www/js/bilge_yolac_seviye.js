// www/js/bilge_yolac_seviye.js
// Bilge Yolaç seviye sistemi: 5 dünya kimliği, platform düzenleri, çevre
// set parçaları, düşman yerleşimleri, boss ve çıkış noktaları.

(function() {
  "use strict";

  var BY = window.BilgeYolac;
  if (!BY) return;

  var state = BY.state;

  var SEVIYE_VERILERI = [
    {
      isim: "Çözüm Vadisi",
      dunyaId: "emre",
      dunyaGenislik: 3600,
      tema: 0,
      platformlar: [
        { x: 180,  y: 0.68, genislik: 120, yukseklik: 12 },
        { x: 360,  y: 0.60, genislik: 110, yukseklik: 12 },
        { x: 540,  y: 0.52, genislik: 130, yukseklik: 12 },
        { x: 820,  y: 0.64, genislik: 160, yukseklik: 12 },
        { x: 1100, y: 0.56, genislik: 110, yukseklik: 12 },
        { x: 1380, y: 0.44, genislik: 180, yukseklik: 14 },
        { x: 1760, y: 0.62, genislik: 120, yukseklik: 12 },
        { x: 2060, y: 0.50, genislik: 140, yukseklik: 14 },
        { x: 2400, y: 0.58, genislik: 160, yukseklik: 12 },
        { x: 2780, y: 0.48, genislik: 120, yukseklik: 12 },
        { x: 3050, y: 0.66, genislik: 210, yukseklik: 14 }
      ],
      setParcalari: [
        { x: 120, tur: "pole", katman: "arka", yOrani: 0.76, genislik: 96, yukseklik: 88, saydamlik: 0.75 },
        { x: 340, tur: "temple", katman: "orta", yOrani: 0.78, genislik: 180, yukseklik: 120 },
        { x: 710, tur: "radar", katman: "orta", yOrani: 0.78, genislik: 150, yukseklik: 120 },
        { x: 1180, tur: "plateau", katman: "arka", yOrani: 0.74, genislik: 180, yukseklik: 100, saydamlik: 0.75 },
        { x: 1480, tur: "temple", katman: "orta", yOrani: 0.74, genislik: 170, yukseklik: 120 },
        { x: 1910, tur: "radar", katman: "orta", yOrani: 0.76, genislik: 140, yukseklik: 116 },
        { x: 2300, tur: "grass", katman: "on", yOrani: 0.82, genislik: 120, yukseklik: 56, saydamlik: 0.95 },
        { x: 2680, tur: "temple", katman: "arka", yOrani: 0.76, genislik: 220, yukseklik: 126, saydamlik: 0.70 },
        { x: 3160, tur: "radar", katman: "orta", yOrani: 0.78, genislik: 170, yukseklik: 130 }
      ],
      dusmanSpawnlar: [
        { x: 620, tip: "drone" },
        { x: 980, tip: "drone" },
        { x: 1360, tip: "sentinel" },
        { x: 1860, tip: "jammer" },
        { x: 2260, tip: "drone" },
        { x: 2720, tip: "sentinel" },
        { x: 3120, tip: "jammer" }
      ],
      bossSpawn: { x: 3320, tip: "boss" },
      cikisNoktasi: { x: 3480 }
    },
    {
      isim: "Sinyal Sahası",
      dunyaId: "selin",
      dunyaGenislik: 3900,
      tema: 1,
      platformlar: [
        { x: 160,  y: 0.70, genislik: 140, yukseklik: 12 },
        { x: 420,  y: 0.60, genislik: 110, yukseklik: 12 },
        { x: 640,  y: 0.50, genislik: 120, yukseklik: 12 },
        { x: 880,  y: 0.40, genislik: 120, yukseklik: 12 },
        { x: 1160, y: 0.54, genislik: 180, yukseklik: 14 },
        { x: 1480, y: 0.44, genislik: 140, yukseklik: 12 },
        { x: 1760, y: 0.36, genislik: 120, yukseklik: 12 },
        { x: 2060, y: 0.52, genislik: 180, yukseklik: 14 },
        { x: 2380, y: 0.62, genislik: 190, yukseklik: 14 },
        { x: 2720, y: 0.46, genislik: 110, yukseklik: 12 },
        { x: 3020, y: 0.56, genislik: 150, yukseklik: 14 },
        { x: 3340, y: 0.68, genislik: 220, yukseklik: 16 }
      ],
      setParcalari: [
        { x: 300, tur: "spire", katman: "arka", yOrani: 0.70, genislik: 180, yukseklik: 140, saydamlik: 0.72 },
        { x: 560, tur: "tower", katman: "orta", yOrani: 0.78, genislik: 140, yukseklik: 150 },
        { x: 980, tur: "energy_gate", katman: "orta", yOrani: 0.76, genislik: 180, yukseklik: 126 },
        { x: 1430, tur: "relay", katman: "on", yOrani: 0.74, genislik: 110, yukseklik: 110 },
        { x: 1850, tur: "fortress", katman: "arka", yOrani: 0.72, genislik: 220, yukseklik: 130, saydamlik: 0.70 },
        { x: 2170, tur: "tower", katman: "orta", yOrani: 0.76, genislik: 150, yukseklik: 150 },
        { x: 2600, tur: "crystal", katman: "on", yOrani: 0.80, genislik: 110, yukseklik: 74 },
        { x: 3170, tur: "energy_gate", katman: "orta", yOrani: 0.78, genislik: 190, yukseklik: 132 }
      ],
      dusmanSpawnlar: [
        { x: 520, tip: "drone" },
        { x: 880, tip: "sentinel" },
        { x: 1220, tip: "jammer" },
        { x: 1600, tip: "drone" },
        { x: 1980, tip: "sentinel" },
        { x: 2340, tip: "drone" },
        { x: 2760, tip: "jammer" },
        { x: 3200, tip: "sentinel" }
      ],
      bossSpawn: { x: 3520, tip: "boss" },
      cikisNoktasi: { x: 3740 }
    },
    {
      isim: "Strateji Platosu",
      dunyaId: "deniz",
      dunyaGenislik: 4050,
      tema: 2,
      platformlar: [
        { x: 140,  y: 0.66, genislik: 110, yukseklik: 10 },
        { x: 320,  y: 0.55, genislik: 80,  yukseklik: 10 },
        { x: 520,  y: 0.44, genislik: 130, yukseklik: 12 },
        { x: 760,  y: 0.58, genislik: 100, yukseklik: 10 },
        { x: 980,  y: 0.48, genislik: 150, yukseklik: 12 },
        { x: 1260, y: 0.38, genislik: 100, yukseklik: 12 },
        { x: 1520, y: 0.54, genislik: 170, yukseklik: 14 },
        { x: 1820, y: 0.40, genislik: 120, yukseklik: 12 },
        { x: 2140, y: 0.46, genislik: 220, yukseklik: 16 },
        { x: 2480, y: 0.58, genislik: 120, yukseklik: 12 },
        { x: 2780, y: 0.42, genislik: 140, yukseklik: 12 },
        { x: 3120, y: 0.52, genislik: 180, yukseklik: 14 },
        { x: 3460, y: 0.66, genislik: 190, yukseklik: 14 }
      ],
      setParcalari: [
        { x: 220, tur: "sacred_tree", katman: "orta", yOrani: 0.80, genislik: 160, yukseklik: 170 },
        { x: 600, tur: "fern", katman: "on", yOrani: 0.82, genislik: 120, yukseklik: 62 },
        { x: 920, tur: "runic_ruin", katman: "arka", yOrani: 0.74, genislik: 180, yukseklik: 120, saydamlik: 0.72 },
        { x: 1320, tur: "sacred_tree", katman: "orta", yOrani: 0.80, genislik: 170, yukseklik: 176 },
        { x: 1790, tur: "rune_stone", katman: "on", yOrani: 0.80, genislik: 110, yukseklik: 84 },
        { x: 2260, tur: "runic_ruin", katman: "orta", yOrani: 0.78, genislik: 200, yukseklik: 124 },
        { x: 2680, tur: "sacred_tree", katman: "arka", yOrani: 0.78, genislik: 200, yukseklik: 180, saydamlik: 0.75 },
        { x: 3180, tur: "rune_stone", katman: "on", yOrani: 0.80, genislik: 120, yukseklik: 86 }
      ],
      dusmanSpawnlar: [
        { x: 420, tip: "drone" },
        { x: 760, tip: "glitch" },
        { x: 1120, tip: "sentinel" },
        { x: 1480, tip: "drone" },
        { x: 1820, tip: "jammer" },
        { x: 2220, tip: "glitch" },
        { x: 2580, tip: "sentinel" },
        { x: 3020, tip: "drone" },
        { x: 3380, tip: "glitch" }
      ],
      bossSpawn: { x: 3660, tip: "boss" },
      cikisNoktasi: { x: 3900 }
    },
    {
      isim: "Doğrulama Hattı",
      dunyaId: "can",
      dunyaGenislik: 4250,
      tema: 3,
      platformlar: [
        { x: 140,  y: 0.72, genislik: 120, yukseklik: 14 },
        { x: 330,  y: 0.62, genislik: 100, yukseklik: 12 },
        { x: 520,  y: 0.54, genislik: 110, yukseklik: 12 },
        { x: 740,  y: 0.44, genislik: 140, yukseklik: 14 },
        { x: 980,  y: 0.58, genislik: 120, yukseklik: 12 },
        { x: 1260, y: 0.36, genislik: 100, yukseklik: 12 },
        { x: 1540, y: 0.54, genislik: 170, yukseklik: 16 },
        { x: 1860, y: 0.44, genislik: 190, yukseklik: 16 },
        { x: 2200, y: 0.56, genislik: 120, yukseklik: 12 },
        { x: 2460, y: 0.42, genislik: 140, yukseklik: 14 },
        { x: 2780, y: 0.66, genislik: 110, yukseklik: 12 },
        { x: 3090, y: 0.50, genislik: 170, yukseklik: 14 },
        { x: 3400, y: 0.60, genislik: 140, yukseklik: 12 },
        { x: 3710, y: 0.70, genislik: 200, yukseklik: 14 }
      ],
      setParcalari: [
        { x: 260, tur: "glitch_temple", katman: "arka", yOrani: 0.76, genislik: 210, yukseklik: 140, saydamlik: 0.74 },
        { x: 690, tur: "thorn", katman: "on", yOrani: 0.82, genislik: 120, yukseklik: 88 },
        { x: 1120, tur: "rift", katman: "orta", yOrani: 0.72, genislik: 160, yukseklik: 150 },
        { x: 1570, tur: "glitch_crystal", katman: "on", yOrani: 0.80, genislik: 120, yukseklik: 98 },
        { x: 1980, tur: "glitch_temple", katman: "orta", yOrani: 0.76, genislik: 220, yukseklik: 146 },
        { x: 2470, tur: "rift", katman: "orta", yOrani: 0.74, genislik: 160, yukseklik: 152 },
        { x: 2960, tur: "thorn", katman: "on", yOrani: 0.82, genislik: 140, yukseklik: 94 },
        { x: 3480, tur: "glitch_temple", katman: "arka", yOrani: 0.76, genislik: 240, yukseklik: 150, saydamlik: 0.72 }
      ],
      dusmanSpawnlar: [
        { x: 420, tip: "sentinel" },
        { x: 780, tip: "glitch" },
        { x: 1180, tip: "jammer" },
        { x: 1540, tip: "glitch" },
        { x: 1900, tip: "sentinel" },
        { x: 2280, tip: "drone" },
        { x: 2640, tip: "glitch" },
        { x: 3040, tip: "jammer" },
        { x: 3440, tip: "sentinel" },
        { x: 3820, tip: "glitch" }
      ],
      bossSpawn: { x: 3950, tip: "boss" },
      cikisNoktasi: { x: 4140 }
    },
    {
      isim: "Rehberlik Atölyesi",
      dunyaId: "ipek",
      dunyaGenislik: 4520,
      tema: 4,
      platformlar: [
        { x: 140,  y: 0.70, genislik: 110, yukseklik: 12 },
        { x: 320,  y: 0.60, genislik: 90,  yukseklik: 10 },
        { x: 520,  y: 0.48, genislik: 120, yukseklik: 12 },
        { x: 740,  y: 0.58, genislik: 110, yukseklik: 10 },
        { x: 980,  y: 0.42, genislik: 150, yukseklik: 14 },
        { x: 1240, y: 0.56, genislik: 110, yukseklik: 12 },
        { x: 1510, y: 0.38, genislik: 120, yukseklik: 12 },
        { x: 1790, y: 0.52, genislik: 170, yukseklik: 14 },
        { x: 2100, y: 0.64, genislik: 210, yukseklik: 16 },
        { x: 2430, y: 0.46, genislik: 120, yukseklik: 12 },
        { x: 2690, y: 0.36, genislik: 110, yukseklik: 12 },
        { x: 2960, y: 0.54, genislik: 180, yukseklik: 14 },
        { x: 3280, y: 0.66, genislik: 150, yukseklik: 12 },
        { x: 3570, y: 0.50, genislik: 170, yukseklik: 14 },
        { x: 3890, y: 0.68, genislik: 220, yukseklik: 16 }
      ],
      setParcalari: [
        { x: 260, tur: "bloom", katman: "on", yOrani: 0.80, genislik: 120, yukseklik: 78 },
        { x: 620, tur: "sanctuary_gate", katman: "arka", yOrani: 0.76, genislik: 200, yukseklik: 134, saydamlik: 0.72 },
        { x: 980, tur: "life_pool", katman: "orta", yOrani: 0.80, genislik: 180, yukseklik: 96 },
        { x: 1420, tur: "flora", katman: "on", yOrani: 0.82, genislik: 130, yukseklik: 76 },
        { x: 1900, tur: "sanctuary_gate", katman: "orta", yOrani: 0.76, genislik: 220, yukseklik: 140 },
        { x: 2450, tur: "life_pool", katman: "orta", yOrani: 0.80, genislik: 180, yukseklik: 96 },
        { x: 3020, tur: "flora", katman: "on", yOrani: 0.82, genislik: 130, yukseklik: 76 },
        { x: 3600, tur: "sanctuary_gate", katman: "arka", yOrani: 0.76, genislik: 240, yukseklik: 148, saydamlik: 0.72 }
      ],
      dusmanSpawnlar: [
        { x: 420, tip: "drone" },
        { x: 820, tip: "sentinel" },
        { x: 1200, tip: "jammer" },
        { x: 1600, tip: "drone" },
        { x: 2040, tip: "sentinel" },
        { x: 2460, tip: "glitch" },
        { x: 2900, tip: "jammer" },
        { x: 3320, tip: "sentinel" },
        { x: 3740, tip: "drone" }
      ],
      bossSpawn: { x: 4060, tip: "boss" },
      cikisNoktasi: { x: 4360 }
    }
  ];

  BY.seviye = {
    yukle: function(seviyeNo) {
      if (seviyeNo < 0 || seviyeNo >= SEVIYE_VERILERI.length) seviyeNo = 0;

      var veri = SEVIYE_VERILERI[seviyeNo];
      state.dunyaGenislik = veri.dunyaGenislik;
      state.mevcutSeviye = seviyeNo;
      state.aktifDunyaId = veri.dunyaId;

      var canvasYukseklik = state.canvasYukseklik || 400;
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
      state.mermiler = [];
      state.parcaciklar = [];

      if (BY.dunya && typeof BY.dunya.seviyeDegistir === "function") {
        BY.dunya.seviyeDegistir(seviyeNo);
      }

      if (BY.dusmanlar && typeof BY.dusmanlar.baslat === "function") {
        try { BY.dusmanlar.baslat(veri.dusmanSpawnlar); } catch (e) { console.warn("[BilgeYolac] Düşman başlatma hatası:", e); }
      }
    },

    mevcutVeriAl: function() {
      var seviyeNo = state.mevcutSeviye || 0;
      if (seviyeNo < 0 || seviyeNo >= SEVIYE_VERILERI.length) return null;
      return SEVIYE_VERILERI[seviyeNo];
    },

    platformlariAl: function() {
      return state.platformlar || [];
    },

    setParcalariAl: function(katman) {
      var veri = this.mevcutVeriAl();
      if (!veri || !veri.setParcalari) return [];
      if (!katman) return veri.setParcalari;
      var sonuc = [];
      for (var i = 0; i < veri.setParcalari.length; i++) {
        if (veri.setParcalari[i].katman === katman) sonuc.push(veri.setParcalari[i]);
      }
      return sonuc;
    },

    dusmanSpawnlariAl: function() {
      var veri = this.mevcutVeriAl();
      return veri ? veri.dusmanSpawnlar : [];
    },

    bossSpawnAl: function() {
      var veri = this.mevcutVeriAl();
      return veri ? veri.bossSpawn : null;
    },

    cikisNoktasiAl: function() {
      var veri = this.mevcutVeriAl();
      return veri ? veri.cikisNoktasi : null;
    },

    seviyeSayisi: function() {
      return SEVIYE_VERILERI.length;
    }
  };

})();