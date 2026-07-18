// www/js/bilge_savunmasi_cekirdek.js
// Bilge Savunması çekirdek katmanı: tek isim alanı (window.BilgeSavunmasi),
// deterministik tohumlu rastgele sayı üreteci, hafif olay yayıncısı, kalite
// durumu ve ortak saf yardımcılar. Bu dosya oyun döngüsü BAŞLATMAZ; yalnızca
// altyapı tanımlar. Diğer bilge_savunmasi_*.js dosyaları bundan sonra yüklenir.

(function() {
  "use strict";

  // Tek isim alanı: eski oyunun global kirliliği tekrarlanmaz.
  var BS = window.BilgeSavunmasi = window.BilgeSavunmasi || {};

  BS.SURUM = "1.0.0";   // R tarafındaki BS_OYUN_SURUMU ile aynı olmalı
  BS.SEMA = 1;          // R tarafındaki BS_SEMA_SURUMU ile aynı olmalı

  // ══════════════════════════════════════════════════════════════════════════
  //  DETERMİNİSTİK RASTGELE SAYI ÜRETECİ (mulberry32)
  //  Aynı tohum her zaman aynı diziyi üretir; haftalık meydan okuma ve plan
  //  denemeleri bu determinizme dayanır. Oyun simülasyonu Math.random KULLANMAZ.
  // ══════════════════════════════════════════════════════════════════════════
  BS.rng = {
    olustur: function(tohum) {
      var durum = (tohum >>> 0) || 1;

      function sonraki() {
        durum |= 0;
        durum = (durum + 0x6D2B79F5) | 0;
        var t = Math.imul(durum ^ (durum >>> 15), 1 | durum);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
      }

      return {
        sonraki: sonraki,
        aralik: function(min, max) {
          return min + (max - min) * sonraki();
        },
        tamsayi: function(min, max) {
          return Math.floor(min + (max - min + 1) * sonraki());
        },
        sec: function(dizi) {
          if (!dizi || !dizi.length) return null;
          return dizi[Math.floor(sonraki() * dizi.length)];
        }
      };
    },

    // Dizeden 31-bit deterministik tohum (istemci jetonları için değil,
    // yalnızca görsel çeşitleme için kullanılır).
    dizedenTohum: function(metin) {
      var h = 2166136261;
      metin = String(metin || "");
      for (var i = 0; i < metin.length; i++) {
        h = (h ^ metin.charCodeAt(i)) >>> 0;
        h = (h * 16777619) % 2147483647;
      }
      return Math.max(1, h | 0);
    }
  };

  // ══════════════════════════════════════════════════════════════════════════
  //  HAFİF OLAY YAYINCISI (oyun içi modüller arası gevşek bağ)
  // ══════════════════════════════════════════════════════════════════════════
  var dinleyiciler = {};

  BS.olaylar = {
    ekle: function(ad, islev) {
      if (!dinleyiciler[ad]) dinleyiciler[ad] = [];
      dinleyiciler[ad].push(islev);
      return islev;
    },
    cikar: function(ad, islev) {
      var liste = dinleyiciler[ad];
      if (!liste) return;
      var yer = liste.indexOf(islev);
      if (yer >= 0) liste.splice(yer, 1);
    },
    yay: function(ad, veri) {
      var liste = dinleyiciler[ad];
      if (!liste) return;
      // Kopya üzerinde döngü: dinleyici kendini çıkarabilir.
      liste.slice().forEach(function(islev) {
        try { islev(veri); } catch (hata) {
          if (window.console && console.warn) {
            console.warn("[BilgeSavunmasi] olay dinleyicisi hatası:", ad, hata);
          }
        }
      });
    },
    temizle: function() {
      dinleyiciler = {};
    }
  };

  // ══════════════════════════════════════════════════════════════════════════
  //  KALİTE VE ERİŞİLEBİLİRLİK DURUMU
  // ══════════════════════════════════════════════════════════════════════════
  BS.kalite = {
    seviye: "dengeli",            // yuksek | dengeli | performans
    efektYogunlugu: 1,            // 0..1 (erişilebilirlik ayarı)
    azaltilmisHareket: false,

    baslat: function() {
      try {
        var mq = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)");
        BS.kalite.azaltilmisHareket = !!(mq && mq.matches);
      } catch (hata) {
        BS.kalite.azaltilmisHareket = false;
      }
    },

    ayarla: function(seviye) {
      if (seviye === "yuksek" || seviye === "dengeli" || seviye === "performans") {
        BS.kalite.seviye = seviye;
        BS.olaylar.yay("kalite-degisti", seviye);
      }
    },

    parcacikSiniri: function() {
      if (BS.kalite.azaltilmisHareket) return 0;
      if (BS.kalite.seviye === "yuksek") return 220;
      if (BS.kalite.seviye === "performans") return 40;
      return 120;
    }
  };

  // ══════════════════════════════════════════════════════════════════════════
  //  ORTAK SAF YARDIMCILAR
  // ══════════════════════════════════════════════════════════════════════════
  BS.yardimci = {
    kirp: function(deger, min, max) {
      return Math.max(min, Math.min(max, deger));
    },

    dogrusal: function(a, b, t) {
      return a + (b - a) * t;
    },

    mesafe: function(x1, y1, x2, y2) {
      var dx = x2 - x1, dy = y2 - y1;
      return Math.sqrt(dx * dx + dy * dy);
    },

    // Dinamik metinler DOM'a girmeden önce daima bu süzgeçten geçer.
    htmlKacis: function(metin) {
      return String(metin == null ? "" : metin)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;");
    },

    sureBicimle: function(saniye) {
      var s = Math.max(0, Math.floor(saniye || 0));
      var dk = Math.floor(s / 60);
      var sn = s % 60;
      return dk + ":" + (sn < 10 ? "0" : "") + sn;
    },

    sayiBicimle: function(deger) {
      var s = Math.round(deger || 0);
      return s.toLocaleString("tr-TR");
    },

    // Güvenli benzersiz istemci jetonu (koşu idempotency anahtarı).
    jetonUret: function() {
      var bayt = new Uint8Array(16);
      if (window.crypto && window.crypto.getRandomValues) {
        window.crypto.getRandomValues(bayt);
      } else {
        for (var i = 0; i < bayt.length; i++) {
          bayt[i] = Math.floor(Math.random() * 256);
        }
      }
      var metin = "";
      for (var j = 0; j < bayt.length; j++) {
        metin += (bayt[j] + 256).toString(16).slice(1);
      }
      return "bs-" + metin;
    }
  };

  BS.kalite.baslat();
})();
