// www/js/bilge_yolac_efektler.js
// Gelişmiş efekt sistemi: parçacıklar, radar darbeleri, lazerler, kalkanlar,
// CRT katmanı ve karaktere özgü yetenek efektleri.

(function() {
  "use strict";

  var BY = window.BilgeYolac;
  if (!BY) return;

  var parcaciklar = [];
  var radarDarbeleri = [];
  var hasarSayilari = [];
  var lazerler = [];
  var kalkanlar = [];
  var taramaCizgiY = 0;
  var sonOrtamEfekt = 0;
  var crtParlamaYogunluk = 0.03;

  function ekranDisindaMi(dX, tolerans) {
    var state = BY.state;
    tolerans = tolerans || 50;
    return dX < -tolerans || dX > state.canvasGenislik + tolerans;
  }

  function parcacikOlustur(x, y, renk, tur, miktar) {
    miktar = miktar || 5;
    for (var i = 0; i < miktar; i++) {
      if (parcaciklar.length >= BY.config.PARCACIK_SINIRI) break;
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
        yasam: 55 + Math.random() * 30,
        maxYasam: 85,
        opaklik: 1,
        yercekim: tur === "yukari" ? -0.02 : 0.03
      });
    }
  }

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

  function hasarEfektiOlustur(x, y, renk) {
    renk = renk || "#FF4444";
    parcacikOlustur(x, y, "#FF4444", "kivilcim", 4);
    parcacikOlustur(x, y, "#FF8800", "kivilcim", 3);
    hasarSayilari.push({
      x: x,
      y: y,
      metin: "!",
      renk: renk,
      yasam: 55,
      maxYasam: 55,
      hizY: -1.4
    });
  }

  function lazerEfektiOlustur(x1, y1, x2, y2, renk) {
    lazerler.push({
      x1: x1, y1: y1, x2: x2, y2: y2,
      renk: renk || "#00E5FF",
      yasam: 12,
      maxYasam: 12,
      genislik: 2
    });
  }

  function patlamaEfektiOlustur(x, y) {
    radarDarbeleri.push({ x: x, y: y, yaricap: 0, maxYaricap: 120, renk: "#FFD700", opaklik: 0.8, hiz: 3 });
    radarDarbeleri.push({ x: x, y: y, yaricap: 0, maxYaricap: 90, renk: "#FF6600", opaklik: 0.6, hiz: 2.2 });
    var renkler = ["#FFD700", "#FF6B6B", "#FF8800", "#FFFFFF", "#FFAA00"];
    for (var i = 0; i < renkler.length; i++) {
      parcacikOlustur(x + (Math.random() - 0.5) * 16, y + (Math.random() - 0.5) * 16, renkler[i], "kivilcim", 4);
    }
    parcacikOlustur(x, y, "#FFD700", "daire", 6);
  }

  function kalkanEfektiOlustur(x, y, yaricap, renk) {
    kalkanlar.push({
      x: x,
      y: y,
      yaricap: yaricap || 40,
      renk: renk || "#4ECDC4",
      yasam: 80,
      maxYasam: 80,
      faz: 0
    });
  }

  function enYakinDusmanAl(x, y) {
    var dusmanlar = BY.state.dusmanlar || [];
    var enYakin = null;
    var minMesafe = Infinity;

    for (var i = 0; i < dusmanlar.length; i++) {
      var d = dusmanlar[i];
      if (!d || !d.aktif || d.can <= 0) continue;
      var dx = (d.x + d.genislik / 2) - x;
      var dy = (d.y + d.yukseklik / 2) - y;
      var mesafe = Math.sqrt(dx * dx + dy * dy);
      if (mesafe < minMesafe) {
        minMesafe = mesafe;
        enYakin = d;
      }
    }
    return enYakin;
  }

  function karakterVurusuOlustur(karakter, adet, yayilma, hasarArtisi) {
    if (!BY.cephanelik) return;
    adet = adet || 1;
    yayilma = yayilma || 0;

    var merkezX = karakter.x + karakter.genislik / 2;
    var merkezY = karakter.y + karakter.yukseklik * 0.45;
    var hedef = enYakinDusmanAl(merkezX, merkezY);
    var hedefX = hedef ? hedef.x + hedef.genislik / 2 : merkezX + karakter.yon * 280;
    var hedefY = hedef ? hedef.y + hedef.yukseklik / 2 : merkezY - 20;

    if (adet === 1) {
      BY.cephanelik.oyuncuAtisiOlustur(karakter, hedefX, hedefY, { hasar: hasarArtisi ? hasarArtisi : undefined });
      return;
    }

    for (var i = 0; i < adet; i++) {
      var oran = adet > 1 ? (i / (adet - 1)) : 0.5;
      var aciOfset = -yayilma / 2 + yayilma * oran;
      BY.cephanelik.oyuncuAtisiOlustur(karakter, hedefX, hedefY, {
        yayilma: aciOfset,
        hasar: hasarArtisi ? hasarArtisi : undefined
      });
    }
  }

  function yetenekEfektiOlustur(karakter) {
    var merkezX = karakter.x + karakter.genislik / 2;
    var merkezY = karakter.y + karakter.yukseklik / 2;
    var renk = karakter.renkler.ana;

    // Persona yetenek efektleri - modern çalışma tarzı temaları
    switch (karakter.yetenekTuru) {
      case "cozum_dalgasi":
        // Emre - çözüm dalgası
        parcacikOlustur(merkezX, merkezY, karakter.renkler.acik, "kivilcim", 8);
        radarDarbesiEkle(merkezX, merkezY, karakter.renkler.acik);
        karakterVurusuOlustur(karakter, 3, 0.14, 14);
        break;

      case "sinyal_taramasi":
        // Selin - sinyal taraması
        radarDarbesiEkle(merkezX, merkezY, renk);
        radarDarbesiEkle(merkezX, merkezY - 8, karakter.renkler.acik);
        parcacikOlustur(merkezX, merkezY - 18, karakter.renkler.acik, "yukari", 12);
        karakterVurusuOlustur(karakter, 5, 0.22, 11);
        break;

      case "rota_projesi":
        // Deniz - rota projeksiyonu
        parcacikOlustur(merkezX, merkezY, karakter.renkler.acik, "daire", 14);
        radarDarbesiEkle(merkezX, merkezY, renk);
        karakterVurusuOlustur(karakter, 4, 0.18, 10);
        break;

      case "dogrulama_isini":
        // Can - doğrulama ışını
        parcacikOlustur(merkezX, merkezY, renk, "kivilcim", 18);
        parcacikOlustur(merkezX, merkezY, "#FFFFFF", "kivilcim", 4);
        karakterVurusuOlustur(karakter, 3, 0.20, 18);
        break;

      case "rehber_halkasi":
        // İpek - rehber halkası (takıma destek/onarım)
        radarDarbesiEkle(merkezX, merkezY, renk);
        radarDarbesiEkle(merkezX, merkezY, karakter.renkler.acik);
        parcacikOlustur(merkezX, merkezY, karakter.renkler.acik, "daire", 10);
        kalkanEfektiOlustur(merkezX, merkezY, 35, karakter.renkler.acik);
        karakterVurusuOlustur(karakter, 2, 0.10, 6);
        BY.state.takimCan = Math.min(BY.state.takimMaxCan, BY.state.takimCan + 4);
        break;
    }
  }

  function zaferEfektiOlustur() {
    var state = BY.state;
    var merkez = BY.karakterler && BY.karakterler.takimMerkeziAl ? BY.karakterler.takimMerkeziAl() : null;
    var x = merkez ? merkez.x : state.canvasGenislik / 2 + state.kameraX;
    var y = merkez ? merkez.y : state.zeminY * 0.5;

    var renkler = ["#FFD700", "#FF6B6B", "#4ECDC4", "#A47DFF", "#FF9FF3"];
    for (var i = 0; i < renkler.length; i++) {
      parcacikOlustur(x + (Math.random() - 0.5) * 100, y, renkler[i], "kivilcim", 8);
    }
    radarDarbesiEkle(x, y, "#FFD700");
  }

  function guncelleParcaciklar() {
    for (var i = parcaciklar.length - 1; i >= 0; i--) {
      var p = parcaciklar[i];
      p.x += p.hizX;
      p.y += p.hizY;
      p.hizY += p.yercekim;
      p.hizX *= 0.98;
      p.yasam--;
      p.opaklik = p.yasam / p.maxYasam;
      p.boyut *= 0.99;
      if (p.yasam <= 0 || p.boyut < 0.3) parcaciklar.splice(i, 1);
    }
  }

  function guncelleRadarDarbeleri() {
    for (var i = radarDarbeleri.length - 1; i >= 0; i--) {
      var r = radarDarbeleri[i];
      r.yaricap += r.hiz;
      r.opaklik = 0.6 * (1 - r.yaricap / r.maxYaricap);
      if (r.yaricap >= r.maxYaricap) radarDarbeleri.splice(i, 1);
    }
  }

  function guncelleHasarSayilari() {
    for (var i = hasarSayilari.length - 1; i >= 0; i--) {
      var h = hasarSayilari[i];
      h.y += h.hizY;
      h.yasam--;
      if (h.yasam <= 0) hasarSayilari.splice(i, 1);
    }
  }

  function guncelleLazerler() {
    for (var i = lazerler.length - 1; i >= 0; i--) {
      lazerler[i].yasam--;
      if (lazerler[i].yasam <= 0) lazerler.splice(i, 1);
    }
  }

  function guncelleKalkanlar() {
    for (var i = kalkanlar.length - 1; i >= 0; i--) {
      kalkanlar[i].yasam--;
      kalkanlar[i].faz += 0.08;
      if (kalkanlar[i].yasam <= 0) kalkanlar.splice(i, 1);
    }
  }

  function ortamEfektleriOlustur(zaman) {
    if (zaman - sonOrtamEfekt < 3000) return;
    sonOrtamEfekt = zaman;

    var state = BY.state;
    var seviye = BY.dunya && BY.dunya.mevcutSeviyeAl ? BY.dunya.mevcutSeviyeAl() : null;
    if (!seviye) return;

    var x = state.kameraX + Math.random() * state.canvasGenislik;
    var y = state.zeminY * (0.26 + Math.random() * 0.42);
    parcacikOlustur(x, y, seviye.aksan, "yukari", 3);
    if (Math.random() > 0.55) radarDarbesiEkle(x, y, seviye.aksan);
  }

  function cizParcaciklar(ctx) {
    var state = BY.state;
    for (var i = 0; i < parcaciklar.length; i++) {
      var p = parcaciklar[i];
      var ekranX = p.x - state.kameraX;
      if (ekranDisindaMi(ekranX, 30)) continue;

      ctx.save();
      ctx.globalAlpha = p.opaklik;
      if (p.tur === "kivilcim") {
        ctx.fillStyle = p.renk;
        ctx.shadowColor = p.renk;
        ctx.shadowBlur = p.boyut * 2;
        ctx.fillRect(Math.floor(ekranX), Math.floor(p.y), Math.ceil(p.boyut), Math.ceil(p.boyut));
      } else {
        ctx.beginPath();
        ctx.arc(ekranX, p.y, p.boyut, 0, Math.PI * 2);
        ctx.fillStyle = p.renk;
        ctx.shadowColor = p.renk;
        ctx.shadowBlur = 4;
        ctx.fill();
      }
      ctx.restore();
    }
  }

  function cizRadarDarbeleri(ctx) {
    var state = BY.state;
    for (var i = 0; i < radarDarbeleri.length; i++) {
      var r = radarDarbeleri[i];
      var ekranX = r.x - state.kameraX;
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

  function cizHasarSayilari(ctx) {
    var state = BY.state;
    for (var i = 0; i < hasarSayilari.length; i++) {
      var h = hasarSayilari[i];
      var ekranX = h.x - state.kameraX;
      if (ekranDisindaMi(ekranX, 30)) continue;
      var opaklik = h.yasam / h.maxYasam;
      ctx.save();
      ctx.globalAlpha = opaklik;
      ctx.font = "bold 12px monospace";
      ctx.textAlign = "center";
      ctx.fillStyle = "rgba(0,0,0,0.7)";
      ctx.fillText(h.metin, ekranX + 1, h.y + 1);
      ctx.fillStyle = h.renk;
      ctx.shadowColor = h.renk;
      ctx.shadowBlur = 4;
      ctx.fillText(h.metin, ekranX, h.y);
      ctx.restore();
    }
  }

  function cizLazerler(ctx) {
    var state = BY.state;
    for (var i = 0; i < lazerler.length; i++) {
      var l = lazerler[i];
      var ekranX1 = l.x1 - state.kameraX;
      var ekranX2 = l.x2 - state.kameraX;
      var sol = Math.min(ekranX1, ekranX2);
      var sag = Math.max(ekranX1, ekranX2);
      if (sag < -50 || sol > state.canvasGenislik + 50) continue;
      var op = l.yasam / l.maxYasam;

      ctx.save();
      ctx.globalAlpha = op * 0.35;
      ctx.strokeStyle = l.renk;
      ctx.shadowColor = l.renk;
      ctx.shadowBlur = 8;
      ctx.lineWidth = l.genislik + 3;
      ctx.beginPath();
      ctx.moveTo(ekranX1, l.y1);
      ctx.lineTo(ekranX2, l.y2);
      ctx.stroke();

      ctx.globalAlpha = op;
      ctx.lineWidth = l.genislik;
      ctx.beginPath();
      ctx.moveTo(ekranX1, l.y1);
      ctx.lineTo(ekranX2, l.y2);
      ctx.stroke();

      ctx.globalAlpha = op * 0.8;
      ctx.strokeStyle = "#FFFFFF";
      ctx.shadowBlur = 0;
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(ekranX1, l.y1);
      ctx.lineTo(ekranX2, l.y2);
      ctx.stroke();
      ctx.restore();
    }
  }

  function cizKalkanlar(ctx) {
    var state = BY.state;
    for (var i = 0; i < kalkanlar.length; i++) {
      var k = kalkanlar[i];
      var ekranX = k.x - state.kameraX;
      if (ekranDisindaMi(ekranX, k.yaricap + 20)) continue;
      var opaklik = (k.yasam / k.maxYasam) * 0.4;
      var nabiz = 1 + Math.sin(k.faz) * 0.1;
      var yaricap = k.yaricap * nabiz;

      ctx.save();
      ctx.globalAlpha = opaklik * 0.3;
      ctx.fillStyle = k.renk;
      ctx.beginPath();
      ctx.arc(ekranX, k.y, yaricap, 0, Math.PI * 2);
      ctx.fill();

      ctx.globalAlpha = opaklik;
      ctx.strokeStyle = k.renk;
      ctx.shadowColor = k.renk;
      ctx.shadowBlur = 6;
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.arc(ekranX, k.y, yaricap, 0, Math.PI * 2);
      ctx.stroke();
      ctx.restore();
    }
  }

  function taramaCizgisiCiz(ctx) {
    var state = BY.state;
    ctx.save();
    var grad = ctx.createLinearGradient(0, taramaCizgiY - 20, 0, taramaCizgiY + 5);
    grad.addColorStop(0, "rgba(255,255,255,0)");
    grad.addColorStop(0.5, "rgba(255,255,255,0.03)");
    grad.addColorStop(1, "rgba(255,255,255,0)");
    ctx.fillStyle = grad;
    ctx.fillRect(0, taramaCizgiY - 20, state.canvasGenislik, 25);
    ctx.restore();
  }

  function crtParlamaCiz(ctx) {
    var state = BY.state;
    ctx.save();
    var grad = ctx.createRadialGradient(
      state.canvasGenislik / 2, state.canvasYukseklik / 2, state.canvasGenislik * 0.3,
      state.canvasGenislik / 2, state.canvasYukseklik / 2, state.canvasGenislik * 0.8
    );
    grad.addColorStop(0, "rgba(0,0,0,0)");
    grad.addColorStop(1, "rgba(0,0,0," + crtParlamaYogunluk + ")");
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, state.canvasGenislik, state.canvasYukseklik);
    ctx.restore();
  }

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
      guncelleParcaciklar();
      guncelleRadarDarbeleri();
      guncelleHasarSayilari();
      guncelleLazerler();
      guncelleKalkanlar();
      taramaCizgiY += 0.5;
      if (taramaCizgiY > BY.state.canvasYukseklik) taramaCizgiY = 0;
      ortamEfektleriOlustur(zaman);
    },

    cizArkaPlan: function(ctx) {
      cizRadarDarbeleri(ctx);
      cizKalkanlar(ctx);
    },

    cizOnPlan: function(ctx) {
      cizParcaciklar(ctx);
      cizLazerler(ctx);
      cizHasarSayilari(ctx);
      taramaCizgisiCiz(ctx);
      crtParlamaCiz(ctx);
    },

    parcacikOlustur: parcacikOlustur,
    radarDarbesiEkle: radarDarbesiEkle,
    yetenekEfektiOlustur: yetenekEfektiOlustur,
    zaferEfektiOlustur: zaferEfektiOlustur,
    hasarEfektiOlustur: hasarEfektiOlustur,
    patlamaEfektiOlustur: patlamaEfektiOlustur,
    lazerEfektiOlustur: lazerEfektiOlustur,
    kalkanEfektiOlustur: kalkanEfektiOlustur
  };

})();