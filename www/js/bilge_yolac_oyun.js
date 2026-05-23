// www/js/bilge_yolac_oyun.js
// Oyun akışı: klavye odaklı takım hareketi, zıplama, inme/etkileşim, takım
// atılması, otomatik hedefli temel atış, boss tetikleme ve seviye geçişi.

(function() {
  "use strict";

  var BY = window.BilgeYolac;
  if (!BY) return;

  // KRİTİK: Otomatik ateş kaldırıldı. Kullanıcı BOŞLUK (ATEŞ) veya fare
  // tıklamasıyla açıkça tetiklediğinde takım ateş eder. Bu, "ateş tuşuna
  // basmadığım halde sürekli ateş ediyorlar" şikayetini giderir.
  var atesBeklemeKaresi = 0;          // Atış arası minimum kare (ardarda tuş basışı koruması)
  var ATES_COOLDOWN_KARELERI = 12;    // ~5 atış/saniye üst sınırı
  var bossOlusturuldu = false;
  var zaferBekleme = 0;

  var FORMASYON = [-84, -42, 0, 42, 84];

  function takimMerkeziAl() {
    return BY.karakterler && BY.karakterler.takimMerkeziAl ? BY.karakterler.takimMerkeziAl() : null;
  }

  function hayattaOlanKarakterler() {
    var liste = [];
    var karakterler = BY.state.karakterler || [];
    for (var i = 0; i < karakterler.length; i++) {
      if (karakterler[i] && (karakterler[i].can === undefined || karakterler[i].can > 0)) {
        liste.push(karakterler[i]);
      }
    }
    return liste;
  }

  function girisSifirla() {
    var giris = BY.state.giris;
    giris.yukariTetik = false;
    giris.asagiTetik = false;
    giris.boslukTetik = false;
    giris.tikla = false;
  }

  function enYakinDusmanAl() {
    var state = BY.state;
    var merkez = takimMerkeziAl();
    var enYakin = null;
    var minMesafe = Infinity;
    if (!merkez || !state.dusmanlar) return null;

    for (var i = 0; i < state.dusmanlar.length; i++) {
      var d = state.dusmanlar[i];
      if (!d || !d.aktif || d.can <= 0) continue;
      var dx = d.x - merkez.x;
      var dy = d.y - merkez.y;
      var mesafe = Math.sqrt(dx * dx + dy * dy);
      if (mesafe < minMesafe) {
        minMesafe = mesafe;
        enYakin = d;
      }
    }
    return enYakin;
  }

  function karakterFormasyonunuKoru() {
    var state = BY.state;
    var karakterler = state.karakterler;
    if (!karakterler || karakterler.length === 0) return;

    var merkez = takimMerkeziAl();
    if (!merkez) return;

    // KRİTİK DÜZELTME: takimMerkeziAl() karakter merkezlerinin ortalamasını
    // döndürür (x + genislik/2). FORMASYON ofsetleri de merkez tabanlıdır.
    // Önceki kod hedef merkezi doğrudan k.x (sol kenar) ile karşılaştırıyordu;
    // bu da her karede sabit genislik/2 kadar fark oluşturup tüm takımı
    // sürekli sağa kaydırıyordu (kullanıcı hiçbir tuşa basmadan sağa akış).
    // Şimdi karakter merkezini hedef merkez ile karşılaştırıyoruz.
    for (var i = 0; i < karakterler.length; i++) {
      var k = karakterler[i];
      var hedefMerkezX = merkez.x + FORMASYON[i];
      var kMerkezX = k.x + k.genislik / 2;
      var fark = hedefMerkezX - kMerkezX;
      k.hizX += fark * 0.012;
    }
  }

  function takimKontroluUygula() {
    var state = BY.state;
    var giris = state.giris;
    var karakterler = hayattaOlanKarakterler();
    if (karakterler.length === 0) return;

    var hareket = 0;
    if (giris.sol && !giris.sag) hareket = -1;
    else if (giris.sag && !giris.sol) hareket = 1;

    if (hareket !== 0) state.takimYon = hareket;

    for (var i = 0; i < karakterler.length; i++) {
      var k = karakterler[i];
      k.yon = state.takimYon || k.yon || 1;

      if (hareket !== 0) {
        k.hizX += hareket * 0.42;
        if (Math.abs(k.hizX) > 3.4) k.hizX = 3.4 * hareket;
        if (!k.yetenekAktif) k.animasyonDurumu = "walk";
      } else if (!k.yetenekAktif && Math.abs(k.hizX) < 0.18) {
        k.animasyonDurumu = "idle";
      }
    }

    if (giris.yukariTetik) {
      for (var j = 0; j < karakterler.length; j++) {
        var kr = karakterler[j];
        var zeminde = !!kr.zemindeMi || Math.abs(kr.hizY || 0) < 0.05;
        if (zeminde) {
          kr.hizY = -7.0;
        }
      }
      if (BY.efektler && BY.efektler.parcacikOlustur) {
        var merkez = takimMerkeziAl();
        if (merkez) BY.efektler.parcacikOlustur(merkez.x, BY.state.zeminY, "#FFFFFF", "kivilcim", 7);
      }
    }

    if (giris.asagi) {
      for (var kx = 0; kx < karakterler.length; kx++) {
        karakterler[kx].hizY += 0.08;
      }
    }

    if (giris.asagiTetik) {
      var takimMerkezi = takimMerkeziAl();
      if (takimMerkezi && BY.efektler && BY.efektler.radarDarbesiEkle) {
        BY.efektler.radarDarbesiEkle(takimMerkezi.x, takimMerkezi.y, BY.state.temaRenk || "#FFFFFF");
      }
    }

    // BOŞLUK artık ATEŞ tuşudur (dash kaldırıldı). Sadece tetik olayında
    // ve cooldown sona erdiğinde takım ateş eder. Tuş basılı tutulursa
    // ATES_COOLDOWN_KARELERI sınırı içinde sürekli atış yapılabilir.
    if (giris.bosluk && atesBeklemeKaresi <= 0) {
      atesBeklemeKaresi = ATES_COOLDOWN_KARELERI;
      takimAtesEt();
    }

    karakterFormasyonunuKoru();
  }

  function takimAtesEt() {
    var state = BY.state;
    var hedef = enYakinDusmanAl();
    var karakterler = hayattaOlanKarakterler();
    if (karakterler.length === 0 || !BY.cephanelik) return;

    var hedefX = hedef ? hedef.x + hedef.genislik / 2 : (takimMerkeziAl().x + state.takimYon * 260);
    var hedefY = hedef ? hedef.y + hedef.yukseklik / 2 : (state.zeminY - 90);

    for (var i = 0; i < karakterler.length; i++) {
      var k = karakterler[i];
      var yayilma = (i - 2) * 0.03;
      BY.cephanelik.oyuncuAtisiOlustur(k, hedefX, hedefY, {
        yayilma: yayilma,
        hasar: undefined
      });
    }
  }

  function bossuTetikle() {
    var state = BY.state;
    if (state.oyunDurumu === "boss" || bossOlusturuldu) return;

    var veri = BY.seviye && BY.seviye.mevcutVeriAl ? BY.seviye.mevcutVeriAl() : null;
    if (!veri || !veri.bossSpawn) return;

    var merkez = takimMerkeziAl();
    if (!merkez) return;

    var normalDusmanSayisi = 0;
    for (var i = 0; i < state.dusmanlar.length; i++) {
      if (state.dusmanlar[i] && state.dusmanlar[i].aktif && state.dusmanlar[i].tip !== "boss" && state.dusmanlar[i].can > 0) {
        normalDusmanSayisi++;
      }
    }

    if (merkez.x >= veri.bossSpawn.x - 280 && normalDusmanSayisi <= 2) {
      bossOlusturuldu = true;
      state.oyunDurumu = "boss";
      if (BY.dusmanlar && BY.dusmanlar.bossBaşlat) BY.dusmanlar.bossBaşlat(veri.bossSpawn);
      if (BY.efektler && BY.efektler.radarDarbesiEkle) {
        BY.efektler.radarDarbesiEkle(veri.bossSpawn.x, state.zeminY * 0.55, "#FFD700");
      }
    }
  }

  function bossBittiMi() {
    var dusmanlar = BY.state.dusmanlar || [];
    for (var i = 0; i < dusmanlar.length; i++) {
      if (dusmanlar[i] && dusmanlar[i].aktif && dusmanlar[i].tip === "boss" && dusmanlar[i].can > 0) {
        return false;
      }
    }
    return true;
  }

  function seviyeCikisiniKontrolEt() {
    var state = BY.state;
    var cikis = BY.seviye && BY.seviye.cikisNoktasiAl ? BY.seviye.cikisNoktasiAl() : null;
    var merkez = takimMerkeziAl();
    if (!cikis || !merkez) return;

    if (state.oyunDurumu === "boss" && bossBittiMi()) {
      state.oyunDurumu = "oynuyor";
    }

    if (bossOlusturuldu && !bossBittiMi()) return;

    if (merkez.x >= cikis.x - 40) {
      state.oyunDurumu = "zafer";
      zaferBekleme++;
      if (zaferBekleme === 1 && BY.efektler && BY.efektler.zaferEfektiOlustur) {
        BY.efektler.zaferEfektiOlustur();
      }
      if (zaferBekleme > 120) {
        zaferBekleme = 0;
        bossOlusturuldu = false;
        if (state.mevcutSeviye >= (BY.seviye.seviyeSayisi() - 1)) {
          state.mevcutSeviye = 0;
        }
        BY.motor.gecisBaslat();
      }
    } else {
      zaferBekleme = 0;
    }
  }

  function takimYenildiMi() {
    return BY.state.takimCan <= 0;
  }

  function yenilgiyiIsle() {
    var state = BY.state;
    state.takimCan = state.takimMaxCan;
    state.mermiler = [];
    bossOlusturuldu = false;
    zaferBekleme = 0;
    state.oyunDurumu = "oynuyor";
    if (BY.seviye && BY.seviye.yukle) BY.seviye.yukle(state.mevcutSeviye);
  }

  BY.oyun = {
    baslat: function() {
      atesBeklemeKaresi = 0;
      bossOlusturuldu = false;
      zaferBekleme = 0;
    },

    oyunuBaslat: function() {
      var state = BY.state;
      state.skor = 0;
      state.takimCan = state.takimMaxCan;
      state.oyunDurumu = "oynuyor";
      state.kameraX = 0;
      bossOlusturuldu = false;
      zaferBekleme = 0;
      atesBeklemeKaresi = 0;

      if (BY.seviye && BY.seviye.yukle) BY.seviye.yukle(state.mevcutSeviye || 0);

      for (var i = 0; i < state.karakterler.length; i++) {
        state.karakterler[i].x = 60 + i * 42;
        state.karakterler[i].y = state.zeminY - state.karakterler[i].yukseklik;
        state.karakterler[i].hizX = 0;
        state.karakterler[i].hizY = 0;
        state.karakterler[i].yon = 1;
      }
    },

    skoreEkle: function(puan) {
      BY.state.skor += (puan || 0);
    },

    guncelle: function() {
      var state = BY.state;
      if (atesBeklemeKaresi > 0) atesBeklemeKaresi--;

      if (state.oyunDurumu !== "oynuyor" && state.oyunDurumu !== "boss" && state.oyunDurumu !== "zafer") {
        girisSifirla();
        return;
      }

      if (takimYenildiMi()) {
        yenilgiyiIsle();
        girisSifirla();
        return;
      }

      if (state.oyunDurumu === "zafer") {
        seviyeCikisiniKontrolEt();
        girisSifirla();
        return;
      }

      // takimKontroluUygula içinde BOŞLUK basılı/tetiklenmişse takim ateş eder.
      // Otomatik (kullanıcı tuşa basmadan) ateş yoktur.
      takimKontroluUygula();

      bossuTetikle();
      seviyeCikisiniKontrolEt();
      girisSifirla();
    }
  };

})();