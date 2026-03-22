// www/js/bilge_yolac_efektler.js
// Parçacık ve efekt sistemi: radar darbeleri, tarama çizgileri, CRT parlama, yetenek efektleri

(function() {
  "use strict";

  var BY = window.BilgeYolac;
  if (!BY) return;

  // Parçacık havuzu
  var parcaciklar = [];

  // Radar darbe efektleri
  var radarDarbeleri = [];

  // Tarama çizgisi
  var taramaCizgiY = 0;
  var taramaAktif = true;

  // CRT parlama parametreleri
  var crtParlamaYogunluk = 0.03;

  // Parçacık oluştur
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

  // Radar darbesi ekle
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

  // Tarama çizgisini güncelle
  function taramaCizgisiGuncelle() {
    var state = BY.state;
    if (!taramaAktif) return;

    taramaCizgiY += 0.5;
    if (taramaCizgiY > state.canvasYukseklik) {
      taramaCizgiY = 0;
    }
  }

  // Parçacıkları çiz
  function parcaciklariCiz(ctx) {
    for (var i = 0; i < parcaciklar.length; i++) {
      var p = parcaciklar[i];

      ctx.save();
      ctx.globalAlpha = p.opaklik;

      if (p.tur === "kivilcim") {
        ctx.fillStyle = p.renk;
        ctx.shadowColor = p.renk;
        ctx.shadowBlur = p.boyut * 2;
        ctx.fillRect(
          Math.floor(p.x),
          Math.floor(p.y),
          Math.ceil(p.boyut),
          Math.ceil(p.boyut)
        );
      } else if (p.tur === "daire") {
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.boyut, 0, Math.PI * 2);
        ctx.fillStyle = p.renk;
        ctx.shadowColor = p.renk;
        ctx.shadowBlur = 4;
        ctx.fill();
      } else {
        ctx.fillStyle = p.renk;
        ctx.fillRect(
          Math.floor(p.x),
          Math.floor(p.y),
          Math.ceil(p.boyut),
          Math.ceil(p.boyut)
        );
      }

      ctx.restore();
    }
  }

  // Radar darbelerini ciz
  function radarDarbeleriniCiz(ctx) {
    for (var i = 0; i < radarDarbeleri.length; i++) {
      var r = radarDarbeleri[i];

      ctx.save();
      ctx.globalAlpha = r.opaklik;
      ctx.strokeStyle = r.renk;
      ctx.lineWidth = 1.5;
      ctx.shadowColor = r.renk;
      ctx.shadowBlur = 4;

      ctx.beginPath();
      ctx.arc(r.x, r.y, r.yaricap, 0, Math.PI * 2);
      ctx.stroke();
      ctx.restore();
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

  // CRT parlama efekti
  function crtParlamaCiz(ctx) {
    var state = BY.state;

    ctx.save();
    // Hafif vinyet efekti
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

  // Yetenek efekti oluştur
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
        // Enerji dalgasi
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
        break;
    }
  }

  // Zafer efekti
  function zaferEfektiOlustur() {
    var state = BY.state;
    var merkezX = state.canvasGenislik / 2;
    var merkezY = state.zeminY * 0.5;

    // Buyuk patlama
    var renkler = ["#FFD700", "#FF6B6B", "#4ECDC4", "#A47DFF", "#FF9FF3"];
    for (var i = 0; i < renkler.length; i++) {
      parcacikOlustur(merkezX + (Math.random() - 0.5) * 100, merkezY, renkler[i], "kivilcim", 10);
    }

    // Merkezi radar darbesi
    radarDarbesiEkle(merkezX, merkezY, "#FFD700");

    // Her karakter icin efekt
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

  // Periyodik ortam efektleri
  var sonOrtamEfekt = 0;
  function ortamEfektleriOlustur(zaman) {
    if (zaman - sonOrtamEfekt < 3000) return;
    sonOrtamEfekt = zaman;

    var state = BY.state;
    var seviye = BY.dunya ? BY.dunya.mevcutSeviyeAl() : null;
    if (!seviye) return;

    // Rastgele ortam parçacıkları
    var x = Math.random() * state.canvasGenislik;
    var y = state.zeminY * (0.3 + Math.random() * 0.4);
    parcacikOlustur(x, y, seviye.aksan, "yukari", 3);

    // Ara sira radar darbesi
    if (Math.random() > 0.5) {
      radarDarbesiEkle(
        Math.random() * state.canvasGenislik,
        state.zeminY * (0.2 + Math.random() * 0.5),
        seviye.aksan
      );
    }
  }

  // Dış arayüz
  BY.efektler = {
    baslat: function() {
      parcaciklar = [];
      radarDarbeleri = [];
      taramaCizgiY = 0;
      sonOrtamEfekt = 0;
    },

    guncelle: function(zaman) {
      parcaciklariGuncelle();
      radarDarbeleriniGuncelle();
      taramaCizgisiGuncelle();
      ortamEfektleriOlustur(zaman);
    },

    cizArkaPlan: function(ctx) {
      radarDarbeleriniCiz(ctx);
    },

    cizOnPlan: function(ctx) {
      parcaciklariCiz(ctx);
      taramaCizgisiCiz(ctx);
      crtParlamaCiz(ctx);
    },

    parcacikOlustur: parcacikOlustur,
    radarDarbesiEkle: radarDarbesiEkle,
    yetenekEfektiOlustur: yetenekEfektiOlustur,
    zaferEfektiOlustur: zaferEfektiOlustur
  };

})();
