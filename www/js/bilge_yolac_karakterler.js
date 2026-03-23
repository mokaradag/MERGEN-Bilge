// www/js/bilge_yolac_karakterler.js
// Karakter sistemi: 16x16 piksel sprite verileri, renkler, AI davranış durumu, yetenekler

(function() {
  "use strict";

  var BY = window.BilgeYolac;
  if (!BY) return;

  // Renk kodları: 0=boş, 1=ana, 2=koyu, 3=açık, 4=ten, 5=sakal/saç, 6=aksesuarRenk, 7=silahRenk
  // Her karakter için idle, walk ve attack kareleri tanımlanıyor

  var SPRITE_VERILERI = {

    // MERGEN (Mor) - Okçu savaşçı, miğferli, yay ve ok
    mergen: {
      renkler: {
        1: "#7C4DFF", 2: "#5B2FCF", 3: "#A47DFF",
        4: "#D4A574", 5: "#2C2C2C", 6: "#8C8C9C",
        7: "#8B6914"
      },
      idle: [
        [0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0],
        [0,0,0,0,0,1,6,6,6,1,0,0,0,0,0,0],
        [0,0,0,0,0,1,6,3,6,1,0,0,0,0,0,0],
        [0,0,0,0,1,4,4,4,4,4,1,0,0,0,0,0],
        [0,0,0,0,1,4,5,4,5,4,1,0,0,0,0,0],
        [0,0,0,0,0,4,4,4,4,4,0,0,0,0,0,0],
        [0,0,0,0,0,0,4,5,4,0,0,0,0,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,1,2,1,1,1,1,1,2,1,0,0,0,0],
        [0,0,7,1,2,1,1,1,1,1,2,1,7,0,0,0],
        [0,0,7,0,1,1,1,1,1,1,1,0,7,0,0,0],
        [0,0,7,0,0,1,2,1,2,1,0,0,7,0,0,0],
        [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
        [0,0,0,0,0,2,1,0,1,2,0,0,0,0,0,0],
        [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
        [0,0,0,0,0,2,2,0,2,2,0,0,0,0,0,0]
      ],
      walk: [
        [0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0],
        [0,0,0,0,0,1,6,6,6,1,0,0,0,0,0,0],
        [0,0,0,0,0,1,6,3,6,1,0,0,0,0,0,0],
        [0,0,0,0,1,4,4,4,4,4,1,0,0,0,0,0],
        [0,0,0,0,1,4,5,4,5,4,1,0,0,0,0,0],
        [0,0,0,0,0,4,4,4,4,4,0,0,0,0,0,0],
        [0,0,0,0,0,0,4,5,4,0,0,0,0,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,1,2,1,1,1,1,1,2,1,0,0,0,0],
        [0,0,7,1,2,1,1,1,1,1,2,1,7,0,0,0],
        [0,0,7,0,1,1,1,1,1,1,1,0,7,0,0,0],
        [0,0,7,0,0,1,2,1,2,1,0,0,0,0,0,0],
        [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
        [0,0,0,0,1,2,0,0,0,2,1,0,0,0,0,0],
        [0,0,0,0,2,1,0,0,0,1,2,0,0,0,0,0],
        [0,0,0,0,2,2,0,0,0,2,2,0,0,0,0,0]
      ]
    },

    // ÜLGEN (Mavi) - Gök hâkimi, geyik boynuzlu taç, cüppeli kral
    ulgen: {
      renkler: {
        1: "#2F6DF6", 2: "#1A4DC0", 3: "#6B9BFF",
        4: "#D4A574", 5: "#B0B0B0", 6: "#DAA520",
        7: "#C8A84E"
      },
      idle: [
        [0,0,0,6,0,0,0,0,0,0,0,6,0,0,0,0],
        [0,0,6,0,6,0,0,6,0,0,6,0,6,0,0,0],
        [0,0,6,0,0,6,6,6,6,6,0,0,6,0,0,0],
        [0,0,0,0,0,6,6,3,6,6,0,0,0,0,0,0],
        [0,0,0,0,4,4,4,4,4,4,4,0,0,0,0,0],
        [0,0,0,0,4,5,4,4,4,5,4,0,0,0,0,0],
        [0,0,0,0,0,4,4,4,4,4,0,0,0,0,0,0],
        [0,0,0,0,0,0,5,5,5,0,0,0,0,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,1,2,1,6,1,6,1,2,1,0,0,0,0],
        [0,0,0,1,2,1,1,1,1,1,2,1,0,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
        [0,0,0,0,0,2,1,0,1,2,0,0,0,0,0,0],
        [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
        [0,0,0,0,0,2,2,0,2,2,0,0,0,0,0,0]
      ],
      walk: [
        [0,0,0,6,0,0,0,0,0,0,0,6,0,0,0,0],
        [0,0,6,0,6,0,0,6,0,0,6,0,6,0,0,0],
        [0,0,6,0,0,6,6,6,6,6,0,0,6,0,0,0],
        [0,0,0,0,0,6,6,3,6,6,0,0,0,0,0,0],
        [0,0,0,0,4,4,4,4,4,4,4,0,0,0,0,0],
        [0,0,0,0,4,5,4,4,4,5,4,0,0,0,0,0],
        [0,0,0,0,0,4,4,4,4,4,0,0,0,0,0,0],
        [0,0,0,0,0,0,5,5,5,0,0,0,0,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,1,2,1,6,1,6,1,2,1,0,0,0,0],
        [0,0,0,1,2,1,1,1,1,1,2,1,0,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
        [0,0,0,0,1,2,0,0,0,2,1,0,0,0,0,0],
        [0,0,0,0,2,1,0,0,0,1,2,0,0,0,0,0],
        [0,0,0,0,2,2,0,0,0,2,2,0,0,0,0,0]
      ]
    },

    // KAYRA (Yeşil) - Bilge ihtiyar, asalı, parlayan küre
    kayra: {
      renkler: {
        1: "#2ECC71", 2: "#1A9C54", 3: "#6EE89B",
        4: "#D4A574", 5: "#E0E0E0", 6: "#8B6914",
        7: "#4AFFA0"
      },
      idle: [
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,5,5,5,0,0,0,0,0,0,0],
        [0,0,0,0,0,5,5,5,5,5,0,0,0,0,0,0],
        [0,0,0,0,4,4,4,4,4,4,4,0,0,0,0,0],
        [0,0,0,0,4,5,4,4,4,5,4,0,0,0,0,0],
        [0,0,0,0,0,4,4,4,4,4,0,0,0,0,0,0],
        [0,0,0,0,0,5,5,5,5,5,0,0,0,0,0,0],
        [0,0,0,0,0,0,5,5,5,0,0,0,0,0,0,0],
        [0,0,6,0,1,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,6,1,2,1,1,1,1,1,2,1,0,7,0,0],
        [0,0,6,1,2,1,1,1,1,1,2,1,0,7,0,0],
        [0,0,6,0,1,1,1,1,1,1,1,0,7,7,7,0],
        [0,0,6,0,0,1,2,1,2,1,0,0,0,7,0,0],
        [0,0,0,0,0,2,1,0,1,2,0,0,0,0,0,0],
        [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
        [0,0,0,0,0,2,2,0,2,2,0,0,0,0,0,0]
      ],
      walk: [
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,5,5,5,0,0,0,0,0,0,0],
        [0,0,0,0,0,5,5,5,5,5,0,0,0,0,0,0],
        [0,0,0,0,4,4,4,4,4,4,4,0,0,0,0,0],
        [0,0,0,0,4,5,4,4,4,5,4,0,0,0,0,0],
        [0,0,0,0,0,4,4,4,4,4,0,0,0,0,0,0],
        [0,0,0,0,0,5,5,5,5,5,0,0,0,0,0,0],
        [0,0,0,0,0,0,5,5,5,0,0,0,0,0,0,0],
        [0,0,6,0,1,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,6,1,2,1,1,1,1,1,2,1,0,7,0,0],
        [0,0,6,1,2,1,1,1,1,1,2,1,0,7,0,0],
        [0,0,6,0,1,1,1,1,1,1,1,0,7,7,7,0],
        [0,0,6,0,0,1,2,1,2,1,0,0,0,7,0,0],
        [0,0,0,0,1,2,0,0,0,2,1,0,0,0,0,0],
        [0,0,0,0,2,1,0,0,0,1,2,0,0,0,0,0],
        [0,0,0,0,2,2,0,0,0,2,2,0,0,0,0,0]
      ]
    },

    // ERLİK (Kırmızı) - Taçlı kral, asalı, tehditkâr
    erlik: {
      renkler: {
        1: "#E74C3C", 2: "#B53A2E", 3: "#F08070",
        4: "#D4A574", 5: "#E0E0E0", 6: "#DAA520",
        7: "#8B6914"
      },
      idle: [
        [0,0,0,0,0,6,0,6,0,6,0,0,0,0,0,0],
        [0,0,0,0,0,6,6,6,6,6,0,0,0,0,0,0],
        [0,0,0,0,0,6,6,3,6,6,0,0,0,0,0,0],
        [0,0,0,0,4,4,4,4,4,4,4,0,0,0,0,0],
        [0,0,0,0,4,5,4,4,4,5,4,0,0,0,0,0],
        [0,0,0,0,0,4,4,4,4,4,0,0,0,0,0,0],
        [0,0,0,0,0,5,5,5,5,5,0,0,0,0,0,0],
        [0,0,0,0,0,0,5,5,5,0,0,0,0,0,0,0],
        [0,0,7,0,1,1,1,6,1,1,1,0,0,0,0,0],
        [0,0,7,1,2,1,1,1,1,1,2,1,0,0,0,0],
        [0,0,7,1,2,1,1,1,1,1,2,1,0,0,0,0],
        [0,0,7,0,1,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,7,0,0,1,2,1,2,1,0,0,0,0,0,0],
        [0,0,0,0,0,2,1,0,1,2,0,0,0,0,0,0],
        [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
        [0,0,0,0,0,2,2,0,2,2,0,0,0,0,0,0]
      ],
      walk: [
        [0,0,0,0,0,6,0,6,0,6,0,0,0,0,0,0],
        [0,0,0,0,0,6,6,6,6,6,0,0,0,0,0,0],
        [0,0,0,0,0,6,6,3,6,6,0,0,0,0,0,0],
        [0,0,0,0,4,4,4,4,4,4,4,0,0,0,0,0],
        [0,0,0,0,4,5,4,4,4,5,4,0,0,0,0,0],
        [0,0,0,0,0,4,4,4,4,4,0,0,0,0,0,0],
        [0,0,0,0,0,5,5,5,5,5,0,0,0,0,0,0],
        [0,0,0,0,0,0,5,5,5,0,0,0,0,0,0,0],
        [0,0,7,0,1,1,1,6,1,1,1,0,0,0,0,0],
        [0,0,7,1,2,1,1,1,1,1,2,1,0,0,0,0],
        [0,0,7,1,2,1,1,1,1,1,2,1,0,0,0,0],
        [0,0,7,0,1,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,7,0,0,1,2,1,2,1,0,0,0,0,0,0],
        [0,0,0,0,1,2,0,0,0,2,1,0,0,0,0,0],
        [0,0,0,0,2,1,0,0,0,1,2,0,0,0,0,0],
        [0,0,0,0,2,2,0,0,0,2,2,0,0,0,0,0]
      ]
    },

    // UMAY ANA (Pembe) - Koruyucu ana, başlıklı, kucağında bebek
    umay_ana: {
      renkler: {
        1: "#E98686", 2: "#C05F5F", 3: "#F5ABAB",
        4: "#D4A574", 5: "#C08050", 6: "#DAA520",
        7: "#F0E0D0"
      },
      idle: [
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,1,3,3,3,1,0,0,0,0,0,0],
        [0,0,0,0,1,6,1,1,1,6,1,0,0,0,0,0],
        [0,0,0,0,4,4,4,4,4,4,4,0,0,0,0,0],
        [0,0,0,0,4,5,4,4,4,5,4,0,0,0,0,0],
        [0,0,0,0,0,4,4,3,4,4,0,0,0,0,0,0],
        [0,0,0,0,0,0,4,4,4,0,0,0,0,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,1,2,1,6,1,6,1,2,1,0,0,0,0],
        [0,0,0,1,2,1,1,1,1,1,2,1,0,0,0,0],
        [0,0,0,1,1,1,7,7,7,1,1,1,0,0,0,0],
        [0,0,0,0,1,1,7,4,7,1,1,0,0,0,0,0],
        [0,0,0,0,0,1,7,7,7,1,0,0,0,0,0,0],
        [0,0,0,0,0,2,1,0,1,2,0,0,0,0,0,0],
        [0,0,0,0,0,1,2,0,2,1,0,0,0,0,0,0],
        [0,0,0,0,0,2,2,0,2,2,0,0,0,0,0,0]
      ],
      walk: [
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,1,3,3,3,1,0,0,0,0,0,0],
        [0,0,0,0,1,6,1,1,1,6,1,0,0,0,0,0],
        [0,0,0,0,4,4,4,4,4,4,4,0,0,0,0,0],
        [0,0,0,0,4,5,4,4,4,5,4,0,0,0,0,0],
        [0,0,0,0,0,4,4,3,4,4,0,0,0,0,0,0],
        [0,0,0,0,0,0,4,4,4,0,0,0,0,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,1,2,1,6,1,6,1,2,1,0,0,0,0],
        [0,0,0,1,2,1,1,1,1,1,2,1,0,0,0,0],
        [0,0,0,1,1,1,7,7,7,1,1,1,0,0,0,0],
        [0,0,0,0,1,1,7,4,7,1,1,0,0,0,0,0],
        [0,0,0,0,0,1,7,7,7,1,0,0,0,0,0,0],
        [0,0,0,0,1,2,0,0,0,2,1,0,0,0,0,0],
        [0,0,0,0,2,1,0,0,0,1,2,0,0,0,0,0],
        [0,0,0,0,2,2,0,0,0,2,2,0,0,0,0,0]
      ]
    }
  };

  // Karakter isimleri ve yetenek tanımları
  var KARAKTER_BILGILERI = {
    mergen:   { isim: "MERGEN",   yetenek: "ok_atisi",     yetenekSuresi: 90, aciklama: "Okçu" },
    ulgen:    { isim: "ÜLGEN",    yetenek: "gok_dalgasi",  yetenekSuresi: 80, aciklama: "Gök Hakimi" },
    kayra:    { isim: "KAYRA",    yetenek: "kure_olustur", yetenekSuresi: 100, aciklama: "Yaratıcı" },
    erlik:    { isim: "ERLİK",    yetenek: "kaos_saldiri", yetenekSuresi: 85, aciklama: "Kaos Gücü" },
    umay_ana: { isim: "UMAY ANA", yetenek: "kalkan_kur",   yetenekSuresi: 95, aciklama: "Koruyucu" }
  };

  // Animasyon durumları
  var ANIMASYON_DURUMLARI = [
    "idle", "walk", "hover", "ability_prep",
    "ability_exec", "ability_recovery",
    "team_sync", "env_reaction", "victory"
  ];

  // Karakter nesnesi oluştur
  function karakterOlustur(id, siraIndex) {
    var state = BY.state;
    var config = BY.config;
    var renkler = config.KARAKTER_RENKLERI[id];
    var bilgi = KARAKTER_BILGILERI[id];
    var sprite = SPRITE_VERILERI[id];

    var aralik = state.canvasGenislik / 6;
    var baslangicX = aralik * (siraIndex + 1);

    return {
      id: id,
      isim: bilgi.isim,
      x: baslangicX,
      y: state.zeminY - 48,
      hizX: 0,
      hizY: 0,
      yon: 1,  // 1=sağ, -1=sol
      genislik: 16 * config.PIKSEL_BOYUT,
      yukseklik: 16 * config.PIKSEL_BOYUT,
      renkler: renkler,
      spriteRenkler: sprite.renkler,
      idleSprite: sprite.idle,
      walkSprite: sprite.walk,
      animasyonDurumu: "idle",
      animasyonKare: 0,
      animasyonZamanlayici: 0,
      yetenekZamanlayici: 0,
      yetenekAktif: false,
      yetenekTuru: bilgi.yetenek,
      yetenekSuresi: bilgi.yetenekSuresi,
      hoverAktif: false,
      gozKirpma: 0,
      nefesOfset: 0,
      auraAci: 0,
      takimSenkron: false,
      zaferAktif: false,
      hedefX: baslangicX,
      hareketBekleme: 0,
      platformY: 0
    };
  }

  // Sprite çizim fonksiyonu
  function spriteCiz(ctx, sprite, renkHaritasi, x, y, pikselBoyut, yon, parlama) {
    if (!sprite || !ctx) return;

    ctx.save();

    // Parlama efekti
    if (parlama && parlama > 0) {
      ctx.shadowColor = renkHaritasi[1] || "#FFF";
      ctx.shadowBlur = parlama;
    }

    var genislik = sprite[0].length;
    var yukseklik = sprite.length;
    var cizimX = yon < 0 ? x + genislik * pikselBoyut : x;

    if (yon < 0) {
      ctx.translate(cizimX, 0);
      ctx.scale(-1, 0);
      ctx.translate(-cizimX, 0);
    }

    for (var satir = 0; satir < yukseklik; satir++) {
      for (var sutun = 0; sutun < genislik; sutun++) {
        var deger = sprite[satir][sutun];
        if (deger === 0) continue;

        var renk = renkHaritasi[deger];
        if (!renk) continue;

        ctx.fillStyle = renk;
        ctx.fillRect(
          Math.floor(x + sutun * pikselBoyut),
          Math.floor(y + satir * pikselBoyut),
          pikselBoyut,
          pikselBoyut
        );
      }
    }

    ctx.restore();
  }

  // Karakter güncelleme
  function karakterGuncelle(karakter, zaman) {
    var state = BY.state;
    var config = BY.config;

    // Nefes animasyonu
    karakter.nefesOfset = Math.sin(zaman * 0.003 + karakter.x * 0.01) * 1.5;

    // Göz kırpma
    karakter.gozKirpma = (karakter.gozKirpma + 1) % 200;

    // Aura dönüşü
    karakter.auraAci = (karakter.auraAci + 0.02) % (Math.PI * 2);

    // Animasyon kare değişimi
    karakter.animasyonZamanlayici++;
    if (karakter.animasyonZamanlayici > 15) {
      karakter.animasyonZamanlayici = 0;
      karakter.animasyonKare = (karakter.animasyonKare + 1) % 2;
    }

    // Yetenek zamanlayıcısı
    if (karakter.yetenekAktif) {
      karakter.yetenekZamanlayici--;
      if (karakter.yetenekZamanlayici <= 0) {
        karakter.yetenekAktif = false;
        karakter.animasyonDurumu = "idle";
      }
    }

    // Fizik
    karakter.hizY += config.YERCEKIM;
    karakter.hizX *= config.SURTUNME;
    karakter.x += karakter.hizX;
    karakter.y += karakter.hizY;

    // Zemin çarpışma
    var zeminSiniri = state.zeminY - karakter.yukseklik;
    if (karakter.y > zeminSiniri) {
      karakter.y = zeminSiniri;
      karakter.hizY = 0;
    }

    // Ekran sınırları
    var solSinir = 20;
    var sagSinir = state.canvasGenislik - karakter.genislik - 20;
    if (karakter.x < solSinir) {
      karakter.x = solSinir;
      karakter.hizX = Math.abs(karakter.hizX) * 0.5;
      karakter.yon = 1;
    }
    if (karakter.x > sagSinir) {
      karakter.x = sagSinir;
      karakter.hizX = -Math.abs(karakter.hizX) * 0.5;
      karakter.yon = -1;
    }

    // Hareket AI (idle durumda)
    if (karakter.animasyonDurumu === "idle" || karakter.animasyonDurumu === "walk") {
      karakter.hareketBekleme--;
      if (karakter.hareketBekleme <= 0) {
        // Yeni hedef seç
        var hedefMerkez = state.canvasGenislik / 2;
        karakter.hedefX = hedefMerkez + (Math.random() - 0.5) * state.canvasGenislik * 0.6;
        karakter.hareketBekleme = 60 + Math.random() * 180;
      }

      var fark = karakter.hedefX - karakter.x;
      if (Math.abs(fark) > 10) {
        karakter.hizX += (fark > 0 ? 0.15 : -0.15);
        karakter.yon = fark > 0 ? 1 : -1;
        karakter.animasyonDurumu = "walk";
      } else {
        karakter.animasyonDurumu = "idle";
      }
    }
  }

  // Karakter çizim
  function karakterCiz(ctx, karakter) {
    var config = BY.config;
    var piksel = config.PIKSEL_BOYUT;

    // Gölge
    ctx.save();
    ctx.fillStyle = "rgba(0,0,0,0.3)";
    ctx.beginPath();
    ctx.ellipse(
      karakter.x + karakter.genislik / 2,
      BY.state.zeminY - 2,
      karakter.genislik / 2.5,
      4,
      0, 0, Math.PI * 2
    );
    ctx.fill();
    ctx.restore();

    // Aura halesi
    var auraYogunluk = karakter.hoverAktif ? 12 : (karakter.yetenekAktif ? 15 : 5);
    ctx.save();
    ctx.beginPath();
    var auraMerkezX = karakter.x + karakter.genislik / 2;
    var auraMerkezY = karakter.y + karakter.yukseklik * 0.3;
    var auraYaricap = karakter.genislik * 0.7 + Math.sin(karakter.auraAci) * 3;
    var auraGradyan = ctx.createRadialGradient(
      auraMerkezX, auraMerkezY, 0,
      auraMerkezX, auraMerkezY, auraYaricap
    );
    auraGradyan.addColorStop(0, karakter.renkler.parlama.replace("0.3", "0." + Math.floor(auraYogunluk / 5)));
    auraGradyan.addColorStop(1, "rgba(0,0,0,0)");
    ctx.fillStyle = auraGradyan;
    ctx.arc(auraMerkezX, auraMerkezY, auraYaricap, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();

    // Sprite
    var mevcutSprite;
    if (karakter.animasyonDurumu === "walk" && karakter.animasyonKare === 1) {
      mevcutSprite = karakter.walkSprite;
    } else {
      mevcutSprite = karakter.idleSprite;
    }

    var cizimY = karakter.y + karakter.nefesOfset;
    var parlamaGuc = karakter.hoverAktif ? 10 : (karakter.yetenekAktif ? 15 : 0);

    spriteCiz(ctx, mevcutSprite, karakter.spriteRenkler, karakter.x, cizimY, piksel, karakter.yon, parlamaGuc);

    // İsim etiketi
    ctx.save();
    ctx.font = "bold 9px monospace";
    ctx.textAlign = "center";
    ctx.fillStyle = karakter.renkler.acik;
    ctx.shadowColor = "rgba(0,0,0,0.8)";
    ctx.shadowBlur = 3;
    ctx.fillText(karakter.isim, karakter.x + karakter.genislik / 2, karakter.y - 8);
    ctx.restore();

    // Platform parlama
    if (karakter.hoverAktif || karakter.yetenekAktif) {
      ctx.save();
      ctx.strokeStyle = karakter.renkler.ana;
      ctx.lineWidth = 2;
      ctx.shadowColor = karakter.renkler.ana;
      ctx.shadowBlur = 8;
      ctx.beginPath();
      ctx.moveTo(karakter.x, BY.state.zeminY);
      ctx.lineTo(karakter.x + karakter.genislik, BY.state.zeminY);
      ctx.stroke();
      ctx.restore();
    }
  }

  // Yetenek çalıştır
  function yetenekCalistir(karakter) {
    if (karakter.yetenekAktif) return;
    karakter.yetenekAktif = true;
    karakter.yetenekZamanlayici = karakter.yetenekSuresi;
    karakter.animasyonDurumu = "ability_exec";

    // Efekt sistemi ile yetenek efekti oluştur
    if (BY.efektler && BY.efektler.yetenekEfektiOlustur) {
      BY.efektler.yetenekEfektiOlustur(karakter);
    }
  }

  // Dış arayüz
  BY.karakterler = {
    SPRITE_VERILERI: SPRITE_VERILERI,
    KARAKTER_BILGILERI: KARAKTER_BILGILERI,

    baslat: function() {
      var state = BY.state;
      state.karakterler = [];
      var ids = ["mergen", "ulgen", "kayra", "erlik", "umay_ana"];
      for (var i = 0; i < ids.length; i++) {
        state.karakterler.push(karakterOlustur(ids[i], i));
      }
    },

    guncelle: function(zaman) {
      var karakterler = BY.state.karakterler;
      for (var i = 0; i < karakterler.length; i++) {
        karakterGuncelle(karakterler[i], zaman);
      }

      // Karakter-karakter çarpışması
      for (var a = 0; a < karakterler.length; a++) {
        for (var b = a + 1; b < karakterler.length; b++) {
          var ka = karakterler[a];
          var kb = karakterler[b];
          var mesafe = Math.abs(ka.x - kb.x);
          var minMesafe = ka.genislik * 0.8;
          if (mesafe < minMesafe) {
            var itme = (minMesafe - mesafe) * 0.1;
            if (ka.x < kb.x) {
              ka.hizX -= itme;
              kb.hizX += itme;
            } else {
              ka.hizX += itme;
              kb.hizX -= itme;
            }
          }
        }
      }
    },

    ciz: function(ctx) {
      var karakterler = BY.state.karakterler;
      for (var i = 0; i < karakterler.length; i++) {
        karakterCiz(ctx, karakterler[i]);
      }
    },

    boyutGuncelle: function() {
      var state = BY.state;
      var karakterler = state.karakterler;
      var aralik = state.canvasGenislik / 6;
      for (var i = 0; i < karakterler.length; i++) {
        karakterler[i].hedefX = aralik * (i + 1);
      }
    },

    yetenekCalistir: yetenekCalistir,
    spriteCiz: spriteCiz,
    karakterOlustur: karakterOlustur
  };

})();