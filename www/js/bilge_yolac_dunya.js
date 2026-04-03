// www/js/bilge_yolac_dunya.js
// Dünya/ortam sistemi: 5 dünya kimliği, daha zengin paralaks, set parçası
// katmanları, 2.5D derinlik ve ön plan perdeleme.

(function() {
  "use strict";

  var BY = window.BilgeYolac;
  if (!BY) return;

  var SEVIYELER = [
    {
      id: "mergen",
      isim: "Mergen Sınır Tapınağı",
      altBaslik: "Tapınak sınırı • radar karakolu • taş kalıntılar",
      gokyuzu: { ust: "#08111E", alt: "#21304A" },
      zemin: { ust: "#2A2630", alt: "#151218" },
      aksan: "#7ED5FF",
      sis: "rgba(126,213,255,0.08)",
      siluet1: "#102035",
      siluet2: "#1B2C40",
      detay: "steppe"
    },
    {
      id: "ulgen",
      isim: "Ülgen Göksel Kalesi",
      altBaslik: "Semavi kuleler • ışıklı düzen • yüksek nizam",
      gokyuzu: { ust: "#040B1B", alt: "#172B58" },
      zemin: { ust: "#151C30", alt: "#090E17" },
      aksan: "#AEE8FF",
      sis: "rgba(174,232,255,0.10)",
      siluet1: "#102041",
      siluet2: "#1A3261",
      detay: "light"
    },
    {
      id: "kayra",
      isim: "Kayra Kutsal Ormanı",
      altBaslik: "Runik harabeler • bilgeliğin kökleri • mistik doğa",
      gokyuzu: { ust: "#07130C", alt: "#1D4029" },
      zemin: { ust: "#112016", alt: "#08110B" },
      aksan: "#89F0B9",
      sis: "rgba(137,240,185,0.08)",
      siluet1: "#0B1D12",
      siluet2: "#163321",
      detay: "forest"
    },
    {
      id: "erlik",
      isim: "Erlik Bozulma Mabedi",
      altBaslik: "Çöküş • gölge yarıkları • bozulmuş tapınak",
      gokyuzu: { ust: "#12030A", alt: "#3A0C18" },
      zemin: { ust: "#241019", alt: "#12070E" },
      aksan: "#FF6B9C",
      sis: "rgba(255,107,156,0.08)",
      siluet1: "#210812",
      siluet2: "#37121E",
      detay: "corruption"
    },
    {
      id: "umay",
      isim: "Umay Şifa Mabedi",
      altBaslik: "Koruyucu biyom • kutsal bahçe • onarıcı ışık",
      gokyuzu: { ust: "#0A1220", alt: "#2C405F" },
      zemin: { ust: "#1B2433", alt: "#0E141B" },
      aksan: "#FFD6F0",
      sis: "rgba(255,214,240,0.10)",
      siluet1: "#1A2133",
      siluet2: "#2A3650",
      detay: "healing"
    }
  ];

  var yildizlar = [];
  var arkaPlanKayma = 0;
  var ortamTaneleri = [];

  function mevcutSeviyeAl() {
    var state = BY.state;
    var seviye = SEVIYELER[state.mevcutSeviye];
    return seviye || SEVIYELER[0];
  }

  function yildizlariOlustur() {
    yildizlar = [];
    for (var i = 0; i < BY.config.YILDIZ_SAYISI; i++) {
      yildizlar.push({
        x: Math.random(),
        y: Math.random() * 0.62,
        boyut: 0.5 + Math.random() * 1.5,
        hiz: 0.08 + Math.random() * 0.25,
        parlama: Math.random() * Math.PI * 2,
        derinlik: Math.floor(Math.random() * 4)
      });
    }
  }

  function ortamTaneleriniOlustur() {
    ortamTaneleri = [];
    for (var i = 0; i < 56; i++) {
      ortamTaneleri.push({
        x: Math.random(),
        y: Math.random(),
        boyut: 1 + Math.random() * 3,
        hizX: (Math.random() - 0.5) * 0.0004,
        hizY: 0.0002 + Math.random() * 0.0006,
        salinim: Math.random() * Math.PI * 2
      });
    }
  }

  function gokyuzuCiz(ctx, seviye) {
    var state = BY.state;
    var grad = ctx.createLinearGradient(0, 0, 0, state.canvasYukseklik);
    grad.addColorStop(0, seviye.gokyuzu.ust);
    grad.addColorStop(1, seviye.gokyuzu.alt);
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, state.canvasGenislik, state.canvasYukseklik);
  }

  function yildizlariCiz(ctx, seviye, zaman) {
    var state = BY.state;
    for (var i = 0; i < yildizlar.length; i++) {
      var y = yildizlar[i];
      var parlaklik = 0.30 + Math.sin(zaman * 0.0018 * y.hiz * 100 + y.parlama) * 0.35;
      var kayma = arkaPlanKayma * (0.02 + y.derinlik * 0.02);
      var ekranX = ((y.x + kayma) % 1) * state.canvasGenislik;
      if (ekranX < 0) ekranX += state.canvasGenislik;
      var ekranY = y.y * state.zeminY;

      ctx.save();
      ctx.globalAlpha = parlaklik;
      ctx.fillStyle = "#F5FBFF";
      ctx.shadowColor = seviye.aksan;
      ctx.shadowBlur = y.boyut * 3;
      ctx.fillRect(Math.floor(ekranX), Math.floor(ekranY), Math.ceil(y.boyut), Math.ceil(y.boyut));
      ctx.restore();
    }
  }

  function siluetKatmaniCiz(ctx, seviye, carpan, tabanY, renk) {
    var state = BY.state;
    var genislik = state.canvasGenislik;
    var kayma = (state.kameraX * carpan) % (genislik * 1.5);
    var baslangic = -kayma - genislik * 0.5;

    ctx.save();
    ctx.fillStyle = renk;
    ctx.beginPath();
    ctx.moveTo(-20, tabanY + 80);

    for (var x = baslangic, i = 0; x < genislik * 2; x += 120, i++) {
      var tepe = tabanY - 40 - Math.sin((x + i * 37) * 0.01) * 20 - Math.cos((x + i * 59) * 0.006) * 30;
      ctx.lineTo(x, tepe);
      ctx.lineTo(x + 60, tabanY + 8 + Math.sin(i) * 12);
    }

    ctx.lineTo(genislik + 60, tabanY + 80);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }

  function sisVeIsikCiz(ctx, seviye) {
    var state = BY.state;
    ctx.save();

    var grad = ctx.createLinearGradient(0, state.zeminY * 0.15, 0, state.canvasYukseklik);
    grad.addColorStop(0, "rgba(255,255,255,0)");
    grad.addColorStop(1, seviye.sis);
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, state.canvasGenislik, state.canvasYukseklik);

    var radial = ctx.createRadialGradient(
      state.canvasGenislik * 0.65, state.canvasYukseklik * 0.24, 20,
      state.canvasGenislik * 0.65, state.canvasYukseklik * 0.24, state.canvasGenislik * 0.45
    );
    radial.addColorStop(0, "rgba(255,255,255,0.10)");
    radial.addColorStop(1, "rgba(255,255,255,0)");
    ctx.fillStyle = radial;
    ctx.fillRect(0, 0, state.canvasGenislik, state.canvasYukseklik);

    ctx.restore();
  }

  function ortamTaneleriniCiz(ctx, seviye, zaman) {
    var state = BY.state;
    ctx.save();
    ctx.fillStyle = seviye.aksan;

    for (var i = 0; i < ortamTaneleri.length; i++) {
      var t = ortamTaneleri[i];
      var ekranX = ((t.x + arkaPlanKayma * (0.03 + i * 0.0007)) % 1) * state.canvasGenislik;
      var ekranY = ((t.y + Math.sin(zaman * 0.0008 + t.salinim) * 0.02) % 1) * state.canvasYukseklik * 0.85;
      ctx.globalAlpha = 0.08 + (i % 3) * 0.05;
      ctx.fillRect(ekranX, ekranY, t.boyut, t.boyut);
    }

    ctx.restore();
  }

  function zeminCiz(ctx, seviye) {
    var state = BY.state;

    var grad = ctx.createLinearGradient(0, state.zeminY, 0, state.canvasYukseklik);
    grad.addColorStop(0, seviye.zemin.ust);
    grad.addColorStop(1, seviye.zemin.alt);
    ctx.fillStyle = grad;
    ctx.fillRect(0, state.zeminY, state.canvasGenislik, state.canvasYukseklik - state.zeminY);

    ctx.save();
    ctx.strokeStyle = seviye.aksan;
    ctx.lineWidth = 2;
    ctx.globalAlpha = 0.35;
    ctx.shadowColor = seviye.aksan;
    ctx.shadowBlur = 8;
    ctx.beginPath();
    ctx.moveTo(0, state.zeminY);
    ctx.lineTo(state.canvasGenislik, state.zeminY);
    ctx.stroke();
    ctx.restore();

    zeminDetayiCiz(ctx, seviye);
  }

  function zeminDetayiCiz(ctx, seviye) {
    var state = BY.state;
    var detay = seviye.detay;

    ctx.save();

    if (detay === "steppe") {
      ctx.fillStyle = "rgba(166, 196, 158, 0.20)";
      for (var i = 0; i < state.canvasGenislik; i += 12) {
        var h = 2 + Math.sin((i + arkaPlanKayma * 1000) * 0.1) * 2;
        ctx.fillRect(i, state.zeminY + 2, 2, h + 3);
      }
    } else if (detay === "light") {
      ctx.fillStyle = "rgba(180, 220, 255, 0.20)";
      for (var j = 0; j < state.canvasGenislik; j += 18) {
        ctx.fillRect(j, state.zeminY + 5 + Math.sin(j * 0.04) * 3, 8, 2);
        ctx.fillRect(j + 4, state.zeminY + 10, 2, 8);
      }
    } else if (detay === "forest") {
      ctx.fillStyle = "rgba(118, 194, 123, 0.22)";
      for (var k = 0; k < state.canvasGenislik; k += 10) {
        ctx.fillRect(k, state.zeminY + 2, 2, 4 + Math.sin(k * 0.1) * 3);
      }
    } else if (detay === "corruption") {
      ctx.fillStyle = "rgba(255, 96, 144, 0.18)";
      for (var g = 0; g < state.canvasGenislik; g += 16) {
        ctx.fillRect(g, state.zeminY + 6, 8, 2);
        if (g % 48 === 0) ctx.fillRect(g + 2, state.zeminY + 2, 2, 10);
      }
    } else if (detay === "healing") {
      ctx.fillStyle = "rgba(255, 220, 244, 0.22)";
      for (var u = 0; u < state.canvasGenislik; u += 14) {
        ctx.fillRect(u, state.zeminY + 3, 2, 6);
        ctx.fillRect(u + 3, state.zeminY + 7, 2, 4);
      }
    }

    ctx.restore();
  }

  function setParcalariniCiz(ctx, katman) {
    if (!BY.seviye || !BY.varliklar || typeof BY.seviye.setParcalariAl !== "function") return;
    var veri = mevcutSeviyeAl();
    var liste = BY.seviye.setParcalariAl(katman);
    for (var i = 0; i < liste.length; i++) {
      BY.varliklar.setParcasiCiz(ctx, liste[i], veri.aksan);
    }
  }

  function dunyayaOzelProceduralVurguCiz(ctx, seviye, zaman) {
    var state = BY.state;

    ctx.save();
    if (seviye.id === "mergen") {
      ctx.strokeStyle = "rgba(126,213,255,0.18)";
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(state.canvasGenislik * 0.82, state.zeminY * 0.28, 18 + Math.sin(zaman * 0.004) * 4, Math.PI * 1.1, Math.PI * 1.9);
      ctx.stroke();
    } else if (seviye.id === "ulgen") {
      ctx.fillStyle = "rgba(174,232,255,0.12)";
      ctx.fillRect(state.canvasGenislik * 0.68, state.zeminY * 0.16, 10, state.zeminY * 0.40);
      ctx.fillRect(state.canvasGenislik * 0.71, state.zeminY * 0.22, 4, state.zeminY * 0.30);
    } else if (seviye.id === "kayra") {
      ctx.fillStyle = "rgba(137,240,185,0.14)";
      ctx.beginPath();
      ctx.arc(state.canvasGenislik * 0.22, state.zeminY * 0.24, 18 + Math.sin(zaman * 0.003) * 3, 0, Math.PI * 2);
      ctx.fill();
    } else if (seviye.id === "erlik") {
      ctx.strokeStyle = "rgba(255,107,156,0.18)";
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(state.canvasGenislik * 0.68, state.zeminY * 0.16);
      ctx.lineTo(state.canvasGenislik * 0.74, state.zeminY * 0.28);
      ctx.lineTo(state.canvasGenislik * 0.70, state.zeminY * 0.38);
      ctx.stroke();
    } else if (seviye.id === "umay") {
      ctx.strokeStyle = "rgba(255,214,240,0.18)";
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(state.canvasGenislik * 0.74, state.zeminY * 0.22, 28 + Math.sin(zaman * 0.003) * 5, 0, Math.PI * 2);
      ctx.stroke();
    }
    ctx.restore();
  }

  BY.dunya = {
    SEVIYELER: SEVIYELER,

    baslat: function() {
      yildizlariOlustur();
      ortamTaneleriniOlustur();
      arkaPlanKayma = 0;
    },

    guncelle: function(zaman) {
      arkaPlanKayma += 0.00022;

      for (var i = 0; i < ortamTaneleri.length; i++) {
        var t = ortamTaneleri[i];
        t.x = (t.x + t.hizX + 1) % 1;
        t.y = (t.y + t.hizY) % 1;
      }
    },

    ciz: function(ctx) {
      var state = BY.state;
      var seviye = mevcutSeviyeAl();
      var zaman = performance.now();

      gokyuzuCiz(ctx, seviye);
      sisVeIsikCiz(ctx, seviye);
      yildizlariCiz(ctx, seviye, zaman);

      siluetKatmaniCiz(ctx, seviye, 0.08, state.zeminY * 0.74, seviye.siluet1);
      siluetKatmaniCiz(ctx, seviye, 0.14, state.zeminY * 0.84, seviye.siluet2);

      if (BY.varliklar) {
        BY.varliklar.dunyaArkaKatmanCiz(ctx, seviye.id, state.zeminY * 0.84, seviye.aksan);
        BY.varliklar.dunyaOrtaKatmanCiz(ctx, seviye.id, state.zeminY * 0.90, seviye.aksan);
      }

      setParcalariniCiz(ctx, "arka");
      dunyayaOzelProceduralVurguCiz(ctx, seviye, zaman);
      setParcalariniCiz(ctx, "orta");
      ortamTaneleriniCiz(ctx, seviye, zaman);
      zeminCiz(ctx, seviye);
    },

    cizOnPlan: function(ctx) {
      var state = BY.state;
      var seviye = mevcutSeviyeAl();

      setParcalariniCiz(ctx, "on");
      if (BY.varliklar) {
        BY.varliklar.dunyaOnKatmanCiz(ctx, seviye.id, state.zeminY * 0.98, seviye.aksan);
      }

      ctx.save();
      ctx.fillStyle = "rgba(0,0,0,0.08)";
      ctx.fillRect(0, state.zeminY + 18, state.canvasGenislik, state.canvasYukseklik - state.zeminY);
      ctx.restore();
    },

    seviyeDegistir: function(yeniSeviye) {
      var seviye = SEVIYELER[yeniSeviye] || SEVIYELER[0];
      BY.state.temaRenk = seviye.aksan;
      BY.state.aktifDunyaId = seviye.id;
    },

    boyutGuncelle: function() {
      yildizlariOlustur();
      ortamTaneleriniOlustur();
    },

    mevcutSeviyeAl: mevcutSeviyeAl
  };

})();