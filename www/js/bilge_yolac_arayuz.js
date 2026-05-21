// www/js/bilge_yolac_arayuz.js
// Oyun arayüzü: başlık ekranı, slogan rotasyonu, HUD, dünya alt başlığı,
// boss sağlık çubuğu ve yeni klavye kontrol ipuçları.

(function() {
  "use strict";

  var BY = window.BilgeYolac;
  if (!BY) return;

  var SLOGANLAR = [
    "Görevi al, yolu aç.",
    "Bilgi, sezgi, hareket.",
    "Ajan ritmi başladı.",
    "Strateji kur, ekibi yönet.",
    "Dünya katman katman açılıyor.",
    "Retro ruh, yeni derinlik.",
    "Her dünya ayrı bir düzen.",
    "Çözüm, sinyal, rota, doğrulama, rehberlik.",
    "Bilge düşünür, takım uygular.",
    "Sınırı geç, ritmi yakala."
  ];

  var mevcutSloganIndex = 0;
  var sloganZamanlayici = 0;
  var sloganOpaklik = 1;
  var sloganGecis = false;
  var sloganAnimTuru = "fade";
  var sloganSlideOfset = 0;
  var baslikParlama = 0;
  var tiklaYanipSonme = 0;
  var zaferBaslangicZamani = 0;

  var SLOGAN_DEGISIM_SURESI = 3800;
  var SLOGAN_GECIS_SURESI = 800;

  function pikselYaziCiz(ctx, metin, x, y, boyut, renk, golge, parlama) {
    ctx.save();
    if (parlama && parlama > 0) {
      ctx.shadowColor = renk;
      ctx.shadowBlur = parlama;
    }
    if (golge) {
      ctx.font = "bold " + boyut + "px monospace";
      ctx.textAlign = "center";
      ctx.fillStyle = "rgba(0,0,0,0.6)";
      ctx.fillText(metin, x + 2, y + 2);
    }
    ctx.font = "bold " + boyut + "px monospace";
    ctx.textAlign = "center";
    ctx.fillStyle = renk;
    ctx.fillText(metin, x, y);
    ctx.restore();
  }

  function saglikCubugu(ctx, x, y, genislik, yukseklik, oran, kenarRenk) {
    oran = Math.max(0, Math.min(1, oran));
    ctx.save();
    ctx.fillStyle = "rgba(0,0,0,0.6)";
    ctx.fillRect(x, y, genislik, yukseklik);
    var renk = oran > 0.6 ? "#2ECC71" : (oran > 0.3 ? "#F1C40F" : "#E74C3C");
    var dolgu = ctx.createLinearGradient(x, y, x, y + yukseklik);
    dolgu.addColorStop(0, renk);
    dolgu.addColorStop(1, "rgba(0,0,0,0.3)");
    ctx.fillStyle = dolgu;
    ctx.fillRect(x, y, genislik * oran, yukseklik);
    ctx.strokeStyle = kenarRenk || "rgba(255,255,255,0.3)";
    ctx.lineWidth = 1;
    ctx.strokeRect(x, y, genislik, yukseklik);
    ctx.restore();
  }

  function yildizCiz(ctx, merkezX, merkezY, yaricap, renk, dolu) {
    ctx.save();
    ctx.beginPath();
    for (var i = 0; i < 5; i++) {
      var disAci = (i * 2 * Math.PI / 5) - Math.PI / 2;
      var icAci = disAci + Math.PI / 5;
      var icYaricap = yaricap * 0.4;
      if (i === 0) ctx.moveTo(merkezX + Math.cos(disAci) * yaricap, merkezY + Math.sin(disAci) * yaricap);
      else ctx.lineTo(merkezX + Math.cos(disAci) * yaricap, merkezY + Math.sin(disAci) * yaricap);
      ctx.lineTo(merkezX + Math.cos(icAci) * icYaricap, merkezY + Math.sin(icAci) * icYaricap);
    }
    ctx.closePath();
    if (dolu) {
      ctx.fillStyle = renk;
      ctx.shadowColor = renk;
      ctx.shadowBlur = 6;
      ctx.fill();
    } else {
      ctx.strokeStyle = renk;
      ctx.lineWidth = 1.5;
      ctx.globalAlpha = 0.3;
      ctx.stroke();
    }
    ctx.restore();
  }

  function sloganGuncelle(zaman) {
    var gecenSure = zaman - sloganZamanlayici;
    if (gecenSure > SLOGAN_DEGISIM_SURESI && !sloganGecis) {
      sloganGecis = true;
      var turler = ["fade", "slide", "blink"];
      sloganAnimTuru = turler[Math.floor(Math.random() * turler.length)];
    }

    if (!sloganGecis) return;

    var ilerleme = (gecenSure - SLOGAN_DEGISIM_SURESI) / SLOGAN_GECIS_SURESI;
    if (ilerleme < 0.5) {
      sloganOpaklik = 1 - ilerleme * 2;
      if (sloganAnimTuru === "slide") sloganSlideOfset = -ilerleme * 100;
    } else if (ilerleme < 1) {
      if (ilerleme < 0.55) {
        mevcutSloganIndex = (mevcutSloganIndex + 1) % SLOGANLAR.length;
        sloganSlideOfset = 50;
      }
      sloganOpaklik = (ilerleme - 0.5) * 2;
      if (sloganAnimTuru === "slide") sloganSlideOfset = 50 * (1 - (ilerleme - 0.5) * 2);
    } else {
      sloganGecis = false;
      sloganOpaklik = 1;
      sloganSlideOfset = 0;
      sloganZamanlayici = zaman;
    }
  }

  function sloganCiz(ctx, merkezX) {
    var state = BY.state;
    var y = state.canvasYukseklik * 0.22;
    var boyut = Math.max(11, Math.min(16, state.canvasGenislik * 0.022));
    var seviye = BY.dunya ? BY.dunya.mevcutSeviyeAl() : null;
    var renk = seviye ? seviye.aksan : "#00E5FF";
    var metin = SLOGANLAR[mevcutSloganIndex];

    ctx.save();
    if (sloganAnimTuru === "blink") {
      if (Math.floor(performance.now() / 200) % 2 === 0 || !sloganGecis) {
        ctx.globalAlpha = sloganOpaklik;
        pikselYaziCiz(ctx, metin, merkezX, y, boyut, renk, false, 4);
      }
    } else if (sloganAnimTuru === "slide") {
      ctx.globalAlpha = sloganOpaklik;
      pikselYaziCiz(ctx, metin, merkezX + sloganSlideOfset, y, boyut, renk, false, 4);
    } else {
      ctx.globalAlpha = sloganOpaklik;
      pikselYaziCiz(ctx, metin, merkezX, y, boyut, renk, false, 4);
    }
    ctx.restore();
  }

  function seviyeMetniCiz(ctx) {
    var state = BY.state;
    var seviye = BY.dunya ? BY.dunya.mevcutSeviyeAl() : null;
    if (!seviye) return;

    ctx.save();
    ctx.font = "9px monospace";
    ctx.textAlign = "left";
    ctx.fillStyle = "rgba(255,255,255,0.25)";
    ctx.fillText("Seviye " + (state.mevcutSeviye + 1) + "/5: " + seviye.isim, 12, state.canvasYukseklik - 22);
    ctx.fillStyle = "rgba(255,255,255,0.18)";
    ctx.fillText(seviye.altBaslik || "", 12, state.canvasYukseklik - 10);
    ctx.restore();
  }

  function baslikEkraniCiz(ctx) {
    var state = BY.state;
    var seviye = BY.dunya ? BY.dunya.mevcutSeviyeAl() : null;
    var merkezX = state.canvasGenislik / 2;
    var baslikY = state.canvasYukseklik * 0.12;
    var baslikBoyut = Math.max(18, Math.min(36, state.canvasGenislik * 0.05));
    var baslikRenk = seviye ? seviye.aksan : "#00E5FF";

    baslikParlama = 4 + Math.sin(performance.now() * 0.002) * 3;

    ctx.save();
    ctx.shadowColor = baslikRenk;
    ctx.shadowBlur = baslikParlama + 8;
    ctx.font = "bold " + baslikBoyut + "px monospace";
    ctx.textAlign = "center";
    ctx.fillStyle = baslikRenk;
    ctx.globalAlpha = 0.3;
    ctx.fillText("BİLGE YOLAÇ", merkezX, baslikY);
    ctx.restore();

    pikselYaziCiz(ctx, "BİLGE YOLAÇ", merkezX, baslikY, baslikBoyut, "#FFFFFF", true, baslikParlama);

    ctx.save();
    ctx.font = Math.max(10, baslikBoyut * 0.35) + "px monospace";
    ctx.textAlign = "center";
    ctx.fillStyle = "rgba(255,255,255,0.45)";
    ctx.fillText("[ RETRO AJAN ALANI ]", merkezX, baslikY + baslikBoyut * 0.6);
    ctx.restore();

    if (seviye) {
      ctx.save();
      ctx.font = "bold 12px monospace";
      ctx.textAlign = "center";
      ctx.fillStyle = seviye.aksan;
      ctx.globalAlpha = 0.8;
      ctx.fillText(seviye.isim, merkezX, baslikY + baslikBoyut + 18);
      ctx.restore();
    }

    sloganCiz(ctx, merkezX);

    var altY = state.canvasYukseklik * 0.93;
    tiklaYanipSonme = 0.5 + Math.sin(performance.now() * 0.003) * 0.4;
    ctx.save();
    ctx.globalAlpha = tiklaYanipSonme;
    ctx.font = "bold 11px monospace";
    ctx.textAlign = "center";
    ctx.fillStyle = "#FFFFFF";
    ctx.shadowColor = "#FFFFFF";
    ctx.shadowBlur = 4;
    ctx.fillText("BAŞLAT: TIKLA veya BOŞLUK", merkezX, altY);
    ctx.restore();

    seviyeMetniCiz(ctx);
  }

  function ilerlemeBarCiz(ctx) {
    var state = BY.state;
    var cikis = BY.seviye && BY.seviye.cikisNoktasiAl ? BY.seviye.cikisNoktasiAl() : { x: state.dunyaGenislik };
    var karakterler = state.karakterler || [];
    var takimX = 0;

    if (karakterler.length > 0) {
      for (var i = 0; i < karakterler.length; i++) takimX += karakterler[i].x;
      takimX /= karakterler.length;
    }

    var oran = Math.min(1, Math.max(0, takimX / (cikis.x || state.dunyaGenislik)));
    ctx.save();
    ctx.fillStyle = "rgba(255,255,255,0.1)";
    ctx.fillRect(0, 0, state.canvasGenislik, 2);
    ctx.fillStyle = (BY.dunya && BY.dunya.mevcutSeviyeAl()) ? BY.dunya.mevcutSeviyeAl().aksan : "#00E5FF";
    ctx.fillRect(0, 0, state.canvasGenislik * oran, 2);
    ctx.restore();
  }

  function takimSaglikCiz(ctx) {
    var state = BY.state;
    var x = 12;
    var y = 10;
    var genislik = 150;
    var yukseklik = 12;
    var can = (typeof state.takimCan === "number" && !isNaN(state.takimCan)) ? state.takimCan : 0;
    var max = (typeof state.takimMaxCan === "number" && state.takimMaxCan > 0) ? state.takimMaxCan : 100;

    ctx.save();
    ctx.font = "bold 9px monospace";
    ctx.textAlign = "left";
    ctx.fillStyle = "rgba(255,255,255,0.6)";
    ctx.fillText("TAKIM", x, y - 2);
    ctx.restore();

    saglikCubugu(ctx, x, y, genislik, yukseklik, can / max);
    ctx.save();
    ctx.font = "bold 8px monospace";
    ctx.textAlign = "center";
    ctx.fillStyle = "#FFFFFF";
    ctx.fillText(Math.ceil(can) + "/" + max, x + genislik / 2, y + yukseklik - 2);
    ctx.restore();
  }

  function skorVeSeviyeCiz(ctx) {
    var state = BY.state;
    var sagX = state.canvasGenislik - 12;
    ctx.save();
    ctx.font = "bold 11px monospace";
    ctx.textAlign = "right";
    ctx.fillStyle = "#FFD700";
    ctx.shadowColor = "#FFD700";
    ctx.shadowBlur = 3;
    ctx.fillText("SKOR: " + (state.skor || 0), sagX, 18);
    ctx.restore();

    ctx.save();
    ctx.font = "9px monospace";
    ctx.textAlign = "right";
    ctx.fillStyle = "rgba(255,255,255,0.5)";
    ctx.fillText("SEVİYE: " + (state.mevcutSeviye + 1) + "/5", sagX, 30);
    ctx.restore();
  }

  function yetenekGostergeleriCiz(ctx) {
    var state = BY.state;
    var karakterler = state.karakterler;
    if (!karakterler || karakterler.length === 0) return;

    var merkezX = state.canvasGenislik / 2;
    var y = state.canvasYukseklik - 18;
    var yaricap = 8;
    var aralik = 26;
    var baslangicX = merkezX - (karakterler.length - 1) * aralik / 2;

    for (var i = 0; i < karakterler.length; i++) {
      var k = karakterler[i];
      var oran = k.yetenekAktif ? 1 : 0.35;

      ctx.save();
      ctx.beginPath();
      ctx.arc(baslangicX + i * aralik, y, yaricap, 0, Math.PI * 2);
      ctx.fillStyle = "rgba(0,0,0,0.5)";
      ctx.fill();

      ctx.globalAlpha = oran;
      ctx.beginPath();
      ctx.arc(baslangicX + i * aralik, y, yaricap - 2, 0, Math.PI * 2);
      ctx.fillStyle = k.renkler ? k.renkler.ana : "#FFFFFF";
      ctx.fill();

      ctx.globalAlpha = 0.6;
      ctx.beginPath();
      ctx.arc(baslangicX + i * aralik, y, yaricap, 0, Math.PI * 2);
      ctx.strokeStyle = "rgba(255,255,255,0.4)";
      ctx.lineWidth = 1;
      ctx.stroke();
      ctx.restore();
    }
  }

  function kontrolIpuclariCiz(ctx) {
    var state = BY.state;
    if (state.oyunDurumu !== "oynuyor" && state.oyunDurumu !== "boss") return;

    ctx.save();
    ctx.font = "8px monospace";
    ctx.textAlign = "left";
    ctx.fillStyle = "rgba(255,255,255,0.35)";
    ctx.fillText("← → HAREKET  |  ↑ ZIPLA  |  ↓ İN / ETKİLEŞ  |  BOŞLUK ATIL  |  TIKLA İKİNCİL SALDIRI", 12, state.canvasYukseklik - 8);
    ctx.restore();
  }

  function bossSaglikCiz(ctx) {
    var dusmanlar = BY.state.dusmanlar || [];
    var boss = null;
    for (var i = 0; i < dusmanlar.length; i++) {
      if (dusmanlar[i].tip === "boss" && dusmanlar[i].aktif) { boss = dusmanlar[i]; break; }
    }
    if (!boss) return;

    var merkezX = BY.state.canvasGenislik / 2;
    var barGenislik = 220;
    var y = 8;

    ctx.save();
    ctx.font = "bold 10px monospace";
    ctx.textAlign = "center";
    ctx.fillStyle = "#FFD700";
    ctx.shadowColor = "#FFD700";
    ctx.shadowBlur = 4;
    ctx.fillText(boss.isim || "BOSS", merkezX, y - 1);
    ctx.restore();

    saglikCubugu(ctx, merkezX - barGenislik / 2, y + 2, barGenislik, 14, (boss.can || 0) / (boss.maxCan || 1), "#FFD700");
  }

  function zaferEkraniCiz(ctx) {
    var state = BY.state;
    var merkezX = state.canvasGenislik / 2;
    var merkezY = state.canvasYukseklik * 0.35;
    var saglikOrani = state.takimCan / state.takimMaxCan;
    var yildizSayisi = saglikOrani > 0.8 ? 3 : (saglikOrani > 0.5 ? 2 : 1);

    ctx.save();
    ctx.fillStyle = "rgba(0,0,0,0.4)";
    ctx.fillRect(0, 0, state.canvasGenislik, state.canvasYukseklik);
    ctx.restore();

    pikselYaziCiz(ctx, "SEVİYE TAMAMLANDI!", merkezX, merkezY, Math.max(16, Math.min(28, state.canvasGenislik * 0.04)), "#FFD700", true, 8);

    ctx.save();
    ctx.font = "bold 14px monospace";
    ctx.textAlign = "center";
    ctx.fillStyle = "#FFFFFF";
    ctx.fillText("SKOR: " + (state.skor || 0), merkezX, merkezY + 35);
    ctx.restore();

    var yildizY = merkezY + 65;
    for (var i = 0; i < 3; i++) {
      yildizCiz(ctx, merkezX - 30 + i * 30, yildizY, 12, "#FFD700", i < yildizSayisi);
    }
  }

  BY.arayuz = {
    baslat: function() {
      mevcutSloganIndex = Math.floor(Math.random() * SLOGANLAR.length);
      sloganZamanlayici = performance.now();
      sloganOpaklik = 1;
      sloganGecis = false;
      sloganAnimTuru = "fade";
      zaferBaslangicZamani = 0;
    },

    guncelle: function(zaman) {
      var state = BY.state;
      if (state.oyunDurumu === "bekleme") sloganGuncelle(zaman);
      if (state.oyunDurumu === "zafer" && zaferBaslangicZamani === 0) zaferBaslangicZamani = zaman;
      if (state.oyunDurumu !== "zafer") zaferBaslangicZamani = 0;
    },

    ciz: function(ctx) {
      var state = BY.state;
      if (state.oyunDurumu === "bekleme") {
        baslikEkraniCiz(ctx);
        return;
      }

      ilerlemeBarCiz(ctx);
      takimSaglikCiz(ctx);
      skorVeSeviyeCiz(ctx);
      yetenekGostergeleriCiz(ctx);
      kontrolIpuclariCiz(ctx);
      seviyeMetniCiz(ctx);

      if (state.oyunDurumu === "boss") bossSaglikCiz(ctx);
      if (state.oyunDurumu === "zafer") zaferEkraniCiz(ctx);
    }
  };

})();