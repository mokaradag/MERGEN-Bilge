// www/js/bilge_yolac_dunya.js
// Dünya/ortam sistemi: 5 seviye tanımı, çok katmanlı paralaks, seviye geçiş mantığı

(function() {
  "use strict";

  var BY = window.BilgeYolac;
  if (!BY) return;

  // Seviye tanımları
  var SEVIYELER = [
    {
      isim: "Kozmik Radar Alanı",
      gokyuzu: { ust: "#0A0015", alt: "#1A0A30" },
      zemin: { ust: "#1A1030", alt: "#0D0820" },
      aksan: "#00E5FF",
      yildizRenk: "#E0E0FF",
      dagRenk1: "#15082A",
      dagRenk2: "#1F1040",
      cimRenk: "#2A1545",
      detaylar: "radar"
    },
    {
      isim: "Fütüristik Radar Üssü",
      gokyuzu: { ust: "#050A1A", alt: "#0A1530" },
      zemin: { ust: "#0A1020", alt: "#060A15" },
      aksan: "#4AFF70",
      yildizRenk: "#D0FFD0",
      dagRenk1: "#0A1020",
      dagRenk2: "#101830",
      cimRenk: "#0F1A25",
      detaylar: "anten"
    },
    {
      isim: "Mistik Tekno Orman",
      gokyuzu: { ust: "#001A0A", alt: "#0A2A15" },
      zemin: { ust: "#0A1A10", alt: "#051008" },
      aksan: "#B040FF",
      yildizRenk: "#D0FFE0",
      dagRenk1: "#0A1A0F",
      dagRenk2: "#152A1A",
      cimRenk: "#0A200F",
      detaylar: "agac"
    },
    {
      isim: "Kadim Tekno Tapınak",
      gokyuzu: { ust: "#1A0F00", alt: "#2A1A05" },
      zemin: { ust: "#1A1005", alt: "#100A02" },
      aksan: "#FFB020",
      yildizRenk: "#FFE0B0",
      dagRenk1: "#1A1008",
      dagRenk2: "#2A1A10",
      cimRenk: "#201508",
      detaylar: "tapinak"
    },
    {
      isim: "Elektronik Harp Meydanı",
      gokyuzu: { ust: "#150505", alt: "#251010" },
      zemin: { ust: "#1A0A0A", alt: "#100505" },
      aksan: "#FF4040",
      yildizRenk: "#FFD0D0",
      dagRenk1: "#1A0808",
      dagRenk2: "#251010",
      cimRenk: "#200A0A",
      detaylar: "harp"
    }
  ];

  // Yıldız verileri
  var yildizlar = [];

  // Dağ noktaları (iki katman)
  var daglar1 = [];
  var daglar2 = [];

  // Arka plan kayma (paralaks)
  var arkaPlanKayma = 0;

  function yildizlariOlustur() {
    var config = BY.config;
    yildizlar = [];
    for (var i = 0; i < config.YILDIZ_SAYISI; i++) {
      yildizlar.push({
        x: Math.random(),
        y: Math.random() * 0.65,
        boyut: 0.5 + Math.random() * 1.5,
        parlama: Math.random() * Math.PI * 2,
        hiz: 0.1 + Math.random() * 0.3,
        derinlik: Math.floor(Math.random() * 3) // 0=yakın, 1=orta, 2=uzak
      });
    }
  }

  function daglariOlustur() {
    daglar1 = [];
    daglar2 = [];

    // Arka dağ katmanı (yavaş hareket)
    for (var i = 0; i < 30; i++) {
      daglar1.push({
        x: i / 30,
        y: 0.5 + Math.sin(i * 0.5) * 0.08 + Math.sin(i * 1.3) * 0.04
      });
    }

    // Ön dağ katmanı (orta hız)
    for (var j = 0; j < 40; j++) {
      daglar2.push({
        x: j / 40,
        y: 0.6 + Math.sin(j * 0.7) * 0.06 + Math.sin(j * 1.8) * 0.03
      });
    }
  }

  // Gökyüzü gradyanı çiz
  function gokyuzuCiz(ctx, seviye) {
    var state = BY.state;
    var gradyan = ctx.createLinearGradient(0, 0, 0, state.zeminY);
    gradyan.addColorStop(0, seviye.gokyuzu.ust);
    gradyan.addColorStop(1, seviye.gokyuzu.alt);
    ctx.fillStyle = gradyan;
    ctx.fillRect(0, 0, state.canvasGenislik, state.zeminY);
  }

  // Yıldızları çiz
  function yildizlariCiz(ctx, seviye, zaman) {
    var state = BY.state;

    for (var i = 0; i < yildizlar.length; i++) {
      var y = yildizlar[i];
      var parlaklik = 0.4 + Math.sin(zaman * 0.002 * y.hiz + y.parlama) * 0.4;

      // Derinliğe göre paralaks
      var paralaksKayma = arkaPlanKayma * (0.05 + y.derinlik * 0.03);
      var ekranX = ((y.x + paralaksKayma) % 1) * state.canvasGenislik;
      if (ekranX < 0) ekranX += state.canvasGenislik;
      var ekranY = y.y * state.zeminY;

      ctx.save();
      ctx.globalAlpha = parlaklik;
      ctx.fillStyle = seviye.yildizRenk;
      ctx.shadowColor = seviye.yildizRenk;
      ctx.shadowBlur = y.boyut * 2;

      ctx.fillRect(
        Math.floor(ekranX),
        Math.floor(ekranY),
        Math.ceil(y.boyut),
        Math.ceil(y.boyut)
      );
      ctx.restore();
    }
  }

  // Dağları çiz (iki katman)
  function daglariCiz(ctx, seviye) {
    var state = BY.state;

    // Arka dağ katmanı
    ctx.save();
    ctx.fillStyle = seviye.dagRenk1;
    ctx.beginPath();
    ctx.moveTo(0, state.zeminY);

    for (var i = 0; i < daglar1.length; i++) {
      var noktaX = ((daglar1[i].x + arkaPlanKayma * 0.02) % 1) * state.canvasGenislik * 1.5 - state.canvasGenislik * 0.25;
      var noktaY = daglar1[i].y * state.zeminY;
      ctx.lineTo(noktaX, noktaY);
    }

    ctx.lineTo(state.canvasGenislik, state.zeminY);
    ctx.closePath();
    ctx.fill();
    ctx.restore();

    // Ön dağ katmanı
    ctx.save();
    ctx.fillStyle = seviye.dagRenk2;
    ctx.beginPath();
    ctx.moveTo(0, state.zeminY);

    for (var j = 0; j < daglar2.length; j++) {
      var nX = ((daglar2[j].x + arkaPlanKayma * 0.04) % 1) * state.canvasGenislik * 1.5 - state.canvasGenislik * 0.25;
      var nY = daglar2[j].y * state.zeminY;
      ctx.lineTo(nX, nY);
    }

    ctx.lineTo(state.canvasGenislik, state.zeminY);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }

  // Zemin çiz
  function zeminCiz(ctx, seviye) {
    var state = BY.state;

    // Zemin gradyanı
    var zeminGradyan = ctx.createLinearGradient(0, state.zeminY, 0, state.canvasYukseklik);
    zeminGradyan.addColorStop(0, seviye.zemin.ust);
    zeminGradyan.addColorStop(1, seviye.zemin.alt);
    ctx.fillStyle = zeminGradyan;
    ctx.fillRect(0, state.zeminY, state.canvasGenislik, state.canvasYukseklik - state.zeminY);

    // Zemin çizgisi (aksan rengi)
    ctx.save();
    ctx.strokeStyle = seviye.aksan;
    ctx.lineWidth = 2;
    ctx.globalAlpha = 0.4;
    ctx.shadowColor = seviye.aksan;
    ctx.shadowBlur = 6;
    ctx.beginPath();
    ctx.moveTo(0, state.zeminY);
    ctx.lineTo(state.canvasGenislik, state.zeminY);
    ctx.stroke();
    ctx.restore();

    // Çim/detay piksel deseni
    ctx.save();
    ctx.fillStyle = seviye.cimRenk;
    for (var i = 0; i < state.canvasGenislik; i += 8) {
      var yukseklik = 2 + Math.sin(i * 0.1 + arkaPlanKayma) * 2;
      ctx.fillRect(i, state.zeminY + 2, 3, yukseklik);
    }
    ctx.restore();
  }

  // Seviyeye özel detaylar çiz
  function detaylarCiz(ctx, seviye, zaman) {
    var state = BY.state;

    switch (seviye.detaylar) {
      case "radar":
        radarDetaylariCiz(ctx, seviye, zaman);
        break;
      case "anten":
        antenDetaylariCiz(ctx, seviye, zaman);
        break;
      case "agac":
        agacDetaylariCiz(ctx, seviye, zaman);
        break;
      case "tapinak":
        tapinakDetaylariCiz(ctx, seviye, zaman);
        break;
      case "harp":
        harpDetaylariCiz(ctx, seviye, zaman);
        break;
    }
  }

  // Radar detayları: radar çanağı, sinyal dalgaları
  function radarDetaylariCiz(ctx, seviye, zaman) {
    var state = BY.state;

    // Radar çanağı (arka planda)
    ctx.save();
    var cX = state.canvasGenislik * 0.85;
    var cY = state.zeminY * 0.3;

    // Çanak gövdesi
    ctx.strokeStyle = seviye.aksan;
    ctx.lineWidth = 2;
    ctx.globalAlpha = 0.5;
    ctx.beginPath();
    ctx.moveTo(cX - 20, cY);
    ctx.quadraticCurveTo(cX, cY - 15, cX + 20, cY);
    ctx.stroke();

    // Çanak direği
    ctx.beginPath();
    ctx.moveTo(cX, cY);
    ctx.lineTo(cX, cY + 30);
    ctx.stroke();

    // Sinyal halkaları
    var halkaSayisi = 3;
    for (var h = 0; h < halkaSayisi; h++) {
      var yaricap = 15 + ((zaman * 0.03 + h * 20) % 60);
      var opaklik = 1 - yaricap / 75;
      if (opaklik < 0) continue;

      ctx.beginPath();
      ctx.globalAlpha = opaklik * 0.3;
      ctx.arc(cX, cY - 5, yaricap, Math.PI * 1.2, Math.PI * 1.8);
      ctx.stroke();
    }
    ctx.restore();
  }

  // Anten detayları
  function antenDetaylariCiz(ctx, seviye, zaman) {
    var state = BY.state;
    ctx.save();

    // Anten yapıları
    var antenler = [
      { x: state.canvasGenislik * 0.15, yukseklik: 60 },
      { x: state.canvasGenislik * 0.75, yukseklik: 45 },
      { x: state.canvasGenislik * 0.92, yukseklik: 35 }
    ];

    ctx.strokeStyle = seviye.aksan;
    ctx.lineWidth = 2;
    ctx.globalAlpha = 0.4;

    for (var i = 0; i < antenler.length; i++) {
      var a = antenler[i];
      var tabanY = state.zeminY;

      // Anten direği
      ctx.beginPath();
      ctx.moveTo(a.x, tabanY);
      ctx.lineTo(a.x, tabanY - a.yukseklik);
      ctx.stroke();

      // Anten ucu
      ctx.beginPath();
      ctx.moveTo(a.x - 8, tabanY - a.yukseklik);
      ctx.lineTo(a.x + 8, tabanY - a.yukseklik);
      ctx.stroke();

      // Yanıp sönen ışık
      var yanipSonme = Math.sin(zaman * 0.005 + i) > 0.5;
      if (yanipSonme) {
        ctx.fillStyle = seviye.aksan;
        ctx.globalAlpha = 0.8;
        ctx.fillRect(a.x - 1, tabanY - a.yukseklik - 3, 3, 3);
        ctx.globalAlpha = 0.4;
      }
    }
    ctx.restore();
  }

  // Ağaç detayları
  function agacDetaylariCiz(ctx, seviye, zaman) {
    var state = BY.state;
    ctx.save();

    var agaclar = [
      { x: state.canvasGenislik * 0.08, boyut: 1.2 },
      { x: state.canvasGenislik * 0.25, boyut: 0.8 },
      { x: state.canvasGenislik * 0.6, boyut: 1.0 },
      { x: state.canvasGenislik * 0.88, boyut: 0.9 }
    ];

    for (var i = 0; i < agaclar.length; i++) {
      var ag = agaclar[i];
      var tabanY = state.zeminY;
      var govdeY = 40 * ag.boyut;

      // Govde
      ctx.fillStyle = "#2A1A0A";
      ctx.fillRect(ag.x - 3, tabanY - govdeY, 6, govdeY);

      // Yapraklar (parlayan)
      ctx.globalAlpha = 0.5 + Math.sin(zaman * 0.002 + i) * 0.2;
      ctx.fillStyle = seviye.aksan;
      ctx.shadowColor = seviye.aksan;
      ctx.shadowBlur = 8;

      // Ust yaprak
      ctx.fillRect(ag.x - 10, tabanY - govdeY - 8, 20, 10);
      // Orta yaprak
      ctx.fillRect(ag.x - 14, tabanY - govdeY + 5, 28, 8);
      // Alt yaprak
      ctx.fillRect(ag.x - 10, tabanY - govdeY + 15, 20, 6);

      ctx.shadowBlur = 0;
    }
    ctx.restore();
  }

  // Tapınak detayları
  function tapinakDetaylariCiz(ctx, seviye, zaman) {
    var state = BY.state;
    ctx.save();

    // Tapınak sütunları
    var sutunlar = [
      state.canvasGenislik * 0.2,
      state.canvasGenislik * 0.35,
      state.canvasGenislik * 0.65,
      state.canvasGenislik * 0.8
    ];

    ctx.globalAlpha = 0.35;

    for (var i = 0; i < sutunlar.length; i++) {
      var sX = sutunlar[i];
      var tabanY = state.zeminY;

      // Sütun
      ctx.fillStyle = "#3A2A15";
      ctx.fillRect(sX - 5, tabanY - 70, 10, 70);

      // Sütun başı
      ctx.fillRect(sX - 8, tabanY - 75, 16, 6);

      // Enerji oymaları
      ctx.fillStyle = seviye.aksan;
      ctx.globalAlpha = 0.2 + Math.sin(zaman * 0.003 + i * 1.5) * 0.15;
      ctx.fillRect(sX - 2, tabanY - 60, 4, 3);
      ctx.fillRect(sX - 2, tabanY - 45, 4, 3);
      ctx.fillRect(sX - 2, tabanY - 30, 4, 3);
      ctx.globalAlpha = 0.35;
    }

    // Üst kemer
    ctx.strokeStyle = "#3A2A15";
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.moveTo(sutunlar[0], state.zeminY - 75);
    ctx.lineTo(sutunlar[3], state.zeminY - 75);
    ctx.stroke();

    ctx.restore();
  }

  // Harp alanı detayları
  function harpDetaylariCiz(ctx, seviye, zaman) {
    var state = BY.state;
    ctx.save();

    // Hasar görmüş yapılar
    ctx.fillStyle = "#1A0808";
    ctx.globalAlpha = 0.4;

    // Yıkık duvar parçaları
    var parcalar = [
      { x: state.canvasGenislik * 0.1, g: 15, y: 20 },
      { x: state.canvasGenislik * 0.45, g: 25, y: 12 },
      { x: state.canvasGenislik * 0.7, g: 10, y: 25 },
      { x: state.canvasGenislik * 0.9, g: 20, y: 18 }
    ];

    for (var i = 0; i < parcalar.length; i++) {
      var p = parcalar[i];
      ctx.fillRect(p.x, state.zeminY - p.y, p.g, p.y);
    }

    // Elektrik kıvılcımları
    ctx.strokeStyle = seviye.aksan;
    ctx.lineWidth = 1;
    ctx.globalAlpha = 0.3 + Math.random() * 0.3;

    if (Math.random() > 0.95) {
      var kX = Math.random() * state.canvasGenislik;
      var kY = state.zeminY * (0.3 + Math.random() * 0.4);
      ctx.beginPath();
      ctx.moveTo(kX, kY);
      for (var s = 0; s < 4; s++) {
        kX += (Math.random() - 0.5) * 20;
        kY += 5 + Math.random() * 10;
        ctx.lineTo(kX, kY);
      }
      ctx.stroke();
    }

    ctx.restore();
  }

  // Dış arayüz
  BY.dunya = {
    SEVIYELER: SEVIYELER,

    baslat: function() {
      yildizlariOlustur();
      daglariOlustur();
      arkaPlanKayma = 0;
    },

    guncelle: function(zaman) {
      // Yavaş paralaks kayması
      arkaPlanKayma += 0.0002;
    },

    ciz: function(ctx) {
      var state = BY.state;
      var seviye = SEVIYELER[state.mevcutSeviye];
      var zaman = performance.now();

      gokyuzuCiz(ctx, seviye);
      yildizlariCiz(ctx, seviye, zaman);
      daglariCiz(ctx, seviye);
      detaylarCiz(ctx, seviye, zaman);
      zeminCiz(ctx, seviye);
    },

    seviyeDegistir: function(yeniSeviye) {
      // Seviye degistiginde ek ayarlamalar
    },

    boyutGuncelle: function() {
      // Yeniden boyutlandırmada dağ noktalarını güncelle
      daglariOlustur();
    },

    mevcutSeviyeAl: function() {
      return SEVIYELER[BY.state.mevcutSeviye];
    }
  };

})();