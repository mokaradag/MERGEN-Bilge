// www/js/bilge_yolac_etkilesim.js
// Etkileşim sistemi: tıklama ile oyun başlatma/yetenek tetikleme, fare hover tespiti, klavye desteği, dokunmatik destek

(function() {
  "use strict";

  var BY = window.BilgeYolac;
  if (!BY) return;

  // ── Olay dinleyicileri referansları (temizlik için) ──────────────────────
  var fareHareketRef = null;
  var fareTiklaRef = null;
  var fareAyrilRef = null;
  var dokunmaBaslaRef = null;
  var klavyeRef = null;

  // ════════════════════════════════════════════════════════════════════════
  //  FARE HAREKET İŞLEYİCİSİ
  // ════════════════════════════════════════════════════════════════════════

  function fareHareketIsle(e) {
    var state = BY.state;
    var canvas = state.canvas;
    if (!canvas) return;

    var rect = canvas.getBoundingClientRect();
    state.fareX = e.clientX - rect.left;
    state.fareY = e.clientY - rect.top;
    state.fareUzerinde = true;

    // Yalnızca oynuyor durumunda karakter hover kontrolü yap
    if (state.oyunDurumu !== "oynuyor" && state.oyunDurumu !== "boss") return;

    // Fare konumunu dünya koordinatına çevir
    var dunyaFareX = state.fareX + state.kameraX;
    var dunyaFareY = state.fareY;

    // Karakter hover kontrolü
    var karakterler = state.karakterler;
    for (var i = 0; i < karakterler.length; i++) {
      var k = karakterler[i];
      var mesafeX = Math.abs(dunyaFareX - (k.x + k.genislik / 2));
      var mesafeY = Math.abs(dunyaFareY - (k.y + k.yukseklik / 2));
      var hover = mesafeX < k.genislik * 0.8 && mesafeY < k.yukseklik * 0.8;

      if (hover && !k.hoverAktif) {
        // Hover başladı - karakter tepkisi
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

  // ════════════════════════════════════════════════════════════════════════
  //  KARAKTER HOVER TEPKİSİ
  // ════════════════════════════════════════════════════════════════════════

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

    // Karaktere özel hover davranışları
    switch (karakter.id) {
      case "mergen":
        // Hedef nişangâhı efekti
        if (BY.efektler && BY.efektler.radarDarbesiEkle) {
          BY.efektler.radarDarbesiEkle(
            karakter.x + karakter.genislik / 2,
            karakter.y + karakter.yukseklik * 0.3,
            karakter.renkler.ana
          );
        }
        break;

      case "ulgen":
        // Sakin enerji dalgası
        if (BY.efektler && BY.efektler.radarDarbesiEkle) {
          BY.efektler.radarDarbesiEkle(
            karakter.x + karakter.genislik / 2,
            karakter.y + karakter.yukseklik / 2,
            karakter.renkler.acik
          );
        }
        break;

      case "kayra":
        // Küre genişlemesi
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
        // Kalkan genişlemesi
        if (BY.efektler && BY.efektler.radarDarbesiEkle) {
          BY.efektler.radarDarbesiEkle(
            karakter.x + karakter.genislik / 2,
            karakter.y + karakter.yukseklik / 2,
            karakter.renkler.acik
          );
        }
        if (BY.efektler && BY.efektler.parcacikOlustur) {
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

  // ════════════════════════════════════════════════════════════════════════
  //  TIKLAMA İŞLEYİCİSİ
  // ════════════════════════════════════════════════════════════════════════

  function fareTiklaIsle(e) {
    var state = BY.state;
    if (!state.calisiyor) return;

    // Shiny müdahalesini engelle - donma hatasını düzelt
    e.stopPropagation();
    e.preventDefault();

    var canvas = state.canvas;
    if (!canvas) return;

    // ── Bekleme durumunda: oyunu başlat ──
    if (state.oyunDurumu === "bekleme") {
      // Oyun modülünü fiilen başlat (bekleme → oynuyor)
      if (BY.oyun && typeof BY.oyun.oyunuBaslat === "function") {
        BY.oyun.oyunuBaslat();
      }

      // Başlatma efekti
      if (BY.efektler && BY.efektler.parcacikOlustur) {
        var merkezX = state.canvasGenislik / 2 + state.kameraX;
        var merkezY = state.zeminY * 0.5;
        BY.efektler.parcacikOlustur(merkezX, merkezY, "#FFFFFF", "kivilcim", 15);
        BY.efektler.radarDarbesiEkle(merkezX, merkezY, "#FFD700");
      }
      return;
    }

    // ── Oynuyor/boss durumunda: takım yetenek patlaması ──
    if (state.oyunDurumu === "oynuyor" || state.oyunDurumu === "boss") {
      var karakterler = state.karakterler;

      // Tüm karakterlerin yeteneklerini aynı anda tetikle
      for (var i = 0; i < karakterler.length; i++) {
        var k = karakterler[i];
        if (BY.karakterler && BY.karakterler.yetenekCalistir) {
          BY.karakterler.yetenekCalistir(k);
        }
        // Hafif zıplama geri bildirimi
        if (k.hizY === 0) {
          k.hizY = -3 - Math.random() * 2;
        }
      }

      // Görsel geri bildirim: tıklama noktasında parçacık
      var rect = canvas.getBoundingClientRect();
      var tiklaX = (e.clientX - rect.left) + state.kameraX;
      var tiklaY = e.clientY - rect.top;

      if (BY.efektler && BY.efektler.parcacikOlustur) {
        BY.efektler.parcacikOlustur(tiklaX, tiklaY, "#FFFFFF", "kivilcim", 8);
      }
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  FARE AYRILMA İŞLEYİCİSİ
  // ════════════════════════════════════════════════════════════════════════

  function fareAyrilIsle() {
    var state = BY.state;
    state.fareX = -1000;
    state.fareY = -1000;
    state.fareUzerinde = false;

    // Tüm hover durumlarını sıfırla
    var karakterler = state.karakterler;
    for (var i = 0; i < karakterler.length; i++) {
      karakterler[i].hoverAktif = false;
      if (karakterler[i].animasyonDurumu === "hover") {
        karakterler[i].animasyonDurumu = "idle";
      }
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  DOKUNMATİK İŞLEYİCİSİ
  // ════════════════════════════════════════════════════════════════════════

  function dokunmaBaslaIsle(e) {
    if (e.touches && e.touches.length > 0) {
      var dokunma = e.touches[0];
      // Yapay bir olay nesnesi oluştur
      fareTiklaIsle({
        clientX: dokunma.clientX,
        clientY: dokunma.clientY,
        stopPropagation: function() {},
        preventDefault: function() {}
      });
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  KLAVYE İŞLEYİCİSİ
  // ════════════════════════════════════════════════════════════════════════

  function klavyeIsle(e) {
    var state = BY.state;
    if (!state.calisiyor) return;

    // Metin giriş alanına yazıyorsak oyun tuşlarını yakala
    var aktifEleman = document.activeElement;
    if (aktifEleman) {
      var etiket = aktifEleman.tagName.toLowerCase();
      if (etiket === "input" || etiket === "textarea" || etiket === "select" ||
          aktifEleman.isContentEditable) {
        return; // Giriş alanındaysa oyun etkileşimini devre dışı bırak
      }
    }

    // Boşluk tuşu: takım atılma hareketi
    if (e.code === "Space" || e.keyCode === 32) {
      e.preventDefault();

      // Oynuyor veya boss durumunda
      if (state.oyunDurumu === "oynuyor" || state.oyunDurumu === "boss") {
        var karakterler = state.karakterler;
        for (var i = 0; i < karakterler.length; i++) {
          var k = karakterler[i];
          // Hareket yönünde hız artışı
          var yon = k.yon || 1;
          k.hizX += yon * 4;
          // Hafif zıplama
          if (k.hizY === 0) {
            k.hizY = -3;
          }
        }

        // Atılma efekti
        if (BY.efektler && BY.efektler.parcacikOlustur && karakterler.length > 0) {
          var ilkKar = karakterler[0];
          BY.efektler.parcacikOlustur(
            ilkKar.x + ilkKar.genislik / 2,
            ilkKar.y + ilkKar.yukseklik / 2,
            "#FFFFFF",
            "kivilcim",
            6
          );
        }
      }

      // Bekleme durumunda boşluk ile de başlat
      if (state.oyunDurumu === "bekleme") {
        if (BY.oyun && typeof BY.oyun.oyunuBaslat === "function") {
          BY.oyun.oyunuBaslat();
        }
      }
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  DIŞ ARAYÜZ
  // ════════════════════════════════════════════════════════════════════════

  BY.etkilesim = {
    baslat: function() {
      var canvas = BY.state.canvas;
      if (!canvas) return;

      // Önceki dinleyicileri kaldır
      this.temizle();

      // Yeni dinleyici referanslarını oluştur
      fareHareketRef = fareHareketIsle;
      fareTiklaRef = fareTiklaIsle;
      fareAyrilRef = fareAyrilIsle;
      dokunmaBaslaRef = dokunmaBaslaIsle;
      klavyeRef = klavyeIsle;

      // Canvas olay dinleyicileri
      canvas.addEventListener("mousemove", fareHareketRef);
      canvas.addEventListener("click", fareTiklaRef);
      canvas.addEventListener("mouseleave", fareAyrilRef);
      canvas.addEventListener("touchstart", dokunmaBaslaRef, { passive: true });

      // Klavye dinleyicisi (document seviyesinde)
      document.addEventListener("keydown", klavyeRef);
    },

    temizle: function() {
      var canvas = BY.state.canvas;

      if (canvas) {
        if (fareHareketRef) canvas.removeEventListener("mousemove", fareHareketRef);
        if (fareTiklaRef) canvas.removeEventListener("click", fareTiklaRef);
        if (fareAyrilRef) canvas.removeEventListener("mouseleave", fareAyrilRef);
        if (dokunmaBaslaRef) canvas.removeEventListener("touchstart", dokunmaBaslaRef);
      }

      if (klavyeRef) document.removeEventListener("keydown", klavyeRef);

      fareHareketRef = null;
      fareTiklaRef = null;
      fareAyrilRef = null;
      dokunmaBaslaRef = null;
      klavyeRef = null;
    }
  };

})();