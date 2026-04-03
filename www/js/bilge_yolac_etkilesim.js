// www/js/bilge_yolac_etkilesim.js
// Etkileşim sistemi: fare hover tespiti, ikincil tıklama saldırısı ve
// birinci sınıf klavye desteği (Sol/Sağ/Yukarı/Aşağı/Boşluk).

(function() {
  "use strict";

  var BY = window.BilgeYolac;
  if (!BY) return;

  var fareHareketRef = null;
  var fareTiklaRef = null;
  var fareAyrilRef = null;
  var dokunmaBaslaRef = null;
  var klavyeBasRef = null;
  var klavyeBirakRef = null;

  function girisDurumuAl() {
    return BY.state.giris;
  }

  function fareHareketIsle(e) {
    var state = BY.state;
    var canvas = state.canvas;
    if (!canvas) return;

    var rect = canvas.getBoundingClientRect();
    state.fareX = e.clientX - rect.left;
    state.fareY = e.clientY - rect.top;
    state.fareUzerinde = true;

    if (state.oyunDurumu !== "oynuyor" && state.oyunDurumu !== "boss") return;

    var dunyaFareX = state.fareX + state.kameraX;
    var dunyaFareY = state.fareY;
    var karakterler = state.karakterler;

    for (var i = 0; i < karakterler.length; i++) {
      var k = karakterler[i];
      var mesafeX = Math.abs(dunyaFareX - (k.x + k.genislik / 2));
      var mesafeY = Math.abs(dunyaFareY - (k.y + k.yukseklik / 2));
      var hover = mesafeX < k.genislik * 0.8 && mesafeY < k.yukseklik * 0.8;

      if (hover && !k.hoverAktif) {
        k.hoverAktif = true;
        k.animasyonDurumu = "hover";
        hoverTepkisiVer(k);
      } else if (!hover && k.hoverAktif) {
        k.hoverAktif = false;
        if (k.animasyonDurumu === "hover") k.animasyonDurumu = "idle";
      }
    }
  }

  function hoverTepkisiVer(karakter) {
    if (karakter.hizY === 0) karakter.hizY = -3;

    if (BY.efektler && BY.efektler.parcacikOlustur) {
      BY.efektler.parcacikOlustur(
        karakter.x + karakter.genislik / 2,
        karakter.y + karakter.yukseklik / 2,
        karakter.renkler.ana,
        "kivilcim",
        5
      );
    }
  }

  function ikincilTakimSaldirisi(tiklaX, tiklaY) {
    var state = BY.state;
    var karakterler = state.karakterler;

    for (var i = 0; i < karakterler.length; i++) {
      var k = karakterler[i];
      if (BY.karakterler && BY.karakterler.yetenekCalistir) {
        BY.karakterler.yetenekCalistir(k);
      }
      if (k.hizY === 0) k.hizY = -2.5 - Math.random() * 1.5;
    }

    if (BY.efektler && BY.efektler.parcacikOlustur) {
      BY.efektler.parcacikOlustur(tiklaX, tiklaY, "#FFFFFF", "kivilcim", 8);
    }
  }

  function fareTiklaIsle(e) {
    var state = BY.state;
    if (!state.calisiyor) return;

    e.stopPropagation();
    e.preventDefault();

    var canvas = state.canvas;
    if (!canvas) return;

    if (state.oyunDurumu === "bekleme") {
      if (BY.oyun && typeof BY.oyun.oyunuBaslat === "function") {
        BY.oyun.oyunuBaslat();
      }

      if (BY.efektler && BY.efektler.parcacikOlustur) {
        var merkezX = state.canvasGenislik / 2 + state.kameraX;
        var merkezY = state.zeminY * 0.5;
        BY.efektler.parcacikOlustur(merkezX, merkezY, "#FFFFFF", "kivilcim", 15);
        BY.efektler.radarDarbesiEkle(merkezX, merkezY, "#FFD700");
      }
      return;
    }

    if (state.oyunDurumu === "oynuyor" || state.oyunDurumu === "boss") {
      var rect = canvas.getBoundingClientRect();
      var tiklaX = (e.clientX - rect.left) + state.kameraX;
      var tiklaY = e.clientY - rect.top;
      ikincilTakimSaldirisi(tiklaX, tiklaY);
    }
  }

  function fareAyrilIsle() {
    var state = BY.state;
    state.fareX = -1000;
    state.fareY = -1000;
    state.fareUzerinde = false;

    var karakterler = state.karakterler;
    for (var i = 0; i < karakterler.length; i++) {
      karakterler[i].hoverAktif = false;
      if (karakterler[i].animasyonDurumu === "hover") karakterler[i].animasyonDurumu = "idle";
    }
  }

  function dokunmaBaslaIsle(e) {
    if (e.touches && e.touches.length > 0) {
      var d = e.touches[0];
      fareTiklaIsle({
        clientX: d.clientX,
        clientY: d.clientY,
        stopPropagation: function() {},
        preventDefault: function() {}
      });
    }
  }

  function girisAlaniMi() {
    var aktifEleman = document.activeElement;
    if (!aktifEleman) return false;
    var etiket = (aktifEleman.tagName || "").toLowerCase();
    return etiket === "input" || etiket === "textarea" || etiket === "select" || aktifEleman.isContentEditable;
  }

  function klavyeBasIsle(e) {
    var state = BY.state;
    if (!state.calisiyor || girisAlaniMi()) return;

    var giris = girisDurumuAl();
    var code = e.code || e.key;

    if (code === "ArrowLeft" || e.key === "ArrowLeft") {
      e.preventDefault();
      giris.sol = true;
    } else if (code === "ArrowRight" || e.key === "ArrowRight") {
      e.preventDefault();
      giris.sag = true;
    } else if (code === "ArrowUp" || e.key === "ArrowUp") {
      e.preventDefault();
      if (!giris.yukari) giris.yukariTetik = true;
      giris.yukari = true;
    } else if (code === "ArrowDown" || e.key === "ArrowDown") {
      e.preventDefault();
      if (!giris.asagi) giris.asagiTetik = true;
      giris.asagi = true;
    } else if (code === "Space" || e.keyCode === 32) {
      e.preventDefault();
      if (!giris.bosluk) giris.boslukTetik = true;
      giris.bosluk = true;

      if (state.oyunDurumu === "bekleme" && BY.oyun && BY.oyun.oyunuBaslat) {
        BY.oyun.oyunuBaslat();
      }
    }
  }

  function klavyeBirakIsle(e) {
    var giris = girisDurumuAl();
    var code = e.code || e.key;

    if (code === "ArrowLeft" || e.key === "ArrowLeft") {
      giris.sol = false;
    } else if (code === "ArrowRight" || e.key === "ArrowRight") {
      giris.sag = false;
    } else if (code === "ArrowUp" || e.key === "ArrowUp") {
      giris.yukari = false;
    } else if (code === "ArrowDown" || e.key === "ArrowDown") {
      giris.asagi = false;
    } else if (code === "Space" || e.keyCode === 32) {
      giris.bosluk = false;
    }
  }

  BY.etkilesim = {
    baslat: function() {
      var canvas = BY.state.canvas;
      if (!canvas) return;

      this.temizle();

      fareHareketRef = fareHareketIsle;
      fareTiklaRef = fareTiklaIsle;
      fareAyrilRef = fareAyrilIsle;
      dokunmaBaslaRef = dokunmaBaslaIsle;
      klavyeBasRef = klavyeBasIsle;
      klavyeBirakRef = klavyeBirakIsle;

      canvas.addEventListener("mousemove", fareHareketRef);
      canvas.addEventListener("click", fareTiklaRef);
      canvas.addEventListener("mouseleave", fareAyrilRef);
      canvas.addEventListener("touchstart", dokunmaBaslaRef, { passive: true });

      document.addEventListener("keydown", klavyeBasRef);
      document.addEventListener("keyup", klavyeBirakRef);
    },

    guncelle: function() {
      // Sürekli giriş okuması oyun modülünde yapılır.
    },

    temizle: function() {
      var canvas = BY.state.canvas;

      if (canvas) {
        if (fareHareketRef) canvas.removeEventListener("mousemove", fareHareketRef);
        if (fareTiklaRef) canvas.removeEventListener("click", fareTiklaRef);
        if (fareAyrilRef) canvas.removeEventListener("mouseleave", fareAyrilRef);
        if (dokunmaBaslaRef) canvas.removeEventListener("touchstart", dokunmaBaslaRef);
      }

      if (klavyeBasRef) document.removeEventListener("keydown", klavyeBasRef);
      if (klavyeBirakRef) document.removeEventListener("keyup", klavyeBirakRef);

      fareHareketRef = null;
      fareTiklaRef = null;
      fareAyrilRef = null;
      dokunmaBaslaRef = null;
      klavyeBasRef = null;
      klavyeBirakRef = null;
    }
  };

})();