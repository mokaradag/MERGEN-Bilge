// www/js/bilge_yolac_efektler.js
// Gelişmiş parçacık ve efekt sistemi: radar darbeleri, tarama çizgileri, CRT parlama, yetenek efektleri, hasar sayıları, lazerler, patlamalar, kalkanlar

(function() {
  "use strict";

  var BY = window.BilgeYolac;
  if (!BY) return;

  // ── Parçacık havuzu ──────────────────────────────────────────────────────
  var parcaciklar = [];

  // ── Radar darbe efektleri ────────────────────────────────────────────────
  var radarDarbeleri = [];

  // ── Hasar sayıları dizisi ────────────────────────────────────────────────
  var hasarSayilari = [];

  // ── Lazer ışınları dizisi ────────────────────────────────────────────────
  var lazerler = [];

  // ── Kalkan efektleri dizisi ──────────────────────────────────────────────
  var kalkanlar = [];

  // ── Tarama çizgisi durumu ────────────────────────────────────────────────
  var taramaCizgiY = 0;
  var taramaAktif = true;

  // ── CRT parlama parametreleri ────────────────────────────────────────────
  var crtParlamaYogunluk = 0.03;

  // ── Periyodik ortam efektleri zamanlayıcısı ──────────────────────────────
  var sonOrtamEfekt = 0;

  // ── Yardımcı: ekran dışında mı kontrolü ─────────────────────────────────
  function ekranDisindaMi(dX, tolerans) {
    var state = BY.state;
    tolerans = tolerans || 50;
    return (dX < -tolerans || dX > state.canvasGenislik + tolerans);
  }

  // ════════════════════════════════════════════════════════════════════════
  //  PARÇACIK SİSTEMİ
  // ════════════════════════════════════════════════════════════════════════

  // Parçacık oluştur (dünya koordinatlarında x, y)
  function parcacikOlustur(x, y, renk, tur, miktar) {
    var config = BY.config;
    miktar = miktar || 5;

    for (var i = 0; i < miktar; i++) {
      if (parcaciklar.length >= config.PARCACIK_SINIRI) break;

      var aci = Math.random() * Math.PI * 2;
      var hiz = 0.5 + Math.random() * 2;

      parcaciklar.push({
        x: x,
        y: y,
        hizX: Math.cos(aci) * hiz,
        hizY: Math.sin(aci) * hiz - 1,
        boyut: 1 + Math.random() * 3,
        renk: renk,
        tur: tur || "normal",
        yasam: 60 + Math.random() * 40,
        maxYasam: 100,
        opaklik: 1,
        yercekim: tur === "yukari" ? -0.02 : 0.03
      });
    }
  }

  // Parçacıkları güncelle
  function parcaciklariGuncelle() {
    for (var i = parcaciklar.length - 1; i >= 0; i--) {
      var p = parcaciklar[i];
      p.x += p.hizX;
      p.y += p.hizY;
      p.hizY += p.yercekim;
      p.hizX *= 0.98;
      p.yasam--;
      p.opaklik = p.yasam / p.maxYasam;
      p.boyut *= 0.99;

      if (p.yasam <= 0 || p.boyut < 0.3) {
        parcaciklar.splice(i, 1);
      }
    }
  }

  // Parçacıkları çiz (dünya→ekran dönüşümü ile)
  function parcaciklariCiz(ctx) {
    var state = BY.state;

    for (var i = 0; i < parcaciklar.length; i++) {
      var p = parcaciklar[i];

      // Dünya koordinatından ekran koordinatına dönüştür
      var ekranX = p.x - state.kameraX;

      // Ekran dışındaysa atla
      if (ekranDisindaMi(ekranX, 20)) continue;

      ctx.save();
      ctx.globalAlpha = p.opaklik;

      if (p.tur === "kivilcim") {
        ctx.fillStyle = p.renk;
        ctx.shadowColor = p.renk;
        ctx.shadowBlur = p.boyut * 2;
        ctx.fillRect(
          Math.floor(ekranX),
          Math.floor(p.y),
          Math.ceil(p.boyut),
          Math.ceil(p.boyut)
        );
      } else if (p.tur === "daire") {
        ctx.beginPath();
        ctx.arc(ekranX, p.y, p.boyut, 0, Math.PI * 2);
        ctx.fillStyle = p.renk;
        ctx.shadowColor = p.renk;
        ctx.shadowBlur = 4;
        ctx.fill();
      } else {
        ctx.fillStyle = p.renk;
        ctx.fillRect(
          Math.floor(ekranX),
          Math.floor(p.y),
          Math.ceil(p.boyut),
          Math.ceil(p.boyut)
        );
      }

      ctx.restore();
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  RADAR DARBELERİ
  // ════════════════════════════════════════════════════════════════════════

  // Radar darbesi ekle (dünya koordinatlarında)
  function radarDarbesiEkle(x, y, renk) {
    radarDarbeleri.push({
      x: x,
      y: y,
      yaricap: 0,
      maxYaricap: 80 + Math.random() * 40,
      renk: renk || "#00E5FF",
      opaklik: 0.6,
      hiz: 1.5 + Math.random()
    });
  }

  // Radar darbelerini güncelle
  function radarDarbeleriniGuncelle() {
    for (var i = radarDarbeleri.length - 1; i >= 0; i--) {
      var r = radarDarbeleri[i];
      r.yaricap += r.hiz;
      r.opaklik = 0.6 * (1 - r.yaricap / r.maxYaricap);

      if (r.yaricap >= r.maxYaricap) {
        radarDarbeleri.splice(i, 1);
      }
    }
  }

  // Radar darbelerini çiz (dünya→ekran dönüşümü ile)
  function radarDarbeleriniCiz(ctx) {
    var state = BY.state;

    for (var i = 0; i < radarDarbeleri.length; i++) {
      var r = radarDarbeleri[i];
      var ekranX = r.x - state.kameraX;

      // Ekran dışındaysa atla (yarıçap kadar tolerans)
      if (ekranDisindaMi(ekranX, r.maxYaricap + 20)) continue;

      ctx.save();
      ctx.globalAlpha = r.opaklik;
      ctx.strokeStyle = r.renk;
      ctx.lineWidth = 1.5;
      ctx.shadowColor = r.renk;
      ctx.shadowBlur = 4;

      ctx.beginPath();
      ctx.arc(ekranX, r.y, r.yaricap, 0, Math.PI * 2);
      ctx.stroke();
      ctx.restore();
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  TARAMA ÇİZGİSİ VE CRT PARLAMA
  // ════════════════════════════════════════════════════════════════════════

  // Tarama çizgisini güncelle
  function taramaCizgisiGuncelle() {
    var state = BY.state;
    if (!taramaAktif) return;

    taramaCizgiY += 0.5;
    if (taramaCizgiY > state.canvasYukseklik) {
      taramaCizgiY = 0;
    }
  }

  // Tarama çizgisini çiz
  function taramaCizgisiCiz(ctx) {
    var state = BY.state;
    if (!taramaAktif) return;

    ctx.save();
    var gradyan = ctx.createLinearGradient(0, taramaCizgiY - 20, 0, taramaCizgiY + 5);
    gradyan.addColorStop(0, "rgba(255,255,255,0)");
    gradyan.addColorStop(0.5, "rgba(255,255,255,0.03)");
    gradyan.addColorStop(1, "rgba(255,255,255,0)");
    ctx.fillStyle = gradyan;
    ctx.fillRect(0, taramaCizgiY - 20, state.canvasGenislik, 25);
    ctx.restore();
  }

  // CRT parlama efekti (vinyet)
  function crtParlamaCiz(ctx) {
    var state = BY.state;

    ctx.save();
    var vinyetGradyan = ctx.createRadialGradient(
      state.canvasGenislik / 2, state.canvasYukseklik / 2,
      state.canvasGenislik * 0.3,
      state.canvasGenislik / 2, state.canvasYukseklik / 2,
      state.canvasGenislik * 0.8
    );
    vinyetGradyan.addColorStop(0, "rgba(0,0,0,0)");
    vinyetGradyan.addColorStop(1, "rgba(0,0,0," + crtParlamaYogunluk + ")");
    ctx.fillStyle = vinyetGradyan;
    ctx.fillRect(0, 0, state.canvasGenislik, state.canvasYukseklik);
    ctx.restore();
  }

  // ════════════════════════════════════════════════════════════════════════
  //  HASAR SAYILARI (yüzen hasar metni)
  // ════════════════════════════════════════════════════════════════════════

  // Hasar efekti oluştur: kırmızı/turuncu parçacık patlaması + yüzen hasar sayısı
  function hasarEfektiOlustur(x, y, renk) {
    renk = renk || "#FF4444";

    // Kırmızı ve turuncu parçacık patlaması
    parcacikOlustur(x, y, "#FF4444", "kivilcim", 4);
    parcacikOlustur(x, y, "#FF8800", "kivilcim", 3);

    // Yüzen hasar sayısı
    hasarSayilari.push({
      x: x,
      y: y,
      metin: "!",
      renk: renk,
      yasam: 60,
      maxYasam: 60,
      hizY: -1.5
    });
  }

  // Hasar sayılarını güncelle
  function hasarSayilariniGuncelle() {
    for (var i = hasarSayilari.length - 1; i >= 0; i--) {
      var h = hasarSayilari[i];
      h.y += h.hizY;
      h.yasam--;

      if (h.yasam <= 0) {
        hasarSayilari.splice(i, 1);
      }
    }
  }

  // Hasar sayılarını çiz (pikselleştirilmiş küçük metin)
  function hasarSayilariniCiz(ctx) {
    var state = BY.state;

    for (var i = 0; i < hasarSayilari.length; i++) {
      var h = hasarSayilari[i];
      var ekranX = h.x - state.kameraX;

      // Ekran dışındaysa atla
      if (ekranDisindaMi(ekranX, 30)) continue;

      var opaklik = h.yasam / h.maxYasam;

      ctx.save();
      ctx.globalAlpha = opaklik;

      // Gölge katmanı
      ctx.font = "bold 12px monospace";
      ctx.textAlign = "center";
      ctx.fillStyle = "rgba(0,0,0,0.7)";
      ctx.fillText(h.metin, ekranX + 1, h.y + 1);

      // Ana metin
      ctx.fillStyle = h.renk;
      ctx.shadowColor = h.renk;
      ctx.shadowBlur = 4;
      ctx.fillText(h.metin, ekranX, h.y);

      ctx.restore();
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  LAZER IŞINLARI
  // ════════════════════════════════════════════════════════════════════════

  // Lazer efekti oluştur: iki nokta arasında parlayan çizgi
  function lazerEfektiOlustur(x1, y1, x2, y2, renk) {
    renk = renk || "#00E5FF";

    lazerler.push({
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
      renk: renk,
      yasam: 15,
      maxYasam: 15,
      genislik: 2
    });
  }

  // Lazerleri güncelle
  function lazerleriGuncelle() {
    for (var i = lazerler.length - 1; i >= 0; i--) {
      var l = lazerler[i];
      l.yasam--;

      if (l.yasam <= 0) {
        lazerler.splice(i, 1);
      }
    }
  }

  // Lazerleri çiz (parlayan çizgi efekti)
  function lazerleriCiz(ctx) {
    var state = BY.state;

    for (var i = 0; i < lazerler.length; i++) {
      var l = lazerler[i];
      var ekranX1 = l.x1 - state.kameraX;
      var ekranX2 = l.x2 - state.kameraX;

      // Her iki uç da ekran dışındaysa atla
      var solUc = Math.min(ekranX1, ekranX2);
      var sagUc = Math.max(ekranX1, ekranX2);
      if (sagUc < -50 || solUc > state.canvasGenislik + 50) continue;

      var opaklik = l.yasam / l.maxYasam;

      ctx.save();
      ctx.globalAlpha = opaklik;

      // Dış parlama katmanı (geniş, soluk)
      ctx.strokeStyle = l.renk;
      ctx.shadowColor = l.renk;
      ctx.shadowBlur = 8;
      ctx.lineWidth = l.genislik + 3;
      ctx.globalAlpha = opaklik * 0.3;
      ctx.beginPath();
      ctx.moveTo(ekranX1, l.y1);
      ctx.lineTo(ekranX2, l.y2);
      ctx.stroke();

      // İç parlak çizgi
      ctx.globalAlpha = opaklik;
      ctx.shadowBlur = 4;
      ctx.lineWidth = l.genislik;
      ctx.beginPath();
      ctx.moveTo(ekranX1, l.y1);
      ctx.lineTo(ekranX2, l.y2);
      ctx.stroke();

      // Merkez beyaz çekirdek
      ctx.globalAlpha = opaklik * 0.8;
      ctx.strokeStyle = "#FFFFFF";
      ctx.shadowBlur = 0;
      ctx.lineWidth = Math.max(1, l.genislik * 0.4);
      ctx.beginPath();
      ctx.moveTo(ekranX1, l.y1);
      ctx.lineTo(ekranX2, l.y2);
      ctx.stroke();

      ctx.restore();
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  PATLAMA EFEKTİ
  // ════════════════════════════════════════════════════════════════════════

  // Büyük patlama efekti: genişleyen halka + çok sayıda rastgele renkli parçacık
  function patlamaEfektiOlustur(x, y) {
    // Genişleyen radar halkası
    radarDarbeleri.push({
      x: x,
      y: y,
      yaricap: 0,
      maxYaricap: 120 + Math.random() * 60,
      renk: "#FFD700",
      opaklik: 0.8,
      hiz: 3
    });

    // İkinci bir halka daha (gecikmeli etki)
    radarDarbeleri.push({
      x: x,
      y: y,
      yaricap: 0,
      maxYaricap: 80 + Math.random() * 40,
      renk: "#FF6600",
      opaklik: 0.6,
      hiz: 2
    });

    // Çok sayıda rastgele renkli parçacık
    var patlamaRenkleri = ["#FFD700", "#FF6B6B", "#FF8800", "#FFFFFF", "#FF4444", "#FFAA00"];
    for (var i = 0; i < patlamaRenkleri.length; i++) {
      parcacikOlustur(
        x + (Math.random() - 0.5) * 20,
        y + (Math.random() - 0.5) * 20,
        patlamaRenkleri[i],
        "kivilcim",
        5
      );
    }

    // Büyük daire parçacıkları
    parcacikOlustur(x, y, "#FFD700", "daire", 8);
  }

  // ════════════════════════════════════════════════════════════════════════
  //  KALKAN EFEKTİ
  // ════════════════════════════════════════════════════════════════════════

  // Kalkan efekti oluştur: nabız atan yarı saydam daire
  function kalkanEfektiOlustur(x, y, yaricap, renk) {
    yaricap = yaricap || 40;
    renk = renk || "#4ECDC4";

    kalkanlar.push({
      x: x,
      y: y,
      yaricap: yaricap,
      renk: renk,
      yasam: 90,
      maxYasam: 90,
      faz: 0
    });
  }

  // Kalkanları güncelle
  function kalkanlariGuncelle() {
    for (var i = kalkanlar.length - 1; i >= 0; i--) {
      var k = kalkanlar[i];
      k.yasam--;
      k.faz += 0.08;

      if (k.yasam <= 0) {
        kalkanlar.splice(i, 1);
      }
    }
  }

  // Kalkanları çiz (nabız atan yarı saydam daire)
  function kalkanlariCiz(ctx) {
    var state = BY.state;

    for (var i = 0; i < kalkanlar.length; i++) {
      var k = kalkanlar[i];
      var ekranX = k.x - state.kameraX;

      // Ekran dışındaysa atla
      if (ekranDisindaMi(ekranX, k.yaricap + 20)) continue;

      var opaklik = (k.yasam / k.maxYasam) * 0.4;
      // Nabız efekti: yarıçap hafifçe oynasın
      var nabiz = 1 + Math.sin(k.faz) * 0.1;
      var cizimYaricap = k.yaricap * nabiz;

      ctx.save();

      // Yarı saydam dolgu
      ctx.globalAlpha = opaklik * 0.3;
      ctx.fillStyle = k.renk;
      ctx.beginPath();
      ctx.arc(ekranX, k.y, cizimYaricap, 0, Math.PI * 2);
      ctx.fill();

      // Parlayan kenar çizgisi
      ctx.globalAlpha = opaklik;
      ctx.strokeStyle = k.renk;
      ctx.shadowColor = k.renk;
      ctx.shadowBlur = 6;
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.arc(ekranX, k.y, cizimYaricap, 0, Math.PI * 2);
      ctx.stroke();

      ctx.restore();
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  YETENEK EFEKTLERİ
  // ════════════════════════════════════════════════════════════════════════

  // Karakter yetenek efekti oluştur
  function yetenekEfektiOlustur(karakter) {
    var merkezX = karakter.x + karakter.genislik / 2;
    var merkezY = karakter.y + karakter.yukseklik / 2;
    var renk = karakter.renkler.ana;

    switch (karakter.yetenekTuru) {
      case "ok_atisi":
        // Ok izleri
        for (var i = 0; i < 8; i++) {
          parcacikOlustur(merkezX + 20, merkezY - 10, renk, "kivilcim", 1);
        }
        radarDarbesiEkle(merkezX, merkezY, renk);
        break;

      case "gok_dalgasi":
        // Enerji dalgası
        radarDarbesiEkle(merkezX, merkezY, renk);
        radarDarbesiEkle(merkezX, merkezY - 10, karakter.renkler.acik);
        parcacikOlustur(merkezX, merkezY - 20, renk, "yukari", 12);
        break;

      case "kure_olustur":
        // Küre parçacıkları
        parcacikOlustur(merkezX, merkezY, renk, "daire", 15);
        radarDarbesiEkle(merkezX, merkezY, karakter.renkler.acik);
        break;

      case "kaos_saldiri":
        // Kaotik parçacıklar
        parcacikOlustur(merkezX, merkezY, renk, "kivilcim", 20);
        parcacikOlustur(merkezX, merkezY, "#FF0000", "kivilcim", 5);
        break;

      case "kalkan_kur":
        // Koruyucu kalkan
        radarDarbesiEkle(merkezX, merkezY, renk);
        radarDarbesiEkle(merkezX, merkezY, karakter.renkler.acik);
        parcacikOlustur(merkezX, merkezY, renk, "daire", 10);
        kalkanEfektiOlustur(merkezX, merkezY, 35, karakter.renkler.acik);
        break;
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  ZAFER EFEKTİ
  // ════════════════════════════════════════════════════════════════════════

  function zaferEfektiOlustur() {
    var state = BY.state;

    // Takım merkezini hesapla
    var merkezX = state.canvasGenislik / 2 + state.kameraX;
    var merkezY = state.zeminY * 0.5;

    if (state.karakterler.length > 0) {
      var topX = 0;
      for (var c = 0; c < state.karakterler.length; c++) {
        topX += state.karakterler[c].x;
      }
      merkezX = topX / state.karakterler.length;
    }

    // Büyük renkli patlama
    var renkler = ["#FFD700", "#FF6B6B", "#4ECDC4", "#A47DFF", "#FF9FF3"];
    for (var i = 0; i < renkler.length; i++) {
      parcacikOlustur(merkezX + (Math.random() - 0.5) * 100, merkezY, renkler[i], "kivilcim", 10);
    }

    // Merkezi radar darbesi
    radarDarbesiEkle(merkezX, merkezY, "#FFD700");

    // Her karakter için efekt
    var karakterler = state.karakterler;
    for (var k = 0; k < karakterler.length; k++) {
      var kar = karakterler[k];
      parcacikOlustur(
        kar.x + kar.genislik / 2,
        kar.y + kar.yukseklik / 2,
        kar.renkler.ana,
        "daire", 8
      );
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  PERİYODİK ORTAM EFEKTLERİ
  // ════════════════════════════════════════════════════════════════════════

  function ortamEfektleriOlustur(zaman) {
    if (zaman - sonOrtamEfekt < 3000) return;
    sonOrtamEfekt = zaman;

    var state = BY.state;
    var seviye = BY.dunya ? BY.dunya.mevcutSeviyeAl() : null;
    if (!seviye) return;

    // Rastgele ortam parçacıkları (görünür alanda)
    var x = state.kameraX + Math.random() * state.canvasGenislik;
    var y = state.zeminY * (0.3 + Math.random() * 0.4);
    parcacikOlustur(x, y, seviye.aksan, "yukari", 3);

    // Ara sıra radar darbesi
    if (Math.random() > 0.5) {
      radarDarbesiEkle(
        state.kameraX + Math.random() * state.canvasGenislik,
        state.zeminY * (0.2 + Math.random() * 0.5),
        seviye.aksan
      );
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  DIŞ ARAYÜZ
  // ════════════════════════════════════════════════════════════════════════

  BY.efektler = {
    baslat: function() {
      parcaciklar = [];
      radarDarbeleri = [];
      hasarSayilari = [];
      lazerler = [];
      kalkanlar = [];
      taramaCizgiY = 0;
      sonOrtamEfekt = 0;
    },

    guncelle: function(zaman) {
      parcaciklariGuncelle();
      radarDarbeleriniGuncelle();
      hasarSayilariniGuncelle();
      lazerleriGuncelle();
      kalkanlariGuncelle();
      taramaCizgisiGuncelle();
      ortamEfektleriOlustur(zaman);
    },

    // Arka plan efektleri (düşmanlar ve karakterlerden önce çizilir)
    cizArkaPlan: function(ctx) {
      radarDarbeleriniCiz(ctx);
      kalkanlariCiz(ctx);
    },

    // Ön plan efektleri (her şeyin üstüne çizilir)
    cizOnPlan: function(ctx) {
      parcaciklariCiz(ctx);
      lazerleriCiz(ctx);
      hasarSayilariniCiz(ctx);
      taramaCizgisiCiz(ctx);
      crtParlamaCiz(ctx);
    },

    // Mevcut efekt oluşturma fonksiyonları
    parcacikOlustur: parcacikOlustur,
    radarDarbesiEkle: radarDarbesiEkle,
    yetenekEfektiOlustur: yetenekEfektiOlustur,
    zaferEfektiOlustur: zaferEfektiOlustur,

    // Yeni efekt oluşturma fonksiyonları
    hasarEfektiOlustur: hasarEfektiOlustur,
    patlamaEfektiOlustur: patlamaEfektiOlustur,
    lazerEfektiOlustur: lazerEfektiOlustur,
    kalkanEfektiOlustur: kalkanEfektiOlustur
  };

})();