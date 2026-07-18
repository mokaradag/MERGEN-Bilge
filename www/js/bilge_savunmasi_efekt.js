// www/js/bilge_savunmasi_efekt.js
// Bilge Savunması efekt katmanı: havuzlanmış parçacıklar, yüzen metinler ve
// kısıtlı ekran sarsıntısı. Parçacık sayısı kalite seviyesine göre sınırlıdır
// ve azaltılmış hareket tercihinde tamamen kapanır. Efektler okunabilirliği
// artırmak içindir; oyunu örtmez.

(function() {
  "use strict";

  var BS = window.BilgeSavunmasi = window.BilgeSavunmasi || {};

  var parcaciklar = [];
  var metinler = [];
  var sarsinti = 0;

  BS.efekt = {

    temizle: function() {
      parcaciklar = [];
      metinler = [];
      sarsinti = 0;
    },

    // Sim fx kuyruğunu görsel efektlere çevirir (her karede çağrılır).
    kuyrukIsle: function(durum) {
      var kuyruk = durum.fxKuyrugu;
      if (!kuyruk.length) return [];
      var olaylar = kuyruk.splice(0, kuyruk.length);

      olaylar.forEach(function(olay) {
        if (olay.tip === "olum") {
          BS.efekt.patlama(olay.x, olay.y, olay.renk,
                           olay.patronMu ? 26 : 10);
          BS.efekt.metin(olay.x, olay.y, "+" + olay.kaynak, "#ffd166");
          if (olay.patronMu) sarsinti = Math.min(8, sarsinti + 6);
        } else if (olay.tip === "vurus") {
          BS.efekt.patlama(olay.x, olay.y, "#ffffff", 2);
        } else if (olay.tip === "sizinti") {
          sarsinti = Math.min(8, sarsinti + (olay.patronMu ? 5 : 2));
        } else if (olay.tip === "yerlestir" || olay.tip === "yukselt") {
          BS.efekt.patlama(olay.x, olay.y, "#7ae582", 12);
        } else if (olay.tip === "sat") {
          BS.efekt.metin(olay.x, olay.y, "+" + olay.iade, "#8ecae6");
        } else if (olay.tip === "yetenek") {
          BS.efekt.patlama(olay.x, olay.y, "#ffffff", 18);
        } else if (olay.tip === "onarim") {
          BS.efekt.metin(9, 1, "Onarım +" + olay.miktar, "#7ae582");
        } else if (olay.tip === "kaynak") {
          BS.efekt.metin(olay.x, olay.y, "+" + olay.miktar, "#ffd166");
        }
      });

      // Ekran düzeyi olaylar (dalga/patron/sonuç) HUD tarafından işlenir.
      return olaylar;
    },

    patlama: function(hx, hy, renk, adet) {
      var sinir = BS.kalite.parcacikSiniri();
      if (sinir <= 0) return;
      var eklenecek = Math.min(adet, Math.max(0, sinir - parcaciklar.length));
      for (var i = 0; i < eklenecek; i++) {
        var aci = Math.random() * Math.PI * 2;
        var hiz = 0.6 + Math.random() * 2.2;
        parcaciklar.push({
          x: hx, y: hy,
          vx: Math.cos(aci) * hiz,
          vy: Math.sin(aci) * hiz,
          omur: 0.5 + Math.random() * 0.4,
          kalan: 0.5 + Math.random() * 0.4,
          renk: renk || "#ffffff",
          boyut: 1.5 + Math.random() * 2.5
        });
      }
    },

    metin: function(hx, hy, yazi, renk) {
      if (BS.kalite.azaltilmisHareket && metinler.length > 6) return;
      if (metinler.length > 24) metinler.shift();
      metinler.push({
        x: hx, y: hy, yazi: yazi, renk: renk || "#fff",
        kalan: 1.1, omur: 1.1
      });
    },

    tik: function(dt) {
      for (var i = parcaciklar.length - 1; i >= 0; i--) {
        var p = parcaciklar[i];
        p.kalan -= dt;
        if (p.kalan <= 0) { parcaciklar.splice(i, 1); continue; }
        p.x += p.vx * dt;
        p.y += p.vy * dt;
        p.vx *= 0.92;
        p.vy *= 0.92;
      }
      for (var j = metinler.length - 1; j >= 0; j--) {
        var m = metinler[j];
        m.kalan -= dt;
        m.y -= dt * 0.7;
        if (m.kalan <= 0) metinler.splice(j, 1);
      }
      if (sarsinti > 0) sarsinti = Math.max(0, sarsinti - dt * 18);
    },

    ciz: function(ctx, cizici) {
      if (sarsinti > 0.2 && !BS.kalite.azaltilmisHareket) {
        ctx.save();
        ctx.translate((Math.random() - 0.5) * sarsinti,
                      (Math.random() - 0.5) * sarsinti);
      }

      parcaciklar.forEach(function(p) {
        ctx.globalAlpha = Math.max(0, p.kalan / p.omur);
        ctx.fillStyle = p.renk;
        ctx.fillRect(
          cizici.kenarX + (p.x + 0.5) * cizici.hucre - p.boyut / 2,
          cizici.kenarY + (p.y + 0.5) * cizici.hucre - p.boyut / 2,
          p.boyut, p.boyut
        );
      });
      ctx.globalAlpha = 1;

      metinler.forEach(function(m) {
        ctx.globalAlpha = Math.max(0, m.kalan / m.omur);
        ctx.fillStyle = m.renk;
        ctx.font = "600 " + Math.round(cizici.hucre * 0.34) + "px 'Segoe UI', sans-serif";
        ctx.textAlign = "center";
        ctx.fillText(m.yazi,
                     cizici.kenarX + (m.x + 0.5) * cizici.hucre,
                     cizici.kenarY + (m.y + 0.2) * cizici.hucre);
      });
      ctx.globalAlpha = 1;

      if (sarsinti > 0.2 && !BS.kalite.azaltilmisHareket) {
        ctx.restore();
      }
    }
  };
})();
