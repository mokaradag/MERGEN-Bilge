// www/js/bilge_yolac_etkilesim.js
// Etkileşim: fare hover tespiti (karakter başına tepki), tıkla başla, dokunmatik destek

(function() {
  "use strict";

  var BY = window.BilgeYolac;
  if (!BY) return;

  // Fare olay dinleyicileri referanslari (temizlik icin)
  var fareHareketRef = null;
  var fareTiklaRef = null;
  var fareAyrilRef = null;
  var dokunmaBaslaRef = null;

  // Fare hareket işleyicisi
  function fareHareketIsle(e) {
    var state = BY.state;
    var canvas = state.canvas;
    if (!canvas) return;

    var rect = canvas.getBoundingClientRect();
    state.fareX = (e.clientX - rect.left);
    state.fareY = (e.clientY - rect.top);
    state.fareUzerinde = true;

    // Karakter hover kontrolü
    var karakterler = state.karakterler;
    for (var i = 0; i < karakterler.length; i++) {
      var k = karakterler[i];
      var mesafeX = Math.abs(state.fareX - (k.x + k.genislik / 2));
      var mesafeY = Math.abs(state.fareY - (k.y + k.yukseklik / 2));
      var hover = mesafeX < k.genislik * 0.8 && mesafeY < k.yukseklik * 0.8;

      if (hover && !k.hoverAktif) {
        // Hover basladi - karakter tepkisi
        k.hoverAktif = true;
        k.animasyonDurumu = "hover";
        hoverTepkisiVer(k);
      } else if (!hover && k.hoverAktif) {
        // Hover bitti
        k.hoverAktif = false;
        if (k.animasyonDurumu === "hover") {
          k.animasyonDurumu = "idle";
        }
      }
    }
  }

  // Karakter bazinda hover tepkisi
  function hoverTepkisiVer(karakter) {
    // Hafif zıplama
    if (karakter.hizY === 0) {
      karakter.hizY = -3;
    }

    // Parçacık efekti
    if (BY.efektler && BY.efektler.parcacikOlustur) {
      BY.efektler.parcacikOlustur(
        karakter.x + karakter.genislik / 2,
        karakter.y + karakter.yukseklik / 2,
        karakter.renkler.ana,
        "kivilcim",
        5
      );
    }

    // Karaktere ozel hover davranislari
    switch (karakter.id) {
      case "mergen":
        // Hedef nisangahi efekti
        if (BY.efektler && BY.efektler.radarDarbesiEkle) {
          BY.efektler.radarDarbesiEkle(
            karakter.x + karakter.genislik / 2,
            karakter.y + karakter.yukseklik * 0.3,
            karakter.renkler.ana
          );
        }
        break;

      case "ulgen":
        // Sakin enerji dalgasi
        if (BY.efektler && BY.efektler.radarDarbesiEkle) {
          BY.efektler.radarDarbesiEkle(
            karakter.x + karakter.genislik / 2,
            karakter.y + karakter.yukseklik / 2,
            karakter.renkler.acik
          );
        }
        break;

      case "kayra":
        // Kure genislemesi
        if (BY.efektler && BY.efektler.parcacikOlustur) {
          BY.efektler.parcacikOlustur(
            karakter.x + karakter.genislik / 2,
            karakter.y + karakter.yukseklik / 2,
            karakter.renkler.ana,
            "daire",
            8
          );
        }
        break;

      case "erlik":
        // Glitch bozulma
        if (BY.efektler && BY.efektler.parcacikOlustur) {
          BY.efektler.parcacikOlustur(
            karakter.x + karakter.genislik / 2,
            karakter.y + karakter.yukseklik / 2,
            "#FF0000",
            "kivilcim",
            10
          );
        }
        break;

      case "umay_ana":
        // Kalkan genislemesi
        if (BY.efektler && BY.efektler.radarDarbesiEkle) {
          BY.efektler.radarDarbesiEkle(
            karakter.x + karakter.genislik / 2,
            karakter.y + karakter.yukseklik / 2,
            karakter.renkler.acik
          );
          BY.efektler.parcacikOlustur(
            karakter.x + karakter.genislik / 2,
            karakter.y + karakter.yukseklik / 2,
            karakter.renkler.ana,
            "daire",
            6
          );
        }
        break;
    }
  }

  // Tıklama işleyicisi
  function fareTiklaIsle(e) {
    var state = BY.state;
    if (!state.calisiyor) return;

    var canvas = state.canvas;
    if (!canvas) return;

    var rect = canvas.getBoundingClientRect();
    var tiklaX = e.clientX - rect.left;
    var tiklaY = e.clientY - rect.top;

    // Karakterlerin üzerine tıklandı mı kontrol et
    var karakterler = state.karakterler;
    var tiklandiMi = false;

    for (var i = 0; i < karakterler.length; i++) {
      var k = karakterler[i];
      var mesafeX = Math.abs(tiklaX - (k.x + k.genislik / 2));
      var mesafeY = Math.abs(tiklaY - (k.y + k.yukseklik / 2));

      if (mesafeX < k.genislik && mesafeY < k.yukseklik) {
        tiklandiMi = true;
        // Yetenek çalıştır
        if (BY.karakterler && BY.karakterler.yetenekCalistir) {
          BY.karakterler.yetenekCalistir(k);
        }
        // Zıplat
        if (k.hizY === 0) {
          k.hizY = -6;
        }
      }
    }

    // Hiçbir karaktere tıklanmadıysa, hepsini zıplat
    if (!tiklandiMi) {
      for (var j = 0; j < karakterler.length; j++) {
        var kar = karakterler[j];
        if (kar.hizY === 0) {
          kar.hizY = -4 - Math.random() * 2;
        }
      }

      // Tikla efekti
      if (BY.efektler && BY.efektler.parcacikOlustur) {
        BY.efektler.parcacikOlustur(tiklaX, tiklaY, "#FFFFFF", "kivilcim", 8);
      }
    }
  }

  // Fare ayrılma işleyicisi
  function fareAyrilIsle() {
    var state = BY.state;
    state.fareX = -1000;
    state.fareY = -1000;
    state.fareUzerinde = false;

    // Tum hover durumlarini sifirla
    var karakterler = state.karakterler;
    for (var i = 0; i < karakterler.length; i++) {
      karakterler[i].hoverAktif = false;
      if (karakterler[i].animasyonDurumu === "hover") {
        karakterler[i].animasyonDurumu = "idle";
      }
    }
  }

  // Dokunmatik başlangıç işleyicisi
  function dokunmaBaslaIsle(e) {
    if (e.touches && e.touches.length > 0) {
      var dokunma = e.touches[0];
      fareTiklaIsle({
        clientX: dokunma.clientX,
        clientY: dokunma.clientY
      });
    }
  }

  // Dış arayüz
  BY.etkilesim = {
    baslat: function() {
      var canvas = BY.state.canvas;
      if (!canvas) return;

      // Onceki dinleyicileri kaldir
      this.temizle();

      // Yeni dinleyicileri ekle
      fareHareketRef = fareHareketIsle;
      fareTiklaRef = fareTiklaIsle;
      fareAyrilRef = fareAyrilIsle;
      dokunmaBaslaRef = dokunmaBaslaIsle;

      canvas.addEventListener("mousemove", fareHareketRef);
      canvas.addEventListener("click", fareTiklaRef);
      canvas.addEventListener("mouseleave", fareAyrilRef);
      canvas.addEventListener("touchstart", dokunmaBaslaRef, { passive: true });
    },

    temizle: function() {
      var canvas = BY.state.canvas;
      if (!canvas) return;

      if (fareHareketRef) canvas.removeEventListener("mousemove", fareHareketRef);
      if (fareTiklaRef) canvas.removeEventListener("click", fareTiklaRef);
      if (fareAyrilRef) canvas.removeEventListener("mouseleave", fareAyrilRef);
      if (dokunmaBaslaRef) canvas.removeEventListener("touchstart", dokunmaBaslaRef);

      fareHareketRef = null;
      fareTiklaRef = null;
      fareAyrilRef = null;
      dokunmaBaslaRef = null;
    }
  };

})();
