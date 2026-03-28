// www/js/bilge_yolac_arayuz.js
// Oyun arayüzü: başlık ekranı, slogan rotasyonu, HUD (sağlık çubuğu, skor, seviye), seviye tamamlanma ekranı, ilerleme çubuğu

(function() {
  "use strict";

  var BY = window.BilgeYolac;
  if (!BY) return;

  // ── Slogan listesi (Türkçe karakterlerle) ───────────────────────────────
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

  // ── Arayüz dahili durumu ─────────────────────────────────────────────────
  var mevcutSloganIndex = 0;
  var sloganZamanlayici = 0;
  var sloganOpaklik = 1;
  var sloganGecis = false;
  var sloganAnimTuru = "fade"; // fade | slide | blink
  var sloganSlideOfset = 0;

  var baslikParlama = 0;
  var tiklaYanipSonme = 0;

  // Zafer durumu için yardımcılar
  var zaferBaslangicZamani = 0;

  var SLOGAN_DEGISIM_SURESI = 4000; // 4 saniye
  var SLOGAN_GECIS_SURESI = 800;    // Geçiş animasyonu süresi

  // ════════════════════════════════════════════════════════════════════════
  //  YARDIMCI FONKSİYONLAR
  // ════════════════════════════════════════════════════════════════════════

  // Piksel görünümlü metin çiz (gölge ve parlama opsiyonlu)
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

  // Yatay sağlık çubuğu çiz
  function saglikCubugu(ctx, x, y, genislik, yukseklik, oran, kenarRenk) {
    oran = Math.max(0, Math.min(1, oran));

    // Koyu arka plan
    ctx.save();
    ctx.fillStyle = "rgba(0,0,0,0.6)";
    ctx.fillRect(x, y, genislik, yukseklik);

    // Sağlık rengi: yeşilden kırmızıya geçiş
    var dolguRenk;
    if (oran > 0.6) {
      dolguRenk = "#2ECC71"; // Yeşil
    } else if (oran > 0.3) {
      dolguRenk = "#F1C40F"; // Sarı
    } else {
      dolguRenk = "#E74C3C"; // Kırmızı
    }

    // Dolgu gradyanı
    var dolguGenislik = genislik * oran;
    if (dolguGenislik > 0) {
      var grad = ctx.createLinearGradient(x, y, x, y + yukseklik);
      grad.addColorStop(0, dolguRenk);
      grad.addColorStop(1, "rgba(0,0,0,0.3)");
      ctx.fillStyle = grad;
      ctx.fillRect(x, y, dolguGenislik, yukseklik);
    }

    // İnce kenar çizgisi
    ctx.strokeStyle = kenarRenk || "rgba(255,255,255,0.3)";
    ctx.lineWidth = 1;
    ctx.strokeRect(x, y, genislik, yukseklik);

    ctx.restore();
  }

  // Beş köşeli yıldız çiz
  function yildizCiz(ctx, merkezX, merkezY, yaricap, renk, dolu) {
    ctx.save();
    ctx.beginPath();
    for (var i = 0; i < 5; i++) {
      var disAci = (i * 2 * Math.PI / 5) - Math.PI / 2;
      var icAci = disAci + Math.PI / 5;
      var icYaricap = yaricap * 0.4;

      if (i === 0) {
        ctx.moveTo(merkezX + Math.cos(disAci) * yaricap, merkezY + Math.sin(disAci) * yaricap);
      } else {
        ctx.lineTo(merkezX + Math.cos(disAci) * yaricap, merkezY + Math.sin(disAci) * yaricap);
      }
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

  // ════════════════════════════════════════════════════════════════════════
  //  BAŞLIK EKRANI (oyunDurumu === "bekleme")
  // ════════════════════════════════════════════════════════════════════════

  function baslikEkraniCiz(ctx) {
    var state = BY.state;
    var merkezX = state.canvasGenislik / 2;

    // ── Ana başlık: "BİLGE YOLAÇ" ──
    var baslikY = state.canvasYukseklik * 0.12;
    var baslikBoyut = Math.min(36, state.canvasGenislik * 0.05);
    if (baslikBoyut < 18) baslikBoyut = 18;

    // Parlama efekti
    baslikParlama = 4 + Math.sin(performance.now() * 0.002) * 3;

    // Aksan rengini al
    var seviye = BY.dunya ? BY.dunya.mevcutSeviyeAl() : null;
    var baslikRenk = seviye ? seviye.aksan : "#00E5FF";

    // Alt ışıma
    ctx.save();
    ctx.shadowColor = baslikRenk;
    ctx.shadowBlur = baslikParlama + 8;
    ctx.font = "bold " + baslikBoyut + "px monospace";
    ctx.textAlign = "center";
    ctx.fillStyle = baslikRenk;
    ctx.globalAlpha = 0.3;
    ctx.fillText("BİLGE YOLAÇ", merkezX, baslikY);
    ctx.restore();

    // Ana başlık metni
    pikselYaziCiz(ctx, "BİLGE YOLAÇ", merkezX, baslikY, baslikBoyut, "#FFFFFF", true, baslikParlama);

    // ── Alt başlık: "[ AJAN TERMİNALİ ]" ──
    var altBaslikBoyut = Math.max(10, baslikBoyut * 0.35);
    ctx.save();
    ctx.font = altBaslikBoyut + "px monospace";
    ctx.textAlign = "center";
    ctx.fillStyle = "rgba(255,255,255,0.4)";
    ctx.fillText("[ AJAN TERMİNALİ ]", merkezX, baslikY + baslikBoyut * 0.6);
    ctx.restore();

    // ── Slogan ──
    sloganCiz(ctx, merkezX);

    // ── "BAŞLAMAK İÇİN TIKLA" (nabız atan) ──
    var altY = state.canvasYukseklik * 0.93;
    var altBoyut = Math.max(10, Math.min(14, state.canvasGenislik * 0.018));
    tiklaYanipSonme = 0.5 + Math.sin(performance.now() * 0.003) * 0.4;

    ctx.save();
    ctx.globalAlpha = tiklaYanipSonme;
    ctx.font = "bold " + altBoyut + "px monospace";
    ctx.textAlign = "center";
    ctx.fillStyle = "#FFFFFF";
    ctx.shadowColor = "#FFFFFF";
    ctx.shadowBlur = 4;
    ctx.fillText("BAŞLAMAK İÇİN TIKLA veya BOŞLUK", merkezX, altY);
    ctx.restore();

    // ── Sol alt köşede seviye ismi ──
    seviyeIsminiCiz(ctx);
  }

  // Slogan çiz
  function sloganCiz(ctx, merkezX) {
    var state = BY.state;
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

  // Sol alt köşede seviye ismi
  function seviyeIsminiCiz(ctx) {
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

  // ════════════════════════════════════════════════════════════════════════
  //  OYUN HUD (oyunDurumu !== "bekleme")
  // ════════════════════════════════════════════════════════════════════════

  function oyunHUDCiz(ctx) {
    var state = BY.state;

    // ── İlerleme çubuğu (en üstte ince çizgi) ──
    ilerlemeBarCiz(ctx);

    // ── Sol üst: Takım sağlık çubuğu ──
    takimSaglikCiz(ctx);

    // ── Sağ üst: Skor ve seviye göstergesi ──
    skorVeSeviyeCiz(ctx);

    // ── Alt: Yetenek bekleme süreleri göstergeleri ──
    yetenekGostergeleriCiz(ctx);

    // ── Alt sol: Kontrol ipuçları ──
    kontrolIpuclariCiz(ctx);

    // ── Üst orta: Boss sağlık çubuğu (boss aktifse) ──
    if (state.oyunDurumu === "boss") {
      bossSaglikCiz(ctx);
    }
  }

  // En üstte ince ilerleme çubuğu (takımın seviye içindeki konumu)
  function ilerlemeBarCiz(ctx) {
    var state = BY.state;

    // Çıkış noktasını hesapla
    var cikisX = state.dunyaGenislik;
    if (BY.seviye && typeof BY.seviye.cikisNoktasiAl === "function") {
      var cikis = BY.seviye.cikisNoktasiAl();
      if (cikis && cikis.x) cikisX = cikis.x;
    }

    // Takım merkez konumu
    var takimX = 0;
    var karakterler = state.karakterler;
    if (karakterler.length > 0) {
      for (var i = 0; i < karakterler.length; i++) {
        takimX += karakterler[i].x;
      }
      takimX /= karakterler.length;
    }

    var oran = Math.min(1, Math.max(0, takimX / cikisX));
    var barYukseklik = 2;

    ctx.save();
    // Arka plan
    ctx.fillStyle = "rgba(255,255,255,0.1)";
    ctx.fillRect(0, 0, state.canvasGenislik, barYukseklik);

    // Dolgu
    var seviye = BY.dunya ? BY.dunya.mevcutSeviyeAl() : null;
    var renk = seviye ? seviye.aksan : "#00E5FF";
    ctx.fillStyle = renk;
    ctx.fillRect(0, 0, state.canvasGenislik * oran, barYukseklik);
    ctx.restore();
  }

  // Sol üst: Takım sağlık çubuğu
  function takimSaglikCiz(ctx) {
    var state = BY.state;
    var x = 12;
    var y = 10;
    var genislik = 150;
    var yukseklik = 12;

    // Güvenli sayısal değerler (NaN / undefined koruması)
    var takimCan = (typeof state.takimCan === "number" && !isNaN(state.takimCan))
      ? state.takimCan : 0;
    var takimMaxCan = (typeof state.takimMaxCan === "number" && !isNaN(state.takimMaxCan) && state.takimMaxCan > 0)
      ? state.takimMaxCan : 100;

    // Etiket
    ctx.save();
    ctx.font = "bold 9px monospace";
    ctx.textAlign = "left";
    ctx.fillStyle = "rgba(255,255,255,0.6)";
    ctx.fillText("TAKIM", x, y - 2);
    ctx.restore();

    // Sağlık çubuğu
    var oran = takimCan / takimMaxCan;
    saglikCubugu(ctx, x, y, genislik, yukseklik, oran);

    // Sayısal değer
    ctx.save();
    ctx.font = "bold 8px monospace";
    ctx.textAlign = "center";
    ctx.fillStyle = "#FFFFFF";
    ctx.fillText(Math.ceil(takimCan) + "/" + takimMaxCan, x + genislik / 2, y + yukseklik - 2);
    ctx.restore();
  }

  // Sağ üst: Skor ve seviye göstergesi
  function skorVeSeviyeCiz(ctx) {
    var state = BY.state;
    var sagX = state.canvasGenislik - 12;

    // Güvenli sayısal değerler
    var skor = (typeof state.skor === "number" && !isNaN(state.skor)) ? state.skor : 0;
    var seviye = (typeof state.mevcutSeviye === "number" && !isNaN(state.mevcutSeviye))
      ? state.mevcutSeviye : 0;

    // Skor
    ctx.save();
    ctx.font = "bold 11px monospace";
    ctx.textAlign = "right";
    ctx.fillStyle = "#FFD700";
    ctx.shadowColor = "#FFD700";
    ctx.shadowBlur = 3;
    ctx.fillText("SKOR: " + skor, sagX, 18);
    ctx.restore();

    // Seviye göstergesi
    ctx.save();
    ctx.font = "9px monospace";
    ctx.textAlign = "right";
    ctx.fillStyle = "rgba(255,255,255,0.5)";
    ctx.fillText("SEVİYE: " + (seviye + 1) + "/5", sagX, 30);
    ctx.restore();
  }

  // Yetenek bekleme süreleri göstergeleri (alt kısımda 5 küçük daire)
  function yetenekGostergeleriCiz(ctx) {
    var state = BY.state;
    var karakterler = state.karakterler;
    if (karakterler.length === 0) return;

    var merkezX = state.canvasGenislik / 2;
    var y = state.canvasYukseklik - 18;
    var yaricap = 8;
    var aralik = 26;
    var baslangicX = merkezX - (karakterler.length - 1) * aralik / 2;

    for (var i = 0; i < karakterler.length; i++) {
      var k = karakterler[i];
      var cx = baslangicX + i * aralik;

      // Bekleme süresi oranını hesapla
      var beklemeSuresi = k.yetenekBeklemeSuresi || 0;
      var maxBekleme = k.yetenekMaxBekleme || 1;
      var oran = 1 - Math.min(1, beklemeSuresi / maxBekleme);

      // Arka plan daire
      ctx.save();
      ctx.beginPath();
      ctx.arc(cx, y, yaricap, 0, Math.PI * 2);
      ctx.fillStyle = "rgba(0,0,0,0.5)";
      ctx.fill();

      // Dolum yayı (saat yönünde dolar)
      if (oran > 0) {
        ctx.beginPath();
        ctx.moveTo(cx, y);
        ctx.arc(cx, y, yaricap, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * oran);
        ctx.closePath();
        ctx.fillStyle = k.renkler ? k.renkler.ana : "#FFFFFF";
        ctx.globalAlpha = 0.7;
        ctx.fill();
      }

      // Kenar çizgisi
      ctx.globalAlpha = 0.4;
      ctx.beginPath();
      ctx.arc(cx, y, yaricap, 0, Math.PI * 2);
      ctx.strokeStyle = "rgba(255,255,255,0.4)";
      ctx.lineWidth = 1;
      ctx.stroke();

      ctx.restore();
    }
  }

  // Alt sol: Kontrol ipuçları (oyun sırasında küçük metin)
  function kontrolIpuclariCiz(ctx) {
    var state = BY.state;
    if (state.oyunDurumu !== "oynuyor" && state.oyunDurumu !== "boss") return;

    var x = 12;
    var y = state.canvasYukseklik - 8;

    ctx.save();
    ctx.font = "8px monospace";
    ctx.textAlign = "left";
    ctx.fillStyle = "rgba(255,255,255,0.35)";
    ctx.fillText("TIKLA: Takım Saldırısı  |  BOŞLUK: Hızlan", x, y);
    ctx.restore();
  }

  // Üst orta: Boss sağlık çubuğu
  function bossSaglikCiz(ctx) {
    var state = BY.state;
    var dusmanlar = state.dusmanlar;

    // Boss düşmanı bul
    var boss = null;
    for (var i = 0; i < dusmanlar.length; i++) {
      if (dusmanlar[i].tip === "boss") {
        boss = dusmanlar[i];
        break;
      }
    }
    if (!boss) return;

    var merkezX = state.canvasGenislik / 2;
    var barGenislik = 200;
    var barYukseklik = 14;
    var y = 8;

    // Boss ismi
    ctx.save();
    ctx.font = "bold 10px monospace";
    ctx.textAlign = "center";
    ctx.fillStyle = "#FFD700";
    ctx.shadowColor = "#FFD700";
    ctx.shadowBlur = 4;
    ctx.fillText(boss.isim || "BOSS", merkezX, y - 1);
    ctx.restore();

    // Boss sağlık çubuğu
    var oran = (boss.can || 0) / (boss.maxCan || 1);
    saglikCubugu(ctx, merkezX - barGenislik / 2, y + 2, barGenislik, barYukseklik, oran, "#FFD700");
  }

  // ════════════════════════════════════════════════════════════════════════
  //  SEVİYE TAMAMLANDI EKRANI (oyunDurumu === "zafer")
  // ════════════════════════════════════════════════════════════════════════

  function zaferEkraniCiz(ctx) {
    var state = BY.state;
    var merkezX = state.canvasGenislik / 2;
    var merkezY = state.canvasYukseklik * 0.35;

    // Yarı saydam karartma
    ctx.save();
    ctx.fillStyle = "rgba(0,0,0,0.4)";
    ctx.fillRect(0, 0, state.canvasGenislik, state.canvasYukseklik);
    ctx.restore();

    // "SEVİYE TAMAMLANDI!" başlığı
    var baslikBoyut = Math.min(28, state.canvasGenislik * 0.04);
    if (baslikBoyut < 16) baslikBoyut = 16;
    pikselYaziCiz(ctx, "SEVİYE TAMAMLANDI!", merkezX, merkezY, baslikBoyut, "#FFD700", true, 8);

    // Skor gösterimi
    ctx.save();
    ctx.font = "bold 14px monospace";
    ctx.textAlign = "center";
    ctx.fillStyle = "#FFFFFF";
    ctx.fillText("SKOR: " + state.skor, merkezX, merkezY + 35);
    ctx.restore();

    // Yıldız derecelendirme (kalan sağlığa göre)
    var saglikOrani = state.takimCan / state.takimMaxCan;
    var yildizSayisi;
    if (saglikOrani > 0.8) {
      yildizSayisi = 3;
    } else if (saglikOrani > 0.5) {
      yildizSayisi = 2;
    } else {
      yildizSayisi = 1;
    }

    var yildizY = merkezY + 65;
    var yildizAralik = 30;
    var yildizBaslangicX = merkezX - yildizAralik;

    for (var i = 0; i < 3; i++) {
      var dolu = i < yildizSayisi;
      yildizCiz(ctx, yildizBaslangicX + i * yildizAralik, yildizY, 12, "#FFD700", dolu);
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  SLOGAN GÜNCELLEME MANTIĞI
  // ════════════════════════════════════════════════════════════════════════

  function sloganGuncelle(zaman) {
    var gecenSure = zaman - sloganZamanlayici;

    // Slogan geçiş kontrolü
    if (gecenSure > SLOGAN_DEGISIM_SURESI && !sloganGecis) {
      sloganGecis = true;
      // Rastgele animasyon türü seç
      var turler = ["fade", "slide", "blink"];
      sloganAnimTuru = turler[Math.floor(Math.random() * turler.length)];
    }

    if (sloganGecis) {
      var gecisIlerleme = (gecenSure - SLOGAN_DEGISIM_SURESI) / SLOGAN_GECIS_SURESI;

      if (gecisIlerleme < 0.5) {
        // Kaybolma fazı
        sloganOpaklik = 1 - gecisIlerleme * 2;
        if (sloganAnimTuru === "slide") {
          sloganSlideOfset = -gecisIlerleme * 100;
        }
      } else if (gecisIlerleme < 1) {
        // Yeni slogan belirme fazı
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
  }

  // ════════════════════════════════════════════════════════════════════════
  //  DIŞ ARAYÜZ
  // ════════════════════════════════════════════════════════════════════════

  BY.arayuz = {
    SLOGANLAR: SLOGANLAR,

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

      // Bekleme durumunda slogan rotasyonu
      if (state.oyunDurumu === "bekleme") {
        sloganGuncelle(zaman);
      }

      // Zafer ekranı zamanlayıcısı
      if (state.oyunDurumu === "zafer" && zaferBaslangicZamani === 0) {
        zaferBaslangicZamani = zaman;
      }
      if (state.oyunDurumu !== "zafer") {
        zaferBaslangicZamani = 0;
      }
    },

    ciz: function(ctx) {
      var state = BY.state;

      if (state.oyunDurumu === "bekleme") {
        // Başlık ekranı
        baslikEkraniCiz(ctx);
      } else {
        // Oyun HUD
        oyunHUDCiz(ctx);

        // Zafer ekranı (HUD üzerine çizilir)
        if (state.oyunDurumu === "zafer") {
          zaferEkraniCiz(ctx);
        }
      }
    }
  };

})();