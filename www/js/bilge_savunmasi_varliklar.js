// www/js/bilge_savunmasi_varliklar.js
// Bilge Savunması görsel varlık katmanı: yerel SVG/PNG sprite yükleyici
// (kuleler, dekor, isteğe bağlı düşman gövdeleri) ve kule/dekor çizim
// yardımcıları. TÜM varlıklar depo içindedir (assets/bilge_savunmasi/
// gorseller/); dosya yoksa her çizim zarif prosedürel yedeğe düşer, oyun
// hiçbir zaman kırık görsel göstermez. CDN/dış ağ bağımlılığı YOKTUR.

(function() {
  "use strict";

  var BS = window.BilgeSavunmasi = window.BilgeSavunmasi || {};

  var KOK = "assets/bilge_savunmasi/gorseller/";
  var resimler = {};   // görece yol -> { hazir: bool, yok: bool, resim: Image }

  function resimAl(gorece) {
    var kayit = resimler[gorece];
    if (kayit) return (kayit.hazir && !kayit.yok) ? kayit.resim : null;

    kayit = { hazir: false, yok: false, resim: new Image() };
    resimler[gorece] = kayit;
    kayit.resim.onload = function() { kayit.hazir = true; };
    kayit.resim.onerror = function() { kayit.yok = true; kayit.hazir = true; };
    kayit.resim.src = KOK + gorece;
    return null;
  }

  BS.varliklar = {

    kuleGorsel: function(tip, seviye) {
      return resimAl("kuleler/" + tip + "_" + (Math.min(seviye, 2) + 1) + ".svg");
    },

    dekorGorsel: function(ad) {
      return resimAl("dekor/" + ad + ".svg");
    },

    // Operatör dusmanlar/<id>.svg eklerse gövde sprite olarak kullanılır;
    // yoksa null döner ve mevcut prosedürel gövde çizimi devam eder.
    dusmanGorsel: function(id) {
      return resimAl("dusmanlar/" + id + ".svg");
    },

    // ── Kule gövdesi (2.5D: hücre tabanından yukarı uzanan yapı) ─────────────
    // secenekler: { secili: bool, aksan: renk }
    kuleCiz: function(ctx, cizici, kule, secenekler) {
      var h = cizici.hucre;
      var x = cizici.kenarX + (kule.x + 0.5) * h;
      var y = cizici.kenarY + (kule.y + 0.5) * h;
      var tanim = BS.denge.kuleAl(kule.tip);
      if (!tanim) return;

      // Zemin gölgesi: derinlik hissinin temeli.
      ctx.fillStyle = "rgba(0,0,0,0.35)";
      ctx.beginPath();
      ctx.ellipse(x, y + h * 0.3, h * 0.38, h * 0.14, 0, 0, Math.PI * 2);
      ctx.fill();

      var resim = BS.varliklar.kuleGorsel(kule.tip, kule.seviye);
      if (resim) {
        // Sprite: taban hücre merkezinde, gövde yukarı taşar (2.5D siluet).
        var gen = h * 1.06;
        var boy = h * 1.5;
        ctx.drawImage(resim, x - gen / 2, y + h * 0.34 - boy, gen, boy);
      } else {
        BS.varliklar._kuleYedekCiz(ctx, x, y, h, kule);
      }

      // Kademe noktaları (seviye rozetleri).
      for (var s = 0; s < kule.seviye; s++) {
        ctx.fillStyle = "#ffd166";
        ctx.beginPath();
        ctx.arc(x - 7 + s * 7, y + h * 0.42, 2.4, 0, Math.PI * 2);
        ctx.fill();
      }
    },

    // Prosedürel kule yedeği: tip başına ayırt edici siluet.
    _kuleYedekCiz: function(ctx, x, y, h, kule) {
      var renkler = {
        gozetleme:   { govde: "#3d5a80", vurgu: "#8ecae6" },
        veri_topu:   { govde: "#6c4f2c", vurgu: "#f4a261" },
        kripto_isik: { govde: "#4a3a75", vurgu: "#b088f9" }
      };
      var renk = renkler[kule.tip] || renkler.gozetleme;
      var tabanY = y + h * 0.3;

      // Taban platformu.
      ctx.fillStyle = "rgba(10, 14, 26, 0.9)";
      ctx.beginPath();
      ctx.ellipse(x, tabanY, h * 0.34, h * 0.15, 0, 0, Math.PI * 2);
      ctx.fill();

      // Gövde: yukarı daralan kütle.
      ctx.fillStyle = renk.govde;
      ctx.beginPath();
      ctx.moveTo(x - h * 0.26, tabanY);
      ctx.lineTo(x - h * 0.17, tabanY - h * 0.72);
      ctx.lineTo(x + h * 0.17, tabanY - h * 0.72);
      ctx.lineTo(x + h * 0.26, tabanY);
      ctx.closePath();
      ctx.fill();
      ctx.strokeStyle = "rgba(255,255,255,0.22)";
      ctx.lineWidth = 1.2;
      ctx.stroke();

      // Tepe: tipe özgü başlık.
      var tepeY = tabanY - h * 0.72;
      ctx.fillStyle = renk.vurgu;
      if (kule.tip === "veri_topu") {
        // Havan namlusu: kalın kısa fıçı.
        ctx.beginPath();
        ctx.ellipse(x, tepeY, h * 0.2, h * 0.13, 0, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillRect(x - h * 0.07, tepeY - h * 0.3, h * 0.14, h * 0.3);
      } else if (kule.tip === "kripto_isik") {
        // Kristal prizma.
        ctx.beginPath();
        ctx.moveTo(x, tepeY - h * 0.34);
        ctx.lineTo(x + h * 0.14, tepeY);
        ctx.lineTo(x, tepeY + h * 0.08);
        ctx.lineTo(x - h * 0.14, tepeY);
        ctx.closePath();
        ctx.fill();
      } else {
        // Gözetleme yuvası + anten.
        ctx.beginPath();
        ctx.arc(x, tepeY, h * 0.14, 0, Math.PI * 2);
        ctx.fill();
        ctx.strokeStyle = renk.vurgu;
        ctx.lineWidth = 1.6;
        ctx.beginPath();
        ctx.moveTo(x, tepeY - h * 0.12);
        ctx.lineTo(x, tepeY - h * 0.34);
        ctx.stroke();
      }

      // Seviye arttıkça gövdeye ışık bandı eklenir.
      for (var b = 0; b < kule.seviye; b++) {
        ctx.fillStyle = "rgba(255,255,255,0.3)";
        ctx.fillRect(x - h * 0.14, tabanY - h * (0.24 + b * 0.18),
                     h * 0.28, 2);
      }
    },

    // ── Dekor öğeleri (arka plan sahne süsleri; hücreleri işgal etmez) ───────
    // Deterministik yerleşim: harita kimliğinden tohumlanır; inşa edilemez
    // hücreler ve sahne kenar boşlukları kullanılır.
    dekorPlanla: function(harita) {
      var adaylar = ["kristal", "anten", "sunucu", "kaya", "veri_agaci", "bayrak"];
      var rng = BS.rng.olustur(BS.rng.dizedenTohum(harita.id + ":dekor"));
      var plan = [];
      (harita.insaEdilemez || []).forEach(function(hucre) {
        plan.push({
          x: hucre.x, y: hucre.y,
          ad: adaylar[Math.floor(rng.sonraki() * adaylar.length)],
          olcek: 0.8 + rng.sonraki() * 0.35
        });
      });
      return plan;
    },

    dekorCiz: function(ctx, cizici, plan) {
      var h = cizici.hucre;
      plan.forEach(function(oge) {
        var x = cizici.kenarX + (oge.x + 0.5) * h;
        var y = cizici.kenarY + (oge.y + 0.5) * h;
        var resim = BS.varliklar.dekorGorsel(oge.ad);

        ctx.fillStyle = "rgba(0,0,0,0.25)";
        ctx.beginPath();
        ctx.ellipse(x, y + h * 0.3, h * 0.3 * oge.olcek, h * 0.1, 0, 0, Math.PI * 2);
        ctx.fill();

        if (resim) {
          var gen = h * 0.9 * oge.olcek;
          var boy = h * 1.15 * oge.olcek;
          ctx.drawImage(resim, x - gen / 2, y + h * 0.32 - boy, gen, boy);
        } else {
          // Yedek: küçük kristal siluet.
          ctx.fillStyle = "rgba(140, 170, 220, 0.4)";
          ctx.beginPath();
          ctx.moveTo(x, y - h * 0.4 * oge.olcek);
          ctx.lineTo(x + h * 0.16 * oge.olcek, y + h * 0.1);
          ctx.lineTo(x, y + h * 0.24);
          ctx.lineTo(x - h * 0.16 * oge.olcek, y + h * 0.1);
          ctx.closePath();
          ctx.fill();
        }
      });
    }
  };
})();
