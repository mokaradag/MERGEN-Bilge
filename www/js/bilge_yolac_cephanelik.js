// =============================================================================
// Dosya Yolu: www/js/bilge_yolac_cephanelik.js
// Açıklama: Bilge Yolaç için karaktere ve düşmana özgü mermi/enerji sistemi.
//           Tematik atış oluşturma, mermi profilleri ve retro uyumlu çizim
//           geri dönüşleri bu modülde tutulur.
// =============================================================================

(function() {
  "use strict";

  var BY = window.BilgeYolac;
  if (!BY) return;

  var OYUNCU_PROFILLERI = {
    mergen: {
      tur: "ok",
      hiz: 5.8,
      genislik: 18,
      yukseklik: 5,
      hasar: 10,
      renk: "#C7A95A",
      izRenk: "rgba(255,240,180,0.55)",
      varlikId: "mergen"
    },
    ulgen: {
      tur: "gok_parlama",
      hiz: 4.6,
      genislik: 12,
      yukseklik: 12,
      hasar: 9,
      renk: "#A7E2FF",
      izRenk: "rgba(167,226,255,0.60)",
      varlikId: "ulgen"
    },
    kayra: {
      tur: "runkure",
      hiz: 4.2,
      genislik: 14,
      yukseklik: 14,
      hasar: 8,
      renk: "#86F0B6",
      izRenk: "rgba(134,240,182,0.58)",
      varlikId: "kayra"
    },
    erlik: {
      tur: "bozulma_kirigi",
      hiz: 4.9,
      genislik: 12,
      yukseklik: 10,
      hasar: 11,
      renk: "#FF5D86",
      izRenk: "rgba(255,93,134,0.60)",
      varlikId: "erlik"
    },
    umay_ana: {
      tur: "koruyucu_darbe",
      hiz: 4.0,
      genislik: 16,
      yukseklik: 16,
      hasar: 6,
      renk: "#FFD6F0",
      izRenk: "rgba(255,214,240,0.60)",
      varlikId: "umay_ana"
    }
  };

  var DUSMAN_PROFILLERI = {
    drone: {
      tur: "drone_boltu",
      hiz: 3.4,
      genislik: 10,
      yukseklik: 4,
      renk: "#7DEFFF",
      izRenk: "rgba(125,239,255,0.45)",
      varlikId: "drone"
    },
    jammer: {
      tur: "karistirma_nabzi",
      hiz: 2.6,
      genislik: 12,
      yukseklik: 12,
      renk: "#FFB04A",
      izRenk: "rgba(255,176,74,0.40)",
      varlikId: "jammer"
    },
    sentinel: {
      tur: "mizrak_lazer",
      hiz: 3.0,
      genislik: 14,
      yukseklik: 4,
      renk: "#B78DFF",
      izRenk: "rgba(183,141,255,0.45)",
      varlikId: "sentinel"
    },
    glitch: {
      tur: "glitch_kaosu",
      hiz: 3.3,
      genislik: 12,
      yukseklik: 10,
      renk: "#FF4477",
      izRenk: "rgba(255,68,119,0.42)",
      varlikId: "glitch"
    },
    boss: {
      tur: "cekirdek_patlamasi",
      hiz: 3.8,
      genislik: 16,
      yukseklik: 16,
      renk: "#FFE16C",
      izRenk: "rgba(255,225,108,0.52)",
      varlikId: "boss"
    }
  };

  function hedefeVektor(kaynakX, kaynakY, hedefX, hedefY, hiz) {
    var dx = hedefX - kaynakX;
    var dy = hedefY - kaynakY;
    var mesafe = Math.sqrt(dx * dx + dy * dy) || 1;
    return {
      hizX: (dx / mesafe) * hiz,
      hizY: (dy / mesafe) * hiz,
      aci: Math.atan2(dy, dx)
    };
  }

  function ortakMermiOlustur(temel) {
    var m = {};
    for (var anahtar in temel) {
      if (Object.prototype.hasOwnProperty.call(temel, anahtar)) {
        m[anahtar] = temel[anahtar];
      }
    }
    return m;
  }

  function oyuncuAtisiOlustur(karakter, hedefX, hedefY, secenekler) {
    if (!karakter) return null;
    secenekler = secenekler || {};

    var profil = OYUNCU_PROFILLERI[karakter.id] || OYUNCU_PROFILLERI.mergen;
    var kaynakX = secenekler.kaynakX || (karakter.x + karakter.genislik * 0.55);
    var kaynakY = secenekler.kaynakY || (karakter.y + karakter.yukseklik * 0.42);
    var yayilma = secenekler.yayilma || 0;
    var hiz = secenekler.hiz || profil.hiz;
    var hedef = hedefeVektor(kaynakX, kaynakY, hedefX, hedefY, hiz);
    var aci = hedef.aci + yayilma;

    var mermi = ortakMermiOlustur({
      x: kaynakX,
      y: kaynakY,
      hizX: Math.cos(aci) * hiz,
      hizY: Math.sin(aci) * hiz,
      aci: aci,
      hasar: secenekler.hasar || profil.hasar,
      sahip: "takim",
      yasam: secenekler.yasam || 130,
      genislik: profil.genislik,
      yukseklik: profil.yukseklik,
      renk: profil.renk,
      izRenk: profil.izRenk,
      tur: profil.tur,
      karakterId: karakter.id,
      vurmaEfekti: secenekler.vurmaEfekti || profil.tur,
      spriteId: profil.varlikId
    });

    if (BY.state && BY.state.mermiler) {
      BY.state.mermiler.push(mermi);
    }
    return mermi;
  }

  function dusmanAtisiOlustur(dusman, hedefX, hedefY, secenekler) {
    if (!dusman) return null;
    secenekler = secenekler || {};

    var profil = DUSMAN_PROFILLERI[dusman.tip] || DUSMAN_PROFILLERI.drone;
    var kaynakX = secenekler.kaynakX || (dusman.x + dusman.genislik * 0.50);
    var kaynakY = secenekler.kaynakY || (dusman.y + dusman.yukseklik * 0.50);
    var hedef = hedefeVektor(kaynakX, kaynakY, hedefX, hedefY, secenekler.hiz || profil.hiz);

    var mermi = ortakMermiOlustur({
      x: kaynakX,
      y: kaynakY,
      hizX: hedef.hizX,
      hizY: hedef.hizY,
      aci: hedef.aci,
      hasar: secenekler.hasar || dusman.hasar || 6,
      sahip: "dusman",
      yasam: secenekler.yasam || 160,
      genislik: profil.genislik,
      yukseklik: profil.yukseklik,
      renk: profil.renk,
      izRenk: profil.izRenk,
      tur: profil.tur,
      dusmanTipi: dusman.tip,
      spriteId: profil.varlikId
    });

    if (BY.state && BY.state.mermiler) {
      BY.state.mermiler.push(mermi);
    }
    return mermi;
  }

  function cizYedekMermi(ctx, ekranX, m) {
    ctx.save();
    ctx.translate(ekranX, m.y);
    ctx.rotate(m.aci || 0);

    if (m.tur === "ok") {
      ctx.fillStyle = "#E6D1A3";
      ctx.fillRect(-8, -1, 12, 2);
      ctx.fillStyle = "#B28A3D";
      ctx.fillRect(3, -2, 4, 4);
      ctx.beginPath();
      ctx.moveTo(8, 0);
      ctx.lineTo(3, -3);
      ctx.lineTo(3, 3);
      ctx.closePath();
      ctx.fill();
    } else if (m.tur === "gok_parlama") {
      ctx.fillStyle = m.renk;
      ctx.shadowColor = m.renk;
      ctx.shadowBlur = 8;
      ctx.beginPath();
      ctx.arc(0, 0, 5, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = "#FFFFFF";
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(-7, 0);
      ctx.lineTo(7, 0);
      ctx.moveTo(0, -7);
      ctx.lineTo(0, 7);
      ctx.stroke();
    } else if (m.tur === "runkure") {
      ctx.fillStyle = m.renk;
      ctx.beginPath();
      ctx.arc(0, 0, 6, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = "#E4FFF3";
      ctx.lineWidth = 1;
      ctx.strokeRect(-3, -3, 6, 6);
      ctx.strokeRect(-5, -1, 10, 2);
    } else if (m.tur === "bozulma_kirigi" || m.tur === "glitch_kaosu") {
      ctx.fillStyle = m.renk;
      ctx.fillRect(-6, -2, 12, 4);
      ctx.fillRect(-2, -6, 4, 12);
      ctx.fillStyle = "#FFFFFF";
      ctx.fillRect(-5, 1, 6, 2);
      ctx.fillRect(1, -5, 2, 6);
    } else if (m.tur === "koruyucu_darbe" || m.tur === "karistirma_nabzi" || m.tur === "cekirdek_patlamasi") {
      ctx.strokeStyle = m.renk;
      ctx.shadowColor = m.renk;
      ctx.shadowBlur = 6;
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(0, 0, 6, 0, Math.PI * 2);
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(0, 0, 2, 0, Math.PI * 2);
      ctx.fillStyle = m.renk;
      ctx.fill();
    } else if (m.tur === "mizrak_lazer" || m.tur === "drone_boltu") {
      ctx.fillStyle = m.renk;
      ctx.fillRect(-7, -1.5, 14, 3);
      ctx.fillStyle = "#FFFFFF";
      ctx.fillRect(-3, -0.5, 6, 1);
    } else {
      ctx.fillStyle = m.renk || "#FFFFFF";
      ctx.fillRect(-3, -3, 6, 6);
    }

    ctx.restore();
  }

  function mermiVarligiCiz(ctx, ekranX, m) {
    var kayit = BY.varliklar && BY.varliklar.mermiVarligiAl ? BY.varliklar.mermiVarligiAl(m.spriteId || m.karakterId || m.dusmanTipi) : null;
    if (!kayit || !kayit.durum || kayit.durum.durum !== "hazir") {
      cizYedekMermi(ctx, ekranX, m);
      return;
    }

    ctx.save();
    ctx.translate(ekranX, m.y);
    ctx.rotate(m.aci || 0);
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(kayit.durum.resim, -m.genislik / 2, -m.yukseklik / 2, m.genislik, m.yukseklik);
    ctx.restore();
  }

  function mermiIzleriCiz(ctx, ekranX, m) {
    if (!m.izRenk) return;

    ctx.save();
    ctx.strokeStyle = m.izRenk;
    ctx.shadowColor = m.izRenk;
    ctx.shadowBlur = 6;
    ctx.lineWidth = Math.max(1, Math.min(3, (m.yukseklik || 4) * 0.25));
    ctx.beginPath();
    ctx.moveTo(ekranX, m.y);
    ctx.lineTo(ekranX - (m.hizX || 0) * 3, m.y - (m.hizY || 0) * 3);
    ctx.stroke();
    ctx.restore();
  }

  BY.cephanelik = {
    OYUNCU_PROFILLERI: OYUNCU_PROFILLERI,
    DUSMAN_PROFILLERI: DUSMAN_PROFILLERI,
    oyuncuAtisiOlustur: oyuncuAtisiOlustur,
    dusmanAtisiOlustur: dusmanAtisiOlustur,

    mermileriCiz: function(ctx) {
      var state = BY.state;
      if (!state || !state.mermiler) return;

      for (var i = 0; i < state.mermiler.length; i++) {
        var m = state.mermiler[i];
        var ekranX = m.x - state.kameraX;
        if (ekranX < -30 || ekranX > state.canvasGenislik + 30) continue;

        mermiIzleriCiz(ctx, ekranX, m);
        mermiVarligiCiz(ctx, ekranX, m);
      }
    }
  };

})();