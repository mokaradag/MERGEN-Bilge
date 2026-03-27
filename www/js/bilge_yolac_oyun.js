// www/js/bilge_yolac_oyun.js
// Ana oyun mantığı: platformer ilerleme, düşman çarpışmaları, seviye tamamlama, skor sistemi, takım yönetimi

(function() {
  "use strict";

  var BY = window.BilgeYolac;
  if (!BY) return;

  // ── Oyun sabitleri ──────────────────────────────────────────────────────────
  var TAKIM_HIZI = 1.2;              // Takımın ileri yürüme hızı (piksel/kare)
  var DUSMAN_ALGILAMA_MESAFESI = 250; // Düşman algılama mesafesi (piksel)
  var BOSS_ALGILAMA_MESAFESI = 400;   // Boss alanına giriş mesafesi
  var ZAFER_SURESI = 3000;            // Zafer gösterimi süresi (ms)
  var MERMI_TAKIM_HASARI = 8;         // Düşman mermisi takım hasarı
  var TAKIM_VURUŞ_ALANI = 80;         // Takım çarpışma yarıçapı (piksel)
  var OTOMATIK_SALDIRI_ARALIĞI = 100; // Otomatik saldırı kareleri arası
  var TAKIM_IYILESME_HIZI = 0.02;     // Her karede iyileşme miktarı
  var SEVIYE_TAMAMLAMA_BONUSU = 500;  // Seviye tamamlama bonus puanı

  // ── İç durum değişkenleri ───────────────────────────────────────────────────
  var zaferZamanlayici = 0;
  var bossOlusturuldu = false;
  var sonSaldiriKaresi = 0;
  var takimDurumu = "ilerleme";  // ilerleme | savas | boss | bekleme
  var oyunBasladi = false;

  // ── Takım ilerleme mantığı ──────────────────────────────────────────────────
  function takimIlerlemeGuncelle() {
    var state = BY.state;
    var karakterler = state.karakterler;
    if (karakterler.length === 0) return;

    // Yakında düşman var mı kontrol et
    var enYakinDusman = enYakinDusmaniAl();
    var dusmanYakinda = enYakinDusman && enYakinDusman.mesafe < DUSMAN_ALGILAMA_MESAFESI;

    // Boss alanına yaklaştık mı
    var cikis = BY.seviye ? BY.seviye.cikisNoktasiAl() : null;
    var bossSpawn = BY.seviye ? BY.seviye.bossSpawnAl() : null;
    var takimMerkez = BY.karakterler ? BY.karakterler.takimMerkeziAl() : { x: 0, y: 0 };

    // Boss alanına giriş
    if (bossSpawn && takimMerkez.x > bossSpawn.x - BOSS_ALGILAMA_MESAFESI && !bossOlusturuldu) {
      state.oyunDurumu = "boss";
      takimDurumu = "boss";
      bossOlusturuldu = true;

      // Boss düşmanını oluştur
      if (BY.dusmanlar && BY.dusmanlar.bossBaşlat) {
        BY.dusmanlar.bossBaşlat(bossSpawn);
      } else if (BY.dusmanlar && BY.dusmanlar.baslat) {
        // Boss yoksa normal düşman olarak ekle
        state.dusmanlar.push({
          tip: "boss",
          x: bossSpawn.x,
          y: state.zeminY - 48,
          hizX: 0, hizY: 0,
          genislik: 32, yukseklik: 32,
          can: 300, maxCan: 300,
          hasar: 15, aktif: true,
          durum: "patrol",
          saldiriZamanlayici: 0,
          animKare: 0, yonX: -1,
          pikseBoyut: BY.config.PIKSEL_BOYUT
        });
      }
      return;
    }

    // Düşman yakınsa savaş moduna geç
    if (dusmanYakinda) {
      takimDurumu = "savas";
      otomatikSaldiriKontrol();
    } else {
      takimDurumu = "ilerleme";
    }

    // İlerleme modundaysa takımı sağa doğru hareket ettir
    if (takimDurumu === "ilerleme") {
      for (var i = 0; i < karakterler.length; i++) {
        var k = karakterler[i];
        // Her karakter formatında hedef ata (sağa doğru)
        k.hedefX = takimMerkez.x + TAKIM_HIZI * 30 + i * 40;

        // Platformlara otomatik zıplama: önünde platform var mı?
        var onundePlatform = platformKontrol(k);
        if (onundePlatform && (k.zempimdeMi || k.hizY === 0)) {
          k.hizY = -6;
        }
      }
    }
  }

  // ── Çıkış noktası kontrolü ──────────────────────────────────────────────────
  function cikisKontrol() {
    var state = BY.state;
    var cikis = BY.seviye ? BY.seviye.cikisNoktasiAl() : null;
    if (!cikis) return;

    var takimMerkez = BY.karakterler ? BY.karakterler.takimMerkeziAl() : null;
    if (!takimMerkez) return;

    // Çıkış noktasına ulaşıldı mı?
    if (takimMerkez.x >= cikis.x) {
      seviyeTamamla();
    }
  }

  // ── Boss savaşı kontrolü ────────────────────────────────────────────────────
  function bossKontrol() {
    var state = BY.state;

    // Boss yenildi mi kontrol et
    var bossHayatta = false;
    for (var i = 0; i < state.dusmanlar.length; i++) {
      if (state.dusmanlar[i].tip === "boss" && state.dusmanlar[i].aktif && state.dusmanlar[i].can > 0) {
        bossHayatta = true;
        break;
      }
    }

    if (!bossHayatta && bossOlusturuldu) {
      // Boss yenildi - zafer!
      state.oyunDurumu = "zafer";
      zaferZamanlayici = performance.now();

      // Zafer efektleri
      if (BY.efektler && BY.efektler.zaferEfektiOlustur) {
        BY.efektler.zaferEfektiOlustur();
      }
    }

    // Boss savaşında da otomatik saldırı
    otomatikSaldiriKontrol();
  }

  // ── Mermi çarpışma kontrolü ─────────────────────────────────────────────────
  function mermiCarpismaKontrol() {
    var state = BY.state;
    var mermiler = state.mermiler;
    if (!mermiler) return;

    var takimMerkez = BY.karakterler ? BY.karakterler.takimMerkeziAl() : null;

    for (var i = mermiler.length - 1; i >= 0; i--) {
      var m = mermiler[i];
      if (!m) continue;

      if (m.sahip === "takim") {
        // Takım mermisi → düşmanlara çarpma
        for (var d = 0; d < state.dusmanlar.length; d++) {
          var dusman = state.dusmanlar[d];
          if (!dusman || !dusman.aktif || dusman.can <= 0) continue;

          // Mermi düşmana değdi mi?
          if (BY.fizik && BY.fizik.kutucukCarpisma) {
            var carpisti = BY.fizik.kutucukCarpisma(
              { x: m.x, y: m.y, genislik: 4, yukseklik: 4 },
              dusman
            );
            if (carpisti) {
              // Düşmana hasar ver
              if (BY.dusmanlar && BY.dusmanlar.hasarVer) {
                BY.dusmanlar.hasarVer(dusman, m.hasar || 10);
              } else {
                dusman.can -= (m.hasar || 10);
              }
              // Mermii kaldır
              mermiler.splice(i, 1);
              break;
            }
          }
        }
      } else if (m.sahip === "dusman" && takimMerkez) {
        // Düşman mermisi → takıma çarpma
        var mesafeX = Math.abs(m.x - takimMerkez.x);
        var mesafeY = Math.abs(m.y - takimMerkez.y);

        if (mesafeX < TAKIM_VURUŞ_ALANI && mesafeY < TAKIM_VURUŞ_ALANI * 0.6) {
          // Takıma hasar ver
          if (BY.karakterler && BY.karakterler.takimHasarAl) {
            BY.karakterler.takimHasarAl(m.hasar || MERMI_TAKIM_HASARI);
          } else {
            state.takimCan = Math.max(0, state.takimCan - (m.hasar || MERMI_TAKIM_HASARI));
          }
          mermiler.splice(i, 1);
        }
      }
    }
  }

  // ── Otomatik saldırı sistemi ────────────────────────────────────────────────
  function otomatikSaldiriKontrol() {
    var state = BY.state;
    if (state.kare - sonSaldiriKaresi < OTOMATIK_SALDIRI_ARALIĞI) return;

    var enYakin = enYakinDusmaniAl();
    if (!enYakin) return;

    sonSaldiriKaresi = state.kare;

    // Rastgele bir karakter saldırı yapsın
    var karakterler = state.karakterler;
    if (karakterler.length === 0) return;
    var saldiran = karakterler[Math.floor(Math.random() * karakterler.length)];

    if (BY.karakterler && BY.karakterler.yetenekCalistir) {
      BY.karakterler.yetenekCalistir(saldiran);
    }
  }

  // ── En yakın düşmanı bul ────────────────────────────────────────────────────
  function enYakinDusmaniAl() {
    var state = BY.state;
    var takimMerkez = BY.karakterler ? BY.karakterler.takimMerkeziAl() : null;
    if (!takimMerkez) return null;

    var enYakin = null;
    var enYakinMesafe = Infinity;

    for (var i = 0; i < state.dusmanlar.length; i++) {
      var d = state.dusmanlar[i];
      if (!d || !d.aktif || d.can <= 0) continue;

      var mesafe = Math.abs(d.x - takimMerkez.x);
      if (mesafe < enYakinMesafe) {
        enYakinMesafe = mesafe;
        enYakin = { dusman: d, mesafe: mesafe };
      }
    }

    return enYakin;
  }

  // ── Önündeki platform kontrolü ──────────────────────────────────────────────
  function platformKontrol(karakter) {
    var state = BY.state;
    var platformlar = state.platformlar;
    if (!platformlar) return false;

    for (var i = 0; i < platformlar.length; i++) {
      var p = platformlar[i];
      // Karakterin biraz ilerisinde ve üstünde bir platform var mı?
      var ilerideMi = p.x > karakter.x && p.x < karakter.x + 120;
      var ustundeMi = p.y < karakter.y && p.y > karakter.y - 80;
      if (ilerideMi && ustundeMi) return true;
    }
    return false;
  }

  // ── Oyun bitişi kontrolü ────────────────────────────────────────────────────
  function oyunBitisKontrol() {
    var state = BY.state;
    if (state.takimCan <= 0) {
      // Takım yenildi - seviyeyi yeniden yükle
      state.takimCan = state.takimMaxCan;
      state.oyunDurumu = "oynuyor";
      bossOlusturuldu = false;
      takimDurumu = "ilerleme";

      // Kamerayı ve karakterleri sıfırla
      state.kameraX = 0;
      for (var i = 0; i < state.karakterler.length; i++) {
        state.karakterler[i].x = 60 + i * 40;
        state.karakterler[i].y = state.zeminY - 48;
      }

      // Seviyeyi yeniden yükle
      if (BY.seviye && BY.seviye.yukle) {
        BY.seviye.yukle(state.mevcutSeviye);
      }
    }
  }

  // ── Yavaş iyileşme ─────────────────────────────────────────────────────────
  function iyilesmeGuncelle() {
    var state = BY.state;
    if (takimDurumu === "ilerleme" && state.takimCan < state.takimMaxCan) {
      state.takimCan = Math.min(state.takimMaxCan, state.takimCan + TAKIM_IYILESME_HIZI);
    }
  }

  // ── Seviye tamamlama ────────────────────────────────────────────────────────
  function seviyeTamamla() {
    var state = BY.state;

    // Yıldız puanı hesapla
    var canYuzdesi = state.takimCan / state.takimMaxCan;
    var yildiz = canYuzdesi > 0.8 ? 3 : (canYuzdesi > 0.5 ? 2 : 1);

    // Bonus puan
    state.skor += SEVIYE_TAMAMLAMA_BONUSU * yildiz;

    // Zafer durumuna geç
    state.oyunDurumu = "zafer";
    zaferZamanlayici = performance.now();
    state._zaferYildiz = yildiz;

    // Zafer efektleri
    if (BY.efektler && BY.efektler.zaferEfektiOlustur) {
      BY.efektler.zaferEfektiOlustur();
    }
  }

  // ── Zafer sonrası geçiş ────────────────────────────────────────────────────
  function zaferSonrasiKontrol(zaman) {
    if (zaman - zaferZamanlayici > ZAFER_SURESI) {
      var state = BY.state;

      // Seviye geçişi başlat
      state.gecisAktif = true;
      state.gecisBaslangic = zaman;
      state.gecisIlerleme = 0;
      state._gecisYuklendi = false;
      state.oyunDurumu = "gecis";

      // İç durumu sıfırla
      bossOlusturuldu = false;
      takimDurumu = "ilerleme";
      sonSaldiriKaresi = 0;
    }
  }

  // ── Bekleme durumunda idle animasyon ────────────────────────────────────────
  function beklemeGuncelle() {
    var state = BY.state;
    var karakterler = state.karakterler;
    if (karakterler.length === 0) return;

    // Karakterler ekranın ortasında hafifçe hareket etsin
    var merkez = state.canvasGenislik * 0.4;
    for (var i = 0; i < karakterler.length; i++) {
      var k = karakterler[i];
      k.hedefX = merkez + i * 45 + Math.sin(performance.now() * 0.001 + i) * 20;
      k.animasyonDurumu = "idle";
    }
  }

  // ── Dış arayüz ─────────────────────────────────────────────────────────────
  BY.oyun = {
    baslat: function() {
      var state = BY.state;
      takimDurumu = "ilerleme";
      zaferZamanlayici = 0;
      bossOlusturuldu = false;
      sonSaldiriKaresi = 0;
      oyunBasladi = true;

      // Skor ve can sıfırlama (sadece ilk başlangıçta)
      if (state.skor === 0) {
        state.takimCan = state.takimMaxCan;
      }

      // İlk seviyeyi yükle
      if (BY.seviye && BY.seviye.yukle) {
        BY.seviye.yukle(state.mevcutSeviye);
      }

      // Karakterleri başlangıç pozisyonuna yerleştir
      state.kameraX = 0;
      for (var i = 0; i < state.karakterler.length; i++) {
        state.karakterler[i].x = 60 + i * 40;
      }
    },

    guncelle: function(zaman) {
      var state = BY.state;

      switch (state.oyunDurumu) {
        case "bekleme":
          beklemeGuncelle();
          break;

        case "oynuyor":
          takimIlerlemeGuncelle();
          mermiCarpismaKontrol();
          iyilesmeGuncelle();
          oyunBitisKontrol();
          cikisKontrol();
          break;

        case "boss":
          bossKontrol();
          mermiCarpismaKontrol();
          oyunBitisKontrol();
          break;

        case "zafer":
          zaferSonrasiKontrol(zaman);
          break;

        case "gecis":
          // Motor.guncelle tarafından yönetilir
          break;
      }
    },

    skoreEkle: function(miktar) {
      BY.state.skor += miktar;
    },

    seviyeTamamla: seviyeTamamla,

    getTakimDurumu: function() {
      return takimDurumu;
    }
  };

})();
