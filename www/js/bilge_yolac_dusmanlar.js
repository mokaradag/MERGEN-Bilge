// www/js/bilge_yolac_dusmanlar.js
// Düşman sistemi: 4 düşman tipi (Drone, Sentinel, Jammer, Glitch) + Boss, yapay zekâ davranışları, saldırı kalıpları

(function() {
  "use strict";

  var BY = window.BilgeYolac;
  if (!BY) return;

  // ── Düşman sprite verileri (8x8 piksel) ───────────────────────────────────
  // Renk kodları: 0=boş, 1=gövde ana, 2=koyu, 3=açık, 4=göz/enerji

  var SPRITE_DRONE = [
    [0,0,3,3,3,3,0,0],
    [0,3,1,1,1,1,3,0],
    [3,1,4,1,1,4,1,3],
    [3,1,1,1,1,1,1,3],
    [0,2,1,1,1,1,2,0],
    [0,0,2,3,3,2,0,0],
    [0,0,0,2,2,0,0,0],
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
    [0,0,0,3,3,0,0,0],
    [0,0,3,1,1,3,0,0],
    [0,3,1,4,4,1,3,0],
    [3,1,1,1,1,1,1,3],
    [3,1,1,1,1,1,1,3],
    [0,2,1,1,1,1,2,0],
    [0,0,2,2,2,2,0,0],
    [0,2,0,0,0,0,2,0]
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

  // Boss sprite (16x16) - Kozmik Muhafız
  var SPRITE_BOSS = [
    [0,0,0,0,3,3,3,3,3,3,3,3,0,0,0,0],
    [0,0,0,3,1,1,1,3,3,1,1,1,3,0,0,0],
    [0,0,3,1,2,1,1,1,1,1,1,2,1,3,0,0],
    [0,3,1,1,1,4,4,1,1,4,4,1,1,1,3,0],
    [0,3,1,1,1,4,4,1,1,4,4,1,1,1,3,0],
    [0,3,2,1,1,1,1,1,1,1,1,1,1,2,3,0],
    [3,1,2,1,1,1,3,3,3,3,1,1,1,2,1,3],
    [3,1,1,2,1,1,1,1,1,1,1,1,2,1,1,3],
    [3,1,1,2,1,1,1,1,1,1,1,1,2,1,1,3],
    [3,1,1,1,2,1,1,3,3,1,1,2,1,1,1,3],
    [0,3,1,1,1,2,2,1,1,2,2,1,1,1,3,0],
    [0,3,1,1,1,1,1,1,1,1,1,1,1,1,3,0],
    [0,0,3,1,1,1,2,2,2,2,1,1,1,3,0,0],
    [0,0,0,3,2,1,1,0,0,1,1,2,3,0,0,0],
    [0,0,0,0,2,2,0,0,0,0,2,2,0,0,0,0],
    [0,0,0,2,2,0,0,0,0,0,0,2,2,0,0,0]
  ];

  // ── Düşman tipi tanımları ─────────────────────────────────────────────────
  var DUSMAN_TIPLERI = {
    drone: {
      sprite: SPRITE_DRONE,
      boyut: 8,
      can: 30,
      hasar: 5,
      hiz: 0.8,
      puan: 10,
      ucan: true,
      saldiriAraligi: 120
    },
    sentinel: {
      sprite: SPRITE_SENTINEL,
      boyut: 8,
      can: 60,
      hasar: 10,
      hiz: 0.5,
      puan: 25,
      ucan: false,
      saldiriAraligi: 90
    },
    jammer: {
      sprite: SPRITE_JAMMER,
      boyut: 8,
      can: 40,
      hasar: 3,
      hiz: 0,
      puan: 15,
      ucan: false,
      saldiriAraligi: 90
    },
    glitch: {
      sprite: SPRITE_GLITCH,
      boyut: 8,
      can: 35,
      hasar: 7,
      hiz: 0.6,
      puan: 20,
      ucan: false,
      saldiriAraligi: 150
    },
    boss: {
      sprite: SPRITE_BOSS,
      boyut: 16,
      can: 300,
      hasar: 15,
      hiz: 0.4,
      puan: 100,
      ucan: false,
      saldiriAraligi: 120
    }
  };

  // ── Renk haritası oluştur ─────────────────────────────────────────────────
  function renkHaritasiOlustur(tip) {
    var renkler = BY.config.DUSMAN_RENKLERI[tip] || BY.config.DUSMAN_RENKLERI.drone;
    return {
      1: renkler.ana,
      2: renkler.koyu,
      3: renkler.acik,
      4: "#FF0000"
    };
  }

  // ── Düşman nesnesi oluştur ────────────────────────────────────────────────
  function dusmanOlustur(x, tip) {
    var tanim = DUSMAN_TIPLERI[tip];
    if (!tanim) tanim = DUSMAN_TIPLERI.drone;

    var state = BY.state;
    var piksel = BY.config.PIKSEL_BOYUT;
    var genislik = tanim.boyut * piksel;
    var yukseklik = tanim.boyut * piksel;

    // Y pozisyonu: uçan düşmanlar havada, diğerleri zeminde
    var y;
    if (tanim.ucan) {
      y = state.zeminY * (0.3 + Math.random() * 0.3);
    } else {
      y = state.zeminY - yukseklik;
    }

    return {
      tip: tip,
      x: x,
      y: y,
      hizX: 0,
      hizY: 0,
      genislik: genislik,
      yukseklik: yukseklik,
      can: tanim.can,
      maxCan: tanim.can,
      hasar: tanim.hasar,
      hiz: tanim.hiz,
      sprite: tanim.sprite,
      renkHaritasi: renkHaritasiOlustur(tip),
      pikseBoyut: piksel,
      animKare: 0,
      durum: "patrol",
      saldiriZamanlayici: 0,
      yonX: -1,
      aktif: true,
      puan: tanim.puan,
      // Tipe özel durum
      dalga: Math.random() * Math.PI * 2,
      teleportZamanlayici: 0,
      fazIndeksi: 0,   // Boss fazı
      minyonOlusturuldu: false
    };
  }

  // ── Sprite çizim ──────────────────────────────────────────────────────────
  function dusmanSpriteCiz(ctx, dusman) {
    var state = BY.state;
    var ekranX = dusman.x - state.kameraX;

    // Ekran dışındaysa çizme
    if (ekranX < -50 || ekranX > state.canvasGenislik + 50) return;

    var sprite = dusman.sprite;
    var renkler = dusman.renkHaritasi;
    var piksel = dusman.pikseBoyut;

    if (!sprite) return;

    ctx.save();

    // Glitch tipi için bozulma efekti
    if (dusman.tip === "glitch" && dusman.durum === "teleport") {
      ctx.globalAlpha = 0.4 + Math.random() * 0.3;
    }

    // Sprite piksellerini çiz
    for (var satir = 0; satir < sprite.length; satir++) {
      for (var sutun = 0; sutun < sprite[satir].length; sutun++) {
        var deger = sprite[satir][sutun];
        if (deger === 0) continue;

        var renk = renkler[deger];
        if (!renk) continue;

        ctx.fillStyle = renk;
        var cX = Math.floor(ekranX + sutun * piksel);
        var cY = Math.floor(dusman.y + satir * piksel);
        ctx.fillRect(cX, cY, piksel, piksel);
      }
    }

    ctx.restore();
  }

  // ── Sağlık çubuğu çiz ────────────────────────────────────────────────────
  function canBarCiz(ctx, dusman) {
    var state = BY.state;
    var ekranX = dusman.x - state.kameraX;
    if (ekranX < -50 || ekranX > state.canvasGenislik + 50) return;
    if (dusman.can >= dusman.maxCan) return; // Tam cansa gösterme

    var barG = dusman.genislik + 4;
    var barY2 = 3;
    var barX = ekranX - 2;
    var barY = dusman.y - 6;
    var canYuzde = dusman.can / dusman.maxCan;

    ctx.save();
    // Arka plan
    ctx.fillStyle = "rgba(0,0,0,0.5)";
    ctx.fillRect(barX, barY, barG, barY2);
    // Can dolgusu
    var renk = canYuzde > 0.5 ? "#2ECC71" : (canYuzde > 0.2 ? "#F39C12" : "#E74C3C");
    ctx.fillStyle = renk;
    ctx.fillRect(barX, barY, barG * canYuzde, barY2);
    ctx.restore();
  }

  // ── Düşman AI güncelleme ──────────────────────────────────────────────────

  function droneGuncelle(dusman, takimMerkez) {
    // Sinüs dalgası ile yukarı-aşağı hareket
    dusman.dalga += 0.03;
    dusman.y += Math.sin(dusman.dalga) * 0.8;

    // Takıma yaklaşma
    if (takimMerkez && Math.abs(dusman.x - takimMerkez.x) < 400) {
      var yonX = takimMerkez.x < dusman.x ? -1 : 1;
      dusman.hizX = yonX * dusman.hiz * 0.5;
      dusman.yonX = yonX;
    } else {
      dusman.hizX *= 0.95;
    }

    dusman.x += dusman.hizX;

    // Periyodik saldırı - lazer mermisi
    dusman.saldiriZamanlayici++;
    if (dusman.saldiriZamanlayici > DUSMAN_TIPLERI.drone.saldiriAraligi && takimMerkez) {
      dusman.saldiriZamanlayici = 0;
      mermiOlustur(dusman, takimMerkez);
    }
  }

  function sentinelGuncelle(dusman, takimMerkez) {
    // Yerçekimi ve platform çarpışması
    if (BY.fizik) {
      BY.fizik.yercegimiUygula(dusman);
      BY.fizik.platformCarpisma(dusman);
    }

    // Takıma doğru yürü
    if (takimMerkez) {
      var mesafe = Math.abs(dusman.x - takimMerkez.x);
      if (mesafe < 300) {
        var yonX = takimMerkez.x < dusman.x ? -1 : 1;
        // Yakınsa koşma (charge)
        var hizCarpani = mesafe < 150 ? 2 : 1;
        dusman.hizX = yonX * dusman.hiz * hizCarpani;
        dusman.yonX = yonX;
      }
    }

    dusman.x += dusman.hizX;
    dusman.hizX *= 0.9;

    // Temas hasarı
    if (takimMerkez && Math.abs(dusman.x - takimMerkez.x) < 30) {
      dusman.saldiriZamanlayici++;
      if (dusman.saldiriZamanlayici > DUSMAN_TIPLERI.sentinel.saldiriAraligi) {
        dusman.saldiriZamanlayici = 0;
        if (BY.karakterler && BY.karakterler.takimHasarAl) {
          BY.karakterler.takimHasarAl(dusman.hasar);
        }
        if (BY.efektler && BY.efektler.hasarEfektiOlustur) {
          BY.efektler.hasarEfektiOlustur(takimMerkez.x, takimMerkez.y, "#FF4444");
        }
      }
    }
  }

  function jammerGuncelle(dusman, takimMerkez) {
    // Jammer hareketsiz kalır, periyodik alan hasarı verir
    if (BY.fizik) {
      BY.fizik.yercegimiUygula(dusman);
      BY.fizik.platformCarpisma(dusman);
    }

    dusman.saldiriZamanlayici++;
    if (dusman.saldiriZamanlayici > DUSMAN_TIPLERI.jammer.saldiriAraligi) {
      dusman.saldiriZamanlayici = 0;

      // Alan hasarı - takım yakındaysa
      if (takimMerkez && Math.abs(dusman.x - takimMerkez.x) < 150) {
        if (BY.karakterler && BY.karakterler.takimHasarAl) {
          BY.karakterler.takimHasarAl(dusman.hasar);
        }

        // Nabız halkası efekti
        if (BY.efektler && BY.efektler.radarDarbesiEkle) {
          BY.efektler.radarDarbesiEkle(
            dusman.x + dusman.genislik / 2,
            dusman.y + dusman.yukseklik / 2,
            BY.config.DUSMAN_RENKLERI.jammer.ana
          );
        }
      }
    }
  }

  function glitchGuncelle(dusman, takimMerkez) {
    // Periyodik ışınlanma
    dusman.teleportZamanlayici++;
    if (dusman.teleportZamanlayici > 180) {
      dusman.teleportZamanlayici = 0;
      dusman.durum = "teleport";

      // Rastgele yeni pozisyon (takım civarında)
      if (takimMerkez) {
        dusman.x = takimMerkez.x + (Math.random() - 0.5) * 300;
        dusman.y = BY.state.zeminY - dusman.yukseklik - Math.random() * 80;
      }

      // Işınlanma efekti
      if (BY.efektler && BY.efektler.parcacikOlustur) {
        BY.efektler.parcacikOlustur(
          dusman.x + dusman.genislik / 2,
          dusman.y + dusman.yukseklik / 2,
          BY.config.DUSMAN_RENKLERI.glitch.ana,
          "kivilcim", 8
        );
      }

      // 3'lü mermi patlaması
      if (takimMerkez) {
        for (var i = -1; i <= 1; i++) {
          mermiOlustur(dusman, {
            x: takimMerkez.x + i * 30,
            y: takimMerkez.y
          });
        }
      }

      // Kısa süre sonra görünür ol
      setTimeout(function() { dusman.durum = "patrol"; }, 500);
    }

    // Yerçekimi
    if (BY.fizik) {
      BY.fizik.yercegimiUygula(dusman);
      BY.fizik.platformCarpisma(dusman);
    }
  }

  function bossGuncelle(dusman, takimMerkez) {
    // Yerçekimi
    if (BY.fizik) {
      BY.fizik.yercegimiUygula(dusman);
      BY.fizik.platformCarpisma(dusman);
    }

    // Boss fazı belirle
    var canYuzde = dusman.can / dusman.maxCan;
    if (canYuzde > 0.6) {
      dusman.fazIndeksi = 0;
    } else if (canYuzde > 0.3) {
      dusman.fazIndeksi = 1;
    } else {
      dusman.fazIndeksi = 2;
    }

    // Takıma doğru yavaş hareket
    if (takimMerkez) {
      var mesafe = dusman.x - takimMerkez.x;
      if (Math.abs(mesafe) > 100) {
        var yonX = mesafe > 0 ? -1 : 1;
        dusman.hizX = yonX * dusman.hiz * (1 + dusman.fazIndeksi * 0.3);
        dusman.yonX = yonX;
      }
    }

    dusman.x += dusman.hizX;
    dusman.hizX *= 0.9;

    // Saldırı kalıpları faza göre
    var saldiriHizi = 120 - dusman.fazIndeksi * 30; // Faz arttıkça hızlanır
    dusman.saldiriZamanlayici++;

    if (dusman.saldiriZamanlayici > saldiriHizi && takimMerkez) {
      dusman.saldiriZamanlayici = 0;

      switch (dusman.fazIndeksi) {
        case 0: // Yavaş lazer çizgisi
          mermiOlustur(dusman, takimMerkez);
          break;

        case 1: // Geniş saldırı + minyon
          mermiOlustur(dusman, { x: takimMerkez.x - 40, y: takimMerkez.y });
          mermiOlustur(dusman, takimMerkez);
          mermiOlustur(dusman, { x: takimMerkez.x + 40, y: takimMerkez.y });

          // Faz 2'de bir kez minyon oluştur
          if (!dusman.minyonOlusturuldu) {
            dusman.minyonOlusturuldu = true;
            // 2 drone minyon
            BY.state.dusmanlar.push(dusmanOlustur(dusman.x - 60, "drone"));
            BY.state.dusmanlar.push(dusmanOlustur(dusman.x + 60, "drone"));
          }
          break;

        case 2: // Öfke modu - hızlı ateş
          for (var i = -2; i <= 2; i++) {
            mermiOlustur(dusman, {
              x: takimMerkez.x + i * 25,
              y: takimMerkez.y
            });
          }
          break;
      }
    }
  }

  // ── Mermi oluştur ─────────────────────────────────────────────────────────
  function mermiOlustur(dusman, hedef) {
    var state = BY.state;
    var kaynakX = dusman.x + dusman.genislik / 2;
    var kaynakY = dusman.y + dusman.yukseklik / 2;

    var dx = hedef.x - kaynakX;
    var dy = hedef.y - kaynakY;
    var mesafe = Math.sqrt(dx * dx + dy * dy);
    if (mesafe < 1) mesafe = 1;

    var hiz = 2.5;
    state.mermiler.push({
      x: kaynakX,
      y: kaynakY,
      hizX: (dx / mesafe) * hiz,
      hizY: (dy / mesafe) * hiz,
      hasar: dusman.hasar,
      sahip: "dusman",
      yasam: 180,
      genislik: 4,
      yukseklik: 4,
      renk: dusman.renkHaritasi[1] || "#FF0000"
    });

    // Lazer efekti
    if (BY.efektler && BY.efektler.lazerEfektiOlustur) {
      BY.efektler.lazerEfektiOlustur(kaynakX, kaynakY, hedef.x, hedef.y, dusman.renkHaritasi[1]);
    }
  }

  // ── Düşman ölüm işleme ───────────────────────────────────────────────────
  function dusmanOlumu(dusman) {
    dusman.aktif = false;

    // Patlama efekti
    if (BY.efektler && BY.efektler.patlamaEfektiOlustur) {
      BY.efektler.patlamaEfektiOlustur(
        dusman.x + dusman.genislik / 2,
        dusman.y + dusman.yukseklik / 2
      );
    }

    // Puan ekle
    if (BY.oyun && BY.oyun.skoreEkle) {
      BY.oyun.skoreEkle(dusman.puan || 10);
    }
  }

  // ── Dış arayüz ─────────────────────────────────────────────────────────────
  BY.dusmanlar = {
    DUSMAN_TIPLERI: DUSMAN_TIPLERI,

    baslat: function(spawnlar) {
      var state = BY.state;
      state.dusmanlar = [];

      if (!spawnlar || !Array.isArray(spawnlar)) return;

      for (var i = 0; i < spawnlar.length; i++) {
        var s = spawnlar[i];
        state.dusmanlar.push(dusmanOlustur(s.x, s.tip));
      }
    },

    guncelle: function(zaman) {
      var state = BY.state;
      var dusmanlar = state.dusmanlar;
      if (!dusmanlar) return;

      var takimMerkez = BY.karakterler ? BY.karakterler.takimMerkeziAl() : null;

      for (var i = dusmanlar.length - 1; i >= 0; i--) {
        var d = dusmanlar[i];
        if (!d || !d.aktif) continue;

        // Can kontrolü
        if (d.can <= 0) {
          dusmanOlumu(d);
          continue;
        }

        // Görünür alanın yakınındaki düşmanları güncelle (±600px)
        if (Math.abs(d.x - state.kameraX - state.canvasGenislik / 2) > 600) continue;

        // Animasyon karesi
        d.animKare = (d.animKare + 1) % 120;

        // Tipe göre AI güncelle
        switch (d.tip) {
          case "drone":
            droneGuncelle(d, takimMerkez);
            break;
          case "sentinel":
            sentinelGuncelle(d, takimMerkez);
            break;
          case "jammer":
            jammerGuncelle(d, takimMerkez);
            break;
          case "glitch":
            glitchGuncelle(d, takimMerkez);
            break;
          case "boss":
            bossGuncelle(d, takimMerkez);
            break;
        }
      }

      // Ölü düşmanları temizle (periyodik)
      if (state.kare % 60 === 0) {
        for (var j = dusmanlar.length - 1; j >= 0; j--) {
          if (dusmanlar[j] && !dusmanlar[j].aktif) {
            dusmanlar.splice(j, 1);
          }
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

        // Görünür alandaki düşmanları çiz
        var ekranX = d.x - state.kameraX;
        if (ekranX < -50 || ekranX > state.canvasGenislik + 50) continue;

        // Gölge
        ctx.save();
        ctx.fillStyle = "rgba(0,0,0,0.2)";
        ctx.beginPath();
        ctx.ellipse(
          ekranX + d.genislik / 2,
          state.zeminY - 1,
          d.genislik / 2,
          3, 0, 0, Math.PI * 2
        );
        ctx.fill();
        ctx.restore();

        // Sprite çiz
        dusmanSpriteCiz(ctx, d);

        // Sağlık çubuğu
        canBarCiz(ctx, d);

        // Jammer alan göstergesi
        if (d.tip === "jammer") {
          ctx.save();
          ctx.globalAlpha = 0.1 + Math.sin(d.animKare * 0.05) * 0.05;
          ctx.strokeStyle = BY.config.DUSMAN_RENKLERI.jammer.ana;
          ctx.lineWidth = 1;
          ctx.beginPath();
          ctx.arc(ekranX + d.genislik / 2, d.y + d.yukseklik / 2, 100, 0, Math.PI * 2);
          ctx.stroke();
          ctx.restore();
        }

        // Boss özel efektleri
        if (d.tip === "boss") {
          ctx.save();
          ctx.globalAlpha = 0.15;
          ctx.fillStyle = BY.config.DUSMAN_RENKLERI.boss.ana;
          ctx.shadowColor = BY.config.DUSMAN_RENKLERI.boss.ana;
          ctx.shadowBlur = 10;
          ctx.beginPath();
          ctx.arc(ekranX + d.genislik / 2, d.y + d.yukseklik / 2, d.genislik, 0, Math.PI * 2);
          ctx.fill();
          ctx.restore();
        }
      }

      // Mermileri çiz
      mermileriCiz(ctx);
    },

    hasarVer: function(dusman, miktar) {
      if (!dusman) return;
      dusman.can -= miktar;

      // Hasar efekti
      if (BY.efektler && BY.efektler.hasarEfektiOlustur) {
        BY.efektler.hasarEfektiOlustur(
          dusman.x + dusman.genislik / 2,
          dusman.y,
          "#FF4444"
        );
      }

      // Hasar parçacıkları
      if (BY.efektler && BY.efektler.parcacikOlustur) {
        BY.efektler.parcacikOlustur(
          dusman.x + dusman.genislik / 2,
          dusman.y + dusman.yukseklik / 2,
          dusman.renkHaritasi[1] || "#FF0000",
          "kivilcim", 3
        );
      }
    },

    bossBaşlat: function(bossVeri) {
      if (!bossVeri) return;
      var boss = dusmanOlustur(bossVeri.x, "boss");
      BY.state.dusmanlar.push(boss);
    },

    boyutGuncelle: function() {
      // Düşman Y pozisyonlarını yeni zemin seviyesine göre güncelle
      var state = BY.state;
      for (var i = 0; i < state.dusmanlar.length; i++) {
        var d = state.dusmanlar[i];
        if (d && !DUSMAN_TIPLERI[d.tip].ucan) {
          d.y = state.zeminY - d.yukseklik;
        }
      }
    }
  };

  // ── Mermileri çiz (yardımcı) ──────────────────────────────────────────────
  function mermileriCiz(ctx) {
    var state = BY.state;
    var mermiler = state.mermiler;
    if (!mermiler) return;

    for (var i = 0; i < mermiler.length; i++) {
      var m = mermiler[i];
      var ekranX = m.x - state.kameraX;

      if (ekranX < -10 || ekranX > state.canvasGenislik + 10) continue;

      ctx.save();
      ctx.fillStyle = m.renk || "#FF0000";
      ctx.shadowColor = m.renk || "#FF0000";
      ctx.shadowBlur = 4;
      ctx.fillRect(Math.floor(ekranX) - 2, Math.floor(m.y) - 2, 4, 4);
      ctx.restore();
    }
  }

})();
