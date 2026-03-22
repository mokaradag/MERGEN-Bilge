// www/js/bilge_yolac_oyun.js
// Otomatik oyun sistemi: takım koordinasyonu AI, seviye ilerleme, ortak eylemler, zafer

(function() {
  "use strict";

  var BY = window.BilgeYolac;
  if (!BY) return;

  // Oyun durumu
  var takimDurumu = "ilerleme";  // ilerleme, duraklama, ortakEylem, zafer, bekleme
  var takimZamanlayici = 0;
  var eylemSayaci = 0;
  var sonYetenekZamani = 0;
  var sonTakimEylemiZamani = 0;
  var zaferGosterildi = false;
  var ilerlemeYonu = 1; // 1=sag, -1=sol

  // Takimin hedef konumu
  var takimHedefX = 0;

  // Eylem asamalari
  var ILERLEME_SURESI = 8000;   // 8 saniye ilerleme
  var DURAKLAMA_SURESI = 3000;  // 3 saniye duraklama
  var EYLEM_SURESI = 4000;      // 4 saniye ortak eylem
  var ZAFER_SURESI = 5000;      // 5 saniye zafer gosterimi

  // Takim ilerleme mantigi
  function takimIlerlemeGuncelle(zaman) {
    var state = BY.state;
    var karakterler = state.karakterler;
    if (karakterler.length === 0) return;

    var gecenSure = zaman - takimZamanlayici;

    switch (takimDurumu) {
      case "ilerleme":
        // Karakterleri birlikte ilerlet
        takimHedefX += ilerlemeYonu * 0.3;

        // Sinir kontrolu
        if (takimHedefX > state.canvasGenislik * 0.6) {
          ilerlemeYonu = -1;
        } else if (takimHedefX < state.canvasGenislik * 0.1) {
          ilerlemeYonu = 1;
        }

        // Her karaktere hedef ata
        for (var i = 0; i < karakterler.length; i++) {
          var aralik = state.canvasGenislik / 7;
          karakterler[i].hedefX = takimHedefX + aralik * (i + 0.5);
          karakterler[i].animasyonDurumu = "walk";
          karakterler[i].yon = ilerlemeYonu;
        }

        if (gecenSure > ILERLEME_SURESI) {
          takimDurumu = "duraklama";
          takimZamanlayici = zaman;
        }
        break;

      case "duraklama":
        // Karakterler duraksasin, idle durumuna gecsin
        for (var j = 0; j < karakterler.length; j++) {
          karakterler[j].animasyonDurumu = "idle";
        }

        if (gecenSure > DURAKLAMA_SURESI) {
          takimDurumu = "ortakEylem";
          takimZamanlayici = zaman;
          ortakEylemBaslat();
        }
        break;

      case "ortakEylem":
        // Ortak yetenek gosterimi
        if (gecenSure > EYLEM_SURESI) {
          eylemSayaci++;

          // Her 3 eylemde bir zafer ani
          if (eylemSayaci % 3 === 0 && !zaferGosterildi) {
            takimDurumu = "zafer";
            takimZamanlayici = zaman;
            zaferBaslat();
          } else {
            takimDurumu = "ilerleme";
            takimZamanlayici = zaman;
            zaferGosterildi = false;
          }
        }
        break;

      case "zafer":
        // Zafer animasyonu
        for (var v = 0; v < karakterler.length; v++) {
          karakterler[v].animasyonDurumu = "victory";
          // Zafer ziplama
          if (Math.random() > 0.97 && karakterler[v].hizY === 0) {
            karakterler[v].hizY = -4;
          }
        }

        if (gecenSure > ZAFER_SURESI) {
          takimDurumu = "ilerleme";
          takimZamanlayici = zaman;
          zaferGosterildi = true;

          // Karakterleri normale dondur
          for (var n = 0; n < karakterler.length; n++) {
            karakterler[n].animasyonDurumu = "idle";
            karakterler[n].zaferAktif = false;
          }
        }
        break;
    }
  }

  // Ortak eylem baslat
  function ortakEylemBaslat() {
    var state = BY.state;
    var karakterler = state.karakterler;

    // Sirayla yetenek kullan
    for (var i = 0; i < karakterler.length; i++) {
      (function(index) {
        setTimeout(function() {
          if (BY.karakterler && BY.karakterler.yetenekCalistir) {
            BY.karakterler.yetenekCalistir(karakterler[index]);
          }
        }, index * 500); // Her 500ms'de bir karakter
      })(i);
    }
  }

  // Zafer animasyonu baslat
  function zaferBaslat() {
    var state = BY.state;
    var karakterler = state.karakterler;

    // Tum karakterleri zafer durumuna al
    for (var i = 0; i < karakterler.length; i++) {
      karakterler[i].zaferAktif = true;
      karakterler[i].animasyonDurumu = "victory";
      if (karakterler[i].hizY === 0) {
        karakterler[i].hizY = -5 - Math.random() * 2;
      }
    }

    // Zafer efekti
    if (BY.efektler && BY.efektler.zaferEfektiOlustur) {
      BY.efektler.zaferEfektiOlustur();
    }
  }

  // Periyodik bireysel yetenek kullanimi
  function bireyselYetenekKontrol(zaman) {
    if (zaman - sonYetenekZamani < 6000) return; // Her 6 saniyede bir
    sonYetenekZamani = zaman;

    var state = BY.state;
    var karakterler = state.karakterler;
    if (karakterler.length === 0) return;

    // Rastgele bir karakter sec ve yetenek kullandir
    if (takimDurumu === "ilerleme") {
      var rastgeleIndex = Math.floor(Math.random() * karakterler.length);
      var karakter = karakterler[rastgeleIndex];

      if (!karakter.yetenekAktif && BY.karakterler && BY.karakterler.yetenekCalistir) {
        BY.karakterler.yetenekCalistir(karakter);
      }
    }
  }

  // Takim senkronizasyon efekti
  function takimSenkronKontrol(zaman) {
    if (zaman - sonTakimEylemiZamani < 15000) return; // Her 15 saniyede bir
    sonTakimEylemiZamani = zaman;

    var state = BY.state;
    var karakterler = state.karakterler;

    // Kisa senkronizasyon ani
    for (var i = 0; i < karakterler.length; i++) {
      karakterler[i].takimSenkron = true;

      // Senkron parcacik
      if (BY.efektler && BY.efektler.parcacikOlustur) {
        BY.efektler.parcacikOlustur(
          karakterler[i].x + karakterler[i].genislik / 2,
          karakterler[i].y + karakterler[i].yukseklik / 2,
          karakterler[i].renkler.acik,
          "daire",
          3
        );
      }

      // 1 saniye sonra senkronu kapat
      (function(k) {
        setTimeout(function() {
          k.takimSenkron = false;
        }, 1000);
      })(karakterler[i]);
    }

    // Senkron cizgisi efekti - karakterler arasi baglanti
    if (BY.efektler && BY.efektler.radarDarbesiEkle && karakterler.length > 0) {
      var merkezX = 0;
      var merkezY = 0;
      for (var j = 0; j < karakterler.length; j++) {
        merkezX += karakterler[j].x + karakterler[j].genislik / 2;
        merkezY += karakterler[j].y + karakterler[j].yukseklik / 2;
      }
      merkezX /= karakterler.length;
      merkezY /= karakterler.length;

      BY.efektler.radarDarbesiEkle(merkezX, merkezY, "#FFD700");
    }
  }

  // Dış arayüz
  BY.oyun = {
    baslat: function() {
      takimDurumu = "ilerleme";
      takimZamanlayici = performance.now();
      eylemSayaci = 0;
      sonYetenekZamani = performance.now();
      sonTakimEylemiZamani = performance.now();
      zaferGosterildi = false;
      ilerlemeYonu = 1;
      takimHedefX = BY.state.canvasGenislik * 0.2;
    },

    guncelle: function(zaman) {
      takimIlerlemeGuncelle(zaman);
      bireyselYetenekKontrol(zaman);
      takimSenkronKontrol(zaman);
    },

    getTakimDurumu: function() {
      return takimDurumu;
    }
  };

})();
