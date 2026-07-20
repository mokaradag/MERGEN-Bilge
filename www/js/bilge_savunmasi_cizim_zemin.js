// www/js/bilge_savunmasi_cizim_zemin.js
// Bilge Savunması statik zemin ressamı: zemin degradesi, nebula lekeleri,
// altıgen plaka dokusu, tanecik, yıldız alanı, devre izleri, ızgara noktaları,
// katmanlı veri yolları, giriş portalları, inşa edilemez hücre dokusu ve kenar
// vinyeti. Tek seferlik offscreen çizimdir (bilge_savunmasi_cizim.js her
// boyutlandırmada çağırır); kare başına maliyeti yoktur.

(function() {
  "use strict";

  var BS = window.BilgeSavunmasi = window.BilgeSavunmasi || {};

  BS.cizimZemin = {

    // c: offscreen 2d bağlamı; arka: offscreen canvas; cizici: ölçüler.
    ciz: function(c, arka, cizici, harita) {
      var izgara = BS.haritalar.IZGARA;
      var tema = harita.tema;
      var h = cizici.hucre;

      function hucreX(hx) { return cizici.kenarX + (hx + 0.5) * h; }
      function hucreY(hy) { return cizici.kenarY + (hy + 0.5) * h; }

      function yolCiz(yol) {
        c.beginPath();
        c.moveTo(hucreX(yol[0].x), hucreY(yol[0].y));
        for (var i = 1; i < yol.length; i++) {
          c.lineTo(hucreX(yol[i].x), hucreY(yol[i].y));
        }
        c.stroke();
      }

      var grd = c.createLinearGradient(0, 0, 0, arka.height);
      grd.addColorStop(0, tema.zemin1);
      grd.addColorStop(1, tema.zemin2);
      c.fillStyle = grd;
      c.fillRect(0, 0, arka.width, arka.height);

      var rng = BS.rng.olustur(BS.rng.dizedenTohum(harita.id));

      // Derinlik: seyrek nebula/veri bulutu lekeleri (tek seferlik maliyet).
      for (var n = 0; n < 5; n++) {
        var nx = rng.sonraki() * arka.width;
        var ny = rng.sonraki() * arka.height;
        var nr = (0.18 + rng.sonraki() * 0.22) * arka.width;
        var bulut = c.createRadialGradient(nx, ny, 0, nx, ny, nr);
        bulut.addColorStop(0, tema.vurgu + "10");
        bulut.addColorStop(1, "rgba(0,0,0,0)");
        c.fillStyle = bulut;
        c.fillRect(nx - nr, ny - nr, nr * 2, nr * 2);
      }

      // Altıgen plaka dokusu: zemine metalik panel hissi verir (tek seferlik).
      c.strokeStyle = "rgba(255,255,255,0.035)";
      c.lineWidth = 1;
      var plakaR = h * 1.35;
      var plakaH = plakaR * Math.sqrt(3) / 2;
      for (var phy = -1; phy * plakaH * 2 < arka.height + plakaR; phy++) {
        for (var phx = -1; phx * plakaR * 1.5 < arka.width + plakaR; phx++) {
          var pcx = phx * plakaR * 1.5;
          var pcy = phy * plakaH * 2 + (phx % 2 ? plakaH : 0);
          c.beginPath();
          for (var pv = 0; pv < 6; pv++) {
            var pa = Math.PI / 3 * pv;
            var pvx = pcx + Math.cos(pa) * plakaR * 0.92;
            var pvy = pcy + Math.sin(pa) * plakaR * 0.92;
            if (pv === 0) c.moveTo(pvx, pvy); else c.lineTo(pvx, pvy);
          }
          c.closePath();
          c.stroke();
        }
      }

      // İnce tanecik (grain): düz degrade yüzeyi kırar, doku derinliği katar.
      for (var gr = 0; gr < 240; gr++) {
        var grx = rng.sonraki() * arka.width;
        var gry = rng.sonraki() * arka.height;
        c.globalAlpha = 0.02 + rng.sonraki() * 0.04;
        c.fillStyle = rng.sonraki() > 0.5 ? "#ffffff" : "#000000";
        c.fillRect(grx, gry, 1.4, 1.4);
      }
      c.globalAlpha = 1;

      // Paralaks yıldız/veri noktaları (görsel tohum: harita kimliği).
      c.fillStyle = "rgba(255,255,255,0.16)";
      for (var i = 0; i < 110; i++) {
        var px = rng.sonraki() * arka.width;
        var py = rng.sonraki() * arka.height;
        var b = rng.sonraki() * 1.6 + 0.4;
        c.globalAlpha = 0.05 + rng.sonraki() * 0.2;
        c.fillRect(px, py, b, b);
      }
      c.globalAlpha = 1;

      // İnce devre izleri: inşa alanına teknoloji dokusu katar.
      c.strokeStyle = tema.izgara;
      c.lineWidth = 1;
      for (var d = 0; d < 14; d++) {
        var dx = Math.floor(rng.sonraki() * izgara.genislik);
        var dy = Math.floor(rng.sonraki() * izgara.yukseklik);
        var uz = 2 + Math.floor(rng.sonraki() * 4);
        var yatay = rng.sonraki() > 0.5;
        c.globalAlpha = 0.35;
        c.beginPath();
        c.moveTo(hucreX(dx), hucreY(dy));
        c.lineTo(hucreX(yatay ? dx + uz : dx), hucreY(yatay ? dy : dy + uz));
        c.stroke();
        c.globalAlpha = 0.5;
        c.beginPath();
        c.arc(hucreX(dx), hucreY(dy), 1.6, 0, Math.PI * 2);
        c.fill();
      }
      c.globalAlpha = 1;

      // Izgara: çizgi yerine hafif kesişim noktaları (daha sakin zemin).
      c.fillStyle = tema.izgara;
      for (var gx = 1; gx < izgara.genislik; gx++) {
        for (var gy = 1; gy < izgara.yukseklik; gy++) {
          c.globalAlpha = 0.5;
          c.fillRect(cizici.kenarX + gx * h - 1,
                     cizici.kenarY + gy * h - 1, 2, 2);
        }
      }
      c.globalAlpha = 1;

      // Rotalar: dış ışıma -> koyu taban -> yüzey dolgusu -> kenar ışığı ->
      // orta şerit + yön okları + köşe düğümleri (katmanlı veri yolu görünümü).
      harita.yollar.forEach(function(yol) {
        c.lineCap = "round";
        c.lineJoin = "round";

        c.strokeStyle = tema.vurgu + "22";
        c.lineWidth = h * 0.96;
        yolCiz(yol);
        c.strokeStyle = tema.yolKenar;
        c.lineWidth = h * 0.8;
        yolCiz(yol);
        c.strokeStyle = tema.yol;
        c.lineWidth = h * 0.62;
        yolCiz(yol);
        c.strokeStyle = "rgba(255,255,255,0.05)";
        c.lineWidth = h * 0.5;
        yolCiz(yol);

        // Kenar ışığı: üstten aydınlatılmış ince çizgiler.
        c.strokeStyle = tema.vurgu + "33";
        c.lineWidth = 1.5;
        c.setLineDash([h * 0.55, h * 0.2]);
        yolCiz(yol);
        c.setLineDash([]);

        // Orta şerit.
        c.strokeStyle = "rgba(255,255,255,0.09)";
        c.lineWidth = 2;
        c.setLineDash([h * 0.3, h * 0.35]);
        yolCiz(yol);
        c.setLineDash([]);

        // Segment yön okları (akış hissi; statik, ucuz).
        c.fillStyle = "rgba(255,255,255,0.14)";
        for (var s = 0; s < yol.length - 1; s++) {
          var ax = hucreX(yol[s].x), ay = hucreY(yol[s].y);
          var bx = hucreX(yol[s + 1].x), by = hucreY(yol[s + 1].y);
          var mx = (ax + bx) / 2, my = (ay + by) / 2;
          var aci = Math.atan2(by - ay, bx - ax);
          c.save();
          c.translate(mx, my);
          c.rotate(aci);
          c.beginPath();
          c.moveTo(h * 0.14, 0);
          c.lineTo(-h * 0.06, -h * 0.12);
          c.lineTo(-h * 0.06, h * 0.12);
          c.closePath();
          c.fill();
          c.restore();
        }

        // Köşe düğümleri: dönüşlerde devre bağlantı noktası.
        for (var k = 1; k < yol.length - 1; k++) {
          c.fillStyle = tema.yolKenar;
          c.beginPath();
          c.arc(hucreX(yol[k].x), hucreY(yol[k].y), h * 0.16, 0, Math.PI * 2);
          c.fill();
          c.strokeStyle = tema.vurgu + "55";
          c.lineWidth = 1.5;
          c.stroke();
        }

        // Giriş kapısı: ışıma halkalı portal + çift ok.
        var giris = yol[0];
        var gxp = hucreX(giris.x), gyp = hucreY(giris.y);
        var kapi = c.createRadialGradient(gxp, gyp, 0, gxp, gyp, h * 0.9);
        kapi.addColorStop(0, tema.vurgu + "44");
        kapi.addColorStop(1, "rgba(0,0,0,0)");
        c.fillStyle = kapi;
        c.fillRect(gxp - h, gyp - h, h * 2, h * 2);
        c.strokeStyle = tema.vurgu + "88";
        c.lineWidth = 2;
        c.beginPath();
        c.arc(gxp, gyp, h * 0.42, 0, Math.PI * 2);
        c.stroke();
        c.fillStyle = tema.vurgu;
        c.globalAlpha = 0.8;
        [0, 0.22].forEach(function(kayma) {
          c.beginPath();
          c.moveTo(gxp - h * (0.3 - kayma), gyp - h * 0.22);
          c.lineTo(gxp + h * (0.02 + kayma), gyp);
          c.lineTo(gxp - h * (0.3 - kayma), gyp + h * 0.22);
          c.closePath();
          c.fill();
        });
        c.globalAlpha = 1;
      });

      // İnşa edilemez hücreler: çapraz taramalı doku (yalnızca koyu leke değil).
      harita.insaEdilemez.forEach(function(hc) {
        var ix = cizici.kenarX + hc.x * h;
        var iy = cizici.kenarY + hc.y * h;
        c.fillStyle = "rgba(0,0,0,0.28)";
        c.fillRect(ix, iy, h, h);
        c.save();
        c.beginPath();
        c.rect(ix, iy, h, h);
        c.clip();
        c.strokeStyle = "rgba(255,255,255,0.05)";
        c.lineWidth = 1;
        for (var t = -1; t < 3; t++) {
          c.beginPath();
          c.moveTo(ix + t * (h / 2), iy);
          c.lineTo(ix + t * (h / 2) + h, iy + h);
          c.stroke();
        }
        c.restore();
      });

      // Kenar vinyeti: sahneyi çerçeveler, odağı rotaya toplar.
      var vin = c.createRadialGradient(
        arka.width / 2, arka.height / 2, arka.height * 0.35,
        arka.width / 2, arka.height / 2, arka.height * 0.85
      );
      vin.addColorStop(0, "rgba(0,0,0,0)");
      vin.addColorStop(1, "rgba(0,0,0,0.32)");
      c.fillStyle = vin;
      c.fillRect(0, 0, arka.width, arka.height);
    }
  };
})();
