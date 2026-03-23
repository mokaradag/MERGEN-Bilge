// www/js/bilge_yolac_arayuz.js
// UI kaplama: başlık ("BİLGE YOLAÇ"), slogan rotasyonu, metin animasyonları, HUD

(function() {
  "use strict";

  var BY = window.BilgeYolac;
  if (!BY) return;

  // Slogan listesi (Türkçe karakterlerle)
  var SLOGANLAR = [
    "Görevi al, yolu aç.",
    "Bilge düşünür, anında açar.",
    "Komutu ver, yol açılsın.",
    "Karardan eyleme tek adım.",
    "Akıllı hamle, açık yol.",
    "Zoru görür, yolu açar.",
    "Planı kur, akışı aç.",
    "Her görevde bir yol aç.",
    "Bilgiden güce, güçten eyleme.",
    "Bilge Yolaç: işin önü açık.",
    "Yolu gör, hamleni yap.",
    "Bilge karar, hızlı sonuç.",
    "Stratejini kur, yolu aç.",
    "Karmaşayı çöz, akışı başlat.",
    "Doğru hamle, net sonuç.",
    "Bilgiyle yön ver, hızla ilerle.",
    "Her adımda akıl, her hamlede güç.",
    "Engeli tanı, yolu aç.",
    "Sistemi anla, sonucu hızlandır.",
    "Akıl ile ilerle, yol kendiliğinden açılsın."
  ];

  // Arayuz durumu
  var mevcutSloganIndex = 0;
  var sloganZamanlayici = 0;
  var sloganOpaklik = 1;
  var sloganGecis = false;
  var sloganAnimTuru = "fade"; // fade, slide, blink
  var sloganSlideOfset = 0;

  var baslikParlama = 0;
  var tiklaYanipSonme = 0;

  var SLOGAN_DEGISIM_SURESI = 4000; // 4 saniye
  var SLOGAN_GECIS_SURESI = 800;    // Geçiş animasyonu

  // Piksel yazı çizim yardımcısı
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

  // Başlık çiz
  function baslikCiz(ctx) {
    var state = BY.state;
    var merkezX = state.canvasGenislik / 2;
    var baslikY = state.canvasYukseklik * 0.12;

    // Başlık boyutu - responsive
    var baslikBoyut = Math.min(36, state.canvasGenislik * 0.05);
    if (baslikBoyut < 18) baslikBoyut = 18;

    // Parlama efekti
    baslikParlama = 4 + Math.sin(performance.now() * 0.002) * 3;

    // Ana renk - aksan renginden
    var seviye = BY.dunya ? BY.dunya.mevcutSeviyeAl() : null;
    var baslikRenk = seviye ? seviye.aksan : "#00E5FF";

    // Alt glow
    ctx.save();
    ctx.shadowColor = baslikRenk;
    ctx.shadowBlur = baslikParlama + 8;
    ctx.font = "bold " + baslikBoyut + "px monospace";
    ctx.textAlign = "center";
    ctx.fillStyle = baslikRenk;
    ctx.globalAlpha = 0.3;
    ctx.fillText("BİLGE YOLAÇ", merkezX, baslikY);
    ctx.restore();

    // Ana başlık
    pikselYaziCiz(ctx, "BİLGE YOLAÇ", merkezX, baslikY, baslikBoyut, "#FFFFFF", true, baslikParlama);

    // Alt başlık
    var altBaslikBoyut = Math.max(10, baslikBoyut * 0.35);
    ctx.save();
    ctx.font = altBaslikBoyut + "px monospace";
    ctx.textAlign = "center";
    ctx.fillStyle = "rgba(255,255,255,0.4)";
    ctx.fillText("[ AJAN TERMINALI ]", merkezX, baslikY + baslikBoyut * 0.6);
    ctx.restore();
  }

  // Slogan çiz
  function sloganCiz(ctx) {
    var state = BY.state;
    var merkezX = state.canvasGenislik / 2;
    var sloganY = state.canvasYukseklik * 0.22;
    var sloganBoyut = Math.max(11, Math.min(16, state.canvasGenislik * 0.022));

    var seviye = BY.dunya ? BY.dunya.mevcutSeviyeAl() : null;
    var sloganRenk = seviye ? seviye.aksan : "#00E5FF";

    var metin = SLOGANLAR[mevcutSloganIndex];

    ctx.save();

    switch (sloganAnimTuru) {
      case "fade":
        ctx.globalAlpha = sloganOpaklik;
        pikselYaziCiz(ctx, metin, merkezX, sloganY, sloganBoyut, sloganRenk, false, 4);
        break;

      case "slide":
        ctx.globalAlpha = sloganOpaklik;
        pikselYaziCiz(ctx, metin, merkezX + sloganSlideOfset, sloganY, sloganBoyut, sloganRenk, false, 4);
        break;

      case "blink":
        var gorunur = Math.floor(performance.now() / 200) % 2 === 0;
        if (gorunur || !sloganGecis) {
          ctx.globalAlpha = sloganOpaklik;
          pikselYaziCiz(ctx, metin, merkezX, sloganY, sloganBoyut, sloganRenk, false, 4);
        }
        break;
    }

    ctx.restore();
  }

  // Alt bilgi çiz
  function altBilgiCiz(ctx) {
    var state = BY.state;
    var merkezX = state.canvasGenislik / 2;
    var altY = state.canvasYukseklik * 0.93;
    var altBoyut = Math.max(10, Math.min(14, state.canvasGenislik * 0.018));

    // "BAŞLAMAK İÇİN TIKLA" - yanıp sönen
    tiklaYanipSonme = 0.5 + Math.sin(performance.now() * 0.003) * 0.4;

    ctx.save();
    ctx.globalAlpha = tiklaYanipSonme;
    ctx.font = "bold " + altBoyut + "px monospace";
    ctx.textAlign = "center";
    ctx.fillStyle = "#FFFFFF";
    ctx.shadowColor = "#FFFFFF";
    ctx.shadowBlur = 4;
    ctx.fillText("BAŞLAMAK İÇİN TIKLA", merkezX, altY);
    ctx.restore();

    // "REHBERİNİ SEÇ" - sabit
    ctx.save();
    ctx.font = (altBoyut - 2) + "px monospace";
    ctx.textAlign = "center";
    ctx.fillStyle = "rgba(255,255,255,0.35)";
    ctx.fillText("REHBERİNİ SEÇ", merkezX, altY + altBoyut + 4);
    ctx.restore();
  }

  // Seviye bilgisi HUD
  function seviyeHUDCiz(ctx) {
    var state = BY.state;
    var seviye = BY.dunya ? BY.dunya.mevcutSeviyeAl() : null;
    if (!seviye) return;

    var hudX = 12;
    var hudY = state.canvasYukseklik - 20;

    ctx.save();
    ctx.font = "9px monospace";
    ctx.textAlign = "left";
    ctx.fillStyle = "rgba(255,255,255,0.25)";
    ctx.fillText("Seviye " + (state.mevcutSeviye + 1) + "/5: " + seviye.isim, hudX, hudY);
    ctx.restore();
  }

  // Dış arayüz
  BY.arayuz = {
    SLOGANLAR: SLOGANLAR,

    baslat: function() {
      mevcutSloganIndex = Math.floor(Math.random() * SLOGANLAR.length);
      sloganZamanlayici = performance.now();
      sloganOpaklik = 1;
      sloganGecis = false;
      sloganAnimTuru = "fade";
    },

    guncelle: function(zaman) {
      var gecenSure = zaman - sloganZamanlayici;

      // Slogan geçiş kontrolü
      if (gecenSure > SLOGAN_DEGISIM_SURESI && !sloganGecis) {
        sloganGecis = true;
        // Rastgele animasyon turu sec
        var turler = ["fade", "slide", "blink"];
        sloganAnimTuru = turler[Math.floor(Math.random() * turler.length)];
      }

      if (sloganGecis) {
        var gecisIlerleme = (gecenSure - SLOGAN_DEGISIM_SURESI) / SLOGAN_GECIS_SURESI;

        if (gecisIlerleme < 0.5) {
          // Kaybolma
          sloganOpaklik = 1 - gecisIlerleme * 2;
          if (sloganAnimTuru === "slide") {
            sloganSlideOfset = -gecisIlerleme * 100;
          }
        } else if (gecisIlerleme < 1) {
          // Yeni slogan belirme
          if (gecisIlerleme < 0.55) {
            mevcutSloganIndex = (mevcutSloganIndex + 1) % SLOGANLAR.length;
            sloganSlideOfset = 50;
          }
          sloganOpaklik = (gecisIlerleme - 0.5) * 2;
          if (sloganAnimTuru === "slide") {
            sloganSlideOfset = 50 * (1 - (gecisIlerleme - 0.5) * 2);
          }
        } else {
          // Geçiş tamamlandı
          sloganGecis = false;
          sloganOpaklik = 1;
          sloganSlideOfset = 0;
          sloganZamanlayici = zaman;
        }
      }
    },

    ciz: function(ctx) {
      baslikCiz(ctx);
      sloganCiz(ctx);
      altBilgiCiz(ctx);
      seviyeHUDCiz(ctx);
    }
  };

})();