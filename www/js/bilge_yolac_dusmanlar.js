// www/js/bilge_yolac_dusmanlar.js
// Düşman sistemi: dünya uyumlu görünüm, ayrışan siluetler, dünya bazlı boss
// adları ve tematik mermi üretimi.

(function() {
  "use strict";

  var BY = window.BilgeYolac;
  if (!BY) return;

  var SPRITE_DRONE = [
    [0,0,0,3,3,0,0,0],
    [0,0,3,1,1,3,0,0],
    [0,3,1,4,4,1,3,0],
    [3,1,1,1,1,1,1,3],
    [0,2,1,1,1,1,2,0],
    [0,0,2,3,3,2,0,0],
    [0,2,0,0,0,0,2,0],
    [0,0,0,0,0,0,0,0]
  ];

  var SPRITE_SENTINEL = [
    [0,0,1,1,1,1,0,0],
    [0,1,2,3,3,2,1,0],
    [1,2,4,2,2,4,2,1],
    [1,1,1,1,1,1,1,1],
    [0,1,2,1,1,2,1,0],
    [0,1,2,1,1,2,1,0],
    [0,1,1,0,0,1,1,0],
    [0,2,2,0,0,2,2,0]
  ];

  var SPRITE_JAMMER = [
    [0,0,3,3,3,3,0,0],
    [0,3,1,1,1,1,3,0],
    [3,1,1,4,4,1,1,3],
    [3,1,1,1,1,1,1,3],
    [0,2,1,1,1,1,2,0],
    [0,0,2,2,2,2,0,0],
    [0,2,0,0,0,0,2,0],
    [2,0,0,0,0,0,0,2]
  ];

  var SPRITE_GLITCH = [
    [0,3,0,0,0,0,3,0],
    [3,1,3,0,0,3,1,3],
    [0,1,4,1,1,4,1,0],
    [0,0,1,1,1,1,0,0],
    [0,1,1,3,3,1,1,0],
    [1,2,0,1,1,0,2,1],
    [0,0,0,2,2,0,0,0],
    [0,0,2,0,0,2,0,0]
  ];

  var SPRITE_BOSS = [
    [0,0,0,3,3,3,3,3,3,3,3,0,0,0],
    [0,0,3,1,1,1,1,3,3,1,1,1,3,0],
    [0,3,1,2,1,1,1,1,1,1,1,2,1,3],
    [3,1,1,1,4,4,1,1,1,4,4,1,1,1],
    [3,1,2,1,1,1,1,3,3,1,1,1,1,2],
    [3,1,1,2,1,1,1,1,1,1,1,1,2,1],
    [3,1,1,2,1,1,1,1,1,1,1,1,2,1],
    [3,1,1,1,2,1,1,3,3,1,1,2,1,1],
    [3,1,1,1,1,2,2,1,1,2,2,1,1,1],
    [0,3,1,1,1,1,1,1,1,1,1,1,1,3],
    [0,0,3,1,1,1,2,2,2,2,1,1,3,0],
    [0,0,0,3,2,1,1,0,0,1,1,2,3,0],
    [0,0,0,0,2,2,0,0,0,0,2,2,0,0],
    [0,0,0,2,2,0,0,0,0,0,0,2,2,0]
  ];

  var DUSMAN_TIPLERI = {
    drone: { sprite: SPRITE_DRONE, boyut: 8, can: 26, hasar: 5, hiz: 0.85, puan: 15, ucan: true, saldiriAraligi: 120 },
    sentinel: { sprite: SPRITE_SENTINEL, boyut: 8, can: 60, hasar: 9, hiz: 0.55, puan: 22, ucan: false, saldiriAraligi: 96 },
    jammer: { sprite: SPRITE_JAMMER, boyut: 8, can: 42, hasar: 4, hiz: 0.12, puan: 18, ucan: false, saldiriAraligi: 110 },
    glitch: { sprite: SPRITE_GLITCH, boyut: 8, can: 38, hasar: 7, hiz: 0.70, puan: 20, ucan: false, saldiriAraligi: 135 },
    boss: { sprite: SPRITE_BOSS, boyut: 14, can: 320, hasar: 14, hiz: 0.42, puan: 120, ucan: false, saldiriAraligi: 90 }
  };

  function renkHaritasiOlustur(tip, dunyaId) {
    var temel = BY.config.DUSMAN_RENKLERI[tip] || BY.config.DUSMAN_RENKLERI.drone;
    var vurgu = temel.acik;
    if (dunyaId === "emre") vurgu = "#C6E6FF";
    if (dunyaId === "selin") vurgu = "#D8F1FF";
    if (dunyaId === "deniz") vurgu = "#A8FFC9";
    if (dunyaId === "can") vurgu = "#F4D6A8";
    if (dunyaId === "ipek") vurgu = "#FFDDF3";
    return { 1: temel.ana, 2: temel.koyu, 3: vurgu, 4: "#FFFFFF" };
  }

  function bossIsmiAl(dunyaId) {
    if (BY.varliklar && typeof BY.varliklar.bossVarligiAl === "function") {
      var boss = BY.varliklar.bossVarligiAl(dunyaId);
      if (boss && boss.isim) return boss.isim;
    }
    return "Engel";
  }

  function dusmanOlustur(x, tip) {
    var tanim = DUSMAN_TIPLERI[tip] || DUSMAN_TIPLERI.drone;
    var state = BY.state;
    var piksel = BY.config.PIKSEL_BOYUT;
    var boyut = tanim.boyut * piksel;
    var dunyaId = state.aktifDunyaId || "emre";

    var y = tanim.ucan ? state.zeminY * (0.28 + Math.random() * 0.28) : state.zeminY - boyut;

    return {
      tip: tip,
      isim: tip === "boss" ? bossIsmiAl(dunyaId) : tip.toUpperCase(),
      x: x,
      y: y,
      hizX: 0,
      hizY: 0,
      genislik: boyut,
      yukseklik: boyut,
      can: tanim.can,
      maxCan: tanim.can,
      hasar: tanim.hasar,
      hiz: tanim.hiz,
      sprite: tanim.sprite,
      renkHaritasi: renkHaritasiOlustur(tip, dunyaId),
      pikselBoyut: piksel,
      animKare: 0,
      durum: "devriye",
      saldiriZamanlayici: 0,
      yonX: -1,
      aktif: true,
      puan: tanim.puan,
      dalga: Math.random() * Math.PI * 2,
      teleportZamanlayici: 0,
      fazIndeksi: 0,
      minyonOlusturuldu: false,
      dunyaId: dunyaId
    };
  }

  function spriteFallbackCiz(ctx, dusman, ekranX) {
    var sprite = dusman.sprite;
    var renkler = dusman.renkHaritasi;
    var piksel = dusman.pikselBoyut;

    ctx.save();
    for (var satir = 0; satir < sprite.length; satir++) {
      for (var sutun = 0; sutun < sprite[satir].length; sutun++) {
        var deger = sprite[satir][sutun];
        if (!deger) continue;
        ctx.fillStyle = renkler[deger];
        ctx.fillRect(
          Math.floor(ekranX + sutun * piksel),
          Math.floor(dusman.y + satir * piksel),
          piksel,
          piksel
        );
      }
    }

    if (dusman.tip === "drone") {
      ctx.strokeStyle = dusman.renkHaritasi[3];
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(ekranX + 2, dusman.y + dusman.yukseklik * 0.5);
      ctx.lineTo(ekranX - 6, dusman.y + dusman.yukseklik * 0.25);
      ctx.moveTo(ekranX + dusman.genislik - 2, dusman.y + dusman.yukseklik * 0.5);
      ctx.lineTo(ekranX + dusman.genislik + 6, dusman.y + dusman.yukseklik * 0.25);
      ctx.stroke();
    } else if (dusman.tip === "jammer") {
      ctx.strokeStyle = dusman.renkHaritasi[3];
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.arc(ekranX + dusman.genislik / 2, dusman.y + dusman.yukseklik / 2, dusman.genislik * 0.8, 0, Math.PI * 2);
      ctx.stroke();
    } else if (dusman.tip === "glitch") {
      ctx.fillStyle = "rgba(255,255,255,0.16)";
      ctx.fillRect(ekranX - 3, dusman.y + 3, dusman.genislik + 6, 2);
      ctx.fillRect(ekranX + 4, dusman.y + dusman.yukseklik - 4, dusman.genislik - 8, 2);
    } else if (dusman.tip === "boss") {
      ctx.strokeStyle = dusman.renkHaritasi[3];
      ctx.lineWidth = 2;
      ctx.strokeRect(ekranX - 4, dusman.y - 4, dusman.genislik + 8, dusman.yukseklik + 8);
    }
    ctx.restore();
  }

  function dusmanSpriteCiz(ctx, dusman) {
    var state = BY.state;
    var ekranX = dusman.x - state.kameraX;
    if (ekranX < -80 || ekranX > state.canvasGenislik + 80) return;

    var varlik = BY.varliklar && BY.varliklar.dusmanVarligiAl ? BY.varliklar.dusmanVarligiAl(dusman.tip, dusman.dunyaId) : null;
    if (varlik && varlik.durum && varlik.durum.durum === "hazir") {
      ctx.save();
      if (dusman.tip === "glitch" && dusman.durum === "teleport") ctx.globalAlpha = 0.55;
      ctx.imageSmoothingEnabled = false;
      ctx.drawImage(varlik.durum.resim, Math.floor(ekranX), Math.floor(dusman.y), dusman.genislik, dusman.yukseklik);
      ctx.restore();
      return;
    }

    spriteFallbackCiz(ctx, dusman, ekranX);
  }

  function canBarCiz(ctx, dusman) {
    var state = BY.state;
    var ekranX = dusman.x - state.kameraX;
    if (ekranX < -80 || ekranX > state.canvasGenislik + 80) return;
    if (dusman.can >= dusman.maxCan) return;

    var g = dusman.genislik + 6;
    var h = 4;
    var x = ekranX - 3;
    var y = dusman.y - 8;
    var oran = dusman.can / dusman.maxCan;

    ctx.save();
    ctx.fillStyle = "rgba(0,0,0,0.55)";
    ctx.fillRect(x, y, g, h);
    ctx.fillStyle = oran > 0.5 ? "#2ECC71" : (oran > 0.2 ? "#F39C12" : "#E74C3C");
    ctx.fillRect(x, y, g * oran, h);
    ctx.restore();
  }

  function takimMerkeziAl() {
    return BY.karakterler && BY.karakterler.takimMerkeziAl ? BY.karakterler.takimMerkeziAl() : null;
  }

  function dusmanAtesEt(dusman, hedef) {
    if (!BY.cephanelik || !BY.cephanelik.dusmanAtisiOlustur || !hedef) return;
    BY.cephanelik.dusmanAtisiOlustur(dusman, hedef.x, hedef.y);

    if (BY.efektler && BY.efektler.lazerEfektiOlustur) {
      BY.efektler.lazerEfektiOlustur(
        dusman.x + dusman.genislik / 2,
        dusman.y + dusman.yukseklik / 2,
        hedef.x,
        hedef.y,
        dusman.renkHaritasi[1]
      );
    }
  }

  function droneGuncelle(dusman, takimMerkez) {
    dusman.dalga += 0.03;
    dusman.y += Math.sin(dusman.dalga) * 0.8;

    if (takimMerkez && Math.abs(dusman.x - takimMerkez.x) < 420) {
      dusman.yonX = takimMerkez.x < dusman.x ? -1 : 1;
      dusman.hizX = dusman.yonX * dusman.hiz * 0.6;
    } else {
      dusman.hizX *= 0.95;
    }

    dusman.x += dusman.hizX;
    dusman.saldiriZamanlayici++;
    if (dusman.saldiriZamanlayici > DUSMAN_TIPLERI.drone.saldiriAraligi && takimMerkez) {
      dusman.saldiriZamanlayici = 0;
      dusmanAtesEt(dusman, takimMerkez);
    }
  }

  function sentinelGuncelle(dusman, takimMerkez) {
    if (BY.fizik) {
      BY.fizik.yercegimiUygula(dusman);
      BY.fizik.platformCarpisma(dusman);
    }

    if (takimMerkez) {
      var mesafe = Math.abs(dusman.x - takimMerkez.x);
      if (mesafe < 320) {
        dusman.yonX = takimMerkez.x < dusman.x ? -1 : 1;
        dusman.hizX = dusman.yonX * dusman.hiz * (mesafe < 150 ? 1.8 : 1.0);
      }
    }

    dusman.x += dusman.hizX;
    dusman.hizX *= 0.84;

    if (takimMerkez && Math.abs(dusman.x - takimMerkez.x) < 40) {
      dusman.saldiriZamanlayici++;
      if (dusman.saldiriZamanlayici > DUSMAN_TIPLERI.sentinel.saldiriAraligi) {
        dusman.saldiriZamanlayici = 0;
        if (BY.karakterler && BY.karakterler.takimHasarAl) BY.karakterler.takimHasarAl(dusman.hasar);
        if (BY.efektler && BY.efektler.hasarEfektiOlustur) BY.efektler.hasarEfektiOlustur(takimMerkez.x, takimMerkez.y, "#FF6666");
      }
    }
  }

  function jammerGuncelle(dusman, takimMerkez) {
    if (BY.fizik) {
      BY.fizik.yercegimiUygula(dusman);
      BY.fizik.platformCarpisma(dusman);
    }

    dusman.saldiriZamanlayici++;
    if (dusman.saldiriZamanlayici > DUSMAN_TIPLERI.jammer.saldiriAraligi) {
      dusman.saldiriZamanlayici = 0;

      if (BY.efektler && BY.efektler.radarDarbesiEkle) {
        BY.efektler.radarDarbesiEkle(
          dusman.x + dusman.genislik / 2,
          dusman.y + dusman.yukseklik / 2,
          dusman.renkHaritasi[1]
        );
      }

      if (takimMerkez && Math.abs(dusman.x - takimMerkez.x) < 170) {
        if (BY.karakterler && BY.karakterler.takimHasarAl) BY.karakterler.takimHasarAl(dusman.hasar);
        dusmanAtesEt(dusman, takimMerkez);
      }
    }
  }

  function glitchGuncelle(dusman, takimMerkez) {
    dusman.teleportZamanlayici++;
    if (dusman.teleportZamanlayici > 180) {
      dusman.teleportZamanlayici = 0;
      dusman.durum = "teleport";

      if (takimMerkez) {
        dusman.x = takimMerkez.x + (Math.random() - 0.5) * 280;
        dusman.y = BY.state.zeminY - dusman.yukseklik - Math.random() * 84;
      }

      if (BY.efektler && BY.efektler.parcacikOlustur) {
        BY.efektler.parcacikOlustur(dusman.x, dusman.y, dusman.renkHaritasi[1], "kivilcim", 9);
      }

      if (takimMerkez) {
        for (var i = -1; i <= 1; i++) {
          dusmanAtesEt(dusman, { x: takimMerkez.x + i * 35, y: takimMerkez.y });
        }
      }

      setTimeout(function() { dusman.durum = "devriye"; }, 380);
    }

    if (BY.fizik) {
      BY.fizik.yercegimiUygula(dusman);
      BY.fizik.platformCarpisma(dusman);
    }
  }

  function bossGuncelle(dusman, takimMerkez) {
    if (BY.fizik) {
      BY.fizik.yercegimiUygula(dusman);
      BY.fizik.platformCarpisma(dusman);
    }

    var canYuzde = dusman.can / dusman.maxCan;
    dusman.fazIndeksi = canYuzde > 0.66 ? 0 : (canYuzde > 0.33 ? 1 : 2);

    if (takimMerkez) {
      var mesafe = dusman.x - takimMerkez.x;
      if (Math.abs(mesafe) > 120) {
        dusman.yonX = mesafe > 0 ? -1 : 1;
        dusman.hizX = dusman.yonX * dusman.hiz * (1 + dusman.fazIndeksi * 0.25);
      }
    }

    dusman.x += dusman.hizX;
    dusman.hizX *= 0.88;

    dusman.saldiriZamanlayici++;
    var aralik = 115 - dusman.fazIndeksi * 22;
    if (dusman.saldiriZamanlayici > aralik && takimMerkez) {
      dusman.saldiriZamanlayici = 0;

      if (dusman.fazIndeksi === 0) {
        dusmanAtesEt(dusman, takimMerkez);
      } else if (dusman.fazIndeksi === 1) {
        dusmanAtesEt(dusman, { x: takimMerkez.x - 40, y: takimMerkez.y });
        dusmanAtesEt(dusman, takimMerkez);
        dusmanAtesEt(dusman, { x: takimMerkez.x + 40, y: takimMerkez.y });

        if (!dusman.minyonOlusturuldu) {
          dusman.minyonOlusturuldu = true;
          BY.state.dusmanlar.push(dusmanOlustur(dusman.x - 70, "drone"));
          BY.state.dusmanlar.push(dusmanOlustur(dusman.x + 70, "drone"));
        }
      } else {
        for (var i = -2; i <= 2; i++) {
          dusmanAtesEt(dusman, { x: takimMerkez.x + i * 28, y: takimMerkez.y - (Math.abs(i) % 2) * 18 });
        }
      }
    }
  }

  function dusmanOlumu(dusman) {
    dusman.aktif = false;

    if (BY.efektler && BY.efektler.patlamaEfektiOlustur) {
      BY.efektler.patlamaEfektiOlustur(dusman.x + dusman.genislik / 2, dusman.y + dusman.yukseklik / 2);
    }

    if (BY.oyun && BY.oyun.skoreEkle) {
      BY.oyun.skoreEkle(dusman.puan || 10);
    }
  }

  BY.dusmanlar = {
    DUSMAN_TIPLERI: DUSMAN_TIPLERI,

    baslat: function(spawnlar) {
      var state = BY.state;
      state.dusmanlar = [];
      if (!spawnlar || !Array.isArray(spawnlar)) return;
      for (var i = 0; i < spawnlar.length; i++) {
        state.dusmanlar.push(dusmanOlustur(spawnlar[i].x, spawnlar[i].tip));
      }
    },

    guncelle: function(zaman) {
      var state = BY.state;
      var takimMerkez = takimMerkeziAl();
      var dusmanlar = state.dusmanlar;
      if (!dusmanlar) return;

      for (var i = dusmanlar.length - 1; i >= 0; i--) {
        var d = dusmanlar[i];
        if (!d || !d.aktif) continue;

        if (d.can <= 0) {
          dusmanOlumu(d);
          continue;
        }

        if (Math.abs(d.x - state.kameraX - state.canvasGenislik / 2) > 760) continue;

        d.animKare = (d.animKare + 1) % 120;

        switch (d.tip) {
          case "drone": droneGuncelle(d, takimMerkez); break;
          case "sentinel": sentinelGuncelle(d, takimMerkez); break;
          case "jammer": jammerGuncelle(d, takimMerkez); break;
          case "glitch": glitchGuncelle(d, takimMerkez); break;
          case "boss": bossGuncelle(d, takimMerkez); break;
        }
      }

      if (state.kare % 60 === 0) {
        for (var j = dusmanlar.length - 1; j >= 0; j--) {
          if (dusmanlar[j] && !dusmanlar[j].aktif) dusmanlar.splice(j, 1);
        }
      }
    },

    ciz: function(ctx) {
      var state = BY.state;
      var dusmanlar = state.dusmanlar;
      if (!dusmanlar) return;

      for (var i = 0; i < dusmanlar.length; i++) {
        var d = dusmanlar[i];
        if (!d || !d.aktif) continue;

        var ekranX = d.x - state.kameraX;
        if (ekranX < -80 || ekranX > state.canvasGenislik + 80) continue;

        ctx.save();
        ctx.fillStyle = "rgba(0,0,0,0.20)";
        ctx.beginPath();
        ctx.ellipse(ekranX + d.genislik / 2, state.zeminY - 1, d.genislik / 2, 3, 0, 0, Math.PI * 2);
        ctx.fill();
        ctx.restore();

        dusmanSpriteCiz(ctx, d);
        canBarCiz(ctx, d);

        if (d.tip === "jammer") {
          ctx.save();
          ctx.globalAlpha = 0.08 + Math.sin(d.animKare * 0.05) * 0.05;
          ctx.strokeStyle = d.renkHaritasi[1];
          ctx.lineWidth = 1;
          ctx.beginPath();
          ctx.arc(ekranX + d.genislik / 2, d.y + d.yukseklik / 2, 100, 0, Math.PI * 2);
          ctx.stroke();
          ctx.restore();
        }

        if (d.tip === "boss") {
          ctx.save();
          ctx.globalAlpha = 0.14;
          ctx.fillStyle = d.renkHaritasi[1];
          ctx.shadowColor = d.renkHaritasi[3];
          ctx.shadowBlur = 12;
          ctx.beginPath();
          ctx.arc(ekranX + d.genislik / 2, d.y + d.yukseklik / 2, d.genislik, 0, Math.PI * 2);
          ctx.fill();
          ctx.restore();
        }
      }

      if (BY.cephanelik && BY.cephanelik.mermileriCiz) {
        BY.cephanelik.mermileriCiz(ctx);
      }
    },

    hasarVer: function(dusman, miktar) {
      if (!dusman) return;
      dusman.can -= miktar;

      if (BY.efektler && BY.efektler.hasarEfektiOlustur) {
        BY.efektler.hasarEfektiOlustur(dusman.x + dusman.genislik / 2, dusman.y, "#FF6666");
      }

      if (BY.efektler && BY.efektler.parcacikOlustur) {
        BY.efektler.parcacikOlustur(
          dusman.x + dusman.genislik / 2,
          dusman.y + dusman.yukseklik / 2,
          dusman.renkHaritasi[1],
          "kivilcim",
          4
        );
      }
    },

    bossBaşlat: function(bossVeri) {
      if (!bossVeri) return;
      BY.state.dusmanlar.push(dusmanOlustur(bossVeri.x, "boss"));
    },

    boyutGuncelle: function() {
      var state = BY.state;
      for (var i = 0; i < state.dusmanlar.length; i++) {
        var d = state.dusmanlar[i];
        if (d && !DUSMAN_TIPLERI[d.tip].ucan) {
          d.y = state.zeminY - d.yukseklik;
        }
      }
    }
  };

})();